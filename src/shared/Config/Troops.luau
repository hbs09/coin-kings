--!strict
--[[
	Config/Troops — ÚNICA fonte dos valores de balanceamento das tropas.
	Nenhum destes números deve ser repetido na lógica do jogo.

	`bonusVs` descreve sempre o lado do atacante: "soldier é forte vs archer"
	escreve-se em soldier.bonusVs.archer. O "fraco vs" aparece implicitamente
	no bonusVs do adversário.
]]

local Types = require(script.Parent.Parent.Types)

type TroopDef = Types.TroopDef
type TroopId = Types.TroopId

local Troops = {}

local defs: { [TroopId]: TroopDef } = {
	soldier = {
		id = "soldier",
		cost = 20,
		hp = 100,
		damage = 10,
		range = 1.5,
		attackSpeed = 1.0,
		moveSpeed = 10,
		bonusVs = { archer = 1.5 },
		radius = 1.4,
		height = 4,
		color = Color3.fromRGB(176, 182, 196),
		weapon = "sword",
	},

	spearman = {
		id = "spearman",
		cost = 35,
		hp = 120,
		damage = 14,
		range = 4,
		attackSpeed = 0.9,
		moveSpeed = 9,
		bonusVs = { knight = 2.0, giant = 1.4 },
		radius = 1.5,
		height = 4.2,
		color = Color3.fromRGB(124, 150, 116),
		weapon = "spear",
	},

	archer = {
		id = "archer",
		cost = 40,
		hp = 70,
		damage = 16,
		range = 26,
		attackSpeed = 0.8,
		moveSpeed = 8,
		bonusVs = { soldier = 1.25, spearman = 1.25, shieldbearer = 1.1 },
		radius = 1.3,
		height = 3.8,
		color = Color3.fromRGB(104, 178, 118),
		weapon = "bow",
	},

	shieldbearer = {
		id = "shieldbearer",
		cost = 60,
		hp = 320,
		damage = 12,
		range = 1.5,
		attackSpeed = 0.8,
		moveSpeed = 7,
		bonusVs = { archer = 1.5 },
		radius = 1.8,
		height = 4.2,
		color = Color3.fromRGB(150, 140, 110),
		weapon = "sword",
		shield = true,
	},

	knight = {
		id = "knight",
		cost = 80,
		hp = 200,
		damage = 26,
		range = 2,
		attackSpeed = 1.0,
		moveSpeed = 18,
		bonusVs = { archer = 1.6, fire_mage = 1.8, healer = 1.6 },
		radius = 1.7,
		height = 5,
		color = Color3.fromRGB(226, 186, 92),
		weapon = "sword",
		shield = true,
	},

	fire_mage = {
		id = "fire_mage",
		cost = 120,
		hp = 90,
		damage = 30,
		range = 22,
		attackSpeed = 0.45,
		moveSpeed = 7,
		aoeRadius = 8,
		bonusVs = { soldier = 1.2, spearman = 1.2 },
		radius = 1.4,
		height = 4.4,
		color = Color3.fromRGB(226, 106, 72),
		weapon = "staff",
	},

	healer = {
		id = "healer",
		cost = 100,
		hp = 110,
		damage = 0,
		range = 12,
		attackSpeed = 0.7,
		moveSpeed = 8,
		healAmount = 20,
		bonusVs = {},
		radius = 1.3,
		height = 4,
		color = Color3.fromRGB(240, 236, 170),
		weapon = "staff",
	},

	giant = {
		id = "giant",
		cost = 250,
		hp = 1200,
		damage = 60,
		range = 2.5,
		attackSpeed = 0.5,
		moveSpeed = 6,
		aoeRadius = 5,
		bonusVs = { soldier = 1.5, archer = 1.3 },
		radius = 3.2,
		height = 9,
		color = Color3.fromRGB(150, 110, 150),
		weapon = "club",
	},
}

Troops.defs = defs

-- Ordem de apresentação na loja (do mais barato ao mais caro).
local order: { TroopId } = { "soldier", "spearman", "archer", "shieldbearer", "knight", "healer", "fire_mage", "giant" }

Troops.order = order

function Troops.get(troopId: TroopId): TroopDef?
	return defs[troopId]
end

return Troops
