--!strict
--[[
	Config/Leaderboard — a classificação global.

	Vive num OrderedDataStore separado do perfil: o perfil é a verdade do
	jogador, isto é só um índice para ordenar. Se a classificação se perder,
	ninguém perde troféus.

	**O nome do armazém leva a temporada.** Quando houver reset de temporada,
	muda-se `season` aqui e a classificação começa limpa sem apagar nada do que
	já existe — a tabela anterior fica lá, inteira, para consulta ou prémios.
]]

local Leaderboard = {}

Leaderboard.enabled = true

Leaderboard.storePrefix = "Trophies_S"
Leaderboard.season = 1

-- Quantos lugares se mostram.
Leaderboard.topCount = 10

-- De quanto em quanto tempo se vai buscar a tabela (segundos). Ler de 5 em 5
-- minutos chega: isto é para ver onde se está, não é um placar ao vivo.
Leaderboard.refreshInterval = 300

-- Intervalo mínimo entre duas escritas do mesmo jogador, para não gastar o
-- orçamento de pedidos do DataStore numa sessão de muitas partidas seguidas.
Leaderboard.minWriteInterval = 30

function Leaderboard.storeName(): string
	return Leaderboard.storePrefix .. tostring(Leaderboard.season)
end

return Leaderboard
