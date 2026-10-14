--!strict
--[[
	AdminService — os atalhos da fase de testes.

	Velocidade da simulação, saltar fase, ouro, troféus e repor o perfil. Serve
	para testar em minutos o que de outra forma levava horas a jogar.

	**Quem pode é decidido aqui, no servidor**, a partir de Config/Admin. O
	cliente só desenha o painel depois de o servidor lhe dizer que ele existe,
	e cada comando é verificado outra vez à chegada. Esconder o botão não é
	segurança: sem esta verificação, qualquer jogador podia mandar o mesmo
	remote e dar-se troféus.

	Por omissão isto só funciona no Studio.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local AdminConfig = require(Shared.Config.Admin)

local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local RankService = require(script.Parent.RankService)

local AdminService = {}

local function isAdmin(player: Player): boolean
	if AdminConfig.allowStudio and RunService:IsStudio() then
		return true
	end
	return table.find(AdminConfig.userIds, player.UserId) ~= nil
end

local function announce(player: Player)
	Net.fireClient("AdminState", player, { enabled = isAdmin(player) })
end

local function handle(player: Player, command: string, value: number?)
	if not isAdmin(player) then
		warn(`AdminService: {player.Name} tentou "{command}" sem permissao.`)
		return
	end

	if command == "speed" then
		CombatService.setSpeed(value or 1)
	elseif command == "skipPhase" then
		MatchService.adminSkipPhase(player)
	elseif command == "gold" then
		MatchService.adminGrantGold(player, AdminConfig.goldGrant)
	elseif command == "trophies" then
		RankService.adminAddTrophies(player, value or AdminConfig.trophyGrant)
		MatchService.adminRefresh(player)
	elseif command == "resetProfile" then
		if DataService.resetProfile(player) then
			-- Um perfil reposto é um jogador novo: volta a ter as tropas da
			-- arena inicial e o tutorial por fazer.
			RankService.ensureUnlocks(player)
			MatchService.adminRefresh(player)
		end
	else
		warn(`AdminService: comando desconhecido "{command}"`)
	end
end

function AdminService.init()
	Net.onServerEvent("AdminCommand", function(player: Player, command: any, value: any)
		handle(player, command :: string, value :: number?)
	end)

	Players.PlayerAdded:Connect(announce)
end

function AdminService.start()
	for _, player in Players:GetPlayers() do
		announce(player)
	end
end

return AdminService
