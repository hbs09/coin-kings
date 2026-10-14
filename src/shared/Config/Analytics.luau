--!strict
--[[
	Config/Analytics — o que se mede e como se chamam os eventos.

	Mede-se o que decide o roadmap, e mais nada:

	- **partidas por sessão** e **tempo de fila**, que são dois dos três
	  critérios do travão (CLAUDE.md);
	- o **funil do tutorial**, para saber onde é que um jogador novo desiste;
	- a duração e o resultado das partidas, para perceber o ritmo.

	O D1 e a duração média de sessão vêm de graça no painel do criador: não
	vale a pena duplicá-los aqui.

	Os testes do Studio não contam por omissão — senão os dados reais ficam
	cheios de sessões de dois minutos em que se está a experimentar código.
]]

local Analytics = {}

Analytics.enabled = true
Analytics.logInStudio = false

-- Nomes dos eventos personalizados (aparecem assim no painel do criador).
Analytics.events = {
	matchStart = "match_start",
	matchEnd = "match_end",
	queueWait = "queue_wait",
	sessionEnd = "session_end",
}

-- Funil de entrada: onde é que se perde quem acabou de chegar.
Analytics.tutorialFunnel = {
	started = 1,
	firstUnit = 2,
	battle = 3,
	finished = 4,
}

Analytics.tutorialStepNames = {
	"tutorial_started",
	"tutorial_first_unit",
	"tutorial_battle",
	"tutorial_finished",
}

return Analytics
