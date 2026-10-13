-- Run from the repository root: luajit tests/model_spec.lua
local ns = {}
assert(loadfile("Core/Model.lua"))("SkillUpForever", ns)
local Model = ns.Model
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function near(actual, expected, label)
	checks = checks + 1
	assert(
		type(actual) == "number" and math.abs(actual - expected) < 1e-12,
		label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	)
end

equal(Model.Get(2152), nil, "lookup before data loads")
equal(Model.Color(nil, 48), nil, "unknown color")
equal(Model.Chance(nil, 48), nil, "unknown chance")

ns.Thresholds = { [2674] = { 125, 100, 107, 115 } }
equal(Model.Get(2674), nil, "contradictory bundled thresholds are unknown")
ns.Thresholds = nil

local cloak = { 1, 40, 55, 70 }
local boundaries = {
	{ -1, "red" },
	{ 0, "red" },
	{ 1, "orange", 1 },
	{ 2, "orange", 1 },
	{ 39, "orange", 1 },
	{ 40, "yellow", 1 },
	{ 41, "yellow", 29 / 30 },
	{ 48, "yellow", 22 / 30 },
	{ 54, "yellow", 16 / 30 },
	{ 55, "green", 0.5 },
	{ 56, "green", 14 / 30 },
	{ 69, "green", 1 / 30 },
	{ 70, "grey", 0 },
	{ 71, "grey", 0 },
	{ 300, "grey", 0 },
}
for _, case in ipairs(boundaries) do
	local skill, color, chance = case[1], case[2], case[3]
	local label = "Handstitched Leather Cloak at " .. skill
	equal(Model.Color(cloak, skill), color, label .. " color")
	if chance == nil then
		equal(Model.Chance(cloak, skill), nil, label .. " chance")
	else
		near(Model.Chance(cloak, skill), chance, label .. " chance")
	end
end

for _, invalid in ipairs({ { 1, 40, 40, 40 }, { 1, 40, 35, 30 } }) do
	for _, skill in ipairs({ 0, 1, 29, 30, 39, 40, 70 }) do
		equal(Model.Chance(invalid, skill), nil, "grey<=yellow at " .. skill)
	end
end

local tiny = { 1, 10, 10, 11 }
equal(Model.Color(tiny, 9), "orange", "tiny range before yellow")
equal(Model.Color(tiny, 10), "green", "green equals yellow")
near(Model.Chance(tiny, 10), 1, "tiny range chance at yellow")
equal(Model.Color(tiny, 11), "grey", "tiny range grey boundary")
near(Model.Chance(tiny, 11), 0, "tiny range grey chance")
equal(Model.Color({ 10, 10, 15, 20 }, 9), "red", "orange equals yellow: red")
equal(Model.Color({ 10, 10, 15, 20 }, 10), "yellow", "orange equals yellow: yellow")
near(Model.Chance({ 10, 10, 15, 20 }, 10), 1, "orange equals yellow chance")

assert(loadfile("Data/Thresholds.lua"))("SkillUpForever", ns)
equal(type(ns.Thresholds), "table", "generated namespace table")
equal(Model.Get(-1), nil, "unknown recipe")
equal(Model.Get(2152), ns.Thresholds[2152], "lookup uses recipe spell ID")
-- These are spell IDs, not the output item IDs.
-- Sample every profession that levels by crafting, with recipes the client has always had: a
-- recipe Forever adds can lose its skill range in a later build, and with it its thresholds.
local samples = {
	2152,
	9058,
	2331,
	7418,
	2660,
	2963,
	3918,
	2540,
	2657,
	3275,
}
for _, recipeID in ipairs(samples) do
	local t = Model.Get(recipeID)
	local label = "sample recipe " .. recipeID
	equal(type(t), "table", label .. " exists")
	for index = 2, 4 do
		equal(t[index - 1] <= t[index], true, label .. " ascending thresholds")
	end
end
near(Model.Chance(Model.Get(9058), 48), 22 / 30, "generated cloak matches mockup")

