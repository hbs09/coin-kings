--!strict
--[[
	BotService — o adversário que não é um jogador.

	Hoje serve o tutorial: transforma o exército fixo de Config/Tutorial num
	exército válido para o MatchService, com ids próprios.

	Valida cada unidade com as mesmas regras do jogador — dentro da sua metade,
	sem sobreposições — e descarta (com aviso) o que não servir. Assim um erro
	de configuração aparece no arranque, e não a meio da primeira partida de
	alguém que acabou de chegar ao jogo.

	É também daqui que sai o adversário de treino quando a fila do PvP demora
	demasiado. Sem campanha, esse bot não é um extra: é o que segura o jogo nas
	horas em que não há duas pessoas online ao mesmo tempo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Tutorial = require(Shared.Config.Tutorial)
local BotConfig = require(Shared.Config.Bot)
local MatchConfig = require(Shared.Config.Match)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local BotService = {}

local map = Maps.default

-- O bot joga sempre do lado B.
local BOT_TEAM: Types.Team = "B"

-- `nextId` devolve o id seguinte; é o MatchService que gere o contador, para
-- os ids serem únicos entre as duas equipas.
function BotService.buildTutorialArmy(nextId: () -> number): { Types.ArmyEntry }
	local army: { Types.ArmyEntry } = {}

	for _, unit in Tutorial.enemy do
		local def = Troops.get(unit.troopId)
		if not def then
			warn(`BotService: o tutorial usa a tropa desconhecida "{unit.troopId}"`)
			continue
		end

		if not Maps.canPlace(map, BOT_TEAM, unit.x, unit.z, def.radius) then
			warn(`BotService: tutorial: {unit.troopId} em ({unit.x}, {unit.z}) fica fora da metade do bot; ignorado.`)
			continue
		end

		if not Placement.spacingOk(army, unit.x, unit.z, def, nil) then
			warn(`BotService: tutorial: {unit.troopId} em ({unit.x}, {unit.z}) sobrepoe outra unidade; ignorado.`)
			continue
		end

		table.insert(army, { id = nextId(), troopId = unit.troopId, x = unit.x, z = unit.z })
	end

	return army
end

-- Exercito de treino -----------------------------------------------------------

local random = Random.new()

-- Quantas unidades de cada tropa cabem no orcamento, segundo os pesos da
-- composicao sorteada. So conta tropas que o jogador ja tenha desbloqueado.
local function pickCounts(budget: number, pool: { Types.TroopId }): { [Types.TroopId]: number }
	local usable: { BotConfig.Composition } = {}
	for _, composition in BotConfig.compositions do
		for troopId in composition.weights do
			if table.find(pool, troopId) then
				table.insert(usable, composition)
				break
			end
		end
	end

	local counts: { [Types.TroopId]: number } = {}
	local spent = 0

	if #usable > 0 then
		local composition = usable[random:NextInteger(1, #usable)]

		local totalWeight = 0
		for troopId, weight in composition.weights do
			if table.find(pool, troopId) then
				totalWeight += weight
			end
		end

		if totalWeight > 0 then
			for troopId, weight in composition.weights do
				local def = Troops.get(troopId)
				if def and table.find(pool, troopId) then
					local share = budget * (weight / totalWeight)
					local amount = math.floor(share / def.cost)
					if amount > 0 then
						counts[troopId] = amount
						spent += amount * def.cost
					end
				end
			end
		end
	end

	-- O que sobrar vai para a tropa mais barata disponivel: nao se deixa ouro
	-- em cima da mesa, tal como um jogador nao deixaria.
	local cheapestId: Types.TroopId? = nil
	local cheapestCost = math.huge
	for _, troopId in pool do
		local def = Troops.get(troopId)
		if def and def.cost < cheapestCost then
			cheapestCost = def.cost
			cheapestId = troopId
		end
	end
	if not cheapestId then
		local def = Troops.get(BotConfig.fallbackTroop)
		if def then
			cheapestId = BotConfig.fallbackTroop
			cheapestCost = def.cost
		end
	end

	if cheapestId and cheapestCost > 0 and cheapestCost < math.huge then
		local extra = math.floor((budget - spent) / cheapestCost)
		if extra > 0 then
			counts[cheapestId] = (counts[cheapestId] or 0) + extra
		end
	end

	return counts
end

-- Poe uma lista de tropas em filas, a avancar na fila e a mudar de fila quando
-- chega ao fim da largura.
local function layOut(troopIds: { Types.TroopId }, startZ: number, army: { Types.ArmyEntry }, nextId: () -> number)
	local x = -BotConfig.spread
	local z = startZ

	for _, troopId in troopIds do
		local def = Troops.get(troopId)
		if not def then
			continue
		end
		if #army >= MatchConfig.maxUnitsPerPlayer then
			return
		end

		local step = math.max(BotConfig.columnStep, def.radius * 2 + 1)
		local placed = false

		for _ = 1, 200 do
			if x > BotConfig.spread then
				x = -BotConfig.spread
				z += BotConfig.rowStep
			end

			if Maps.canPlace(map, BOT_TEAM, x, z, def.radius) and Placement.spacingOk(army, x, z, def, nil) then
				table.insert(army, { id = nextId(), troopId = troopId, x = x, z = z })
				x += step
				placed = true
				break
			end

			x += step
		end

		if not placed then
			-- Sem espaco: o que falta tambem nao cabe.
			return
		end
	end
end

-- Exercito de treino para um orcamento e para as tropas que o jogador tem.
function BotService.buildArmy(budget: number, pool: { Types.TroopId }, nextId: () -> number): { Types.ArmyEntry }
	local counts = pickCounts(budget, pool)

	local melee: { Types.TroopId } = {}
	local ranged: { Types.TroopId } = {}
	for troopId, amount in counts do
		local def = Troops.get(troopId)
		if def then
			local list = if def.range > BotConfig.rangedThreshold then ranged else melee
			for _ = 1, amount do
				table.insert(list, troopId)
			end
		end
	end

	local army: { Types.ArmyEntry } = {}
	layOut(melee, BotConfig.meleeRowZ, army, nextId)
	layOut(ranged, BotConfig.rangedRowZ, army, nextId)
	return army
end

function BotService.init()
	-- Validação no arranque: um tutorial mal configurado aparece já aqui.
	local counter = 0
	local army = BotService.buildTutorialArmy(function(): number
		counter += 1
		return counter
	end)
	if #army ~= #Tutorial.enemy then
		warn("BotService: o tutorial tem unidades invalidas (ver avisos acima).")
	end
end

function BotService.start() end

return BotService
