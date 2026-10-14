--!strict
--[[
	Config/Data — persistência: nomes, tempos, política de retry e o perfil
	por omissão de um jogador novo.

	O `schemaVersion` sobe sempre que a forma do perfil mudar. O DataService
	preenche automaticamente os campos que faltarem a um perfil antigo
	(reconcile), por isso acrescentar um campo novo aqui basta; só é preciso
	código de migração quando um campo muda de significado.
]]

local Types = require(script.Parent.Parent.Types)

local Data = {}

Data.schemaVersion = 1
Data.storeName = "PlayerProfiles"
Data.keyPrefix = "Player_"

-- Gravação
Data.autosaveInterval = 60 -- segundos
Data.retryAttempts = 4
Data.retryBackoff = 1.5 -- segundos, multiplicados pelo número da tentativa

-- Session lock: impede dois servidores de escreverem o mesmo perfil ao mesmo
-- tempo (o clássico "entrar em dois servidores e duplicar moedas").
-- O lock é renovado a cada autosave; outro servidor só o pode tomar depois de
-- `sessionLockStaleAfter` sem renovação, que é o que destranca um perfil
-- preso por um servidor que caiu.
Data.sessionLockStaleAfter = 120
Data.sessionLockRetries = 5
Data.sessionLockRetryDelay = 6

local defaultProfile: Types.Profile = {
	version = Data.schemaVersion,
	elo = 1000,
	wins = 0,
	losses = 0,
	season = 1,
	level = 1,
	xp = 0,
	coins = 0,
	unlockedTroops = {},
	cosmetics = {},
	equipped = {},
	dailyQuests = {},
	trophies = 0,
	tutorialDone = false,
	lastLogin = 0,
}

Data.defaultProfile = defaultProfile

return Data
