--!strict
--[[
	LeaderboardController — a classificação global, vista do lobby.

	Um botão no canto abre a lista; o servidor serve-a de uma cópia que
	atualiza de 5 em 5 minutos. Não é um placar ao vivo, é para se ver onde se
	está — e é por isso que pedir ao abrir chega.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local LeaderboardConfig = require(Shared.Config.Leaderboard)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local LeaderboardController = {}

type Row = {
	frame: Frame,
	rankLabel: TextLabel,
	nameLabel: TextLabel,
	trophyLabel: TextLabel,
}

local openButton: TextButton
local panel: Frame
local emptyLabel: TextLabel
local selfLabel: TextLabel
local rows: { Row } = {}

local open = false

local function refreshVisibility()
	local inLobby = State.phase == "Lobby"
	openButton.Visible = inLobby
	panel.Visible = inLobby and open
end

local function render(payload: Types.LeaderboardPayload)
	local entries = payload.entries
	emptyLabel.Visible = #entries == 0
	selfLabel.Text = Locale.get("leaderboard_self", payload.selfTrophies)

	for index, row in rows do
		local entry = entries[index]
		row.frame.Visible = entry ~= nil
		if entry then
			row.rankLabel.Text = `{entry.rank}.`
			row.nameLabel.Text = entry.name
			row.trophyLabel.Text = tostring(entry.trophies)

			-- O próprio fica destacado, para se encontrar sem procurar.
			local isSelf = entry.userId == State.userId
			row.nameLabel.TextColor3 = if isSelf then colors.accent else colors.text
			row.rankLabel.TextColor3 = if isSelf then colors.accent else colors.textDim
		end
	end
end

local function buildRow(parent: Instance, order: number): Row
	local frame = make("Frame", {
		Name = `Row{order}`,
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Visible = false,
		Parent = parent,
	}) :: Frame

	local rankLabel = make("TextLabel", {
		Name = "Rank",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 34, 1, 0),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	}) :: TextLabel

	local nameLabel = make("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 34, 0, 0),
		Size = UDim2.new(1, -110, 1, 0),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = frame,
	}) :: TextLabel

	local trophyLabel = make("TextLabel", {
		Name = "Trophies",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 1, 0),
		BackgroundTransparency = 1,
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	}) :: TextLabel

	return { frame = frame, rankLabel = rankLabel, nameLabel = nameLabel, trophyLabel = trophyLabel }
end

function LeaderboardController.init()
	local root = UIController.getRoot()

	openButton = make("TextButton", {
		Name = "OpenLeaderboard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 132, 0, 36),
		BackgroundColor3 = colors.panelLight,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = Locale.get("leaderboard"),
		TextColor3 = colors.text,
		TextSize = 15,
		Visible = false,
		Parent = root,
	}) :: TextButton
	UIUtil.corner(openButton, 8)

	panel = make("Frame", {
		Name = "Leaderboard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 380),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.02,
		BorderSizePixel = 0,
		Visible = false,
		-- Por cima do painel do lobby.
		ZIndex = 5,
		Parent = root,
	}) :: Frame
	UIUtil.corner(panel, 14)
	UIUtil.padding(panel, 16)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(420, 380)
	constraint.Parent = panel

	make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Font = UIUtil.font,
		Text = Locale.get("leaderboard"),
		TextColor3 = colors.accent,
		TextSize = 20,
		ZIndex = 5,
		Parent = panel,
	})

	local list = make("Frame", {
		Name = "Rows",
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -110),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = panel,
	}) :: Frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list

	for index = 1, LeaderboardConfig.topCount do
		table.insert(rows, buildRow(list, index))
	end

	emptyLabel = make("TextLabel", {
		Name = "Empty",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Font = UIUtil.fontRegular,
		Text = Locale.get("leaderboard_empty"),
		TextColor3 = colors.textDim,
		TextSize = 15,
		Visible = false,
		ZIndex = 6,
		Parent = list,
	}) :: TextLabel

	selfLabel = make("TextLabel", {
		Name = "Self",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -44),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 14,
		ZIndex = 5,
		Parent = panel,
	}) :: TextLabel

	local closeButton = make("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = Locale.get("leaderboard_close"),
		TextColor3 = colors.text,
		TextSize = 15,
		ZIndex = 5,
		Parent = panel,
	}) :: TextButton
	UIUtil.corner(closeButton, 8)

	closeButton.MouseButton1Click:Connect(function()
		open = false
		refreshVisibility()
	end)
end

function LeaderboardController.start()
	openButton.MouseButton1Click:Connect(function()
		open = true
		refreshVisibility()
		-- Pede-se ao abrir: a lista do servidor so muda de 5 em 5 minutos.
		Net.fireServer("RequestLeaderboard")
	end)

	State.onLeaderboard(render)
	State.onMatchState(refreshVisibility)

	refreshVisibility()
end

return LeaderboardController
