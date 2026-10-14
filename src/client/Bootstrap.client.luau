--!strict
--[[
	Bootstrap do cliente — o unico LocalScript.
	init() em todos os controladores (criar UI, camara, pastas), depois start()
	(ligar aos remotes e ao input). O State e o primeiro: e ele que recebe o
	estado do servidor e avisa os outros.
]]

local State = require(script.Parent.State)
local CameraController = require(script.Parent.Controllers.CameraController)
local UIController = require(script.Parent.Controllers.UIController)
local LobbyController = require(script.Parent.Controllers.LobbyController)
local AdminController = require(script.Parent.Controllers.AdminController)
local ShopController = require(script.Parent.Controllers.ShopController)
local PlacementController = require(script.Parent.Controllers.PlacementController)
local SpellController = require(script.Parent.Controllers.SpellController)
local UnitsController = require(script.Parent.Controllers.UnitsController)

State.init()
CameraController.init()
UIController.init()
LobbyController.init()
AdminController.init()
ShopController.init()
PlacementController.init()
SpellController.init()
UnitsController.init()

State.start()
CameraController.start()
UIController.start()
LobbyController.start()
AdminController.start()
ShopController.start()
PlacementController.start()
SpellController.start()
UnitsController.start()

print("[CoinKings] cliente pronto")
