--!strict
--[[
	Locale — todo o texto visível para o jogador.
	Nenhuma string de UI deve ser escrita diretamente num controlador.
	`Locale.get("key", arg)` substitui "{1}" pelo argumento.
]]

local Locale = {}

export type Language = "pt" | "en"

Locale.language = "pt" :: Language

local pt: { [string]: string } = {
	-- fases
	phase_lobby = "À espera de adversário",
	phase_prep = "Preparação",
	phase_reveal = "Exércitos revelados",
	phase_battle = "Batalha",
	phase_round_end = "Fim da ronda",
	phase_match_end = "Fim da partida",

	-- hud
	gold = "Ouro",
	round = "Ronda {1}",
	units = "Unidades {1}/{2}",
	ready = "Pronto",
	cancel_ready = "Cancelar",
	waiting_opponent = "À espera do adversário...",
	opponent_ready = "O adversário está pronto",
	sell_mode = "Vender",
	sell_mode_on = "A vender (toca numa unidade)",

	-- ajudas
	hint_place = "Arrasta para a tua metade para colocar",
	hint_drag = "Arrasta as tuas unidades para as mover",
	hint_battle = "A batalha começou. Boa sorte!",
	hint_lobby = "Precisas de 2 jogadores. Abre Test > 2 Players no Studio.",

	-- resultados
	you_win = "VITÓRIA",
	you_lose = "DERROTA",
	draw = "EMPATE",
	round_won = "Ganhaste a ronda",
	round_lost = "Perdeste a ronda",
	round_draw = "Ronda empatada",
	reason_elimination = "por eliminação",
	reason_timeout = "por valor em campo",
	reason_aborted = "partida interrompida",

	-- avisos do servidor
	not_enough_gold = "Ouro insuficiente",
	invalid_placement = "Tens de colocar na tua metade",
	unit_limit = "Limite de {1} unidades",
	too_close = "Demasiado perto de outra unidade",
	troop_locked = "Essa tropa ainda não está disponível",
	wrong_phase = "Só podes mexer no exército na preparação",
	opponent_left = "O adversário saiu",
	empty_army = "Coloca pelo menos uma unidade!",
}

local en: { [string]: string } = {
	phase_lobby = "Waiting for an opponent",
	phase_prep = "Preparation",
	phase_reveal = "Armies revealed",
	phase_battle = "Battle",
	phase_round_end = "Round over",
	phase_match_end = "Match over",

	gold = "Gold",
	round = "Round {1}",
	units = "Units {1}/{2}",
	ready = "Ready",
	cancel_ready = "Cancel",
	waiting_opponent = "Waiting for the opponent...",
	opponent_ready = "Opponent is ready",
	sell_mode = "Sell",
	sell_mode_on = "Selling (tap a unit)",

	hint_place = "Drag onto your half to place",
	hint_drag = "Drag your units to move them",
	hint_battle = "The battle has begun. Good luck!",
	hint_lobby = "Needs 2 players. Use Test > 2 Players in Studio.",

	you_win = "VICTORY",
	you_lose = "DEFEAT",
	draw = "DRAW",
	round_won = "You won the round",
	round_lost = "You lost the round",
	round_draw = "Round drawn",
	reason_elimination = "by elimination",
	reason_timeout = "on field value",
	reason_aborted = "match interrupted",

	not_enough_gold = "Not enough gold",
	invalid_placement = "Place it on your own half",
	unit_limit = "Limit of {1} units",
	too_close = "Too close to another unit",
	troop_locked = "That troop is not available yet",
	wrong_phase = "You can only edit your army during preparation",
	opponent_left = "The opponent left",
	empty_army = "Place at least one unit!",
}

local tables: { [string]: { [string]: string } } = { pt = pt, en = en }

-- Nome visível de cada tropa (o id fica em inglês no código).
local troopNames: { [string]: { [string]: string } } = {
	pt = {
		soldier = "Soldado",
		spearman = "Lanceiro",
		archer = "Arqueiro",
		shieldbearer = "Escudeiro",
		knight = "Cavaleiro",
		fire_mage = "Mago de Fogo",
		healer = "Curandeiro",
		giant = "Gigante",
	},
	en = {
		soldier = "Soldier",
		spearman = "Spearman",
		archer = "Archer",
		shieldbearer = "Shieldbearer",
		knight = "Knight",
		fire_mage = "Fire Mage",
		healer = "Healer",
		giant = "Giant",
	},
}

function Locale.get(key: string, ...: any): string
	local strings = tables[Locale.language] or pt
	local text = strings[key]
	if not text then
		return key
	end
	local count = select("#", ...)
	for index = 1, count do
		local value = select(index, ...)
		text = string.gsub(text, "{" .. index .. "}", tostring(value))
	end
	return text
end

function Locale.troopName(troopId: string): string
	local names = troopNames[Locale.language] or troopNames.pt
	return names[troopId] or troopId
end

return Locale
