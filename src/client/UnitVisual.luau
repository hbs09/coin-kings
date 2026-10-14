--!strict
--[[
	UnitVisual — o corpo de uma unidade, no cliente.

	Uma unidade = uma Part ancorada (sem Humanoid), movida por CFrame, com um
	BillboardGui opcional para a inicial da tropa e a barra de vida. As medidas
	e as cores vem todas de Config/Troops: isto so desenha.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)
local Locale = require(Shared.Locale)

local UnitVisual = {}

export type Visual = {
	part: BasePart,
	healthFill: Frame?,
	def: Types.TroopDef,
	pivotY: number,
}

export type Options = {
	ghost: boolean?,
	healthBar: boolean?,
	label: boolean?,
}

local map = Maps.default

local function buildBillboard(part: BasePart, def: Types.TroopDef, withHealthBar: boolean): Frame?
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromOffset(44, 22)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.height * 0.7, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 260
	billboard.LightInfluence = 0
	billboard.Parent = part

	local initial = Instance.new("TextLabel")
	initial.Name = "Initial"
	initial.BackgroundTransparency = 1
	initial.Size = UDim2.new(1, 0, 0.6, 0)
	initial.Font = Enum.Font.GothamBold
	initial.Text = string.upper(string.sub(Locale.troopName(def.id), 1, 1))
	initial.TextColor3 = def.color
	initial.TextStrokeTransparency = 0.4
	initial.TextScaled = true
	initial.Parent = billboard

	if not withHealthBar then
		return nil
	end

	local track = Instance.new("Frame")
	track.Name = "HealthTrack"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.new(0.9, 0, 0.22, 0)
	track.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	track.BorderSizePixel = 0
	track.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "HealthFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(104, 200, 132)
	fill.BorderSizePixel = 0
	fill.Parent = track

	return fill
end

function UnitVisual.create(def: Types.TroopDef, teamColor: Color3, parent: Instance, options: Options): Visual
	local ghost = options.ghost == true

	local part = Instance.new("Part")
	part.Name = `Unit_{def.id}`
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = not ghost
	part.Material = if ghost then Enum.Material.ForceField else Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(def.radius * 1.7, def.height, def.radius * 1.7)
	part.Color = teamColor
	part.Transparency = if ghost then 0.45 else 0
	part.Parent = parent

	local healthFill: Frame? = nil
	if options.label ~= false then
		healthFill = buildBillboard(part, def, options.healthBar == true)
	end

	local visual: Visual = {
		part = part,
		healthFill = healthFill,
		def = def,
		pivotY = map.floorY + def.height / 2,
	}
	return visual
end

function UnitVisual.setPosition(visual: Visual, x: number, z: number, yaw: number?)
	local position = CFrame.new(x, visual.pivotY, z)
	if yaw then
		visual.part.CFrame = position * CFrame.Angles(0, yaw, 0)
	else
		visual.part.CFrame = position
	end
end

function UnitVisual.setHealth(visual: Visual, fraction: number)
	local fill = visual.healthFill
	if not fill then
		return
	end
	local clamped = math.clamp(fraction, 0, 1)
	fill.Size = UDim2.fromScale(clamped, 1)
	fill.BackgroundColor3 = if clamped > 0.5
		then Color3.fromRGB(104, 200, 132)
		elseif clamped > 0.25 then Color3.fromRGB(240, 196, 92)
		else Color3.fromRGB(226, 94, 86)
end

-- Verde quando a posicao e valida, vermelho quando nao e.
function UnitVisual.setGhostValid(visual: Visual, valid: boolean)
	visual.part.Color = if valid then Color3.fromRGB(120, 220, 140) else Color3.fromRGB(226, 94, 86)
end

function UnitVisual.destroy(visual: Visual)
	visual.part:Destroy()
end

return UnitVisual
