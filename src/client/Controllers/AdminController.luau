--!strict
--[[
	AdminController — o painel de atalhos da fase de testes.

	Só aparece depois de o servidor confirmar que este jogador é admin
	(Config/Admin). Mesmo assim, nada aqui decide nada: cada botão manda um
	pedido e é o servidor que o valida outra vez.

	Começa fechado, num botão pequeno, para não tapar o campo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local AdminConfig = require(Shared.Config.Admin)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local AdminController = {}

local root: Frame
local toggle: TextButton
local list: Frame
local speedButtons: { [number]: TextButton } = {}

local enabled = false
local open = false
local currentSpeed = 1

local function send(command: string, value: number?)
	if value then
		Net.fireServer("AdminCommand", command, value)
	else
		Net.fireServer("AdminCommand", command)
	end
end

local function refresh()
	root.Visible = enabled
	list.Visible = enabled and open
	toggle.Text = if open then "ADMIN ▾" else "ADMIN ▸"

	for speed, button in speedButtons do
		local active = speed == currentSpeed
		button.BackgroundColor3 = if active then colors.accent else colors.panelLight
		button.TextColor3 = if active then Color3.fromRGB(28, 24, 12) else colors.text
	end
end

local function button(parent: Instance, name: string, label: string, order: number): TextButton
	local instance = make("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = label,
		TextColor3 = colors.text,
		TextSize = 13,
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	UIUtil.corner(instance, 6)
	return instance
end

function AdminController.init()
	root = make("Frame", {
		Name = "Admin",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(0, 132, 0, 220),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = UIController.getRoot(),
	}) :: Frame

	toggle = make("TextButton", {
		Name = "Toggle",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.font,
		Text = "ADMIN ▸",
		TextColor3 = colors.bad,
		TextSize = 13,
		Parent = root,
	}) :: TextButton
	UIUtil.corner(toggle, 6)

	list = make("Frame", {
		Name = "List",
		Position = UDim2.new(0, 0, 0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	}) :: Frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	-- Velocidade da simulacao, lado a lado.
	local speedRow = make("Frame", {
		Name = "SpeedRow",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = list,
	}) :: Frame

	local speedLayout = Instance.new("UIListLayout")
	speedLayout.FillDirection = Enum.FillDirection.Horizontal
	speedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	speedLayout.Padding = UDim.new(0, 4)
	speedLayout.Parent = speedRow

	for index, speed in AdminConfig.speeds do
		local instance = make("TextButton", {
			Name = `Speed{speed}`,
			Size = UDim2.new(0, 41, 1, 0),
			BackgroundColor3 = colors.panelLight,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = UIUtil.font,
			Text = `x{speed}`,
			TextColor3 = colors.text,
			TextSize = 13,
			LayoutOrder = index,
			Parent = speedRow,
		}) :: TextButton
		UIUtil.corner(instance, 6)
		instance.MouseButton1Click:Connect(function()
			currentSpeed = speed
			send("speed", speed)
			refresh()
		end)
		speedButtons[speed] = instance
	end

	local skipButton = button(list, "Skip", Locale.get("admin_skip"), 2)
	local goldButton = button(list, "Gold", Locale.get("admin_gold", AdminConfig.goldGrant), 3)
	local trophyButton = button(list, "Trophies", Locale.get("admin_trophies", AdminConfig.trophyGrant), 4)
	local trophyDownButton = button(list, "TrophiesDown", Locale.get("admin_trophies", -AdminConfig.trophyGrant), 5)
	local resetButton = button(list, "Reset", Locale.get("admin_reset"), 6)

	toggle.MouseButton1Click:Connect(function()
		open = not open
		refresh()
	end)
	skipButton.MouseButton1Click:Connect(function()
		send("skipPhase")
	end)
	goldButton.MouseButton1Click:Connect(function()
		send("gold")
	end)
	trophyButton.MouseButton1Click:Connect(function()
		send("trophies", AdminConfig.trophyGrant)
	end)
	trophyDownButton.MouseButton1Click:Connect(function()
		send("trophies", -AdminConfig.trophyGrant)
	end)
	resetButton.MouseButton1Click:Connect(function()
		send("resetProfile")
	end)
end

function AdminController.start()
	State.onAdminState(function(isEnabled: boolean)
		enabled = isEnabled
		refresh()
	end)

	refresh()
end

return AdminController
