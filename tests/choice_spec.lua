-- Run from the repository root: luajit tests/choice_spec.lua
-- The player's say over the route, with the whole addon loaded: gathered materials valued at what they would
-- sell for (the Prices setting), and "Not this recipe", which leaves a recipe out of every route on this
-- character until Show again. Two Blacksmithing recipes reach the same skill: one from ore this character
-- mines, one from flux a vendor sells.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local FROM_ORE, FROM_FLUX = 101, 102
local ORE, FLUX = 2770, 2880

local c = Client.load({
	boot = false,
	saved = { routeTargets = { [164] = 20 } },
	data = {
		Thresholds = {
			[FROM_ORE] = { 1, 30, 45, 60 },
			[FROM_FLUX] = { 1, 30, 45, 60 },
		},
		RecipeData = {
			[FROM_ORE] = { skillLine = 164, reagents = { { itemID = ORE, quantity = 2 } } },
			[FROM_FLUX] = { skillLine = 164, reagents = { { itemID = FLUX, quantity = 2 } } },
		},
		TrainerFees = {},
		TrainerRanks = {},
		ItemSellPrices = {},
		GatheredBy = { [ORE] = 186 },
		VendorPrices = { [FLUX] = 50 },
		ProfessionTrainers = {},
		ScrollDrops = {},
		WorldDrops = {},
	},
})
local ns = c.ns
c.spells = { [FROM_ORE] = "Copper Chain Belt", [FROM_FLUX] = "Rough Grinding Stone" }
c.known = { [FROM_ORE] = true, [FROM_FLUX] = true }
c.items = { [ORE] = { name = "Copper Ore", sell = 5 }, [FLUX] = { name = "Weak Flux" } }
c.auction = { [ORE] = 100 }
c.professions = {
	{ name = "Blacksmithing", icon = 136241, rank = 1, max = 75, id = 8164 },
	{ name = "Mining", icon = 136248, rank = 50, max = 75, id = 8186 },
}
c.Boot()

---@return SkillUpPlan
local function Plan()
	return ns.PlanRoute(ns.RouteProfessions()[164])
end

--[[ Gathered materials ]]

equal(ns.db.valueGathered, false, "gathered materials are free by default")
equal(ns.Price(ORE).copper, 0, "so ore this character mines costs nothing")
equal(Plan().crafts[1].recipeID, FROM_ORE, "and the route crafts from it")

-- On, ore is worth its auction price after the cut, which beats its vendor sell price.
c.SetSetting("valueGathered", true)
equal(ns.Price(ORE).copper, 95, "a gathered material costs its auction price after the 5% cut")
equal(ns.Price(ORE).source, "gather", "it is still gathered, not bought")
equal(ns.Price(ORE).worth, "auction", "valued at the auction")
equal(ns.PriceSourceText(ns.Price(ORE)), "you gather it (Mining), valued at its AH price", "and says so")
equal(ns.NetCost(FROM_ORE), 190, "a craft from it costs what the ore would sell for")
equal(Plan().crafts[1].recipeID, FROM_FLUX, "so the route picks the cheaper flux recipe instead")

-- A cheap auction never values ore below what a vendor pays for it.
c.auction[ORE] = 4
c.AuctionatorScan()
equal(ns.Price(ORE).copper, 5, "the vendor sell price is the floor")
equal(ns.Price(ORE).worth, "vendor", "and is where the value came from")
equal(ns.PriceSourceText(ns.Price(ORE)), "you gather it (Mining), valued at its vendor sell price", "said so")
equal(Plan().crafts[1].recipeID, FROM_ORE, "worth little, the ore recipe is back")

-- With no auction price at all, the vendor sell price alone; a secret sell price is never computed with.
c.auction[ORE] = nil
c.AuctionatorScan()
equal(ns.Price(ORE).copper, 5, "without an auction price, the vendor sell price")
c.G.issecretvalue = function(value)
	return value == 5
end
c.AuctionatorScan()
equal(ns.Price(ORE).copper, 0, "an unreadable sell price and no auction price leave it free, not guessed")
equal(ns.Price(ORE).worth, nil, "with no value claimed")
c.G.issecretvalue = nil
c.AuctionatorScan()

-- Buying instead of gathering ignores the setting: the ore is then bought like any other reagent.
c.auction[ORE] = 100
ns.SetCollectMode("auction")
equal(ns.Price(ORE).source, "auctionator", "Buy reagents buys gathered materials at the auction house")
equal(ns.Price(ORE).copper, 100, "at the full auction price")
ns.SetCollectMode("gather")
c.SetSetting("valueGathered", false)
equal(ns.Price(ORE).copper, 0, "off again, gathering is free")

