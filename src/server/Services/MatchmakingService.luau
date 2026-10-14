--!strict
--[[
	MatchmakingService — fase 1: emparelha os dois primeiros jogadores do
	servidor assim que nao houver partida a decorrer.

	No MVP entra aqui o Elo (+-100, a alargar com a espera) e o recurso ao
	BotService depois de 20 s de fila. A interface publica (`enqueue`,
	`remove`) ja esta pensada para isso.
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
	if not table.find(queue, player) then
		table.insert(queue, player)
	end
end

function MatchmakingService.init()
	Players.PlayerAdded:Connect(enqueue)
	Players.PlayerRemoving:Connect(function(player: Player)
		remove(player)
		MatchService.handlePlayerLeaving(player)
	end)

	for _, player in Players:GetPlayers() do
		enqueue(player)
	end
end

function MatchmakingService.start()
	task.spawn(function()
		while true do
			task.wait(POLL_INTERVAL)

			-- Limpa quem saiu entretanto.
			for index = #queue, 1, -1 do
				local player = queue[index]
				if not player.Parent then
					table.remove(queue, index)
				end
			end

			if not MatchService.isActive() and #queue >= 2 then
				local playerA = table.remove(queue, 1)
				local playerB = table.remove(queue, 1)
				if playerA and playerB and playerA.Parent and playerB.Parent then
					MatchService.beginMatch(playerA, playerB)
					-- Voltam para o fim da fila: acabada a partida, jogam outra
					-- (e com 3+ jogadores no servidor, o proximo par roda).
					table.insert(queue, playerA)
					table.insert(queue, playerB)
				end
			end
		end
	end)
end

return MatchmakingService
