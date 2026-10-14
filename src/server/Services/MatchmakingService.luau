--!strict
--[[
	MatchmakingService — a fila do PvP.

	**Ninguem e emparelhado sem pedir.** Quem entra fica no lobby a escolher
	entre a campanha e o PvP; so entra na fila quem carregar em jogar online
	(remote SetQueued). Sem isto, um jogador a ler a lista de capitulos era
	atirado para uma partida a meio da leitura.

	Quem acaba uma partida continua na fila, de proposito: encadear partidas e
	a alavanca com mais efeito na retencao. Para parar, carrega em cancelar.

	No MVP entra aqui o Elo (±100, a alargar com a espera) e o recurso ao
	BotService depois de 20 s de fila.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

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
