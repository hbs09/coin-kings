--!strict
--[[
	LobbyController — o ecrã entre partidas.

	Mostra onde o jogador está (troféus e arena), o que falta para a arena
	seguinte e a tropa que ela entrega — é esse o objetivo que o faz voltar a
	carregar em jogar.

	Ninguém é emparelhado sem pedir: entrar na fila é um clique explícito.
	O tutorial corre sozinho na primeira vez; aqui fica só o botão de repetir.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Locale = require(Shared.Locale)
local RankConfig = require(Shared.Config.Rank)

local State = require(script.Parent.Parent.State)
local UIUtil = require(script.Parent.Parent.UIUtil)
local UIController = require(script.Parent.UIController)

local make = UIUtil.make
local colors = UIUtil.colors

local LobbyController = {}

local panel: Frame
local arenaLabel: TextLabel
local trophyLabel: TextLabel
local progressFill: Frame
local nextArenaLabel: TextLabel
local recordLabel: TextLabel
local pvpButton: TextButton
local tutorialButton: TextButton

local function trophies(): number
	local profile = State.profile
	return if profile then profile.trophies else 0
end

function LobbyController.refresh()
	panel.Visible = State.phase == "Lobby"
	if not panel.Visible then
		return
	end

	local profile = State.profile
	local total = trophies()
	local arena = RankConfig.arenaFor(total)
	local following = RankConfig.nextArena(total)

	arenaLabel.Text = Locale.get("lobby_arena", Locale.get(arena.nameKey))
	trophyLabel.Text = Locale.get("lobby_trophies", total)

	if following then
		-- A barra enche entre o piso desta arena e o da seguinte.
		local span = following.trophies - arena.trophies
		local done = total - arena.trophies
		progressFill.Size = UDim2.fromScale(math.clamp(if span > 0 then done / span else 1, 0, 1), 1)

		local unlockName = if #following.unlocks > 0
			then Locale.troopName(following.unlocks[1])
			else Locale.get(following.nameKey)
		nextArenaLabel.Text = Locale.get("lobby_next_arena", following.trophies, unlockName)
	else
		progressFill.Size = UDim2.fromScale(1, 1)
		nextArenaLabel.Text = Locale.get("lobby_max_arena")
	end

	if profile then
		recordLabel.Text = Locale.get("lobby_profile", profile.level, profile.coins, profile.wins, profile.losses)
	else
		recordLabel.Text = ""
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

function LobbyController.init()
	local root = UIController.getRoot()

	panel = make("Frame", {
		Name = "Lobby",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -40, 0, 330),
		BackgroundColor3 = colors.panel,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	}) :: Frame
	UIUtil.corner(panel, 14)
	UIUtil.padding(panel, 18)

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(520, 330)
	constraint.Parent = panel

	make("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Font = UIUtil.font,
		Text = Locale.get("lobby_title"),
		TextColor3 = colors.accent,
		TextSize = 24,
		Parent = panel,
	})

	arenaLabel = make("TextLabel", {
		Name = "Arena",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 0, 26),
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.text,
		TextSize = 20,
		Parent = panel,
	}) :: TextLabel

	trophyLabel = make("TextLabel", {
		Name = "Trophies",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 60),
		Size = UDim2.new(1, 0, 0, 24),
		Font = UIUtil.font,
		Text = "",
		TextColor3 = colors.accent,
		TextSize = 19,
		Parent = panel,
	}) :: TextLabel

	-- Barra de progresso para a arena seguinte.
	local track = make("Frame", {
		Name = "ProgressTrack",
		Position = UDim2.new(0, 0, 0, 92),
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundColor3 = Color3.fromRGB(18, 20, 26),
		BorderSizePixel = 0,
		Parent = panel,
	}) :: Frame
	UIUtil.corner(track, 5)

	progressFill = make("Frame", {
		Name = "ProgressFill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = colors.accent,
		BorderSizePixel = 0,
		Parent = track,
	}) :: Frame
	UIUtil.corner(progressFill, 5)

	nextArenaLabel = make("TextLabel", {
		Name = "NextArena",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 106),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 14,
		Parent = panel,
	}) :: TextLabel

	recordLabel = make("TextLabel", {
		Name = "Record",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 130),
		Size = UDim2.new(1, 0, 0, 20),
		Font = UIUtil.fontRegular,
		Text = "",
		TextColor3 = colors.textDim,
		TextSize = 14,
		Parent = panel,
	}) :: TextLabel

	pvpButton = make("TextButton", {
		Name = "PlayOnline",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -46),
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = colors.good,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.font,
		Text = Locale.get("lobby_pvp"),
		TextColor3 = Color3.fromRGB(16, 24, 18),
		TextSize = 19,
		Parent = panel,
	}) :: TextButton
	UIUtil.corner(pvpButton, 10)

	tutorialButton = make("TextButton", {
		Name = "ReplayTutorial",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = colors.panelLight,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = UIUtil.fontRegular,
		Text = Locale.get("lobby_replay_tutorial"),
		TextColor3 = colors.textDim,
		TextSize = 15,
		Parent = panel,
	}) :: TextButton
	UIUtil.corner(tutorialButton, 8)
end

function LobbyController.start()
	pvpButton.MouseButton1Click:Connect(function()
		Net.fireServer("SetQueued", not State.queued)
	end)

	tutorialButton.MouseButton1Click:Connect(function()
		-- Repetir o tutorial tira-nos da fila: senão, acabado o tutorial,
		-- caíamos numa partida online sem a pedir.
		if State.queued then
			Net.fireServer("SetQueued", false)
		end
		Net.fireServer("StartTutorial")
	end)

	State.onMatchState(LobbyController.refresh)
	State.onProfile(LobbyController.refresh)
	State.onQueueState(LobbyController.refresh)

	LobbyController.refresh()
end

return LobbyController
