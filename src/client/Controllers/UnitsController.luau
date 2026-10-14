--!strict
--[[
	UnitsController — desenha a batalha.

	Recebe o Roster no Reveal (ids, tropas, equipas e posicoes iniciais) e
	depois um Snapshot por tick do servidor (10 Hz). Entre snapshots interpola
	as posicoes, para a batalha ficar fluida a 60 fps sem replicar a 60 Hz.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)

local State = require(script.Parent.Parent.State)
local UnitVisual = require(script.Parent.Parent.UnitVisual)

local UnitsController = {}

local map = Maps.default

type Tracked = {
	visual: UnitVisual.Visual,
	maxHp: number,
	-- posicao desenhada e posicao que o servidor confirmou
	currentX: number,
	currentZ: number,
	targetX: number,
	targetZ: number,
	yaw: number,
}

local folder: Folder
local tracked: { [number]: Tracked } = {}

-- Quanto maior, mais depressa o modelo encosta a posicao do servidor.
local SMOOTHING = 14

local function clearAll()
	for id, entry in tracked do
		UnitVisual.destroy(entry.visual)
		tracked[id] = nil
	end
end

local function onRoster(payload: Types.RosterPayload)
	clearAll()

	for _, entry in payload.units do
		local def = Troops.get(entry.troopId)
		if def then
			local visual = UnitVisual.create(def, Maps.teamColor(map, entry.team), folder, {
				label = true,
				healthBar = true,
			})
			-- Todas as unidades comecam a olhar para o lado inimigo.
			local yaw = if entry.team == "A" then 0 else math.pi

			tracked[entry.id] = {
				visual = visual,
				maxHp = entry.maxHp,
				currentX = entry.x,
				currentZ = entry.z,
				targetX = entry.x,
				targetZ = entry.z,
				yaw = yaw,
			}
			UnitVisual.setPosition(visual, entry.x, entry.z, yaw)
		end
	end
end

local function onSnapshot(payload: Types.SnapshotPayload)
	local alive = payload.alive
	local count = #alive

	-- Array plano: id, x, z, hp
	local index = 1
	while index + 3 <= count do
		local id = alive[index]
		local entry = tracked[id]
		if entry then
			entry.targetX = alive[index + 1]
			entry.targetZ = alive[index + 2]
			UnitVisual.setHealth(entry.visual, alive[index + 3] / entry.maxHp)
		end
		index += 4
	end

	for _, id in payload.dead do
		local entry = tracked[id]
		if entry then
			UnitVisual.destroy(entry.visual)
			tracked[id] = nil
		end
	end
end

local function onRender(deltaTime: number)
	local alpha = math.min(1, deltaTime * SMOOTHING)

	for _, entry in tracked do
		local dx = entry.targetX - entry.currentX
		local dz = entry.targetZ - entry.currentZ

		if dx * dx + dz * dz > 1e-6 then
			entry.currentX += dx * alpha
			entry.currentZ += dz * alpha
			-- Vira-se para onde anda (so quando se mexe o suficiente).
			if dx * dx + dz * dz > 0.01 then
				entry.yaw = math.atan2(-dx, -dz)
			end
			UnitVisual.setPosition(entry.visual, entry.currentX, entry.currentZ, entry.yaw)
		end
	end
end

function UnitsController.init()
	folder = Instance.new("Folder")
	folder.Name = "BattleUnits"
	folder.Parent = workspace
end

function UnitsController.start()
	State.onRoster(onRoster)
	State.onSnapshot(onSnapshot)

	State.onMatchState(function(payload: Types.MatchStatePayload)
		-- Entre rondas e no lobby o campo fica limpo.
		if payload.phase == "Prep" or payload.phase == "Lobby" then
			clearAll()
		end
	end)

	RunService.RenderStepped:Connect(onRender)
end

return UnitsController
