--!strict
--[[
	PlacementController — comprar e posicionar, com rato ou com o dedo.

	Como funciona:
	- Arrastar um cartao da loja direto para a propria metade coloca a tropa,
	  num gesto so. Um toque no cartao escolhe-a, e depois toca-se no campo.
	- Arrastar uma unidade ja colocada move-a, de graca, durante a preparacao.
	- No modo "Vender" (ou com o botao direito), tocar numa unidade devolve o ouro.

	O cliente nunca muda o exercito por si: desenha o que o servidor confirmou
	em ArmyUpdate e pinta a pre-visualizacao com a regra de Util/Placement.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local Net = require(Shared.Net)
local Maps = require(Shared.Config.Maps)
local Troops = require(Shared.Config.Troops)
local Placement = require(Shared.Util.Placement)

local State = require(script.Parent.Parent.State)
local UnitVisual = require(script.Parent.Parent.UnitVisual)
local ShopController = require(script.Parent.ShopController)
local UIController = require(script.Parent.UIController)

local PlacementController = {}

local map = Maps.default

local folder: Folder
local visuals: { [number]: UnitVisual.Visual } = {}

local ghost: UnitVisual.Visual? = nil
local ghostTroopId: Types.TroopId? = nil

-- Arrasto em curso
local activeInput: InputObject? = nil
local movingUnitId: number? = nil
local dragStart: Vector2? = nil
-- Um arrasto que comecou num cartao so coloca se o dedo andou: senao, um
-- simples toque no cartao largava uma unidade atras do painel da loja.
local dragFromCard = false
local DRAG_THRESHOLD = 14

-- Ecra -> arena ---------------------------------------------------------------

-- Devolve o ponto em coordenadas LOCAIS a arena (ja sem o offset do slot), que
-- sao as mesmas que o servidor valida.
local function screenToArena(screenPosition: Vector3): Vector2?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	-- ScreenPointToRay (e nao ViewportPointToRay) porque as posicoes do
	-- UserInputService ja vem sem o GUI inset da barra de topo.
	local ray = camera:ScreenPointToRay(screenPosition.X, screenPosition.Y)
	local directionY = ray.Direction.Y
	if math.abs(directionY) < 1e-5 then
		return nil
	end

	local distance = (map.floorY - ray.Origin.Y) / directionY
	if distance <= 0 then
		return nil
	end

	local point = ray.Origin + ray.Direction * distance
	return Vector2.new(point.X - State.arenaOffsetX, point.Z)
end

local function unitAt(position: Vector2): Types.ArmyEntry?
	local best: Types.ArmyEntry? = nil
	local bestDistance = math.huge
	for _, entry in State.army do
		local def = Troops.get(entry.troopId)
		if def then
			local dx = entry.x - position.X
			local dz = entry.z - position.Y
			local squared = dx * dx + dz * dz
			local reach = def.radius + 1.5
			if squared <= reach * reach and squared < bestDistance then
				bestDistance = squared
				best = entry
			end
		end
	end
	return best
end

-- Desenho do exercito ---------------------------------------------------------

local function teamColor(): Color3
	local team = State.team
	return if team then Maps.teamColor(map, team) else Color3.fromRGB(150, 150, 150)
end

local function clearVisuals()
	for id, visual in visuals do
		UnitVisual.destroy(visual)
		visuals[id] = nil
	end
end

local function redrawArmy()
	local seen: { [number]: boolean } = {}

	for _, entry in State.army do
		seen[entry.id] = true
		local def = Troops.get(entry.troopId)
		if def then
			local visual = visuals[entry.id]
			if not visual then
				visual = UnitVisual.create(def, teamColor(), folder, { label = true })
				visuals[entry.id] = visual
			end
			UnitVisual.setPosition(visual, entry.x + State.arenaOffsetX, entry.z)
			visual.part.Transparency = if movingUnitId == entry.id then 0.6 else 0
		end
	end

	for id, visual in visuals do
		if not seen[id] then
			UnitVisual.destroy(visual)
			visuals[id] = nil
		end
	end
end

-- Pre-visualizacao ------------------------------------------------------------

local function destroyGhost()
	local current = ghost
	if current then
		UnitVisual.destroy(current)
	end
	ghost = nil
	ghostTroopId = nil
end

local function ensureGhost(troopId: Types.TroopId): UnitVisual.Visual?
	if ghost and ghostTroopId == troopId then
		return ghost
	end
	destroyGhost()

	local def = Troops.get(troopId)
	if not def then
		return nil
	end

	local visual = UnitVisual.create(def, teamColor(), folder, { ghost = true, label = false })
	ghost = visual
	ghostTroopId = troopId
	return visual
end

-- Qual a tropa que o arrasto atual esta a posicionar?
local function draggedTroopId(): Types.TroopId?
	local unitId = movingUnitId
	if unitId then
		local entry = State.findUnit(unitId)
		return if entry then entry.troopId else nil
	end
	return ShopController.getSelected()
end

local function updateGhost(screenPosition: Vector3)
	if not State.canEditArmy() then
		destroyGhost()
		return
	end

	local troopId = draggedTroopId()
	if not troopId then
		destroyGhost()
		return
	end

	local point = screenToArena(screenPosition)
	if not point then
		destroyGhost()
		return
	end

	local visual = ensureGhost(troopId)
	local def = Troops.get(troopId)
	local team = State.team
	if not visual or not def or not team then
		return
	end

	UnitVisual.setPosition(visual, point.X + State.arenaOffsetX, point.Y)
	UnitVisual.setGhostValid(visual, Placement.isValid(team, State.army, point.X, point.Y, def, movingUnitId))
end

-- Entrada ---------------------------------------------------------------------

local function commit(screenPosition: Vector3)
	local point = screenToArena(screenPosition)
	if not point then
		return
	end

	local unitId = movingUnitId
	if unitId then
		Net.fireServer("MoveUnit", unitId, point.X, point.Y)
		return
	end

	local troopId = ShopController.getSelected()
	if troopId then
		Net.fireServer("PlaceUnit", troopId, point.X, point.Y)
	end
end

local function endDrag()
	activeInput = nil
	movingUnitId = nil
	dragStart = nil
	dragFromCard = false
	destroyGhost()
	redrawArmy()
end

-- Arrasto comecado num cartao da loja (ShopController avisa).
local function beginCardDrag(_troopId: Types.TroopId, input: InputObject)
	if not State.canEditArmy() then
		return
	end
	activeInput = input
	dragStart = Vector2.new(input.Position.X, input.Position.Y)
	dragFromCard = true
	movingUnitId = nil
	updateGhost(input.Position)
end

local function onInputBegan(input: InputObject, processed: boolean)
	if processed or not State.canEditArmy() then
		return
	end

	local inputType = input.UserInputType
	local isPrimary = inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
	local isSecondary = inputType == Enum.UserInputType.MouseButton2
	if not isPrimary and not isSecondary then
		return
	end

	local point = screenToArena(input.Position)
	if not point then
		return
	end

	-- Vender: botao direito, ou modo de venda no telemovel.
	if isSecondary or UIController.isSellMode() then
		local entry = unitAt(point)
		if entry then
			Net.fireServer("SellUnit", entry.id)
		end
		return
	end

	activeInput = input
	dragStart = Vector2.new(input.Position.X, input.Position.Y)
	dragFromCard = false

	-- Pegar numa unidade ja colocada tem prioridade: e o gesto obvio quando se
	-- carrega mesmo em cima dela, mesmo com uma tropa escolhida na loja.
	local entry = unitAt(point)
	if entry then
		movingUnitId = entry.id
		redrawArmy()
	end

	updateGhost(input.Position)
end

local function onInputChanged(input: InputObject, _processed: boolean)
	-- Se o gesto e o nosso, seguimo-lo ate ao fim: um arrasto que comeca num
	-- cartao vem marcado como "processado" pela interface, e e suposto.
	if input == activeInput then
		updateGhost(input.Position)
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		-- O rato mostra sempre onde vai cair.
		updateGhost(input.Position)
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if input ~= activeInput then
		return
	end

	if State.canEditArmy() then
		local start = dragStart
		local travelled = if start
			then (Vector2.new(input.Position.X, input.Position.Y) - start).Magnitude
			else 0
		-- Do cartao, so coloca quem arrastou. Do campo, um toque chega.
		if not dragFromCard or travelled >= DRAG_THRESHOLD then
			commit(input.Position)
		end
	end

	endDrag()
end

function PlacementController.init()
	folder = Instance.new("Folder")
	folder.Name = "PrepUnits"
	folder.Parent = workspace
end

function PlacementController.start()
	State.onArmy(function()
		if State.canEditArmy() then
			redrawArmy()
		end
	end)

	State.onMatchState(function(payload: Types.MatchStatePayload)
		if payload.phase == "Prep" then
			redrawArmy()
		else
			-- Fora da preparacao o campo passa a ser desenhado pelo UnitsController.
			endDrag()
			clearVisuals()
		end
	end)

	-- No Reveal os modelos da batalha substituem os da preparacao.
	State.onRoster(function()
		endDrag()
		clearVisuals()
	end)

	ShopController.onCardDragStart(beginCardDrag)

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
end

return PlacementController
