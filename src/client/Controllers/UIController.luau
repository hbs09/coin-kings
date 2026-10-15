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
local root: ScreenGui
local topBar: Frame
local resourceBar: Frame
local leaveButton: TextButton
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
local bannerActions: Frame
local lobbyButton: TextButton
local retryButton: TextButton
local playButton: TextButton

-- O que fazer assim que voltarmos ao lobby. Sair de uma partida e pedir ao
-- servidor e esperar; so quando ele confirma o lobby e que se pode arrancar
-- outra coisa.
local pendingAfterLobby: string? = nil
-- Enquanto o ecra de fim tem botoes, o cronometro nao aparece: o tempo que
-- resta e so a rede de seguranca do servidor e nao e da conta do jogador.
local hideTimer = false
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

function UIController.getRoot(): ScreenGui
	return root
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
	local bar = UIUtil.panel({
		Name = "TopBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(0, 300, 0, 78),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Parent = root,
	}, 12)
	topBar = bar

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
		Font = UIUtil.fontDisplay,
		Text = "0:00",
		TextColor3 = colors.text,
		TextSize = 34,
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
	-- Em cima a esquerda fica por baixo da barra do Roblox (menu e chat), por
	-- isso o ouro vive ao pe da loja, que e para onde se olha ao comprar.
	local bar = UIUtil.panel({
		Name = "Resources",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -150),
		Size = UDim2.new(0, 196, 0, 58),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Parent = root,
	}, 12)
	UIUtil.padding(bar, 9)
	resourceBar = bar

	goldLabel = make("TextLabel", {
		Name = "Gold",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		Font = UIUtil.fontDisplay,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 26,
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

	-- Ocupa a largura toda menos a coluna dos botoes, a direita. Os cartoes
	-- deslizam na horizontal quando nao cabem (ShopController).
	shopContainer = UIUtil.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, -144, 0, 112),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Parent = bottom,
	}, 14)
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

	sellButton = UIUtil.button({
		Name = "SellMode",
		Size = UDim2.new(1, 0, 0, 40),
		Font = UIUtil.font,
		Text = Locale.get("sell_mode"),
		TextColor3 = colors.text,
		TextSize = 15,
		LayoutOrder = 1,
		Parent = actions,
	}, colors.panelLight, colors.panel)

	readyButton = UIUtil.button({
		Name = "Ready",
		Size = UDim2.new(1, 0, 0, 54),
		Font = UIUtil.fontDisplay,
		Text = Locale.get("ready"),
		TextColor3 = colors.textOnLight,
		TextSize = 20,
		LayoutOrder = 2,
		Parent = actions,
	}, colors.good, colors.goodDeep)
end

