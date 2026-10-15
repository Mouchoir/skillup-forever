-- The stub game client the specs share: `local Client = dofile("tests/client.lua")`, from the repository root.
-- Client.load loads the files SkillUpForever.toc lists, in its order, against stubs of the client API the addon
-- calls, and returns a handle. A spec sets what the client holds (professions, bags, a merchant, Auctionator's
-- prices, the clock), fires the game's events, and asserts on what the addon produces. Nothing on `ns` is faked.
local Client = {}

local ADDON = "SkillUpForever"

local checks = 0
function Client.equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

---@param spec string
function Client.report(spec)
	print(spec .. ": " .. checks .. " checks passed")
end

local function noop() end

-- A synthetic QuestieDB with the public shape Integrations/Questie.lua reads; none of it is the real
-- database's data. `db` is what it knows, and a spec may change it between reads:
--   items = { [id] = { vendors, quests, drops, class, teaches } }
--   npcs = { [id] = { name, spawns = { [area] = { { x, y } } }, zone, side } }, side "A", "H", "AH" or nil
--   quests = { [id] = { name, races } }
--   areas = { [area] = uiMapID }, parents = { [area] = parent area }; contract (2 unless set); a field
--   named in `without` is left out of the schema. `db.reads` counts the records read.
function Client.QuestieDB(db)
	db.reads = 0
	local function Keys(fields)
		local keys = {}
		for index, field in ipairs(fields) do
			keys[field] = db.without ~= field and index or nil
		end
		return keys
	end
	local function Source(map)
		local parts = {}
		for key, value in pairs(map or {}) do
			parts[#parts + 1] = string.format("[%d]=%d", key, value)
		end
		return "return {" .. table.concat(parts, ",") .. "}"
	end
	local function Entity(rows, read)
		return {
			GetAll = function(id, fields)
				db.reads = db.reads + 1
				local row = rows()[id]
				if not row then
					return nil
				end
				local values = { n = #fields }
				for index, field in ipairs(fields) do
					values[index] = read(row, field)
				end
				return values
			end,
			GetAllIds = function()
				local ids = {}
				for id in pairs(rows()) do
					ids[#ids + 1] = id
				end
				table.sort(ids)
				return ids
			end,
		}
	end
	local item = { vendors = "vendors", questRewards = "quests", npcDrops = "drops", teachesSpell = "teaches" }
	local npc = { name = "name", spawns = "spawns", zoneID = "zone", friendlyToFaction = "side" }
	local quest = { name = "name", requiredRaces = "races" }
	return {
		RequireContract = function(required)
			return required == (db.contract or 2), "QuestieDB contract mismatch"
		end,
		Meta = {
			ItemMeta = { itemKeys = Keys({ "vendors", "questRewards", "npcDrops", "class", "teachesSpell" }) },
			NpcMeta = { npcKeys = Keys({ "name", "spawns", "zoneID", "friendlyToFaction" }) },
			QuestMeta = { questKeys = Keys({ "name", "requiredRaces" }) },
		},
		Support = {
			Get = function(name)
				return name == "ZoneDB"
						and {
							private = {
								areaIdToUiMapId = Source(db.areas),
								subZoneToParentZone = Source(db.parents),
							},
						}
					or nil
			end,
		},
		Item = Entity(function()
			return db.items or {}
		end, function(row, field)
			return field == "class" and (row.class or 9) or row[item[field]]
		end),
		Npc = Entity(function()
			return db.npcs or {}
		end, function(row, field)
			return row[npc[field]]
		end),
		Quest = Entity(function()
			return db.quests or {}
		end, function(row, field)
			return row[quest[field]]
		end),
	}
end

-- A synthetic AtlasLoot: `db.recipes` = { [scroll item] = { profession, skill, recipe } } as its recipe
-- module keeps them (one scroll a recipe when asked by recipe: the highest item wins, as its reverse map
-- overwrites), and `db.drops` = { [npc] = { [item] = chance % } }.
function Client.AtlasLoot(db)
	return {
		Data = {
			Recipe = {
				GetRecipeData = function(itemID)
					return db.recipes[itemID]
				end,
				GetRecipeForSpell = function(spellID)
					local found
					for itemID, row in pairs(db.recipes) do
						if row[3] == spellID and (not found or itemID > found) then
							found = itemID
						end
					end
					return found
				end,
			},
			Droprate = {
				GetData = function(_, npcID, itemID)
					return db.drops and db.drops[npcID] and db.drops[npcID][itemID]
				end,
			},
		},
	}
end

-- options: data (ns tables that replace the bundled Data/*.lua ones of the same name), saved (SkillUpForeverDB),
-- auctionator (false for a client without it), trackerManager (false for a client without Blizzard's tracker
-- manager), boot (false to stop before the addon's ADDON_LOADED; c.Boot() then runs it), questie and atlasLoot
-- (what a synthetic QuestieDB and AtlasLoot hold, as Client.QuestieDB and Client.AtlasLoot take it; a client
-- has neither without them), build (the client build GetBuildInfo reports).
function Client.load(options)
	options = options or {}
	local G = setmetatable({}, { __index = _G })
	local c = {
		G = G,
		ns = {},
		now = 0,
		build = options.build or "70205",
		frames = {},
		chat = {},
		-- { name, icon, rank, max, id, modifier } in spellbook order; `id` is what the client reports for it.
		professions = {},
		spells = {}, -- [spellID] = name
		known = {}, -- [spellID] = true: in the spellbook
		items = {}, -- [itemID] = { name, sell }; a missing field is item data the client has not loaded
		bags = {}, -- [itemID] = count
		schematics = {}, -- [recipeID] = { reagents = { { itemID, quantity } }, output = itemID }: the open window's
		-- [recipeID] = { info = { maxTrivialLevel, numSkillUps, learned, relativeDifficulty }, requirements = { ... } }:
		-- what the client's own recipe read answers, empty for a recipe it says nothing about.
		live = {},
		craftable = 999, -- what C_TradeSkillUI.GetCraftableCount answers
		auction = {}, -- [itemID] = copper, as Auctionator last saw it
		auctionAge = 0, -- whole days
		auctionAutoscan = nil, -- Auctionator's "scan when the auction house opens" option
		shoppingLists = {}, -- [list name] = the searches Auctionator was last given
		merchant = nil, -- { { itemID, price, stackCount, ... } } while a merchant window is open
		npc = nil, -- { id, name }: who the player is dealing with, the client's "npc" unit
		money = 1000000,
		level = 60,
		player = { name = "Tester", realm = "Realm", faction = "Alliance", x = 0, y = 0, instance = 0 },
		maps = {}, -- [world instance] = { mapID, name }: the continent's one zone map
		areas = {}, -- [areaID] = name
		opened = {}, -- profession IDs passed to OpenTradeSkill
		purchased = {}, -- { index, count } per BuyMerchantItem call
		requested = {}, -- [itemID] = true: item data asked for
		tracker = {}, -- modules attached to the shared tracker host
	}
	G._G = G

	--[[ Frames ]]

	-- Scripts, events, visibility and text are kept; any other setter is accepted and ignored. A method that is
	-- none of those is nil, so a new client call the addon makes fails here until it is stubbed on purpose.
	local Methods = {}
	local frameMeta = {
		__index = function(_, key)
			if Methods[key] then
				return Methods[key]
			elseif type(key) == "string" and (key:find("^Set") or key:find("^Clear") or key:find("^Enable")) then
				return noop
			end
		end,
	}
	local function NewFrame(name, parent)
		local frame = setmetatable({
			parent = parent,
			scripts = {},
			events = {},
			shown = true,
		}, frameMeta)
		c.frames[#c.frames + 1] = frame
		if name then
			G[name] = frame
		end
		return frame
	end
	function Methods:RegisterEvent(event)
		self.events[event] = true
	end
	function Methods:SetScript(name, fn)
		self.scripts[name] = fn
	end
	function Methods:Show()
		self.shown = true
	end
	function Methods:Hide()
		self.shown = false
	end
	function Methods:SetShown(shown)
		self.shown = shown and true or false
	end
	function Methods:IsShown()
		return self.shown
	end
	function Methods:SetEnabled(enabled)
		self.disabled = not enabled
	end
	function Methods:IsEnabled()
		return not self.disabled
	end
	function Methods:SetText(text)
		self.text = text
	end
	function Methods.GetTextWidth()
		return 100
	end
	-- A font string keeps its text like a frame does.
	function Methods:CreateFontString()
		return NewFrame(nil, self)
	end

	-- What the tracker section's stock template gives it; the shared host lays it out with these.
	local TrackerModule = {}
	function TrackerModule:MarkDirty()
		self.dirty = (self.dirty or 0) + 1
	end
	function TrackerModule:GetBlock(id)
		local block = { id = id, lines = {}, SetHeader = noop }
		function block.AddObjective(_, key, text)
			block.lines[#block.lines + 1] = { key = key, text = text }
			return NewFrame()
		end
		self.blocks[#self.blocks + 1] = block
		return block
	end
	function TrackerModule.LayoutBlock()
		return true
	end

	G.CreateFrame = function(_, name, parent, template)
		local frame = NewFrame(name, parent)
		if template == "ObjectiveTrackerModuleTemplate" then
			for key, method in pairs(TrackerModule) do
				frame[key] = method
			end
		end
		return frame
	end
	G.UIParent = NewFrame("UIParent")
	G.ObjectiveTrackerFrame = NewFrame("ObjectiveTrackerFrame")
	G.MerchantFrame = NewFrame("MerchantFrame")
	G.MerchantFrame.IsShown = function()
		return c.merchant ~= nil
	end
	G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, message)
			c.chat[#c.chat + 1] = message
		end,
	}
	-- Blizzard's tracker manager is never entered, and no native method is hooked.
	if options.trackerManager ~= false then
		G.ObjectiveTrackerManager = setmetatable({}, {
			__index = function()
				error("native tracker accessed")
			end,
		})
	end
	G.hooksecurefunc = function()
		error("native methods must stay unhooked")
	end
	G.OBJECTIVE_TRACKER_COLOR = { Complete = "complete" }

	-- The tracker host another Forever addon already published; UI/TrackerHost.lua adopts it instead of
	-- building its own, whose frames tracker_host_spec covers.
	c.host = {
		Attach = function(module)
			if not c.host.IsAttached(module) then
				c.tracker[#c.tracker + 1] = module
			end
		end,
		IsAttached = function(module)
			for _, attached in ipairs(c.tracker) do
				if attached == module then
					return true
				end
			end
			return false
		end,
	}
	G.ForeverTrackerHost = c.host

	-- The attached sections laid out now: { { id, lines = { { key, text } } } }, top to bottom.
	function c.Tracker()
		local blocks = {}
		for _, module in ipairs(c.tracker) do
			module.blocks = blocks
			module:LayoutContents()
		end
		return blocks
	end

	--[[ Events and time ]]

	-- An event reaches only the frames that registered for it.
	function c.Fire(event, ...)
		for _, frame in ipairs(c.frames) do
			if frame.events[event] and frame.scripts.OnEvent then
				frame.scripts.OnEvent(frame, event, ...)
			end
		end
	end

	---@return integer frames how many frames registered for the event
	function c.Listeners(event)
		local count = 0
		for _, frame in ipairs(c.frames) do
			count = count + (frame.events[event] and 1 or 0)
		end
		return count
	end

	local timers = {}
	G.C_Timer = {
		After = function(delay, fn)
			timers[#timers + 1] = { at = c.now + delay, fn = fn }
		end,
	}

	-- Moves the clock on and runs the timers that came due, earliest first; Advance(0) is the next frame.
	function c.Advance(seconds)
		c.now = c.now + seconds
		while true do
			local due
			for index, timer in ipairs(timers) do
				if timer.at <= c.now and (not due or timer.at < timers[due].at) then
					due = index
				end
			end
			if not due then
				return
			end
			table.remove(timers, due).fn()
		end
	end

	local addons, waiting, afterEvents = {}, {}, {}
	G.EventUtil = {
		ContinueOnAddOnLoaded = function(name, fn)
			if addons[name] then
				fn()
			else
				waiting[name] = waiting[name] or {}
				table.insert(waiting[name], fn)
			end
		end,
		ContinueAfterAllEvents = function(fn)
			afterEvents[#afterEvents + 1] = fn
		end,
	}
	-- A load-on-demand addon (Blizzard_Professions, Blizzard_TrainerUI) arriving.
	function c.LoadAddOn(name)
		addons[name] = true
		for _, fn in ipairs(waiting[name] or {}) do
			fn()
		end
		waiting[name] = nil
	end
	-- The login events everything deferred with ContinueAfterAllEvents waits on.
	function c.EnterWorld()
		for _, fn in ipairs(afterEvents) do
			fn()
		end
	end

	--[[ The character ]]

	G.UnitName = function(unit)
		if unit == "npc" then
			return c.npc and c.npc.name
		end
		return c.player.name
	end
	G.UnitClass = function()
		return c.player.className or "Shaman", c.player.classFile or "SHAMAN", c.player.classID or 64
	end
	G.UnitGUID = function(unit)
		return unit == "npc" and c.npc and string.format("Creature-0-1-0-0-%d-0000000001", c.npc.id) or nil
	end
	G.GetNormalizedRealmName = function()
		return c.player.realm
	end
	G.UnitFactionGroup = function()
		return c.player.faction
	end
	G.UnitLevel = function()
		return c.level
	end
	G.UnitPosition = function()
		return c.player.x, c.player.y, 0, c.player.instance
	end
	G.InCombatLockdown = function()
		return false
	end
	G.GetMoney = function()
		return c.money
	end
	G.GetProfessions = function()
		local indices = {}
		for index in ipairs(c.professions) do
			indices[index] = index
		end
		return unpack(indices)
	end
	G.GetProfessionInfo = function(index)
		local p = c.professions[index]
		return p.name, p.icon, p.rank, p.max, nil, nil, p.id, p.modifier
	end
	G.C_Spell = {
		GetSpellName = function(id)
			return c.spells[id]
		end,
	}
	G.C_SpellBook = {
		IsSpellKnown = function(id)
			return c.known[id] == true
		end,
	}
	G.C_TradeSkillUI = {
		GetRecipeSchematic = function(recipeID)
			local schematic = c.schematics[recipeID]
			if not schematic then
				return nil
			end
			local slots = {}
			for index, reagent in ipairs(schematic.reagents) do
				slots[index] =
					{ reagentType = 0, quantityRequired = reagent[2], reagents = { { itemID = reagent[1] } } }
			end
			return { reagentSlotSchematics = slots, outputItemID = schematic.output, quantityMin = 1 }
		end,
		OpenTradeSkill = function(id)
			c.opened[#c.opened + 1] = id
			return true
		end,
		OpenRecipe = function(recipeID)
			c.opened[#c.opened + 1] = recipeID
		end,
		-- No profession window is open.
		IsTradeSkillLinked = function()
			return false
		end,
		IsTradeSkillGuild = function()
			return false
		end,
		GetBaseProfessionInfo = noop,
		GetAllRecipeIDs = function()
			local ids = {}
			for recipeID in pairs(c.live) do
				ids[#ids + 1] = recipeID
			end
			table.sort(ids)
			return ids
		end,
		GetRecipeInfo = function(recipeID)
			return c.live[recipeID] and c.live[recipeID].info
		end,
		GetRecipeRequirements = function(recipeID)
			return c.live[recipeID] and c.live[recipeID].requirements or {}
		end,
		GetCraftableCount = function()
			return c.craftable
		end,
	}

	--[[ Items, bags and the merchant ]]

	G.C_Item = {
		GetItemInfo = function(id)
			local item = c.items[id] or {}
			return item.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, item.sell
		end,
		GetItemNameByID = function(id)
			return c.items[id] and c.items[id].name
		end,
		GetItemIconByID = function(id)
			return c.items[id] and c.items[id].icon
		end,
		GetItemQualityByID = function(id)
			return c.items[id] and c.items[id].quality
		end,
		GetItemQualityColor = function()
			return 1, 1, 1, "ffffff"
		end,
		GetItemCount = function(id)
			return c.bags[id] or 0
		end,
		RequestLoadItemDataByID = function(id)
			c.requested[id] = true
		end,
		-- A tool requirement is a localized item name; the client resolves it back to the item.
		GetItemInfoInstant = function(itemInfo)
			if type(itemInfo) == "number" then
				return itemInfo
			end
			for itemID, item in pairs(c.items) do
				if item.name == itemInfo then
					return itemID
				end
			end
		end,
	}
	G.C_CurrencyInfo = {
		GetCoinTextureString = function(copper)
			return copper .. "c"
		end,
	}
	G.C_PaperDollInfo = {
		GetInventorySlotInfo = function()
			return 0, 134400
		end,
	}
	G.GetMerchantNumItems = function()
		return c.merchant and #c.merchant or 0
	end
	G.GetMerchantItemID = function(index)
		return c.merchant[index].itemID
	end
	G.C_MerchantFrame = {
		GetItemInfo = function(index)
			return c.merchant[index]
		end,
	}
	G.GetMerchantItemMaxStack = function()
		return 20
	end
	G.BuyMerchantItem = function(index, count)
		c.purchased[#c.purchased + 1] = { index = index, count = count }
	end

	--[[ Auctionator ]]

	local scanned = {}
	-- Item:CreateFromItemID and ContinuableContainer are what Auctionator's name lookups need; the
	-- container calls back at once, as it does when every name is already known.
	G.Item = {
		CreateFromItemID = function(itemID)
			return itemID
		end,
	}
	G.ContinuableContainer = {
		Create = function()
			local items = {}
			return {
				AddContinuable = function(_, item)
					items[#items + 1] = item
				end,
				ContinueOnLoad = function(_, callback)
					callback()
				end,
			}
		end,
	}
	if options.auctionator ~= false then
		G.Auctionator = {
			API = {
				v1 = {
					GetAuctionPriceByItemID = function(_, itemID)
						return c.auction[itemID]
					end,
					GetAuctionAgeByItemID = function(_, itemID)
						if type(c.auctionAge) == "table" then
							return c.auctionAge[itemID]
						end
						return c.auctionAge
					end,
					RegisterForDBUpdate = function(_, fn)
						scanned[#scanned + 1] = fn
					end,
					CreateShoppingList = function(_, name, searches)
						c.shoppingLists[name] = searches
					end,
					ConvertToSearchString = function(_, request)
						return string.format("%sx%d", request.searchString, request.quantity)
					end,
				},
			},
			-- Auctionator's own config table, which has no public API contract.
			Config = {
				Options = { AUTOSCAN = "autoscan_2" },
				Get = function()
					return c.auctionAutoscan
				end,
			},
		}
	end
	-- Auctionator finished a scan: its prices are now what c.auction holds.
	function c.AuctionatorScan()
		for _, fn in ipairs(scanned) do
			fn()
		end
	end

	--[[ The map: every spawn of a world instance is the middle of that instance's one zone map ]]

	local function Middle()
		return {
			GetXY = function()
				return 0.5, 0.5
			end,
		}
	end
	local function MapInfo(mapID)
		for _, map in pairs(c.maps) do
			if map.mapID == mapID then
				return { mapID = mapID, name = map.name, mapType = G.Enum.UIMapType.Zone, parentMapID = 0 }
			end
		end
	end
	G.C_Map = {
		-- A zone map covers its continent: a map point is the same numbers as a world one.
		GetWorldPosFromMapPos = function(mapID, point)
			for instance, map in pairs(c.maps) do
				if map.mapID == mapID then
					return instance, {
						GetXY = function()
							return point.x, point.y
						end,
					}
				end
			end
		end,
		GetMapInfo = MapInfo,
		GetAreaInfo = function(areaID)
			return c.areas[areaID]
		end,
		GetBestMapForUnit = function()
			return c.maps[c.player.instance] and c.maps[c.player.instance].mapID
		end,
		GetPlayerMapPosition = Middle,
	}
	G.CreateVector2D = function(x, y)
		return { x = x, y = y }
	end

	--[[ Settings: the stock panel as a table of settings; a change runs the addon's own callback ]]

	local settings = {}
	local function Setting(variable, get, set)
		local setting = { GetValue = get }
		function setting:SetValueChangedCallback(fn)
			self.changed = fn
		end
		function setting.SetValue(_, value)
			set(value)
			if setting.changed then
				setting.changed()
			end
		end
		settings[variable] = setting
		return setting
	end
	local categories = 0
	local function Category()
		categories = categories + 1
		local id = categories
		return {
			GetID = function()
				return id
			end,
		}
	end
	G.Settings = {
		VarType = { Boolean = "boolean", String = "string", Number = "number" },
		RegisterVerticalLayoutCategory = Category,
		RegisterVerticalLayoutSubcategory = Category,
		RegisterAddOnCategory = noop,
		RegisterAddOnSetting = function(_, variable, key, db)
			return Setting(variable, function()
				return db[key]
			end, function(value)
				db[key] = value
			end)
		end,
		RegisterProxySetting = function(_, variable, _, _, _, get, set)
			return Setting(variable, get, set)
		end,
		RegisterInitializer = noop,
		CreateCheckboxInitializer = noop,
		CreateSliderInitializer = noop,
		CreateSliderOptions = function()
			return { SetLabelFormatter = noop }
		end,
		SetValue = function(variable, value)
			settings[variable]:SetValue(value)
		end,
		NotifyUpdate = noop,
		OpenToCategory = noop,
	}
	G.CreateSettingsButtonInitializer = noop
	G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }
	-- The player changing one of the addon's settings in the options panel.
	function c.SetSetting(key, value)
		G.Settings.SetValue(ADDON .. "_" .. key, value)
	end

	--[[ The rest of what the files touch as they load and initialise ]]

	G.Enum = {
		TradeskillRelativeDifficulty = { Optimal = 1, Medium = 2, Easy = 3, Trivial = 4 },
		CraftingReagentType = { Basic = 0 },
		RecipeRequirementType = { SpellFocus = 0, Totem = 1, Area = 2 },
		TooltipDataType = { Item = 0, Unit = 2, Object = 4 },
		UIMapType = { Continent = 2, Zone = 3, Dungeon = 4, Micro = 5 },
	}
	G.CreateColor = function(r, g, b)
		return {
			r = r,
			g = g,
			b = b,
			GetRGB = function(self)
				return self.r, self.g, self.b
			end,
		}
	end
	-- [tooltip data type] = the post-calls the addon added, for a spec to run against its own tooltip.
	c.postCalls = {}
	G.TooltipDataProcessor = {
		AddTooltipPostCall = function(kind, call)
			c.postCalls[kind] = c.postCalls[kind] or {}
			table.insert(c.postCalls[kind], call)
		end,
	}
	c.locale = "enUS"
	G.GetLocale = function()
		return c.locale
	end
	G.UNIT_SKINNABLE_LEATHER = "Skinnable"
	G.UNIT_SKINNABLE_HERB, G.UNIT_SKINNABLE_ROCK = "Requires Herbalism", "Requires Mining"
	G.SlashCmdList = {}
	G.strtrim = function(text)
		return (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end
	G.PlaySound = noop
	G.SOUNDKIT = {}
	G.DEFAULT, G.OFF, G.UNKNOWN = "Default", "Off", "Unknown"
	G.debugprofilestop = function()
		return 0
	end
	G.time = function()
		return c.now
	end
	G.GetBuildInfo = function()
		return "1.60.1", c.build, "Sep 24 2026", 16001, "wow", "1.60.1." .. c.build
	end
	G.C_AddOns = {
		GetAddOnMetadata = function(_, field)
			return field == "X-Flavor" and "Forever" or nil
		end,
		IsAddOnLoaded = function()
			return false
		end,
		DoesAddOnExist = function()
			return false
		end,
	}
	G.LibQuestieDB = options.questie and Client.QuestieDB(options.questie)
	G.AtlasLoot = options.atlasLoot and Client.AtlasLoot(options.atlasLoot)
	G.APPRENTICE, G.JOURNEYMAN, G.EXPERT, G.ARTISAN = "Apprentice", "Journeyman", "Expert", "Artisan"
	G.Mixin = function(target, source)
		for key, value in pairs(source) do
			target[key] = value
		end
		return target
	end

	--[[ The addon ]]

	G.SkillUpForeverDB = options.saved
	local data = options.data
	for line in io.lines(ADDON .. ".toc") do
		local file = line:match("^([%w_\\]+%.lua)%s*$")
		if file then
			-- The fixtures stand in for the bundled tables before any file reads them.
			if data and not file:find("^Locales\\") and not file:find("^Data\\") then
				for name, value in pairs(data) do
					c.ns[name] = value
				end
				data = nil
			end
			setfenv(assert(loadfile((file:gsub("\\", "/")))), G)(ADDON, c.ns)
		end
	end
	function c.Boot()
		c.LoadAddOn(ADDON)
	end
	if options.boot ~= false then
		c.Boot()
	end
	return c
end

return Client
