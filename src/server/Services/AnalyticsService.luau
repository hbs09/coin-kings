--!strict
--[[
	AnalyticsService — o que se mede, medido.

	Usa o AnalyticsService do próprio Roblox, que alimenta o painel do criador.
	Sem serviços externos, sem HTTP, sem custos — e os números aparecem ao lado
	da retenção D1, que é onde se vão ler juntos.

	Duas regras:

	1. **Telemetria nunca parte o jogo.** Todas as chamadas vão em pcall. Um
	   erro a medir não pode estragar uma partida de ninguém; no pior caso
	   perde-se um número.
	2. **O Studio não polui os dados reais** (Config/Analytics.logInStudio).
	   Sem isto, as sessões de dois minutos a testar código entravam na média
	   e as decisões do roadmap passavam a ser tomadas sobre dados nossos.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnalyticsConfig = require(ReplicatedStorage.Shared.Config.Analytics)

local Service = {}

type Session = {
	startedAt: number,
	matches: number,
}

local sessions: { [Player]: Session } = {}
local warned = false

local function active(): boolean
	if not AnalyticsConfig.enabled then
		return false
	end
	if RunService:IsStudio() and not AnalyticsConfig.logInStudio then
		return false
	end
	return true
end

-- Envolve qualquer chamada de telemetria: falhar a medir nunca pode falhar o
-- jogo, e um aviso chega (repetir o mesmo erro a cada partida nao ajuda).
local function safely(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok and not warned then
		warned = true
		warn(`AnalyticsService: {label} falhou ({err}). A telemetria fica desligada ate reiniciar.`)
	end
end

local function logEvent(player: Player, eventName: string, value: number?, field: string?)
	if not active() then
		return
	end

	safely(eventName, function()
		local fields: { [string]: string } = {}
		if field then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = field
		end
		AnalyticsService:LogCustomEvent(player, eventName, value, fields)
	end)
end

-- API -------------------------------------------------------------------------

function Service.logMatchStart(player: Player, mode: string)
	local session = sessions[player]
	if session then
		session.matches += 1
	end
	logEvent(player, AnalyticsConfig.events.matchStart, 1, mode)
end

-- `duration` em segundos: e o ritmo real de uma partida, que e o que decide se
-- um jogador encadeia a seguinte ou vai embora.
function Service.logMatchEnd(player: Player, mode: string, result: string, duration: number)
	logEvent(player, AnalyticsConfig.events.matchEnd, math.floor(duration), `{mode}_{result}`)
end

-- Tempo de fila: acima de 20 s no pico de jogadores, o PvP nao se sustenta
-- sozinho (ver "O travao" no CLAUDE.md).
function Service.logQueueWait(player: Player, seconds: number, outcome: string)
	logEvent(player, AnalyticsConfig.events.queueWait, math.floor(seconds), outcome)
end

-- Funil de entrada: em que passo e que se perde quem acabou de chegar.
function Service.logTutorialStep(player: Player, step: number)
	if not active() then
		return
	end

	local name = AnalyticsConfig.tutorialStepNames[step]
	if not name then
		return
	end

	safely("funil do tutorial", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

function Service.init()
	Players.PlayerAdded:Connect(function(player: Player)
		sessions[player] = { startedAt = os.clock(), matches = 0 }
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		local session = sessions[player]
		sessions[player] = nil
		if not session then
			return
		end

		-- Partidas por sessao: o segundo criterio do travao. O valor do evento
		-- e o numero de partidas; a duracao da sessao ja vem do painel.
		logEvent(player, AnalyticsConfig.events.sessionEnd, session.matches)
	end)

	for _, player in Players:GetPlayers() do
		sessions[player] = { startedAt = os.clock(), matches = 0 }
	end
end

function Service.start() end

return Service
