-- Run from the repository root: luajit tests/secret_spec.lua
-- Values the client hands over as secret: a player's "attempt to perform arithmetic on a secret number value"
-- on an item hover lasted until /reload. A secret count, sell price or item id is never tested, compared or
-- summed, and never kept where a later read would find it.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local BANDAGE, SILK, BANDAGE_ITEM = 1, 3, 50

-- A secret stands in as a value Lua refuses to compute with, and issecretvalue knows it.
local Secret = setmetatable({}, {
	__tostring = function()
		return "secret"
	end,
})

local c = Client.load({
	boot = false,
	saved = { routeTargets = { [129] = 50 }, trackedProfessions = { [129] = true } },
	data = {
		Thresholds = { [BANDAGE] = { 1, 30, 45, 60 } },
		RecipeData = {
			[BANDAGE] = {
				skillLine = 129,
				reagents = { { itemID = SILK, quantity = 1 } },
				output = { itemID = BANDAGE_ITEM, quantity = 1 },
			},
		},
		TrainerFees = {},
		TrainerRanks = { [129] = {} },
		ItemSellPrices = { [BANDAGE_ITEM] = 2 },
		GatheredBy = {},
		VendorPrices = { [SILK] = 10 },
		ProfessionTrainers = {},
	},
})
local G, ns = c.G, c.ns

-- The item tooltip's post call and what it drew.
local post
G.TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn)
		if kind == G.Enum.TooltipDataType.Item then
			post = fn
		end
	end,
}
local lines, refreshed = {}, 0
local tooltipItem
G.GameTooltip = {
	IsShown = function()
		return true
	end,
	IsForbidden = function()
		return false
	end,
	GetItem = function()
		return "Linen Cloth", "link", tooltipItem
	end,
	RefreshData = function()
		refreshed = refreshed + 1
	end,
}
local function Line(_, text)
	lines[#lines + 1] = text
end
G.GameTooltip_AddColoredLine, G.GameTooltip_AddNormalLine, G.GameTooltip_AddDisabledLine = Line, Line, Line
G.GameTooltip_AddBlankLineToTooltip = function() end
G.IsShiftKeyDown = function()
	return false
end
G.NORMAL_FONT_COLOR = {}
local secret = false
G.issecretvalue = function(value)
	return value == Secret
end
local GetItemCount, GetItemInfo = G.C_Item.GetItemCount, G.C_Item.GetItemInfo
G.C_Item.GetItemCount = function(id)
	return secret and Secret or GetItemCount(id)
end
G.C_Item.GetItemInfo = function(id)
	if secret then
		return "Bandage", nil, nil, nil, nil, nil, nil, nil, nil, nil, Secret
	end
	return GetItemInfo(id)
end
c.level = 20
c.items[SILK] = { name = "Linen Cloth" }
c.items[BANDAGE_ITEM] = { name = "Linen Bandage", sell = 3 }
c.known[BANDAGE] = true
c.professions = { { name = "First Aid", rank = 10, max = 75, id = 129 } }
c.auction[SILK] = 10
c.bags[SILK] = 4
c.Boot()
c.EnterWorld()
c.Advance(0)

equal(ns.Have(SILK), 4, "a readable count")
secret = true
equal(ns.Have(SILK), 4, "a secret count reads as the last one seen")
equal(ns.Have(999), 0, "and as none for an item never seen")

-- The hover that failed: the route's need for the item, with the count secret.
post(G.GameTooltip, { id = SILK })
local route
for _, text in ipairs(lines) do
	route = route or text:match("^Route: 4/%d+")
end
equal(route ~= nil, true, "the hover draws the route line from the last count")
lines = {}
post(G.GameTooltip, { id = Secret })
equal(#lines, 0, "a secret item id draws nothing")

-- A forbidden tooltip is never read or drawn on.
local forbidden = setmetatable({
	IsForbidden = function()
		return true
	end,
}, { __index = G.GameTooltip })
post(forbidden, { id = SILK })
equal(#lines, 0, "a forbidden tooltip draws nothing")

-- A vendor whose GUID or name is secret is not recorded, and nothing raises.
c.npc = { id = 1234, name = "Vendor" }
local UnitGUID, UnitName = G.UnitGUID, G.UnitName
G.UnitGUID = function()
	return Secret
end
equal(ns.SeeVendor({ SILK }), false, "a secret vendor GUID records nothing")
G.UnitGUID = UnitGUID
G.UnitName = function()
	return Secret
end
equal(ns.SeeVendor({ SILK }), false, "a secret vendor name records nothing")
G.UnitName = UnitName
c.npc = nil

-- A secret sell price is no live price: the bundled one stands in, as while item data loads.
local cost, value = ns.CraftCost(BANDAGE)
equal(cost, 10, "the reagents still cost what the vendor asks")
equal(value and value.copper, 2, "and a secret sell price gives way to the bundled one")

-- Shift redraws the tooltip only for an item id it can read.
tooltipItem = Secret
c.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
equal(refreshed, 0, "a secret tooltip item is left alone")
tooltipItem = SILK
c.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
equal(refreshed, 1, "a readable one is redrawn")

-- Once the client lets the count be read again, it is the one used.
secret = false
c.bags[SILK] = 9
equal(ns.Have(SILK), 9, "a readable count wins again")

Client.report("secret_spec")