local function buildOverlays(root: ScreenGui)
	hintLabel = make("TextLabel", {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 1),
		-- Acima do painel do ouro, que agora vive em cima da loja.
		Position = UDim2.new(0.5, 0, 1, -212),
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
		BorderSizePixel = 0,
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 16,
		Visible = false,
		Parent = root,
	}) :: TextLabel
	UIUtil.corner(toastLabel, 10)
	UIUtil.gradient(toastLabel, colors.bad, colors.badDeep)

	leaveButton = make("TextButton", {
		Name = "Leave",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 110, 0, 36),
		BackgroundColor3 = colors.panelLight,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = Locale.get("leave_match"),
		TextColor3 = colors.textDim,
		TextSize = 15,
		Visible = false,
		Parent = root,
	}) :: TextButton
	UIUtil.corner(leaveButton, 8)

	bannerFrame = make("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 470, 0, 200),
		BackgroundColor3 = colors.panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	UIUtil.corner(bannerFrame, 18)
	UIUtil.gradient(bannerFrame, colors.panelTop, colors.panel)
	UIUtil.stroke(bannerFrame, 2, colors.accent, 0.6)

	bannerTitle = make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 18),
		Size = UDim2.new(1, 0, 0, 56),
		Font = UIUtil.fontDisplay,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 46,
		Parent = bannerFrame,
	}) :: TextLabel

	bannerActions = make("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(1, -28, 0, 44),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = bannerFrame,
	}) :: Frame

	local actionsLayout = Instance.new("UIListLayout")
	actionsLayout.FillDirection = Enum.FillDirection.Horizontal
	actionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionsLayout.Padding = UDim.new(0, 8)
	actionsLayout.Parent = bannerActions

	local function actionButton(name: string, label: string, order: number, primary: boolean): TextButton
		local tone = if primary then colors.good else colors.panelLight
		local toneDeep = if primary then colors.goodDeep else colors.panel
		return UIUtil.button({
			Name = name,
			Size = UDim2.new(0, 140, 1, 0),
			Font = UIUtil.font,
			Text = label,
			TextColor3 = if primary then colors.textOnLight else colors.text,
			TextSize = 15,
			LayoutOrder = order,
			Parent = bannerActions,
		}, tone, toneDeep)
	end

	retryButton = actionButton("Retry", Locale.get("result_retry"), 1, false)
	lobbyButton = actionButton("Lobby", Locale.get("result_lobby"), 2, true)
	playButton = actionButton("Play", Locale.get("result_play"), 3, false)

	bannerSubtitle = make("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 76),
		Size = UDim2.new(1, 0, 0, 48),
		TextWrapped = true,
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
	local isTutorial = State.mode == "tutorial"
	local inLobby = phase == "Lobby"
	phaseLabel.Text = Locale.get(phaseKey(phase))
	timerLabel.Text = UIUtil.formatTime(State.timeLeft())
	timerLabel.TextColor3 = if phase == "Prep" and State.timeLeft() <= 10 then colors.bad else colors.text

	if isTutorial then
		roundLabel.Text = Locale.get("tutorial_name")
	elseif State.mode == "sandbox" and not inLobby then
		roundLabel.Text = Locale.get("sandbox_name")
	elseif State.mode == "training" and not inLobby then
		-- Quem joga contra o bot tem de saber que esta a jogar contra o bot.
		roundLabel.Text = `{Locale.get("training_name")}  ·  {Locale.get("round", State.round)}`
	elseif State.team and not inLobby then
		roundLabel.Text = `{Locale.get("round", State.round)}  {State.selfScore} - {State.opponentScore}`
	else
		roundLabel.Text = ""
	end

	-- No lobby o painel de escolha ocupa o ecra: o HUD da partida sai da frente.
	topBar.Visible = not inLobby
	resourceBar.Visible = not inLobby

	-- Depois do tutorial a saida e por botao, nao por cronometro.
	local showResultActions = isTutorial and phase == "MatchEnd"
	bannerActions.Visible = showResultActions
	hideTimer = showResultActions
	if showResultActions then
		timerLabel.Text = ""
	end
	-- "Desistir" nao faz sentido com a partida ja acabada: ai mandam os botoes
	-- do ecra de fim.
	-- Sair a meio serve ao tutorial e ao sandbox: nos dois nao ha adversario
	-- nenhum a ficar pendurado.
	local canLeave = isTutorial or State.mode == "sandbox"
	leaveButton.Visible = not inLobby and canLeave and phase ~= "MatchEnd"

	goldLabel.Text = `{Locale.get("gold")}: {State.gold}`
	unitsLabel.Text = Locale.get("units", State.unitCount(), MatchConfig.maxUnitsPerPlayer)

	local editing = State.canEditArmy()
	shopContainer.Visible = editing
	readyButton.Visible = editing
	sellButton.Visible = editing

	if editing then
		readyButton.Text = if State.selfReady then Locale.get("cancel_ready") else Locale.get("ready")
		readyButton.BackgroundColor3 = if State.selfReady then colors.panelLight else colors.good
		readyButton.TextColor3 = if State.selfReady then colors.text else colors.textOnLight
	end

	if inLobby then
		hintLabel.Text = ""
	elseif phase == "Prep" then
		if isTutorial then
			hintLabel.Text = Locale.get("tutorial_hint")
		elseif State.selfReady then
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
	if hideTimer then
		return
	end
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
	local subtitle = `{selfScore} - {otherScore}`

	-- No PvP o que interessa no fim sao os trofeus, nao o placar.
	local delta = payload.trophyDelta
	if delta then
		local trophyText = if delta >= 0
			then Locale.get("trophy_gain", delta)
			else Locale.get("trophy_loss", delta)
		subtitle = `{subtitle}  ·  {trophyText}`
	end

	local unlocked = payload.unlocked
	if unlocked and #unlocked > 0 then
		subtitle = subtitle .. "\n" .. Locale.get("unlocked_troop", Locale.troopName(unlocked[1]))
	end

	UIController.setBanner(title, subtitle, true)
end

function UIController.init()
	root = make("ScreenGui", {
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

	leaveButton.MouseButton1Click:Connect(function()
		pendingAfterLobby = nil
		Net.fireServer("LeaveMatch")
	end)

	-- Os tres botoes do ecra de fim pedem para sair e deixam dito o que fazer
	-- a seguir; o resto acontece quando o servidor confirmar o lobby.
	local function leaveThen(action: string?)
		pendingAfterLobby = action
		UIController.setBanner("", "", false)
		Net.fireServer("LeaveMatch")
	end

	lobbyButton.MouseButton1Click:Connect(function()
		leaveThen(nil)
	end)

	retryButton.MouseButton1Click:Connect(function()
		leaveThen("tutorial")
	end)

	playButton.MouseButton1Click:Connect(function()
		leaveThen("queue")
	end)

	State.onMatchState(function(payload: Types.MatchStatePayload)
		if payload.phase == "Lobby" and pendingAfterLobby then
			local action = pendingAfterLobby
			pendingAfterLobby = nil
			if action == "tutorial" then
				Net.fireServer("StartTutorial")
			elseif action == "queue" then
				Net.fireServer("SetQueued", true)
			end
		end

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
