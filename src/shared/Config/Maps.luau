--!strict
--[[
	Config/Maps — geometria do mapa e das áreas de colocação.
	O servidor constrói o mapa a partir daqui e valida as posições;
	o cliente usa os mesmos números para desenhar a pré-visualização.

	Eixos: X = largura, Z = profundidade. A equipa A ocupa Z negativo,
	a equipa B ocupa Z positivo. O centro (Z = 0) é a linha divisória.
]]

local Types = require(script.Parent.Parent.Types)

export type Rect = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

export type MapDef = {
	id: string,
	-- Chão: X em [-width/2, width/2], Z em [-length/2, length/2]
	width: number,
	length: number,
	floorY: number,
	-- Faixa neutra (meia-largura) em volta de Z = 0 onde não se pode construir.
	neutralBand: number,
	-- Margem interior em que também não se pode construir.
	edgeMargin: number,
	-- Câmara fixa de cada equipa (a de B é espelhada em Z).
	cameraHeight: number,
	cameraBack: number,
	-- Alvo da camara, medido para o lado da propria equipa.
	cameraLookOwnZ: number,
	cameraFov: number,
	-- Cores do cenário.
	floorColor: Color3,
	halfAColor: Color3,
	halfBColor: Color3,
	teamAColor: Color3,
	teamBColor: Color3,
}

local Maps = {}

local flatArena: MapDef = {
	id = "flat_arena",
	width = 90,
	length = 150,
	floorY = 0,
	neutralBand = 8,
	edgeMargin = 5,
	-- Com estes valores o campo todo (150 studs de profundidade) cabe no ecra
	-- em 16:9 e em 4:3, sem a propria retaguarda ficar fora de vista.
	cameraHeight = 110,
	cameraBack = 150,
	cameraLookOwnZ = 10,
	cameraFov = 45,
	floorColor = Color3.fromRGB(86, 112, 78),
	halfAColor = Color3.fromRGB(74, 96, 128),
	halfBColor = Color3.fromRGB(128, 82, 78),
	teamAColor = Color3.fromRGB(86, 140, 220),
	teamBColor = Color3.fromRGB(220, 94, 86),
}

-- O mapa do protótipo. Quando houver mais do que um, entra aqui um registo.
Maps.default = flatArena

-- Retângulo onde `team` pode colocar unidades.
function Maps.buildRect(map: MapDef, team: Types.Team): Rect
	local halfWidth = map.width / 2 - map.edgeMargin
	local far = map.length / 2 - map.edgeMargin
	if team == "A" then
		return { minX = -halfWidth, maxX = halfWidth, minZ = -far, maxZ = -map.neutralBand }
	end
	return { minX = -halfWidth, maxX = halfWidth, minZ = map.neutralBand, maxZ = far }
end

-- Verifica se um círculo de raio `radius` cabe dentro da área da equipa.
function Maps.canPlace(map: MapDef, team: Types.Team, x: number, z: number, radius: number): boolean
	local rect = Maps.buildRect(map, team)
	return x - radius >= rect.minX
		and x + radius <= rect.maxX
		and z - radius >= rect.minZ
		and z + radius <= rect.maxZ
end

-- Mantém uma unidade dentro do chão durante a batalha (pode atravessar o centro).
function Maps.clampToArena(map: MapDef, x: number, z: number, radius: number): (number, number)
	local limitX = map.width / 2 - radius
	local limitZ = map.length / 2 - radius
	return math.clamp(x, -limitX, limitX), math.clamp(z, -limitZ, limitZ)
end

function Maps.teamColor(map: MapDef, team: Types.Team): Color3
	return if team == "A" then map.teamAColor else map.teamBColor
end

-- Câmara fixa por equipa: atrás da própria metade, a olhar para o centro.
function Maps.cameraCFrame(map: MapDef, team: Types.Team): CFrame
	local sign = if team == "A" then -1 else 1
	local position = Vector3.new(0, map.cameraHeight, sign * map.cameraBack)
	local lookAt = Vector3.new(0, 0, sign * map.cameraLookOwnZ)
	return CFrame.lookAt(position, lookAt)
end

return Maps
