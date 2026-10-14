--!strict
--[[
	ShopController — os cartoes da loja.

	A lista de tropas vem de Config/Match.troopPool e os custos de Config/Troops.
	Escolher um cartao e so uma intencao local: o ouro e descontado quando o
	servidor aceita a colocacao.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Locale = require(Shared.Locale)
local Troops = require(Shared.Config.Troops)
local MatchConfig = require(Shared.Config.Match)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local ShopController = {}

type Card = {
	troopId: Types.TroopId,
	def: Types.TroopDef,
	button: TextButton,
	costLabel: TextLabel,
}

local cards: { Card } = {}
local selected: Types.TroopId? = nil

function ShopController.getSelected(): Types.TroopId?
	return selected
end

function ShopController.clearSelection()
	selected = nil
	ShopController.refresh()
end

local function select(troopId: Types.TroopId)
	selected = if selected == troopId then nil else troopId
	ShopController.refresh()
end

function ShopController.refresh()
	for _, card in cards do
		local affordable = State.gold >= card.def.cost
		local isSelected = selected == card.troopId

		card.button.BackgroundColor3 = if isSelected
			then colors.accent
			elseif affordable then colors.panelLight
			else Color3.fromRGB(30, 32, 38)
		card.button.TextColor3 = if isSelected then Color3.fromRGB(28, 24, 12) else colors.text
		card.costLabel.TextColor3 = if isSelected
			then Color3.fromRGB(28, 24, 12)
			elseif affordable then colors.accent
			else colors.textDim
	end
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
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		LayoutOrder = orderIndex,
		Parent = parent,
	}) :: TextButton
	UIUtil.corner(button, 10)

	-- Mancha com a cor da tropa, para a reconhecer no campo.
	local swatch = make("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 34, 0, 34),
		BackgroundColor3 = def.color,
		BorderSizePixel = 0,
		Parent = button,
	}) :: Frame
	UIUtil.corner(swatch, 17)

	make("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 46),
		Size = UDim2.new(1, -4, 0, 20),
		Font = UIUtil.fontRegular,
		Text = Locale.troopName(troopId),
		TextColor3 = colors.text,
		TextSize = 14,
		TextScaled = false,
		Parent = button,
	})

	local costLabel = make("TextLabel", {
		Name = "Cost",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 66),
		Size = UDim2.new(1, 0, 0, 22),
		Font = UIUtil.font,
		Text = tostring(def.cost),
		TextColor3 = colors.accent,
		TextSize = 18,
		Parent = button,
	}) :: TextLabel

	button.MouseButton1Click:Connect(function()
		select(troopId)
	end)

	table.insert(cards, { troopId = troopId, def = def, button = button, costLabel = costLabel })
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
		if MatchConfig.isTroopAvailable(troopId) then
			orderIndex += 1
			buildCard(scroller, troopId, orderIndex)
		end
	end

	-- Em ecras largos o painel encolhe para o tamanho dos cartoes, em vez de
	-- ficar um retangulo vazio enorme.
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(math.max(1, orderIndex) * 112 + 8, math.huge)
	constraint.Parent = container
end

function ShopController.start()
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
