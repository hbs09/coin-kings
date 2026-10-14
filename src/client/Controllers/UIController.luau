--!strict
--[[
	UIController — HUD da partida: fase, cronometro, ouro, unidades, botao de
	pronto, modo de venda, banner do centro e avisos.

	Cria as regioes da interface e deixa a loja para o ShopController, que
	preenche o contentor devolvido por `UIController.getShopContainer()`.
	Todo o texto vem do Locale.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local MatchConfig = require(Shared.Config.Match)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)

local make = UIUtil.make
local colors = UIUtil.colors

local UIController = {}

local player = Players.LocalPlayer :: Player

local sellMode = false
local toastUntil = 0

-- Referencias criadas no init.
local phaseLabel: TextLabel
local timerLabel: TextLabel
local roundLabel: TextLabel
local goldLabel: TextLabel
local unitsLabel: TextLabel
local hintLabel: TextLabel
local toastLabel: TextLabel
local readyButton: TextButton
local sellButton: TextButton
local bannerFrame: Frame
local bannerTitle: TextLabel
local bannerSubtitle: TextLabel
local shopContainer: Frame

local function phaseKey(phase: Types.MatchPhase): string
	if phase == "Prep" then
		return "phase_prep"
	elseif phase == "Reveal" then
		return "phase_reveal"
	elseif phase == "Battle" then
		return "phase_battle"
	elseif phase == "RoundEnd" then
		return "phase_round_end"
	elseif phase == "MatchEnd" then
		return "phase_match_end"
	end
	return "phase_lobby"
end

function UIController.isSellMode(): boolean
	return sellMode and State.canEditArmy()
end

function UIController.getShopContainer(): Frame
	return shopContainer
end

function UIController.showToast(text: string)
	toastLabel.Text = text
	toastLabel.Visible = true
	toastUntil = os.clock() + 2.5
end

function UIController.setBanner(title: string, subtitle: string, visible: boolean)
	bannerTitle.Text = title
	bannerSubtitle.Text = subtitle
	bannerFrame.Visible = visible
end

local function setSellMode(enabled: boolean)
	sellMode = enabled
	sellButton.BackgroundColor3 = if enabled then colors.bad else colors.panelLight
	sellButton.Text = if enabled then Locale.get("sell_mode_on") else Locale.get("sell_mode")
end

-- Construcao ------------------------------------------------------------------

local function buildTopBar(root: ScreenGui)
	local bar = make("Frame", {
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 320, 0, 72),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = root,
	}) :: Frame
	UIUtil.corner(bar, 10)

	phaseLabel = make("TextLabel", {
		Name = "Phase",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 6),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 16,
		Parent = bar,
	}) :: TextLabel

	timerLabel = make("TextLabel", {
		Name = "Timer",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 24),
		Size = UDim2.new(1, 0, 0, 34),
		Font = UIUtil.font,
		Text = "0:00",
		TextColor3 = colors.text,
		TextSize = 30,
		Parent = bar,
	}) :: TextLabel

	roundLabel = make("TextLabel", {
		Name = "Round",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 16),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 14,
		Parent = bar,
	}) :: TextLabel
end

local function buildResourceBar(root: ScreenGui)
	local bar = make("Frame", {
		Name = "Resources",
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(0, 170, 0, 62),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Parent = root,
	}) :: Frame
	UIUtil.corner(bar, 10)
	UIUtil.padding(bar, 8)

	goldLabel = make("TextLabel", {
		Name = "Gold",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	}) :: TextLabel

	unitsLabel = make("TextLabel", {
		Name = "Units",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 26),
		Size = UDim2.new(1, 0, 0, 18),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = bar,
	}) :: TextLabel
end

local function buildBottom(root: ScreenGui)
	local bottom = make("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 132),
		BackgroundTransparency = 1,
		Parent = root,
	}) :: Frame

	shopContainer = make("Frame", {
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(0, 360, 0, 112),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = bottom,
	}) :: Frame
	UIUtil.corner(shopContainer, 12)
	UIUtil.padding(shopContainer, 8)

	local actions = make("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.new(0, 132, 0, 112),
		BackgroundTransparency = 1,
		Parent = bottom,
	}) :: Frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 8)
	layout.Parent = actions

	sellButton = make("TextButton", {
		Name = "SellMode",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = Locale.get("sell_mode"),
		TextColor3 = colors.text,
		TextSize = 15,
		LayoutOrder = 1,
		Parent = actions,
	}) :: TextButton
	UIUtil.corner(sellButton, 10)

	readyButton = make("TextButton", {
		Name = "Ready",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = colors.good,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.font,
		Text = Locale.get("ready"),
		TextColor3 = Color3.fromRGB(16, 24, 18),
		TextSize = 20,
		LayoutOrder = 2,
		Parent = actions,
	}) :: TextButton
	UIUtil.corner(readyButton, 10)
end

local function buildOverlays(root: ScreenGui)
	hintLabel = make("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.new(0, 420, 0, 22),
		BackgroundTransparency = 1,
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 15,
		TextStrokeTransparency = 0.6,
		Parent = root,
	}) :: TextLabel

	toastLabel = make("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0, 300, 0, 32),
		BackgroundColor3 = colors.bad,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 16,
		Visible = false,
		Parent = root,
	}) :: TextLabel
	UIUtil.corner(toastLabel, 8)

	bannerFrame = make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 460, 0, 130),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	UIUtil.corner(bannerFrame, 14)

	bannerTitle = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 56),
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 44,
		Parent = bannerFrame,
	}) :: TextLabel

	bannerSubtitle = make("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 78),
		Size = UDim2.new(1, 0, 0, 32),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 18,
		Parent = bannerFrame,
	}) :: TextLabel
