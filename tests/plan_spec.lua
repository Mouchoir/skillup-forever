-- Run from the repository root: luajit tests/plan_spec.lua
-- The levelling plan over the bundled First Aid data, with no frames loaded:
-- Linen Bandage (3275), and Heavy Linen Bandage (3276), which a trainer teaches at 40 for 1s.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local LINEN, HEAVY, WOOL, CLOTH = 3275, 3276, 3277, 2589
local known, costs, sources, skipped = {}, {}, {}, {}
local auctionator, open, craftable, level = false, 129, 99, 20
local dropPlans
local ns = {
	db = { trainer = {}, trainerRanks = {}, routeTargets = {} },
	Catalogue = {
		Recipe = function(recipeID)
			return sources[recipeID]
		end,
	},
	WhenStale = function(_, drop)
		dropPlans = drop
	end,
	IsLearned = function(id)
		return known[id] == true
	end,
	IsSkipped = function(id)
		return skipped[id] == true
	end,
	NetCost = function(id)
		return costs[id]
	end,
	PriceSource = function(id)
		return sources[id]
	end,
	Price = function(id)
		return sources[id] and { copper = 1, source = sources[id] }
	end,
	HasAuctionator = function()
		return auctionator
	end,
	OpenSkillLine = function()
		return open
	end,
	PlayerProfessions = function()
		return { [129] = { name = "First Aid" }, [182] = { name = "Herbalism" } }
	end,
}
ns.Reagents = function(id)
	return ns.RecipeData[id].reagents
end
ns.Have = function()
	return 0
end
local env = setmetatable({
	APPRENTICE = "Apprentice",
	JOURNEYMAN = "Journeyman",
	EXPERT = "Expert",
	ARTISAN = "Artisan",
	UnitLevel = function()
		return level
	end,
	C_Spell = {
		GetSpellName = function(id)
			return ({ [LINEN] = "Linen Bandage", [HEAVY] = "Heavy Linen Bandage" })[id]
		end,
	},
	C_TradeSkillUI = {
		GetCraftableCount = function()
			return craftable
		end,
	},
}, { __index = _G })
for _, file in ipairs({
	"Locales/enUS.lua",
	"Data/Thresholds.lua",
	"Data/Recipes.lua",
	"Data/Trainer.lua",
	"Core/Model.lua",
	"Core/Plan.lua",
}) do
	setfenv(assert(loadfile(file)), env)("SkillUpForever", ns)
end

local function FirstAid(base, modifier, max)
	modifier, max = modifier or 0, max or 75
	return {
		skillLine = 129,
		name = "First Aid",
		base = base,
		modifier = modifier,
		skill = base + modifier,
		max = max,
		capped = base >= max,
	}
end
-- A fresh plan for a new setup: the cache is keyed on skill and target, not on what is known.
local function Plan(profession, target)
	ns.db.routeTargets[129] = target
	dropPlans()
	return ns.PlanRoute(profession)
end
local function Kinds(plan)
	local kinds = {}
	for index, step in ipairs(plan.steps) do
		kinds[index] = step.rank and "rank" or step.training and "train" or "craft"
	end
	return table.concat(kinds, " ")
end

equal(ns.RouteProfessions()[129].name, "First Aid", "a crafting profession can be planned")
equal(ns.RouteProfessions()[182], nil, "a gathering one can't")
equal(ns.RankName(150), "Journeyman", "the 150 cap is Journeyman")
equal(ns.RankName(60), nil, "a cap no rank ends at has no name")

