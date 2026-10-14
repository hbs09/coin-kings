--!strict
--[[
	Util/Placement — a regra de "esta posicao serve?".

	Vive no shared para o servidor validar e o cliente poder pintar a
	pre-visualizacao de verde ou vermelho com exatamente o mesmo criterio.
	A decisao continua a ser do servidor: aqui so esta a regra, lida de Config.
]]

local Types = require(script.Parent.Parent.Types)
local Maps = require(script.Parent.Parent.Config.Maps)
local MatchConfig = require(script.Parent.Parent.Config.Match)
local Troops = require(script.Parent.Parent.Config.Troops)

local Placement = {}

-- Distancia minima entre centros de duas unidades.
local function minDistance(a: Types.TroopDef, b: Types.TroopDef): number
	return a.radius + b.radius + MatchConfig.minUnitSpacing
end

-- `ignoreId` serve para mover uma unidade sem ela colidir consigo mesma.
function Placement.spacingOk(
	army: { Types.ArmyEntry },
	x: number,
	z: number,
	def: Types.TroopDef,
	ignoreId: number?
): boolean
	for _, entry in army do
		if entry.id ~= ignoreId then
			local other = Troops.get(entry.troopId)
			if other then
				local dx = entry.x - x
				local dz = entry.z - z
				local limit = minDistance(def, other)
				if dx * dx + dz * dz < limit * limit then
					return false
				end
			end
		end
	end
	return true
end

-- Dentro da propria metade e sem sobrepor nada.
function Placement.isValid(
	team: Types.Team,
	army: { Types.ArmyEntry },
	x: number,
	z: number,
	def: Types.TroopDef,
	ignoreId: number?
): boolean
	if not Maps.canPlace(Maps.default, team, x, z, def.radius) then
		return false
	end
	return Placement.spacingOk(army, x, z, def, ignoreId)
end

return Placement
