-- Run from the repository root: luajit tests/changes_spec.lua
-- What each change makes stale, with the whole addon loaded: the real caches of Prices, Plan and the public
-- API, driven by the client's events and by the writers, with a recorder standing in for each view.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local SHIRT, CLOTH, SHIRT_ITEM, BOLT, CLOAK = 1, 10, 11, 12, 13
local c = Client.load({
	data = {
		Thresholds = { [SHIRT] = { 1, 60, 70, 80 }, [BOLT] = { 1, 90, 100, 110 } },
		RecipeData = { [SHIRT] = { skillLine = 197, reagents = {} }, [BOLT] = { skillLine = 197, reagents = {} } },
		VendorPrices = { [CLOTH] = 10 },
		-- Skinning, which this character lacks: asking is what makes Prices remember its professions.
		GatheredBy = { [CLOTH] = 393 },
		TrainerFees = {},
		TrainerRanks = {},
		ItemSellPrices = {},
	},
})
local ns = c.ns
-- The open window's schematics, which are what the schematic cache keeps.
local schematic = { reagents = { { CLOTH, 1 } }, output = SHIRT_ITEM }
c.schematics = { [SHIRT] = schematic, [BOLT] = schematic }
c.items[SHIRT_ITEM] = { sell = 5 }
c.known[SHIRT] = true
c.professions = { { name = "Tailoring", rank = 50, max = 75, id = 197 } }
local function Tailoring()
	return ns.PlayerProfessions()[197]
end

