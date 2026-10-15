--!strict
--[[
	ShopController — os cartoes da loja.

	A lista de tropas vem de Config/Match.troopPool e os custos de Config/Troops.
	Escolher um cartao e so uma intencao local: o ouro e descontado quando o
	servidor aceita a colocacao.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Locale = require(Shared.Locale)
local Troops = require(Shared.Config.Troops)

local State = require(script.Parent.Parent.State)
local UnitVisual = require(script.Parent.Parent.UnitVisual)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local ShopController = {}

type Card = {
	troopId: Types.TroopId,
	def: Types.TroopDef,
	button: TextButton,
	nameLabel: TextLabel,
	costLabel: TextLabel,
	costPill: Frame,
	highlight: UIStroke,
}

local cards: { Card } = {}
local selected: Types.TroopId? = nil
local sizeConstraint: UISizeConstraint? = nil

-- O PlacementController regista-se aqui para poder arrastar direto do cartao
-- para o campo, num gesto so. E o ShopController a avisar, e nao o contrario,
-- para nao haver dependencia circular entre os dois.
type DragListener = (troopId: Types.TroopId, input: InputObject) -> ()
local dragListeners: { DragListener } = {}

-- O arrasto em curso. No toque, quando o dedo **entra** noutro elemento da
-- interface, esse elemento recebe um InputBegan novo — ou seja, cada cartao
-- por onde o dedo passa julga que o toque comecou ali. Sem isto, arrastar o
-- soldado por cima do arqueiro trocava a tropa a meio do gesto.
local activeDrag: InputObject? = nil

local function dragInProgress(): boolean
	local current = activeDrag
	if not current then
		return false
	end
	-- Rede de seguranca: se o toque ja acabou sem passar pelo InputEnded,
	-- nao fica um arrasto fantasma a bloquear a loja.
	if current.UserInputState == Enum.UserInputState.End then
		activeDrag = nil
		return false
	end
	return true
end

function ShopController.onCardDragStart(listener: DragListener)
	table.insert(dragListeners, listener)
end

local function isAvailable(troopId: Types.TroopId): boolean
	return table.find(State.troopPool, troopId) ~= nil
end

function ShopController.getSelected(): Types.TroopId?
	return selected
end

function ShopController.clearSelection()
	selected = nil
	ShopController.refresh()
end

local function select(troopId: Types.TroopId)
	-- Clicar numa bloqueada nao faz nada: ve-se, nao se usa.
	if not isAvailable(troopId) then
		return
	end
	-- Escolher sem alternar: quem arrasta de um cartao espera sempre sair com
	-- essa tropa na mao, nao com a selecao desligada.
	selected = troopId
	ShopController.refresh()
end

function ShopController.refresh()
	-- O carrossel e so o que se pode usar agora. O que ainda nao e nosso vive
	-- no catalogo, nao no meio das tropas que estamos a tentar comprar.
	local visibleCount = 0

	for _, card in cards do
		local available = isAvailable(card.troopId)
		card.button.Visible = available
		if not available then
			continue
		end
		visibleCount += 1

		local affordable = State.gold >= card.def.cost
		local isSelected = selected == card.troopId

		-- Escolhido: contorno aceso. Sem ouro: tudo apagado, incluindo a
		-- pastilha do custo, que e onde o olho vai primeiro.
		card.highlight.Transparency = if isSelected then 0 else 1
		card.button.BackgroundTransparency = if affordable then 0 else 0.45
		card.nameLabel.TextColor3 = if affordable then colors.text else colors.textDim
		card.costPill.BackgroundColor3 = if affordable then colors.accent else colors.panelLight
		card.costLabel.TextColor3 = if affordable then colors.textOnLight else colors.textDim
	end

	-- Se a tropa escolhida deixou de estar disponivel, desmarca-a.
	local current = selected
	if current and not isAvailable(current) then
		selected = nil
	end

	-- O painel acompanha o numero de cartoes a vista: com tres tropas nao fica
	-- um retangulo vazio com espaco para oito.
	local constraint = sizeConstraint
	if constraint then
		constraint.MaxSize = Vector2.new(math.max(1, visibleCount) * 112 + 8, math.huge)
	end
end

-- O retrato do cartao e o proprio boneco da tropa, numa ViewportFrame: a arte
-- do cartao e exatamente o que vai aparecer no campo, sem desenhar nada.
local function buildPortrait(parent: Instance, def: Types.TroopDef)
	local viewport = make("ViewportFrame", {
		Name = "Portrait",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, -12, 0, 44),
		BackgroundColor3 = Color3.fromRGB(18, 20, 28),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Ambient = Color3.fromRGB(190, 190, 200),
		LightColor = Color3.fromRGB(255, 252, 240),
		LightDirection = Vector3.new(-0.4, -1, -0.6),
		Parent = parent,
	}) :: ViewportFrame
	UIUtil.corner(viewport, 8)

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local visual = UnitVisual.create(def, Color3.fromRGB(104, 142, 204), viewport, { label = false })
	visual.model:PivotTo(CFrame.new(0, def.height * 0.52, 0) * CFrame.Angles(0, math.rad(205), 0))

	-- A camara afasta-se conforme a altura da tropa, para o gigante caber e o
	-- arqueiro nao ficar perdido ao longe.
	local distance = def.height * 1.45
	camera.CFrame = CFrame.lookAt(
		Vector3.new(distance * 0.55, def.height * 0.75, distance),
		Vector3.new(0, def.height * 0.45, 0)
	)
end

local function buildCard(parent: Instance, troopId: Types.TroopId, orderIndex: number)
	local def = Troops.get(troopId)
	if not def then
		return
	end

	local button = make("TextButton", {
		Name = `Card_{troopId}`,
		Size = UDim2.new(0, 104, 1, 0),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = orderIndex,
		Parent = parent,
	}) :: TextButton
	UIUtil.corner(button, 10)
	UIUtil.gradient(button, colors.panelTop, colors.panel)

	-- O contorno acende quando o cartao esta escolhido.
	local highlight = UIUtil.stroke(button, 2.5, colors.accent, 1)

	buildPortrait(button, def)

	local nameLabel = make("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 4, 0, 52),
		Size = UDim2.new(1, -8, 0, 14),
		Font = UIUtil.font,
		Text = Locale.troopName(troopId),
		TextColor3 = colors.text,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	}) :: TextLabel

	-- Pastilha do custo: o numero que mais se olha ao comprar.
	local costPill = make("Frame", {
		Name = "Cost",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, -16, 0, 22),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Parent = button,
	}) :: Frame
	UIUtil.corner(costPill, 11)
	UIUtil.gradient(costPill, colors.accent, colors.accentDeep)

	local costLabel = make("TextLabel", {
		Name = "Value",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = UIUtil.fontDisplay,
		Text = tostring(def.cost),
		TextColor3 = colors.textOnLight,
		TextSize = 15,
		Parent = costPill,
	}) :: TextLabel

	-- InputBegan em vez de MouseButton1Click: precisamos do InputObject para
	-- seguir o mesmo toque ate ao campo.
	button.InputBegan:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		if inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch then
			return
		end
		if not isAvailable(troopId) then
			return
		end
		if dragInProgress() then
			return
		end

		activeDrag = input
		select(troopId)
		for _, listener in dragListeners do
			listener(troopId, input)
		end
	end)

	table.insert(cards, {
		troopId = troopId,
		def = def,
		button = button,
		nameLabel = nameLabel,
		costLabel = costLabel,
		costPill = costPill,
		highlight = highlight,
	})
end

function ShopController.init()
	local container = UIController.getShopContainer()

	-- Com 8 tropas os cartoes nao cabem num telemovel: deslizam na horizontal.
	local scroller = make("ScrollingFrame", {
		Name = "Cards",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageTransparency = 0.4,
		Parent = container,
	}) :: ScrollingFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroller

	local orderIndex = 0
	for _, troopId in Troops.order do
		orderIndex += 1
		buildCard(scroller, troopId, orderIndex)
	end

	-- O tamanho real e acertado no refresh, conforme as tropas a vista.
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(math.max(1, orderIndex) * 112 + 8, math.huge)
	constraint.Parent = container
	sizeConstraint = constraint
end

function ShopController.start()
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == activeDrag then
			activeDrag = nil
		end
	end)

	State.onArmy(function()
		ShopController.refresh()
	end)

	State.onMatchState(function()
		if not State.canEditArmy() then
			selected = nil
		end
		ShopController.refresh()
	end)

	ShopController.refresh()
end

return ShopController
