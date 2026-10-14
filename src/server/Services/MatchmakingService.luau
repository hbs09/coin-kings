--!strict
--[[
	MatchmakingService — a fila do servidor.

	Fase 1/2: emparelha os primeiros dois da fila sempre que houver uma arena
	livre. Quem acaba uma partida volta ao fim da fila (via MatchService
	.onMatchEnded), por isso com 2 jogadores joga-se seguido e com mais o par
	vai rodando.

	No MVP entra aqui o Elo (±100, a alargar com a espera) e o recurso ao
	BotService depois de 20 s de fila.
]]

local Players = game:GetService("Players")

local MatchService = require(script.Parent.MatchService)

local MatchmakingService = {}

local queue: { Player } = {}
local POLL_INTERVAL = 1

local function remove(player: Player)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
	end
end

local function enqueue(player: Player)
	-- Quem esta a jogar nao entra na fila.
	if MatchService.isInMatch(player) then
		return
	end
	if not table.find(queue, player) then
		table.insert(queue, player)
	end
end

-- Tira da fila quem ja saiu do servidor.
local function pruneQueue()
	for index = #queue, 1, -1 do
		local player = queue[index]
		if not player.Parent or MatchService.isInMatch(player) then
			table.remove(queue, index)
		end
	end
end

function MatchmakingService.init()
	Players.PlayerAdded:Connect(enqueue)
	Players.PlayerRemoving:Connect(function(player: Player)
		remove(player)
		MatchService.handlePlayerLeaving(player)
	end)

	-- Acabada a partida, os dois voltam a ficar disponiveis.
	MatchService.onMatchEnded(function(players: { Player })
		for _, player in players do
			if player.Parent then
				enqueue(player)
			end
		end
	end)

	for _, player in Players:GetPlayers() do
		enqueue(player)
	end
end

function MatchmakingService.start()
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)
			pruneQueue()

			-- Enche todas as arenas livres que a fila conseguir alimentar.
			while #queue >= 2 and MatchService.freeSlot() ~= nil do
				local playerA = table.remove(queue, 1)
				local playerB = table.remove(queue, 1)
				if not (playerA and playerB) then
					break
				end
				if not MatchService.beginMatch(playerA, playerB) then
					-- Nao arrancou (sem slot ou ja em jogo): nao perder a vez.
					enqueue(playerA)
					enqueue(playerB)
					break
				end
			end
		end
	end)
end

return MatchmakingService
