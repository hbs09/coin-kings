--!strict
--[[
	RankService — troféus, arenas e desbloqueios.

	É o único sítio onde os troféus de um jogador mudam, e o único que decide
	que tropas é que ele pode usar.

	Os desbloqueios ficam **gravados no perfil** (`unlockedTroops`) em vez de
	serem calculados a partir dos troféus a cada consulta. A diferença importa:
	quem cair de arena mantém as tropas. Perder troféus custa estatuto, nunca
	ferramentas.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local RankConfig = require(Shared.Config.Rank)
local Troops = require(Shared.Config.Troops)

local DataService = require(script.Parent.DataService)

export type MatchOutcome = {
	trophies: number,
	delta: number,
	arenaId: string,
	-- Tropas que esta partida acabou de entregar (para avisar o jogador).
	unlocked: { Types.TroopId },
}

local RankService = {}

-- Garante que o perfil tem gravado tudo o que os seus troféus já deram.
-- Corre ao entrar e depois de cada partida: é isto que faz um jogador antigo
-- receber uma tropa nova se mudarmos as arenas em Config/Rank.
local function grantUnlocks(profile: Types.Profile): { Types.TroopId }
	local granted: { Types.TroopId } = {}
	for _, troopId in RankConfig.unlockedBy(profile.trophies) do
		if not profile.unlockedTroops[troopId] then
			profile.unlockedTroops[troopId] = true
			table.insert(granted, troopId)
		end
	end
	return granted
end

function RankService.getTrophies(player: Player): number
	local profile = DataService.get(player)
	return if profile then profile.trophies else RankConfig.startingTrophies
end

function RankService.getArena(player: Player): RankConfig.Arena
	return RankConfig.arenaFor(RankService.getTrophies(player))
end

-- As tropas que este jogador pode levar para uma partida, pela ordem da loja.
function RankService.unlockedPool(player: Player): { Types.TroopId }
	local profile = DataService.get(player)
	if not profile then
		-- Sem perfil carregado, vale o que a arena inicial dá.
		return RankConfig.unlockedBy(RankConfig.startingTrophies)
	end

	local pool: { Types.TroopId } = {}
	for _, troopId in Troops.order do
		if profile.unlockedTroops[troopId] then
			table.insert(pool, troopId)
		end
	end
	return pool
end

-- Aplica o resultado de uma partida PvP. Devolve nil se o perfil ainda não
-- tiver carregado (nesse caso não se mexe em nada).
function RankService.applyMatchResult(player: Player, opponentTrophies: number, won: boolean): MatchOutcome?
	local profile = DataService.get(player)
	if not profile then
		return nil
	end

	local outcome: MatchOutcome? = nil

	DataService.update(player, function(data: Types.Profile)
		local before = data.trophies
		local played = data.wins + data.losses
		local raw = RankConfig.change(before, opponentTrophies, won, played)

		-- O piso é o da arena onde se estava antes da partida: perde-se troféus
		-- dentro da arena, não se sai dela.
		local floor = RankConfig.floorFor(before)
		local updated = math.max(floor, before + raw)

		data.trophies = updated

		outcome = {
			trophies = updated,
			-- O delta que o jogador vê é o efetivo, já com o piso: tem de bater
			-- certo com o número que lhe muda à frente.
			delta = updated - before,
			arenaId = RankConfig.arenaFor(updated).id,
			unlocked = grantUnlocks(data),
		}
	end)

	return outcome
end

-- Atalho de teste: soma (ou tira) trofeus e entrega o que a nova arena der.
function RankService.adminAddTrophies(player: Player, delta: number): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end

	DataService.update(player, function(data: Types.Profile)
		data.trophies = math.max(0, data.trophies + delta)
		grantUnlocks(data)
	end)
	return true
end

-- Garante os desbloqueios da arena atual (usado depois de repor um perfil).
function RankService.ensureUnlocks(player: Player)
	DataService.update(player, function(data: Types.Profile)
		grantUnlocks(data)
	end)
end

function RankService.init()
	-- Quem entra recebe já o que os seus troféus dão (e quem é antigo recebe o
	-- que entretanto tivermos acrescentado às arenas).
	DataService.onProfileLoaded(function(player: Player)
		DataService.update(player, function(profile: Types.Profile)
			grantUnlocks(profile)
		end)
	end)
end

function RankService.start() end

return RankService
