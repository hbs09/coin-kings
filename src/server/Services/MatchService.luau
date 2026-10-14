--!strict
--[[
	MatchService — a maquina de estados da partida e a autoridade sobre o
	exercito de cada jogador.

	Queue -> Prep -> Reveal -> Battle -> RoundEnd -> ... -> MatchEnd

	Regras importantes desta fase:
	- Durante a Prep cada jogador so recebe o SEU exercito (ArmyUpdate). O
	  exercito do adversario e revelado apenas na fase Reveal, pelo Roster.
	- Comprar, mover e vender e sempre validado aqui: fase, tropa disponivel,
	  limite de unidades, area da propria metade, espacamento e ouro.
	- O numero de rondas vem de Config/Match (fase 1 = 1 ronda).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local MatchConfig = require(Shared.Config.Match)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local EconomyService = require(script.Parent.EconomyService)
local CombatService = require(script.Parent.CombatService)

type Side = {
	player: Player,
	team: Types.Team,
	army: { Types.ArmyEntry },
	ready: boolean,
	lostLastRound: boolean,
}

local MatchService = {}

local sides: { [Player]: Side } = {}
local phase: Types.MatchPhase = "Lobby"
local phaseEndsAt = 0
local phaseDuration = 0
local round = 0
local scoreA = 0
local scoreB = 0
local active = false
local abortRequested = false
local nextUnitId = 0

local map = Maps.default

-- Utilitarios -----------------------------------------------------------------

local function now(): number
	return workspace:GetServerTimeNow()
end

local function notify(player: Player, key: string, arg: string?)
	local payload: Types.NoticePayload = { key = key, arg = arg }
	Net.fireClient("Notice", player, payload)
end

local function getSideByTeam(team: Types.Team): Side?
	for _, side in sides do
		if side.team == team then
			return side
		end
	end
	return nil
end

local function getOpponent(side: Side): Side?
	return getSideByTeam(if side.team == "A" then "B" else "A")
end

local function scoreOf(team: Types.Team): number
	return if team == "A" then scoreA else scoreB
end

local function sendArmy(player: Player)
	local side = sides[player]
	local payload: Types.ArmyPayload = {
		gold = EconomyService.getGold(player),
		maxUnits = MatchConfig.maxUnitsPerPlayer,
		units = if side then side.army else {},
	}
	Net.fireClient("ArmyUpdate", player, payload)
end

local function broadcastState()
	for _, player in Players:GetPlayers() do
		local side = sides[player]
		local opponent: Side? = if side then getOpponent(side) else nil

		local payload: Types.MatchStatePayload = {
			phase = phase,
			round = round,
			maxRounds = MatchConfig.maxRounds,
			endsAt = phaseEndsAt,
			duration = phaseDuration,
			team = if side then side.team else nil,
			selfReady = if side then side.ready else false,
			opponentReady = if opponent then opponent.ready else false,
			opponentName = if opponent then opponent.player.Name else nil,
			selfScore = if side then scoreOf(side.team) else 0,
			opponentScore = if opponent then scoreOf(opponent.team) else 0,
		}
		Net.fireClient("MatchState", player, payload)
	end
end

local function setPhase(nextPhase: Types.MatchPhase, duration: number)
	phase = nextPhase
	phaseDuration = duration
	phaseEndsAt = now() + duration
	broadcastState()
end

local function bothReady(): boolean
	local count = 0
	for _, side in sides do
		if not side.ready then
			return false
		end
		count += 1
	end
	return count == 2
end

-- Espera o fim da fase. Na Prep, acaba mais cedo se os dois estiverem prontos.
local function waitPhaseEnd()
	while now() < phaseEndsAt do
		if abortRequested then
			return
		end
		if phase == "Prep" and bothReady() then
			return
		end
		task.wait(0.1)
	end
end

-- Validacao da colocacao ------------------------------------------------------

local function findEntry(side: Side, unitId: number): (number?, Types.ArmyEntry?)
	for index, entry in side.army do
		if entry.id == unitId then
			return index, entry
		end
	end
	return nil, nil
end

local function editableSide(player: Player): Side?
	local side = sides[player]
	if not side then
		notify(player, "wrong_phase")
		return nil
	end
	if phase ~= "Prep" then
		notify(player, "wrong_phase")
		return nil
	end
	if side.ready then
		-- Mexer no exercito cancela o "pronto" em vez de ser recusado.
		side.ready = false
		broadcastState()
	end
	return side
end

local function handlePlace(player: Player, troopId: string, x: number, z: number)
	local side = editableSide(player)
	if not side then
		return
	end

	if not MatchConfig.isTroopAvailable(troopId) then
		notify(player, "troop_locked")
		return
	end

	local def = Troops.get(troopId)
	if not def then
		notify(player, "troop_locked")
		return
	end

	if #side.army >= MatchConfig.maxUnitsPerPlayer then
		notify(player, "unit_limit", tostring(MatchConfig.maxUnitsPerPlayer))
		return
	end

	if not Maps.canPlace(map, side.team, x, z, def.radius) then
		notify(player, "invalid_placement")
		return
	end

	if not Placement.spacingOk(side.army, x, z, def, nil) then
		notify(player, "too_close")
		return
	end

	if not EconomyService.trySpend(player, def.cost) then
		notify(player, "not_enough_gold")
		return
	end

	nextUnitId += 1
	table.insert(side.army, { id = nextUnitId, troopId = troopId, x = x, z = z })
	sendArmy(player)
end

local function handleMove(player: Player, unitId: number, x: number, z: number)
	local side = editableSide(player)
	if not side then
		return
	end

	local _, entry = findEntry(side, unitId)
	if not entry then
		return
	end

	local def = Troops.get(entry.troopId)
	if not def then
		return
	end

	if not Maps.canPlace(map, side.team, x, z, def.radius) then
		notify(player, "invalid_placement")
		return
	end

	if not Placement.spacingOk(side.army, x, z, def, unitId) then
		notify(player, "too_close")
		return
	end

	entry.x = x
	entry.z = z
	sendArmy(player)
end

local function handleSell(player: Player, unitId: number)
	local side = editableSide(player)
	if not side then
		return
	end

	local index, entry = findEntry(side, unitId)
	if not index or not entry then
		return
	end

	local def = Troops.get(entry.troopId)
	table.remove(side.army, index)
	if def then
		-- Na preparacao o reembolso e total: posicionar e decidir, nao apostar.
		EconomyService.refund(player, def.cost)
	end
	sendArmy(player)
end

local function handleReady(player: Player, ready: boolean)
	local side = sides[player]
	if not side or phase ~= "Prep" then
		return
	end
	if ready and #side.army == 0 then
		notify(player, "empty_army")
		return
	end
	side.ready = ready
	broadcastState()
end

-- Ciclo da partida ------------------------------------------------------------

local function collectSpawnEntries(): { Types.SpawnEntry }
	local entries: { Types.SpawnEntry } = {}
	for _, side in sides do
		for _, unit in side.army do
			local def = Troops.get(unit.troopId)
			if def then
				table.insert(entries, {
					id = unit.id,
					troopId = unit.troopId,
					team = side.team,
					maxHp = def.hp,
					x = unit.x,
					z = unit.z,
				})
			end
		end
	end
	return entries
end

local function resetToLobby()
	CombatService.clear()
	for _, side in sides do
		EconomyService.clear(side.player)
	end
	sides = {}
	active = false
	round = 0
	scoreA = 0
	scoreB = 0
	setPhase("Lobby", MatchConfig.lobbyCountdown)
end

local function startRound(roundNumber: number)
	round = roundNumber
	for _, side in sides do
		side.army = {}
		side.ready = false
		local bonus = if side.lostLastRound then MatchConfig.loserBonus else 0
		EconomyService.setGold(side.player, MatchConfig.startingGold + bonus)
	end

	setPhase("Prep", MatchConfig.prepDuration)
	for _, side in sides do
		sendArmy(side.player)
	end
	waitPhaseEnd()
end

local function runMatch()
	active = true
	abortRequested = false
	round = 0
	scoreA = 0
	scoreB = 0

	for _, side in sides do
		side.lostLastRound = false
	end

	local roundNumber = 1
	while not abortRequested do
		startRound(roundNumber)
		if abortRequested then
			break
		end

		-- Reveal: os exercitos aparecem aos dois jogadores.
		setPhase("Reveal", MatchConfig.revealDuration)
		CombatService.spawnRound(collectSpawnEntries())
		waitPhaseEnd()
		if abortRequested then
			break
		end

		-- Battle
		setPhase("Battle", MatchConfig.battleDuration)
		local result = CombatService.runBattle(MatchConfig.battleDuration)
		if abortRequested or result.reason == "aborted" then
			break
		end

		if result.winner == "A" then
			scoreA += 1
		elseif result.winner == "B" then
			scoreB += 1
		end

		for _, side in sides do
			side.lostLastRound = result.winner ~= nil and result.winner ~= side.team
		end

		result.round = roundNumber
		result.scoreA = scoreA
		result.scoreB = scoreB
		Net.fireAllClients("RoundResult", result)

		setPhase("RoundEnd", MatchConfig.roundEndDuration)
		waitPhaseEnd()
		CombatService.clear()

		local decided = scoreA >= MatchConfig.roundsToWin or scoreB >= MatchConfig.roundsToWin
		if decided or roundNumber >= MatchConfig.maxRounds or abortRequested then
			break
		end
		roundNumber += 1
	end

	local winner: Types.Team? = nil
	if scoreA > scoreB then
		winner = "A"
	elseif scoreB > scoreA then
		winner = "B"
	end

	local payload: Types.MatchResultPayload = { winner = winner, scoreA = scoreA, scoreB = scoreB }
	Net.fireAllClients("MatchResult", payload)

	setPhase("MatchEnd", MatchConfig.matchEndDuration)
	waitPhaseEnd()
	resetToLobby()
end

-- API -------------------------------------------------------------------------

function MatchService.isActive(): boolean
	return active
end

function MatchService.beginMatch(playerA: Player, playerB: Player)
	if active then
		return
	end

	sides = {}
	sides[playerA] = { player = playerA, team = "A", army = {}, ready = false, lostLastRound = false }
	sides[playerB] = { player = playerB, team = "B", army = {}, ready = false, lostLastRound = false }

	task.spawn(function()
		local ok, err = pcall(runMatch)
		if not ok then
			warn(`MatchService: a partida falhou: {err}`)
			resetToLobby()
		end
	end)
end

function MatchService.handlePlayerLeaving(player: Player)
	if not sides[player] then
		return
	end

	sides[player] = nil
	if not active then
		return
	end

	abortRequested = true
	CombatService.stop()
	for _, side in sides do
		notify(side.player, "opponent_left")
	end
end

function MatchService.init()
	Net.onServerEvent("PlaceUnit", function(player: Player, troopId: any, x: any, z: any)
		handlePlace(player, troopId :: string, x :: number, z :: number)
	end)

	Net.onServerEvent("MoveUnit", function(player: Player, unitId: any, x: any, z: any)
		handleMove(player, unitId :: number, x :: number, z :: number)
	end)

	Net.onServerEvent("SellUnit", function(player: Player, unitId: any)
		handleSell(player, unitId :: number)
	end)

	Net.onServerEvent("SetReady", function(player: Player, ready: any)
		handleReady(player, ready :: boolean)
	end)

	Net.onServerEvent("RequestState", function(player: Player)
		broadcastState()
		sendArmy(player)
	end)
end

function MatchService.start()
	setPhase("Lobby", MatchConfig.lobbyCountdown)

	-- Quem entra a meio de uma partida recebe o estado atual (como espectador).
	Players.PlayerAdded:Connect(function()
		broadcastState()
	end)
end

return MatchService
