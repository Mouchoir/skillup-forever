-- Run from the repository root: luajit tests/route_spec.lua
-- The route page drawn from a real plan; the plan itself is plan_spec's.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local function FirstAid(skill)
	return { skillLine = 129, name = "First Aid", skill = skill, base = skill, max = 75, modifier = 0 }
end

-- The route page, drawn into stub frames: every frame method is a no-op but the
-- scripts, which run, and the lists, which record their rows.
local function Stub()
	local scripts = {}
	return setmetatable({}, {
		__index = function(self, key)
			local value
			if key == "SetScript" or key == "HookScript" then
				value = function(_, name, fn)
					local previous = key == "HookScript" and scripts[name]
					scripts[name] = previous and function(...)
						previous(...)
						fn(...)
					end or fn
				end
			elseif key == "SetChecked" then
				value = function(frame, checked)
					rawset(frame, "checked", checked)
				end
			elseif key == "SetEnabled" then
				value = function(frame, enabled)
					rawset(frame, "enabled", enabled and true or false)
				end
			elseif key == "IsEnabled" then
				value = function(frame)
					return rawget(frame, "enabled") ~= false
				end
			elseif key == "Enable" then
				value = function(frame)
					rawset(frame, "enabled", true)
				end
			elseif key == "Disable" then
				value = function(frame)
					rawset(frame, "enabled", false)
				end
			elseif key == "Enter" then
				value = function(frame)
					if scripts.OnEnter then
						scripts.OnEnter(frame)
					end
				end
			elseif key == "Event" then
				value = function(frame, event)
					scripts.OnEvent(frame, event)
				end
			elseif key == "SetCustomOnMouseUpHandler" then
				value = function(_, fn)
					scripts.OnMouseUp = fn
				end
			elseif key == "Show" then
				value = function(frame)
					rawset(frame, "shown", true)
					if scripts.OnShow then
						scripts.OnShow(frame)
					end
				end
			elseif key == "SetShown" then
				value = function(frame, shown)
					rawset(frame, "shown", shown == true)
				end
			elseif key == "IsShown" then
				value = function(frame)
					return rawget(frame, "shown") == true
				end
			elseif key == "Click" then
				value = function(frame)
					if scripts.OnClick then
						scripts.OnClick(frame)
					else
						scripts.OnMouseUp(frame, "LeftButton", true)
					end
				end
			else
				value = Stub()
			end
			rawset(self, key, value)
			return value
		end,
		__call = function()
			return Stub()
		end,
		__add = function()
			return 0
		end,
	})
