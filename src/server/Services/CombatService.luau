--!strict
--[[
	CombatService — a batalha, so com numeros.

	Cada partida tem a sua Session: o servidor corre varias ao mesmo tempo, uma
	por arena. Nada de estado global aqui.

	O servidor nao cria uma Instance por unidade: simula posicoes em tick fixo
	(Config/Match.tickRate) e replica o minimo (id, x, z, hp) **so aos dois
	jogadores da partida**. O cliente constroi os modelos a partir do Roster e
	interpola entre snapshots.

	As coordenadas sao sempre locais a arena; o deslocamento do slot e assunto
	do cliente, na altura de desenhar.

	IA de combate: procurar o inimigo vivo mais proximo, aproximar-se ate ao
	alcance e atacar respeitando o attackSpeed. O dano usa bonusVs e, quando a
	tropa tem aoeRadius, atinge todos os inimigos em volta do alvo.

	IA de suporte (tropas com healAmount): procurar o aliado ferido mais proximo
	e cura-lo; sem feridos, acompanha o grupo por tras em vez de avancar para o
	inimigo. Nao ataca.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local MatchConfig = require(Shared.Config.Match)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Spells = require(Shared.Config.Spells)

type Unit = {
	id: number,
	team: Types.Team,
	troopId: Types.TroopId,
	def: Types.TroopDef,
	x: number,
	z: number,
	hp: number,
	maxHp: number,
	cooldown: number,
	-- Segundos que ainda falta estar parado (feitico de congelar).
	frozenFor: number,
	-- Atacou no ultimo tick: viaja no snapshot para o cliente animar o golpe.
	swinging: boolean,
	alive: boolean,
}

export type Session = {
	units: { [number]: Unit },
	order: { number }, -- iteracao deterministica
	currentTick: number,
	running: boolean,
	stopRequested: boolean,
	-- Quem recebe o Roster e os Snapshots desta partida.
	recipients: { Player },
}

local CombatService = {}

-- Multiplicador da simulacao, para os atalhos de teste. Afeta so o ritmo a que
-- os ticks sao processados; o passo fixo mantem-se, por isso a batalha corre
-- igual, apenas mais depressa no relogio de quem ve.
local speedMultiplier = 1

function CombatService.setSpeed(value: number)
	speedMultiplier = math.clamp(value, 0.25, 10)
end

function CombatService.init() end
function CombatService.start() end

-- Ciclo de vida ---------------------------------------------------------------

function CombatService.createSession(recipients: { Player }): Session
	return {
		units = {},
		order = {},
		currentTick = 0,
		running = false,
		stopRequested = false,
		recipients = recipients,
	}
end

function CombatService.clear(session: Session)
	session.units = {}
	session.order = {}
	session.currentTick = 0
	session.running = false
	session.stopRequested = false
end

function CombatService.stop(session: Session)
	session.stopRequested = true
end

function CombatService.setRecipients(session: Session, recipients: { Player })
	session.recipients = recipients
end

local function sendToSession(session: Session, remoteName: string, payload: any)
	for _, player in session.recipients do
		if player.Parent then
			Net.fireClient(remoteName, player, payload)
		end
	end
end

-- Criacao ---------------------------------------------------------------------

-- Cria as unidades da ronda e manda o roster. E aqui que os exercitos deixam de
-- ser secretos, por isso so se chama na fase Reveal.
function CombatService.spawnRound(session: Session, entries: { Types.SpawnEntry })
	CombatService.clear(session)

	for _, entry in entries do
		local def = Troops.get(entry.troopId)
		if def then
			session.units[entry.id] = {
				id = entry.id,
				team = entry.team,
				troopId = entry.troopId,
				def = def,
				x = entry.x,
				z = entry.z,
				hp = def.hp,
				maxHp = def.hp,
				cooldown = 0,
				frozenFor = 0,
				swinging = false,
				alive = true,
			}
			table.insert(session.order, entry.id)
		end
	end

	table.sort(session.order)

	local roster: Types.RosterPayload = { units = entries }
	sendToSession(session, "Roster", roster)
end

-- Feiticos ---------------------------------------------------------------------

-- Aplica um feitico num ponto. `caster` e a equipa de quem lancou, para saber
-- quem e inimigo. Devolve quantas unidades foram apanhadas.
function CombatService.castSpell(session: Session, spellId: string, caster: Types.Team, x: number, z: number): number
	local def = Spells.get(spellId)
	if not def then
		return 0
	end

	local hits = 0

	for _, id in session.order do
		local unit = session.units[id]
		if unit and unit.alive then
			local isEnemy = unit.team ~= caster
			local matches = def.affects == "all"
				or (def.affects == "enemies" and isEnemy)
				or (def.affects == "allies" and not isEnemy)

			if matches then
				local dx = unit.x - x
				local dz = unit.z - z
				if dx * dx + dz * dz <= def.radius * def.radius then
					hits += 1
					if def.freezeDuration > 0 then
						unit.frozenFor = math.max(unit.frozenFor, def.freezeDuration)
					end
					if def.damage > 0 then
						unit.hp -= def.damage
						if unit.hp <= 0 then
							unit.hp = 0
							unit.alive = false
						end
					end
				end
			end
		end
	end

	-- Quem morreu desaparece no snapshot seguinte (no maximo 0,1 s depois); o
	-- cliente ja desenhou o efeito a partir do SpellCast.
	return hits
end

-- Simulacao -------------------------------------------------------------------

local function nearestEnemy(session: Session, unit: Unit): Unit?
	local best: Unit? = nil
	local bestDistance = math.huge
	for _, id in session.order do
		local other = session.units[id]
		if other and other.alive and other.team ~= unit.team then
			local dx = other.x - unit.x
			local dz = other.z - unit.z
			local distance = dx * dx + dz * dz
			if distance < bestDistance then
				bestDistance = distance
				best = other
			end
		end
	end
	return best
end

-- Aliado ferido mais proximo (ignora-se a si proprio).
local function nearestWoundedAlly(session: Session, unit: Unit): Unit?
	local best: Unit? = nil
	local bestDistance = math.huge
	for _, id in session.order do
		local other = session.units[id]
		if other and other.alive and other.team == unit.team and other.id ~= unit.id and other.hp < other.maxHp then
			local dx = other.x - unit.x
			local dz = other.z - unit.z
			local distance = dx * dx + dz * dz
			if distance < bestDistance then
				bestDistance = distance
				best = other
			end
		end
	end
	return best
end

-- Aliado de combate mais proximo, para o curandeiro ter quem seguir.
-- Ignora outros curandeiros: dois curandeiros nao se seguem um ao outro.
local function nearestFighterAlly(session: Session, unit: Unit): Unit?
	local best: Unit? = nil
	local bestDistance = math.huge
	for _, id in session.order do
		local other = session.units[id]
		if
			other
			and other.alive
			and other.team == unit.team
			and other.id ~= unit.id
			and not other.def.healAmount
		then
			local dx = other.x - unit.x
			local dz = other.z - unit.z
			local distance = dx * dx + dz * dz
			if distance < bestDistance then
				bestDistance = distance
				best = other
			end
		end
	end
	return best
end

-- Aproxima-se de `other` sem lhe colar: para a `stopDistance` de distancia.
local function moveToward(unit: Unit, other: Unit, dt: number, stopDistance: number)
	local dx = other.x - unit.x
	local dz = other.z - unit.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= 1e-4 then
		return
	end
	local stepLength = math.min(unit.def.moveSpeed * dt, distance - stopDistance)
	if stepLength > 0 then
		unit.x += dx / distance * stepLength
		unit.z += dz / distance * stepLength
	end
end

local function reachBetween(unit: Unit, other: Unit): number
	return unit.def.range + unit.def.radius + other.def.radius
end

local function distanceBetween(unit: Unit, other: Unit): number
	local dx = other.x - unit.x
	local dz = other.z - unit.z
	return math.sqrt(dx * dx + dz * dz)
end

local function applyDamage(attacker: Unit, victim: Unit, dead: { number })
	local multiplier = attacker.def.bonusVs[victim.troopId] or 1
	victim.hp -= attacker.def.damage * multiplier
	if victim.hp <= 0 then
		victim.hp = 0
		victim.alive = false
		table.insert(dead, victim.id)
	end
end

local function attack(session: Session, unit: Unit, target: Unit, dead: { number })
	unit.cooldown = 1 / unit.def.attackSpeed
	unit.swinging = true

	local aoeRadius = unit.def.aoeRadius
	if not aoeRadius then
		applyDamage(unit, target, dead)
		return
	end

	for _, id in session.order do
		local other = session.units[id]
		if other and other.alive and other.team ~= unit.team then
			local dx = other.x - target.x
			local dz = other.z - target.z
			if dx * dx + dz * dz <= aoeRadius * aoeRadius then
				applyDamage(unit, other, dead)
			end
		end
	end
end

local function heal(unit: Unit, patient: Unit)
	unit.cooldown = 1 / unit.def.attackSpeed
	local amount = unit.def.healAmount or 0
	patient.hp = math.min(patient.maxHp, patient.hp + amount)
end

-- Curandeiro: trata do ferido mais proximo; sem feridos, segue o grupo.
local function stepSupport(session: Session, unit: Unit, dt: number)
	local patient = nearestWoundedAlly(session, unit)
	if patient then
		local reach = reachBetween(unit, patient)
		if distanceBetween(unit, patient) <= reach then
			if unit.cooldown <= 0 then
				heal(unit, patient)
			end
		else
			moveToward(unit, patient, dt, reach)
		end
		return
	end

	-- Ninguem ferido: fica atras do aliado de combate mais proximo, a meio
	-- alcance, para nao ir sozinho contra o inimigo.
	local anchor = nearestFighterAlly(session, unit)
	if anchor then
		local keep = unit.def.range * 0.6
		if distanceBetween(unit, anchor) > keep then
			moveToward(unit, anchor, dt, keep)
		end
	end
end

-- Empurra unidades sobrepostas, para nao ficarem todas no mesmo ponto.
local function separate(session: Session)
	local order = session.order
	local count = #order
	for i = 1, count do
		local a = session.units[order[i]]
		if a and a.alive and a.frozenFor <= 0 then
			for j = i + 1, count do
				local b = session.units[order[j]]
				if b and b.alive and b.frozenFor <= 0 then
					local dx = b.x - a.x
					local dz = b.z - a.z
					local minDistance = a.def.radius + b.def.radius
					local squared = dx * dx + dz * dz
					if squared < minDistance * minDistance then
						if squared < 1e-6 then
							-- Perfeitamente sobrepostas: abre-as num angulo estavel.
							local angle = a.id * 2.3999632
							dx = math.cos(angle)
							dz = math.sin(angle)
							squared = 1
						end
						local distance = math.sqrt(squared)
						local push = (minDistance - distance) * 0.5
						local nx = dx / distance * push
						local nz = dz / distance * push
						a.x -= nx
						a.z -= nz
						b.x += nx
						b.z += nz
					end
				end
			end
		end
	end
end

local function step(session: Session, dt: number, dead: { number })
	local map = Maps.default

	for _, id in session.order do
		local unit = session.units[id]
		if unit and unit.alive then
			unit.cooldown = math.max(0, unit.cooldown - dt)
			unit.swinging = false

			if unit.frozenFor > 0 then
				-- Congelado: nao anda, nao ataca, nao cura. O cooldown corre
				-- na mesma, para nao sair do gelo a disparar de imediato.
				unit.frozenFor = math.max(0, unit.frozenFor - dt)
			elseif unit.def.healAmount then
				stepSupport(session, unit, dt)
			else
				local target = nearestEnemy(session, unit)
				if target then
					local reach = reachBetween(unit, target)
					if distanceBetween(unit, target) <= reach then
						if unit.cooldown <= 0 then
							attack(session, unit, target, dead)
						end
					else
						moveToward(unit, target, dt, reach)
					end
				end
			end
		end
	end

	separate(session)

	for _, id in session.order do
		local unit = session.units[id]
		if unit and unit.alive then
			unit.x, unit.z = Maps.clampToArena(map, unit.x, unit.z, unit.def.radius)
		end
	end
end

-- Replicacao ------------------------------------------------------------------

local function broadcastSnapshot(session: Session, dead: { number })
	local alive: { number } = {}
	local cursor = 0
	for _, id in session.order do
		local unit = session.units[id]
		if unit and unit.alive then
			alive[cursor + 1] = unit.id
			alive[cursor + 2] = math.floor(unit.x * 100) / 100
			alive[cursor + 3] = math.floor(unit.z * 100) / 100
			alive[cursor + 4] = math.ceil(unit.hp)
			-- Campo de bits do estado: 1 = congelado, 2 = a atacar.
			local flags = 0
			if unit.frozenFor > 0 then
				flags += 1
			end
			if unit.swinging then
				flags += 2
			end
			alive[cursor + 5] = flags
			cursor += 5
		end
	end

	local snapshot: Types.SnapshotPayload = { tick = session.currentTick, alive = alive, dead = dead }
	sendToSession(session, "Snapshot", snapshot)
end

-- Resultado -------------------------------------------------------------------

local function tally(session: Session, team: Types.Team): (number, number)
	local count = 0
	local value = 0
	for _, id in session.order do
		local unit = session.units[id]
		if unit and unit.alive and unit.team == team then
			count += 1
			value += unit.def.cost
		end
	end
	return count, value
end

local function buildResult(session: Session, reason: Types.RoundEndReason): Types.RoundResultPayload
	local countA, valueA = tally(session, "A")
	local countB, valueB = tally(session, "B")

	local winner: Types.Team? = nil
	if reason == "elimination" then
		if countA > 0 and countB == 0 then
			winner = "A"
		elseif countB > 0 and countA == 0 then
			winner = "B"
		end
	elseif reason == "timeout" then
		-- Sem eliminacao: ganha quem tem mais valor (em ouro) vivo.
		if valueA > valueB then
			winner = "A"
		elseif valueB > valueA then
			winner = "B"
		end
	end

	return {
		round = 0, -- preenchido pelo MatchService
		winner = winner,
		reason = reason,
		valueA = valueA,
		valueB = valueB,
		countA = countA,
		countB = countB,
		scoreA = 0,
		scoreB = 0,
	}
end

-- Corre a batalha ate um lado morrer ou o tempo acabar. Bloqueia a thread da
-- partida (cada partida tem a sua), que e quem conduz a maquina de estados.
function CombatService.runBattle(session: Session, maxDuration: number): Types.RoundResultPayload
	local interval = 1 / MatchConfig.tickRate
	local accumulator = 0
	local elapsed = 0

	session.running = true
	session.stopRequested = false

	while true do
		local dt: number = RunService.Heartbeat:Wait() * speedMultiplier
		accumulator += dt
		elapsed += dt

		-- Nunca processar demasiados ticks de uma vez: se o servidor engasgar,
		-- a batalha abranda em vez de saltar.
		local budget = 4
		while accumulator >= interval and budget > 0 do
			accumulator -= interval
			budget -= 1
			session.currentTick += 1

			local dead: { number } = {}
			step(session, interval, dead)
			broadcastSnapshot(session, dead)

			if session.stopRequested then
				session.running = false
				return buildResult(session, "aborted")
			end

			local countA = tally(session, "A")
			local countB = tally(session, "B")
			if countA == 0 or countB == 0 then
				session.running = false
				return buildResult(session, "elimination")
			end
		end

		if elapsed >= maxDuration then
			session.running = false
			return buildResult(session, "timeout")
		end
	end
end

return CombatService
