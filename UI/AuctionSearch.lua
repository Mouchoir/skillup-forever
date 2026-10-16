---@type string, SkillUpNamespace
local _, ns = ...
local L = ns.L

-- At the auction house, the Professions window's selected recipe gets a bar: how many to craft, and a search for
-- what its reagents still lack for that many (#142). It only searches; buying stays the player's.

local CALLER = "SkillUp Forever"
-- The one Auctionator list this writes, replaced on every search.
local CRAFT_LIST = ns.AuctionListName("crafting")
-- Where a reagent's price comes from, as the route's shopping list groups it: only the auction house's and the
-- unpriced are searched there, as with the route's own Auctionator list.
local AUCTION_SOURCES = { auctionator = true }

-- How many of a recipe to search reagents for: the crafts the route plans for it, else one.
---@param recipeID integer
---@return integer
function ns.PlannedCrafts(recipeID)
	local recipe = ns.RecipeData[recipeID]
	local profession = recipe and ns.RouteProfessions()[recipe.skillLine]
	local total = 0
	if profession then
		for _, craft in ipairs(ns.PlanRoute(profession).crafts) do
			if craft.recipeID == recipeID then
				total = total + craft.crafts
			end
			-- A recipe the route makes reagents with counts its sub-crafts too.
			for _, sub in ipairs(craft.subcrafts or {}) do
				if sub.recipeID == recipeID then
					total = total + sub.crafts
				end
			end
		end
	end
	return total > 0 and math.ceil(total) or 1
end

-- Each basic reagent `count` crafts need that the bags and bank (once it has been opened) lack, in recipe order:
-- the auction house's and the unpriced ones. A vendor's reagent, or one you gather, is not searched for there.
---@param recipeID integer
---@param count integer
---@return SkillUpShoppingItem[]
function ns.ReagentShortfall(recipeID, count)
	local short = {}
	for _, reagent in ipairs(ns.Reagents(recipeID) or {}) do
		local missing = reagent.quantity * count - ns.Have(reagent.itemID)
		local source = ns.PriceSource(reagent.itemID)
		if missing > 0 and (source == nil or AUCTION_SOURCES[source]) then
			short[#short + 1] = { itemID = reagent.itemID, count = missing }
		end
	end
	return short
end

-- Without Auctionator, which reagent the next click puts in the game's search box, per recipe, count and what is
-- still short, so buying one starts the round again rather than skipping the next.
local nextIndex, nextKey = 1, nil

-- Searches the auction house for what `count` crafts of the recipe still lack. With Auctionator, one shopping
-- list of exact names with quantities, searched at once; without it, the game's own search box gets the next
-- missing reagent's name on each call. Returns how it searched: "auctionator", "game" with the reagent it put in
-- the box, "unfilled" with the reagent it could not (its name not loaded yet, or the auction house not on a
-- Buy tab), or "none".
---@param recipeID integer
---@param count integer
---@return 'auctionator'|'game'|'unfilled'|'none'
---@return SkillUpShoppingItem?
function ns.SearchReagents(recipeID, count)
	local short = ns.ReagentShortfall(recipeID, count)
	if #short == 0 then
		return "none"
	end
	if ns.HasAuctionator() then
		local api = Auctionator.API.v1
		ns.WithItemNames(short, function()
			-- Names can arrive after the auction house has closed; Auctionator searches only while it is open.
			if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
				return
			end
			ns.SafeCall("auction house reagent search", function()
				local searches, names = {}, {}
				for _, item in ipairs(short) do
					local name = assert(C_Item.GetItemNameByID(item.itemID))
					names[#names + 1] = name
					searches[#searches + 1] = api.ConvertToSearchString(
						CALLER,
						{ searchString = name, isExact = true, quantity = item.count }
					)
				end
				api.CreateShoppingList(CALLER, CRAFT_LIST, searches)
				-- MultiSearchAdvanced keeps the quantities; an older Auctionator searches the exact names.
				if api.MultiSearchAdvanced then
					api.MultiSearchAdvanced(CALLER, searches)
				elseif api.MultiSearchExact then
					api.MultiSearchExact(CALLER, names)
				end
			end)
		end)
		return "auctionator"
	end
	local parts = { tostring(recipeID), tostring(count) } ---@type string[]
	for _, item in ipairs(short) do
		parts[#parts + 1] = item.itemID .. ":" .. item.count
	end
	local key = table.concat(parts, ",")
	if key ~= nextKey or nextIndex > #short then
		nextKey, nextIndex = key, 1
	end
	local item = short[nextIndex]
	local name = C_Item.GetItemNameByID(item.itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(item.itemID)
		return "unfilled", item
	end
	-- The auction house's own public setter, which Blizzard's item clicks use: it fills the search box and
	-- starts nothing, so the player's own Search click runs the query. It declines off the Buy tabs.
	local house = AuctionHouseFrame
	if not (house and house:IsShown()) then
		return "unfilled", item
	end
	local filled = house:SetSearchText(name) -- taint-ok: verified safe contract, a setter that queries nothing
	if not filled then
		return "unfilled", item
	end
	nextIndex = nextIndex + 1
	return "game", item
end

-- A closed auction house starts the next visit's round from the first reagent.
local function ForgetRound()
	nextKey, nextIndex = nil, 1
end

---@class SkillUpAuctionBar : Frame
---@field Label FontString
---@field Count EditBox
---@field Crafts FontString
---@field Search Button

---@type SkillUpAuctionBar?
local bar
---@type integer?
local recipeID

-- The count typed into the bar, at least one.
---@return integer
local function Count()
	local count = bar and tonumber(bar.Count:GetText())
	return count and count >= 1 and math.floor(count) or 1
end

local function ShowSearchTooltip(button)
	if not recipeID then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_TOP")
	GameTooltip_SetTitle(GameTooltip, L["Reagents still needed"])
	local short = ns.ReagentShortfall(recipeID, Count())
	for _, item in ipairs(short) do
		local name = C_Item.GetItemNameByID(item.itemID) or string.format(L["item %d"], item.itemID)
		GameTooltip:AddDoubleLine(name, tostring(item.count), 1, 1, 1, 1, 1, 1)
	end
	if #short == 0 then
		GameTooltip_AddNormalLine(GameTooltip, L["Your bags and bank have enough."])
	elseif not ns.HasAuctionator() then
		GameTooltip_AddDisabledLine(GameTooltip, L["Each click puts the next one in the search box; press Search."])
	end
	GameTooltip:Show()
end

local function Refresh()
	if not bar then
		return
	end
	local atAuction = AuctionHouseFrame and AuctionHouseFrame:IsShown()
	local reagents = recipeID and ns.Reagents(recipeID)
	bar:SetShown(ns.db.auctionSearch and atAuction and reagents ~= nil and #reagents > 0 or false)
end

---@param info TradeSkillRecipeInfo?
local function OnRecipeSelected(_, info)
	local id = info and info.recipeID
	if id ~= recipeID then
		recipeID = id
		if bar and id then
			bar.Count:SetText(tostring(ns.PlannedCrafts(id)))
		end
	end
	Refresh()
end

local function OnSearch()
	if not recipeID then
		return
	end
	local how, item = ns.SearchReagents(recipeID, Count())
	if how == "none" then
		ns.Print(L["your bags and bank already hold the reagents for that many."])
	elseif how == "game" and item then
		local name = C_Item.GetItemNameByID(item.itemID) or string.format(L["item %d"], item.itemID)
		ns.Print(string.format(L["searching for %s: you need %d more."], name, item.count))
	elseif how == "unfilled" then
		ns.Print(L["open the auction house's Buy tab, then search again."])
	end
end

function ns.AttachAuctionSearch()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = page and page.SchematicForm
	if bar or not form then
		return
	end
	bar = CreateFrame("Frame", nil, page) --[[@as SkillUpAuctionBar]]
	bar:SetSize(250, 26)
	-- Beside the page's own Create All button, below the recipe, clear of its Track Recipe checkbox.
	if page.CreateAllButton then
		bar:SetPoint("RIGHT", page.CreateAllButton, "LEFT", -12, 0)
	else
		bar:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 160, 8)
	end
	bar.Label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.Label:SetPoint("LEFT", bar, "LEFT", 0, 0)
	bar.Label:SetText(L["Reagents for"])
	bar.Count = CreateFrame("EditBox", nil, bar, "InputBoxTemplate") --[[@as EditBox]]
	bar.Count:SetSize(36, 20)
	bar.Count:SetPoint("LEFT", bar.Label, "RIGHT", 10, 0)
	bar.Count:SetAutoFocus(false)
	bar.Count:SetNumeric(true)
	bar.Count:SetMaxLetters(4)
	bar.Count:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		OnSearch()
	end)
	bar.Count:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	bar.Crafts = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	bar.Crafts:SetPoint("LEFT", bar.Count, "RIGHT", 4, 0)
	bar.Crafts:SetText(L["crafts"])
	bar.Search = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate") --[[@as Button]]
	bar.Search:SetText(L["Search"])
	bar.Search:SetSize(bar.Search:GetTextWidth() + 32, 22)
	bar.Search:SetPoint("LEFT", bar.Crafts, "RIGHT", 10, 0)
	bar.Search:SetScript("OnClick", OnSearch)
	bar.Search:SetScript("OnEnter", ShowSearchTooltip)
	bar.Search:SetScript("OnLeave", GameTooltip_Hide)
	bar:Hide()
	EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", OnRecipeSelected, bar)
	local info = form.GetRecipeInfo and form:GetRecipeInfo()
	OnRecipeSelected(nil, info)
	ns.WhenStale("auctionSearch", Refresh)
end

for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
	ns.WhenEvent(event, function()
		if event == "AUCTION_HOUSE_CLOSED" then
			ForgetRound()
		end
		-- Blizzard shows or hides its frame on the same event; read it a frame later.
		C_Timer.After(0, Refresh)
	end)
end
