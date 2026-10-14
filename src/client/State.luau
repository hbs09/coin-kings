--!strict
--[[
	State — o espelho local do estado que o servidor manda.

	E o unico modulo do cliente ligado ao Net para receber estado: os
	controladores registam-se aqui (onMatchState, onArmy, ...) em vez de abrirem
	as suas proprias ligacoes, para a ordem de atualizacao ser sempre a mesma.

	Nada aqui decide regras de jogo; sao dados para desenhar.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)

local State = {
	phase = "Lobby" :: Types.MatchPhase,
	round = 0,
	maxRounds = 1,
	endsAt = 0,
	duration = 0,
	team = nil :: Types.Team?,
	mode = "pvp" :: Types.MatchMode,
	chapterId = nil :: string?,
	-- Tropas a venda nesta partida (o capitulo limita a loja).
	troopPool = {} :: { Types.TroopId },
	-- Perfil e fila, para o lobby.
	profile = nil :: Types.ProfilePayload?,
	queued = false,
	waiting = 0,
	-- Deslocamento em X da arena desta partida (as posicoes chegam em
	-- coordenadas locais; somar isto para desenhar no mundo).
	arenaOffsetX = 0,
	selfReady = false,
	opponentReady = false,
	opponentName = nil :: string?,
	selfScore = 0,
	opponentScore = 0,

	gold = 0,
	maxUnits = 0,
	army = {} :: { Types.ArmyEntry },
}

type MatchStateFn = (payload: Types.MatchStatePayload) -> ()
type ArmyFn = (payload: Types.ArmyPayload) -> ()
type RosterFn = (payload: Types.RosterPayload) -> ()
type SnapshotFn = (payload: Types.SnapshotPayload) -> ()
type RoundResultFn = (payload: Types.RoundResultPayload) -> ()
type MatchResultFn = (payload: Types.MatchResultPayload) -> ()
type ProfileFn = (payload: Types.ProfilePayload) -> ()
type QueueFn = () -> ()
type AdminFn = (enabled: boolean) -> ()
type NoticeFn = (payload: Types.NoticePayload) -> ()

local matchStateFns: { MatchStateFn } = {}
local armyFns: { ArmyFn } = {}
local rosterFns: { RosterFn } = {}
local snapshotFns: { SnapshotFn } = {}
local roundResultFns: { RoundResultFn } = {}
local matchResultFns: { MatchResultFn } = {}
local profileFns: { ProfileFn } = {}
local queueFns: { QueueFn } = {}
local adminFns: { AdminFn } = {}
local noticeFns: { NoticeFn } = {}

function State.onMatchState(fn: MatchStateFn)
	table.insert(matchStateFns, fn)
end

function State.onArmy(fn: ArmyFn)
	table.insert(armyFns, fn)
end

function State.onRoster(fn: RosterFn)
	table.insert(rosterFns, fn)
end

function State.onSnapshot(fn: SnapshotFn)
	table.insert(snapshotFns, fn)
end

function State.onRoundResult(fn: RoundResultFn)
	table.insert(roundResultFns, fn)
end

function State.onMatchResult(fn: MatchResultFn)
	table.insert(matchResultFns, fn)
end

function State.onProfile(fn: ProfileFn)
	table.insert(profileFns, fn)
end

function State.onQueueState(fn: QueueFn)
	table.insert(queueFns, fn)
end

function State.onAdminState(fn: AdminFn)
	table.insert(adminFns, fn)
end

function State.onNotice(fn: NoticeFn)
	table.insert(noticeFns, fn)
end

-- Segundos que faltam na fase atual (relogio do servidor).
function State.timeLeft(): number
	return math.max(0, State.endsAt - workspace:GetServerTimeNow())
end

function State.canEditArmy(): boolean
	return State.phase == "Prep" and State.team ~= nil
end

function State.findUnit(unitId: number): Types.ArmyEntry?
	for _, entry in State.army do
		if entry.id == unitId then
			return entry
		end
	end
	return nil
end

function State.unitCount(): number
	return #State.army
end

function State.init()
	Net.onClientEvent("MatchState", function(raw: any)
		local payload = raw :: Types.MatchStatePayload
		State.phase = payload.phase
		State.round = payload.round
		State.maxRounds = payload.maxRounds
		State.endsAt = payload.endsAt
		State.duration = payload.duration
		State.team = payload.team
		State.arenaOffsetX = payload.arenaOffsetX
		State.mode = payload.mode
		State.chapterId = payload.chapterId
		State.troopPool = payload.troopPool
		State.selfReady = payload.selfReady
		State.opponentReady = payload.opponentReady
		State.opponentName = payload.opponentName
		State.selfScore = payload.selfScore
		State.opponentScore = payload.opponentScore
		for _, fn in matchStateFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("ArmyUpdate", function(raw: any)
		local payload = raw :: Types.ArmyPayload
		State.gold = payload.gold
		State.maxUnits = payload.maxUnits
		State.army = payload.units
		for _, fn in armyFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("Roster", function(raw: any)
		local payload = raw :: Types.RosterPayload
		for _, fn in rosterFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("Snapshot", function(raw: any)
		local payload = raw :: Types.SnapshotPayload
		for _, fn in snapshotFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("RoundResult", function(raw: any)
		local payload = raw :: Types.RoundResultPayload
		for _, fn in roundResultFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("MatchResult", function(raw: any)
		local payload = raw :: Types.MatchResultPayload
		for _, fn in matchResultFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("Profile", function(raw: any)
		local payload = raw :: Types.ProfilePayload
		State.profile = payload
		for _, fn in profileFns do
			fn(payload)
		end
	end)

	Net.onClientEvent("QueueState", function(raw: any)
		State.queued = raw.queued == true
		State.waiting = tonumber(raw.waiting) or 0
		for _, fn in queueFns do
			fn()
		end
	end)

	Net.onClientEvent("AdminState", function(raw: any)
		local isEnabled = raw.enabled == true
		for _, fn in adminFns do
			fn(isEnabled)
		end
	end)

	Net.onClientEvent("Notice", function(raw: any)
		local payload = raw :: Types.NoticePayload
		for _, fn in noticeFns do
			fn(payload)
		end
	end)
end

function State.start()
	-- O servidor pode ter mandado o estado antes de este cliente estar ligado.
	Net.fireServer("RequestState")
end

return State
