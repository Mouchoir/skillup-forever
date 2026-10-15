-- Run from the repository root: luajit tests/bench.lua
-- Measures the addon inside the headless harness the specs use: what each file SkillUpForever.toc lists
-- costs to load, what login and init do, and what each event, timer and hot lookup costs to run. Every
-- number is CPU time from os.clock, printed per call. Nothing here asserts; it is a measuring stick.
local Client = dofile("tests/client.lua")

-- The harness loads each file and gives it the stub environment with setfenv; the wrappers forward that
-- environment to the real chunk and time its execution.
local realLoadfile, realSetfenv = loadfile, setfenv
local envOf = setmetatable({}, { __mode = "k" })
rawset(_G, "setfenv", function(fn, env)
	envOf[fn] = env
	return realSetfenv(fn, env)
end)
local fileTimes, fileCompile, fileOrder = {}, {}, {}
rawset(_G, "loadfile", function(path)
	local compileStarted = os.clock()
	local chunk, err = realLoadfile(path)
	fileCompile[path] = os.clock() - compileStarted
	if not chunk then
		return chunk, err
	end
	local wrapper
	wrapper = function(...)
		local env = envOf[wrapper]
		if env then
			realSetfenv(chunk, env)
		end
		local started = os.clock()
		local a, b, d, e, f, g, h, i = chunk(...)
		local cost = os.clock() - started
		fileTimes[path] = (fileTimes[path] or 0) + cost
		fileOrder[#fileOrder + 1] = path
		return a, b, d, e, f, g, h, i
	end
	return wrapper
end)

local function report(label, iterations, fn)
	collectgarbage("collect")
	collectgarbage("collect")
	local started = os.clock()
	for index = 1, iterations do
		fn(index)
	end
	local total = os.clock() - started
	print(
		string.format(
			"%-52s %10.4f ms/call  %9.2f ms total  x%d",
			label,
			total * 1000 / iterations,
			total * 1000,
			iterations
		)
	)
	return total
end

-- A character with one open profession that knows every recipe of it, so a plan has real work.
local c = Client.load({ boot = false })
local ns = c.ns

-- The client surfaces the harness does not stub for the tooltip path, and a hook that captures the item
-- tooltip post-call the addon registers.
local noop = function() end
local tooltipPostCall
c.G.TooltipDataProcessor = {
	AddTooltipPostCall = function(kind, fn)
		if kind == c.G.Enum.TooltipDataType.Item then
			tooltipPostCall = fn
		end
	end,
}
c.G.GameTooltip = {
	IsForbidden = function()
		return false
	end,
	SetOwner = noop,
	AddDoubleLine = noop,
	Show = noop,
}
c.G.GameTooltip_AddBlankLineToTooltip = noop
c.G.GameTooltip_AddNormalLine = noop
c.G.GameTooltip_AddDisabledLine = noop
c.G.GameTooltip_AddColoredLine = noop
c.G.GameTooltip_SetTitle = noop
c.G.GameTooltip_InsertFrame = noop
c.G.IsShiftKeyDown = function()
	return false
end

local LW, MAX = 165, 300
local lwids = {}
for recipeID, recipe in pairs(ns.RecipeData) do
	if recipe.skillLine == LW then
		lwids[#lwids + 1] = recipeID
	end
end
table.sort(lwids)
for _, recipeID in ipairs(lwids) do
	c.known[recipeID] = true
end
c.professions = { { name = "Leatherworking", icon = 136247, rank = 200, max = MAX, id = 8165, modifier = 0 } }
for itemID in pairs(ns.ItemSellPrices) do
	c.items[itemID] = { name = "Item " .. itemID, sell = ns.ItemSellPrices[itemID] }
end

print("== file load (execution of each TOC file, before SavedVariables) ==")
local bootStarted = os.clock()
c.Boot()
local bootTime = os.clock() - bootStarted
local compileTotal, runTotal = 0, 0
for _, path in ipairs(fileOrder) do
	compileTotal = compileTotal + fileCompile[path]
	runTotal = runTotal + fileTimes[path]
	print(
		string.format("%-46s compile %8.4f ms   run %8.4f ms", path, fileCompile[path] * 1000, fileTimes[path] * 1000)
	)
end
print(string.format("%-46s compile %8.4f ms   run %8.4f ms", "ALL TOC files", compileTotal * 1000, runTotal * 1000))
print(string.format("%-52s %10.4f ms", "Boot (ADDON_LOADED init, first time)", bootTime * 1000))

local lw = ns.PlayerProfessions()[LW]

print("== first ask for what the load path does not build ==")
local reagentIndexCold = report("ns.UsedIn (builds the reagent index)", 1, function()
	ns.UsedIn(2318)
end)
local planCold = 0
for _ = 1, 5 do
	ns.Changed("recipes")
	planCold = planCold + report("PlanRoute (rebuilt after recipes change)", 1, function()
		ns.PlanRoute(lw)
	end)
end
local apiCold = 0
for _ = 1, 5 do
	ns.Changed("bags")
	apiCold = apiCold + report("API.Professions (rebuilt)", 1, function()
		c.G.SkillUpForever.API.Professions()
	end)
end

print("== event handlers (fired through the shared Changes frame) ==")
-- The open profession's whole recipe list, as a list update hands it over.
c.G.C_TradeSkillUI.GetAllRecipeIDs = function()
	return lwids
end
c.G.C_TradeSkillUI.GetRecipeInfo = function()
	return { learned = true }
end
-- A merchant with a stack of a reagent the plan uses, so RecordMerchant and the buy button work.
c.merchant = { { itemID = 2318, price = 200, stackCount = 5 } }
c.npc = { id = 1234, name = "Trader" }
ns.SetTracked(LW, true)

for _, case in ipairs({
	{ "TRADE_SKILL_LIST_UPDATE", 200 },
	{ "BAG_UPDATE_DELAYED", 200 },
	{ "SKILL_LINES_CHANGED", 200 },
	{ "MODIFIER_STATE_CHANGED", 5000 },
	{ "TOOLTIP_DATA_UPDATE", 5000 },
	{ "MERCHANT_UPDATE", 200 },
	{ "MERCHANT_SHOW", 200 },
	{ "PLAYER_LEVEL_UP", 200 },
	{ "ZONE_CHANGED_NEW_AREA", 200 },
	{ "ITEM_DATA_LOAD_RESULT", 200 },
	{ "NEW_RECIPE_LEARNED", 200 },
}) do
	report("fire " .. case[1], case[2], function()
		c.Fire(case[1])
	end)
end

print("== event burst ==")
-- A synthetic burst with a merchant open and a tracked profession, followed by deferred timers.
-- This combines work across timer advances; it is not a measurement of a rendered game frame.
local function eventBurst()
	c.Fire("TRADE_SKILL_LIST_UPDATE")
	c.Fire("SKILL_LINES_CHANGED")
	c.Fire("NEW_RECIPE_LEARNED")
	c.Fire("BAG_UPDATE_DELAYED")
	c.Advance(0)
	c.Advance(0.2)
end
report("events + deferred work", 500, eventBurst)

print("== interaction paths (tracker and tooltip) ==")
report("ns.TrackedNeeds (one tracked profession)", 500, function()
	ns.TrackedNeeds()
end)
report("tracker LayoutContents (marks dirty)", 500, function()
	c.Tracker()
end)
if tooltipPostCall then
	report("item tooltip post-call (reagent, route mode)", 5000, function()
		tooltipPostCall(c.G.GameTooltip, { id = 2318 })
	end)
end

print("== hot lookups ==")
report("ns.IsLearned (learned recipe)", 200000, function()
	ns.IsLearned(lwids[1])
end)
report("ns.PlayerProfessions", 100000, function()
	ns.PlayerProfessions()
end)
report("ns.Price (cached)", 200000, function()
	ns.Price(2318)
end)
report("ns.CraftCost (cached recipe)", 20000, function()
	ns.CraftCost(lwids[1])
end)
report("ns.UsedIn (warm index)", 200000, function()
	ns.UsedIn(2318)
end)
report("ns.PlanRoute (cached)", 200000, function()
	ns.PlanRoute(lw)
end)
report("API.Professions (cached)", 200000, function()
	c.G.SkillUpForever.API.Professions()
end)

local builtPlan = ns.PlanRoute(lw)
report("ns.RouteReagents", 5000, function()
	ns.RouteReagents(builtPlan)
end)

print(string.format("COLD used-in index: %.4f ms", reagentIndexCold * 1000))
print(string.format("COLD plan rebuild avg: %.4f ms", planCold * 1000 / 5))
print(string.format("COLD API rebuild avg: %.4f ms", apiCold * 1000 / 5))
