--!strict
--[[
	Net — todos os RemoteEvent do jogo num só lugar.

	- O servidor cria os remotes em ReplicatedStorage/Net (Net.init).
	- Cada remote declara a direção, um limite de chamadas por segundo e um
	  validador de argumentos. O que não passa é descartado em silêncio:
	  o cliente nunca é autoridade.
	- Nomes novos entram em SPECS; nada de Instance.new("RemoteEvent") fora daqui.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Net"

export type Direction = "ToServer" | "ToClient"

type Spec = {
	direction: Direction,
	-- Só se aplica a ToServer. 0 = sem limite.
	maxPerSecond: number,
	validate: ((args: { any }, count: number) -> boolean)?,
}

-- Validadores -----------------------------------------------------------------

local function isFiniteNumber(value: any): boolean
	if typeof(value) ~= "number" then
		return false
	end
	local n = value :: number
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function isCoord(value: any): boolean
	return isFiniteNumber(value) and math.abs(value :: number) <= 10000
end

local function isId(value: any): boolean
	if not isFiniteNumber(value) then
		return false
	end
	local n = value :: number
	return n > 0 and n % 1 == 0 and n < 1e9
end

local function isShortString(value: any): boolean
	if typeof(value) ~= "string" then
		return false
	end
	local s = value :: string
	return #s > 0 and #s <= 32
end

-- Registo ---------------------------------------------------------------------

local SPECS: { [string]: Spec } = {
	-- cliente -> servidor (intenções)
	PlaceUnit = {
		direction = "ToServer",
		maxPerSecond = 15,
		validate = function(args, count)
			return count == 3 and isShortString(args[1]) and isCoord(args[2]) and isCoord(args[3])
		end,
	},
	MoveUnit = {
		direction = "ToServer",
		maxPerSecond = 30,
		validate = function(args, count)
			return count == 3 and isId(args[1]) and isCoord(args[2]) and isCoord(args[3])
		end,
	},
	SellUnit = {
		direction = "ToServer",
		maxPerSecond = 15,
		validate = function(args, count)
			return count == 1 and isId(args[1])
		end,
	},
	SetReady = {
		direction = "ToServer",
		maxPerSecond = 5,
		validate = function(args, count)
			return count == 1 and typeof(args[1]) == "boolean"
		end,
	},
	-- Comecar um capitulo da campanha.
	StartCampaign = {
		direction = "ToServer",
		maxPerSecond = 2,
		validate = function(args, count)
			return count == 1 and isShortString(args[1])
		end,
	},
	-- Entrar ou sair da fila do PvP (ninguem e emparelhado sem pedir).
	SetQueued = {
		direction = "ToServer",
		maxPerSecond = 3,
		validate = function(args, count)
			return count == 1 and typeof(args[1]) == "boolean"
		end,
	},
	-- Desistir de um capitulo e voltar ao lobby.
	LeaveMatch = {
		direction = "ToServer",
		maxPerSecond = 2,
		validate = function(_args, count)
			return count == 0
		end,
	},
	-- Pedido de sincronizacao: quem entra a meio recebe a fase e o seu exercito.
	RequestState = {
		direction = "ToServer",
		maxPerSecond = 2,
		validate = function(_args, count)
			return count == 0
		end,
	},

	-- servidor -> cliente (estado)
	MatchState = { direction = "ToClient", maxPerSecond = 0 },
	ArmyUpdate = { direction = "ToClient", maxPerSecond = 0 },
	Roster = { direction = "ToClient", maxPerSecond = 0 },
	Snapshot = { direction = "ToClient", maxPerSecond = 0 },
	RoundResult = { direction = "ToClient", maxPerSecond = 0 },
	MatchResult = { direction = "ToClient", maxPerSecond = 0 },
	Profile = { direction = "ToClient", maxPerSecond = 0 },
	QueueState = { direction = "ToClient", maxPerSecond = 0 },
	Notice = { direction = "ToClient", maxPerSecond = 0 },
}

local Net = {}

local folder: Folder? = nil
local cache: { [string]: RemoteEvent } = {}

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end

	local created: Folder
	if RunService:IsServer() then
		local found = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if found and found:IsA("Folder") then
			created = found
		else
			created = Instance.new("Folder")
			created.Name = FOLDER_NAME
			created.Parent = ReplicatedStorage
		end
	else
		local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30)
		if not (found and found:IsA("Folder")) then
			error("Net: a pasta de remotes nao replicou")
		end
		created = found
	end

	folder = created
	return created
end

local function getRemote(name: string): RemoteEvent
	local cached = cache[name]
	if cached then
		return cached
	end
	if not SPECS[name] then
		error(`Net: remote desconhecido "{name}"`)
	end

	local parent = getFolder()
	local found: Instance? = if RunService:IsServer()
		then parent:FindFirstChild(name)
		else parent:WaitForChild(name, 30)
	if not (found and found:IsA("RemoteEvent")) then
		error(`Net: remote "{name}" nao existe (chamaste Net.init no servidor?)`)
	end

	cache[name] = found
	return found
end

-- Rate limit (token bucket por jogador e por remote) --------------------------

type Bucket = { tokens: number, last: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

local function allow(player: Player, name: string, maxPerSecond: number): boolean
	if maxPerSecond <= 0 then
		return true
	end

	local perPlayer = buckets[player]
	if not perPlayer then
		perPlayer = {}
		buckets[player] = perPlayer
	end

	local now = os.clock()
	local bucket = perPlayer[name]
	if not bucket then
		bucket = { tokens = maxPerSecond, last = now }
		perPlayer[name] = bucket
	end

	bucket.tokens = math.min(maxPerSecond, bucket.tokens + (now - bucket.last) * maxPerSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- API -------------------------------------------------------------------------

-- Só no servidor: cria a pasta e os remotes. Chamar antes de qualquer serviço.
function Net.init()
	if not RunService:IsServer() then
		return
	end
	local parent = getFolder()
	for name in SPECS do
		if not parent:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = parent
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
end

-- Servidor: liga um handler já protegido por rate limit e validação.
function Net.onServerEvent(name: string, handler: (player: Player, ...any) -> ())
	local spec = SPECS[name]
	if not spec or spec.direction ~= "ToServer" then
		error(`Net: "{name}" nao e um remote cliente -> servidor`)
	end

	getRemote(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, name, spec.maxPerSecond) then
			return
		end
		local args: { any } = { ... }
		local count = select("#", ...)
		local validate = spec.validate
		if validate and not validate(args, count) then
			warn(`Net: argumentos invalidos em "{name}" de {player.Name}`)
			return
		end
		handler(player, ...)
	end)
end

function Net.fireClient(name: string, player: Player, payload: any)
	getRemote(name):FireClient(player, payload)
end

function Net.fireAllClients(name: string, payload: any)
	getRemote(name):FireAllClients(payload)
end

-- Cliente: envia uma intenção.
function Net.fireServer(name: string, ...: any)
	getRemote(name):FireServer(...)
end

-- Cliente: recebe estado.
function Net.onClientEvent(name: string, handler: (payload: any) -> ())
	local spec = SPECS[name]
	if not spec or spec.direction ~= "ToClient" then
		error(`Net: "{name}" nao e um remote servidor -> cliente`)
	end
	getRemote(name).OnClientEvent:Connect(handler)
end

return Net