local redrawn = {}
for _, view in ipairs({ "tracker", "routeTab", "recipeList", "trainer", "route" }) do
	ns.WhenStale(view, function()
		redrawn[#redrawn + 1] = view
	end)
end

-- The schematic cache keeps what the window gave for good; what it took for a recipe the window has no
-- schematic for (CLOAK) is what it drops, to ask the client again.
local cloakReads = 0
local realSchematic = c.G.C_TradeSkillUI.GetRecipeSchematic
c.G.C_TradeSkillUI.GetRecipeSchematic = function(recipeID, ...)
	if recipeID == CLOAK then
		cloakReads = cloakReads + 1
	end
	return realSchematic(recipeID, ...)
end
local function CloakReads()
	ns.Reagents(CLOAK)
	return cloakReads
end

-- Each cache hands back the table it kept until it is dropped; the schematic cache, how often it asked.
local CACHES = { "schematics", "prices", "plans", "api" }
local function Kept()
	return {
		schematics = CloakReads(),
		prices = ns.Price(CLOTH),
		plans = ns.PlanRoute(Tailoring()),
		api = c.G.SkillUpForever.API.Professions(),
	}
end

-- What `change` dropped and redrew, as "caches | views" in the order they went.
local function Stale(change)
	local before = Kept()
	redrawn = {}
	change()
	local views = table.concat(redrawn, " ")
	local after, dropped = Kept(), {}
	for _, cache in ipairs(CACHES) do
		if after[cache] ~= before[cache] then
			dropped[#dropped + 1] = cache
		end
	end
	return table.concat(dropped, " ") .. " | " .. views
end

local function Event(event)
	return function()
		c.Fire(event)
	end
end
local function Changed(kind)
	return function()
		ns.Changed(kind)
	end
end

equal(#ns.PlanRoute(Tailoring()).crafts > 0, true, "the plan under test has crafts")
equal(Stale(function() end), " | ", "nothing changes on its own")

-- The public list was built without the reagent's name, so item data arriving rebuilds it once.
equal(Stale(Event("ITEM_DATA_LOAD_RESULT")), "api | route tracker", "item data the public list waited on")
c.items[CLOTH] = { name = "Linen Cloth" }
c.Fire("BAG_UPDATE_DELAYED")
equal(Stale(Event("ITEM_DATA_LOAD_RESULT")), " | route tracker", "item data nothing waited on")

for _, case in ipairs({
	-- The window's own events redraw what shows it and keep the plans: its scan reports what changed in them.
	{ "TRADE_SKILL_DATA_SOURCE_CHANGED", "api | route tracker" },
	{ "NEW_RECIPE_LEARNED", "schematics plans api | route tracker" },
	{ "TRADE_SKILL_SHOW", "api | route tracker" },
	{ "TRADE_SKILL_LIST_UPDATE", "api | route tracker" },
	{ "SKILL_LINES_CHANGED", "plans api | route tracker" },
	{ "BAG_UPDATE_DELAYED", "api | route tracker" },
	{ "PLAYER_LEVEL_UP", "api | route tracker" },
	{ "ZONE_CHANGED_NEW_AREA", "api | " },
	{ "MERCHANT_SHOW", " | tracker" },
	{ "MERCHANT_UPDATE", " | tracker" },
	{ "MERCHANT_CLOSED", " | tracker" },
	{ "GET_ITEM_INFO_RECEIVED", " | " },
}) do
	equal(c.Listeners(case[1]), 1, case[1] .. " arrives on one frame")
	equal(Stale(Event(case[1])), case[2], case[1])
end

-- A recipe learned with no recipe list update after it (the window closed) still reaches the plan.
local function Plans(recipeID)
	for _, craft in ipairs(ns.PlanRoute(Tailoring()).crafts) do
		if craft.recipeID == recipeID then
			return true
		end
	end
	return false
end
equal(Plans(BOLT), false, "an unlearned recipe is not planned")
c.known[BOLT] = true
c.Fire("NEW_RECIPE_LEARNED")
equal(Plans(BOLT), true, "a newly learned recipe is planned at once")

-- One event that means two things is still one pass: every cache and view once.
c.professions[2] = { name = "Herbalism", rank = 1, max = 75, id = 182 }
equal(
	Stale(Event("SKILL_LINES_CHANGED")),
	"prices plans api | route recipeList tracker",
	"a skill change that is a new profession"
)
c.merchant = { { itemID = CLOTH, price = 40, stackCount = 5 } }
equal(
	Stale(Event("MERCHANT_SHOW")),
	"prices plans api | route recipeList tracker",
	"a merchant with a price not seen before"
)
equal(ns.Price(CLOTH).copper, 8, "which is the price now")
equal(Stale(Event("MERCHANT_UPDATE")), " | tracker", "the same merchant again")

-- A sell price the client had not loaded: one re-price after the burst of item data.
c.items[SHIRT_ITEM].sell = nil
ns.CraftCost(SHIRT)
equal(c.requested[SHIRT_ITEM], true, "the sell price is asked for")
c.items[SHIRT_ITEM].sell = 5
equal(Stale(Event("GET_ITEM_INFO_RECEIVED")), " | ", "item info a craft's value waited on changes nothing yet")
local function HalfASecond()
	c.Advance(0.5)
end
equal(Stale(HalfASecond), "prices plans api | route recipeList tracker", "it waits out the burst, then prices changed")
equal(Stale(HalfASecond), " | ", "once")

-- What the writers report.
equal(Stale(c.AuctionatorScan), "prices plans api | route recipeList tracker", "an Auctionator scan")
equal(Stale(Changed("fees")), "plans api | route tracker", "fees recorded at a trainer")
equal(Stale(Changed("target")), "plans api | route tracker", "a new target")
equal(
	Stale(function()
		ns.SetTracked(197, true)
	end),
	"api | route tracker",
	"tracking a profession"
)
equal(
	Stale(function()
		c.SetSetting("showSkill", true)
	end),
	"prices plans api | route recipeList tracker trainer routeTab",
	"a setting changed in the options panel: every view, once each, in the order they were always refreshed"
)
equal(pcall(ns.Changed, "typo"), false, "an unknown change is an error, not a silent no-op")

Client.report("changes_spec")