--[[ Not this recipe ]]

ns.SetSkipped(FROM_ORE, true)
equal(ns.db.skippedRecipes["Tester-Realm"][FROM_ORE], true, "a skip is saved for this character")
equal(ns.IsSkipped(FROM_ORE), true, "and read back")
local plan = Plan()
equal(#plan.crafts, 1, "the route still reaches the target")
equal(plan.crafts[1].recipeID, FROM_FLUX, "without the skipped recipe, though it was the cheapest")
equal(#ns.SkippedRecipes(164), 1, "the profession lists one skipped recipe")
equal(ns.SkippedRecipes(164)[1].name, "Copper Chain Belt", "by name")
equal(#ns.SkippedRecipes(171), 0, "and another profession none")

-- The tracker's header menu shows each skipped recipe of its profession again.
---@return table
local function MenuDescription()
	local description = { buttons = {} }
	function description.CreateTitle() end
	function description.CreateButton(_, text, action)
		local button = MenuDescription()
		button.text, button.action = text, action
		description.buttons[#description.buttons + 1] = button
		return button
	end
	return description
end
local root = MenuDescription()
c.G.MenuUtil = {
	CreateContextMenu = function(owner, generator)
		generator(owner, root)
	end,
}
ns.SetTracked(164, true)
local block = c.Tracker()[1]
local module = c.G.SkillUpForeverObjectiveTracker
-- The stock tracker module's own method, which the stub client leaves out.
function module.GetContextMenuParent()
	return module
end
module:OnBlockHeaderClick(block)
local skippedMenu
for _, button in ipairs(root.buttons) do
	if button.text == "Skipped (1)" then
		skippedMenu = button
	end
end
equal(skippedMenu ~= nil, true, "the tracker's header menu counts the skipped recipes")
equal(skippedMenu.buttons[1].text, "Show again: Copper Chain Belt", "and shows each one again")
skippedMenu.buttons[1].action()
equal(ns.IsSkipped(FROM_ORE), false, "from there")
ns.SetSkipped(FROM_ORE, true)

-- Skipping every recipe leaves the normal no-route state, not an error.
ns.SetSkipped(FROM_FLUX, true)
plan = Plan()
equal(#plan.crafts, 0, "nothing left to craft")
equal(ns.RouteBlocked(plan), "Nothing you know skills up past 1.", "says so the usual way")

-- /su skipped lists them with their IDs, and /su unskip shows one, or all, again.
local SlashCommand = c.G.SlashCmdList.SKILLUPFOREVER
c.chat = {}
SlashCommand("skipped")
equal(c.chat[1]:find("Skipped (2):", 1, true) ~= nil, true, "/su skipped counts them")
equal(c.chat[2]:find("Copper Chain Belt (101)", 1, true) ~= nil, true, "and names each with its ID")
SlashCommand("unskip 101")
equal(ns.IsSkipped(FROM_ORE), false, "/su unskip shows one again")
equal(Plan().crafts[1].recipeID, FROM_ORE, "and the route uses it again")
c.chat = {}
SlashCommand("unskip 999")
equal(c.chat[1]:find("/su skipped lists", 1, true) ~= nil, true, "an ID that isn't skipped says how to find one")
SlashCommand("unskip all")
equal(ns.IsSkipped(FROM_FLUX), false, "/su unskip all shows every one again")
equal(ns.db.skippedRecipes["Tester-Realm"], nil, "leaving nothing saved")
c.chat = {}
SlashCommand("skipped")
equal(c.chat[1]:find("no skipped recipes", 1, true) ~= nil, true, "with none skipped, it says how to skip one")

-- A save that isn't a recipe ID set is dropped on load.
local reloaded = Client.load({
	saved = { skippedRecipes = { ["Tester-Realm"] = { [FROM_ORE] = true, bad = true, [7] = "yes" }, Other = 3 } },
})
equal(reloaded.ns.db.skippedRecipes["Tester-Realm"][FROM_ORE], true, "a saved skip survives a reload")
equal(reloaded.ns.db.skippedRecipes["Tester-Realm"].bad, nil, "a key that isn't a recipe ID is dropped")
equal(reloaded.ns.db.skippedRecipes["Tester-Realm"][7], nil, "and a value that isn't true")
equal(reloaded.ns.db.skippedRecipes.Other, nil, "and a character entry that isn't a table")

Client.report("choice_spec")
