--!strict
--[[
	SpellController — comprar feitiços na preparação e lançá-los na batalha.

	É a única coisa que o jogador faz com a batalha a correr, por isso tem de
	ser legível de relance: na preparação os botões mostram o custo, na batalha
	mostram quantas cargas restam e qual está escolhida.

	Lançar é escolher o feitiço e tocar no campo. Enquanto houver um escolhido,
	um círculo mostra a área que vai apanhar — ninguém deve descobrir o raio de
	um meteoro depois de o ter gasto.

	Como sempre, isto só manda intenções: quem valida a fase, a carga, o
	intervalo e a área é o servidor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Maps = require(Shared.Config.Maps)
local Spells = require(Shared.Config.Spells)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local SpellController = {}

type Card = {
	spellId: string,
	def: Spells.SpellDef,
	button: TextButton,
	label: TextLabel,
}

local map = Maps.default

local bar: Frame
local cards: { Card } = {}
local effectsFolder: Folder
local aimPart: BasePart? = nil

local selected: string? = nil

-- Quantas cargas há de cada feitiço, a partir do que o servidor confirmou.
local function chargesOf(spellId: string): number
	local count = 0
	for _, owned in State.spells do
		if owned == spellId then
			count += 1
		end
	end
	return count
end

-- Mira -------------------------------------------------------------------------

local function ensureAim(): BasePart
	local existing = aimPart
	if existing then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "SpellAim"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 8, 8)
	part.Parent = effectsFolder

	aimPart = part
	return part
end

local function hideAim()
	local part = aimPart
	if part then
		part.Transparency = 1
	end
end

local function showAim(x: number, z: number, def: Spells.SpellDef)
	local part = ensureAim()
	part.Size = Vector3.new(0.2, def.radius * 2, def.radius * 2)
	part.Color = def.color
	part.CFrame = CFrame.new(x + State.arenaOffsetX, map.floorY + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Transparency = 0.6
end

-- O efeito que se vê quando um feitiço cai: um disco que cresce e desaparece.
local function playEffect(payload: Types.SpellCastPayload)
	local def = Spells.get(payload.spellId)
	if not def then
		return
	end

	local part = Instance.new("Part")
	part.Name = "SpellEffect"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = def.color
	part.Transparency = 0.2
	part.Size = Vector3.new(0.4, def.radius * 0.6, def.radius * 0.6)
	part.CFrame = CFrame.new(payload.x + State.arenaOffsetX, map.floorY + 0.2, payload.z)
		* CFrame.Angles(0, 0, math.pi / 2)
	part.Parent = effectsFolder

	local grow = TweenService:Create(
		part,
		TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, def.radius * 2, def.radius * 2), Transparency = 1 }
	)
	grow:Play()
	grow.Completed:Connect(function()
		part:Destroy()
	end)
end

-- Barra -------------------------------------------------------------------------

local function refresh()
	local phase = State.phase
	local prep = State.canEditArmy()
	local battle = phase == "Battle" or phase == "Reveal"
	bar.Visible = prep or battle

	if not bar.Visible then
		selected = nil
		hideAim()
		return
	end

	for _, card in cards do
		local charges = chargesOf(card.spellId)
		local isSelected = selected == card.spellId

		if prep then
			-- Na preparação compra-se: o botão mostra o custo e quantos já há.
			card.label.Text = if charges > 0
				then `{Locale.spellName(card.spellId)} x{charges}`
				else `{Locale.spellName(card.spellId)}  {card.def.cost}`
			card.button.BackgroundColor3 = if charges > 0 then colors.panelLight else colors.panel
		else
			card.label.Text = `{Locale.spellName(card.spellId)} x{charges}`
			card.button.BackgroundColor3 = if isSelected
				then card.def.color
				elseif charges > 0 then colors.panelLight
				else colors.panel
		end

		card.button.AutoButtonColor = prep or charges > 0
		card.label.TextColor3 = if isSelected
			then Color3.fromRGB(24, 22, 18)
			elseif (prep or charges > 0) then colors.text
			else colors.textDim
	end

	-- Um feitiço sem cargas deixa de estar escolhido.
	local current = selected
	if current and chargesOf(current) == 0 then
		selected = nil
		hideAim()
	end
end

local function onCardPressed(card: Card)
	if State.canEditArmy() then
		Net.fireServer("BuySpell", card.spellId)
		return
	end

	-- Na batalha, escolher (ou desescolher) para lançar.
	if chargesOf(card.spellId) == 0 then
		return
	end
	selected = if selected == card.spellId then nil else card.spellId
	if not selected then
		hideAim()
	end
	refresh()
end

-- Lançamento --------------------------------------------------------------------

local function arenaPointFrom(screenPosition: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local directionY = ray.Direction.Y
	if math.abs(directionY) < 1e-5 then
		return nil
	end

	local distance = (map.floorY - ray.Origin.Y) / directionY
	if distance <= 0 then
		return nil
	end

	local point = ray.Origin + ray.Direction * distance
	return Vector2.new(point.X - State.arenaOffsetX, point.Z)
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or State.phase ~= "Battle" then
		return
	end

	local spellId = selected
	if not spellId then
		return
	end

	local inputType = input.UserInputType
	if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
		return
	end

	local point = arenaPointFrom(input.Position)
	if not point then
		return
	end

	Net.fireServer("CastSpell", spellId, point.X, point.Y)
end

local function onInputChanged(input: InputObject, _processed: boolean)
	local spellId = selected
	if not spellId or State.phase ~= "Battle" then
		return
	end

	local inputType = input.UserInputType
	if inputType ~= Enum.UserInputType.MouseMovement and inputType ~= Enum.UserInputType.Touch then
		return
	end

	local def = Spells.get(spellId)
	local point = arenaPointFrom(input.Position)
	if def and point then
		showAim(point.X, point.Y, def)
	end
end

function SpellController.init()
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "SpellEffects"
	effectsFolder.Parent = workspace

	-- Por cima da coluna de botões, à direita: é lá que a mão já está.
	bar = make("Frame", {
		Name = "Spells",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -150),
		Size = UDim2.new(0, 132, 0, 76),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = UIController.getRoot(),
	}) :: Frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = bar

	for index, spellId in Spells.order do
		local def = Spells.get(spellId)
		if def then
			local button = make("TextButton", {
				Name = `Spell_{spellId}`,
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundColor3 = colors.panel,
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = index,
				Parent = bar,
			}) :: TextButton
			UIUtil.corner(button, 8)

			local label = make("TextLabel", {
				Name = "Label",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Font = UIUtil.font,
				Text = "",
				TextColor3 = colors.text,
				TextSize = 14,
				Parent = button,
			}) :: TextLabel

			local card: Card = { spellId = spellId, def = def, button = button, label = label }
			button.MouseButton1Click:Connect(function()
				onCardPressed(card)
			end)
			table.insert(cards, card)
		end
	end
end

function SpellController.start()
	State.onArmy(refresh)
	State.onMatchState(refresh)
	State.onSpellCast(playEffect)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)

	-- Sem feitiço escolhido não há mira no chão.
	RunService.RenderStepped:Connect(function()
		if not selected then
			hideAim()
		end
	end)

	refresh()
end

return SpellController
