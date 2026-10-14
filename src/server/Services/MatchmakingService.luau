--!strict
--[[
	MatchmakingService — a fila do PvP.

	**Ninguem e emparelhado sem pedir.** Quem esta no lobby a ver os trofeus e a
	arena so entra na fila se carregar em jogar online (remote SetQueued).

	Quem acaba uma partida continua na fila, de proposito: encadear partidas e
	a alavanca com mais efeito na retencao. Para parar, carrega em cancelar.

	Empareja por trofeus: a fila e ordenada e sai o par mais proximo. Com
	poucos jogadores isso quer dizer "quem estiver la", que e o melhor possivel
	e exatamente por isso que o adversario de treino do BotService (fila acima
	de 20 s) e a proxima peca importante.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local RankService = require(script.Parent.RankService)

local MatchmakingService = {}

local queue: { Player } = {}
local wantsQueue: { [Player]: boolean } = {}
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
		end
	end

	for _, player in Players:GetPlayers() do
		if isEligible(player) and not table.find(queue, player) then
			table.insert(queue, player)
		end
	end
end

function MatchmakingService.init()
	Net.onServerEvent("SetQueued", function(player: Player, queued: any)
		wantsQueue[player] = queued == true
		if not wantsQueue[player] then
			removeFromQueue(player)
		end
		sendQueueState(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		wantsQueue[player] = nil
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
				if not MatchService.beginMatch(playerA, playerB) then
					-- Nao arrancou: o refreshQueue do proximo ciclo repoe-os.
					break
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