-- Where the known recipes run out.
known[LINEN], costs[LINEN] = true, 1
local short = Plan(FirstAid(1), 100)
equal(short.target, 100, "the saved target")
equal(short.reached, 60, "Linen Bandage alone stops at 60")
equal(short.stopReason, "no_recipe", "for want of a recipe")
equal(#short.ranks, 0, "a rank past where the route stops is not trained")
equal(Kinds(short), "craft", "one step")
equal(short.crafts[1].color, "orange", "coloured where the craft starts")
equal(ns.RouteBlocked(short), nil, "a plan with crafts isn't blocked")
equal(ns.PlanRoute(FirstAid(1)), short, "the same skill and target is the same plan")
equal(Plan(FirstAid(1), 100) ~= short, true, "an invalidated plan is planned again")
equal(Plan(FirstAid(1), 0).target, 26, "no target, or one already reached, is 25 points on")
equal(Plan(FirstAid(60), 300).target, 150, "a target stops at the last rank a trainer teaches")

-- A rank is trained between the crafts either side of the skill it needs.
known[HEAVY], costs[HEAVY] = true, 1
local ranked = Plan(FirstAid(40), 90)
equal(Kinds(ranked), "craft rank craft", "crafts, the rank, then crafts on")
equal(ranked.steps[1].craft.to, 50, "crafts up to the skill Journeyman needs")
equal(ranked.steps[2].rank.name, "Journeyman", "then trains Journeyman")
equal(ranked.steps[2].rank.reqSkill, 50, "at 50")
equal(ranked.steps[3].craft.from, 50, "then crafts on past the cap")
equal(ranked.steps[3].craft.to, 90, "to the target")
equal(ranked.reached, 90, "which it reaches")
equal(ranked.cost, 500 + 10 + 92, "the rank's fee and the covered crafts are in the cost")
equal(ns.RankText(ranked.ranks[1]), "Train Journeyman at 50", "the rank as a line")
-- What a trainer was seen to charge for the rank replaces the bundled fee, in the step and the total.
ns.db.trainerRanks[129] = { [150] = 450 }
local charged = Plan(FirstAid(40), 90)
equal(charged.steps[2].rank.fee, 450, "a fee seen at a trainer wins")
equal(charged.cost, 450 + 10 + 92, "and is the one in the cost")
ns.db.trainerRanks[129] = nil
ranked.ranks[1].level, level = 10, 5
equal(ns.RankText(ranked.ranks[1]), "Train Journeyman at 50 (level 10)", "with the level while below it")
level = 20

-- Every reagent the crafts use, totalled, in the bucket its price puts it in.
local cloth = ranked.crafts[1].crafts * 2 + ranked.crafts[2].crafts * 2
local reagents = ns.RouteReagents(ranked)
equal(#reagents, 1, "one reagent")
equal(reagents[1].itemID, CLOTH, "linen cloth")
equal(reagents[1].need, cloth, "two a craft, for both halves of the split")
equal(reagents[1].source, "unknown", "no price, no source")
sources[CLOTH] = "auctionator"
equal(ns.RouteReagents(ranked)[1].source, "auction", "an auction price is the auction bucket")
sources[CLOTH] = nil

-- A recipe to train is trained just before its first craft, with what the trainer wants for it.
known[HEAVY] = nil
local trained = Plan(FirstAid(40), 75)
equal(Kinds(trained), "train craft", "the training, then its craft")
local training = trained.training[1]
equal(trained.steps[1].training, training, "the step is the plan's training")
equal(training.recipeID, HEAVY, "Heavy Linen Bandage")
equal(training.fee, 100, "its fee")
equal(training.reqSkill, 40, "the skill the trainer wants, with no walk needed first")
equal(training.cap, 41, "from a trainer who teaches past it")
equal(training.usedAt, 40, "first crafted at 40")
equal(trained.cost, 100 + 49, "the fee and the covered crafts are in the cost")
ns.db.trainer[129] = { [HEAVY] = { 80, 50 } }
local quoted = Plan(FirstAid(40), 75)
equal(quoted.training[1].fee, 80, "a trainer seen to charge less wins")
equal(quoted.training[1].reqSkill, 50, "and so does the skill it wanted")
equal(quoted.training[1].usedAt, 50, "nothing is crafted before it can be taught")
ns.db.trainer[129] = nil
-- Not this recipe: a skipped recipe is never trained, and the route carries on with what is left.
skipped[HEAVY] = true
local unskipped = Plan(FirstAid(40), 75)
equal(#unskipped.training, 0, "a skipped recipe is not trained")
equal(unskipped.crafts[1].recipeID, LINEN, "the route crafts what is left")
skipped[LINEN] = true
local nothing = Plan(FirstAid(40), 75)
equal(#nothing.crafts, 0, "skipping every recipe leaves nothing to craft")
equal(ns.RouteBlocked(nothing), "Nothing you know skills up past 40.", "the usual no-route state")
skipped = {}

-- The plan is in base skill whatever the racial bonus; thresholds are met with the bonus.
local bonus = Plan(FirstAid(40, 15), 75)
equal(bonus.crafts[1].from, 40, "crafts start at the base skill")
equal(bonus.crafts[1].recipeID, HEAVY, "with the recipe the bonus already makes the better one")
equal(bonus.crafts[#bonus.crafts].to, 75, "and end at the base target")
equal(bonus.reached, 75, "reached in base skill")
equal(bonus.training[1].usedAt, 40, "training is placed in base skill")
equal(bonus.training[1].reqSkill, 40, "at the base skill the trainer wants")
equal(bonus.crafts[1].color, "yellow", "55 with the bonus is yellow")
known[HEAVY] = true
local bonusRank = Plan(FirstAid(40, 15), 90)
equal(Kinds(bonusRank), "craft rank craft", "the rank still splits the crafts")
equal(bonusRank.steps[1].craft.to, 50, "at the base skill it needs")
known[LINEN] = nil
equal(Plan(FirstAid(40, 15), 150).reached, 85, "Heavy Linen Bandage goes grey at 100 with the bonus")
known[LINEN] = true

-- The difficulty bands a recipe still has from where it can be learned.
local function Bands(recipeID)
	local parts = {}
	for index, band in ipairs(ns.RecipeBands(FirstAid(40), recipeID)) do
		parts[index] = band.color .. " " .. band.from
	end
	return table.concat(parts, ", ")
end
equal(Bands(LINEN), "orange 1, yellow 30, green 45, grey 60", "every band from the data")
equal(Bands(HEAVY), "orange 40, yellow 50, green 75, grey 100", "from where the trainer teaches it")
ns.db.trainer[129] = { [HEAVY] = { 80, 60 } }
equal(Bands(HEAVY), "yellow 60, green 75, grey 100", "a band over before it can be learned is dropped")
ns.db.trainer[129] = nil
sources[LINEN] = { skill = 35 }
equal(Bands(LINEN), "yellow 35, green 45, grey 60", "a scroll's required skill counts the same")
sources[LINEN] = {}
equal(Bands(LINEN), "orange 1, yellow 30, green 45, grey 60", "a scroll of unknown skill starts with the data")
sources[LINEN] = nil
equal(#ns.RecipeBands(FirstAid(40), 1), 0, "no thresholds, no bands")

-- The skill where a recipe can be learned, the number the crafted gear view shows for its recipe:
-- a trainer's own requirement, not the data's placeholder first threshold.
-- classic-db's 110 and 120 moved down as far as Forever moved each recipe's range from Classic Era's.
equal(ns.LearnSkill(FirstAid(40), 3848), 85, "Double-stitched Woolen Shoulders is taught at 85")
equal(ns.LearnSkill(FirstAid(40), 2166), 95, "Toughened Leather Armor is taught at 95")
equal(ns.LearnSkill(FirstAid(40), 19819), 290, "a recipe with no trainer takes its pattern's skill")
-- A Forever-added recipe with no trainer: the pattern that teaches it carries the real requirement,
-- where the client's own orange sits at its placeholder 1.
local leatherworking = { skillLine = 165, name = "Leatherworking", skill = 0, modifier = 0 }
equal(ns.LearnSkill(leatherworking, 1255109), 100, "Brawler's Leather Hood's pattern asks 100")
equal(ns.LearnSkill(leatherworking, 1255105), 100, "Stormrider's Leather Hood's pattern asks 100")
equal(ns.LearnSkill(leatherworking, 12719), 0, "a recipe with no known source has no skill")
-- It draws no band below where it is taught, so the orange band starts at the pattern's skill.
local hood = ns.RecipeBands(leatherworking, 1255109)
equal(hood[1].color .. " " .. hood[1].from, "orange 100", "the hood's first band starts at the pattern's skill")

-- Why there is nothing to craft.
costs[LINEN], costs[HEAVY] = nil, nil
local unpriced = Plan(FirstAid(40), 75)
equal(#unpriced.steps, 0, "nothing priced, nothing to walk")
equal(unpriced.unpriced, 2, "both known recipes are left out")
equal(
	ns.RouteBlocked(unpriced),
	"These reagents have no vendor price. Auction prices need Auctionator.",
	"unpriced without Auctionator"
)
auctionator = true
equal(
	ns.RouteBlocked(unpriced),
	"Auctionator hasn't seen these reagents yet: scan the auction house with it to price them.",
	"unpriced with it"
)
auctionator = false
local missing = ns.UnpricedReagents(unpriced)
equal(#missing, 1, "the reagent that keeps them out, once")
equal(missing[1], CLOTH, "linen cloth")
sources[CLOTH] = "vendor"
equal(#ns.UnpricedReagents(unpriced), 0, "a priced reagent isn't listed")
sources[CLOTH] = nil
equal(Plan(FirstAid(70), 75).unpriced, 1, "a grey recipe keeps nothing out")
costs[LINEN], costs[HEAVY] = 1, 1
known[LINEN], known[HEAVY] = nil, nil
ns.db.trainer[129] = { [HEAVY] = { 100, 200 } }
equal(ns.RouteBlocked(Plan(FirstAid(40), 75)), "Nothing you know skills up past 40.", "nothing known")
equal(ns.RouteBlocked(Plan(FirstAid(40, 15), 75)), "Nothing you know skills up past 40.", "in base skill")
ns.db.trainer[129] = nil
known[LINEN], known[HEAVY] = true, true
equal(
	ns.RouteBlocked(Plan(FirstAid(150, 0, 150), 200)),
	"At the 150 cap: no trainer teaches the next rank.",
	"capped with no rank to train"
)

-- The next craft: the first craft, as often as it needs and the client allows.
local five = Plan(FirstAid(10), 15)
craftable = 2
local craft = ns.NextCraft(five)
equal(craft.count, 2, "the client count limits the batch")
equal(craft.recipeID, LINEN, "an available batch can be crafted")
equal(craft.text, "Craft 2 of 5× Linen Bandage", "and says how many of the route's it can make")
craftable = 12
equal(ns.NextCraft(five).count, 5, "never crafts beyond the planned step")
craftable = 0
craft = ns.NextCraft(five)
equal(craft.recipeID, nil, "zero available disables crafting")
equal(craft.text, "Craft 5× Linen Bandage", "the label still names the craft")
equal(craft.reason, "Missing reagents for this step.", "zero available explains the disabled button")
equal(craft.missing.itemID, CLOTH, "and names the reagent it is short of")
equal(craft.missing.count, 5, "with how many more it needs")
craftable = 99
open = 171
equal(ns.NextCraft(five).reason, "Open First Aid to craft from here.", "another profession is open")
open = 129
-- Heavy Linen Bandage from 70 to the 75 cap: five points whose chance falls from 0.6 to 0.52.
equal(ns.NextCraft(Plan(FirstAid(70), 90)).count, 13, "crafts only to the cap until the rank is trained")
-- With a +15 bonus the same thresholds are met from 55 base, and the cap of 75 base is 90 with it.
equal(ns.NextCraft(Plan(FirstAid(55, 15), 90)).count, 67, "the cap is on base skill")
equal(
	ns.NextCraft(Plan(FirstAid(75), 90)).reason,
	"Train Journeyman first: you're at your cap.",
	"at the cap the rank comes first"
)
known[HEAVY] = nil
equal(ns.NextCraft(Plan(FirstAid(60), 75)).reason, "Train Heavy Linen Bandage first.", "an unlearned recipe")
known[LINEN] = nil
equal(ns.NextCraft(Plan(FirstAid(100), 110)).reason, "Nothing to craft on this route.", "an empty plan")
known[LINEN] = true

-- The trainer window: which of its offers to train next.
ns.db.routeTargets[129], costs[WOOL] = 75, 1
local offers = { { recipeID = WOOL, fee = 250 }, { recipeID = HEAVY, fee = 100 } }
equal(ns.BestTraining(FirstAid(40), {}, offers), HEAVY, "the offer that carries the route on")
equal(ns.BestTraining(FirstAid(40), {}, { offers[1] }), nil, "not one the target never uses")
equal(ns.BestTraining(FirstAid(75), {}, offers), nil, "nothing at the cap")
skipped[HEAVY] = true
equal(ns.BestTraining(FirstAid(40), {}, offers), nil, "not one the player skipped")
skipped = {}
known[HEAVY] = true
equal(ns.BestTraining(FirstAid(40), {}, offers), nil, "not one already learned")
known[HEAVY] = nil
ns.db.routeTargets[129] = 150
known[LINEN] = nil
offers = { { recipeID = WOOL, fee = 250 } }
equal(ns.BestTraining(FirstAid(60, 0, 150), {}, offers), nil, "nothing gets to where Wool Bandage starts")
equal(
	ns.BestTraining(FirstAid(60, 0, 150), { [HEAVY] = true }, offers),
	WOOL,
	"a recipe the trainer shows as known does"
)

Client.report("plan_spec")
