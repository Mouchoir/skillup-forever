---@type string, SkillUpNamespace
local _, ns = ...
local L = ns.L

-- Options > AddOns > SkillUp Forever: a short index page, then a stock subpage per group so no page grows
-- tall. Every row goes in through Settings.RegisterInitializer, which inserts it from Blizzard's secure delegate.
-- Settings.CreateCheckbox/CreateDropdown insert from our code instead, and the settings search reads every
-- layout, so that tainted it: a restricted button in the results (Social's Discord Sign In) was then blocked
-- and blamed on us.
local category

---@param target SkillUpCategory
local function Register(target, key, varType, name)
	local setting =
		Settings.RegisterAddOnSetting(target, "SkillUpForever_" .. key, key, ns.db, varType, name, ns.DEFAULTS[key])
	setting:SetValueChangedCallback(function()
		ns.Changed("settings")
	end)
	return setting
end

---@param target SkillUpCategory
local function Checkbox(target, key, name, tooltip)
	Settings.RegisterInitializer(
		target,
		Settings.CreateCheckboxInitializer(Register(target, key, Settings.VarType.Boolean, name), nil, tooltip)
	)
end

-- options: { value, label } pairs, in menu order.
---@param target SkillUpCategory
local function Choice(target, key, name, options, tooltip)
	local setting = Register(target, key, Settings.VarType.String, name)
	local function Index(value)
		for index, option in ipairs(options) do
			if option[1] == value then
				return index
			end
		end
	end
	-- Forever's native settings dropdown enters a menu VM assertion.
	-- A discrete stock slider avoids menus; the string setting remains the saved-value owner.
	local variable = "SkillUpForever_" .. key .. "_choice"
	local proxy = Settings.RegisterProxySetting(
		target,
		variable,
		Settings.VarType.Number,
		name,
		Index(ns.DEFAULTS[key]),
		function()
			return Index(ns.db[key])
		end,
		function(value)
			local option = options[value]
			if option then
				Settings.SetValue("SkillUpForever_" .. key, option[1])
			end
		end
	)
	setting:SetValueChangedCallback(function()
		Settings.NotifyUpdate(variable)
		ns.Changed("settings")
	end)
	local slider = Settings.CreateSliderOptions(1, #options, 1)
	slider:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return options[value][2]
	end)
	Settings.RegisterInitializer(target, Settings.CreateSliderInitializer(proxy, slider, tooltip))
end

-- A phrase is one key however long, so its line may run past the limit.
-- luacheck: push no max line length
function ns.RegisterSettings()
	category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

	-- Rows are grouped onto a stock subpage each; the category itself is the index, one button per group. A
	-- button goes in through Settings.RegisterInitializer too, and stays out of search (addSearchTags false),
	-- which finds the settings themselves.
	local function Section(name, rows)
		local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, name)
		rows(subcategory)
		Settings.RegisterInitializer(
			category,
			CreateSettingsButtonInitializer(name, L["Open"], function()
				Settings.OpenToCategory(subcategory:GetID())
			end, nil, false)
		)
	end

	Section(L["Recipe rows"], function(rows)
		Checkbox(
			rows,
			"showRowText",
			L["Show skill on recipe rows"],
			L["Skill-up chance and cost per skill-up at the right of each recipe."]
		)

		Checkbox(
			rows,
			"showSkill",
			L["Show skill range start on rows"],
			L["Add the start of each recipe's difficulty range. This is separate from the skill needed to learn it."]
		)

		Checkbox(
			rows,
			"showTooltip",
			L["Show thresholds tooltip"],
			L["Orange, yellow, green and grey thresholds when hovering a recipe."]
		)

		Checkbox(
			rows,
			"showCost",
			L["Show cost per skill-up"],
			L["Reagent cost divided by skill-up chance, on recipe rows and in the tooltip. Common vendor reagents are priced from the start and updated at merchants you visit, reagents you gather are free unless you value them under Prices, and auction prices need Auctionator."]
		)
	end)

	Section(L["Prices"], function(rows)
		Choice(
			rows,
			"craftValue",
			L["Count what crafts sell for"],
			ns.CRAFT_VALUE_OPTIONS,
			L["Subtract what the crafted item sells for from its cost. Auction prices need Auctionator, are after the 5% cut, and may not sell."]
		)

		Checkbox(
			rows,
			"valueGathered",
			L["Value gathered materials at what they'd sell for"],
			L["A material your professions gather costs what selling it would bring instead of nothing: its auction price after the 5% cut, or its vendor sell price if that is more. Used for the route and the costs on recipe rows. Auction prices need Auctionator."]
		)
	end)

	Section(L["Route and trainer"], function(rows)
		Checkbox(
			rows,
			"showTracker",
			L["Show tracked professions"],
			L["Show profession routes in the objective tracker. Hiding them keeps your tracked professions and targets."]
		)
		local host = ns.TrackerHost
		if host and host.GetSettings and host.SetAttached and host.OnAttachmentChanged then
			local variable = "SkillUpForever_trackerAttached"
			local setting = Settings.RegisterProxySetting(
				rows,
				variable,
				Settings.VarType.Boolean,
				L["Attach to quest tracker"],
				true,
				function()
					return host.GetSettings().attached
				end,
				function(value)
					host.SetAttached(value == true)
				end
			)
			Settings.RegisterInitializer(
				rows,
				Settings.CreateCheckboxInitializer(
					setting,
					nil,
					L["Turn this off to drag the shared Forever tracker anywhere on screen."]
				)
			)
			host.OnAttachmentChanged(function()
				Settings.NotifyUpdate(variable)
			end)
		end

		Checkbox(
			rows,
			"showRouteTab",
			L["Show the levelling route tab"],
			L["A side tab on the Professions window with a route to your target skill and its reagents. Tracked professions stay in the objective tracker either way."]
		)

		Checkbox(
			rows,
			"showGearTab",
			L["Show the crafted gear tab"],
			L["A side tab on the Professions window listing the newest crafted item this character can equip in each slot, under the route tab."]
		)

		Checkbox(
			rows,
			"merchantButton",
			L["Show the buy button at merchants"],
			L["A button above a merchant's window that buys the reagents your tracked routes still need from that merchant. It asks first, with the total cost."]
		)

		Checkbox(
			rows,
			"showTrainer",
			L["Annotate trainer recipes"],
			L["Required skill, skill-up chance and cost on profession trainer recipes, and which one is best to train next for your route."]
		)
	end)

	Section(L["Tooltips and sorting"], function(rows)
		Choice(
			rows,
			"reagentTooltip",
			L["Reagent tooltips"],
			ns.REAGENT_TOOLTIP_OPTIONS,
			L["What hovering an item says about your professions: how much of it your tracked routes need (hold Shift for every recipe that uses it), every such recipe and its colour, or nothing."]
		)

		Choice(
			rows,
			"sortMode",
			L["Sort recipes"],
			ns.SORT_OPTIONS,
			L["Sort recipes in one list, learned first, then unlearned. Default restores categories."]
		)
	end)

	Section(L["Addon"], function(rows)
		Checkbox(
			rows,
			"companionHints",
			L["Suggest companion addons"],
			L["Waypoint tooltips say when Shortest Path Forever, not installed or turned off, would plot the route."]
		)

		Checkbox(
			rows,
			"whatsNew",
			L["What's new after an update"],
			L["One line in chat the first time a new version loads."]
		)
	end)

	Settings.RegisterAddOnCategory(category)
end
-- luacheck: pop

-- Through the setting, so the settings panel and its change callback stay in step.
---@param mode string
function ns.SetSortMode(mode)
	Settings.SetValue("SkillUpForever_sortMode", mode)
end

function ns.OpenSettings()
	-- No category when an update's files are missing: Core has already said to restart the game.
	if not category then
		return
	end
	Settings.OpenToCategory(category:GetID())
end
