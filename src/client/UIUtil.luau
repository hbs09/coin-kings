--!strict
--[[
	UIUtil — o sistema de desenho da interface.

	Toda a UI é criada em runtime, por isso é aqui que vive a aparência: cores,
	tipos de letra, cantos, contornos, gradientes e sombras. Mudar o aspeto do
	jogo inteiro é mexer neste ficheiro, não em sete controladores.

	Regra: os controladores dizem **o que** mostram; isto decide **como** é que
	se parece.
]]

local UIUtil = {}

-- Paleta ------------------------------------------------------------------------

UIUtil.colors = {
	-- Fundos, do mais escuro ao mais claro.
	shadow = Color3.fromRGB(8, 9, 14),
	panel = Color3.fromRGB(26, 29, 40),
	panelTop = Color3.fromRGB(40, 45, 62),
	panelLight = Color3.fromRGB(52, 58, 78),
	outline = Color3.fromRGB(16, 18, 26),

	text = Color3.fromRGB(244, 246, 252),
	textDim = Color3.fromRGB(158, 166, 188),
	textOnLight = Color3.fromRGB(26, 22, 12),

	-- Destaques.
	accent = Color3.fromRGB(255, 203, 71),
	accentDeep = Color3.fromRGB(226, 155, 32),
	good = Color3.fromRGB(96, 214, 136),
	goodDeep = Color3.fromRGB(52, 168, 96),
	bad = Color3.fromRGB(240, 95, 92),
	badDeep = Color3.fromRGB(196, 56, 56),
	info = Color3.fromRGB(104, 178, 240),
}

UIUtil.font = Enum.Font.GothamBold
UIUtil.fontDisplay = Enum.Font.GothamBlack
UIUtil.fontRegular = Enum.Font.Gotham

-- Construção ---------------------------------------------------------------------

-- Cria uma Instance e aplica as propriedades. O Parent é sempre aplicado no
-- fim, para o motor não refazer o layout a cada propriedade.
function UIUtil.make(className: string, props: { [string]: any }): Instance
	local instance = Instance.new(className)
	local target = instance :: any
	local parent = props.Parent
	for key, value in props do
		if key ~= "Parent" then
			target[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIUtil.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function UIUtil.stroke(parent: Instance, thickness: number, color: Color3, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness
	stroke.Color = color
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UIUtil.padding(parent: Instance, pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

-- Gradiente vertical: o truque mais barato para um painel deixar de parecer um
-- retângulo chapado.
function UIUtil.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = parent
	return gradient
end

-- Sombra sem imagens: um painel escuro ligeiramente maior, por trás. Não é um
-- blur a sério, mas separa o painel do fundo, que é o que interessa.
function UIUtil.shadow(target: GuiObject, spread: number): Frame
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = target.AnchorPoint
	shadow.Position = target.Position + UDim2.fromOffset(0, math.max(2, spread // 2))
	shadow.Size = target.Size + UDim2.fromOffset(spread * 2, spread * 2)
	shadow.BackgroundColor3 = UIUtil.colors.shadow
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = math.max(1, target.ZIndex - 1)
	shadow.Parent = target.Parent
	UIUtil.corner(shadow, 16)
	return shadow
end

-- Painel: fundo com gradiente, canto redondo, contorno e sombra. É o bloco de
-- construção de tudo o que é caixa na interface.
function UIUtil.panel(props: { [string]: any }, radius: number?): Frame
	local frame = UIUtil.make("Frame", props) :: Frame
	local corner = radius or 14
	UIUtil.corner(frame, corner)
	UIUtil.gradient(frame, UIUtil.colors.panelTop, UIUtil.colors.panel)
	UIUtil.stroke(frame, 1.5, UIUtil.colors.outline, 0.3)
	return frame
end

-- Botão com cor sólida e contorno mais escuro por baixo, o aspeto de botão
-- carnudo que se espera num jogo do Roblox.
function UIUtil.button(props: { [string]: any }, tone: Color3, toneDeep: Color3): TextButton
	props.BackgroundColor3 = tone
	props.BorderSizePixel = 0
	props.AutoButtonColor = true
	local button = UIUtil.make("TextButton", props) :: TextButton
	UIUtil.corner(button, 10)
	UIUtil.gradient(button, tone, toneDeep)
	UIUtil.stroke(button, 2, toneDeep, 0.2)
	return button
end

function UIUtil.formatTime(seconds: number): string
	local whole = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

return UIUtil
