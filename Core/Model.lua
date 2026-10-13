---@type string, SkillUpNamespace
local _, ns = ...
---@class SkillUpModel
local Model = {}
ns.Model = Model

-- A value the client hands over as secret (Forever's restricted reads, as in combat) errors on a truth
-- test, a comparison or arithmetic, and stays secret wherever it is kept. nil for one, so the caller treats
-- it as unknown; any other value unchanged.
---@generic T
---@param value T
---@return T?
function ns.Readable(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

---@param recipeID integer
---@return number[]?
function Model.Get(recipeID)
	-- The client's live grey replaces the bundled one; its yellow and green do not exist, so the
	-- bundled pair stays under the live grey.
	local live = ns.LiveRecipes and ns.LiveRecipes[recipeID]
	local thresholds = live and live.thresholds or (ns.Thresholds and ns.Thresholds[recipeID])
	if
		thresholds
		and thresholds[1] <= thresholds[2]
		and thresholds[2] <= thresholds[3]
		and thresholds[3] < thresholds[4]
	then
		return thresholds
	end
	return nil
end

---@param t number[]?
---@param skill number
---@return string?
function Model.Color(t, skill)
	if not t then
		return nil
	end
	if skill < t[1] then
		return "red"
	end
	if skill < t[2] then
		return "orange"
	end
	if skill < t[3] then
		return "yellow"
	end
	if skill < t[4] then
		return "green"
	end
	return "grey"
end

---@param t number[]?
---@param skill number
---@return number?
function Model.Chance(t, skill)
	if not t or t[4] <= t[2] or skill < t[1] then
		return nil
	end
	if skill < t[2] then
		return 1
	end
	if skill >= t[4] then
		return 0
	end
	return (t[4] - skill) / (t[4] - t[2])
end

-- Expected spend per skill point: one craft costs `cost` and succeeds with `chance`.
---@param cost number?
---@param chance number?
---@return number?
function Model.CostPerSkillUp(cost, chance)
	if not cost or not chance or chance <= 0 then
		return nil
	end
	return cost / chance
end

-- The chance a run of crafts has to reach its skill goal, so a route is planned to cover an
-- unlucky run rather than the average one.
Model.CONFIDENCE = 0.9

-- The crafts that reach `to` from `from` with Model.CONFIDENCE certainty: the fewest crafts whose
-- odds of every needed skill point are at least that, worked out point by point because the
-- chance changes as skill rises. A craft can grant `skillUps` points at once, which the client's
-- own recipe info gives for an orange recipe.
---@param thresholds number[]
---@param from number
---@param to number
---@param skillUps integer?
---@return number
function Model.CoveredCrafts(thresholds, from, to, skillUps)
	local needed = to - from
	if needed <= 0 then
		return 0
	end
	local ups = math.max(skillUps or 1, 1)
	-- odds[points]: the chance that many points are in hand after the crafts counted so far.
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
					-- A craft never grants more points than the recipe has left before grey.
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

-- The skill points one craft grants at `skill`, at most `room` of them: the client's live count,
-- capped by what the recipe has left before grey and by what the target still wants.
---@param thresholds number[]
---@param skill number
---@param skillUps integer?
---@param room number
---@return integer
function Model.Gain(thresholds, skill, skillUps, room)
	local left = thresholds[4] - skill
	if left <= 0 or room <= 0 then
		return 0
	end
	return math.max(1, math.min(skillUps or 1, left, room))
end

-- Net cost of one skill point at Model.CONFIDENCE: a low chance carries the crafts it needs, and a
-- craft that grants several points is worth that many.
---@param cost number?
---@param thresholds number[]
---@param skill number
---@param skillUps integer?
---@return number?
function Model.CostPerPoint(cost, thresholds, skill, skillUps)
	local ups = math.max(skillUps or 1, 1)
	if not cost or (Model.Chance(thresholds, skill) or 0) <= 0 then
		return nil
	end
	return cost * Model.CoveredCrafts(thresholds, skill, skill + ups, ups) / ups
end

-- Inputs are already filtered to learned recipes of one profession, with prices
-- frozen by the caller. Inventory affects shopping, never recipe selection.
---@param snapshot SkillUpSnapshot
---@return SkillUpRoute
function Model.PlanRoute(snapshot)
	local route = {
		segments = {},
		expectedCost = 0,
		reachedSkill = snapshot.skill,
		excluded = { unpriced = 0, recipes = {} },
	}
	local priced, thresholds, costOf = {}, {}, {}
	for _, recipe in ipairs(snapshot.recipes) do
		if recipe.netCost == nil then
			-- A grey recipe could not help even with a price, so it keeps nothing out.
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
		-- A profit ranks as free: a falling chance would otherwise favour near-grey
		-- crafts that take many times the crafts per point.
		local best, bestKey, bestChance
		for _, recipe in ipairs(priced) do
			local chance = Model.Chance(recipe.thresholds, skill)
			local key = Model.CostPerPoint(math.max(recipe.netCost, 0), recipe.thresholds, skill, recipe.skillUps)
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
	-- Each step carries the crafts and cost that reach its target in nine runs of ten.
	for _, segment in ipairs(route.segments) do
		segment.crafts =
			Model.CoveredCrafts(thresholds[segment.recipeID], segment.fromSkill, segment.toSkill, segment.skillUps)
		route.expectedCost = route.expectedCost + costOf[segment.recipeID] * segment.crafts
	end
	return route
end

-- Reach comes first when the learned route is blocked; compare costs only for
-- equal endpoints. Each candidate is a separate purchase, charged exactly once.
---@param snapshot SkillUpSnapshot
---@param services SkillUpService[]
---@return {recipeID: integer, savings: number, reachedSkill: number}?
function Model.RecommendTraining(snapshot, services)
	local baseline = Model.PlanRoute(snapshot)
	local recipes = {}
	for index, recipe in ipairs(snapshot.recipes) do
		recipes[index] = recipe
	end
	local candidate = { skill = snapshot.skill, target = snapshot.target, recipes = recipes }
	local best
	for _, service in ipairs(services) do
		recipes[#snapshot.recipes + 1] = service
		local route = Model.PlanRoute(candidate)
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

-- The learned route plus whatever training pays for itself: keep adding the
-- service RecommendTraining picks (reach first, then savings net of its fee),
-- then drop any a later addition made unnecessary. Greedy, so not guaranteed
-- optimal, but each fee is charged once and only for recipes the route uses.
---@param snapshot SkillUpSnapshot
---@param services SkillUpService[]
---@return SkillUpTrainedRoute
function Model.PlanWithTraining(snapshot, services)
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
		local best = Model.RecommendTraining(current, remaining)
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
	local route = Model.PlanRoute(current)
	---@cast route SkillUpTrainedRoute
	local firstUse = {}
	for _, segment in ipairs(route.segments) do
		firstUse[segment.recipeID] = firstUse[segment.recipeID] or segment.fromSkill
	end
	-- An unused recipe never changes a greedy pick, so dropping it keeps the route.
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

-- The shopping list's buckets, in the order it lists them, and the price source that fills each;
-- a reagent with no price goes in "unknown". Everything that walks the list walks this.
---@type SkillUpShoppingSource[]
Model.SHOPPING_SOURCES = { "gather", "vendor", "auction", "unknown" }
---@type table<SkillUpPriceSource, SkillUpShoppingSource>
local BUCKET = { gather = "gather", vendor = "vendor", auctionator = "auction" }

---@param needed table<integer, number>
---@param sourceOf fun(itemID: integer): SkillUpPriceSource?
---@return table<string, SkillUpShoppingItem[]>
function Model.BucketNeeded(needed, sourceOf)
	local list = {}
	for _, source in ipairs(Model.SHOPPING_SOURCES) do
		list[source] = {}
	end
	for itemID, count in pairs(needed) do
		if count > 0 then
			local source = sourceOf(itemID)
			local bucket = list[source and BUCKET[source] or "unknown"]
			bucket[#bucket + 1] = { itemID = itemID, count = count }
		end
	end
	for _, bucket in pairs(list) do
		table.sort(bucket, function(a, b)
			return a.itemID < b.itemID
		end)
	end
	return list
end

-- Raw items, already totalled, into the shopping list's buckets.
---@param items {itemID: integer, count: number}[]
---@param sourceOf fun(itemID: integer): SkillUpPriceSource?
---@return table<string, SkillUpShoppingItem[]>
function Model.BucketItems(items, sourceOf)
	local needed = {}
	for _, item in ipairs(items) do
		if item.itemID then
			needed[item.itemID] = (needed[item.itemID] or 0) + item.count
		end
	end
	return Model.BucketNeeded(needed, sourceOf)
end

---@param recipeData table<integer, SkillUpRecipe>
---@return table<integer, integer[]>
function Model.BuildReagentIndex(recipeData)
	local index = {}
	for recipeID, recipe in pairs(recipeData) do
		local seen = {}
		for _, reagent in ipairs(recipe.reagents) do
			local itemID = reagent.itemID
			if not seen[itemID] then
				index[itemID] = index[itemID] or {}
				local recipes = index[itemID]
				recipes[#recipes + 1] = recipeID
				seen[itemID] = true
			end
		end
	end
	for _, recipes in pairs(index) do
		table.sort(recipes)
	end
	return index
end

-- Rounds so a row stays short: whole gold from 100g (123g), else whole silver from
-- 1s (1g 23s, 45s), else copper (80c).
---@param copper number
---@return number
function Model.RoundMoney(copper)
	if copper == 0 then
		return 0
	end
	local unit = copper >= 1000000 and 10000 or copper >= 100 and 100 or 1
	return math.max(math.floor(copper / unit + 0.5), 1) * unit
end
