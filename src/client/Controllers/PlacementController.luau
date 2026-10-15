--!strict
--[[
	PlacementController — comprar e posicionar, com rato ou com o dedo.

	Como funciona:
	- Arrastar um cartao da loja direto para a propria metade coloca **uma**
	  tropa, onde se largar. Atravessar o campo com o dedo nao compra nada pelo
	  caminho: quem arrasta do cartao ainda esta a escolher onde por a primeira.
	- **Comprada a primeira, o arrasto no campo enche**: com a tropa ja
	  escolhida, passar o dedo pela propria metade vai colocando enquanto
	  houver ouro e espaco. Montar 30 soldados a um toque de cada vez era
	  trabalho a mais, mas comprar sem querer e pior.
	- Arrastar uma unidade ja colocada move-a, de graca, durante a preparacao.
	- No modo "Vender" (ou com o botao direito), carregar numa unidade marca-a
	  e e ao largar que ela e vendida: da tempo de ver o que vai embora.
	- Um circulo no chao segue o dedo durante qualquer arrasto: verde onde se
	  pode colocar, vermelho onde nao, e a volta da unidade que vai ser vendida.

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

-- Circulo que segue o dedo, para o jogador ver sempre onde vai cair.
local cursorPart: BasePart? = nil

-- Arrasto em curso
local activeInput: InputObject? = nil
-- Unidade marcada para venda enquanto o dedo esta em baixo.
local sellTargetId: number? = nil
local movingUnitId: number? = nil
local dragStart: Vector2? = nil
-- Um arrasto que comecou num cartao so coloca se o dedo andou: senao, um
-- simples toque no cartao largava uma unidade atras do painel da loja.
local dragFromCard = false
local DRAG_THRESHOLD = 14

-- Pintura: enquanto se arrasta, vai-se colocando pelo caminho.
local paintedAny = false
local lastPaint: Vector2? = nil
local lastPaintClock = 0
-- O servidor limita os pedidos de colocacao, por isso ha um intervalo minimo
-- entre duas unidades pintadas.
local PAINT_INTERVAL = 0.09
-- Quanto ouro ja foi pedido e ainda nao veio confirmado no ArmyUpdate: sem
-- isto, um arrasto rapido pedia mais do que da e enchia o ecra de avisos.
local pendingSpend = 0

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
			UnitVisual.setTransparency(visual, if movingUnitId == entry.id then 0.6 else 0)
		end
	end

	for id, visual in visuals do
		if not seen[id] then
			UnitVisual.destroy(visual)
			visuals[id] = nil
		end
	end
end

-- Cursor ----------------------------------------------------------------------

local function ensureCursor(): BasePart
	local existing = cursorPart
	if existing then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "Cursor"
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 6, 6)
	part.Parent = folder

	cursorPart = part
	return part
end

local function showCursor(x: number, z: number, diameter: number, color: Color3)
	local part = ensureCursor()
	part.Size = Vector3.new(0.2, diameter, diameter)
	part.Color = color
	-- O cilindro tem as faces redondas no eixo X; rodado assim fica deitado.
	part.CFrame = CFrame.new(x + State.arenaOffsetX, map.floorY + 0.12, z) * CFrame.Angles(0, 0, math.pi / 2)
	part.Transparency = 0.5
end

local function hideCursor()
	local part = cursorPart
	if part then
		part.Transparency = 1
	end
end

-- Marca para venda a unidade que esta debaixo do dedo e desenha o circulo a
-- volta dela. Sem unidade por baixo, nao ha nada marcado nem nada a mostrar.
local function updateSellCursor(point: Vector2)
	local entry = unitAt(point)
	sellTargetId = if entry then entry.id else nil

	if not entry then
		hideCursor()
		return
	end

	local def = Troops.get(entry.troopId)
	local diameter = if def then def.radius * 3 else 4
	showCursor(entry.x, entry.z, diameter, Color3.fromRGB(226, 94, 86))
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
		hideCursor()
		return
	end

	local troopId = draggedTroopId()
	if not troopId then
		destroyGhost()
		hideCursor()
		return
	end

	local point = screenToArena(screenPosition)
	if not point then
		destroyGhost()
		hideCursor()
		return
	end

	local visual = ensureGhost(troopId)
	local def = Troops.get(troopId)
	local team = State.team
	if not visual or not def or not team then
		return
	end

	local valid = Placement.isValid(team, State.army, point.X, point.Y, def, movingUnitId)
	UnitVisual.setPosition(visual, point.X + State.arenaOffsetX, point.Y)
	UnitVisual.setGhostValid(visual, valid)
	showCursor(
		point.X,
		point.Y,
		def.radius * 2.6,
		if valid then Color3.fromRGB(120, 220, 140) else Color3.fromRGB(226, 94, 86)
	)

	-- Pintar: so nos arrastos feitos no campo, com a tropa ja escolhida. Do
	-- cartao nao se pinta, para atravessar o campo nao comprar sem querer.
	-- E nunca sem um gesto em curso: nada se compra sem o botao em baixo.
	if activeInput == nil or dragFromCard or movingUnitId or not valid then
		return
	end

	local now = os.clock()
	if now - lastPaintClock < PAINT_INTERVAL then
		return
	end

	-- So vale a pena pedir se ja houver espaco para outra: a regra e a mesma
	-- que o servidor aplica, por isso nao se pede o que ia ser recusado.
	local previous = lastPaint
	if previous then
		local minimum = def.radius * 2 + 1
		if (point - previous).Magnitude < minimum then
			return
		end
	end

	if State.gold - pendingSpend < def.cost then
		return
	end

	Net.fireServer("PlaceUnit", troopId, point.X, point.Y)
	pendingSpend += def.cost
	lastPaint = point
	lastPaintClock = now
	paintedAny = true
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
	paintedAny = false
	lastPaint = nil
	sellTargetId = nil
	destroyGhost()
	hideCursor()
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

	-- Vender: botao direito, ou modo de venda no telemovel. Marca-se agora e
	-- vende-se ao largar, para dar tempo de ver qual e que vai embora.
	if isSecondary or UIController.isSellMode() then
		activeInput = input
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		dragFromCard = false
		updateSellCursor(point)
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
	-- So se segue o gesto com o botao (ou o dedo) em baixo. Sem isto, passear
	-- o rato pelo campo com uma tropa escolhida parecia um arrasto — e chegava
	-- a comprar unidades sem um unico clique.
	if activeInput == nil then
		return
	end

	-- O gesto e o nosso. Com rato, o movimento chega num InputObject proprio,
	-- diferente do do botao; com dedo, e o mesmo do inicio ao fim.
	local isOurs = input == activeInput or input.UserInputType == Enum.UserInputType.MouseMovement
	if not isOurs then
		return
	end

	if sellTargetId ~= nil or UIController.isSellMode() then
		local point = screenToArena(input.Position)
		if point then
			updateSellCursor(point)
		end
	else
		updateGhost(input.Position)
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if input ~= activeInput then
		return
	end

	-- Venda: o que estiver marcado vai-se embora agora.
	local selling = sellTargetId
	if selling then
		Net.fireServer("SellUnit", selling)
		endDrag()
		return
	end

	-- Em modo de venda nao se coloca nada: largar no vazio nao compra.
	if UIController.isSellMode() then
		endDrag()
		return
	end

	if State.canEditArmy() and not paintedAny then
		local start = dragStart
		local travelled = if start
			then (Vector2.new(input.Position.X, input.Position.Y) - start).Magnitude
			else 0
		-- Do cartao, so coloca quem arrastou. Do campo, um toque chega.
		-- (Se ja se pintou pelo caminho, a ultima ja la ficou.)
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
		-- O servidor confirmou o exercito: o que estava pedido ja la esta.
		pendingSpend = 0
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
