--!strict
--[[
	Config/Bot — como o adversário de treino monta o exército dele.

	Serve as partidas que arrancam quando a fila do PvP demora demasiado. Sem
	isto, um servidor com uma pessoa só é um jogo que não se pode jogar — e com
	um 1v1 isso acontece em todas as horas mortas.

	Duas regras que mantêm o treino honesto:

	- **O bot joga com o mesmo orçamento que o jogador.** A dificuldade vem da
	  composição que calha, nunca de dar mais ouro ou mais vida ao bot.
	- **O bot só usa tropas que o jogador já desbloqueou.** Perder para um
	  gigante que ainda nem se viu não ensina nada.

	Os pesos são a fatia do orçamento que vai para cada tropa. A composição é
	sorteada a cada ronda, para o treino não ser sempre o mesmo problema.
]]

local Types = require(script.Parent.Parent.Types)

export type Composition = {
	id: string,
	weights: { [Types.TroopId]: number },
}

local Bot = {}

local compositions: { Composition } = {
	-- Muita gente barata: castiga quem não leva dano em área.
	{ id = "horde", weights = { soldier = 1 } },
	-- O clássico: linha à frente, distância atrás.
	{ id = "line", weights = { soldier = 0.5, archer = 0.5 } },
	-- Anti-cavalaria com apoio.
	{ id = "spears", weights = { spearman = 0.6, archer = 0.4 } },
	-- Muro: aguenta de frente e castiga quem não tem área.
	{ id = "wall", weights = { shieldbearer = 0.55, archer = 0.45 } },
	-- Rápida: vai direta aos arqueiros.
	{ id = "cavalry", weights = { knight = 0.6, soldier = 0.4 } },
	-- Um pouco de tudo.
	{ id = "mixed", weights = { soldier = 0.3, archer = 0.3, spearman = 0.2, knight = 0.2 } },
}

Bot.compositions = compositions

-- Tropa a usar quando nada da composição sorteada está desbloqueado.
Bot.fallbackTroop = "soldier" :: Types.TroopId

-- Formação: corpo a corpo à frente, distância atrás (Z é a profundidade da
-- metade do bot, que começa na faixa neutra).
Bot.meleeRowZ = 14
Bot.rangedRowZ = 32
Bot.rowStep = 6
Bot.columnStep = 7
-- Meia-largura usada para espalhar as filas.
Bot.spread = 34
-- Acima deste alcance a tropa é tratada como de distância.
Bot.rangedThreshold = 8

return Bot
