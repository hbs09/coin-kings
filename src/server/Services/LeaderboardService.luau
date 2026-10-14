--!strict
--[[
	LeaderboardService — a classificação global por troféus.

	Escreve os troféus de cada jogador num OrderedDataStore e vai buscar o topo
	de 5 em 5 minutos, servindo depois a toda a gente a partir de uma cópia em
	memória. Ler uma vez por servidor em vez de uma vez por jogador é o que
	mantém isto dentro do orçamento de pedidos do DataStore.

	Duas coisas a saber:

	- **Isto é um índice, não é a verdade.** Os troféus do jogador vivem no
	  perfil (DataService). Se a classificação falhar ou se perder, ninguém
	  perde nada do que conquistou.
	- **Nunca bloqueia o jogo.** Tudo em pcall; sem DataStore (ou no Studio sem
	  acesso às APIs) a lista chega vazia e o cliente diz que ainda não há
	  classificação, em vez de dar erro.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local LeaderboardConfig = require(Shared.Config.Leaderboard)

local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

local store: OrderedDataStore? = nil
local cached: { Types.LeaderboardEntry } = {}
local lastWrite: { [Player]: number } = {}
local nameCache: { [number]: string } = {}
local warned = false

local function warnOnce(message: string)
	if warned then
		return
	end
	warned = true
	warn(`LeaderboardService: {message}`)
end

local function nameFor(userId: number): string
	local cachedName = nameCache[userId]
	if cachedName then
		return cachedName
	end

	-- Jogadores que estão no servidor não precisam de ida à API.
	local player = Players:GetPlayerByUserId(userId)
	if player then
		nameCache[userId] = player.DisplayName
		return player.DisplayName
	end

	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(result) == "string" then result else `#{userId}`
	nameCache[userId] = name
	return name
end

-- Escrita ---------------------------------------------------------------------

function LeaderboardService.publish(player: Player)
	local activeStore = store
	if not activeStore then
		return
	end

	local profile = DataService.get(player)
	if not profile then
		return
	end

	local now = os.clock()
	local previous = lastWrite[player]
	if previous and now - previous < LeaderboardConfig.minWriteInterval then
		return
	end
	lastWrite[player] = now

	task.spawn(function()
		local ok, err = pcall(function()
			activeStore:SetAsync(tostring(player.UserId), math.floor(profile.trophies))
		end)
		if not ok then
			warnOnce(`nao consegui gravar a classificacao ({err})`)
		end
	end)
end

-- Leitura ---------------------------------------------------------------------

local function refresh()
	local activeStore = store
	if not activeStore then
		return
	end

	local ok, pages = pcall(function()
		return activeStore:GetSortedAsync(false, LeaderboardConfig.topCount)
	end)
	if not ok or not pages then
		warnOnce(`nao consegui ler a classificacao ({pages})`)
		return
	end

	local okPage, page = pcall(function()
		return pages:GetCurrentPage()
	end)
	if not okPage or typeof(page) ~= "table" then
		return
	end

	local entries: { Types.LeaderboardEntry } = {}
	for index, row in page do
		local userId = tonumber(row.key)
		if userId then
			table.insert(entries, {
				rank = index,
				userId = userId,
				name = nameFor(userId),
				trophies = tonumber(row.value) or 0,
			})
		end
	end

	cached = entries
end

local function send(player: Player)
	local profile = DataService.get(player)
	local payload: Types.LeaderboardPayload = {
		entries = cached,
		selfTrophies = if profile then profile.trophies else 0,
	}
	Net.fireClient("Leaderboard", player, payload)
end

-- Ciclo de vida ----------------------------------------------------------------

function LeaderboardService.init()
	if not LeaderboardConfig.enabled then
		return
	end

	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(LeaderboardConfig.storeName())
	end)
	if ok then
		store = result
	else
		warnOnce(`sem OrderedDataStore ({result})`)
	end

	Net.onServerEvent("RequestLeaderboard", function(player: Player)
		send(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		lastWrite[player] = nil
	end)
end

function LeaderboardService.start()
	if not LeaderboardConfig.enabled then
		return
	end

	task.spawn(function()
		while true do
			refresh()
			task.wait(LeaderboardConfig.refreshInterval)
		end
	end)
end

return LeaderboardService
