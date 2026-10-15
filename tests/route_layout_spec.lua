-- Run from the repository root: luajit tests/route_layout_spec.lua
-- The route and gear pages at their real window size: the rectangles their controls, headings and rows
-- occupy, the width a reagent name gets, and the side tabs handing the window from one page to the other.
-- Frames resolve their anchors in screen pixels, as tracker_geometry_spec does; a name or an icon that
-- would reach outside its region is the bug this guards.
local Client = dofile("tests/client.lua")
local equal = Client.equal

-- Friz Quadrata at 12px, the widths the client draws for GameFontNormal and GameFontHighlight; anything not
-- listed is measured at a flat rate. The reagent names are the ones the rows in this spec carry.
local WIDTH = {
	["Buy reagents"] = 73,
	["Route"] = 33,
	["Reagents  (have / need)"] = 133,
	["Light Leather"] = 74,
	["Coarse Thread"] = 81,
	["Simple Wood"] = 76,
	["Latest Auctionator prices: rescan to update old prices."] = 271,
}
local function TextWidth(text)
	return WIDTH[text] or #text * 7
end

local function noop() end
local created, insets, tabs, pageFrame = {}, {}, {}, nil

-- Where a point sits inside a region: its own fraction of the region's width and height.
local function Fraction(point)
	local x = point:find("LEFT", 1, true) and 0 or point:find("RIGHT", 1, true) and 1 or 0.5
	local y = point:find("BOTTOM", 1, true) and 0 or point:find("TOP", 1, true) and 1 or 0.5
	return x, y
end

-- A region's rect in screen pixels: left, bottom, right, top. Anchors resolve against their relative
-- region; a frame on the scroll view stretches to its scroll box, as the client does.
local function Rect(frame, seen)
	if not frame then
		return 0, 0, 0, 0
	end
	if frame.allPoints then
		return Rect(frame.allPoints, seen)
	end
	if frame.scrollable and #frame.points == 0 and frame.parent then
		return Rect(frame.parent, seen)
	end
	if #frame.points == 0 then
		return 0, 0, frame.width or 0, frame.height or 0
	end
	seen = seen or {}
	assert(not seen[frame], "anchor dependency cycle")
	seen[frame] = true
	local left, right, bottom, top, hx, hy
	for _, anchor in ipairs(frame.points) do
		local rl, rb, rr, rt = Rect(anchor.relative, seen)
		local rx, ry = Fraction(anchor.relativePoint)
		local ax = rl + rx * (rr - rl) + anchor.x
		local ay = rb + ry * (rt - rb) + anchor.y
		local fx, fy = Fraction(anchor.point)
		if fx == 0 then
			left = ax
		elseif fx == 1 then
			right = ax
		else
			hx = ax
		end
		if fy == 0 then
			bottom = ay
		elseif fy == 1 then
			top = ay
		else
			hy = ay
		end
	end
	seen[frame] = nil
	local text = frame.text and TextWidth(frame.text) or 0
	if not (left and right) then
		if left then
			right = left + (frame.width or text)
		elseif right then
			left = right - (frame.width or text)
		elseif hx then
			left, right = hx - (frame.width or 0) / 2, hx + (frame.width or 0) / 2
		else
			left, right = 0, frame.width or 0
		end
	end
	if not (bottom and top) then
		if bottom then
			top = bottom + (frame.height or 12)
		elseif top then
			bottom = top - (frame.height or 12)
		elseif hy then
			bottom, top = hy - (frame.height or 12) / 2, hy + (frame.height or 12) / 2
		else
			bottom, top = 0, frame.height or 12
		end
	end
	return left, bottom, right, top
end

local function Width(region)
	local left, _, right = Rect(region)
	return right - left
end

-- Two rects intersect when they overlap on both axes; touching edges do not count.
local function overlaps(a, b)
	local al, ab, ar, at = Rect(a)
	local bl, bb, br, bt = Rect(b)
	return al < br and bl < ar and ab < bt and bb < at
end

