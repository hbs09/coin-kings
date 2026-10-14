--!strict
--[[
	MatchService — a maquina de estados da partida e a autoridade sobre o
	exercito de cada jogador.

	Queue -> Prep -> Reveal -> Battle -> RoundEnd -> ... -> MatchEnd

	Serve os dois modos, porque a unica diferenca entre eles e **quem esta do
	outro lado**:
	- "pvp": dois jogadores, melhor de 3, orcamento de Config/Match.
	- "campaign": um jogador contra um exercito fixo de Config/Campaign, uma
	  ronda, orcamento e loja do capitulo. Ganhar marca o capitulo como feito e
	  da XP e moedas.

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
local Campaign = require(Shared.Config.Campaign)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local BotService = require(script.Parent.BotService)
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
	chapterId: string?,
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

-- Tropas a venda nesta partida: as do capitulo na campanha, o pool global no PvP.
local function troopPoolOf(match: Match): { Types.TroopId }
	local chapterId = match.chapterId
	if chapterId then
		local chapter = Campaign.get(chapterId)
		if chapter then
			return chapter.troopPool
		end
	end
	return MatchConfig.troopPool
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
		campaign = profile.campaign,
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
		chapterId = nil,
		troopPool = MatchConfig.troopPool,
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
	local pool = troopPoolOf(match)
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
			chapterId = match.chapterId,
			troopPool = pool,
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

	if table.find(troopPoolOf(match), troopId) == nil then
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

	local chapter = if match.chapterId then Campaign.get(match.chapterId) else nil

	for _, side in match.sides do
		side.army = {}
		side.ready = false

		local player = side.player
		if player then
			local bonus = if side.lostLastRound then MatchConfig.loserBonus else 0
			local gold = if chapter then chapter.gold else MatchConfig.startingGold + bonus
			EconomyService.setGold(player, gold)
		elseif match.chapterId then
			-- O bot nao compra: o exercito dele vem do capitulo, ja validado.
			side.army = BotService.buildCampaignArmy(match.chapterId, allocateUnitId)
			side.ready = true
		end
	end

	setPhase(match, "Prep", MatchConfig.prepDuration)
	for _, player in playersOf(match) do
		sendArmy(player)
	end
	waitPhaseEnd(match)
end

-- Capitulo ganho: marca como feito e paga a recompensa (uma vez so).
local function awardCampaign(match: Match, winner: Types.Team?)
	local chapterId = match.chapterId
	if not chapterId or not winner then
		return
	end

	local chapter = Campaign.get(chapterId)
	if not chapter then
		return
	end

	for _, side in match.sides do
		local player = side.player
		if player and side.team == winner then
			local firstTime = false
			DataService.update(player, function(profile: Types.Profile)
				if not profile.campaign[chapterId] then
					profile.campaign[chapterId] = true
					firstTime = true
				end
				-- Repetir um capitulo nao volta a pagar: a campanha e para
				-- resolver, nao para moer.
				if firstTime then
					profile.xp += chapter.rewardXp
					profile.coins += chapter.rewardCoins
				end
			end)
			if firstTime then
				notify(player, "chapter_complete", tostring(chapter.rewardCoins))
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

	if not match.abortRequested then
		if match.mode == "campaign" then
			awardCampaign(match, winner)
		elseif winner then
			-- Historico do PvP. Uma partida abortada nao conta: sem Elo ainda
			-- nao ha nada a ganhar em premiar ou punir uma desistencia.
			for _, side in match.sides do
				local player = side.player
				if player then
					local won = side.team == winner
					DataService.update(player, function(profile: Types.Profile)
						if won then
							profile.wins += 1
						else
							profile.losses += 1
						end
					end)
				end
			end
		end
	end

	local payload: Types.MatchResultPayload = { winner = winner, scoreA = match.scoreA, scoreB = match.scoreB }
	for _, player in playersOf(match) do
		Net.fireClient("MatchResult", player, payload)
	end

	setPhase(match, "MatchEnd", MatchConfig.matchEndDuration)
	waitPhaseEnd(match)
	closeMatch(match)
end

local function spawnMatch(match: Match)
	matches[match.slot] = match
	for _, player in playersOf(match) do
		matchByPlayer[player] = match
	end

	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn(`MatchService: a partida no slot {match.slot} falhou: {err}`)
			closeMatch(match)
		end
	end)
end

local function newMatch(slot: number, mode: Types.MatchMode, chapterId: string?): Match
	return {
		slot = slot,
		offsetX = Maps.arenaOffset(map, slot),
		mode = mode,
		chapterId = chapterId,
		roundsToWin = if mode == "campaign" then Campaign.roundsToWin else MatchConfig.roundsToWin,
		maxRounds = if mode == "campaign" then Campaign.maxRounds else MatchConfig.maxRounds,
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

	local match = newMatch(slot, "pvp", nil)
	match.sides.A = newSide(playerA, "A")
	match.sides.B = newSide(playerB, "B")
	CombatService.setRecipients(match.session, { playerA, playerB })
	spawnMatch(match)
	return true
end

function MatchService.beginCampaign(player: Player, chapterId: string): boolean
	if matchByPlayer[player] then
		return false
	end

	local chapter = Campaign.get(chapterId)
	if not chapter then
		return false
	end

	-- Um capitulo so abre com o anterior feito: o cliente ja o esconde, mas e
	-- o servidor que decide.
	local profile = DataService.get(player)
	local completed = if profile then profile.campaign else {}
	if not Campaign.isUnlocked(chapterId, completed) then
		notify(player, "chapter_locked")
		return false
	end

	local slot = MatchService.freeSlot()
	if not slot then
		notify(player, "server_full")
		return false
	end

	local match = newMatch(slot, "campaign", chapterId)
	match.sides.A = newSide(player, "A")
	match.sides.B = newSide(nil, "B")
	CombatService.setRecipients(match.session, { player })
	spawnMatch(match)
	return true
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

	Net.onServerEvent("StartCampaign", function(player: Player, chapterId: any)
		MatchService.beginCampaign(player, chapterId :: string)
	end)

	-- Desistir e so para a campanha: no PvP sair a meio e abandonar, e isso
	-- passa por sair da partida (handlePlayerLeaving).
	Net.onServerEvent("LeaveMatch", function(player: Player)
		local match = matchByPlayer[player]
		if match and match.mode == "campaign" then
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
	DataService.onProfileLoaded(sendProfile)

	Players.PlayerAdded:Connect(greet)
	for _, player in Players:GetPlayers() do
		greet(player)
	end
end

return MatchService
