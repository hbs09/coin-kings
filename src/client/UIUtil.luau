--!strict
--[[
	UIUtil — atalhos para construir a interface por codigo.
	A UI toda e criada em runtime: nao ha ficheiros .rbxm para manter.
]]

local UIUtil = {}

-- Cria uma Instance e aplica as propriedades. O Parent e sempre aplicado no
-- fim, para o motor nao refazer o layout a cada propriedade.
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

function UIUtil.padding(parent: Instance, pixels: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pixels)
	padding.PaddingBottom = UDim.new(0, pixels)
	padding.PaddingLeft = UDim.new(0, pixels)
	padding.PaddingRight = UDim.new(0, pixels)
	padding.Parent = parent
	return padding
end

function UIUtil.formatTime(seconds: number): string
	local whole = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", whole // 60, whole % 60)
end

-- Paleta (so apresentacao; nada de balanceamento).
UIUtil.colors = {
	panel = Color3.fromRGB(24, 26, 34),
	panelLight = Color3.fromRGB(38, 42, 54),
	text = Color3.fromRGB(240, 242, 248),
	textDim = Color3.fromRGB(168, 174, 190),
	accent = Color3.fromRGB(246, 198, 86),
	good = Color3.fromRGB(104, 200, 132),
	bad = Color3.fromRGB(226, 94, 86),
}

UIUtil.font = Enum.Font.GothamBold
UIUtil.fontRegular = Enum.Font.Gotham

return UIUtil