local function NewRegion(parent)
	local region = { parent = parent, points = {}, scripts = {}, shown = true, enabled = true }
	function region:SetPoint(...)
		local args = { ... }
		local point = args[1]
		local relative, relativePoint, x, y
		if type(args[2]) == "table" then
			relative, relativePoint, x, y = args[2], args[3], args[4], args[5]
		else
			relative, relativePoint, x, y = parent, point, args[2], args[3]
		end
		self.points[#self.points + 1] =
			{ point = point, relative = relative, relativePoint = relativePoint, x = x or 0, y = y or 0 }
	end
	function region:ClearAllPoints()
		self.points = {}
	end
	function region:SetAllPoints(target)
		self.allPoints = target
	end
	function region:SetSize(width, height)
		self.width, self.height = width, height
	end
	function region:SetWidth(width)
		self.width = width
	end
	function region:SetHeight(height)
		self.height = height
	end
	function region:GetWidth()
		return Width(self)
	end
	function region:GetHeight()
		local _, bottom, _, top = Rect(self)
		return top - bottom
	end
	function region:SetText(text)
		self.text = text
	end
	function region:GetTextWidth()
		return TextWidth(self.text or "")
	end
	function region:GetStringWidth()
		return TextWidth(self.text or "")
	end
	function region.GetStringHeight()
		return 12
	end
	function region:SetShown(shown)
		self.shown = shown and true or false
	end
	function region:Show()
		self.shown = true
		if self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
	function region:Hide()
		self.shown = false
	end
	function region:IsShown()
		return self.shown
	end
	function region:IsVisible()
		return self.shown
	end
	function region:SetEnabled(enabled)
		self.enabled = enabled and true or false
	end
	function region:IsEnabled()
		return self.enabled
	end
	function region:Enable()
		self.enabled = true
	end
	function region:Disable()
		self.enabled = false
	end
	function region:SetChecked(checked)
		self.checked = checked
	end
	function region:GetChecked()
		return self.checked
	end
	function region:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function region:HookScript(name, fn)
		local previous = self.scripts[name]
		self.scripts[name] = previous and function(...)
			previous(...)
			fn(...)
		end or fn
	end
	function region:RegisterEvent(event)
		self.events = self.events or {}
		self.events[event] = true
	end
	function region:CreateFontString()
		local font = NewRegion(self)
		font.height = 12
		created[#created + 1] = font
		return font
	end
	function region:CreateTexture()
		local texture = NewRegion(self)
		created[#created + 1] = texture
		return texture
	end
	function region:SetCustomOnMouseUpHandler(fn)
		self.scripts.OnMouseUp = fn
	end
	function region:GetPortrait()
		return self.portrait
	end
	function region.GetEffectiveScale()
		return 1
	end
	function region.GetFrameLevel()
		return 1
	end
	function region.HasFocus()
		return false
	end
	function region:Click()
		if self.scripts.OnClick then
			self.scripts.OnClick(self)
		end
	end
	created[#created + 1] = region
	return setmetatable(region, {
		__index = function(_, key)
			if type(key) == "string" and key:match("^%u") then
				return noop
			end
			return nil
		end,
	})
end

local ProfessionsFrame = NewRegion(nil)
ProfessionsFrame.CraftingPage = NewRegion(ProfessionsFrame)
ProfessionsFrame.CraftingPage.width, ProfessionsFrame.CraftingPage.height = 673, 594
ProfessionsFrame.BookPage = NewRegion(ProfessionsFrame)
ProfessionsFrame.ProfessionsOverviewTab = NewRegion(ProfessionsFrame)
ProfessionsFrame.rightProfessionTabs = {}
ProfessionsFrame.portrait = NewRegion(ProfessionsFrame)
ProfessionsFrame.portrait:SetPoint("TOPLEFT", 0, 0)
ProfessionsFrame.portrait:SetSize(64, 64)
-- PortraitFrameTemplate's title band: the window's content starts at -21, so nothing a page draws may
-- reach into it or over the portrait that overhangs the top-left corner.
local titleBar = NewRegion(ProfessionsFrame)
titleBar:SetPoint("TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", 0, 0)
titleBar:SetHeight(21)

local function CreateFrame(_, _, parent, template)
	local region = NewRegion(parent)
	region.template = template
	if template == "LargeSideTabButtonTemplate" then
		region.Icon = NewRegion(region)
		tabs[#tabs + 1] = region
	elseif template == "InsetFrameTemplate" then
		insets[#insets + 1] = region
	elseif template == "UICheckButtonTemplate" then
		region.width, region.height = 26, 26
	elseif parent == ProfessionsFrame and template == nil then
		pageFrame = region
	end
	return region
end

-- The scroll box list, as this spec needs it: the view draws a frame for an element through its element
-- factory, at the extent it gives that element, and the scroll box stacks them as the client does.
local function CreateScrollBoxListLinearView()
	local view = NewRegion(nil)
	function view:SetElementExtentCalculator(calculator)
		self.extent = calculator
	end
	function view:SetElementFactory(factory)
		self.factory = factory
	end
	return view
end

local function InitScrollBoxList(scrollBox, _, view)
	function scrollBox:SetDataProvider(provider)
		local offset = 0
		for _, elementData in ipairs(provider.elements) do
			local template, initializer
			view.factory(function(name, init)
				template, initializer = name, init
			end, elementData)
			local frame = CreateFrame(nil, nil, self, template)
			initializer(frame, elementData)
			local height = view.extent(nil, elementData)
			frame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -offset)
			frame:SetPoint("RIGHT", self, "RIGHT")
			frame:SetHeight(height)
			offset = offset + height
			self.frames = self.frames or {}
			self.frames[#self.frames + 1] = frame
		end
	end
end

local function Color()
	return {
		GetRGB = noop,
		WrapTextInColorCode = function(_, text)
			return text
		end,
	}
end

local timers = {}
local waypoints, opened, showAll = {}, {}, false
local reagents = {
	{ itemID = 1, need = 50, source = "gather" },
	{ itemID = 2, need = 20, source = "vendor" },
	{ itemID = 3, need = 10, source = "vendor" },
}
local plan = {
	target = 100,
	crafts = { { recipeID = 3275, crafts = 5, from = 1, to = 5, color = "green" } },
	steps = {
		-- The sub-craft that makes the craft's reagent, as its own row before the craft.
		{ subcraft = { recipeID = 3276, itemID = 2, crafts = 5, made = 5 } },
		{ craft = { recipeID = 3275, crafts = 5, from = 1, to = 5, color = "green" } },
	},
	ranks = {},
	cost = 0,
	unpriced = 0,
}

local function FirstAid(skill)
	return { skillLine = 129, name = "First Aid", icon = 135966, skill = skill, base = skill, max = 75, modifier = 0 }
end

local ns = {
	L = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	db = { routeTargets = { [129] = 100 }, showRouteTab = true },
	COLORS = setmetatable({}, {
		__index = Color,
	}),
	GatheredBy = {},
	FormatNet = function(copper)
		return tostring(copper)
	end,
	NetCost = function()
		return 10
	end,
	Have = function()
		return 0
	end,
	IsLearned = function()
		return true
	end,
	IsTracked = function()
		return false
	end,
	SetTracked = noop,
	SkippedRecipes = function()
		return {}
	end,
	HasAuctionator = function()
		return true
	end,
	AuctionatorAutoscan = function()
		return nil
	end,
	AuctionListName = function(profession)
		return "SkillUp: " .. profession
	end,
	ShowRecipe = noop,
	TrackerAttached = function()
		return true
	end,
	CollectMode = function()
		return "gather"
	end,
	SetCollectMode = noop,
	ShowAllGear = function()
		return showAll
	end,
	SetShowAllGear = function(show)
		showAll = show and true or false
	end,
	PlayerProfessions = function()
		return { [129] = FirstAid(1) }
	end,
	ProfessionSkillLine = function(_, reported)
		return reported
	end,
	RouteProfessions = function()
		return { [129] = FirstAid(48) }
	end,
	PlanRoute = function(profession)
		plan.profession = profession
		return plan
	end,
	RouteReagents = function()
		return reagents
	end,
	UnpricedReagents = function()
		return {}
	end,
	NextCraft = function()
		return { text = "Craft next", reason = "Nothing to craft on this route." }
	end,
	RouteBlocked = function()
		return nil
	end,
	RankText = function()
		return "Rank"
	end,
	Price = function()
		return { copper = 10, source = "auctionator" }
	end,
	PriceAge = function()
		return 90000
	end,
	PriceAgeText = function()
		return "2d ago"
	end,
	PriceSourceText = function()
		return ""
	end,
	NearestVendor = function()
		return nil
	end,
	NearestNPC = function()
		return nil
	end,
	NearestTrainer = function()
		return nil
	end,
	SetWaypoint = function(npcID)
		waypoints[#waypoints + 1] = npcID
		return true
	end,
	RecipeNPC = function()
		return 1234
	end,
	AddNearest = noop,
	AddCompanionHint = noop,
	AddSourceLines = noop,
	SuggestionNPC = function()
		return nil
	end,
	RecipeSuggestions = function()
		return {}
	end,
	RecipeBands = function()
		return {}
	end,
	ScrollSkill = function()
		return 1
	end,
	ScrollPrice = function()
		return nil
	end,
	Catalogue = {
		Hint = function() end,
		Recipe = function()
			return nil
		end,
	},
	TrainingFor = function()
		return nil
	end,
	NPCLocation = function()
		return { name = "Somewhere" }
	end,
	Changed = noop,
	WhenStale = noop,
	WhenEvent = noop,
	Print = noop,
}

local env = setmetatable({
	-- SafeCall hands a caught error to the game's handler: here it fails the spec.
	geterrorhandler = function()
		return function(message)
			io.stderr:write("error handler: ", tostring(message), "\n")
			os.exit(1)
		end
	end,
	CreateFrame = CreateFrame,
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	hooksecurefunc = function()
		error("the route page must not hook native profession methods")
	end,
	C_Item = {
		GetItemNameByID = function(itemID)
			return ({ "Light Leather", "Coarse Thread", "Simple Wood" })[itemID]
		end,
		GetItemIconByID = function()
			return 134400
		end,
		GetItemQualityByID = function()
			return nil
		end,
		RequestLoadItemDataByID = noop,
		GetItemInfo = function() end,
	},
	C_PaperDollInfo = {
		GetInventorySlotInfo = function()
			return 0, 134400
		end,
	},
	Professions = false,
	ProfessionsFrame = ProfessionsFrame,
	C_Spell = {
		GetSpellName = function(id)
			return "Spell " .. id
		end,
		GetSpellTexture = noop,
	},
	C_TradeSkillUI = {
		GetCraftableCount = function()
			return 5
		end,
		CraftRecipe = noop,
		OpenRecipe = function(recipeID)
			opened[#opened + 1] = recipeID
		end,
		GetRecipeInfo = function() end,
	},
	GameTooltip = NewRegion(nil),
	GameTooltip_SetTitle = noop,
	GameTooltip_AddNormalLine = noop,
	GameTooltip_AddDisabledLine = noop,
	GameTooltip_AddColoredDoubleLine = noop,
	GameTooltip_AddBlankLineToTooltip = noop,
	GameTooltip_AddHighlightLine = noop,
	GameTooltip_AddInstructionLine = noop,
	GameTooltip_Hide = noop,
	NORMAL_FONT_COLOR = Color(),
	HIGHLIGHT_FONT_COLOR = Color(),
	GRAY_FONT_COLOR = Color(),
	RED_FONT_COLOR = Color(),
	CreateScrollBoxListLinearView = CreateScrollBoxListLinearView,
	CreateDataProvider = function(elements)
		return { elements = elements }
	end,
	ScrollUtil = { InitScrollBoxListWithScrollBar = InitScrollBoxList },
	ScrollBoxConstants = { RetainScrollPosition = true },
	IsModifiedClick = function()
		return false
	end,
	ChatEdit_InsertLink = noop,
	HandleModifiedItemClick = noop,
}, {
	__index = function(_, key)
		local value = _G[key]
		if value == nil then
			return noop
		end
		return value
	end,
})

for _, file in ipairs({
	"Locales/enUS.lua",
	"Data/Thresholds.lua",
	"Data/Recipes.lua",
	"Data/Trainer.lua",
	"Core/Model.lua",
	"Core/SafeCall.lua",
	"Core/Changes.lua",
	"Core/Plan.lua",
	"UI/List.lua",
	"UI/Route.lua",
	"UI/Gear.lua",
}) do
	setfenv(assert(loadfile(file)), env)("SkillUpForever", ns)
end

ns.RouteReagents = function()
	return reagents
end
ns.Reagents = function(recipeID)
	if recipeID == 2001 then
		return { { itemID = 1, quantity = 50 }, { itemID = 2, quantity = 20 } }
	end
	return {}
end
ns.PlanRoute = function(profession)
	plan.profession = profession
	return plan
end
ns.CraftedGear = function()
	local profession = FirstAid(1)
	local head = {
		{
			recipeID = 2001,
			itemID = 1001,
			name = "Known Helm",
			skillLine = 129,
			skill = 30,
			level = 20,
			profession = profession.name,
			learned = true,
			state = "known",
		},
		{
			recipeID = 2002,
			itemID = 1002,
			name = "Trainable Helm",
			skillLine = 129,
			skill = 40,
			level = 20,
			profession = profession.name,
			learned = false,
			state = "trainable",
		},
		{
			recipeID = 2003,
			itemID = 1003,
			name = "Far Helm",
			skillLine = 129,
			skill = 240,
			level = 20,
			profession = profession.name,
			learned = false,
			state = "needs",
		},
	}
	-- Every character-sheet slot is returned, as the real rule returns them, so a click on an empty
	-- slot keeps the selection.
	local slots = {}
	for index = 1, 15 do
		slots[index] = { slot = index, name = "Slot " .. index, items = index == 1 and head or {} }
	end
	return slots
end
ns.NextCraft = function()
	-- The bottom row is laid out with the craft button at its widest, so a longer label cannot reach
	-- a control beside it.
	return { text = "Craft 999× Cured Light Hide of the Bear", recipeID = 3275, count = 999, planned = 999, to = 100 }
end

ns.AttachRoute()
local tab = tabs[1]
local page = pageFrame
ns.db.showGearTab = true
ns.AttachGear()
tab.scripts.OnMouseUp(nil, "LeftButton", true)
equal(page ~= nil, true, "the route page is created")
equal(page.RouteList ~= nil and page.ReagentList ~= nil, true, "with its two lists")

local function Find(text)
	for _, region in ipairs(created) do
		if region.text == text then
			return region
		end
	end
end

local headings = { Find("Route"), Find("Reagents  (have / need)") }
equal(headings[1] ~= nil and headings[2] ~= nil, true, "the two inset headings exist")

local pageL, pageB, pageR, pageT = Rect(page)
for _, heading in ipairs(headings) do
	local left, bottom, right, top = Rect(heading)
	equal(left > pageL and right < pageR, true, heading.text .. " sits inside the page's width")
	equal(top < pageT and bottom > pageB, true, heading.text .. " sits inside the page's height")
	equal(overlaps(heading, titleBar), false, heading.text .. " misses the title bar")
	equal(overlaps(heading, ProfessionsFrame.portrait), false, heading.text .. " misses the portrait")
end

-- The switch and its label are one control in the header; Track, Craft and the vendor button share
-- the bottom row, right to left, with the craft label at its widest so no length can overlap.
local controls = {
	page.Collect,
	page.CollectLabel,
	page.Vendor,
	page.Craft,
	page.Track,
}
local names = { "the switch", "the switch's label", "the vendor button", "Craft", "Track" }

for index, control in ipairs(controls) do
	for _, heading in ipairs(headings) do
		equal(overlaps(control, heading), false, names[index] .. " misses the " .. heading.text .. " heading")
	end
	local left, bottom, right, top = Rect(control)
	equal(left > pageL and right < pageR, true, names[index] .. " sits inside the page's width")
	equal(top < pageT and bottom > pageB, true, names[index] .. " sits inside the page's height")
	equal(overlaps(control, titleBar), false, names[index] .. " misses the title bar")
	equal(overlaps(control, ProfessionsFrame.portrait), false, names[index] .. " misses the portrait")
end
for index, control in ipairs(controls) do
	equal(Width(control) > 0, true, names[index] .. " has a width to overlap with")
end
for i = 1, #controls do
	for j = i + 1, #controls do
		equal(overlaps(controls[i], controls[j]), false, names[i] .. " misses " .. names[j])
	end
end

-- The controls hang off existing regions, never off a hand-measured offset from the window top.
local switchAnchor = page.Collect.points[1]
equal(switchAnchor.relative, page.Target, "the switch hangs off the target it changes")
equal(switchAnchor.relativePoint, "RIGHT", "at the target's right, in the header")
local vendorAnchor = page.Vendor.points[1]
equal(vendorAnchor.relative, page.Craft, "the vendor button hangs off the craft it sits beside")
equal(vendorAnchor.relativePoint, "LEFT", "at the craft's left, in the bottom row")
local craftAnchor = page.Craft.points[1]
equal(craftAnchor.relative, page.Track, "the craft button hangs off the track button")
equal(craftAnchor.relativePoint, "LEFT", "at the track's left, in the bottom row")
equal(Width(page.Craft), 240, "the craft button is drawn at its widest label")

-- The list's scroll box is what the addon places; the game lays the rows out inside it, so the scroll
-- box must sit inside the inset and every row the game draws inside the scroll box.
local routeLeft, routeBottom, routeRight, routeTop = Rect(insets[1])
local boxLeft, boxBottom, boxRight, boxTop = Rect(page.RouteList.scrollBox)
equal(boxLeft >= routeLeft and boxRight <= routeRight, true, "the route list's scroll box is inside its inset")
equal(boxTop <= routeTop and boxBottom >= routeBottom, true, "and inside its height")
local routeRows = 0
for _, row in ipairs(page.RouteList.scrollBox.frames) do
	if row.kind == "row" then
		routeRows = routeRows + 1
		local left, bottom, right, top = Rect(row)
		equal(Width(row.Icon) >= 36, true, "a route row's icon is a full item icon")
		equal(left >= routeLeft and right <= routeRight, true, "the route row is inside its inset's width")
		equal(top <= routeTop and bottom >= routeBottom, true, "and inside its height")
		local textLeft, textBottom, textRight = Rect(row.Text)
		equal(textLeft > left and textRight < right, true, "the name is inside the row")
		local detailLeft, _, detailRight, detailTop = Rect(row.Detail)
		equal(detailLeft >= textLeft and detailRight <= textRight, true, "the facts line spans the name's width")
		equal(detailTop <= textBottom, true, "and sits under the name")
	end
end
equal(routeRows, 2, "the route list draws the sub-craft and the craft as rows")
equal(Find("Craft 5× Spell 3276") ~= nil, true, "the sub-craft names itself as a craft")
equal(Find("makes 5 Coarse Thread") ~= nil, true, "and says how much of the reagent it makes")

-- A reagent row is the same item row: the icon, the name and where it comes from with how many of
-- the route's need the bags hold.
local reagentLeft, reagentBottom, reagentRight, reagentTop = Rect(insets[2])
local reagentBoxLeft, reagentBoxBottom, reagentBoxRight, reagentBoxTop = Rect(page.ReagentList.scrollBox)
equal(
	reagentBoxLeft >= reagentLeft and reagentBoxRight <= reagentRight,
	true,
	"the reagent list's scroll box is inside its inset"
)
equal(reagentBoxTop <= reagentTop and reagentBoxBottom >= reagentBottom, true, "and inside its height")
local reagentRows = 0
for _, row in ipairs(page.ReagentList.scrollBox.frames) do
	if row.kind == "row" then
		reagentRows = reagentRows + 1
		local left, bottom, right, top = Rect(row)
		equal(Width(row.Icon) >= 36, true, "a reagent row's icon is a full item icon")
		equal(left >= reagentLeft and right <= reagentRight, true, "the reagent row is inside its inset's width")
		equal(top <= reagentTop and bottom >= reagentBottom, true, "and inside its height")
		equal(Width(row.Text), 183.5, "a reagent row gives its name the width the row has")
	end
end
equal(reagentRows, 3, "the reagent list draws a row a reagent")

-- The gear page is the window's other page. Its title, switch and rows all sit inside the visible
-- page, under the window's title bar and clear of its portrait, as the route page's own controls do.
local routePage, gearPage = page, pageFrame
local routeTab = tab
local gearTab = tabs[2]
local gearInset = insets[3]
local _, pageBottom, _, pageTop = Rect(page)
local insetLeft, insetBottom, insetRight, gearTop = Rect(gearInset)
equal(gearTop, 506, "the gear inset starts under the window's title bar")
equal(overlaps(gearInset, titleBar), false, "the gear inset misses the title bar")
equal(overlaps(gearInset, ProfessionsFrame.portrait), false, "and the portrait")

local title = Find("Crafted gear")
local titleLeft, titleBottom, titleRight, titleTop = Rect(title)
equal(title ~= nil, true, "the gear page has its title")
equal(overlaps(title, titleBar), false, "the title misses the title bar")
equal(overlaps(title, ProfessionsFrame.portrait), false, "and the portrait")
equal(titleTop <= pageTop and titleBottom >= pageBottom, true, "the title sits inside the page")
equal(titleLeft > insetLeft and titleRight <= insetRight, true, "over its inset width")

local switch = gearPage.ShowAll
equal(switch ~= nil and gearPage.ShowAllLabel ~= nil, true, "the gear page has its switch")
equal(Width(switch) > 0, true, "the switch has a width to overlap with")
equal(overlaps(switch, titleBar), false, "the switch misses the title bar")
equal(overlaps(switch, ProfessionsFrame.portrait), false, "and the portrait")
equal(overlaps(switch, title), false, "and the title")
equal(switch.points[1].relative, gearInset, "the switch hangs off the gear inset")

-- The gear tab shows the page and hides the route's; the first render fills the doll.
gearTab.scripts.OnMouseUp(nil, "LeftButton", true)
equal(gearPage:IsShown(), true, "the gear tab shows the gear page")
equal(routePage:IsShown(), false, "and hides the route page")
equal(gearTab.checked, true, "with the gear tab checked")
equal(routeTab.checked, false, "and the route tab unchecked")

-- The paper doll: one stock-size slot button a character-sheet slot, inside the inset, clear of the
-- title bar and portrait, and clear of each other.
local slots = gearPage.Slots
equal(#slots, 15, "the doll has a slot a character-sheet slot")
for index, slot in ipairs(slots) do
	local left, bottom, right, top = Rect(slot)
	equal(Width(slot), 37, "slot " .. index .. " is a stock-size item slot")
	equal(left > insetLeft and right < insetRight, true, "slot " .. index .. " is inside the inset's width")
	equal(top < gearTop and bottom > insetBottom, true, "slot " .. index .. " is inside its height")
	equal(overlaps(slot, titleBar), false, "slot " .. index .. " misses the title bar")
	equal(overlaps(slot, ProfessionsFrame.portrait), false, "slot " .. index .. " misses the portrait")
end
for i = 1, #slots do
	for j = i + 1, #slots do
		equal(overlaps(slots[i], slots[j]), false, "slot " .. i .. " misses slot " .. j)
	end
end

-- The pane for the selected slot: the pick's icon and name, its reagents and its one button, all
-- inside the pane and clear of the doll.
local pane = gearPage.Detail
local paneLeft, paneBottom, paneRight, paneTop = Rect(pane)
equal(pane.Body:IsShown(), true, "the pane shows a pick")
equal(pane.Empty:IsShown(), false, "and not its empty state")
for index, slot in ipairs({ slots[1], slots[7], slots[13] }) do
	equal(overlaps(slot, pane), false, "doll slot " .. index .. " misses the pane")
end
local iconLeft, iconBottom, iconRight, iconTop = Rect(pane.Icon)
equal(iconRight - iconLeft >= 36, true, "the pane's icon is a full-size item icon")
equal(iconLeft >= paneLeft and iconRight <= paneRight, true, "the pane's icon is inside the pane")
equal(iconTop <= paneTop and iconBottom >= paneBottom, true, "and inside its height")
equal(pane.Name.text ~= nil, true, "the pane names the pick")
local nameLeft, _, _, nameTop = Rect(pane.Name)
equal(nameLeft > iconRight, true, "the name sits beside the icon")
equal(nameTop <= iconTop, true, "at the icon's top")
equal(pane.ReagentRows[1] ~= nil and pane.ReagentRows[1]:IsShown(), true, "the pane draws its reagents")
equal(Width(pane.ReagentRows[1].Icon) >= 36, true, "a reagent row's icon is a full item icon")
local paneReagentLeft, _, paneReagentRight = Rect(pane.ReagentRows[1])
equal(paneReagentLeft >= paneLeft and paneReagentRight <= paneRight, true, "the reagent row is inside the pane")
equal(overlaps(pane.ReagentRows[1], pane.Action), false, "a reagent row misses the action button")
local paneActionLeft, _, paneActionRight = Rect(pane.Action)
equal(paneActionLeft >= paneLeft and paneActionRight <= paneRight, true, "the action button is inside the pane")
equal(overlaps(pane.Action, titleBar), false, "the action button misses the title bar")
equal(pane.Also:IsShown(), true, "the pane lists the slot's other items")
equal(pane.OtherRows[1] ~= nil and pane.OtherRows[1]:IsShown(), true, "with a row a remaining item")
local paneOtherLeft, _, paneOtherRight = Rect(pane.OtherRows[1])
equal(paneOtherLeft >= paneLeft and paneOtherRight <= paneRight, true, "the other item's row is inside the pane")

-- The action button: a known pick opens the recipe, a trainable one sets a waypoint to where it is
-- taught, and one out of reach is disabled with the reason why.
pane.Action:Click()
equal(opened[1], 2001, "a known pick's button opens its recipe")
pane.OtherRows[1]:Click()
equal(pane.Action.text, "Set waypoint", "a trainable pick's button names the waypoint")
pane.Action:Click()
equal(waypoints[1], 1234, "a trainable pick's button sets a waypoint to where it is learned")
pane.OtherRows[2]:Click()
equal(pane.Action:IsEnabled(), false, "a pick out of reach disables its button")
equal(pane.Action.reason ~= nil, true, "with the reason why")

-- Clicking a slot selects it and shows the stock selection highlight.
slots[2]:Click()
equal(slots[2].checked, true, "the clicked slot is checked")
equal(slots[1].checked, false, "and the first is not")

-- The switch saves the rule for the list.
switch:SetChecked(true)
switch.scripts.OnClick(switch)
equal(showAll, true, "the switch saves the choice")

routeTab.scripts.OnMouseUp(nil, "LeftButton", true)
equal(routePage:IsShown(), true, "the route tab shows the route page")
equal(gearPage:IsShown(), false, "and hides the gear page")
equal(routeTab.checked, true, "with the route tab checked")
equal(gearTab.checked, false, "and the gear tab unchecked")

gearTab.scripts.OnMouseUp(nil, "LeftButton", true)
routeTab.scripts.OnMouseUp(nil, "LeftButton", true)
equal(routePage:IsShown(), true, "a second route click shows the route page again")
equal(gearPage:IsShown(), false, "and still hides the gear page")
equal(routeTab.checked, true, "with the route tab checked")
equal(gearTab.checked, false, "and the gear tab unchecked")

-- Blizzard's own tabs hand the window back through their page showing.
ProfessionsFrame.BookPage:Show()
equal(routePage:IsShown(), false, "the overview hides the route page")
equal(gearPage:IsShown(), false, "and the gear page")
equal(routeTab.checked, false, "the route tab unchecks")
equal(gearTab.checked, false, "and the gear tab too")
ProfessionsFrame.CraftingPage:Show()
equal(routePage:IsShown(), false, "a profession page hides the route page")
equal(gearPage:IsShown(), false, "and the gear page")

Client.report("route_layout_spec")