-- Issue #107: the client's minimums for these sit above yellow (Classic's, left on a range Forever moved
-- 25 down). The generator moves Heavy Sharpening Stone's with its range and drops Coarse Sharpening
-- Stone's, which still would not fit, for the placeholder: neither shows "?".
local heavy = Model.Get(2674)
equal(heavy and table.concat(heavy, "/"), "100/100/107/115", "Heavy Sharpening Stone's minimum moved with it")
equal(Model.Color(heavy, 110), "green", "and it is craftable at 110")
local coarse = Model.Get(2665)
equal(coarse and table.concat(coarse, "/"), "1/40/47/55", "Coarse Sharpening Stone keeps the placeholder")
-- A pattern's own requirement is Runed Copper Breastplate's; Runed Copper Belt's moves with its range.
equal(table.concat(Model.Get(2667), "/"), "55/95/115/135", "Runed Copper Breastplate starts where its plans ask")
equal(Model.Color(Model.Get(2666), 75), "orange", "Runed Copper Belt is orange at 75, as the game says")
for recipeID, t in pairs(ns.Thresholds) do
	equal(Model.Get(recipeID) ~= nil, true, "bundled recipe " .. recipeID .. " is ordered: " .. table.concat(t, "/"))
end
equal(Model.Get(9985)[1], 1, "Bronze Warhammer uses the Forever requirement")
ns.LiveRecipes = { [9985] = { thresholds = { 1, 155, 170, 160 } } }
equal(Model.Get(9985), nil, "contradictory live grey is unknown")
ns.LiveRecipes = nil

