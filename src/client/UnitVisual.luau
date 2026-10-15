--!strict
--[[
	UnitVisual — o corpo de uma unidade, no cliente.

	Cada unidade é um bonequinho feito de peças (tronco, cabeça, dois braços,
	duas pernas, arma e escudo), ao estilo do Roblox, montado em código a partir
	das medidas de Config/Troops. Nada de Humanoids: tudo ancorado e movido por
	CFrame, que é o que permite ter 80 destes em campo a 60 fps.

	Desenho de performance, que é o que manda aqui:

	- Quem não está a animar move-se com **um** `PivotTo` — uma chamada por
	  unidade e por frame, as peças vão todas atrás.
	- Só anima os membros quem está a andar ou a atacar, e no máximo
	  `maxAnimatedUnits` ao mesmo tempo. Acima disso ficam em pose parada: num
	  campo com 80 unidades ninguém repara, e o telemóvel agradece.

	A cor do corpo é a da equipa; a da tropa aparece na crista e na arma, para
	se distinguir soldado de arqueiro de relance sem ler nada.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)
local Locale = require(Shared.Locale)

local UnitVisual = {}

export type Visual = {
	model: Model,
	root: BasePart,
	-- Membros animados e a pose base de cada um (relativa aos pés).
	limbs: { BasePart },
	limbOffsets: { CFrame },
	healthFill: Frame?,
	def: Types.TroopDef,
	baseColor: Color3,
	frozen: boolean,
	-- Fase do passo, para as pernas não andarem todas em sincronia.
	phase: number,
	animated: boolean,
}

export type Options = {
	ghost: boolean?,
	healthBar: boolean?,
	label: boolean?,
}

local map = Maps.default

-- Quantas unidades podem animar os membros ao mesmo tempo.
local MAX_ANIMATED = 28
local animatedCount = 0

local SKIN = Color3.fromRGB(226, 198, 150)
local DARK = Color3.fromRGB(58, 56, 64)

local function piece(name: string, size: Vector3, color: Color3, parent: Instance, ghost: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = if ghost then Enum.Material.ForceField else Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Transparency = if ghost then 0.45 else 0
	part.Parent = parent
	return part
end

local function buildBillboard(part: BasePart, def: Types.TroopDef, withHealthBar: boolean): Frame?
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Tag"
	billboard.Size = UDim2.fromOffset(46, 22)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, def.height * 0.55, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = 260
	billboard.LightInfluence = 0
	billboard.Parent = part

	local initial = Instance.new("TextLabel")
	initial.Name = "Initial"
	initial.BackgroundTransparency = 1
	initial.Size = UDim2.new(1, 0, 0.55, 0)
	initial.Font = Enum.Font.GothamBold
	initial.Text = string.upper(string.sub(Locale.troopName(def.id), 1, 1))
	initial.TextColor3 = def.color
	initial.TextStrokeTransparency = 0.3
	initial.TextScaled = true
	initial.Parent = billboard

	if not withHealthBar then
		return nil
	end

	local track = Instance.new("Frame")
	track.Name = "HealthTrack"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, 0)
	track.Size = UDim2.new(0.92, 0, 0.26, 0)
	track.BackgroundColor3 = Color3.fromRGB(16, 16, 20)
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

-- A arma de cada tropa. Vem de Config/Troops; sem arma definida, fica de mãos
-- a abanar (o curandeiro, por exemplo, leva cajado).
local function buildWeapon(def: Types.TroopDef, model: Model, ghost: boolean): (Part?, CFrame)
	local weapon = def.weapon
	if not weapon or weapon == "none" then
		return nil, CFrame.new()
	end

	local h = def.height
	local color = def.color

	if weapon == "sword" then
		local blade = piece("Weapon", Vector3.new(0.14, h * 0.42, 0.3), color, model, ghost)
		return blade, CFrame.new(0, h * 0.1, -0.1)
	elseif weapon == "spear" then
		local shaft = piece("Weapon", Vector3.new(0.12, h * 0.75, 0.12), color, model, ghost)
		return shaft, CFrame.new(0, h * 0.18, -0.1)
	elseif weapon == "bow" then
		local bow = piece("Weapon", Vector3.new(0.12, h * 0.4, 0.5), color, model, ghost)
		return bow, CFrame.new(0, 0, -0.25)
	elseif weapon == "staff" then
		local staff = piece("Weapon", Vector3.new(0.12, h * 0.62, 0.12), color, model, ghost)
		staff.Material = if ghost then Enum.Material.ForceField else Enum.Material.Neon
		return staff, CFrame.new(0, h * 0.14, -0.1)
	end

	local club = piece("Weapon", Vector3.new(0.4, h * 0.3, 0.4), color, model, ghost)
	return club, CFrame.new(0, h * 0.08, -0.15)
end

function UnitVisual.create(def: Types.TroopDef, teamColor: Color3, parent: Instance, options: Options): Visual
	local ghost = options.ghost == true

	local h = def.height
	local w = def.radius * 1.5

	local model = Instance.new("Model")
	model.Name = `Unit_{def.id}`

	-- Proporções: pernas 0,34 · tronco 0,36 · cabeça 0,24 da altura.
	local legHeight = h * 0.34
	local torsoHeight = h * 0.36
	local headSize = h * 0.24

	local torso = piece("Torso", Vector3.new(w, torsoHeight, w * 0.5), teamColor, model, ghost)
	local head = piece("Head", Vector3.new(headSize, headSize, headSize), SKIN, model, ghost)
	local crest = piece("Crest", Vector3.new(headSize * 1.1, headSize * 0.25, headSize * 1.1), def.color, model, ghost)
	local armLeft = piece("ArmLeft", Vector3.new(w * 0.26, torsoHeight * 0.92, w * 0.26), SKIN, model, ghost)
	local armRight = piece("ArmRight", Vector3.new(w * 0.26, torsoHeight * 0.92, w * 0.26), SKIN, model, ghost)
	local legLeft = piece("LegLeft", Vector3.new(w * 0.3, legHeight, w * 0.3), DARK, model, ghost)
	local legRight = piece("LegRight", Vector3.new(w * 0.3, legHeight, w * 0.3), DARK, model, ghost)

	-- Poses relativas aos pés (y = 0 é o chão).
	local torsoY = legHeight + torsoHeight / 2
	local torsoOffset = CFrame.new(0, torsoY, 0)
	local headOffset = CFrame.new(0, legHeight + torsoHeight + headSize / 2, 0)
	local crestOffset = CFrame.new(0, legHeight + torsoHeight + headSize * 1.05, 0)
	local armOffset = torsoHeight / 2 - torsoHeight * 0.46
	local limbOffsets = {
		CFrame.new(-(w / 2 + w * 0.14), torsoY + armOffset, 0),
		CFrame.new(w / 2 + w * 0.14, torsoY + armOffset, 0),
		CFrame.new(-w * 0.22, legHeight / 2, 0),
		CFrame.new(w * 0.22, legHeight / 2, 0),
	}

	model.PrimaryPart = torso

	local weapon, weaponOffset = buildWeapon(def, model, ghost)

	-- Escudo no braço esquerdo, para as tropas que o levam.
	local shield: Part? = nil
	if def.shield then
		shield = piece("Shield", Vector3.new(0.18, torsoHeight * 0.9, w * 0.62), def.color, model, ghost)
	end

	model.Parent = parent

	local visual: Visual = {
		model = model,
		root = torso,
		limbs = { armLeft, armRight, legLeft, legRight },
		limbOffsets = limbOffsets,
		healthFill = nil,
		def = def,
		baseColor = teamColor,
		frozen = false,
		-- Cada unidade começa o passo noutro ponto: um pelotão em que todos
		-- andam em sincronia parece um só boneco repetido.
		phase = math.random() * math.pi * 2,
		animated = false,
	}

	if options.label ~= false then
		visual.healthFill = buildBillboard(head, def, options.healthBar == true)
	end

	-- O PivotTo trata de tudo de uma vez; o pivot é o tronco.
	torso.CFrame = torsoOffset
	head.CFrame = headOffset
	crest.CFrame = crestOffset
	armLeft.CFrame = limbOffsets[1]
	armRight.CFrame = limbOffsets[2]
	legLeft.CFrame = limbOffsets[3]
	legRight.CFrame = limbOffsets[4]
	if weapon then
		weapon.CFrame = limbOffsets[2] * weaponOffset
	end
	if shield then
		shield.CFrame = limbOffsets[1] * CFrame.new(-w * 0.1, 0, 0)
	end

	return visual
end

-- Põe a unidade no sítio. `speed` e `attacking` decidem se vale a pena animar.
function UnitVisual.setPosition(visual: Visual, x: number, z: number, yaw: number?, moving: boolean?, attacking: boolean?)
	local base = CFrame.new(x, map.floorY, z) * CFrame.Angles(0, yaw or 0, 0)

	-- Um PivotTo move o boneco inteiro: é a parte barata.
	visual.model:PivotTo(base * CFrame.new(0, visual.def.height * 0.34 + visual.def.height * 0.18, 0))

	local wantsAnimation = (moving == true or attacking == true) and not visual.frozen
	if not wantsAnimation then
		if visual.animated then
			visual.animated = false
			animatedCount -= 1
		end
		return
	end

	if not visual.animated then
		if animatedCount >= MAX_ANIMATED then
			-- Cheio: fica em pose parada, que a esta distância ninguém nota.
			return
		end
		visual.animated = true
		animatedCount += 1
	end

	visual.phase += if attacking then 0.45 else 0.22
	local swing = math.sin(visual.phase) * (if attacking then 0.1 else 0.55)
	local armSwing = if attacking then math.sin(visual.phase) * 1.1 - 0.6 else -swing

	local limbs = visual.limbs
	local offsets = visual.limbOffsets
	limbs[1].CFrame = base * offsets[1] * CFrame.Angles(armSwing, 0, 0)
	limbs[2].CFrame = base * offsets[2] * CFrame.Angles(if attacking then armSwing else swing, 0, 0)
	limbs[3].CFrame = base * offsets[3] * CFrame.Angles(swing, 0, 0)
	limbs[4].CFrame = base * offsets[4] * CFrame.Angles(-swing, 0, 0)
end

-- Usado para a unidade que se está a arrastar ficar translúcida.
function UnitVisual.setTransparency(visual: Visual, transparency: number)
	for _, part in visual.model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = transparency
		end
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

-- Congelado: o corpo fica azulado e baço, para se perceber de relance quem
-- está parado por causa de um feitiço e não por falta de alvo.
function UnitVisual.setFrozen(visual: Visual, frozen: boolean)
	if visual.frozen == frozen then
		return
	end
	visual.frozen = frozen
	visual.root.Color = if frozen then Color3.fromRGB(150, 200, 236) else visual.baseColor
	visual.root.Material = if frozen then Enum.Material.Ice else Enum.Material.SmoothPlastic
end

-- Verde quando a posicao e valida, vermelho quando nao e.
function UnitVisual.setGhostValid(visual: Visual, valid: boolean)
	local color = if valid then Color3.fromRGB(120, 220, 140) else Color3.fromRGB(226, 94, 86)
	for _, part in visual.model:GetChildren() do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

function UnitVisual.destroy(visual: Visual)
	if visual.animated then
		visual.animated = false
		animatedCount -= 1
	end
	visual.model:Destroy()
end

return UnitVisual
