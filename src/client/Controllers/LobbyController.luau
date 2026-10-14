--!strict
--[[
	LobbyController — o ecrã onde se escolhe o que jogar.

	Duas opções: a campanha (lista de capítulos, com o seguinte a abrir quando
	o anterior estiver feito) e o PvP (entrar na fila).

	Ninguém é emparelhado sem pedir: quem fica a ler a lista de capítulos não é
	atirado para uma partida a meio. Entrar na fila é um clique explícito.

	Isto só desenha e manda intenções; quem decide se um capítulo está aberto
	é o servidor, que valida outra vez em `MatchService.beginCampaign`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local Campaign = require(Shared.Config.Campaign)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local LobbyController = {}

type ChapterRow = {
	chapter: Campaign.Chapter,
	button: TextButton,
	nameLabel: TextLabel,
	stateLabel: TextLabel,
}

local panel: Frame
local profileLabel: TextLabel
local pvpButton: TextButton
local rows: { ChapterRow } = {}

local function completedChapters(): { [string]: boolean }
	local profile = State.profile
	return if profile then profile.campaign else {}
end

local function startChapter(chapterId: string)
	-- Escolher um capítulo tira-nos da fila do PvP: senão, acabado o capítulo,
	-- caíamos numa partida online sem a pedir.
	if State.queued then
		Net.fireServer("SetQueued", false)
	end
	Net.fireServer("StartCampaign", chapterId)
end

function LobbyController.refresh()
	panel.Visible = State.phase == "Lobby"
	if not panel.Visible then
		return
	end

	local profile = State.profile
	if profile then
		profileLabel.Text =
			Locale.get("lobby_profile", profile.level, profile.coins, profile.wins, profile.losses)
	else
		profileLabel.Text = ""
	end

	local completed = completedChapters()
	for _, row in rows do
		local done = completed[row.chapter.id] == true
		local unlocked = Campaign.isUnlocked(row.chapter.id, completed)

		row.nameLabel.Text = Locale.get(row.chapter.nameKey)
		row.button.AutoButtonColor = unlocked

		if done then
			row.stateLabel.Text = Locale.get("chapter_done")
			row.stateLabel.TextColor3 = colors.good
			row.button.BackgroundColor3 = colors.panelLight
			row.nameLabel.TextColor3 = colors.text
		elseif unlocked then
			row.stateLabel.Text = Locale.get("reward", row.chapter.rewardXp, row.chapter.rewardCoins)
			row.stateLabel.TextColor3 = colors.accent
			row.button.BackgroundColor3 = colors.panelLight
			row.nameLabel.TextColor3 = colors.text
		else
			row.stateLabel.Text = Locale.get("chapter_locked_short")
			row.stateLabel.TextColor3 = colors.textDim
			row.button.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
			row.nameLabel.TextColor3 = colors.textDim
		end
	end

	if State.queued then
		pvpButton.Text = `{Locale.get("lobby_searching")} ({State.waiting}) · {Locale.get("lobby_cancel")}`
		pvpButton.BackgroundColor3 = colors.panelLight
		pvpButton.TextColor3 = colors.text
	else
		pvpButton.Text = Locale.get("lobby_pvp")
		pvpButton.BackgroundColor3 = colors.good
		pvpButton.TextColor3 = Color3.fromRGB(16, 24, 18)
	end
end

local function buildChapterRow(parent: Instance, chapter: Campaign.Chapter, order: number)
	local button = make("TextButton", {
		Name = `Chapter_{chapter.id}`,
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	}) :: TextButton
	UIUtil.corner(button, 10)

	local nameLabel = make("TextLabel", {
		Name = "ChapterName",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 6),
		Size = UDim2.new(1, -28, 0, 22),
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	}) :: TextLabel

	make("TextLabel", {
		Name = "Hint",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 28),
		Size = UDim2.new(1, -120, 0, 20),
		Font = UIUtil.fontRegular,
		Text = Locale.get(chapter.hintKey),
		TextColor3 = colors.textDim,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})

	local stateLabel = make("TextLabel", {
		Name = "ChapterState",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.new(0, 150, 0, 20),
		BackgroundTransparency = 1,
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	}) :: TextLabel

	button.MouseButton1Click:Connect(function()
		if Campaign.isUnlocked(chapter.id, completedChapters()) then
			startChapter(chapter.id)
		end
	end)

	table.insert(rows, { chapter = chapter, button = button, nameLabel = nameLabel, stateLabel = stateLabel })
end

function LobbyController.init()
	local root = UIController.getRoot()

	panel = make("Frame", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 1, -60),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	UIUtil.corner(panel, 14)
	UIUtil.padding(panel, 16)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(680, 460)
	constraint.Parent = panel

	make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 30),
		Font = UIUtil.font,
		Text = Locale.get("lobby_title"),
		TextColor3 = colors.accent,
		TextSize = 26,
		Parent = panel,
	})

	profileLabel = make("TextLabel", {
		Name = "Profile",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 32),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 14,
		Parent = panel,
	}) :: TextLabel

	make("TextLabel", {
		Name = "CampaignTitle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 2, 0, 56),
		Size = UDim2.new(1, -4, 0, 20),
		Font = UIUtil.font,
		Text = Locale.get("lobby_campaign"),
		TextColor3 = colors.text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	-- A lista desliza: os capítulos vão crescer e o ecrã do telemóvel não.
	local list = make("ScrollingFrame", {
		Name = "Chapters",
		Position = UDim2.new(0, 0, 0, 80),
		Size = UDim2.new(1, 0, 1, -142),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageTransparency = 0.4,
		Parent = panel,
	}) :: ScrollingFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = list

	for index, chapter in Campaign.chapters do
		buildChapterRow(list, chapter, index)
	end

	pvpButton = make("TextButton", {
		Name = "PlayOnline",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = colors.good,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.font,
		Text = Locale.get("lobby_pvp"),
		TextColor3 = Color3.fromRGB(16, 24, 18),
		TextSize = 18,
		Parent = panel,
	}) :: TextButton
	UIUtil.corner(pvpButton, 10)
end

function LobbyController.start()
	pvpButton.MouseButton1Click:Connect(function()
		Net.fireServer("SetQueued", not State.queued)
	end)

	State.onMatchState(LobbyController.refresh)
	State.onProfile(LobbyController.refresh)
	State.onQueueState(LobbyController.refresh)

	LobbyController.refresh()
end

return LobbyController
