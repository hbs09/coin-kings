--!strict
--[[
	MatchmakingService — a fila do servidor.

	Fase 2: emparelha os primeiros dois da fila sempre que houver uma arena
	livre. A fila e reconstruida a cada ciclo a partir de quem esta no servidor
	(nao esta em partida, ja tem o perfil carregado e ainda nao esta na fila),
	por isso recupera sozinha de qualquer caso estranho: quem acaba uma partida
	volta a entrar, e quem entrou enquanto o perfil carregava nao fica de fora.

	Esperar pelo perfil antes de emparelhar e o que vai permitir, no MVP,
	emparelhar por Elo (±100, a alargar com a espera) e cair no BotService
	depois de 20 s de fila.
]]

local Players = game:GetService("Players")

local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)

local MatchmakingService = {}

local queue: { Player } = {}
local POLL_INTERVAL = 1

-- Tira da fila quem saiu ou ja esta a jogar, e acrescenta quem esta pronto.
local function refreshQueue()
	for index = #queue, 1, -1 do
		local player = queue[index]
		if not player.Parent or MatchService.isInMatch(player) then
			table.remove(queue, index)
		end
	end

	for _, player in Players:GetPlayers() do
		local eligible = not MatchService.isInMatch(player)
			and DataService.isReady(player)
			and not table.find(queue, player)
		if eligible then
			table.insert(queue, player)
		end
	end
end

function MatchmakingService.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		local index = table.find(queue, player)
		if index then
			table.remove(queue, index)
		end
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
		end
	end)
end

return MatchmakingService
