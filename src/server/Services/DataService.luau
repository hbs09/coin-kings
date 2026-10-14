--!strict
--[[
	DataService — o perfil persistente de cada jogador.

	Tres coisas que este modulo garante:

	1. **Retry.** Toda a chamada ao DataStore e tentada varias vezes com espera
	   crescente. O DataStore falha de vez em quando sem ser culpa de ninguem.

	2. **Session lock.** O perfil guardado leva um lock com o JobId do servidor.
	   Outro servidor so lhe pode tocar depois de `sessionLockStaleAfter` sem
	   renovacao. E isto que impede a duplicacao classica (entrar em dois
	   servidores ao mesmo tempo) e, como o lock expira, um servidor que caia
	   nao deixa o perfil preso para sempre.

	3. **Nunca bloquear o jogo.** Se o DataStore estiver em baixo, ou se o
	   Studio nao tiver acesso as APIs, o jogador recebe um perfil em memoria
	   com `canSave = false` e joga na mesma. **Nunca se escreve por cima de um
	   perfil que nao conseguimos ler** — e preferivel perder o progresso de uma
	   sessao do que apagar o de meses.

	Guarda ao sair, de 60 em 60 s (o que tambem renova o lock) e em BindToClose.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local DataConfig = require(Shared.Config.Data)

type Entry = {
	profile: Types.Profile,
	-- false quando o perfil e so de memoria (DataStore indisponivel ou preso
	-- noutro servidor): joga-se na mesma, mas nao se grava.
	canSave: boolean,
	dirty: boolean,
	saving: boolean,
}

local DataService = {}

local store: DataStore? = nil
local entries: { [Player]: Entry } = {}
local loading: { [Player]: boolean } = {}
local warnedAboutStudio = false
local loadedListeners: { (player: Player) -> () } = {}

local function profileKey(player: Player): string
	return DataConfig.keyPrefix .. tostring(player.UserId)
end

-- Copia e preenchimento ------------------------------------------------------

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Preenche os campos que faltam a partir do perfil por omissao e marca a versao
-- atual. E isto que faz um perfil antigo sobreviver a um campo novo em Config.
local function reconcile(stored: any): Types.Profile
	local profile: any = if typeof(stored) == "table" then deepCopy(stored) else {}
	for key, value in DataConfig.defaultProfile :: any do
		if profile[key] == nil then
			profile[key] = deepCopy(value)
		end
	end
	profile.version = DataConfig.schemaVersion
	return profile :: Types.Profile
end

local function fallbackProfile(): Types.Profile
	return reconcile(nil)
end

-- Chamadas ao DataStore -------------------------------------------------------

-- Erros de configuracao (Studio sem acesso as APIs, pedido recusado) nao
-- melhoram com insistencia: insistir so atrasava toda a gente.
local function isUnretryable(err: string): boolean
	return string.find(err, "403") ~= nil
		or string.find(err, "Studio") ~= nil
		or string.find(err, "not allowed") ~= nil
end

local function attemptWithRetry(label: string, fn: () -> ()): (boolean, string?)
	local lastError: string? = nil
	for attempt = 1, DataConfig.retryAttempts do
		local ok, err = pcall(fn)
		if ok then
			return true, nil
		end

		lastError = tostring(err)
		if isUnretryable(lastError) then
			break
		end
		if attempt < DataConfig.retryAttempts then
			task.wait(DataConfig.retryBackoff * attempt)
		end
	end
	warn(`DataService: {label} falhou: {lastError}`)
	return false, lastError
end

-- No Studio o acesso as APIs vem desligado por omissao; sem isto o erro e
-- cru e confuso.
local function warnIfStudioApiDisabled(err: string?)
	if warnedAboutStudio or not err or not RunService:IsStudio() then
		return
	end
	if string.find(err, "403") or string.find(err, "Studio") or string.find(err, "API") then
		warnedAboutStudio = true
		warn(
			"DataService: o Studio nao tem acesso as APIs, por isso nada e gravado. "
				.. "Para testar a persistencia: File > Game Settings > Security > "
				.. "Enable Studio Access to API Services."
		)
	end
end

-- Carregamento ----------------------------------------------------------------

local function loadEntry(player: Player): Entry
	local activeStore = store
	if not activeStore then
		return { profile = fallbackProfile(), canSave = false, dirty = false, saving = false }
	end

	local key = profileKey(player)
	local jobId = game.JobId

	for round = 1, DataConfig.sessionLockRetries do
		local lockedByOther = false
		local loaded: Types.Profile? = nil

		local ok, err = attemptWithRetry("carregar o perfil", function()
			activeStore:UpdateAsync(key, function(old: any): any
				local envelope = if typeof(old) == "table" then old else nil
				local lock = if envelope then envelope.lock else nil

				if typeof(lock) == "table" and lock.jobId ~= jobId then
					local age = os.time() - (tonumber(lock.time) or 0)
					if age < DataConfig.sessionLockStaleAfter then
						-- Outro servidor ainda tem a sessao: abortar a escrita.
						lockedByOther = true
						return nil
					end
				end

				local profile = reconcile(if envelope then envelope.profile else nil)
				profile.lastLogin = os.time()
				loaded = profile
				return { profile = profile, lock = { jobId = jobId, time = os.time() } }
			end)
		end)

		if ok and loaded then
			return { profile = loaded, canSave = true, dirty = false, saving = false }
		end

		if not ok then
			warnIfStudioApiDisabled(err)
			break
		end

		if lockedByOther then
			if round < DataConfig.sessionLockRetries then
				task.wait(DataConfig.sessionLockRetryDelay)
			else
				warn(
					`DataService: o perfil de {player.Name} continua preso noutro servidor; `
						.. "sessao sem gravacao."
				)
			end
		end

		if not player.Parent then
			break
		end
	end

	return { profile = fallbackProfile(), canSave = false, dirty = false, saving = false }
end

-- Gravacao --------------------------------------------------------------------

local function saveEntry(player: Player, entry: Entry, release: boolean): boolean
	local activeStore = store
	if not activeStore or not entry.canSave or entry.saving then
		return false
	end

	entry.saving = true
	local key = profileKey(player)
	local jobId = game.JobId
	local profile = entry.profile
	local stolen = false

	local ok, err = attemptWithRetry("gravar o perfil", function()
		activeStore:UpdateAsync(key, function(old: any): any
			local lock = if typeof(old) == "table" then old.lock else nil

			-- Se outro servidor tomou a sessao entretanto, nao escrevemos por
			-- cima do que ele esta a fazer.
			if typeof(lock) == "table" and lock.jobId ~= jobId then
				local age = os.time() - (tonumber(lock.time) or 0)
				if age < DataConfig.sessionLockStaleAfter then
					stolen = true
					return nil
				end
			end

			return {
				profile = profile,
				lock = if release then nil else { jobId = jobId, time = os.time() },
			}
		end)
	end)

	entry.saving = false

	if stolen then
		entry.canSave = false
		warn(`DataService: outro servidor tomou a sessao de {player.Name}; gravacao cancelada.`)
		return false
	end

	if ok then
		entry.dirty = false
		return true
	end

	warnIfStudioApiDisabled(err)
	return false
end

-- API -------------------------------------------------------------------------

-- O perfil carrega de forma assincrona; quem precisa de o mostrar (o lobby)
-- regista-se aqui em vez de andar a sondar.
function DataService.onProfileLoaded(listener: (player: Player) -> ())
	table.insert(loadedListeners, listener)
end

function DataService.isReady(player: Player): boolean
	return entries[player] ~= nil
end

function DataService.get(player: Player): Types.Profile?
	local entry = entries[player]
	return if entry then entry.profile else nil
end

-- Altera o perfil em memoria e marca-o para gravar. A gravacao em si acontece
-- no autosave, ao sair ou no BindToClose.
function DataService.update(player: Player, mutate: (profile: Types.Profile) -> ()): boolean
	local entry = entries[player]
	if not entry then
		warn(`DataService: perfil de {player.Name} ainda nao carregou; alteracao ignorada.`)
		return false
	end
	mutate(entry.profile)
	entry.dirty = true
	return true
end

-- Carregamento e saida --------------------------------------------------------

local function onPlayerAdded(player: Player)
	if loading[player] or entries[player] then
		return
	end
	loading[player] = true

	local entry = loadEntry(player)
	loading[player] = nil

	-- Pode ter saido enquanto carregava.
	if not player.Parent then
		if entry.canSave then
			saveEntry(player, entry, true)
		end
		return
	end

	entries[player] = entry

	for _, listener in loadedListeners do
		task.spawn(listener, player)
	end
end

local function onPlayerRemoving(player: Player)
	local entry = entries[player]
	entries[player] = nil
	loading[player] = nil
	if entry then
		-- Liberta o lock: se voltar a entrar ja a seguir, nao espera.
		saveEntry(player, entry, true)
	end
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DataConfig.storeName)
	end)
	if ok then
		store = result
	else
		warn(`DataService: sem DataStore ({result}); as sessoes nao vao ser gravadas.`)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Quem ja estava no servidor quando o script arrancou.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(DataConfig.autosaveInterval)
			for player, entry in entries do
				-- Grava-se mesmo sem alteracoes: e isto que renova o lock.
				if entry.canSave then
					task.spawn(saveEntry, player, entry, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for player, entry in entries do
			if entry.canSave then
				pending += 1
				task.spawn(function()
					saveEntry(player, entry, true)
					pending -= 1
				end)
			end
		end

		-- O Roblox da ~30 s; sair antes do tempo e melhor do que ficar preso.
		local deadline = os.clock() + 20
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
