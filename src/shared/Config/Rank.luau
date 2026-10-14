--!strict
--[[
	Config/Rank — troféus e arenas.

	Os troféus são a progressão do jogo: ganha-se no PvP, sobe-se de arena, e
	**cada arena desbloqueia uma tropa nova**. É isto que dá objetivo a quem
	joga online.

	Três regras que não se mexem sem pensar duas vezes:

	1. **O desbloqueio é permanente.** Cair de troféus faz descer de arena, mas
	   nunca tira uma tropa que já era do jogador. Tirar algo conquistado é a
	   pior sensação que um jogo pode dar.
	2. **Não se cai abaixo do piso da arena em que se está.** Perde-se troféus
	   dentro da arena, não se sai dela.
	3. **As tropas novas não são mais fortes, são outras opções.** Não há
	   níveis de tropa: um gigante não bate um soldado "por ser melhor", custa
	   12 vezes mais do mesmo orçamento. É o que mantém o duelo justo mesmo com
	   desbloqueios — e é a diferença entre isto e um jogo de coleção.
]]

local Types = require(script.Parent.Parent.Types)

export type Arena = {
	id: string,
	nameKey: string,
	-- Troféus mínimos para entrar (e piso: não se cai abaixo disto).
	trophies: number,
	-- Tropas que esta arena entrega, para sempre.
	unlocks: { Types.TroopId },
	-- Aspeto do campo nesta arena.
	floorColor: Color3,
	halfAColor: Color3,
	halfBColor: Color3,
}

local Rank = {}

Rank.startingTrophies = 0

-- Oscilação maior nas primeiras partidas, para o jogador chegar depressa ao
-- sítio onde pertence em vez de subir aos poucos durante uma semana.
Rank.placementMatches = 20
Rank.kPlacement = 48
Rank.kNormal = 28
-- Ganhar tem de valer sempre alguma coisa, mesmo contra alguém muito abaixo.
Rank.minChange = 8
Rank.maxChange = 60

local arenas: { Arena } = {
	{
		id = "training",
		nameKey = "arena_training",
		trophies = 0,
		unlocks = { "soldier", "archer", "knight" },
		floorColor = Color3.fromRGB(86, 112, 78),
		halfAColor = Color3.fromRGB(74, 96, 128),
		halfBColor = Color3.fromRGB(128, 82, 78),
	},
	{
		id = "swamp",
		nameKey = "arena_swamp",
		trophies = 200,
		unlocks = { "spearman" },
		floorColor = Color3.fromRGB(66, 92, 70),
		halfAColor = Color3.fromRGB(64, 88, 116),
		halfBColor = Color3.fromRGB(116, 74, 70),
	},
	{
		id = "forge",
		nameKey = "arena_forge",
		trophies = 500,
		unlocks = { "shieldbearer" },
		floorColor = Color3.fromRGB(96, 86, 78),
		halfAColor = Color3.fromRGB(80, 94, 122),
		halfBColor = Color3.fromRGB(134, 84, 70),
	},
	{
		id = "desert",
		nameKey = "arena_desert",
		trophies = 900,
		unlocks = { "fire_mage" },
		floorColor = Color3.fromRGB(176, 150, 102),
		halfAColor = Color3.fromRGB(96, 110, 140),
		halfBColor = Color3.fromRGB(150, 94, 76),
	},
	{
		id = "temple",
		nameKey = "arena_temple",
		trophies = 1400,
		unlocks = { "healer" },
		floorColor = Color3.fromRGB(120, 124, 110),
		halfAColor = Color3.fromRGB(88, 102, 150),
		halfBColor = Color3.fromRGB(148, 88, 94),
	},
	{
		id = "frost",
		nameKey = "arena_frost",
		trophies = 2000,
		unlocks = { "giant" },
		floorColor = Color3.fromRGB(198, 212, 222),
		halfAColor = Color3.fromRGB(96, 126, 176),
		halfBColor = Color3.fromRGB(162, 98, 104),
	},
	{
		id = "legend",
		nameKey = "arena_legend",
		trophies = 3000,
		-- A última não dá tropas: a esta altura já estão todas. Dá estatuto.
		unlocks = {},
		floorColor = Color3.fromRGB(58, 52, 86),
		halfAColor = Color3.fromRGB(78, 96, 170),
		halfBColor = Color3.fromRGB(160, 80, 120),
	},
}

Rank.arenas = arenas

-- A arena em que se está com estes troféus.
function Rank.arenaFor(trophies: number): Arena
	local current = arenas[1]
	for _, arena in arenas do
		if trophies >= arena.trophies then
			current = arena
		end
	end
	return current
end

-- A seguinte, ou nil se já se chegou ao fim.
function Rank.nextArena(trophies: number): Arena?
	for _, arena in arenas do
		if arena.trophies > trophies then
			return arena
		end
	end
	return nil
end

-- Tudo o que estes troféus já deram.
function Rank.unlockedBy(trophies: number): { Types.TroopId }
	local unlocked: { Types.TroopId } = {}
	for _, arena in arenas do
		if trophies >= arena.trophies then
			for _, troopId in arena.unlocks do
				table.insert(unlocked, troopId)
			end
		end
	end
	return unlocked
end

-- Que arena entrega esta tropa (a loja usa isto para dizer o que falta).
function Rank.arenaOf(troopId: Types.TroopId): Arena?
	for _, arena in arenas do
		if table.find(arena.unlocks, troopId) then
			return arena
		end
	end
	return nil
end

-- Não se cai abaixo do piso da arena atual.
function Rank.floorFor(trophies: number): number
	return Rank.arenaFor(trophies).trophies
end

-- Quanto vale esta partida. Fórmula de Elo, mas o número é visível.
function Rank.change(selfTrophies: number, opponentTrophies: number, won: boolean, matchesPlayed: number): number
	local k = if matchesPlayed < Rank.placementMatches then Rank.kPlacement else Rank.kNormal
	local expected = 1 / (1 + 10 ^ ((opponentTrophies - selfTrophies) / 400))
	local score = if won then 1 else 0
	local raw = k * (score - expected)

	local magnitude = math.clamp(math.abs(raw), Rank.minChange, Rank.maxChange)
	local rounded = math.round(magnitude)
	return if won then rounded else -rounded
end

return Rank
