--!strict
--[[
	Bootstrap do servidor — o unico Script do servidor.
	Carrega os servicos pela ordem de dependencia: init() em todos, depois start().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

-- Nesta fase os jogadores nao tem corpo: o jogo e visto de uma camara fixa,
-- por isso nenhuma personagem pode entrar no campo de batalha.
Players.CharacterAutoLoads = false

-- Os remotes tem de existir antes de qualquer servico se ligar a eles.
Net.init()

local AnalyticsService = require(script.Parent.Services.AnalyticsService)
local DataService = require(script.Parent.Services.DataService)
local RankService = require(script.Parent.Services.RankService)
local LeaderboardService = require(script.Parent.Services.LeaderboardService)
local AdminService = require(script.Parent.Services.AdminService)
local BotService = require(script.Parent.Services.BotService)
local MapService = require(script.Parent.Services.MapService)
local EconomyService = require(script.Parent.Services.EconomyService)
local CombatService = require(script.Parent.Services.CombatService)
local MatchService = require(script.Parent.Services.MatchService)
local MatchmakingService = require(script.Parent.Services.MatchmakingService)

AnalyticsService.init()
DataService.init()
RankService.init()
LeaderboardService.init()
BotService.init()
MapService.init()
EconomyService.init()
CombatService.init()
MatchService.init()
MatchmakingService.init()
AdminService.init()

AnalyticsService.start()
DataService.start()
RankService.start()
LeaderboardService.start()
BotService.start()
MapService.start()
EconomyService.start()
CombatService.start()
MatchService.start()
MatchmakingService.start()
AdminService.start()

print("[CoinKings] servidor pronto")
