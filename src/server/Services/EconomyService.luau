--!strict
--[[
	EconomyService — o ouro de cada jogador na ronda atual.
	É a única parte do código que soma ou subtrai ouro; quem quer gastar
	chama `trySpend`, que devolve false se não houver saldo.
]]

local Players = game:GetService("Players")

local EconomyService = {}

local gold: { [Player]: number } = {}

function EconomyService.init()
	Players.PlayerRemoving:Connect(function(player: Player)
		gold[player] = nil
	end)
end

function EconomyService.start() end

function EconomyService.setGold(player: Player, amount: number)
	gold[player] = math.max(0, math.floor(amount))
end

function EconomyService.getGold(player: Player): number
	return gold[player] or 0
end

function EconomyService.trySpend(player: Player, amount: number): boolean
	local current = gold[player] or 0
	if amount < 0 or current < amount then
		return false
	end
	gold[player] = current - amount
	return true
end

function EconomyService.refund(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	gold[player] = (gold[player] or 0) + math.floor(amount)
end

function EconomyService.clear(player: Player)
	gold[player] = nil
end

return EconomyService
