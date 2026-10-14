--!strict
--[[
	Config/Tutorial — a primeira partida de quem acaba de chegar.

	Uma vez só, contra um bot fraco, com as tropas da Arena 1 (as que o jogador
	já tem). Serve para aprender a comprar, arrastar e ver a batalha sem ter
	outro jogador do outro lado a esmagá-lo.

	É de propósito que se ganha com folga: o orçamento dá para mais do que o
	inimigo tem. A primeira partida de um jogador decide se há segunda.
]]

local Types = require(script.Parent.Parent.Types)

export type EnemyUnit = {
	troopId: Types.TroopId,
	x: number,
	z: number,
}

local Tutorial = {}

Tutorial.gold = 150

-- Exército do bot. As posições são locais à arena e têm de caber na metade da
-- equipa B (Z positivo); o BotService valida e avisa se alguma ficar de fora.
-- Quatro soldados a frente e um arqueiro atras: ja obriga a pensar em numero
-- e em avancar, mas continua a ganhar-se com folga. A primeira partida de um
-- jogador decide se ha segunda.
local enemy: { EnemyUnit } = {
	{ troopId = "soldier", x = -11, z = 20 },
	{ troopId = "soldier", x = -4, z = 20 },
	{ troopId = "soldier", x = 4, z = 20 },
	{ troopId = "soldier", x = 11, z = 20 },
	{ troopId = "archer", x = 0, z = 31 },
}

Tutorial.enemy = enemy

-- Recompensa de quem o termina.
Tutorial.rewardXp = 50
Tutorial.rewardCoins = 50

return Tutorial
