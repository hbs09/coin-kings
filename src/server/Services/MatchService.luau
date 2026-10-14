--!strict
--[[
	MatchService — a maquina de estados da partida e a autoridade sobre o
	exercito de cada jogador.

	Queue -> Prep -> Reveal -> Battle -> RoundEnd -> ... -> MatchEnd

	O servidor corre varias partidas ao mesmo tempo, uma por slot/arena
	(Config/Match.maxMatchesPerServer). Cada Match tem o seu estado, a sua
	Session de combate e a sua thread; nada e global.

	Coordenadas: tudo o que viaja entre cliente e servidor e **local a arena**.
	O deslocamento do slot vai no MatchState (arenaOffsetX) e o cliente soma-o
	so para desenhar. Assim as regras de Config/Maps valem para todas as arenas.

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

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CombatService = require(script.Parent.CombatService)

type Side = {
	player: Player,
	team: Types.Team,
	army: { Types.ArmyEntry },
	ready: boolean,
	lostLastRound: boolean,
}

type Match = {
	slot: number,
	offsetX: number,
	sides: { [Player]: Side },
	phase: Types.MatchPhase,
	phaseEndsAt: number,
	phaseDuration: number,
	round: number,
	scoreA: number,
	scoreB: number,
	abortRequested: boolean,
	session: CombatService.Session,
}

local MatchService = {}

local matches: { [number]: Match } = {} -- indexadas pelo slot
local matchByPlayer: { [Player]: Match } = {}
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

local function getSideByTeam(match: Match, team: Types.Team): Side?
	for _, side in match.sides do
		if side.team == team then
			return side
		end
	end
	return nil
end

local function getOpponent(match: Match, side: Side): Side?
	return getSideByTeam(match, if side.team == "A" then "B" else "A")
end

local function scoreOf(match: Match, team: Types.Team): number
	return if team == "A" then match.scoreA else match.scoreB
end

local function playersOf(match: Match): { Player }
	local list: { Player } = {}
	for _, side in match.sides do
		table.insert(list, side.player)
	end
	return list
end

local function sendArmy(player: Player)
	local match = matchByPlayer[player]
	local side = if match then match.sides[player] else nil
	local payload: Types.ArmyPayload = {
		gold = EconomyService.getGold(player),
		maxUnits = MatchConfig.maxUnitsPerPlayer,
		units = if side then side.army else {},
	}
	Net.fireClient("ArmyUpdate", player, payload)
end

-- Estado para quem nao esta em partida nenhuma.
local function sendLobbyState(player: Player)
	local payload: Types.MatchStatePayload = {
		phase = "Lobby",
		round = 0,
		maxRounds = MatchConfig.maxRounds,
		endsAt = now(),
		duration = 0,
		team = nil,
		arenaOffsetX = 0,
		selfReady = false,
		opponentReady = false,
		opponentName = nil,
		selfScore = 0,
		opponentScore = 0,
	}
	Net.fireClient("MatchState", player, payload)
end

local function broadcastState(match: Match)
	for _, side in match.sides do
		local opponent = getOpponent(match, side)
		local payload: Types.MatchStatePayload = {
			phase = match.phase,
			round = match.round,
			maxRounds = MatchConfig.maxRounds,
			endsAt = match.phaseEndsAt,
			duration = match.phaseDuration,
			team = side.team,
			arenaOffsetX = match.offsetX,
			selfReady = side.ready,
			opponentReady = if opponent then opponent.ready else false,
			opponentName = if opponent then opponent.player.Name else nil,
			selfScore = scoreOf(match, side.team),
			opponentScore = if opponent then scoreOf(match, opponent.team) else 0,
		}
		Net.fireClient("MatchState", side.player, payload)
	end
end

local function setPhase(match: Match, nextPhase: Types.MatchPhase, duration: number)
	match.phase = nextPhase
	match.phaseDuration = duration
	match.phaseEndsAt = now() + duration
	broadcastState(match)
end

local function bothReady(match: Match): boolean
	local count = 0
	for _, side in match.sides do
		if not side.ready then
			return false
		end
		count += 1
	end
	return count == 2
end

-- Espera o fim da fase. Na Prep, acaba mais cedo se os dois estiverem prontos.
local function waitPhaseEnd(match: Match)
	while now() < match.phaseEndsAt do
		if match.abortRequested then
			return
		end
		if match.phase == "Prep" and bothReady(match) then
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

local function editableSide(player: Player): (Match?, Side?)
	local match = matchByPlayer[player]
	if not match then
		notify(player, "wrong_phase")
		return nil, nil
	end

	local side = match.sides[player]
	if not side or match.phase ~= "Prep" then
		notify(player, "wrong_phase")
		return nil, nil
	end

	if side.ready then
		-- Mexer no exercito cancela o "pronto" em vez de ser recusado.
		side.ready = false
		broadcastState(match)
	end
	return match, side
end

local function handlePlace(player: Player, troopId: string, x: number, z: number)
	local match, side = editableSide(player)
	if not match or not side then
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
	local match, side = editableSide(player)
	if not match or not side then
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
	local match, side = editableSide(player)
	if not match or not side then
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
	local match = matchByPlayer[player]
	if not match or match.phase ~= "Prep" then
		return
	end

	local side = match.sides[player]
	if not side then
		return
	end

	if ready and #side.army == 0 then
		notify(player, "empty_army")
		return
	end

	side.ready = ready
	broadcastState(match)
end

-- Ciclo da partida ------------------------------------------------------------

local function collectSpawnEntries(match: Match): { Types.SpawnEntry }
	local entries: { Types.SpawnEntry } = {}
	for _, side in match.sides do
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

local function closeMatch(match: Match)
	CombatService.clear(match.session)

	local released = playersOf(match)
	for _, player in released do
		EconomyService.clear(player)
		matchByPlayer[player] = nil
		if player.Parent then
			sendLobbyState(player)
			sendArmy(player)
		end
	end

	matches[match.slot] = nil
	-- O matchmaking volta a por estes jogadores na fila no proximo ciclo.
end

local function startRound(match: Match, roundNumber: number)
	match.round = roundNumber
	for _, side in match.sides do
		side.army = {}
		side.ready = false
		local bonus = if side.lostLastRound then MatchConfig.loserBonus else 0
		EconomyService.setGold(side.player, MatchConfig.startingGold + bonus)
	end

	setPhase(match, "Prep", MatchConfig.prepDuration)
	for _, side in match.sides do
		sendArmy(side.player)
	end
	waitPhaseEnd(match)
end

local function runMatch(match: Match)
	for _, side in match.sides do
		side.lostLastRound = false
	end

	local roundNumber = 1
	while not match.abortRequested do
		startRound(match, roundNumber)
		if match.abortRequested then
			break
		end

		-- Reveal: os exercitos aparecem aos dois jogadores.
		setPhase(match, "Reveal", MatchConfig.revealDuration)
		CombatService.spawnRound(match.session, collectSpawnEntries(match))
		waitPhaseEnd(match)
		if match.abortRequested then
			break
		end

		-- Battle
		setPhase(match, "Battle", MatchConfig.battleDuration)
		local result = CombatService.runBattle(match.session, MatchConfig.battleDuration)
		if match.abortRequested or result.reason == "aborted" then
			break
		end

		if result.winner == "A" then
			match.scoreA += 1
		elseif result.winner == "B" then
			match.scoreB += 1
		end

		for _, side in match.sides do
			side.lostLastRound = result.winner ~= nil and result.winner ~= side.team
		end

		result.round = roundNumber
		result.scoreA = match.scoreA
		result.scoreB = match.scoreB
		for _, side in match.sides do
			Net.fireClient("RoundResult", side.player, result)
		end

		setPhase(match, "RoundEnd", MatchConfig.roundEndDuration)
		waitPhaseEnd(match)
		CombatService.clear(match.session)

		local decided = match.scoreA >= MatchConfig.roundsToWin or match.scoreB >= MatchConfig.roundsToWin
		if decided or roundNumber >= MatchConfig.maxRounds or match.abortRequested then
			break
		end
		roundNumber += 1
	end

	local winner: Types.Team? = nil
	if match.scoreA > match.scoreB then
		winner = "A"
	elseif match.scoreB > match.scoreA then
		winner = "B"
	end

	-- Historico do jogador. Uma partida abortada (adversario saiu) nao conta:
	-- sem Elo ainda nao ha nada a ganhar em premiar ou punir uma desistencia.
	if not match.abortRequested and winner then
		for _, side in match.sides do
			local won = side.team == winner
			DataService.update(side.player, function(profile: Types.Profile)
				if won then
					profile.wins += 1
				else
					profile.losses += 1
				end
			end)
		end
	end

	local payload: Types.MatchResultPayload = { winner = winner, scoreA = match.scoreA, scoreB = match.scoreB }
	for _, side in match.sides do
		Net.fireClient("MatchResult", side.player, payload)
	end

	setPhase(match, "MatchEnd", MatchConfig.matchEndDuration)
	waitPhaseEnd(match)
	closeMatch(match)
end

-- API -------------------------------------------------------------------------

function MatchService.activeCount(): number
	local count = 0
	for _ in matches do
		count += 1
	end
	return count
end

function MatchService.freeSlot(): number?
	for slot = 0, MatchConfig.maxMatchesPerServer - 1 do
		if not matches[slot] then
			return slot
		end
	end
	return nil
end

function MatchService.isInMatch(player: Player): boolean
	return matchByPlayer[player] ~= nil
end

function MatchService.beginMatch(playerA: Player, playerB: Player): boolean
	if matchByPlayer[playerA] or matchByPlayer[playerB] then
		return false
	end

	local slot = MatchService.freeSlot()
	if not slot then
		return false
	end

	local match: Match = {
		slot = slot,
		offsetX = Maps.arenaOffset(map, slot),
		sides = {},
		phase = "Lobby",
		phaseEndsAt = now(),
		phaseDuration = 0,
		round = 0,
		scoreA = 0,
		scoreB = 0,
		abortRequested = false,
		session = CombatService.createSession({ playerA, playerB }),
	}

	match.sides[playerA] = { player = playerA, team = "A", army = {}, ready = false, lostLastRound = false }
	match.sides[playerB] = { player = playerB, team = "B", army = {}, ready = false, lostLastRound = false }

	matches[slot] = match
	matchByPlayer[playerA] = match
	matchByPlayer[playerB] = match

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn(`MatchService: a partida no slot {slot} falhou: {err}`)
			closeMatch(match)
		end
	end)

	return true
end

function MatchService.handlePlayerLeaving(player: Player)
	local match = matchByPlayer[player]
	if not match then
		return
	end

	match.sides[player] = nil
	matchByPlayer[player] = nil
	EconomyService.clear(player)

	match.abortRequested = true
	CombatService.stop(match.session)
	-- Deixa de replicar para quem saiu.
	CombatService.setRecipients(match.session, playersOf(match))

	for _, side in match.sides do
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
		local match = matchByPlayer[player]
		if match then
			broadcastState(match)
		else
			sendLobbyState(player)
		end
		sendArmy(player)
	end)
end

function MatchService.start()
	Players.PlayerAdded:Connect(sendLobbyState)
	for _, player in Players:GetPlayers() do
		sendLobbyState(player)
	end
end

return MatchService
