--!strict
--[[
	Config/Campaign — os capítulos da campanha a solo.

	Cada capítulo é um puzzle: orçamento fixo, loja limitada e um exército
	inimigo sempre igual. O jogador tem de descobrir **o counter**, não moer
	recursos — por isso a dificuldade vem da composição do inimigo, nunca de
	dar mais vida ou mais dano ao bot.

	Ordem pensada para ensinar uma lição de cada vez:
	  1. como se compra e posiciona
	  2. arqueiros morrem a cavalaria
	  3. cavalaria morre a lanceiros
	  4. tanques morrem a dano em área e a distância
	  5. hordas morrem a dano em área
	  6. elites morrem a muitos lanceiros (e trata dos curandeiros primeiro)

	As posições do inimigo são locais à arena e têm de caber na metade da
	equipa B (Z positivo). O BotService valida-as no arranque e avisa se
	alguma ficar fora ou sobreposta.
]]

local Types = require(script.Parent.Parent.Types)

export type EnemyUnit = {
	troopId: Types.TroopId,
	x: number,
	z: number,
}

export type Chapter = {
	id: string,
	-- Chave do Locale, não o texto: o nome do capítulo é traduzido.
	nameKey: string,
	hintKey: string,
	gold: number,
	-- Tropas à venda neste capítulo. A loja do cliente e a validação do
	-- servidor usam esta lista em vez do troopPool global.
	troopPool: { Types.TroopId },
	enemy: { EnemyUnit },
	rewardXp: number,
	rewardCoins: number,
}

local Campaign = {}

local chapters: { Chapter } = {
	{
		id = "first_steps",
		nameKey = "chapter_first_steps",
		hintKey = "chapter_first_steps_hint",
		gold = 120,
		troopPool = { "soldier" },
		enemy = {
			{ troopId = "soldier", x = -7, z = 20 },
			{ troopId = "soldier", x = 0, z = 20 },
			{ troopId = "soldier", x = 7, z = 20 },
		},
		rewardXp = 50,
		rewardCoins = 20,
	},

	{
		id = "arrow_line",
		nameKey = "chapter_arrow_line",
		hintKey = "chapter_arrow_line_hint",
		gold = 240,
		troopPool = { "soldier", "knight" },
		enemy = {
			{ troopId = "archer", x = -15, z = 32 },
			{ troopId = "archer", x = -5, z = 32 },
			{ troopId = "archer", x = 5, z = 32 },
			{ troopId = "archer", x = 15, z = 32 },
			{ troopId = "soldier", x = -6, z = 18 },
			{ troopId = "soldier", x = 6, z = 18 },
		},
		rewardXp = 60,
		rewardCoins = 25,
	},

	{
		id = "cavalry",
		nameKey = "chapter_cavalry",
		hintKey = "chapter_cavalry_hint",
		gold = 320,
		troopPool = { "soldier", "spearman", "archer" },
		enemy = {
			{ troopId = "knight", x = -14, z = 24 },
			{ troopId = "knight", x = 0, z = 24 },
			{ troopId = "knight", x = 14, z = 24 },
		},
		rewardXp = 70,
		rewardCoins = 30,
	},

	{
		id = "the_wall",
		nameKey = "chapter_the_wall",
		hintKey = "chapter_the_wall_hint",
		gold = 420,
		troopPool = { "soldier", "spearman", "archer", "fire_mage" },
		enemy = {
			{ troopId = "shieldbearer", x = -12, z = 20 },
			{ troopId = "shieldbearer", x = -4, z = 20 },
			{ troopId = "shieldbearer", x = 4, z = 20 },
			{ troopId = "shieldbearer", x = 12, z = 20 },
			{ troopId = "archer", x = -6, z = 34 },
			{ troopId = "archer", x = 6, z = 34 },
		},
		rewardXp = 80,
		rewardCoins = 35,
	},

	{
		id = "horde",
		nameKey = "chapter_horde",
		hintKey = "chapter_horde_hint",
		gold = 520,
		troopPool = { "soldier", "spearman", "archer", "shieldbearer", "knight", "fire_mage" },
		enemy = {
			{ troopId = "soldier", x = -18, z = 18 },
			{ troopId = "soldier", x = -12, z = 18 },
			{ troopId = "soldier", x = -6, z = 18 },
			{ troopId = "soldier", x = 0, z = 18 },
			{ troopId = "soldier", x = 6, z = 18 },
			{ troopId = "soldier", x = 12, z = 18 },
			{ troopId = "soldier", x = 18, z = 18 },
			{ troopId = "soldier", x = -15, z = 25 },
			{ troopId = "soldier", x = -9, z = 25 },
			{ troopId = "soldier", x = -3, z = 25 },
			{ troopId = "soldier", x = 3, z = 25 },
			{ troopId = "soldier", x = 9, z = 25 },
			{ troopId = "soldier", x = 15, z = 25 },
		},
		rewardXp = 90,
		rewardCoins = 40,
	},

	{
		id = "the_giant",
		nameKey = "chapter_the_giant",
		hintKey = "chapter_the_giant_hint",
		gold = 680,
		troopPool = { "soldier", "spearman", "archer", "shieldbearer", "knight", "healer", "fire_mage", "giant" },
		enemy = {
			{ troopId = "giant", x = 0, z = 22 },
			{ troopId = "shieldbearer", x = -10, z = 18 },
			{ troopId = "shieldbearer", x = 10, z = 18 },
			{ troopId = "healer", x = -6, z = 36 },
			{ troopId = "healer", x = 6, z = 36 },
		},
		rewardXp = 120,
		rewardCoins = 60,
	},
}

Campaign.chapters = chapters

-- A campanha é uma ronda só: é um puzzle, não um duelo.
Campaign.roundsToWin = 1
Campaign.maxRounds = 1

function Campaign.get(chapterId: string): Chapter?
	for _, chapter in chapters do
		if chapter.id == chapterId then
			return chapter
		end
	end
	return nil
end

local function indexOf(chapterId: string): number?
	for index, chapter in chapters do
		if chapter.id == chapterId then
			return index
		end
	end
	return nil
end

-- Um capítulo abre quando o anterior estiver feito. O primeiro está sempre
-- aberto, para nunca haver um jogador sem nada para fazer.
function Campaign.isUnlocked(chapterId: string, completed: { [string]: boolean }): boolean
	local index = indexOf(chapterId)
	if not index then
		return false
	end
	if index == 1 then
		return true
	end
	local previous = chapters[index - 1]
	return completed[previous.id] == true
end

return Campaign