end

-- Atualizacoes ----------------------------------------------------------------

local function refreshHud()
	local phase = State.phase
	phaseLabel.Text = Locale.get(phaseKey(phase))
	timerLabel.Text = UIUtil.formatTime(State.timeLeft())
	timerLabel.TextColor3 = if phase == "Prep" and State.timeLeft() <= 10 then colors.bad else colors.text

	if State.team and phase ~= "Lobby" then
		roundLabel.Text = `{Locale.get("round", State.round)}  {State.selfScore} - {State.opponentScore}`
	else
		roundLabel.Text = ""
	end

	goldLabel.Text = `{Locale.get("gold")}: {State.gold}`
	unitsLabel.Text = Locale.get("units", State.unitCount(), MatchConfig.maxUnitsPerPlayer)

	local editing = State.canEditArmy()
	shopContainer.Visible = editing
	readyButton.Visible = editing
	sellButton.Visible = editing

	if editing then
		readyButton.Text = if State.selfReady then Locale.get("cancel_ready") else Locale.get("ready")
		readyButton.BackgroundColor3 = if State.selfReady then colors.panelLight else colors.good
		readyButton.TextColor3 = if State.selfReady then colors.text else Color3.fromRGB(16, 24, 18)
	end

	if phase == "Lobby" then
		hintLabel.Text = Locale.get("hint_lobby")
	elseif phase == "Prep" then
		if State.selfReady then
			hintLabel.Text = Locale.get("waiting_opponent")
		elseif State.opponentReady then
			hintLabel.Text = Locale.get("opponent_ready")
		elseif State.unitCount() == 0 then
			hintLabel.Text = Locale.get("hint_place")
		else
			hintLabel.Text = Locale.get("hint_drag")
		end
	else
		hintLabel.Text = ""
	end
end

-- Corre a cada frame: so o que muda com o tempo.
local lastSecond = -1

local function refreshClock()
	local remaining = State.timeLeft()
	local whole = math.floor(remaining + 0.5)
	if whole ~= lastSecond then
		lastSecond = whole
		timerLabel.Text = UIUtil.formatTime(remaining)
		timerLabel.TextColor3 = if State.phase == "Prep" and remaining <= 10 then colors.bad else colors.text
	end
	if toastLabel.Visible and os.clock() > toastUntil then
		toastLabel.Visible = false
	end
end

local function onRoundResult(payload: Types.RoundResultPayload)
	local team = State.team
	if not team then
		return
	end

	local title: string
	if payload.winner == nil then
		title = Locale.get("round_draw")
	elseif payload.winner == team then
		title = Locale.get("round_won")
	else
		title = Locale.get("round_lost")
	end

	local reasonKey = if payload.reason == "elimination"
		then "reason_elimination"
		elseif payload.reason == "timeout" then "reason_timeout"
		else "reason_aborted"
	local selfValue = if team == "A" then payload.valueA else payload.valueB
	local otherValue = if team == "A" then payload.valueB else payload.valueA
	UIController.setBanner(title, `{Locale.get(reasonKey)} — {selfValue} vs {otherValue}`, true)
end

local function onMatchResult(payload: Types.MatchResultPayload)
	local team = State.team
	if not team then
		return
	end

	local title: string
	if payload.winner == nil then
		title = Locale.get("draw")
	elseif payload.winner == team then
		title = Locale.get("you_win")
	else
		title = Locale.get("you_lose")
	end

	local selfScore = if team == "A" then payload.scoreA else payload.scoreB
	local otherScore = if team == "A" then payload.scoreB else payload.scoreA
	UIController.setBanner(title, `{selfScore} - {otherScore}`, true)
end

function UIController.init()
	local root = make("ScreenGui", {
		Name = "CoinKingsHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui

	buildTopBar(root)
	buildResourceBar(root)
	buildBottom(root)
	buildOverlays(root)
	setSellMode(false)
end

function UIController.start()
	readyButton.MouseButton1Click:Connect(function()
		Net.fireServer("SetReady", not State.selfReady)
	end)

	sellButton.MouseButton1Click:Connect(function()
		setSellMode(not sellMode)
	end)

	State.onMatchState(function(payload: Types.MatchStatePayload)
		if payload.phase ~= "Prep" then
			setSellMode(false)
		end
		if payload.phase == "Prep" then
			UIController.setBanner("", "", false)
		elseif payload.phase == "Reveal" then
			UIController.setBanner(Locale.get("phase_reveal"), Locale.get("hint_battle"), true)
			task.delay(MatchConfig.revealDuration, function()
				if State.phase == "Battle" or State.phase == "Reveal" then
					UIController.setBanner("", "", false)
				end
			end)
		elseif payload.phase == "Lobby" then
			UIController.setBanner("", "", false)
		end
		refreshHud()
	end)

	State.onArmy(refreshHud)
	State.onRoundResult(onRoundResult)
	State.onMatchResult(onMatchResult)

	State.onNotice(function(payload: Types.NoticePayload)
		UIController.showToast(Locale.get(payload.key, payload.arg))
	end)

	RunService.RenderStepped:Connect(refreshClock)
end

return UIController
