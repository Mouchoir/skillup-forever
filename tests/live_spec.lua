-- Run from the repository root: luajit tests/live_spec.lua
-- The client's own recipe data and the one scan that reads it: the live grey threshold replaces the
-- bundled one while the bundled yellow and green stay, the skill points one craft grants change what
-- a plan asks for, a tool the bags lack blocks the craft and joins the shopping list, and a reagent a
-- known recipe makes for less than it costs to buy becomes its own craft step.
local Client = dofile("tests/client.lua")
local equal = Client.equal

--[[ The live read: grey, skill points, tools and stations, and one scan for a burst. ]]

local BANDAGE, CLOTH, HAMMER = 3275, 2589, 5956

local c = Client.load()
local ns = c.ns
c.professions = { { name = "First Aid", rank = 1, max = 75, id = 129 } }
c.known[BANDAGE] = true
local required = c.G.Enum.RecipeRequirementType
c.live[BANDAGE] = {
	info = { learned = true, maxTrivialLevel = 200, numSkillUps = 1, relativeDifficulty = 1 },
	requirements = {
		{ name = "Blacksmith Hammer", type = required.Totem, met = false },
		{ name = "Anvil", type = required.SpellFocus, met = true },
	},
}
c.items[HAMMER] = { name = "Blacksmith Hammer", sell = 1 }
-- The bandage's cloth and its output are priced, so the route has a step to block.
ns.db.vendor[CLOTH] = 10
c.items[1251] = { sell = 0 }

-- One scan per burst: the events of an open window arrive several to a frame.
local scans = 0
local realInfo = c.G.C_TradeSkillUI.GetRecipeInfo
c.G.C_TradeSkillUI.GetRecipeInfo = function(recipeID)
	scans = scans + 1
	return realInfo(recipeID)
end
c.Fire("TRADE_SKILL_SHOW")
c.Fire("TRADE_SKILL_LIST_UPDATE")
c.Fire("TRADE_SKILL_DATA_SOURCE_CHANGED")
equal(scans, 0, "no scan while the burst arrives")
c.Advance(0)
equal(scans, 1, "one scan for the whole burst")

local thresholds = ns.Model.Get(BANDAGE)
equal(thresholds[4], 200, "the client's live grey replaces the bundled one")
equal(thresholds[2], 30, "the bundled yellow stays under it")
equal(thresholds[3], 45, "and the bundled green")
equal(ns.RecipeSkillUps(BANDAGE), 1, "one point a craft when the client says so")
equal(ns.MissingTool(BANDAGE).name, "Blacksmith Hammer", "a tool the bags lack is reported")
equal(ns.MissingTool(BANDAGE).met, false, "as unmet")
equal(ns.RecipeStation(BANDAGE), "Anvil", "the station it is made at is named")

-- The craft's first step, blocked by the missing tool, and the tool in the shopping list once.
ns.db.routeTargets[129] = 20
local profession = ns.PlayerProfessions()[129]
local plan = ns.PlanRoute(profession)
ns.OpenSkillLine = function()
	return 129
