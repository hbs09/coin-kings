--!strict
--[[
	MapService — constrói as arenas a partir de Config/Maps.

	Uma arena por slot (Config/Match.maxMatchesPerServer), afastadas em X o
	suficiente para a arena do lado ficar fora do enquadramento da câmara. As
	unidades vivem em coordenadas locais à arena; só o desenho soma o offset.

	Tudo é ancorado e sem colisão de personagens: nesta fase os jogadores não
	têm corpo, vêem o campo por uma câmara fixa.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maps = require(ReplicatedStorage.Shared.Config.Maps)
local MatchConfig = require(ReplicatedStorage.Shared.Config.Match)
local RankConfig = require(ReplicatedStorage.Shared.Config.Rank)

local MapService = {}

local ARENA_NAME = "Arena"

local function part(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.Position = position
	p.Color = color
	p.Parent = parent
	return p
end

function MapService.init()
	-- Limpa o que vem do template do Studio.
	for _, child in workspace:GetChildren() do
		if child.Name == "Baseplate" or child.Name == ARENA_NAME or child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local root = Instance.new("Folder")
	root.Name = ARENA_NAME
	root.Parent = workspace

	for slot = 0, MatchConfig.maxMatchesPerServer - 1 do
		MapService.buildArena(root, slot)
	end
end

-- Uma arena completa, deslocada para o X do seu slot.
function MapService.buildArena(root: Instance, slot: number)
	local map = Maps.default
	local offsetX = Maps.arenaOffset(map, slot)

	local arena = Instance.new("Folder")
	arena.Name = `Arena_{slot}`
	arena.Parent = root

	-- Chão: uma placa por metade, mais a faixa neutra no meio.
	local halfLength = (map.length / 2) - map.neutralBand
	local halfCenter = map.neutralBand + halfLength / 2

	part(
		"Floor",
		Vector3.new(map.width, 1, map.length),
		Vector3.new(offsetX, map.floorY - 0.5, 0),
		map.floorColor,
		arena
	)
	part(
		"HalfA",
		Vector3.new(map.width - 1, 1.1, halfLength),
		Vector3.new(offsetX, map.floorY - 0.45, -halfCenter),
		map.halfAColor,
		arena
	)
	part(
		"HalfB",
		Vector3.new(map.width - 1, 1.1, halfLength),
		Vector3.new(offsetX, map.floorY - 0.45, halfCenter),
		map.halfBColor,
		arena
	)
	part(
		"Divider",
		Vector3.new(map.width, 1.2, 0.6),
		Vector3.new(offsetX, map.floorY - 0.4, 0),
		Color3.fromRGB(240, 240, 240),
		arena
	)

	-- Muretes decorativos, para se perceber o limite do campo.
	local wallHeight = 2
	local wallColor = Color3.fromRGB(58, 60, 66)
	part(
		"WallWest",
		Vector3.new(1, wallHeight, map.length),
		Vector3.new(offsetX - map.width / 2, map.floorY + wallHeight / 2, 0),
		wallColor,
		arena
	)
	part(
		"WallEast",
		Vector3.new(1, wallHeight, map.length),
		Vector3.new(offsetX + map.width / 2, map.floorY + wallHeight / 2, 0),
		wallColor,
		arena
	)
	part(
		"WallSouth",
		Vector3.new(map.width + 2, wallHeight, 1),
		Vector3.new(offsetX, map.floorY + wallHeight / 2, -map.length / 2),
		wallColor,
		arena
	)
	part(
		"WallNorth",
		Vector3.new(map.width + 2, wallHeight, 1),
		Vector3.new(offsetX, map.floorY + wallHeight / 2, map.length / 2),
		wallColor,
		arena
	)
end

-- Veste o campo de um slot com as cores da arena. Como cada partida tem o seu
-- slot em exclusivo, subir de arena vê-se mesmo no chão.
function MapService.applyTheme(slot: number, arena: RankConfig.Arena)
	local root = workspace:FindFirstChild(ARENA_NAME)
	local arenaFolder = if root then root:FindFirstChild(`Arena_{slot}`) else nil
	if not arenaFolder then
		return
	end

	local floor = arenaFolder:FindFirstChild("Floor")
	local halfA = arenaFolder:FindFirstChild("HalfA")
	local halfB = arenaFolder:FindFirstChild("HalfB")

	if floor and floor:IsA("BasePart") then
		floor.Color = arena.floorColor
	end
	if halfA and halfA:IsA("BasePart") then
		halfA.Color = arena.halfAColor
	end
	if halfB and halfB:IsA("BasePart") then
		halfB.Color = arena.halfBColor
	end
end

function MapService.start() end

return MapService
