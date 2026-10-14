--!strict
--[[
	CombatService — a batalha, so com numeros.

	O servidor nao cria uma Instance por unidade: simula posicoes em tick fixo
	(Config/Match.tickRate) e replica o minimo (id, x, z, hp). O cliente constroi
	os modelos a partir do Roster e interpola entre snapshots.

	IA desta fase: procurar o inimigo vivo mais proximo, aproximar-se ate ao
	alcance e atacar respeitando o attackSpeed. O dano usa bonusVs e, quando a
	tropa tem aoeRadius, atinge todos os inimigos em volta do alvo.
	(O healer entra no MVP, com a sua propria procura de aliado ferido.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local MatchConfig = require(Shared.Config.Match)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)

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
	alive: boolean,
}

local CombatService = {}

local units: { [number]: Unit } = {}
local order: { number } = {} -- iteracao deterministica
local currentTick = 0
local running = false
local stopRequested = false

function CombatService.init() end
function CombatService.start() end

-- Limpeza ---------------------------------------------------------------------

function CombatService.clear()
	units = {}
	order = {}
	currentTick = 0
	running = false
	stopRequested = false
end

function CombatService.stop()
	stopRequested = true
end

-- Criacao ---------------------------------------------------------------------

-- Cria as unidades da ronda e manda o roster completo. E aqui que os exercitos
-- deixam de ser secretos, por isso so se chama na fase Reveal.
function CombatService.spawnRound(entries: { Types.SpawnEntry })
	CombatService.clear()

	for _, entry in entries do
		local def = Troops.get(entry.troopId)
		if def then
			units[entry.id] = {
				id = entry.id,
				team = entry.team,
				troopId = entry.troopId,
				def = def,
				x = entry.x,
				z = entry.z,
				hp = def.hp,
				maxHp = def.hp,
				cooldown = 0,
				alive = true,
			}
			table.insert(order, entry.id)
		end
	end

	table.sort(order)

	local roster: Types.RosterPayload = { units = entries }
	Net.fireAllClients("Roster", roster)
end

-- Simulacao -------------------------------------------------------------------

local function nearestEnemy(unit: Unit): Unit?
	local best: Unit? = nil
	local bestDistance = math.huge
	for _, id in order do
		local other = units[id]
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

local function applyDamage(attacker: Unit, victim: Unit, dead: { number })
	local multiplier = attacker.def.bonusVs[victim.troopId] or 1
	victim.hp -= attacker.def.damage * multiplier
	if victim.hp <= 0 then
		victim.hp = 0
		victim.alive = false
		table.insert(dead, victim.id)
	end
end

local function attack(unit: Unit, target: Unit, dead: { number })
	unit.cooldown = 1 / unit.def.attackSpeed

	local aoeRadius = unit.def.aoeRadius
	if not aoeRadius then
		applyDamage(unit, target, dead)
		return
	end

	for _, id in order do
		local other = units[id]
		if other and other.alive and other.team ~= unit.team then
			local dx = other.x - target.x
			local dz = other.z - target.z
			if dx * dx + dz * dz <= aoeRadius * aoeRadius then
				applyDamage(unit, other, dead)
			end
		end
	end
end

-- Empurra unidades sobrepostas, para nao ficarem todas no mesmo ponto.
local function separate()
	local count = #order
	for i = 1, count do
		local a = units[order[i]]
		if a and a.alive then
			for j = i + 1, count do
				local b = units[order[j]]
				if b and b.alive then
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

local function step(dt: number, dead: { number })
	local map = Maps.default

	for _, id in order do
		local unit = units[id]
		if unit and unit.alive then
			unit.cooldown = math.max(0, unit.cooldown - dt)

			local target = nearestEnemy(unit)
			if target then
				local dx = target.x - unit.x
				local dz = target.z - unit.z
				local distance = math.sqrt(dx * dx + dz * dz)
				local reach = unit.def.range + unit.def.radius + target.def.radius

				if distance <= reach then
					if unit.cooldown <= 0 then
						attack(unit, target, dead)
					end
				elseif distance > 1e-4 then
					local stepLength = math.min(unit.def.moveSpeed * dt, distance - reach)
					if stepLength > 0 then
						unit.x += dx / distance * stepLength
						unit.z += dz / distance * stepLength
					end
				end
			end
		end
	end

	separate()

	for _, id in order do
		local unit = units[id]
		if unit and unit.alive then
			unit.x, unit.z = Maps.clampToArena(map, unit.x, unit.z, unit.def.radius)
		end
	end
end

-- Replicacao ------------------------------------------------------------------

local function broadcastSnapshot(dead: { number })
	local alive: { number } = {}
	local cursor = 0
	for _, id in order do
		local unit = units[id]
		if unit and unit.alive then
			alive[cursor + 1] = unit.id
			alive[cursor + 2] = math.floor(unit.x * 100) / 100
			alive[cursor + 3] = math.floor(unit.z * 100) / 100
			alive[cursor + 4] = math.ceil(unit.hp)
			cursor += 4
		end
	end

	local snapshot: Types.SnapshotPayload = { tick = currentTick, alive = alive, dead = dead }
	Net.fireAllClients("Snapshot", snapshot)
end

-- Resultado -------------------------------------------------------------------

local function tally(team: Types.Team): (number, number)
	local count = 0
	local value = 0
	for _, id in order do
		local unit = units[id]
		if unit and unit.alive and unit.team == team then
			count += 1
			value += unit.def.cost
		end
	end
	return count, value
end

local function buildResult(reason: Types.RoundEndReason): Types.RoundResultPayload
	local countA, valueA = tally("A")
	local countB, valueB = tally("B")

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

-- Corre a batalha ate um lado morrer ou o tempo acabar. Bloqueia a thread do
-- MatchService, que e quem conduz a maquina de estados.
function CombatService.runBattle(maxDuration: number): Types.RoundResultPayload
	local interval = 1 / MatchConfig.tickRate
	local accumulator = 0
	local elapsed = 0

	running = true
	stopRequested = false

	while true do
		local dt: number = RunService.Heartbeat:Wait()
		accumulator += dt
		elapsed += dt

		-- Nunca processar demasiados ticks de uma vez: se o servidor engasgar,
		-- a batalha abranda em vez de saltar.
		local budget = 4
		while accumulator >= interval and budget > 0 do
			accumulator -= interval
			budget -= 1
			currentTick += 1

			local dead: { number } = {}
			step(interval, dead)
			broadcastSnapshot(dead)

			if stopRequested then
				running = false
				return buildResult("aborted")
			end

			local countA = tally("A")
			local countB = tally("B")
			if countA == 0 or countB == 0 then
				running = false
				return buildResult("elimination")
			end
		end

		if elapsed >= maxDuration then
			running = false
			return buildResult("timeout")
		end
	end
end

return CombatService
