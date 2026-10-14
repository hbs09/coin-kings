--!strict
--[[
	BotService — o adversário que não é um jogador.

	Hoje faz uma coisa só: transformar o exército fixo de um capítulo
	(Config/Campaign) num exército válido para o MatchService, com ids próprios.

	Valida cada unidade com as mesmas regras do jogador — dentro da sua metade,
	sem sobreposições — e descarta (com aviso) o que não servir. Assim um erro
	de configuração aparece no arranque, em vez de dar um bot com unidades
	dentro da parede.

	No MVP é também daqui que sai o exército aleatório para um orçamento, quando
	a fila do PvP passar dos 20 s e for preciso um adversário de treino.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Campaign = require(Shared.Config.Campaign)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local BotService = {}

local map = Maps.default

-- O bot joga sempre do lado B.
local BOT_TEAM: Types.Team = "B"

-- `nextId` devolve o id seguinte; é o MatchService que gere o contador, para
-- os ids serem únicos entre as duas equipas.
function BotService.buildCampaignArmy(chapterId: string, nextId: () -> number): { Types.ArmyEntry }
	local chapter = Campaign.get(chapterId)
	if not chapter then
		warn(`BotService: capitulo desconhecido "{chapterId}"`)
		return {}
	end

	local army: { Types.ArmyEntry } = {}

	for _, unit in chapter.enemy do
		local def = Troops.get(unit.troopId)
		if not def then
			warn(`BotService: capitulo "{chapterId}" usa a tropa desconhecida "{unit.troopId}"`)
			continue
		end

		if not Maps.canPlace(map, BOT_TEAM, unit.x, unit.z, def.radius) then
			warn(
				`BotService: capitulo "{chapterId}": {unit.troopId} em ({unit.x}, {unit.z}) `
					.. "fica fora da metade do bot; ignorado."
			)
			continue
		end

		if not Placement.spacingOk(army, unit.x, unit.z, def, nil) then
			warn(
				`BotService: capitulo "{chapterId}": {unit.troopId} em ({unit.x}, {unit.z}) `
					.. "sobrepoe outra unidade; ignorado."
			)
			continue
		end

		table.insert(army, { id = nextId(), troopId = unit.troopId, x = unit.x, z = unit.z })
	end

	return army
end

function BotService.init()
	-- Validação no arranque: um capítulo mal configurado aparece já aqui, e não
	-- a meio de uma partida de um jogador.
	local counter = 0
	local function nextId(): number
		counter += 1
		return counter
	end

	for _, chapter in Campaign.chapters do
		local army = BotService.buildCampaignArmy(chapter.id, nextId)
		if #army ~= #chapter.enemy then
			warn(`BotService: o capitulo "{chapter.id}" tem unidades invalidas (ver avisos acima).`)
		end
	end
end

function BotService.start() end

return BotService
