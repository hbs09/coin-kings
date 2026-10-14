--!strict
--[[
	MatchmakingService — a fila do PvP.

	**Ninguem e emparelhado sem pedir.** Quem esta no lobby a ver os trofeus e a
	arena so entra na fila se carregar em jogar online (remote SetQueued).

	Quem acaba uma partida continua na fila, de proposito: encadear partidas e
	a alavanca com mais efeito na retencao. Para parar, carrega em cancelar.

	Empareja por trofeus: a fila e ordenada e sai o par mais proximo. Quem
	passar de `Config/Match.queueBotAfter` a espera arranca um treino contra o
	bot — num 1v1, deixar alguem a olhar para uma fila vazia e a forma mais
	rapida de o perder. O treino nao mexe em trofeus nem no historico.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)

local AnalyticsService = require(script.Parent.AnalyticsService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local RankService = require(script.Parent.RankService)

local MatchmakingService = {}

local queue: { Player } = {}
local wantsQueue: { [Player]: boolean } = {}
-- Desde quando esta cada um a espera (para saber quando chamar o bot).
local waitingSince: { [Player]: number } = {}
local POLL_INTERVAL = 1

local function isEligible(player: Player): boolean
	return wantsQueue[player] == true
		and player.Parent ~= nil
		and not MatchService.isInMatch(player)
		and DataService.isReady(player)
end

local function sendQueueState(player: Player)
	Net.fireClient("QueueState", player, {
		queued = wantsQueue[player] == true,
		waiting = #queue,
	})
end

local function removeFromQueue(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
end

-- A fila e reconstruida a cada ciclo a partir de quem esta elegivel, por isso
-- recupera sozinha de qualquer caso estranho.
local function refreshQueue()
	for index = #queue, 1, -1 do
		local player = queue[index]
		if not isEligible(player) then
			table.remove(queue, index)
			waitingSince[player] = nil
		end
	end

	for _, player in Players:GetPlayers() do
		if isEligible(player) and not table.find(queue, player) then
			table.insert(queue, player)
			waitingSince[player] = os.clock()
		end
	end
end

function MatchmakingService.init()
	Net.onServerEvent("SetQueued", function(player: Player, queued: any)
		wantsQueue[player] = queued == true
		if not wantsQueue[player] then
			removeFromQueue(player)
			waitingSince[player] = nil
		end
		sendQueueState(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		wantsQueue[player] = nil
		waitingSince[player] = nil
		removeFromQueue(player)
		MatchService.handlePlayerLeaving(player)
	end)
end

function MatchmakingService.start()
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			refreshQueue()

			-- Ordenar por trofeus faz com que pares vizinhos na fila sejam
			-- tambem os mais parecidos: emparelha-se de cima a baixo.
			table.sort(queue, function(a: Player, b: Player): boolean
				return RankService.getTrophies(a) < RankService.getTrophies(b)
			end)

			-- Enche todas as arenas livres que a fila conseguir alimentar.
			while #queue >= 2 and MatchService.freeSlot() ~= nil do
				local playerA = table.remove(queue, 1)
				local playerB = table.remove(queue, 1)
				if not (playerA and playerB) then
					break
				end
				local waited = os.clock()
				for _, player in { playerA, playerB } do
					local since = waitingSince[player]
					if since then
						AnalyticsService.logQueueWait(player, waited - since, "pvp")
					end
					waitingSince[player] = nil
				end

				if not MatchService.beginMatch(playerA, playerB) then
					-- Nao arrancou: o refreshQueue do proximo ciclo repoe-os.
					break
				end
			end

			-- Quem espera demasiado joga contra o bot em vez de ficar a olhar
			-- para uma fila vazia. Como continua a querer PvP, volta a fila
			-- assim que a partida de treino acabar.
			local now = os.clock()
			for index = #queue, 1, -1 do
				local player = queue[index]
				local since = waitingSince[player]
				if since and now - since >= MatchConfig.queueBotAfter then
					if MatchService.beginTraining(player) then
						AnalyticsService.logQueueWait(player, now - since, "bot")
						table.remove(queue, index)
						waitingSince[player] = nil
					end
				end
			end

			-- Quem esta a espera quer saber quantos estao na fila.
			for _, player in Players:GetPlayers() do
				if wantsQueue[player] then
					sendQueueState(player)
				end
			end
		end
	end)
end

return MatchmakingService
