---@type string, SkillUpNamespace
local _, ns = ...
local L = ns.L

-- SkillUpForever.API, version 1: each profession's next steps, recipes and reagents,
-- read from the same levelling plan the route tab shows, for other addons to draw.
-- Built once and kept until Core/Changes.lua says it is stale.

local MAX_STEPS = 3
local MAX_RECIPES = 5
-- Earlier first: what can be done with what's in the bags beats a trip.
local KIND_ORDER = { craft = 1, buy = 2, gather = 3, train = 4 }

---@type SkillUpAPIProfession[]?
local cache
-- [skill line][step index] = picks the step's NPC by travel time, for Navigate.
---@type table<integer, table<integer, fun(): integer?>>
local pickers = {}
local namesPending = false

ns.WhenStale("api", function()
	namesPending = false
	cache = nil
end)

---@param copper number
---@return string
local function Money(copper)
	return ns.FormatNet(ns.Model.RoundMoney(copper), false)
end

---@param itemID integer
---@return string
local function ItemName(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if name then
		return name
	end
	namesPending = true
	C_Item.RequestLoadItemDataByID(itemID)
	return string.format(L["item %d"], itemID)
end

---@param recipeID integer
---@return integer?
local function OutputItem(recipeID)
	local recipe = ns.RecipeData[recipeID]
	return recipe and recipe.output and recipe.output.itemID or nil
end

-- "Name, Zone · fee", or the fallback when there is no NPC to name.
---@param npcID integer?
---@param fallback string
---@param copper number?
---@return string
local function Detail(npcID, fallback, copper)
	local text = fallback
	if npcID then
		local where = ns.NPCLocation(npcID)
		text = where.name .. ", " .. where.label
	end
	if copper and copper > 0 then
		text = text .. " · " .. Money(copper)
	end
	return text
end

-- [itemID] = recipes that make it, from the bundled data.
---@type table<integer, integer[]>?
local makers

---@param itemID integer
---@return boolean
local function CanCraft(itemID)
	if not makers then
		makers = {}
		for recipeID in pairs(ns.RecipeData) do
			local output = OutputItem(recipeID)
			if output then
				makers[output] = makers[output] or {}
				table.insert(makers[output], recipeID)
			end
		end
	end
	for _, recipeID in ipairs(makers[itemID] or {}) do
		if ns.IsLearned(recipeID) then
			return true
		end
	end
	return false
end

---@param item SkillUpNeededItem
---@return SkillUpAPIReagentSource?
local function ReagentSource(item)
	if item.source == "gather" then
		return "gather"
	elseif item.source == "vendor" then
		return "vendor"
	elseif CanCraft(item.itemID) then
		return "craft"
	elseif item.source == "auction" then
		return "auction"
	end
end

-- Getting `count` more of a reagent, the way its price says it is got.
---@param itemID integer
---@param count number
---@return SkillUpAPIStep
---@return (fun(): integer?)?
local function Acquire(itemID, count)
	local name = ItemName(itemID)
	local price = ns.Price(itemID)
	if price and price.source == "gather" then
		return {
			kind = "gather",
			text = string.format(L["Gather %d %s"], count, name),
			detail = price.profession,
			itemID = itemID,
			count = count,
			nav = false,
		}
	end
	local cost = price and price.copper * count
	local step = {
		kind = "buy",
		text = string.format(L["Buy %d %s"], count, name),
		itemID = itemID,
		count = count,
		cost = cost,
		nav = false,
	}
	if price and price.source == "vendor" then
		local vendor = ns.NearestVendor(itemID)
		step.detail, step.nav = Detail(vendor, L["Vendor"], cost), vendor ~= nil
		return step, vendor and function()
			return ns.NearestVendor(itemID, true)
		end or nil
	elseif price then
		step.detail = Detail(nil, L["Auction house"], cost)
	end
	return step
end

---@param profession SkillUpProfession
---@param text string
---@param cap number
---@param fee number
---@return SkillUpAPIStep
---@return (fun(): integer?)?
local function Train(profession, text, cap, fee)
	local trainer = ns.NearestTrainer(profession, cap)
	local step = {
		kind = "train",
		text = text,
		detail = Detail(trainer, string.format(L["%s trainer"], profession.name), fee),
		cost = fee > 0 and fee or nil,
		nav = trainer ~= nil,
	}
	return step, trainer and function()
		return ns.NearestTrainer(profession, cap, true)
	end or nil
end

-- The route's first few steps, each craft preceded by getting what the bags lack for it.
---@param plan SkillUpPlan
---@return SkillUpAPIStep[]
---@return table<integer, fun(): integer?>
local function Steps(plan)
	local profession = plan.profession
	local steps, picks, held = {}, {}, {}
	---@param step SkillUpAPIStep
	---@param pick (fun(): integer?)?
	local function Add(step, pick)
		if #steps < MAX_STEPS then
			steps[#steps + 1] = step
			picks[#steps] = pick
		end
	end
	for _, walk in ipairs(plan.steps) do
		if #steps >= MAX_STEPS then
			break
		end
		local rank, training, craft, subcraft = walk.rank, walk.training, walk.craft, walk.subcraft
		if subcraft then
			local name = C_Spell.GetSpellName(subcraft.recipeID) or string.format(L["recipe %d"], subcraft.recipeID)
			Add({
				kind = "craft",
				text = string.format(L["Craft %d %s"], subcraft.crafts, name),
				detail = string.format(L["for %s"], ItemName(subcraft.itemID)),
				spellID = subcraft.recipeID,
				itemID = subcraft.itemID,
				count = subcraft.crafts,
				nav = false,
			})
		elseif rank then
			Add(Train(profession, ns.RankText(rank), rank.cap, rank.fee)) -- multi-value: the step and its picker
		elseif training then
			local name = C_Spell.GetSpellName(training.recipeID) or string.format(L["recipe %d"], training.recipeID)
			local step, pick = Train(profession, string.format(L["Train %s"], name), training.cap, training.fee)
			step.spellID, step.itemID = training.recipeID, OutputItem(training.recipeID)
			Add(step, pick)
		elseif craft then
			local recipeID = craft.recipeID
			for _, reagent in ipairs(ns.Reagents(recipeID) or {}) do
				local itemID, need = reagent.itemID, reagent.quantity * craft.crafts
				local have = held[itemID] or ns.Have(itemID)
				held[itemID] = math.max(have - need, 0)
				if have < need then
					Add(Acquire(itemID, need - have)) -- multi-value: the step and its picker
				end
			end
			local name = C_Spell.GetSpellName(recipeID) or string.format(L["recipe %d"], recipeID)
			Add({
				kind = "craft",
				text = string.format(L["Craft %d %s"], craft.crafts, name),
				detail = string.format(L["%d to %d"], craft.from, craft.to),
				spellID = recipeID,
				itemID = OutputItem(recipeID),
				count = craft.crafts,
				nav = false,
			})
		end
	end
	return steps, picks
end

---@param plan SkillUpPlan
---@return SkillUpAPIRecipe[]
local function Recipes(plan)
	local training = {}
	for _, step in ipairs(plan.training) do
		training[step.recipeID] = step
	end
	local recipes = {}
	for i = 1, math.min(#plan.crafts, MAX_RECIPES) do
		local craft = plan.crafts[i]
		local recipeID, step = craft.recipeID, training[craft.recipeID]
		recipes[i] = {
			spellID = recipeID,
			itemID = OutputItem(recipeID),
			name = C_Spell.GetSpellName(recipeID),
			count = craft.crafts,
			fromRank = craft.from,
			toRank = craft.to,
			learned = ns.IsLearned(recipeID) == true,
			color = craft.color,
			trainAt = step and step.usedAt,
			cost = step and step.fee,
		}
	end
	return recipes
end

---@param plan SkillUpPlan
---@return SkillUpAPIReagent[]
local function Reagents(plan)
	local reagents = {}
	for _, item in ipairs(ns.RouteReagents(plan)) do
		reagents[#reagents + 1] =
			{ itemID = item.itemID, need = item.need, have = ns.Have(item.itemID), source = ReagentSource(item) }
	end
	return reagents
end

---@param entry SkillUpAPIProfession
---@return number
local function Urgency(entry)
	local first = entry.steps[1]
	return first and KIND_ORDER[first.kind] or 5
end

---@return SkillUpAPIProfession[]
local function Build()
	local entries, urgency = {}, {}
	pickers = {}
	for skillLine, profession in pairs(ns.RouteProfessions()) do
		local plan = ns.PlanRoute(profession)
		local steps, picks = Steps(plan)
		pickers[skillLine] = picks
		local entry = {
			name = profession.name,
			skillLineID = skillLine,
			icon = profession.icon,
			rank = profession.base,
			maxRank = profession.max,
			title = ns.RankName(profession.max),
			steps = steps,
			recipes = Recipes(plan),
			reagents = Reagents(plan),
		}
		entries[#entries + 1] = entry
		urgency[entry] = { #steps > 0 and 0 or 1, ns.IsTracked(skillLine) and 0 or 1, Urgency(entry) }
	end
	-- Something to do first, then what the player tracks, then the nearest to doing.
	table.sort(entries, function(a, b)
		local ua, ub = urgency[a], urgency[b]
		for i = 1, #ua do
			if ua[i] ~= ub[i] then
				return ua[i] < ub[i]
			end
		end
		return a.name < b.name
	end)
	return entries
end

---@class SkillUpPublicAPI
local API = { version = 1 }

---@return SkillUpAPIProfession[]
function API.Professions()
	if not ns.db then
		return {}
	end
	if not cache then
		cache = Build()
	end
	return cache
end

---@param skillLineID integer
---@param stepIndex integer
---@return boolean
function API.Navigate(skillLineID, stepIndex)
	API.Professions()
	local pick = pickers[skillLineID] and pickers[skillLineID][stepIndex]
	local npcID = pick and pick()
	return npcID ~= nil and ns.SetWaypoint(npcID)
end

-- The profession's window, where SkillUp's recipe colours and route tab are.
---@param skillLineID integer
---@return boolean
function API.OpenRecipes(skillLineID)
	local profession = ns.db and ns.RouteProfessions()[skillLineID]
	if not profession then
		return false
	end
	-- Forever's own profession ID opens it; the classic skill line is the fallback, asked only when it is
	-- another ID: the same one again would just repeat a request the client has refused.
	local id = profession.professionID
	if id and C_TradeSkillUI.OpenTradeSkill(id) then
		return true
	end
	return id ~= skillLineID and C_TradeSkillUI.OpenTradeSkill(skillLineID) == true
end

---@type SkillUpPublicAddon
SkillUpForever = { API = API }

ns.WhenEvent("ITEM_DATA_LOAD_RESULT", function()
	return namesPending and "names" or nil
end)
