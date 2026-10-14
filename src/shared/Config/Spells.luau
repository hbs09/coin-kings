--!strict
--[[
	Config/Spells — os feitiços e o que cada um faz.

	Compram-se na preparação, com o mesmo ouro das tropas, e lançam-se à mão
	durante a batalha. É a única coisa que o jogador decide com a batalha a
	correr, por isso é também a única em que a mão conta tanto como o plano.

	Cada feitiço comprado é **uma carga**: lança-se uma vez e acabou. Comprar
	dois meteoros dá dois meteoros. O limite por ronda está em `maxPerRound`.

	Como nas tropas, o custo vem do mesmo orçamento: um meteoro são sete
	soldados que não se compraram. Nunca se vende poder — compra-se escolha.
]]

local Types = require(script.Parent.Parent.Types)

export type SpellId = string

export type SpellDef = {
	id: SpellId,
	cost: number,
	-- Raio do efeito, em studs.
	radius: number,
	-- Dano imediato a quem for apanhado.
	damage: number,
	-- Segundos parado (0 = não congela).
	freezeDuration: number,
	-- Quem é apanhado pelo efeito.
	affects: "enemies" | "allies" | "all",
	color: Color3,
}

local Spells = {}

-- Quantos feitiços se podem levar para uma ronda.
Spells.maxPerRound = 2

-- Intervalo mínimo entre dois lançamentos, para não se despejar tudo no mesmo
-- instante (o servidor valida).
Spells.castCooldown = 1

local defs: { [SpellId]: SpellDef } = {
	meteor = {
		id = "meteor",
		cost = 150,
		radius = 8,
		damage = 120,
		freezeDuration = 0,
		affects = "enemies",
		color = Color3.fromRGB(236, 118, 68),
	},

	freeze = {
		id = "freeze",
		cost = 100,
		radius = 10,
		damage = 0,
		freezeDuration = 3,
		affects = "enemies",
		color = Color3.fromRGB(126, 198, 236),
	},
}

Spells.defs = defs

-- Ordem de apresentação na barra de feitiços.
local order: { SpellId } = { "meteor", "freeze" }
Spells.order = order

function Spells.get(spellId: SpellId): SpellDef?
	return defs[spellId]
end

-- Feitiços disponíveis nesta fase do roadmap (os outros dois entram no
-- lançamento: divine_shield e fury).
function Spells.isAvailable(spellId: SpellId): boolean
	return table.find(order, spellId) ~= nil
end

return Spells