end
local requested, lists = {}, {}
local page
page = {
	auctionAutoscan = nil,
	db = { trainer = {}, trainerRanks = {}, routeTargets = { [129] = 100 }, showRouteTab = true, vendor = {} },
	COLORS = {},
	IsLearned = function(id)
		return id == 3275
	end,
	NetCost = function() end,
	Reagents = function()
		return { { itemID = 2589, quantity = 1 } }
	end,
	Price = function() end,
	-- One scroll nothing prices, to carry the route on.
	RecipeSuggestions = function()
		return { { recipeID = 3276, source = { item = 6454 }, reach = 115, kindText = "vendor" } }
	end,
	ScrollPrice = function() end,
	-- No Questie or AtlasLoot: the one line saying what to install.
	Catalogue = {
		Hint = function()
			return "Install both."
		end,
	},
	PriceSource = function(itemID)
		-- A reagent another profession gathers is free while the switch is off and bought while it is on.
		if page.GatheredBy[itemID] and page.PlayerProfessions()[page.GatheredBy[itemID]] then
			return page.CollectMode() == "gather" and "gather" or "vendor"
		end
		return ({ "vendor", "vendor", "auctionator" })[itemID]
	end,
	-- One reagent per bucket, the first one this character's First Aid gathers.
	GatheredBy = { [1] = 129 },
	PlayerProfessions = function()
		return { [129] = FirstAid(1) }
	end,
	ProfessionSkillLine = function(_, reported)
		return reported
	end,
	HasAuctionator = function()
		return false
	end,
	AuctionatorAutoscan = function()
		return page.auctionAutoscan
	end,
	AuctionListName = function(profession)
		return "SkillUp: " .. profession
	end,
	IsTracked = function()
		return false
	end,
	CreateList = function()
		local list = { rows = {}, scrollBox = Stub() }
		function list:Add(row)
			self.rows[#self.rows + 1] = row
		end
		list.messages, list.Begin, list.Finish = {}, function() end, function() end
		function list:Message(text)
			self.messages[#self.messages + 1] = text
		end
		lists[#lists + 1] = list
		return list
	end,
	-- The route page hides the gear page when it takes over; this spec loads the route file alone.
	HideGear = function() end,
	-- Recipes this character said Not this recipe to: none until a spec skips one.
	SkippedRecipes = function()
		return page.skipped or {}
	end,
	SetSkipped = function(recipeID, skip)
		page.setSkipped = { recipeID, skip }
	end,
}
-- The client-side seams the page reads: a character that gathers, and no vendor named until a spec says so.
page.CollectMode = function()
	return page.collectMode or "gather"
end
page.SetCollectMode = function(mode)
	page.collectMode = mode
end
page.NearestVendor = function()
	return nil
end
page.NearestNPC = function()
	return nil
end
local timers = {}
local disabledLines = {}
local pageEnv = setmetatable({
	C_Timer = {
		After = function(_, callback)
			timers[#timers + 1] = callback
		end,
	},
	hooksecurefunc = function()
		error("route tab must not hook native profession methods")
	end,
	C_Item = {
		GetItemNameByID = function() end,
		GetItemIconByID = function() end,
		GetItemQualityByID = function() end,
		GetItemQualityColor = function() end,
		RequestLoadItemDataByID = function(id)
			requested[id] = true
		end,
	},
	Professions = false,
	ProfessionsFrame = Stub(),
	C_Spell = {
		GetSpellName = function(id)
			return "Spell " .. id
		end,
		GetSpellTexture = function() end,
	},
}, {
	__index = function(_, key)
		local value = _G[key]
		if value == nil then
			return Stub()
		end
		return value
	end,
})
pageEnv.GameTooltip_AddDisabledLine = function(_, text)
	disabledLines[#disabledLines + 1] = text
end
-- Core/Changes.lua's frame is the only one made while the files load: the game's events arrive on it.
local eventFrame
pageEnv.CreateFrame = function()
	eventFrame = Stub()
	return eventFrame
end
for _, file in ipairs({
	"Locales/enUS.lua",
	"Data/Thresholds.lua",
	"Data/Recipes.lua",
	"Data/Trainer.lua",
	"Core/Model.lua",
	"Core/Changes.lua",
	"Core/Plan.lua",
	"UI/Route.lua",
}) do
	setfenv(assert(loadfile(file)), pageEnv)("SkillUpForever", page)
end
local tabs = {}
local collect, vendor, buttons = nil, nil, {}
pageEnv.CreateFrame = function(_, _, _, template)
	local frame = Stub()
	tabs[#tabs + 1] = frame
	if template == "UICheckButtonTemplate" then
		collect = frame
	elseif template == "UIPanelButtonTemplate" then
		vendor = frame
		buttons[#buttons + 1] = frame
	end
	return frame
end
-- Opening a profession's window asks to track it: the route event defers the ask to the open profession.
local asked = {}
page.AutoTrack = function(skillLine)
	asked[#asked + 1] = skillLine
end
pageEnv.ProfessionsFrame:Show()
pageEnv.Professions = {
	GetProfessionInfo = function()
		return { professionName = "First Aid", professionID = 129 }
	end,
}
page.AttachRoute()
local routeTab = tabs[#tabs] -- the side tab, the last frame the page creates
routeTab:Click()
local reagentList = lists[2]
equal(reagentList.rows[1] and reagentList.rows[1].text, "item 2589", "an unpriced reagent is listed")
equal(requested[2589], true, "and its name is asked for")
-- A route with nothing this character gathers cannot be switched to buying, so it is off and says why.
equal(collect.enabled, false, "a route with nothing to gather disables the switch")
collect:Click()
equal(page.collectMode, nil, "and a click on the disabled switch changes nothing")
collect:Enter()
equal(
	disabledLines[#disabledLines],
	"Nothing on this route is yours to gather, so the switch changes nothing for it.",
	"the disabled switch's tooltip says why"
)
equal(routeTab.checked, true, "opening the route selects its tab")
eventFrame:Event("SKILL_LINES_CHANGED")
routeTab:SetChecked(false) -- Blizzard handles the same event after the addon.
for _, callback in ipairs(timers) do
	callback()
end
equal(routeTab.checked, true, "deferred skill update restores the visible route tab")

for index = #timers, 1, -1 do
	timers[index] = nil
end
asked = {}
eventFrame:Event("TRADE_SKILL_SHOW")
for _, callback in ipairs(timers) do
	callback()
end
equal(asked[#asked], 129, "opening First Aid's window asks to track it")
pageEnv.Professions = false

-- With only Linen Bandage priced, the route runs out and suggests a scroll nothing prices.
page.NetCost = function(recipeID)
	return recipeID == 3275 and 10 or nil
end
page.FormatNet = function(copper)
	return tostring(copper)
end
-- And one reagent from every shopping bucket, each labelled with where it comes from.
page.Reagents = function()
	local reagents = {}
	for index in ipairs(page.Model.SHOPPING_SOURCES) do
		reagents[index] = { itemID = index, quantity = 1 }
	end
	return reagents
end
page.Have = function()
	return 0
end
page.Changed("prices")
routeTab:Click()
local routeList = lists[#lists - 1]
local suggestion = routeList.rows[#routeList.rows]
equal(suggestion and suggestion.detail:find("?", 1, true) ~= nil, true, "an unpriced scroll shows ?")
equal(suggestion.text, "Spell 3276", "a suggested scroll's row is named for its recipe alone")
equal(suggestion.detail:find("vendor", 1, true), 1, "with where it comes from on the line under the name")
equal(
	table.concat(routeList.messages, " | "):find("Install both.", 1, true) ~= nil,
	true,
	"where the route stops, a missing provider is named"
)
local labels = {}
for _, row in ipairs(lists[#lists].rows) do
	labels[row.text] = row.detail
end
for index, source in ipairs(page.Model.SHOPPING_SOURCES) do
	equal(type(labels["item " .. index]), "string", source .. " is listed with a source label")
end

-- The scroll's tooltip opens with the crafted item's own, which already names it.
page.ScrollSkill = function()
	return 1
end
page.RecipeBands = function()
	return {}
end
page.AddSourceLines, page.SuggestionNPC = function() end, function() end
local titles = {}
pageEnv.GameTooltip_AddNormalLine = function(_, text)
	titles[#titles + 1] = text
end
local itemTooltip = { SetItemByID = function() end }
pageEnv.C_Item.GetItemNameByID = function()
	return "Spell 3276"
end
suggestion.tooltip(itemTooltip)
equal(#titles, 0, "a recipe named as its item is does not repeat the name under the item's tooltip")
pageEnv.C_Item.GetItemNameByID = function()
	return "Heavy Linen Bandage"
end
suggestion.tooltip(itemTooltip)
equal(titles[1], "Spell 3276", "a recipe named otherwise is still named there")

-- The collect switch: gather by default, auction after a click, and back.
equal(collect.enabled, true, "a route with a reagent this character gathers enables the switch")
equal(collect.checked, false, "the switch starts on gathering")
local explained
pageEnv.GameTooltip_AddNormalLine = function(_, text)
	explained = text
end
collect:Enter()
equal(
	explained,
	"On, a reagent you could gather is priced at a vendor or the auction house; off, gathering it costs nothing.",
	"the enabled switch's tooltip explains what it does"
)
collect:Click()
equal(page.collectMode, "auction", "clicking asks for auction mode")
equal(collect.checked, true, "and the switch shows it")
collect:Click()
equal(page.collectMode, "gather", "clicking again asks for gathering")
equal(collect.checked, false, "and the switch shows that")

-- The nearest vendor of the route's missing vendor reagents, one click from the page.
local candidates, waypointed = nil, nil
page.NearestVendor = function(itemID)
	return itemID == 2 and 555 or nil
end
page.NearestNPC = function(npcIDs, byTravel)
	candidates, page.travel = npcIDs, byTravel
	return npcIDs[1]
end
page.SetWaypoint = function(npcID)
	waypointed = npcID
	return true
end
routeTab:Click()
equal(vendor.shown, true, "a missing vendor reagent shows the nearest-vendor button")
vendor:Click()
equal(page.travel, true, "the vendor is ranked by the travel integration")
equal(candidates[1], 555, "the nearest vendor of the missing reagent")
equal(waypointed, 555, "and clicking sets the waypoint to that vendor")

page.Reagents = function()
	return { { itemID = 1, quantity = 1 } }
end
routeTab:Click()
equal(vendor.shown, false, "a route with no vendor reagent hides the button")

-- A route with crafts shows the switch's effect in the source column: the gathered reagent is free while
-- the switch is off and bought once it is on.
local realPlan = page.PlanRoute
page.PlanRoute = function(profession)
	return {
		profession = profession,
		target = 100,
		crafts = { { recipeID = 3275, crafts = 5, from = 1, to = 5, color = "green" } },
		steps = {},
		ranks = {},
		cost = 0,
		unpriced = 0,
	}
end
page.Reagents = function()
	return { { itemID = 1, quantity = 1 }, { itemID = 2, quantity = 1 } }
end
pageEnv.C_Item.GetItemNameByID = function(itemID)
	return "Reagent " .. itemID
end
local before = #lists[2].rows
routeTab:Click()
local gathered = lists[2].rows[before + 1]
equal(gathered.text, "Reagent 1", "the route's reagents are listed")
equal(
	gathered.detail:find("gather", 1, true) ~= nil,
	true,
	"a reagent this character gathers shows gather while the switch is off"
)
collect:Click()
equal(
	lists[2].rows[#lists[2].rows - 1].detail:find("vendor", 1, true) ~= nil,
	true,
	"and shows its bought source once the switch is on, so the change is plain"
)
collect:Click()
equal(
	lists[2].rows[#lists[2].rows - 1].detail:find("gather", 1, true) ~= nil,
	true,
	"and gather again when the switch is off"
)
page.PlanRoute = realPlan

local function Drain()
	local count = #timers
	for index = 1, count do
		local callback = timers[index]
		if callback then
			callback()
		end
	end
	for index = 1, count do
		timers[index] = nil
	end
end

-- A bag update and a skill change both redraw the reagent have/need while the page is open.
local have = 0
page.Have = function(itemID)
	return itemID == 1 and have or 0
end
page.RouteReagents = function()
	return { { itemID = 1, need = 9, source = "auction" } }
end
routeTab:Click()
Drain()
local function LastReagentDetail()
	for index = #lists[2].rows, 1, -1 do
		local detail = lists[2].rows[index].detail
		if detail and detail:find("/9", 1, true) then
			return detail
		end
	end
end
local function LastListItem()
	return lists[2].rows[#lists[2].rows]
end
equal(LastReagentDetail(), "AH, 0/9", "the reagent list shows what the bags hold")
have = 8
eventFrame:Event("BAG_UPDATE_DELAYED")
Drain()
equal(LastReagentDetail(), "AH, 8/9", "a bag update redraws the have count")
page.RouteReagents = function()
	return { { itemID = 1, need = 9, source = "auction" }, { itemID = 2, need = 4, source = "vendor" } }
end
eventFrame:Event("SKILL_LINES_CHANGED")
Drain()
equal(LastListItem().detail, "vendor, 0/4", "a skill change redraws the plan's reagents")

-- With Auctionator's scan-on-open option known to be off, the page says where to turn it on; with
-- the option unread, it says nothing.
page.auctionAutoscan = false
lists[2].messages = {}
eventFrame:Event("BAG_UPDATE_DELAYED")
Drain()
equal(
	table.concat(lists[2].messages, " | "):find("Auctionator's scan when the auction house opens is off", 1, true)
		~= nil,
	true,
	"the page says where to turn on Auctionator's own scan"
)
page.auctionAutoscan = nil
lists[2].messages = {}
eventFrame:Event("BAG_UPDATE_DELAYED")
Drain()
equal(
	table.concat(lists[2].messages, " | "):find("Auctionator's scan", 1, true),
	nil,
	"an unread scan option says nothing"
)

-- The reagent list names the Auctionator shopping list it keeps up to date.
page.HasAuctionator = function()
	return true
end
page.collectMode = "auction"
lists[2].messages = {}
eventFrame:Event("BAG_UPDATE_DELAYED")
Drain()
equal(
	table.concat(lists[2].messages, " | "):find("Kept in the Auctionator list 'SkillUp: First Aid'.", 1, true) ~= nil,
	true,
	"the reagent list names the Auctionator list"
)
page.HasAuctionator = function()
	return false
end
page.collectMode = nil

-- A click on Craft asks for a redraw itself, so the page follows a craft even if a game event is missed.
page.NextCraft = function()
	return { recipeID = 3275, count = 3, planned = 5, to = 20, text = "Craft 3 of 5× Spell 3275" }
end
routeTab:Click()
Drain()
for index = #timers, 1, -1 do
	timers[index] = nil
end
buttons[2]:Click()
equal(#timers > 0, true, "a craft click schedules a redraw")

-- A route with crafts and an unpriced reagent is marked incomplete, and the reagent it left out is
-- still named in the reagent list.
page.PlanRoute = function(profession)
	return {
		profession = profession,
		target = 100,
		crafts = { { recipeID = 3275, crafts = 5, from = 1, to = 5, color = "green" } },
		steps = {},
		ranks = {},
		cost = 10,
		unpriced = 2,
		unpricedRecipes = { 3277, 3278 },
	}
end
page.RouteReagents = function()
	return { { itemID = 1, need = 9, source = "vendor" } }
end
page.UnpricedReagents = function()
	return { 2589 }
end
pageEnv.C_Item.GetItemNameByID = function(itemID)
	return "Reagent " .. itemID
end
routeTab:Click()
Drain()
equal(
	table.concat(lists[1].messages, " | "):find("Route incomplete: 2 recipes left out", 1, true) ~= nil,
	true,
	"a route with an unpriced reagent is marked incomplete"
)
local listed = {}
for _, row in ipairs(lists[2].rows) do
	if row.text then
		listed[row.text] = row.detail
	end
end
equal(listed["Reagent 2589"], "no price", "and the reagent it left out is listed as unpriced")

-- Not this recipe: a right-click on a step offers it, and what the route leaves out by choice is one row
-- under it, whose menu shows each recipe again.
---@return table
local function MenuRoot()
	local root = { buttons = {} }
	function root.CreateTitle(_, text)
		root.title = text
	end
	function root.CreateButton(_, text, action)
		root.buttons[#root.buttons + 1] = { text = text, action = action }
	end
	return root
end
local skipCraft = { recipeID = 3275, crafts = 5, from = 1, to = 5, color = "green" }
page.PlanRoute = function(profession)
	return {
		profession = profession,
		target = 100,
		crafts = { skipCraft },
		steps = { { craft = skipCraft } },
		ranks = {},
		cost = 50,
		unpriced = 0,
		unpricedRecipes = {},
	}
end
page.skipped = { { recipeID = 3276, name = "Heavy Linen Bandage" } }
routeTab:Click()
Drain()
local craftRow = lists[1].rows[1]
local instructions = {}
pageEnv.GameTooltip_AddInstructionLine = function(_, text)
	instructions[#instructions + 1] = text
end
craftRow.tooltip(Stub())
equal(instructions[#instructions], "Right-click if you don't want this recipe.", "a step's tooltip says how to skip it")
local craftMenu = MenuRoot()
craftRow.menu(nil, craftMenu)
equal(craftMenu.title, "Spell 3275", "a step's menu is titled with its recipe")
equal(craftMenu.buttons[1].text, "Not this recipe", "and offers Not this recipe")
craftMenu.buttons[1].action()
equal(page.setSkipped[1] == 3275 and page.setSkipped[2], true, "which skips that recipe")
local skippedRow = lists[1].rows[#lists[1].rows]
equal(skippedRow.text, "Skipped (1)", "the skipped recipes are one row under the route")
local skippedMenu = MenuRoot()
skippedRow.menu(nil, skippedMenu)
equal(skippedMenu.buttons[1].text, "Show again: Heavy Linen Bandage", "its menu shows each one again")
skippedMenu.buttons[1].action()
equal(page.setSkipped[1] == 3276 and page.setSkipped[2], false, "by unskipping it")
page.skipped = nil
routeTab:Click()
Drain()
equal(lists[1].rows[#lists[1].rows].text ~= "Skipped (1)", true, "nothing skipped, no row")

-- The page names the latest auction source and flags old prices.
page.Price = function()
	return { copper = 10, source = "auctionator" }
end
page.PriceAge = function()
	return 0
end
routeTab:Click()
Drain()
equal(
	table.concat(lists[2].messages, " | "):find("Latest Auctionator prices.", 1, true) ~= nil,
	true,
	"the reagent list names the latest price source"
)
page.PriceAge = function()
	return 90000
end
routeTab:Click()
Drain()
equal(
	table.concat(lists[2].messages, " | "):find("Latest Auctionator prices: rescan to update old prices.", 1, true)
		~= nil,
	true,
	"an old price asks for a rescan"
)

Client.report("route_spec")
