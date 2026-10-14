--!strict
--[[
	Config/Admin — quem pode usar os atalhos de teste.

	**Nada disto é decidido pelo cliente.** O painel só aparece a quem o
	servidor disser que é admin, e cada comando é validado outra vez no
	servidor quando chega. Um botão escondido não é segurança nenhuma: se a
	verificação não estiver do lado do servidor, é só um exploit à espera do
	lançamento.

	Por omissão isto só funciona no Studio. Para testar num servidor a sério,
	põe o teu UserId em `userIds` — e tira-o antes de abrir o jogo ao público.
]]

local Admin = {}

-- No Studio qualquer um é admin: é a máquina de quem está a desenvolver.
Admin.allowStudio = true

-- UserIds com acesso em servidores a sério. Vazio = ninguém.
local userIds: { number } = {}
Admin.userIds = userIds

-- Velocidades de simulação oferecidas no painel.
local speeds: { number } = { 1, 2, 5 }
Admin.speeds = speeds

-- Quanto dão os botões de atalho.
Admin.goldGrant = 1000
Admin.trophyGrant = 150

return Admin
