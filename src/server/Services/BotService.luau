--!strict
--[[
	BotService — o adversário que não é um jogador.

	Hoje serve o tutorial: transforma o exército fixo de Config/Tutorial num
	exército válido para o MatchService, com ids próprios.

	Valida cada unidade com as mesmas regras do jogador — dentro da sua metade,
	sem sobreposições — e descarta (com aviso) o que não servir. Assim um erro
	de configuração aparece no arranque, e não a meio da primeira partida de
	alguém que acabou de chegar ao jogo.

	É também daqui que vai sair o adversário de treino quando a fila do PvP
	passar dos 20 s. Sem campanha, esse bot deixa de ser um extra: é o que
	segura o jogo quando houver poucos jogadores online.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Tutorial = require(Shared.Config.Tutorial)
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