local rows = 0
for recipeID, t in pairs(ns.Thresholds) do
	rows = rows + 1
	local label = "recipe " .. tostring(recipeID)
	equal(type(recipeID), "number", label .. " key type")
	equal(recipeID > 0 and recipeID % 1 == 0, true, label .. " positive integer key")
	equal(type(t), "table", label .. " row type")
	equal(#t, 4, label .. " four thresholds")
	for index = 1, 4 do
		equal(type(t[index]), "number", label .. " numeric threshold")
		equal(t[index] >= 0 and t[index] % 1 == 0, true, label .. " nonnegative integer threshold")
		if index > 2 then
			equal(t[index - 1] <= t[index], true, label .. " ascending thresholds")
		end
	end
	equal(t[4] > t[2], true, label .. " positive chance denominator")
	equal(t[3], math.floor((t[2] + t[4]) / 2), label .. " green midpoint")
end
equal(rows > 0, true, "generated table is not empty")

-- Per-skill-up cost scales by 1/chance.
equal(Model.CostPerSkillUp(45, 0.5), 90, "half chance doubles cost")
equal(Model.CostPerSkillUp(45, 0), nil, "no skill-up has no cost")
equal(Model.CostPerSkillUp(nil, 1), nil, "unpriced has no cost")
equal(Model.CostPerSkillUp(-20, 0.5), -40, "a profitable craft is profit per skill-up")
-- A route covers an unlucky run: nine runs in ten reach the target.
equal(Model.CONFIDENCE, 0.9, "the covered run is nine in ten")
equal(Model.CoveredCrafts(cloak, 1, 10), 9, "a certain run is one craft a point")
equal(Model.CoveredCrafts(cloak, 40, 41), 1, "an orange point is one craft")
equal(Model.CoveredCrafts(cloak, 55, 56), 4, "a half chance point covers in four crafts")
equal(Model.CoveredCrafts({ 1, 1, 3, 5 }, 2, 4), 5, "a falling chance compounds across points")
equal(Model.CoveredCrafts(cloak, 5, 5), 0, "no points need no crafts")
equal(Model.CostPerPoint(10, cloak, 20), 10, "a certain point costs one craft")
equal(Model.CostPerPoint(10, cloak, 55), 40, "a half chance point carries its risk")
equal(Model.CostPerPoint(10, cloak, 70), nil, "a grey point cannot be bought")
equal(Model.RoundMoney(80.4), 80, "copper stays copper")
equal(Model.RoundMoney(0), 0, "free recipes stay free")
equal(Model.RoundMoney(0.2), 1, "never rounds to nothing")
equal(Model.RoundMoney(4549), 4500, "silver drops copper")
equal(Model.RoundMoney(12345), 12300, "gold keeps silver")
equal(Model.RoundMoney(1234567), 1230000, "100g+ keeps whole gold")

-- Route choices change at integer skill boundaries; round only each segment's
-- accumulated expected crafts, not each individual skill point.
local function candidate(recipeID, thresholds, netCost, fee)
	return { recipeID = recipeID, thresholds = thresholds, netCost = netCost, fee = fee }
end
local flat = { 1, 100, 150, 200 }
local routeSnapshot = {
	skill = 1,
	target = 5,
	recipes = {
		candidate(20, flat, 15),
		candidate(10, { 1, 2, 3, 4 }, 10),
		candidate(1, flat, nil),
	},
}
local route = Model.PlanRoute(routeSnapshot)
equal(#route.segments, 2, "threshold crossing splits route")
equal(route.segments[1].recipeID, 10, "cheaper orange recipe first")
equal(route.segments[1].fromSkill, 1, "segment begins at effective skill")
equal(route.segments[1].toSkill, 3, "yellow recipe used while cheap")
equal(route.segments[2].recipeID, 20, "switch when expected cost rises")
equal(route.segments[2].fromSkill, 3, "consecutive segments meet")
equal(route.segments[2].toSkill, 5, "last segment reaches target")
near(route.expectedCost, 50, "route sums net costs")
equal(route.reachedSkill, 5, "route reaches target")
equal(route.stopReason, nil, "successful route has no stop reason")
equal(route.excluded.unpriced, 1, "unpriced counted once across all skills")
equal(#route.excluded.recipes, 1, "and named")
equal(routeSnapshot.recipes[1].recipeID, 20, "planning does not sort input")

for _, candidates in ipairs({
	{ candidate(20, flat, 0), candidate(10, flat, 0) },
	{ candidate(10, flat, 0), candidate(20, flat, 0) },
}) do
	local tied = Model.PlanRoute({ skill = 1, target = 3, recipes = candidates })
	equal(tied.segments[1].recipeID, 10, "zero-cost tie breaks by recipe ID")
	equal(#tied.segments, 1, "same recipe coalesces")
	equal(tied.segments[1].crafts, 2, "certain crafts stay integral")
	equal(tied.expectedCost, 0, "zero-cost route remains eligible")
end
local fractional = Model.PlanRoute({
	skill = 2,
	target = 4,
	recipes = { candidate(10, { 1, 1, 3, 5 }, 3) },
})
equal(fractional.segments[1].crafts, 5, "a two point step with a falling chance covers in five crafts")
near(fractional.expectedCost, 15, "cost uses the covered crafts")
local profitable = Model.PlanRoute({
	skill = 3,
	target = 4,
	recipes = { candidate(20, flat, -10), candidate(10, { 1, 1, 3, 5 }, -6) },
})
equal(profitable.segments[1].recipeID, 20, "a profit never rewards a lower chance")
near(profitable.expectedCost, -10, "negative expected cost is retained")
local partial = Model.PlanRoute({
	skill = 1,
	target = 6,
	recipes = {
		candidate(10, { 1, 1, 2, 3 }, 10),
		candidate(20, { 4, 5, 6, 7 }, 0),
		candidate(30, nil, -100),
		candidate(40, flat, nil),
	},
})
equal(partial.reachedSkill, 3, "unreachable gap stops at first missing point")
equal(partial.stopReason, "no_recipe", "partial route reports no recipe")
equal(partial.segments[1].toSkill, 3, "partial route retains completed segment")
near(partial.expectedCost, 50, "partial route retains covered cost")
equal(partial.excluded.unpriced, 1, "partial route retains exclusions")
for _, target in ipairs({ 1, 0 }) do
	local complete = Model.PlanRoute({ skill = 1, target = target, recipes = {} })
	equal(#complete.segments, 0, "target already reached needs no crafts")
	equal(complete.reachedSkill, 1, "already reached does not reduce skill")
	equal(complete.stopReason, nil, "already reached is successful")
	equal(complete.expectedCost, 0, "already reached has no cost")
end
local empty = Model.PlanRoute({ skill = 1, target = 2, recipes = { candidate(1, flat, nil) } })
equal(#empty.segments, 0, "only unpriced recipes cannot produce a route")
equal(empty.stopReason, "no_recipe", "only unpriced stops immediately")
local greyed = Model.PlanRoute({ skill = 5, target = 6, recipes = { candidate(1, { 1, 2, 3, 4 }, nil) } })
equal(greyed.excluded.unpriced, 0, "a grey unpriced recipe keeps nothing out of the route")

local trainingSnapshot = { skill = 1, target = 4, recipes = { candidate(100, flat, 100) } }
local training = Model.RecommendTraining(trainingSnapshot, { candidate(20, flat, 50, 100) })
equal(training.recipeID, 20, "cheaper trained recipe recommended")
near(training.savings, 50, "training fee charged once for three crafts")
equal(training.reachedSkill, 4, "training endpoint")
equal(#trainingSnapshot.recipes, 1, "training preserves learned recipe list")
equal(trainingSnapshot.recipes[1].recipeID, 100, "training preserves learned recipe")
equal(Model.RecommendTraining(trainingSnapshot, { candidate(20, flat, 50, 150) }), nil, "break-even training ignored")
equal(Model.RecommendTraining(trainingSnapshot, { candidate(20, flat, 50, 200) }), nil, "fee can erase savings")
equal(Model.RecommendTraining(trainingSnapshot, { candidate(20, flat, nil, 0) }), nil, "unpriced training ignored")
equal(Model.RecommendTraining(trainingSnapshot, {}), nil, "no training services")
for _, services in ipairs({
	{ candidate(20, flat, 50, 100), candidate(10, flat, 50, 100) },
	{ candidate(10, flat, 50, 100), candidate(20, flat, 50, 100) },
}) do
	equal(Model.RecommendTraining(trainingSnapshot, services).recipeID, 10, "training ties use recipe ID")
end
local blockedSnapshot = { skill = 1, target = 5, recipes = { candidate(100, { 1, 2, 2, 3 }, 100) } }
local reach = Model.RecommendTraining(blockedSnapshot, {
	candidate(10, { 1, 2, 2, 3 }, 0, 0), -- Saves money but remains blocked.
	candidate(20, { 1, 2, 3, 4 }, 0, 0), -- Cheaper, but reaches less far.
	candidate(30, flat, 1000, 500),
})
equal(reach.recipeID, 30, "reaching farther takes priority over savings")
equal(reach.reachedSkill, 5, "training reaches full target")

local laddered = Model.PlanWithTraining({ skill = 1, target = 10, recipes = { candidate(100, flat, 100) } }, {
	candidate(10, { 1, 5, 5, 6 }, 10, 50), -- Cheap early on.
	candidate(20, { 5, 10, 10, 11 }, 10, 50), -- Cheap once learnable at 5.
	candidate(30, flat, 90, 1000), -- Never worth its fee.
})
equal(#laddered.training, 2, "training ladder keeps both cheap recipes")
equal(laddered.training[1].recipeID, 10, "training ordered by first use")
equal(laddered.training[1].atSkill, 1, "early recipe trained first")
equal(laddered.training[2].recipeID, 20, "later recipe trained second")
equal(laddered.training[2].atSkill >= 5, true, "recipe not used before learnable")
equal(laddered.trainingCost, 100, "each fee charged once")
equal(laddered.reachedSkill, 10, "training ladder reaches target")
local untrained = Model.PlanWithTraining(trainingSnapshot, { candidate(20, flat, nil, 0) })
equal(#untrained.training, 0, "unpriced training never planned")
equal(untrained.trainingCost, 0, "no training, no fees")
near(untrained.expectedCost, Model.PlanRoute(trainingSnapshot).expectedCost, "no training keeps learned route")
equal(reach.savings < 0, true, "reach recommendation may cost more")
local partialReach = Model.RecommendTraining(blockedSnapshot, { candidate(20, { 1, 2, 3, 4 }, 100, 500) })
equal(partialReach.reachedSkill, 4, "improved partial reach is still recommended")
equal(partialReach.recipeID, 20, "partial reach can justify fee")

local recipeData = {
	[20] = { reagents = { { itemID = 4, quantity = 3 }, { itemID = 2, quantity = 1 } } },
	[10] = {
		reagents = {
			{ itemID = 5, quantity = 1 },
			{ itemID = 4, quantity = 2 },
			{ itemID = 3, quantity = 1 },
			{ itemID = 2, quantity = 2 },
			{ itemID = 1, quantity = 1 },
			{ itemID = 4, quantity = 1 }, -- Duplicate reagent slots must index once.
		},
	},
}
-- The same totals the old per-recipe walk produced, already summed a reagent at a time:
-- 20 at three crafts and again at one, then 10 at two crafts.
local shopping = Model.BucketItems({
	{ itemID = 4, count = 12 },
	{ itemID = 2, count = 4 },
	{ itemID = 5, count = 2 },
	{ itemID = 4, count = 4 },
	{ itemID = 3, count = 2 },
	{ itemID = 2, count = 4 },
	{ itemID = 1, count = 2 },
	{ itemID = 4, count = 2 },
}, function(itemID)
	return ({ [1] = "vendor", [2] = "auctionator", [3] = "auctionator", [4] = "vendor" })[itemID]
end)
equal(#shopping.vendor, 2, "vendor partition")
equal(shopping.vendor[1].itemID, 1, "vendor items sorted ascending")
equal(shopping.vendor[2].itemID, 4, "second vendor item")
equal(shopping.vendor[2].count, 18, "shared requirements aggregate")
equal(#shopping.auction, 2, "Auctionator prices partition as auction")
equal(shopping.auction[1].itemID, 2, "auction items sorted ascending")
equal(shopping.auction[1].count, 8, "shared auction quantity")
equal(shopping.auction[2].itemID, 3, "second auction item")
equal(shopping.unknown[1].itemID, 5, "missing source partition")
equal(shopping.unknown[1].count, 2, "unknown source retains quantity")
local index = Model.BuildReagentIndex(recipeData)
equal(#index[4], 2, "reverse index deduplicates reagent slots")
equal(index[4][1], 10, "reverse index sorted first")
equal(index[4][2], 20, "reverse index sorted second")
equal(index[5][1], 10, "reverse index single recipe")
equal(index[99], nil, "unreferenced item absent")
equal(next(Model.BuildReagentIndex({})), nil, "empty reverse index")

-- Exercise the runtime seam with a small API stub: a bundled fallback must not
-- hide a later live schematic, and unknown reagent data must never be free.
do
	local live, sell, onEvent = {}, nil, nil
	local auction = { [4] = 8 }
	local runtime = {
		Model = Model,
		Readable = ns.Readable,
		RecipeData = {
			[10] = { reagents = { { itemID = 1, quantity = 2 } }, output = { itemID = 2, quantity = 3 } },
			[11] = { reagents = { { itemID = 1, quantity = 2 }, { itemID = 4, quantity = 1 } } },
			[12] = { reagents = { { itemID = 1, quantity = 2 }, { itemID = 7, quantity = 1 } } },
			[13] = { reagents = {} },
		},
		ItemSellPrices = { [2] = 10 },
		VendorPrices = { [1] = 5 },
		GatheredBy = {},
		db = { craftValue = "vendor" },
		CollectMode = function()
			return "gather"
		end,
	}
	local frame = {
		SetScript = function(_, _, callback)
			onEvent = callback
		end,
		RegisterEvent = function() end,
	}
	local env = setmetatable({
		CreateFrame = function()
			return frame
		end,
		GetNormalizedRealmName = function()
			return "Realm"
		end,
		time = function()
			return 0
		end,
		C_TradeSkillUI = {
			GetRecipeSchematic = function(recipeID)
				return live[recipeID]
			end,
		},
		Enum = { CraftingReagentType = { Basic = 1 } },
		C_Item = {
			GetItemInfo = function()
				return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, sell
			end,
			RequestLoadItemDataByID = function() end,
		},
		Auctionator = {
			API = {
				v1 = {
					GetAuctionPriceByItemID = function(_, itemID)
						return auction[itemID]
					end,
				},
			},
		},
	}, { __index = _G })
	setfenv(assert(loadfile("Core/Changes.lua")), env)("SkillUpForever", runtime)
	setfenv(assert(loadfile("Integrations/Prices.lua")), env)("SkillUpForever", runtime)
	runtime.InitPrices()
	equal(runtime.Reagents(10), runtime.RecipeData[10].reagents, "bundled reagent fallback")
	equal(runtime.PriceSource(1), "vendor", "price source vendor")
	equal(runtime.PriceSource(4), "auctionator", "price source auctionator")
	equal(runtime.PriceSource(99), nil, "price source missing")
	live[98] = { reagentSlotSchematics = {} }
	equal(runtime.Reagents(98), nil, "empty live schematic without bundled data has unknown reagents")
	-- One craft's cost, value and net, asked for together: unknown is nil at every step, never free.
	---@return table
	local function costing(recipeID)
		local cost, value, net = runtime.CraftCost(recipeID)
		equal(runtime.NetCost(recipeID), net, "the net cost alone is the same net")
		return { cost = cost, value = value, net = net }
	end
	local function unknown(recipeID, label)
		local c = costing(recipeID)
		equal(c.cost, nil, label .. " is not free")
		equal(c.value, nil, label .. " has no value")
		equal(c.net, nil, label .. " has no net cost")
	end
	unknown(98, "empty live schematic without bundled data")
	live[97] = { reagentSlotSchematics = { { reagentType = 2, quantityRequired = 1, reagents = { { itemID = 1 } } } } }
	unknown(97, "optional-only live schematic without bundled data")
	unknown(99, "unknown recipe")
	unknown(12, "one unpriced reagent")
	equal(costing(11).cost, 18, "reagent cost sums each reagent's quantity")
	equal(costing(11).net, 18, "no output nets to the reagent cost")
	equal(costing(13).cost, 0, "no reagents costs nothing")
	equal(costing(10).cost, 10, "reagent cost")
	equal(costing(10).value.copper, 30, "bundled sell fallback includes output quantity")
	equal(costing(10).value.source, "vendor", "vendor source")
	equal(costing(10).net, -20, "net cost preserves profit")
	sell, auction[2] = 30, 100
	equal(costing(10).value.copper, 90, "vendor value ignores the auction")
	runtime.db.craftValue = "auction"
	equal(costing(10).value.copper, 285, "auction value is net of the cut")
	equal(costing(10).value.source, "auction", "auction source")
	equal(costing(10).net, -275, "auction net cost")
	auction[2] = 20
	equal(costing(10).value.copper, 90, "vendor beats a cheap auction")
	equal(costing(10).value.source, "vendor", "and is the source")
	sell, auction[2] = 0, 0
	equal(costing(10).value.copper, 0, "an auction price of zero still counts")
	auction[2] = nil
	equal(costing(10).value, nil, "live zero sell price overrides bundle")
	equal(costing(10).net, 10, "a worthless item nets to the reagent cost")
	sell = nil
	runtime.db.craftValue = "none"
	equal(costing(10).value, nil, "resale disabled ignores the value")
	equal(costing(10).net, 10, "resale disabled preserves full reagent cost")
	runtime.ItemSellPrices[2] = nil
	equal(costing(10).net, 10, "resale disabled needs no sell price")
	runtime.db.craftValue = "vendor"
	equal(costing(10).cost, 10, "unknown sell price keeps the reagent cost")
	equal(costing(10).value, nil, "unknown sell price has no value")
	equal(costing(10).net, nil, "unknown sell price leaves the net cost unknown, not full")
	runtime.ItemSellPrices[2] = 10
	equal(runtime.UsedIn(1)[1], 10, "runtime reverse index")
	equal(#runtime.UsedIn(99), 0, "runtime absent item returns empty array")
	live[10] = { reagentSlotSchematics = { { reagentType = 1, quantityRequired = 4, reagents = { { itemID = 1 } } } } }
	equal(runtime.Reagents(10)[1].quantity, 2, "bundled fallback is held until profession data changes")
	onEvent(frame, "TRADE_SKILL_LIST_UPDATE")
	equal(runtime.Reagents(10)[1].quantity, 4, "live schematic replaces the fallback after an update")
	equal(runtime.NetCost(10), 20, "live non-item output replaces bundled item")
	live[10] = nil
	onEvent(frame, "TRADE_SKILL_LIST_UPDATE")
	equal(runtime.Reagents(10)[1].quantity, 2, "profession update invalidates live cache")
	live[10] = { reagentSlotSchematics = {} }
	onEvent(frame, "TRADE_SKILL_LIST_UPDATE")
	equal(runtime.Reagents(10), runtime.RecipeData[10].reagents, "empty live schematic uses bundled reagents")
	equal(costing(10).cost, 10, "empty live schematic preserves bundled cost")
	live[10] = {
		reagentSlotSchematics = {
			{ reagentType = 1, quantityRequired = 4, reagents = { { itemID = 1 } } },
			{ reagentType = 1, quantityRequired = 1 },
		},
	}
	onEvent(frame, "TRADE_SKILL_LIST_UPDATE")
	equal(runtime.Reagents(10)[1].quantity, 2, "incomplete live reagents use bundled fallback")
	live[99] = { reagentSlotSchematics = { { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 99 } } } } }
	equal(runtime.Reagents(99)[1].itemID, 99, "previous recipe miss is not cached forever")
	equal(runtime.NetCost(99), nil, "unpriced live reagent prevents net cost")
	runtime.GatheredBy = { [5] = 393, [6] = 186 }
	runtime.PlayerProfessions = function()
		return { [393] = { name = "Skinning" } }
	end
	equal(runtime.PriceSource(5), "gather", "a gathering profession you have makes its yield free")
	equal(runtime.Price(5).copper, 0, "gathered reagents cost nothing")
	equal(runtime.PriceSource(6), nil, "another profession's yield stays unpriced")
	runtime.CollectMode = function()
		return "auction"
	end
	runtime.Changed("prices")
	equal(runtime.PriceSource(5), nil, "auction mode buys a gathered reagent instead of pricing it free")
end

print("model_spec: " .. checks .. " checks passed; " .. rows .. " generated thresholds validated")
