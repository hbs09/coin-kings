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

local DataService = require(script.Parent.Services.DataService)
local MapService = require(script.Parent.Services.MapService)
local EconomyService = require(script.Parent.Services.EconomyService)
local CombatService = require(script.Parent.Services.CombatService)
local MatchService = require(script.Parent.Services.MatchService)
local MatchmakingService = require(script.Parent.Services.MatchmakingService)

DataService.init()
MapService.init()
EconomyService.init()
CombatService.init()
MatchService.init()
MatchmakingService.init()

DataService.start()
MapService.start()
EconomyService.start()
CombatService.start()
MatchService.start()
MatchmakingService.start()

print("[CoinKings] servidor pronto")
