--!strict
--[[
	MatchService — a maquina de estados da partida e a autoridade sobre o
	exercito de cada jogador.

	Queue -> Prep -> Reveal -> Battle -> RoundEnd -> ... -> MatchEnd

	Serve os dois modos, porque a unica diferenca entre eles e **quem esta do
	outro lado**:
	- "pvp": dois jogadores, melhor de 3, orcamento de Config/Match.
	- "tutorial": a primeira partida de quem chega, contra um bot fraco de
	  Config/Tutorial, uma ronda, so com as tropas da Arena 1.
	- "training": o mesmo formato do PvP, mas contra o bot, quando a fila
	  demora demasiado. Nao mexe em trofeus nem no historico.
	- "sandbox": so para admins. Contra o bot, uma ronda, com todas as tropas
	  e ouro a vontade, para experimentar o que for novo.

	Um `Side` pode nao ter `player` (e o bot): e isso que permite partilhar
	todo o ciclo. Os lados sao indexados pela equipa, nao pelo jogador.

	O servidor corre varias partidas ao mesmo tempo, uma por slot/arena
	(Config/Match.maxMatchesPerServer). Cada Match tem o seu estado, a sua
	Session de combate e a sua thread; nada e global.

	Coordenadas: tudo o que viaja entre cliente e servidor e **local a arena**.
	O deslocamento do slot vai no MatchState (arenaOffsetX) e o cliente soma-o
	so para desenhar. Assim as regras de Config/Maps valem para todas as arenas.

	Durante a Prep cada jogador so recebe o SEU exercito (ArmyUpdate); o do
	adversario so e revelado na fase Reveal, pelo Roster.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local MatchConfig = require(Shared.Config.Match)
local Tutorial = require(Shared.Config.Tutorial)
local RankConfig = require(Shared.Config.Rank)
local AdminConfig = require(Shared.Config.Admin)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local BotService = require(script.Parent.BotService)
local MapService = require(script.Parent.MapService)
local RankService = require(script.Parent.RankService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local CombatService = require(script.Parent.CombatService)

type Side = {
	-- nil = bot (campanha). E a unica diferenca entre os dois modos.
	player: Player?,
	team: Types.Team,
	army: { Types.ArmyEntry },
	ready: boolean,
	lostLastRound: boolean,
}

type Match = {
	slot: number,
	offsetX: number,
	mode: Types.MatchMode,
	roundsToWin: number,
	maxRounds: number,
	-- Indexados pela equipa ("A" / "B").
	sides: { [string]: Side },
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

local function allocateUnitId(): number
	nextUnitId += 1
	return nextUnitId
end

local function getOpponent(match: Match, side: Side): Side?
	return match.sides[if side.team == "A" then "B" else "A"]
end

local function scoreOf(match: Match, team: Types.Team): number
	return if team == "A" then match.scoreA else match.scoreB
end

-- So os lados que tem jogador (o bot nao recebe nada nem volta para a fila).
local function playersOf(match: Match): { Player }
	local list: { Player } = {}
	for _, side in match.sides do
		local player = side.player
		if player then
			table.insert(list, player)
		end
	end
	return list
end

local function sideOf(match: Match, player: Player): Side?
	for _, side in match.sides do
		if side.player == player then
			return side
		end
	end
	return nil
end

-- Tropas a venda para este jogador: as que ja desbloqueou. No tutorial sao
-- as da Arena 1, que e exatamente o que um jogador novo tem; no sandbox sao
-- todas, que e o ponto de ter um sandbox.
local function troopPoolFor(player: Player, match: Match?): { Types.TroopId }
	if match and match.mode == "sandbox" then
		return MatchConfig.troopPool
	end
	return RankService.unlockedPool(player)
end

local function sendProfile(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local payload: Types.ProfilePayload = {
		level = profile.level,
		xp = profile.xp,
		coins = profile.coins,
		wins = profile.wins,
		losses = profile.losses,
		trophies = profile.trophies,
		arenaId = RankConfig.arenaFor(profile.trophies).id,
		tutorialDone = profile.tutorialDone,
		unlockedTroops = profile.unlockedTroops,
	}
	Net.fireClient("Profile", player, payload)
end

local function sendArmy(player: Player)
	local match = matchByPlayer[player]
	local side = if match then sideOf(match, player) else nil
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
		mode = "pvp",
		troopPool = troopPoolFor(player),
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
		local player = side.player
		if not player then
			continue
		end

		local opponent = getOpponent(match, side)
		local payload: Types.MatchStatePayload = {
			phase = match.phase,
			round = match.round,
			maxRounds = match.maxRounds,
			endsAt = match.phaseEndsAt,
			duration = match.phaseDuration,
			team = side.team,
			mode = match.mode,
			troopPool = troopPoolFor(player, match),
			arenaOffsetX = match.offsetX,
			selfReady = side.ready,
			opponentReady = if opponent then opponent.ready else false,
			opponentName = if opponent and opponent.player then opponent.player.Name else nil,
			selfScore = scoreOf(match, side.team),
			opponentScore = if opponent then scoreOf(match, opponent.team) else 0,
		}
		Net.fireClient("MatchState", player, payload)
	end
end

local function setPhase(match: Match, nextPhase: Types.MatchPhase, duration: number)
	match.phase = nextPhase
	match.phaseDuration = duration
	match.phaseEndsAt = now() + duration
	broadcastState(match)
end

-- O bot esta sempre pronto, por isso na campanha isto depende so do jogador.
local function bothReady(match: Match): boolean
	for _, side in match.sides do
		if not side.ready then
			return false
		end
	end
	return true
end

-- Espera o fim da fase. Na Prep, acaba mais cedo se estiverem todos prontos.
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

	local side = sideOf(match, player)
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

	if table.find(troopPoolFor(player, match), troopId) == nil then
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

	table.insert(side.army, { id = allocateUnitId(), troopId = troopId, x = x, z = z })
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

	local side = sideOf(match, player)
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

	for _, player in playersOf(match) do
		EconomyService.clear(player)
		matchByPlayer[player] = nil
		if player.Parent then
			sendLobbyState(player)
			sendArmy(player)
			sendProfile(player)
		end
	end

	matches[match.slot] = nil
	-- O matchmaking repoe na fila, no proximo ciclo, quem ainda a quiser.
end

local function startRound(match: Match, roundNumber: number)
	match.round = roundNumber

	local isTutorial = match.mode == "tutorial"

	-- O bot joga com as tropas que o jogador tem: perder para um gigante que
	-- ainda nem se viu nao ensina nada.
	local humanPool: { Types.TroopId } = MatchConfig.troopPool
	for _, side in match.sides do
		local player = side.player
		if player then
			humanPool = troopPoolFor(player, match)
		end
	end

	for _, side in match.sides do
		side.army = {}
		side.ready = false

		local player = side.player
		if player then
			local bonus = if side.lostLastRound then MatchConfig.loserBonus else 0
			local gold = if isTutorial
				then Tutorial.gold
				elseif match.mode == "sandbox" then AdminConfig.sandboxGold
				else MatchConfig.startingGold + bonus
			EconomyService.setGold(player, gold)
		elseif isTutorial then
			-- O bot nao compra: o exercito dele vem de Config/Tutorial.
			side.army = BotService.buildTutorialArmy(allocateUnitId)
			side.ready = true
		else
			-- Treino: mesmo orcamento do jogador, composicao sorteada a cada
			-- ronda. A dificuldade vem da composicao, nunca de dar mais ouro.
			local bonus = if side.lostLastRound then MatchConfig.loserBonus else 0
			local botGold = if match.mode == "sandbox"
				then AdminConfig.sandboxGold
				else MatchConfig.startingGold + bonus
			side.army = BotService.buildArmy(botGold, humanPool, allocateUnitId)
			side.ready = true
		end
	end

	setPhase(match, "Prep", MatchConfig.prepDuration)
	for _, player in playersOf(match) do
		sendArmy(player)
	end
	waitPhaseEnd(match)
end

-- Tutorial terminado: marca-o como feito e paga, uma vez so.
local function awardTutorial(match: Match, winner: Types.Team?)
	for _, side in match.sides do
		local player = side.player
		if player and side.team == winner then
			local firstTime = false
			DataService.update(player, function(profile: Types.Profile)
				if not profile.tutorialDone then
					profile.tutorialDone = true
					profile.xp += Tutorial.rewardXp
					profile.coins += Tutorial.rewardCoins
					firstTime = true
				end
			end)
			if firstTime then
				notify(player, "tutorial_complete", tostring(Tutorial.rewardCoins))
			end
			sendProfile(player)
		end
	end
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

		-- Reveal: os exercitos aparecem aos dois lados.
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
		for _, player in playersOf(match) do
			Net.fireClient("RoundResult", player, result)
		end

		setPhase(match, "RoundEnd", MatchConfig.roundEndDuration)
		waitPhaseEnd(match)
		CombatService.clear(match.session)

		local decided = match.scoreA >= match.roundsToWin or match.scoreB >= match.roundsToWin
		if decided or roundNumber >= match.maxRounds or match.abortRequested then
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

	-- Trofeus do PvP, para irem no MatchResult.
	local outcomes: { [Player]: RankService.MatchOutcome } = {}

	if not match.abortRequested then
		if match.mode == "tutorial" then
			awardTutorial(match, winner)
		elseif match.mode == "pvp" and winner then
			-- Historico do PvP. Uma partida abortada nao conta: sem Elo ainda
			-- nao ha nada a ganhar em premiar ou punir uma desistencia.
			-- Os trofeus do adversario sao lidos antes de qualquer alteracao,
			-- para os dois lados contarem a mesma partida.
			local trophiesBefore: { [Player]: number } = {}
			for _, side in match.sides do
				local player = side.player
				if player then
					trophiesBefore[player] = RankService.getTrophies(player)
				end
			end

			for _, side in match.sides do
				local player = side.player
				local opponent = getOpponent(match, side)
				local opponentPlayer = if opponent then opponent.player else nil
				if player then
					local won = side.team == winner
					DataService.update(player, function(profile: Types.Profile)
						if won then
							profile.wins += 1
						else
							profile.losses += 1
						end
					end)

					local against = if opponentPlayer then trophiesBefore[opponentPlayer] else nil
					local outcome = RankService.applyMatchResult(player, against or 0, won)
					if outcome then
						outcomes[player] = outcome
					end
					sendProfile(player)
				end
			end
		end
	end

	for _, player in playersOf(match) do
		local outcome = outcomes[player]
		local payload: Types.MatchResultPayload = {
			winner = winner,
			scoreA = match.scoreA,
			scoreB = match.scoreB,
			trophyDelta = if outcome then outcome.delta else nil,
			trophies = if outcome then outcome.trophies else nil,
			unlocked = if outcome then outcome.unlocked else nil,
		}
		Net.fireClient("MatchResult", player, payload)
	end

	-- No tutorial ninguem e empurrado para fora: o ecra de fim tem botoes e
	-- este tempo e so a rede de seguranca.
	local endDuration = if match.mode == "tutorial"
		then MatchConfig.tutorialResultTimeout
		else MatchConfig.matchEndDuration
	setPhase(match, "MatchEnd", endDuration)
	waitPhaseEnd(match)
	closeMatch(match)
end

local function spawnMatch(match: Match)
	matches[match.slot] = match
	for _, player in playersOf(match) do
		matchByPlayer[player] = match
	end

	-- O campo veste-se com a arena de quem tem menos troféus: quem está a
	-- subir vê o cenário mudar, em vez de ser o veterano a ver sempre o seu.
	local lowest: number? = nil
	for _, player in playersOf(match) do
		local trophies = RankService.getTrophies(player)
		if lowest == nil or trophies < lowest then
			lowest = trophies
		end
	end
	MapService.applyTheme(match.slot, RankConfig.arenaFor(lowest or 0))

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn(`MatchService: a partida no slot {match.slot} falhou: {err}`)
			closeMatch(match)
		end
	end)
end

local function newMatch(slot: number, mode: Types.MatchMode): Match
	-- O tutorial e o sandbox sao de uma ronda: um e uma aula, o outro e uma
	-- bancada de testes. Em ambos ninguem quer esperar por tres rondas.
	local solo = mode == "tutorial" or mode == "sandbox"
	return {
		slot = slot,
		offsetX = Maps.arenaOffset(map, slot),
		mode = mode,
		-- O tutorial e uma ronda so: e uma aula, nao um duelo.
		roundsToWin = if solo then 1 else MatchConfig.roundsToWin,
		maxRounds = if solo then 1 else MatchConfig.maxRounds,
		sides = {},
		phase = "Lobby",
		phaseEndsAt = now(),
		phaseDuration = 0,
		round = 0,
		scoreA = 0,
		scoreB = 0,
		abortRequested = false,
		session = CombatService.createSession({}),
	}
end

local function newSide(player: Player?, team: Types.Team): Side
	return { player = player, team = team, army = {}, ready = false, lostLastRound = false }
end

-- API -------------------------------------------------------------------------

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

	local match = newMatch(slot, "pvp")
	match.sides.A = newSide(playerA, "A")
	match.sides.B = newSide(playerB, "B")
	CombatService.setRecipients(match.session, { playerA, playerB })
	spawnMatch(match)
	return true
end

function MatchService.beginTutorial(player: Player): boolean
	if matchByPlayer[player] then
		return false
	end

	local slot = MatchService.freeSlot()
	if not slot then
		notify(player, "server_full")
		return false
	end

	local match = newMatch(slot, "tutorial")
	match.sides.A = newSide(player, "A")
	match.sides.B = newSide(nil, "B")
	CombatService.setRecipients(match.session, { player })
	spawnMatch(match)
	return true
end

-- Bancada de testes do admin: contra o bot, tudo desbloqueado, ouro a vontade.
function MatchService.beginSandbox(player: Player): boolean
	if matchByPlayer[player] then
		return false
	end

	local slot = MatchService.freeSlot()
	if not slot then
		notify(player, "server_full")
		return false
	end

	local match = newMatch(slot, "sandbox")
	match.sides.A = newSide(player, "A")
	match.sides.B = newSide(nil, "B")
	CombatService.setRecipients(match.session, { player })
	spawnMatch(match)
	return true
end

-- Partida de treino contra o bot, quando a fila do PvP demora demasiado.
function MatchService.beginTraining(player: Player): boolean
	if matchByPlayer[player] then
		return false
	end

	local slot = MatchService.freeSlot()
	if not slot then
		return false
	end

	local match = newMatch(slot, "training")
	match.sides.A = newSide(player, "A")
	match.sides.B = newSide(nil, "B")
	CombatService.setRecipients(match.session, { player })
	spawnMatch(match)
	return true
end

-- Atalhos de teste (quem pode e decidido no AdminService) --------------------

-- Acaba a fase atual ja, sem esperar pelo cronometro.
function MatchService.adminSkipPhase(player: Player): boolean
	local match = matchByPlayer[player]
	if not match then
		return false
	end
	match.phaseEndsAt = now()
	broadcastState(match)
	return true
end

-- Ouro extra para experimentar composicoes sem esperar pela ronda seguinte.
function MatchService.adminGrantGold(player: Player, amount: number): boolean
	if not matchByPlayer[player] then
		return false
	end
	EconomyService.refund(player, amount)
	sendArmy(player)
	return true
end

-- Volta a mandar perfil e estado (usado depois de mexer nos trofeus).
function MatchService.adminRefresh(player: Player)
	sendProfile(player)
	local match = matchByPlayer[player]
	if match then
		broadcastState(match)
	else
		sendLobbyState(player)
	end
	sendArmy(player)
end

function MatchService.handlePlayerLeaving(player: Player)
	local match = matchByPlayer[player]
	if not match then
		return
	end

	local side = sideOf(match, player)
	if side then
		side.player = nil
	end
	matchByPlayer[player] = nil
	EconomyService.clear(player)

	match.abortRequested = true
	CombatService.stop(match.session)
	-- Deixa de replicar para quem saiu.
	CombatService.setRecipients(match.session, playersOf(match))

	for _, other in playersOf(match) do
		notify(other, "opponent_left")
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

	Net.onServerEvent("StartTutorial", function(player: Player)
		MatchService.beginTutorial(player)
	end)

	-- Desistir e so para o tutorial: no PvP sair a meio e abandonar, e isso
	-- passa por sair da partida (handlePlayerLeaving).
	Net.onServerEvent("LeaveMatch", function(player: Player)
		local match = matchByPlayer[player]
		if match and (match.mode == "tutorial" or match.mode == "sandbox") then
			match.abortRequested = true
			CombatService.stop(match.session)
		end
	end)

	Net.onServerEvent("RequestState", function(player: Player)
		local match = matchByPlayer[player]
		if match then
			broadcastState(match)
		else
			sendLobbyState(player)
		end
		sendArmy(player)
		sendProfile(player)
	end)
end

function MatchService.start()
	local function greet(player: Player)
		sendLobbyState(player)
		-- O perfil pode ainda estar a carregar; quando chegar, o cliente
		-- recebe-o pelo RequestState que manda no arranque.
		sendProfile(player)
	end

	-- O perfil carrega depois de o jogador entrar; mandamo-lo quando chegar.
	-- E e tambem aqui que a primeira partida de sempre comeca sozinha: quem
	-- chega vai direto ao tutorial, sem passar pelo lobby.
	DataService.onProfileLoaded(function(player: Player)
		sendProfile(player)

		local profile = DataService.get(player)
		if profile and not profile.tutorialDone and not matchByPlayer[player] then
			MatchService.beginTutorial(player)
		end
	end)

	Players.PlayerAdded:Connect(greet)
	for _, player in Players:GetPlayers() do
		greet(player)
	end
end

return MatchService
