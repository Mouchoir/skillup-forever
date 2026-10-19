-- Run from the repository root: luajit tests/planner_spec.lua
-- A training search keeps what one re-plan works out for the next (the planner in Core/Model.lua). It must plan
-- exactly what re-planning every candidate from scratch planned. That planner, as v0.18.0 shipped it, is kept
-- below as the reference, and both run on seeded random snapshots and on a character half-way through five
-- professions with every reagent priced. Equal means equal: the same segments, crafts, costs and training,
-- every number to the last bit.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local ns = {}
assert(loadfile("Core/Model.lua"))("SkillUpForever", ns)
local Model = ns.Model

--[[ The reference: v0.18.0's planner, re-planning every candidate in full ]]

local Reference = {}

function Reference.CoveredCrafts(thresholds, from, to, skillUps)
	local needed = to - from
	if needed <= 0 then
		return 0
	end
	local ups = math.max(skillUps or 1, 1)
	local odds = { [0] = 1 }
	local crafts = 0
	while (odds[needed] or 0) < Model.CONFIDENCE do
		crafts = crafts + 1
		local next_ = { [needed] = odds[needed] or 0 }
		for points = 0, needed - 1 do
			local inHand = odds[points]
			if inHand then
				local chance = Model.Chance(thresholds, from + points)
				if chance and chance > 0 then
					local gained = math.min(ups, needed - points, math.max(thresholds[4] - (from + points), 1))
					next_[points] = (next_[points] or 0) + inHand * (1 - chance)
					next_[points + gained] = (next_[points + gained] or 0) + inHand * chance
				else
					next_[points] = (next_[points] or 0) + inHand
				end
			end
		end
		odds = next_
	end
	return crafts
end

function Reference.CostPerPoint(cost, thresholds, skill, skillUps)
	local ups = math.max(skillUps or 1, 1)
	if not cost or (Model.Chance(thresholds, skill) or 0) <= 0 then
		return nil
	end
	return cost * Reference.CoveredCrafts(thresholds, skill, skill + ups, ups) / ups
end

function Reference.PlanRoute(snapshot)
	local route = {
		segments = {},
		expectedCost = 0,
		reachedSkill = snapshot.skill,
		excluded = { unpriced = 0, recipes = {} },
	}
	local priced, thresholds, costOf = {}, {}, {}
	for _, recipe in ipairs(snapshot.recipes) do
		if recipe.netCost == nil then
			if recipe.thresholds[4] > snapshot.skill then
				route.excluded.unpriced = route.excluded.unpriced + 1
				route.excluded.recipes[route.excluded.unpriced] = recipe.recipeID
			end
		else
			priced[#priced + 1] = recipe
			thresholds[recipe.recipeID] = recipe.thresholds
			costOf[recipe.recipeID] = recipe.netCost
		end
	end
	while route.reachedSkill < snapshot.target do
		local skill = route.reachedSkill
		local best, bestKey, bestChance
		for _, recipe in ipairs(priced) do
			local chance = Model.Chance(recipe.thresholds, skill)
			local key = Reference.CostPerPoint(math.max(recipe.netCost, 0), recipe.thresholds, skill, recipe.skillUps)
			if
				key
				and (
					not best
					or key < bestKey
					or (key == bestKey and chance > bestChance)
					or (key == bestKey and chance == bestChance and recipe.recipeID < best.recipeID)
				)
			then
				best, bestKey, bestChance = recipe, key, chance
			end
		end
		if not best then
			route.stopReason = "no_recipe"
			break
		end
		local gain = Model.Gain(best.thresholds, skill, best.skillUps, snapshot.target - skill)
		if gain <= 0 then
			route.stopReason = "no_recipe"
			break
		end
		local segment = route.segments[#route.segments]
		if not segment or segment.recipeID ~= best.recipeID then
			segment = { recipeID = best.recipeID, fromSkill = skill, toSkill = skill, skillUps = best.skillUps }
			route.segments[#route.segments + 1] = segment
		end
		segment.toSkill = skill + gain
		route.reachedSkill = skill + gain
	end
	for _, segment in ipairs(route.segments) do
		segment.crafts =
			Reference.CoveredCrafts(thresholds[segment.recipeID], segment.fromSkill, segment.toSkill, segment.skillUps)
		route.expectedCost = route.expectedCost + costOf[segment.recipeID] * segment.crafts
	end
	return route
end

function Reference.RecommendTraining(snapshot, services)
	local baseline = Reference.PlanRoute(snapshot)
	local recipes = {}
	for index, recipe in ipairs(snapshot.recipes) do
		recipes[index] = recipe
	end
	local candidate = { skill = snapshot.skill, target = snapshot.target, recipes = recipes }
	local best
	for _, service in ipairs(services) do
		recipes[#snapshot.recipes + 1] = service
		local route = Reference.PlanRoute(candidate)
		local savings = baseline.expectedCost - (route.expectedCost + service.fee)
		local helps = route.reachedSkill > baseline.reachedSkill
			or (route.reachedSkill == baseline.reachedSkill and savings > 0)
		if
			helps
			and (
				not best
				or route.reachedSkill > best.reachedSkill
				or (route.reachedSkill == best.reachedSkill and savings > best.savings)
				or (
					route.reachedSkill == best.reachedSkill
					and savings == best.savings
					and service.recipeID < best.recipeID
				)
			)
		then
			best = { recipeID = service.recipeID, savings = savings, reachedSkill = route.reachedSkill }
		end
	end
	return best
end

function Reference.PlanWithTraining(snapshot, services)
	local recipes, remaining = {}, {}
	for index, recipe in ipairs(snapshot.recipes) do
		recipes[index] = recipe
	end
	for index, service in ipairs(services) do
		remaining[index] = service
	end
	local current = { skill = snapshot.skill, target = snapshot.target, recipes = recipes }
	local chosen = {}
	while true do
		local best = Reference.RecommendTraining(current, remaining)
		if not best then
			break
		end
		for index, service in ipairs(remaining) do
			if service.recipeID == best.recipeID then
				recipes[#recipes + 1] = service
				chosen[service.recipeID] = service
				table.remove(remaining, index)
				break
			end
		end
	end
	local route = Reference.PlanRoute(current)
	local firstUse = {}
	for _, segment in ipairs(route.segments) do
		firstUse[segment.recipeID] = firstUse[segment.recipeID] or segment.fromSkill
	end
	route.training, route.trainingCost = {}, 0
	for recipeID, service in pairs(chosen) do
		if firstUse[recipeID] then
			route.training[#route.training + 1] =
				{ recipeID = recipeID, fee = service.fee, atSkill = firstUse[recipeID] }
			route.trainingCost = route.trainingCost + service.fee
		end
	end
	table.sort(route.training, function(a, b)
		return a.atSkill < b.atSkill or (a.atSkill == b.atSkill and a.recipeID < b.recipeID)
	end)
	return route
end

--[[ Comparing ]]

-- Every field of both, both ways, compared with ==.
local function same(actual, expected, label)
	if type(expected) ~= "table" or type(actual) ~= "table" then
		equal(actual, expected, label)
		return
	end
	for key, value in pairs(expected) do
		same(actual[key], value, label .. "." .. tostring(key))
	end
	for key in pairs(actual) do
		equal(expected[key] ~= nil, true, label .. "." .. tostring(key) .. " is the reference's too")
	end
end

--[[ Seeded random snapshots ]]

-- Park and Miller's generator: every product stays exact in a double, so each run draws the same numbers.
local seed = 20261019
local function Random(low, high)
	seed = seed * 16807 % 2147483647
	return low + seed % (high - low + 1)
end

local function Thresholds()
	local orange = Random(1, 250)
	local yellow = orange + Random(0, 25)
	if Random(1, 15) == 1 then
		-- No yellow-to-grey span: Model.Chance has nothing to say, so it is never picked.
		return { orange, yellow, yellow, yellow }
	end
	local green = yellow + Random(0, 25)
	return { orange, yellow, green, green + Random(1, 40) }
end

local function NetCost()
	local roll = Random(1, 20)
	if roll <= 2 then
		return nil
	elseif roll <= 6 then
		return 0 -- many ties
	elseif roll <= 8 then
		return -Random(1, 4000) / 4 -- a profit
	end
	return Random(1, 8000) / 4
end

-- Recipes drawn from a small pool, so a list now and then holds one twice, or a service one the list has. A
-- recipe keeps its thresholds wherever it appears: its crafts are counted from the last copy in the list, and
-- the planner (old and new) never stops counting points another copy's thresholds call grey.
local POOL = {}
for recipeID = 1, 60 do
	POOL[recipeID] = { thresholds = Thresholds(), skillUps = Random(1, 3) == 1 and Random(2, 3) or nil }
end
-- A craft granting several points is ranked only where the route never asks for it fewer points than that short
-- of grey: there neither planner ever finishes counting its crafts, as the last point never covers.
---@param target number
---@param fee boolean?
local function Candidate(target, fee)
	local recipeID = Random(1, #POOL)
	local recipe = POOL[recipeID]
	local skillUps = recipe.skillUps
	return {
		recipeID = recipeID,
		thresholds = recipe.thresholds,
		netCost = NetCost(),
		skillUps = skillUps and recipe.thresholds[4] - skillUps >= target - 1 and skillUps or nil,
		fee = fee and Random(0, 20) * 50 or nil,
	}
end

local CASES = 300
for case = 1, CASES do
	local skill = Random(1, 220)
	local snapshot = { skill = skill, target = skill + Random(-2, 90), recipes = {} }
	for index = 1, Random(0, 14) do
		snapshot.recipes[index] = Candidate(snapshot.target)
	end
	local services = {}
	for index = 1, Random(0, 10) do
		services[index] = Candidate(snapshot.target, true)
	end
	local label = "case " .. case
	same(Model.PlanRoute(snapshot), Reference.PlanRoute(snapshot), label .. " route")
	same(
		Model.RecommendTraining(snapshot, services),
		Reference.RecommendTraining(snapshot, services),
		label .. " recommendation"
	)
	same(
		Model.PlanWithTraining(snapshot, services),
		Reference.PlanWithTraining(snapshot, services),
		label .. " trained route"
	)
	-- Only where every point still has a chance, as the planner asks: a grey point never covers.
	for index = 1, 3 do
		local t = POOL[Random(1, #POOL)].thresholds
		t = t[4] > t[2] and t or { t[1], t[2], t[2] + 5, t[2] + 10 }
		local from = Random(t[1], t[4] - 1)
		local to, ups = Random(from - 1, t[4]), Random(1, 3)
		equal(
			Model.CoveredCrafts(t, from, to, ups),
			Reference.CoveredCrafts(t, from, to, ups),
			label .. " covered crafts " .. index
		)
	end
end

--[[ A character half-way through five professions ]]

-- Every trainer recipe up to each rank is known, every reagent and product has an auction and a sell price, and
-- each route runs to 300, through the ranks and the training on the way. Each search the plans run is checked
-- against the reference on its own inputs.
local PROFESSIONS = {
	{ name = "Blacksmithing", id = 164, rank = 150, max = 225 },
	{ name = "Engineering", id = 202, rank = 120, max = 150 },
	{ name = "Cooking", id = 185, rank = 160, max = 225 },
	{ name = "First Aid", id = 129, rank = 110, max = 150 },
	{ name = "Mining", id = 186, rank = 140, max = 150 },
}
local saved = { routeTargets = {} }
for _, profession in ipairs(PROFESSIONS) do
	saved.routeTargets[profession.id] = 300
end
local c = Client.load({ boot = false, saved = saved })
for _, profession in ipairs(PROFESSIONS) do
	c.professions[#c.professions + 1] =
		{ name = profession.name, rank = profession.rank, max = profession.max, id = profession.id }
	for recipeID, training in pairs(c.ns.TrainerFees) do
		local recipe = c.ns.RecipeData[recipeID]
		if recipe and recipe.skillLine == profession.id and training[2] <= profession.rank then
			c.known[recipeID] = true
		end
	end
end
local items = {}
for _, recipe in pairs(c.ns.RecipeData) do
	for _, reagent in ipairs(recipe.reagents) do
		items[reagent.itemID] = true
	end
	if recipe.output then
		items[recipe.output.itemID] = true
	end
end
local itemIDs = {}
for itemID in pairs(items) do
	itemIDs[#itemIDs + 1] = itemID
end
table.sort(itemIDs)
for _, itemID in ipairs(itemIDs) do
	c.auction[itemID] = Random(100, 20000)
	c.items[itemID] = { name = "Item " .. itemID, sell = c.ns.ItemSellPrices[itemID] or Random(0, 500) }
end
c.Boot()

local searches, trained = 0, 0
local PlanWithTraining = c.ns.Model.PlanWithTraining
c.ns.Model.PlanWithTraining = function(snapshot, services)
	local route = PlanWithTraining(snapshot, services)
	searches, trained = searches + 1, trained + #route.training
	same(route, Reference.PlanWithTraining(snapshot, services), "search " .. searches)
	return route
end
for _, profession in pairs(c.ns.RouteProfessions()) do
	c.ns.PlanRoute(profession)
end
equal(searches, #PROFESSIONS, "each profession's plan was checked")
equal(trained > #PROFESSIONS, true, "and the routes train on the way")

Client.report("planner_spec")
