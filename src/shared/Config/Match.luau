--!strict
--[[
	Config/Match — regras e tempos da partida.
	Fase 2 (MVP): melhor de 3, as 8 tropas, sem feitiços nem Elo.
]]

local Types = require(script.Parent.Parent.Types)

local Match = {}

-- Economia
Match.startingGold = 1000
Match.loserBonus = 150 -- ouro extra para quem perdeu a ronda anterior

-- Formato: melhor de 3
Match.roundsToWin = 2
Match.maxRounds = 3

-- Duração das fases, em segundos
-- Espera maxima na fila antes de arrancar um treino contra o bot. Num 1v1,
-- deixar alguem a olhar para uma fila vazia e a forma mais rapida de o perder.
Match.queueBotAfter = 20

Match.lobbyCountdown = 3
Match.prepDuration = 45
Match.revealDuration = 3
Match.battleDuration = 90
Match.roundEndDuration = 5
Match.matchEndDuration = 8
-- No tutorial o ecra de fim tem botoes: quem decide quando sair e o jogador.
-- Isto e so a rede de seguranca para nao deixar uma arena ocupada por alguem
-- que foi almocar.
Match.tutorialResultTimeout = 180

-- Limites técnicos
-- Partidas em paralelo no mesmo servidor. Cada uma ocupa uma arena (um "slot").
-- Com servidores de 2 jogadores o matchmaking nao sobrevive: 40 jogadores online
-- ficariam espalhados por 20 servidores isolados, cada fila a ver 2 pessoas.
-- O lugar no Studio tem de ter maxPlayers = maxMatchesPerServer * 2.
Match.maxMatchesPerServer = 6
Match.maxUnitsPerPlayer = 40
Match.tickRate = 10 -- Hz da simulação no servidor
Match.minUnitSpacing = 0.5 -- folga mínima entre as bordas de duas unidades, em studs

-- Tropas disponíveis nesta fase do roadmap (as 8 do MVP)
local troopPool: { Types.TroopId } = {
	"soldier",
	"spearman",
	"archer",
	"shieldbearer",
	"knight",
	"healer",
	"fire_mage",
	"giant",
}
Match.troopPool = troopPool

return Match
