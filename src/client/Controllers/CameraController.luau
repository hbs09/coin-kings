--!strict
--[[
	CameraController — camara fixa sobre o campo.

	Nesta fase os jogadores nao tem personagem: a camara e posicionada atras da
	propria metade, com os valores de Config/Maps, para os dois verem o mesmo
	campo de perspetivas espelhadas.

	O CFrame e reaplicado a cada frame porque o modulo de camara do Roblox pode
	voltar a mexer na camara quando o jogador nao tem personagem.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Maps = require(Shared.Config.Maps)

local State = require(script.Parent.Parent.State)

local CameraController = {}

local map = Maps.default
local appliedTeam: Types.Team? = nil
local target = Maps.cameraCFrame(map, "A")

local function apply(team: Types.Team?)
	appliedTeam = team
	-- Sem equipa (ainda no lobby) mostra-se o campo do lado da equipa A.
	target = Maps.cameraCFrame(map, team or "A")

	local camera = workspace.CurrentCamera
	if camera then
		camera.FieldOfView = map.cameraFov
	end
end

local function enforce()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if camera.CFrame ~= target then
		camera.CFrame = target
	end
end

function CameraController.init()
	apply(nil)
	enforce()
end

function CameraController.start()
	State.onMatchState(function(payload: Types.MatchStatePayload)
		if payload.team ~= appliedTeam then
			apply(payload.team)
		end
	end)

	RunService.RenderStepped:Connect(enforce)
end

return CameraController