end
equal(
	ns.NextCraft(plan).reason,
	"Need a Blacksmith Hammer in your bags.",
	"the craft button says which tool is missing"
)
local toolItems = ns.MissingToolItems(plan)
equal(#toolItems, 1, "the missing tool is named once")
equal(toolItems[1], HAMMER, "and resolved to its item")
local reagents = ns.RouteReagents(plan)
equal(reagents[#reagents].itemID, HAMMER, "it joins the shopping list")
equal(reagents[#reagents].need, 1, "needed once for the whole route")
equal(reagents[#reagents].source, "unknown", "an unpriced tool keeps the unknown bucket")

-- A linked or guild window shows someone else's recipes; its learned flags never overwrite ours.
c.known[BANDAGE] = nil
c.live[BANDAGE].info.learned = true
c.Fire("TRADE_SKILL_LIST_UPDATE")
c.Advance(0)
equal(ns.IsLearned(BANDAGE), true, "the scan records what this character knows")
local linkedScans = scans
c.G.C_TradeSkillUI.IsTradeSkillLinked = function()
	return true
end
c.live[BANDAGE].info.learned = false
c.Fire("TRADE_SKILL_LIST_UPDATE")
c.Advance(0)
equal(scans, linkedScans, "a linked window is not scanned")
equal(ns.IsLearned(BANDAGE), true, "and never unlearns a recipe")
c.G.C_TradeSkillUI.IsTradeSkillLinked = function()
	return false
end

-- The tool is carried now: the block lifts and the list drops it.
c.live[BANDAGE].requirements[1].met = true
equal(ns.MissingTool(BANDAGE), nil, "a carried tool is not missing")
equal(#ns.MissingToolItems(plan), 0, "and does not join the shopping list")

--[[ Multi-point crafts. ]]

local c2 = Client.load()
local ns2 = c2.ns
c2.professions = { { name = "First Aid", rank = 1, max = 75, id = 129 } }
c2.known[BANDAGE] = true
c2.live[BANDAGE] = {
	info = { learned = true, maxTrivialLevel = 60, numSkillUps = 2, relativeDifficulty = 1 },
}
ns2.db.vendor[CLOTH] = 10
c2.items[1251] = { sell = 0 }
c2.Fire("TRADE_SKILL_LIST_UPDATE")
c2.Advance(0)
equal(ns2.RecipeSkillUps(BANDAGE), 2, "the client's two points a craft are read")
equal(ns2.Model.CoveredCrafts(ns2.Model.Get(BANDAGE), 1, 11, 2), 5, "ten points in five crafts")
equal(ns2.Model.Gain(ns2.Model.Get(BANDAGE), 1, 2, 20), 2, "a craft grants its two points")
equal(ns2.Model.Gain(ns2.Model.Get(BANDAGE), 1, 2, 1), 1, "no more than the target still wants")
ns2.db.routeTargets[129] = 11
local multi = ns2.PlanRoute(ns2.PlayerProfessions()[129])
equal(multi.crafts[1].crafts, 5, "the route asks for half the crafts a two-point recipe gives")
equal(multi.crafts[1].skillUps, 2, "and says how many points a craft grants")
equal(multi.crafts[1].points, 10, "the step counts the ten points it reaches")

--[[ Sub-crafting: a reagent a learned recipe makes for less than buying it. ]]

local LEATHER, HIDE, GOODS = 20, 10, 30
local c3 = Client.load({
	data = {
		Thresholds = {
			[200] = { 80, 80, 100, 120 },
			[201] = { 1, 40, 55, 70 },
		},
		RecipeData = {
			[200] = {
				skillLine = 129,
				reagents = { { itemID = HIDE, quantity = 2 } },
				output = { itemID = LEATHER, quantity = 1 },
			},
			[201] = {
				skillLine = 129,
				reagents = { { itemID = LEATHER, quantity = 1 } },
				output = { itemID = GOODS, quantity = 1 },
			},
		},
		VendorPrices = { [HIDE] = 100, [LEATHER] = 300 },
		ItemSellPrices = {},
		TrainerFees = {},
		TrainerRanks = {},
		GatheredBy = {},
	},
})
local ns3 = c3.ns
c3.professions = { { name = "First Aid", rank = 1, max = 300, id = 129 } }
c3.known[200], c3.known[201] = true, true
-- The crafted output sells for nothing, so both recipes have a price and the route can rank them.
c3.items[LEATHER] = { name = "Cured Light Hide", sell = 0 }
c3.items[GOODS] = { name = "Cured Goods", sell = 0 }

equal(ns3.SubCraft(LEATHER).recipeID, 200, "a cheaper recipe makes the reagent")
equal(ns3.SubCraft(HIDE), nil, "nothing makes the raw hide")
ns3.db.routeTargets[129] = 20
local sub = ns3.PlanRoute(ns3.PlayerProfessions()[129])
equal(sub.crafts[1].recipeID, 201, "the route levels with the recipe that uses the reagent")
equal(#sub.crafts[1].subcrafts, 1, "which carries its own sub-craft")
equal(sub.crafts[1].subcrafts[1].recipeID, 200, "the recipe that makes the reagent")
equal(sub.crafts[1].subcrafts[1].crafts, sub.crafts[1].crafts, "one sub-craft a craft of the parent")

local kinds = {}
for index, step in ipairs(sub.steps) do
	kinds[index] = step.subcraft and "subcraft" or step.craft and "craft" or "other"
end
equal(table.concat(kinds, " "), "subcraft craft", "the sub-craft is a step of its own before the craft")
equal(sub.steps[1].subcraft.itemID, LEATHER, "for the reagent the craft needs")

local subReagents = ns3.RouteReagents(sub)
equal(#subReagents, 1, "the shopping list holds the raw reagent alone")

-- A sub-craft's own tool is read too, and joins the list once.
c3.items[HAMMER] = { name = "Blacksmith Hammer" }
c3.live[200] = {
	requirements = { { name = "Blacksmith Hammer", type = c3.G.Enum.RecipeRequirementType.Totem, met = false } },
}
local subTools = ns3.MissingToolItems(sub)
equal(#subTools, 1, "a sub-craft's missing tool is added once")
equal(subTools[1], HAMMER, "resolved to its item")
c3.live[200].requirements[1].met = true

equal(subReagents[1].itemID, HIDE, "the hide the reagent is made from")
equal(subReagents[1].need, sub.crafts[1].crafts * 2, "two a craft of the reagent")
equal(subReagents[1].source, "vendor", "priced where it is sold")

-- Not this recipe on the sub-craft: the reagent is bought instead of made.
ns3.SetSkipped(200, true)
equal(ns3.SubCraft(LEATHER), nil, "a skipped recipe never makes a reagent")
local bought = ns3.PlanRoute(ns3.PlayerProfessions()[129])
equal(#bought.crafts[1].subcrafts, 0, "the route buys the reagent instead")
ns3.SetSkipped(200, false)
equal(ns3.SubCraft(LEATHER).recipeID, 200, "and makes it again once shown again")

-- A cycle between two recipes is broken, never followed.
local c4 = Client.load({
	data = {
		Thresholds = { [300] = { 1, 40, 55, 70 }, [301] = { 1, 40, 55, 70 } },
		RecipeData = {
			[300] = {
				skillLine = 129,
				reagents = { { itemID = 50, quantity = 1 } },
				output = { itemID = 40, quantity = 1 },
			},
			[301] = {
				skillLine = 129,
				reagents = { { itemID = 40, quantity = 1 } },
				output = { itemID = 50, quantity = 1 },
			},
		},
		VendorPrices = { [40] = 400, [50] = 100 },
		ItemSellPrices = {},
		TrainerFees = {},
		TrainerRanks = {},
		GatheredBy = {},
	},
})
local ns4 = c4.ns
c4.known[300], c4.known[301] = true, true
equal(ns4.SubCraft(40).recipeID, 300, "the cycle's first item is made by its own recipe")
equal(ns4.SubCraft(50), nil, "and the item that closes the cycle is bought instead")

--[[ A rank boundary splits on a whole craft, so a two-point recipe is not asked for twice. ]]

local SPLIT_RECIPE, CLOTH5, GOODS5 = 400, 10, 30
local c5 = Client.load({
	data = {
		Thresholds = { [SPLIT_RECIPE] = { 1, 200, 210, 220 } },
		RecipeData = {
			[SPLIT_RECIPE] = {
				skillLine = 129,
				reagents = { { itemID = CLOTH5, quantity = 1 } },
				output = { itemID = GOODS5, quantity = 1 },
			},
		},
		VendorPrices = { [CLOTH5] = 1 },
		ItemSellPrices = {},
		TrainerFees = {},
		TrainerRanks = { [129] = { { 150, 500, 50, 0 } } },
		GatheredBy = {},
	},
})
local ns5 = c5.ns
c5.professions = { { name = "First Aid", rank = 49, max = 75, id = 129 } }
c5.known[SPLIT_RECIPE] = true
c5.items[GOODS5] = { sell = 0 }
c5.live[SPLIT_RECIPE] = {
	info = { learned = true, maxTrivialLevel = 220, numSkillUps = 2, relativeDifficulty = 1 },
}
c5.Fire("TRADE_SKILL_LIST_UPDATE")
c5.Advance(0)
ns5.db.routeTargets[129] = 77
local split = ns5.PlanRoute(ns5.PlayerProfessions()[129])
local splitCrafts = 0
for _, craft in ipairs(split.crafts) do
	splitCrafts = splitCrafts + craft.crafts
end
equal(#split.ranks, 1, "the rank is trained on the way")
equal(splitCrafts, 14, "a split at the rank asks for the same crafts as one run")
equal(split.crafts[1].to, 51, "and lands on what the recipe's two points reach above the requirement")
equal(split.steps[1].craft.crafts, 1, "the craft below the rank is one craft")
equal(split.steps[2].rank.name, "Journeyman", "with the rank next")
equal(split.steps[3].craft.crafts, 13, "and the crafts past it carry the rest")

Client.report("live_spec")
