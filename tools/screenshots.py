"""Render the README screenshots from the client's own UI art.

    python3 tools/screenshots.py

Needs Pillow and the wowmock library (env WOWMOCK, default ~/.claude/skills/wow-mock-screenshots). Assets
are fetched from wago.tools once and cached under ~/.cache/wowmock/<build>/.

Every number drawn comes from this repository: thresholds, reagents, sell prices, vendor prices and
what each gathering profession covers from Data/*.lua. The window, tooltip and demo push them through a
Python port of Core/Model.lua, Integrations/Prices.lua, UI/RecipeList.lua's sort and the formatting in
Core/Core.lua and UI/Tooltip.lua; the route, tracker, trainer and reagent scenes run the addon's own Lua under
luajit (lua_scene) and only draw its output.
Only the scene's state (professions, skill, bags, auction prices) is chosen here.
"""

import io
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

WOWMOCK = Path(os.environ.get("WOWMOCK", Path.home() / ".claude" / "skills" / "wow-mock-screenshots"))
if not (WOWMOCK / "wowmock.py").exists():
    sys.exit(f"wowmock.py not found in {WOWMOCK}; set WOWMOCK to the directory that holds it")
sys.path.insert(0, str(WOWMOCK))

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "docs" / "screenshots"

# ------------------------------------------------------------------------------------------ Data/*.lua


LUA_TABLE_SERIALIZER = r"""
local chunk = assert(loadfile(arg[1]))
local ns = {}
setfenv(chunk, setmetatable({}, { __index = _G }))
chunk("SkillUpForever", ns)
local function quote(value)
    local result = { '"' }
    for index = 1, #value do
        local byte = string.byte(value, index)
        if byte == 34 then result[#result + 1] = '\\"'
        elseif byte == 92 then result[#result + 1] = '\\\\'
        elseif byte < 32 then result[#result + 1] = string.format('\\u%04x', byte)
        else result[#result + 1] = string.char(byte) end
    end
    result[#result + 1] = '"'
    return table.concat(result)
end
local function encode(value, seen)
    if type(value) == "string" then return quote(value) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    if type(value) ~= "table" then error("unsupported generated value: " .. type(value)) end
    seen = seen or {}
    assert(not seen[value], "cycle in generated data")
    seen[value] = true
    local array = #value > 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then array = false end
    end
    local parts = {}
    local count = 0
    for _ in pairs(value) do count = count + 1 end
    if count == 0 then
        seen[value] = nil
        return "[]"
    end
    array = array and count == #value
    if array then
        for index = 1, #value do parts[#parts + 1] = encode(value[index], seen) end
        seen[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        parts[#parts + 1] = "[" .. encode(key, seen) .. "," .. encode(value[key], seen) .. "]"
    end
    seen[value] = nil
    return '{"__map__":[' .. table.concat(parts, ",") .. "]}"
end
io.write(encode(ns))
"""


def parse_lua_tables(text):
    """Decode generated Lua with LuaJIT, preserving Lua string and number semantics."""
    with tempfile.NamedTemporaryFile("w", suffix=".lua", encoding="utf-8") as source:
        source.write(text)
        source.flush()
        result = subprocess.run(
            ["luajit", "-", source.name],
            input=LUA_TABLE_SERIALIZER,
            text=True,
            capture_output=True,
            check=True,
        )

    def restore(value):
        if isinstance(value, list):
            return [restore(item) for item in value]
        if isinstance(value, dict) and set(value) == {"__map__"}:
            return {restore(key): restore(item) for key, item in value["__map__"]}
        if isinstance(value, dict):
            return {key: restore(item) for key, item in value.items()}
        return value

    return restore(json.loads(result.stdout))


def load_data():
    ns = {}
    for name in ("Recipes", "Thresholds", "Vendor", "Sources"):
        ns.update(parse_lua_tables((REPO / "Data" / f"{name}.lua").read_text()))
    ns["RecipeName"] = {rid: name for names in ns["RecipeNames"].values() for name, rid in names.items()}
    return ns


NS = load_data()

# ------------------------------------------------------- Core/Model.lua and Integrations/Prices.lua port


def model_color(t, skill):
    if not t:
        return None
    for threshold, color in zip(t, ("red", "orange", "yellow", "green"), strict=False):
        if skill < threshold:
            return color
    return "grey"


def model_chance(t, skill):
    if not t or t[3] <= t[1] or skill < t[0]:
        return None
    if skill < t[1]:
        return 1
    if skill >= t[3]:
        return 0
    return (t[3] - skill) / (t[3] - t[1])


def model_recipe_cost(reagents, price):
    if reagents is None:
        return None
    total = 0
    for reagent in reagents:
        each = price(reagent["itemID"])
        if each is None:
            return None
        total += each * reagent["quantity"]
    return total


def model_cost_per_skill_up(cost, chance):
    if cost is None or not chance or chance <= 0:
        return None
    return cost / chance


def model_craft_value(sell, auction, mode):
    if mode == "none":
        return None, None
    vendor = sell if sell and sell > 0 else None
    # Lua's 0 is true: a zero auction price still counts, as in Prices.lua's ItemValue.
    resale = auction * 0.95 if mode == "auction" and auction is not None else None
    if resale is not None and (not vendor or resale > vendor):
        return resale, "auction"
    return vendor, "vendor" if vendor else None


def round_money(copper):
    if copper == 0:
        return 0
    unit = 10000 if copper >= 1000000 else 100 if copper >= 100 else 1
    return max(math.floor(copper / unit + 0.5), 1) * unit


# ------------------------------------------------------------------------------------------- scene state

COLORS = {  # Core/Core.lua ns.COLORS: the client's GlobalColor rows it names
    "red": (1, 32 / 255, 32 / 255),  # RED_FONT_COLOR
    "orange": (1, 128 / 255, 64 / 255),  # DIFFICULT_DIFFICULTY_COLOR
    "yellow": (1, 1, 0),  # FAIR_DIFFICULTY_COLOR
    "green": (64 / 255, 192 / 255, 64 / 255),  # EASY_DIFFICULTY_COLOR
    "grey": (128 / 255, 128 / 255, 128 / 255),  # TRIVIAL_DIFFICULTY_COLOR
    "unknown": (128 / 255, 128 / 255, 128 / 255),  # GRAY_FONT_COLOR
}

# A Leatherworker/Skinner at 48/75: under the default "gathered reagents are free" the leather, hides and
# scraps Skinning covers cost nothing, so only the vendor thread is paid for. The recipes are the trainer's
# first ones.
SKILL, MAX_SKILL = 48, 75
LEARNED = [2152, 2149, 9058, 9059, 7126, 2153, 3753, 3816, 9060, 9062, 2881, 1229432]
UNLEARNED = [8322]  # Moonglow Vest: taught by a quest
BAGS = {2318: 23}  # Light Leather
AUCTION = {2318: 90, 783: 320, 2934: 8}  # Light Leather, Light Hide, Ruined Leather Scraps (copper), from Auctionator
PROFESSIONS = [  # GetProfessions order, as the side tabs show them: name, icon, rank, max, skill line
    ("Leatherworking", 136247, SKILL, MAX_SKILL, 165),
    ("Skinning", 134366, 62, 75, 393),
    ("First Aid", 135966, 1, 75, 129),
    ("Fishing", 136245, 1, 75, 356),
    ("Cooking", 133971, 1, 75, 185),
]
SKILL_LINE_NAMES = {line: name for name, _, _, _, line in PROFESSIONS}


def price(item_id):
    """Integrations/Prices.lua ns.Price in gather mode: free when one of the
    character's professions gathers it, else vendor (when it's no dearer than
    the auction house), else auction."""
    profession = SKILL_LINE_NAMES.get(NS["GatheredBy"].get(item_id))
    if profession:
        return {"copper": 0, "source": "gather", "profession": profession}
    vendor, ah = NS["VendorPrices"].get(item_id), AUCTION.get(item_id)
    if vendor is not None and (ah is None or vendor <= ah):
        return {"copper": vendor, "source": "vendor"}
    if ah is not None:
        return {"copper": ah, "source": "auctionator"}
    return None


def unit_price(item_id):
    p = price(item_id)
    return p and p["copper"]


def reagents(recipe_id):
    return NS["RecipeData"][recipe_id]["reagents"]


def craft_value(recipe_id):
    """Integrations/Prices.lua CraftValue with craftValue "vendor": the value, and whether it is missing only because
    the sell price isn't known."""
    output = NS["RecipeData"][recipe_id]["output"]
    if not output:
        return None, False
    sell = NS["ItemSellPrices"].get(output["itemID"])
    each, source = model_craft_value(sell, AUCTION.get(output["itemID"]), "vendor")
    if each is None or source is None:
        return None, sell is None
    return {"copper": each * output["quantity"], "source": source, "quantity": output["quantity"]}, False


def craft_cost(recipe_id):
    """Integrations/Prices.lua ns.CraftCost: reagent cost, value and net (unknown until the sell price is)."""
    cost = model_recipe_cost(reagents(recipe_id), unit_price)
    if cost is None:
        return None, None, None
    value, unpriced = craft_value(recipe_id)
    return cost, value, None if unpriced else cost - (value["copper"] if value else 0)


def describe(recipe_id):
    """Core/Core.lua ns.Describe at SKILL, where the live difficulty agrees with the thresholds, so the chance is
    the thresholds' own."""
    t = NS["Thresholds"].get(recipe_id)
    if t and not (t[0] <= t[1] <= t[2] < t[3]):
        t = None
    cost, value, net = craft_cost(recipe_id)
    chance = model_chance(t, SKILL)
    return {
        "thresholds": t,
        "color": model_color(t, SKILL),
        "chance": chance,
        "cost": cost,
        "value": value,
        "net": net,
        "perSkillUp": model_cost_per_skill_up(net, chance),
    }


def row_color(d):
    return COLORS[d["color"] if d["chance"] is not None else ("red" if d["thresholds"] else "unknown")]


def recipe_name(recipe_id):
    return NS["RecipeName"][recipe_id]


def sorted_recipes():
    """RecipeList.lua BuildSorted with sortMode "cost": learned, then unlearned, each by perSkillUp, ties by
    name; None sorts last."""

    def key(recipe_id):
        per = describe(recipe_id)["perSkillUp"]
        return (math.inf if per is None else per, recipe_name(recipe_id).lower())

    return sorted(LEARNED, key=key), sorted(UNLEARNED, key=key)


def craftable_count(recipe_id):
    counts = [BAGS.get(r["itemID"], 0) // r["quantity"] for r in reagents(recipe_id)]
    return min(counts) if counts else 0


# ----------------------------------------------------------------------------------- the addon's own Lua

LEVEL = 20
MONEY = 25000  # 2g 50s: every Apprentice fee is within reach, so the trainer's next pick can be any of them
TOOLTIP_ITEM = 2318  # Light Leather

# Loads the TOC's Lua files, except UI/TrackerHost.lua which the scene stubs, under luajit into recording stubs
# of the client (as tests/route_spec.lua does), runs the addon's start-up, opens its route page, lays out its
# tracker section, decorates an Apprentice trainer's services and shows the reagent's item tooltip, and prints
# what each would draw as JSON. Money is left as {coin:N} and item names as {item:N} for the renderer to fill in.
LUA_SCENE = r"""
-- STATE is defined above this line by screenshots.py.
local ADDON = "SkillUpForever"
local FILES = {}
for line in io.lines(ADDON .. ".toc") do
	local file = line:match("^([%w_\\]+%.lua)%s*$")
	if file and file ~= "UI\\TrackerHost.lua" then
		FILES[#FILES + 1] = (file:gsub("\\", "/"))
	end
end

local function Color(r, g, b)
	return {
		r = r,
		g = g,
		b = b,
		GetRGB = function(c)
			return c.r, c.g, c.b
		end,
	}
end

-- A frame whose methods do nothing but record what the addon shows: text, colour, enabled, shown, scripts.
local RECORDED = {
	SetText = function(self, text)
		rawset(self, "text", text)
	end,
	SetFormattedText = function(self, pattern, ...)
		rawset(self, "text", string.format(pattern, ...))
	end,
	SetTextColor = function(self, r, g, b)
		rawset(self, "color", { r, g, b })
	end,
	SetWidth = function(self, width)
		rawset(self, "width", width)
	end,
	SetTexture = function(self, texture)
		rawset(self, "texture", texture)
	end,
	SetAtlas = function(self, atlas)
		rawset(self, "atlas", atlas)
	end,
	SetVertexColor = function(self, r, g, b)
		rawset(self, "vertex", { r = r, g = g, b = b })
	end,
	SetDesaturated = function(self, desaturated)
		rawset(self, "desaturated", desaturated and true or false)
	end,
	SetEnabled = function(self, enabled)
		rawset(self, "enabled", enabled and true or false)
	end,
	SetChecked = function(self, checked)
		rawset(self, "checked", checked and true or false)
	end,
	GetChecked = function(self)
		return rawget(self, "checked") == true
	end,
	Disable = function(self)
		rawset(self, "enabled", false)
	end,
	SetShown = function(self, shown)
		rawset(self, "shown", shown and true or false)
	end,
	Show = function(self)
		rawset(self, "shown", true)
		if self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end,
	Hide = function(self)
		rawset(self, "shown", false)
	end,
	IsShown = function(self)
		return rawget(self, "shown") == true
	end,
	SetScript = function(self, name, fn)
		self.scripts[name] = fn
	end,
	HookScript = function(self, name, fn)
		local previous = self.scripts[name]
		self.scripts[name] = function(...)
			if previous then previous(...) end
			fn(...)
		end
	end,
	SetCustomOnMouseUpHandler = function(self, fn)
		self.scripts.OnMouseUp = fn
	end,
	SetPortraitToAsset = function(self, asset)
		rawset(self, "portrait", asset)
	end,
	GetTextWidth = function()
		return 0
	end,
	GetWidth = function()
		return 0
	end,
	HasFocus = function()
		return false
	end,
	IsForbidden = function()
		return false
	end,
}

local function Stub()
	return setmetatable({ scripts = {} }, {
		__index = function(self, key)
			-- Fields the addon sets (recipeID, reason, ...) read nil once cleared; methods and child frames stub.
			if type(key) == "string" and key:match("^%l") then
				return nil
			end
			local value = RECORDED[key] or Stub()
			rawset(self, key, value)
			return value
		end,
		__call = function()
			return Stub()
		end,
	})
end

local created, named, hooks, postCalls, loaded = {}, {}, {}, {}, {}
local learned, spellNames = {}, {}
for _, id in ipairs(STATE.learned) do
	learned[id] = true
end

local function TooltipLines(tooltip)
	local lines = rawget(tooltip, "lines")
	if not lines then
		lines = {}
		rawset(tooltip, "lines", lines)
	end
	return lines
end

local function AddLine(tooltip, left, color)
	local lines = TooltipLines(tooltip)
	lines[#lines + 1] = { left = left, color = color }
end

local env
env = setmetatable({
	-- Colours as Blizzard defines them (Core/Core.lua's ns.COLORS takes the difficulty ones).
	RED_FONT_COLOR = Color(unpack(STATE.colors.red)),
	DIFFICULT_DIFFICULTY_COLOR = Color(unpack(STATE.colors.orange)),
	FAIR_DIFFICULTY_COLOR = Color(unpack(STATE.colors.yellow)),
	EASY_DIFFICULTY_COLOR = Color(unpack(STATE.colors.green)),
	TRIVIAL_DIFFICULTY_COLOR = Color(unpack(STATE.colors.grey)),
	GRAY_FONT_COLOR = Color(unpack(STATE.colors.unknown)),
	NORMAL_FONT_COLOR = Color(1, 0.82, 0),
	HIGHLIGHT_FONT_COLOR = Color(1, 1, 1),
	DISABLED_FONT_COLOR = Color(unpack(STATE.disabledColor)),
	OBJECTIVE_TRACKER_COLOR = { Complete = Color(0.6, 0.6, 0.6), Normal = Color(0.8, 0.8, 0.8) },
	OBJECTIVE_DASH_STYLE_HIDE = 2,
	CreateColor = Color,
	APPRENTICE = "Apprentice",
	JOURNEYMAN = "Journeyman",
	EXPERT = "Expert",
	ARTISAN = "Artisan",
	TOTAL = "Total",
	DEFAULT = "Default",
	OFF = "Off",
	Enum = {
		TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 },
		TooltipDataType = { Item = 0, Unit = 2, Object = 4 },
		CraftingReagentType = { Basic = 0 },
		TrainerType = { Tradeskills = 1 },
	},
	SOUNDKIT = {},
	SlashCmdList = {},
	issecretvalue = false,
	GameTooltip_Hide = function() end,
	CreateFrame = function(_, name)
		local frame = Stub()
		created[#created + 1] = frame
		if name then
			named[name] = frame
		end
		return frame
	end,
	Mixin = function(object, ...)
		for i = 1, select("#", ...) do
			for key, value in pairs((select(i, ...))) do
				rawset(object, key, value)
			end
		end
		return object
	end,
	hooksecurefunc = function(a, b, c)
		if type(a) == "string" then
			hooks[a] = b
		else
			hooks[b] = c
		end
	end,
	C_Timer = {
		After = function(_, fn)
			fn()
		end,
	},
	EventUtil = {
		ContinueAfterAllEvents = function(fn) fn() end,
		ContinueOnAddOnLoaded = function(name, fn)
			loaded[name] = fn
		end,
	},
	TooltipDataProcessor = {
		-- Kept by tooltip type: the reagent scene draws an item tooltip, so only the item post-calls run on it.
		AddTooltipPostCall = function(kind, fn)
			postCalls[kind] = postCalls[kind] or {}
			table.insert(postCalls[kind], fn)
		end,
	},
	GameTooltip_AddBlankLineToTooltip = function(tooltip)
		AddLine(tooltip, " ")
	end,
	GameTooltip_AddColoredLine = function(tooltip, text, color)
		AddLine(tooltip, text, color)
	end,
	GameTooltip_AddNormalLine = function(tooltip, text)
		AddLine(tooltip, text, env.NORMAL_FONT_COLOR)
	end,
	GameTooltip_AddDisabledLine = function(tooltip, text)
		AddLine(tooltip, text, env.DISABLED_FONT_COLOR)
	end,
	IsShiftKeyDown = function()
		return false
	end,
	UnitLevel = function()
		return STATE.level
	end,
	GetBuildInfo = function()
		return "1.60.1", "70205", "Sep 24 2026", 16001
	end,
	-- The screenshots are of the English client: every translation file returns at its guard.
	GetLocale = function()
		return "enUS"
	end,
	UnitName = function()
		return "Player"
	end,
	UnitClass = function()
		return "Rogue", "ROGUE", 4
	end,
	C_SkillInfo = {
		GetNumSkillLines = function()
			return 0
		end,
	},
	C_PaperDollInfo = {
		GetInventorySlotInfo = function(name)
			return nil, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name:gsub("Slot$", "")
		end,
	},
	GetNormalizedRealmName = function()
		return "Realm"
	end,
	GetMoney = function()
		return STATE.money
	end,
	GetProfessions = function()
		return unpack(STATE.professionIndices)
	end,
	GetProfessionInfo = function(index)
		local p = STATE.professions[index]
		return p.name, p.icon, p.rank, p.max, nil, nil, p.skillLine, 0
	end,
	Professions = {
		GetProfessionInfo = function()
			return {
				professionName = STATE.open.name,
				professionID = STATE.open.skillLine,
				skillLevel = STATE.open.rank,
				maxSkillLevel = STATE.open.max,
				skillModifier = 0,
				displayName = STATE.open.name,
			}
		end,
	},
	C_AddOns = {
		GetAddOnMetadata = function()
			return "@project-version@"
		end,
	},
	C_CurrencyInfo = {
		GetCoinTextureString = function(copper)
			return "{coin:" .. copper .. "}"
		end,
	},
	C_Item = {
		GetItemNameByID = function(itemID)
			return "{item:" .. itemID .. "}"
		end,
		GetItemIconByID = function(itemID)
			return "item:" .. itemID
		end,
		GetItemQualityByID = function() end,
		GetItemQualityColor = function()
			return 1, 1, 1
		end,
		GetItemCount = function(itemID)
			return STATE.bags[itemID] or 0
		end,
		GetItemInfo = function() end,
		RequestLoadItemDataByID = function() end,
	},
	C_Spell = {
		GetSpellName = function(spellID)
			return spellNames[spellID]
		end,
		GetSpellTexture = function() end,
	},
	C_SpellBook = {
		IsSpellKnown = function(spellID)
			return learned[spellID] == true
		end,
	},
	C_TradeSkillUI = {
		GetRecipeSchematic = function() end,
		GetBaseProfessionInfo = function()
			return { professionName = STATE.open.name, professionID = STATE.open.skillLine }
		end,
		IsTradeSkillLinked = function()
			return false
		end,
		IsTradeSkillGuild = function()
			return false
		end,
		GetAllRecipeIDs = function()
			return {}
		end,
	},
	Auctionator = {
		API = {
			v1 = {
				GetAuctionPriceByItemID = function(_, itemID)
					return STATE.auction[itemID]
				end,
				GetAuctionAgeByItemID = function()
					return 0
				end,
				CreateShoppingList = function() end,
				ConvertToSearchString = function() end,
				RegisterForDBUpdate = function() end,
			},
		},
	},
	C_Texture = {
		GetAtlasInfo = function(atlas)
			return STATE.atlases[atlas]
		end,
	},
	C_Trainer = {
		GetTrainerType = function()
			return 1
		end,
	},
	C_TooltipInfo = {
		GetTrainerService = function(index)
			return { id = STATE.services[index].recipeID }
		end,
	},
	GetNumTrainerServices = function()
		return #STATE.services
	end,
	GetTrainerServiceInfo = function(index)
		local service = STATE.services[index]
		return spellNames[service.recipeID], service.kind
	end,
	GetTrainerServiceCost = function(index)
		return STATE.services[index].fee
	end,
	GetTrainerServiceSkillReq = function(index)
		local service = STATE.services[index]
		return STATE.open.name, service.req, STATE.open.rank >= service.req
	end,
	GetTrainerTradeskillRankValues = function()
		return STATE.open.rank, STATE.open.max, 0
	end,
	GetTrainerServiceStepIndex = function() end,
	-- The frames the addon hooks: anything it touches is a recording stub.
	ProfessionsFrame = Stub(),
	MerchantFrame = Stub(),
	ClassTrainerFrame = Stub(),
	ObjectiveTrackerManager = setmetatable({}, { __index = function() error("native tracker manager accessed") end }),
	ObjectiveTrackerFrame = Stub(),
	UIParent = Stub(),
	GameTooltip = Stub(),
	DEFAULT_CHAT_FRAME = Stub(),
	Settings = Stub(),
	CreateSettingsButtonInitializer = function()
		return function() end
	end,
	MinimalSliderWithSteppersMixin = { Label = { Right = "right" } },
	MenuUtil = Stub(),
	SkillUpForeverDB = {
		trackedProfessions = { [STATE.open.skillLine] = true },
		collectModes = {},
		showGearTab = true,
	},
	-- The optional databases the addon reads through their public tables: absent in this scene.
	AtlasLoot = false,
	LibQuestieDB = false,
	-- No other Forever addon has loaded UI/ForeverFamily.lua: this copy sets the global.
	ForeverFamily = false,
}, {
	__index = function(_, key)
		local value = _G[key]
		if value == nil then
			io.stderr:write("harness: unknown global " .. tostring(key) .. "\n")
		end
		return value
	end,
})

-- This renderer exercises Shopping.LayoutContents; native ownership is covered by tracker_host_spec.
local ns = { TrackerHost = {
	Attach = function(module) module.parentContainer = {} end,
	IsAttached = function(module) return module.parentContainer ~= nil end,
} }
env.ForeverTrackerHost = ns.TrackerHost
for _, file in ipairs(FILES) do
	setfenv(assert(loadfile(file)), env)(ADDON, ns)
end
for _, names in pairs(ns.RecipeNames) do
	for name, recipeID in pairs(names) do
		if recipeID then
			spellNames[recipeID] = name
		end
	end
end
env.C_TradeSkillUI.GetCraftableCount = function(recipeID)
	local count
	for _, reagent in ipairs(ns.RecipeData[recipeID].reagents) do
		local n = math.floor((STATE.bags[reagent.itemID] or 0) / reagent.quantity)
		count = math.min(count or n, n)
	end
	return count or 0
end

-- The addon's own start-up (LoadDB and the attaches), minus the recipe list.
loaded[ADDON]()
ns.NearestTrainer = function() end
ns.NearestVendor = function() end

-- ---------------------------------------------------------------------------------------------- output

local function Rgb(color)
	return color and { color.r, color.g, color.b } or nil
end

local function Json(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" or kind == "number" then
		return tostring(value)
	elseif kind == "string" then
		return '"' .. value:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	if #keys == 0 then
		return "[]"
	end
	local parts = {}
	if #value == #keys then
		for _, item in ipairs(value) do
			parts[#parts + 1] = Json(item)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	for _, key in ipairs(keys) do
		parts[#parts + 1] = Json(tostring(key)) .. ":" .. Json(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- The route page: the lists record their rows; the page's own frames record the rest.
local lists = {}
ns.CreateList = function()
	local list = { rows = {}, scrollBox = Stub() }
	function list:Begin()
		self.rows = {}
	end
	function list:Heading(text)
		self.rows[#self.rows + 1] = { kind = "heading", text = text }
	end
	function list:Message(text, color)
		self.rows[#self.rows + 1] = { kind = "message", text = text, color = Rgb(color) }
	end
	function list:Add(entry)
		self.rows[#self.rows + 1] = {
			kind = "row",
			icon = entry.icon,
			iconColor = Rgb(entry.iconColor),
			text = entry.text,
			color = Rgb(entry.color),
			detail = entry.detail,
			detailColor = Rgb(entry.detailColor),
		}
	end
	function list:Finish() end
	lists[#lists + 1] = list
	return list
end
local first = #created + 1
ns.AttachRoute()
assert(not hooks.RefreshRightTabs and not hooks.RightTabSelected, "native profession methods stay untouched")
local page = created[first]
local routeTab = created[#created] -- the route page's side tab, before the gear page creates its own
local gearFirst = #created + 1
ns.AttachGear()
local gearPage = created[gearFirst]
routeTab.scripts.OnMouseUp(nil, "LeftButton", true)
local function Widget(frame)
	return {
		text = rawget(frame, "text"),
		color = rawget(frame, "color"),
		enabled = rawget(frame, "enabled"),
		shown = rawget(frame, "shown"),
		width = rawget(frame, "width"),
		checked = rawget(frame, "checked"),
	}
end
local route = {
	portrait = rawget(env.ProfessionsFrame, "portrait"),
	skill = Widget(page.Skill),
	target = Widget(page.Target),
	craft = Widget(page.Craft),
	track = Widget(page.Track),
	collect = Widget(page.Collect),
	collectLabel = Widget(page.CollectLabel),
	vendor = Widget(page.Vendor),
	lists = {},
}
for _, list in ipairs(lists) do
	route.lists[#route.lists + 1] = { rows = list.rows }
end

-- The tracker: its module lays out blocks of objectives.
local module = named.SkillUpForeverObjectiveTracker
local blocks = {}
local tracker = { header = module.headerText, blocks = blocks }
module.LayoutContents({
	GetBlock = function()
		local block = { lines = {} }
		function block:SetHeader(text)
			self.header = text
		end
		function block:AddObjective(_, text, _, _, dashStyle, color)
			self.lines[#self.lines + 1] = { text = text, dash = dashStyle ~= 2, color = Rgb(color) }
		end
		blocks[#blocks + 1] = block
		return block
	end,
	LayoutBlock = function()
		return true
	end,
})
for _, block in ipairs(blocks) do
	for key in pairs(block) do
		if key ~= "header" and key ~= "lines" then
			block[key] = nil
		end
	end
end

-- The trainer: what an Apprentice trainer lists under the default filter (available and unavailable, the
-- learned ones hidden), by required skill; every service button, decorated after the addon's rebuild.
STATE.services = {}
for recipeID, training in pairs(ns.TrainerFees) do
	local recipe = ns.RecipeData[recipeID]
	local taught = recipe and recipe.skillLine == STATE.open.skillLine and training[2] < STATE.open.max
	if taught and not learned[recipeID] then
		local kind = training[2] <= STATE.open.rank and "available" or "unavailable"
		STATE.services[#STATE.services + 1] = { recipeID = recipeID, fee = training[1], req = training[2], kind = kind }
	end
end
table.sort(STATE.services, function(a, b)
	if a.req ~= b.req then
		return a.req < b.req
	end
	return spellNames[a.recipeID] < spellNames[b.recipeID]
end)
local buttons = {}
for index, service in ipairs(STATE.services) do
	-- ClassTrainerSkillButtonTemplate, with the "Requires:" line as wide as the renderer measures it.
	local button, subText = Stub(), Stub()
	subText.GetStringWidth = function()
		return STATE.requirementWidths[service.req + 1]
	end
	subText.GetWidth = function()
		return 240
	end
	button.GetWidth = function()
		return 298
	end
	rawset(button, "subText", subText)
	buttons[index] = button
end
rawset(env.ClassTrainerFrame, "shown", true)
env.ClassTrainerFrame.ScrollBox.ForEachFrame = function(_, fn)
	for index, button in ipairs(buttons) do
		button.GetElementData = function()
			return { skillIndex = index }
		end
		fn(button)
	end
end
ns.AttachTrainer()
hooks.ClassTrainerFrame_Update()
local trainer = {}
for index, button in ipairs(buttons) do
	local service = STATE.services[index]
	local text = rawget(button, "SkillUpText")
	trainer[index] = {
		recipeID = service.recipeID,
		name = spellNames[service.recipeID],
		kind = service.kind,
		fee = service.fee,
		req = service.req,
		skillUp = text and Widget(text) or nil,
	}
end

-- The reagent's item tooltip: what the post-call adds.
local tooltip = Stub()
for _, fn in ipairs(postCalls[env.Enum.TooltipDataType.Item] or {}) do
	fn(tooltip, { id = STATE.tooltipItem })
end
local reagent = {}
for _, line in ipairs(TooltipLines(tooltip)) do
	reagent[#reagent + 1] = { left = line.left, color = Rgb(line.color) }
end

-- The crafted gear page: its doll and detail pane, after its tab is selected. The slot's pick and every
-- row is the addon's own listing rule, read back from the frames it filled.
ns.GearTab.scripts.OnMouseUp(nil, "LeftButton", true)
gearPage.Slots[STATE.gearSelected].scripts.OnClick()

local function GearItem(item)
	if not item then
		return nil
	end
	return {
		recipeID = item.recipeID,
		itemID = item.itemID,
		skill = item.skill,
		level = item.level,
		profession = item.profession,
		state = item.state,
	}
end

local function GearRow(row)
	return {
		shown = rawget(row, "shown") == true,
		icon = rawget(row.Icon, "texture"),
		text = rawget(row.Text, "text"),
		detail = rawget(row.Detail, "text"),
	}
end

local gear = {
	showAll = rawget(gearPage.ShowAll, "checked") == true,
	showAllLabel = rawget(gearPage.ShowAllLabel, "text"),
	slots = {},
	reagents = {},
	others = {},
	detail = {},
}
for index, button in ipairs(gearPage.Slots) do
	gear.slots[index] = {
		checked = rawget(button, "checked") == true,
		selected = rawget(button.select, "shown") == true,
		mark = rawget(button.mark, "shown") == true,
		icon = rawget(button.icon, "texture"),
		borderShown = rawget(button.border, "shown") == true,
		item = GearItem(rawget(button, "item")),
	}
end
local detail = gearPage.Detail
gear.detail = {
	name = rawget(detail.Name, "text"),
	requirement = rawget(detail.Requirement, "text"),
	learn = rawget(detail.Learn, "text"),
	state = rawget(detail.State, "text"),
	reagentsShown = rawget(detail.Reagents, "shown") == true,
	action = { text = rawget(detail.Action, "text"), enabled = rawget(detail.Action, "enabled") == true },
	alsoShown = rawget(detail.Also, "shown") == true,
	empty = rawget(detail.Empty, "text"),
	emptyShown = rawget(detail.Empty, "shown") == true,
	bodyShown = rawget(detail.Body, "shown") == true,
	icon = rawget(detail.Icon, "texture"),
}
for _, row in ipairs(detail.ReagentRows) do
	gear.reagents[#gear.reagents + 1] = GearRow(row)
end
for _, row in ipairs(detail.OtherRows) do
	gear.others[#gear.others + 1] = GearRow(row)
end

io.write(Json({ route = route, tracker = tracker, trainer = trainer, reagent = reagent, gear = gear }))
"""


def to_lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, dict):
        return "{" + ", ".join(f"[{to_lua(k)}] = {to_lua(v)}" for k, v in value.items()) + "}"
    return "{" + ", ".join(to_lua(v) for v in value) + "}"


def requirement_text(req):
    """The service button's subText: REQUIRES_LABEL and TRAINER_REQ_SKILL_RANK(_RED) from GlobalStrings."""
    number = "ffffff" if SKILL >= req else "ff2020"
    return f"Requires: Leatherworking (|cff{number}{req}|r)"


def addon_atlases(ui):
    """{name: {width, height}} for every atlas the addon's Lua names, as C_Texture.GetAtlasInfo gives them."""
    names = set(ui.table("UiTextureAtlasElement", key="Name"))
    literals = set()
    for folder in ("Core", "Integrations", "UI"):
        for path in (REPO / folder).glob("*.lua"):
            literals.update(re.findall(r'"([A-Za-z][\w-]*)"', path.read_text(encoding="utf-8")))
    return {name: {"width": ui.atlas(name).width, "height": ui.atlas(name).height} for name in sorted(literals & names)}


def lua_scene(ui):
    """What the route page, tracker, trainer and reagent tooltip draw for the scene's character."""
    canvas = ui.canvas(1, 1)
    professions = [
        {"name": name, "icon": icon, "rank": rank, "max": top, "skillLine": line}
        for name, icon, rank, top, line in PROFESSIONS
    ]
    state = {
        "level": LEVEL,
        "money": MONEY,
        "learned": LEARNED,
        "bags": BAGS,
        "auction": AUCTION,
        "professions": professions,
        "professionIndices": list(range(1, len(professions) + 1)),
        "open": {"name": "Leatherworking", "skillLine": 165, "rank": SKILL, "max": MAX_SKILL},
        "gearSelected": GEAR_SELECTED,
        "tooltipItem": TOOLTIP_ITEM,
        "atlases": addon_atlases(ui),
        "colors": COLORS,
        "disabledColor": DISABLED_FONT_COLOR,
        # What subText:GetStringWidth() gives for each required skill, 0 up.
        "requirementWidths": [canvas.text_width(requirement_text(req), F_SHADOW_SMALL) for req in range(MAX_SKILL + 1)],
    }
    source = f"local STATE = {to_lua(state)}\n{LUA_SCENE}"
    result = subprocess.run(["luajit", "-"], input=source, capture_output=True, text=True, cwd=REPO, check=False)
    if result.returncode != 0 or result.stderr:
        sys.exit(f"the Lua scene failed:\n{result.stderr}")
    return json.loads(result.stdout)


# ------------------------------------------------------------------------------------------------ render

from PIL import Image, ImageOps
from wowmock import (
    FONTS,
    INSET_FRAME_LAYOUT,
    NORMAL,
    QUALITY_TEXT,
    TOOLTIP_LINE_GAP,
    TOOLTIP_PADDING,
    WHITE,
    Font,
    TooltipLine,
    TrackerBlock,
    TrackerModule,
    Ui,
    backdrop,
    coin_texture_string,
    crop_coords,
    draw_money,
    filter_dropdown,
    minimal_checkbox,
    minimal_scrollbar,
    money_width,
    objective_tracker,
    portrait_frame_art,
    scene,
    search_box,
    side_tab,
    three_slice_button,
    tiled,
    tooltip,
    ui_panel_button,
    wrap_text,
)

from gen_thresholds import BUILD

FRIZ = "fonts/frizqt__.ttf"
ARIAL = "fonts/arialn.ttf"
F_ROW = Font(FRIZ, 12, WHITE)  # GameFontHighlight_NoShadow
F_DIVIDER = Font(FRIZ, 12, NORMAL)  # GameFontNormal_NoShadow
F_NORMAL = FONTS["GameFontNormal"]
F_SMALL = FONTS["GameFontHighlightSmall"]
F_NORMAL_SMALL = FONTS["GameFontNormalSmall"]
F_RANK = Font(ARIAL, 12, WHITE, None, True)  # Number12FontOutline
F_SMALL2 = Font(FRIZ, 11, WHITE)  # GameFontHighlightSmall2
F_MED2 = Font(FRIZ, 14, WHITE, (1, -1))  # GameFontHighlightMed2
PROFESSION_RECIPE_COLOR = (226 / 255, 220 / 255, 214 / 255)
DISABLED_FONT_COLOR = (0.5, 0.5, 0.5)

FRAME_W, FRAME_H = 673, 594  # Camelot ProfessionsFrame
LIST_X, LIST_Y, LIST_W = 5, 72, 304  # CraftingPage.RecipeList (OverrideArt width)
LIST_H = FRAME_H - LIST_Y - 5
ROW_H, ROW_GAP, ROW_PAD = 20, 1, 5  # recipe rows; the tree view's spacing and top padding
DIVIDER_H = 70  # RecipeList.lua: the "Unlearned" divider after learned recipes
SCHEMATIC_W, SCHEMATIC_H = 360, 484
SKILL_UP_ICONS = {
    "orange": "Professions-Icon-Skill-High",
    "yellow": "Professions-Icon-Skill-Medium",
    "green": "Professions-Icon-Skill-Low",
}

SELECTED = 1229432  # Camp Tent
HOVERED = 9059  # Handstitched Leather Bracers
GEAR_SELECTED = 8  # Waist: the gear page's detail pane shows the Handstitched Leather Belt


# GetCoinTextureString asks for 14-unit coins, but in the real captures they come out the height of the
# 12-unit text around them (coin ink 11 px at UI scale 1.2), so draw them at the line's height.
COIN_HEIGHT = 12


def money(copper):
    """UI/Tooltip.lua Money: GetCoinTextureString of the rounded amount."""
    return coin_texture_string(math.floor(copper + 0.5), COIN_HEIGHT)


def format_row(d):
    """Core/Core.lua ns.FormatRow with the default settings (showSkill off, showCost on)."""
    if not d["thresholds"]:
        return "?"
    if d["chance"] is None:
        return str(d["thresholds"][0])
    parts = [f"{math.floor(d['chance'] * 100 + 0.5)}%"]
    if d["perSkillUp"] is not None:
        per = d["perSkillUp"]
        parts.append(("|cff40ff40+|r" if per < 0 else "") + coin_texture_string(round_money(abs(per)), COIN_HEIGHT))
    return " · ".join(parts)


def source_text(p):
    """UI/Tooltip.lua ns.PriceSourceText, for an Auctionator price seen today."""
    if p["source"] == "gather":
        return f"you gather it ({p['profession']})"
    return "vendor" if p["source"] == "vendor" else "Auctionator, today"


def recipe_tooltip_lines(ui, recipe_id):
    """UI/Tooltip.lua ShowRecipeTooltip + AddCost for a learned recipe at SKILL. Returns the lines and the index
    of the first blank line AddBar added for the bar."""
    d = describe(recipe_id)
    t = d["thresholds"]
    lines = [
        TooltipLine(recipe_name(recipe_id)),
        TooltipLine(f"Skill range starts at {t[0]}", COLORS["red"] if SKILL < t[0] else WHITE),
    ]
    bar_line = len(lines)
    lines += [TooltipLine(" ")] * bar_blank_lines()
    lines.append(TooltipLine(f"Skill-up chance: {math.floor(d['chance'] * 100 + 0.5)}%", COLORS[d["color"]]))
    lines.append(TooltipLine(" "))
    gold = (1, 0.82, 0)
    for reagent in reagents(recipe_id):
        name = ui.item(reagent["itemID"]).name
        left = f"{name} x{reagent['quantity']}" if reagent["quantity"] > 1 else name
        p = price(reagent["itemID"])
        right = "{} |cff808080({})|r".format(money(p["copper"] * reagent["quantity"]), source_text(p))
        lines.append(TooltipLine(left, right=right))
    lines.append(TooltipLine("Reagents", gold, money(d["cost"])))
    value, net = d["value"], d["net"]
    if value and net is not None:
        each = " x{:g}".format(value["quantity"]) if value["quantity"] != 1 else ""
        source = "AH" if value["source"] == "auction" else "vendor"
        lines.append(
            TooltipLine("Sells for" + each, gold, "{} |cff808080({})|r".format(money(value["copper"]), source))
        )
        lines.append(TooltipLine("Profit per craft" if net < 0 else "Net per craft", gold, money(abs(net))))
    per = d["perSkillUp"]
    if per is not None:
        lines.append(
            TooltipLine(
                "Profit per skill-up" if per < 0 else "Per skill-up",
                gold,
                ("|cff40ff40+|r" if per < 0 else "") + money(abs(per)),
            )
        )
    return lines, bar_line


BAR_WIDTH, MIN_LABEL_GAP = 250, 18  # UI/Tooltip.lua
BAR_SCALE = BAR_WIDTH / 439
BAR_HEIGHT = 18 * BAR_SCALE
BAR_FRAME_HEIGHT = BAR_HEIGHT + 30
BAR_PADDING = 4  # UI/Tooltip.lua BAR_PADDING


def bar_blank_lines():
    """UI/Tooltip.lua BAR_LINES: enough blank GameTooltipText lines to hold the frame and its padding."""
    text_height = FONTS["GameTooltipText"].height
    return math.ceil(round(BAR_FRAME_HEIGHT + BAR_PADDING) / (text_height + TOOLTIP_LINE_GAP))


def skill_bar(ui, t, skill):
    """UI/Tooltip.lua CreateBar + LayoutBar: the rank-bar art at tooltip size, the difficulty bands, threshold
    labels and the pip at the player's skill. Returns a canvas with the frame's TOPLEFT at (m, m)."""
    m = 8
    canvas = ui.canvas(BAR_WIDTH + 2 * m, BAR_FRAME_HEIGHT + 2 * m)
    s = BAR_SCALE
    canvas.draw(ui.atlas("Professions-skillbar-bg"), m - 5 * s, m - 3 * s, 451 * s, 29 * s)
    lo, hi = t[0], t[3] + max(3, math.floor((t[3] - t[0]) * 0.12 + 0.5))

    def x_of(value):
        return (min(max(value, lo), hi) - lo) / (hi - lo) * BAR_WIDTH

    band = ui.texture("interface/targetingframe/ui-statusbar.blp")
    edges = [t[0], t[1], t[2], t[3], hi]
    for i, color in enumerate(("orange", "yellow", "green", "grey")):
        left, right = x_of(edges[i]), x_of(edges[i + 1])
        if right > left:
            canvas.draw(band, m + left, m, max(right - left, 0.1), BAR_HEIGHT, COLORS[color])
    canvas.draw(ui.atlas("Professions-skillbar-frame"), m - 5 * s, m - 3 * s, 451 * s, 29 * s)
    marker_h = BAR_HEIGHT * 1.3
    marker_w = marker_h * 10 / 14
    mx = x_of(skill)
    canvas.draw(
        ui.atlas("ui-hud-experiencebar-frame-pip-camelot"),
        m + mx - marker_w / 2,
        m + BAR_HEIGHT / 2 - marker_h / 2,
        marker_w,
        marker_h,
    )
    last = -math.inf
    for i, value in enumerate(t):
        x = x_of(value)
        if x - last < MIN_LABEL_GAP:
            continue
        last = x
        width = canvas.text_width(str(value), F_SMALL)
        left = 0 if i == 0 else x - width / 2
        canvas.text(m + left, m + BAR_HEIGHT + 4, str(value), F_SMALL)
    you = f"You: {skill}"
    centre = min(max(mx, 24), BAR_WIDTH - 24)
    canvas.text(m + centre - canvas.text_width(you, F_SMALL) / 2, m + BAR_HEIGHT + 16, you, F_SMALL)
    return canvas, m


def recipe_tooltip(ui, recipe_id):
    lines, bar_line = recipe_tooltip_lines(ui, recipe_id)
    canvas = tooltip(ui, lines)
    fonts = [FONTS["GameTooltipHeaderText"]] + [FONTS["GameTooltipText"]] * (len(lines) - 1)
    top = TOOLTIP_PADDING + sum(f.height + TOOLTIP_LINE_GAP for f in fonts[:bar_line])
    bar, m = skill_bar(ui, describe(recipe_id)["thresholds"], SKILL)
    canvas.paste(bar, TOOLTIP_PADDING - m, top + BAR_PADDING - m)
    return canvas


def list_rows():
    """The recipe list's rows top to bottom: ("recipe", id, learned) and ("divider", None, False)."""
    learned, unlearned = sorted_recipes()
    rows = [("recipe", rid, True) for rid in learned]
    if unlearned:
        rows.append(("divider", None, False))
        rows += [("recipe", rid, False) for rid in unlearned]
    return rows


def recipe_row(canvas, x, y, w, recipe_id, learned, selected, hovered):
    """ProfessionsRecipeListRecipeTemplate (20 high) at (x, y, w) with SkillUp's text on its right."""
    ui = canvas.ui
    d = describe(recipe_id)
    icon_atlas = SKILL_UP_ICONS.get(d["color"])
    skill_ups_y = y + (ROW_H - 15) / 2 - (1 if d["color"] == "orange" else 0)
    if icon_atlas:
        icon = ui.atlas(icon_atlas)
        # SkillUps (26x15) at LEFT (-9, yOfs); its icon at RIGHT (0, -1), atlas size.
        canvas.draw(icon, x - 9 + 26 - icon.width, skill_ups_y + (15 - icon.height) / 2 + 1)
    label_x = x - 9 + 26 + 4
    color = WHITE if hovered else (PROFESSION_RECIPE_COLOR if learned else DISABLED_FONT_COLOR)
    label_w = canvas.text(label_x, y, recipe_name(recipe_id), F_ROW, color, box_height=ROW_H)
    count = craftable_count(recipe_id) if learned else 0
    if count > 0:
        canvas.text(label_x + label_w, y, f" [{count}] ", F_ROW, color, box_height=ROW_H)
    text = format_row(d)
    canvas.text(x, y, text, F_ROW, row_color(d), box_height=ROW_H, justify="RIGHT", width=w - 4)
    if selected:
        overlay = ui.atlas("Professions_Recipe_Active")
        canvas.draw(overlay, x + (w - overlay.width) / 2, y + (ROW_H - overlay.height) / 2 + 1)
    if hovered:
        overlay = ui.atlas("Professions_Recipe_Hover")
        canvas.draw(overlay, x + (w - overlay.width) / 2, y + (ROW_H - overlay.height) / 2 + 1, color=(1, 1, 1, 0.5))


def divider_row(canvas, x, y):
    """ProfessionsRecipeListDividerTemplate at SkillUp's height: "Unlearned" and the gold rule."""
    ui = canvas.ui
    bottom = y + DIVIDER_H
    canvas.text(x + 10, bottom - 10 - 13, "Unlearned", F_DIVIDER, box_height=13)
    rule = ui.atlas("Options_HorizontalDivider")
    canvas.draw(rule, x + 5, bottom - 5 - 2, 250, 2, NORMAL)
    canvas.draw(rule, x + 5, bottom - 5 - 2, 250, 2, (*NORMAL, 0.5), blend="ADD")


def recipe_list(canvas, x, y):
    """CraftingPage.RecipeList at (x, y). Returns the hovered row's rect."""
    ui = canvas.ui
    canvas.draw(ui.atlas("Professions-background-summarylist"), x, y, LIST_W, LIST_H)
    filter_x, _, _, _ = filter_dropdown(canvas, x + LIST_W - 8, y + 9)
    search_box(canvas, x + 13, y + 8, filter_x - 4 - (x + 13))
    box_x, box_y, box_w = x + 8, y + 35, LIST_W - 8 - 20
    minimal_scrollbar(canvas, box_x + box_w, box_y, LIST_H - 35 - 5)
    top = box_y + ROW_PAD
    hovered_rect = None
    for row in list_rows():
        kind, rid, learned = row
        if kind == "divider":
            divider_row(canvas, box_x, top)
            top += DIVIDER_H + ROW_GAP
            continue
        recipe_row(canvas, box_x, top, box_w, rid, learned, rid == SELECTED, rid == HOVERED)
        if rid == HOVERED:
            hovered_rect = (box_x, top, box_w, ROW_H)
        top += ROW_H + ROW_GAP
    return hovered_rect


def rank_bar(canvas, x, y, name, skill, max_skill):
    """ProfessionsRankBarTemplate at (x, y): the profession's fill flipbook (first frame) masked to the
    progress, border, "Name skill/max" and the crafting page's chat-link button."""
    ui = canvas.ui
    canvas.draw(ui.atlas("Professions-skillbar-bg"), x, y)
    fill = ui.atlas("Skillbar_Fill_Flipbook_Leatherworking")
    frame = fill.image.crop((0, 0, fill.image.width // 2, fill.image.height // 30))  # 30 rows x 2 columns
    layer = ui.canvas(canvas.width, canvas.height)
    layer.draw(frame, x + 5, y + 3, 441, 18)
    mask = ui.atlas("Professions-skillbar-mask")
    mask_w = 453 * skill / max_skill
    layer.mask(mask.image, x + 5 + 1, y + 3 + 9 - mask.height / 2, mask_w, mask.height)
    canvas.paste(layer, 0, 0)
    canvas.draw(ui.atlas("Professions-skillbar-frame"), x, y, 451, 29)
    canvas.text(x, y + 3, f"{name} {skill}/{max_skill}", F_RANK, justify="CENTER", width=453, box_height=18)
    # The ExpansionDropdownButton hides itself with a single child profession, as on Forever. The crafting
    # page's LinkButton (23x23) sits at the bar's RIGHT (-2, -4): the tertiary square with the chat-link icon.
    bx, by = x + 453 - 2, y + 9 + 4 - 23 / 2
    background = ui.atlas("common-button-tertiary-square-normal")
    canvas.draw(background, bx + (23 - background.width) / 2, by + (23 - background.height) / 2)
    # The -2x member's override (50) is in 2x canvas units; the 1x member's is the real 25.
    canvas.draw(ui.atlas("common-icon-chatlink"), bx - 1, by - 1, 25, 25)


def schematic(canvas, x, y, recipe_id):
    """SchematicFormCraftingTemplate (Camelot, 360 wide) for a recipe: card art, the output icon and name,
    description, reagent slots, Track Recipe."""
    ui = canvas.ui
    data = NS["RecipeData"][recipe_id]
    canvas.draw(ui.atlas("Profession-background-card-leatherworking"), x, y, SCHEMATIC_W, SCHEMATIC_H)
    canvas.draw(ui.atlas("common-insideframe"), x, y, SCHEMATIC_W, SCHEMATIC_H)
    # OutputIcon (47x47) at (28, -28); Camelot's 53x53 icon centred, masked round, the quality ring over it.
    ox, oy = x + 28, y + 28
    item = ui.item(data["output"]["itemID"])
    layer = ui.canvas(canvas.width, canvas.height)
    layer.draw(
        crop_coords(ui.texture(item.icon), 0.078125, 0.921875, 0.078125, 0.921875),
        ox + 23.5 - 26.5,
        oy + 23.5 - 26.5,
        53,
        53,
    )
    layer.mask(
        ui.texture("interface/characterframe/tempportraitalphamask.blp"),
        ox + 23.5 - 26.5 + 2,
        oy + 23.5 - 26.5 + 2,
        49,
        49,
    )
    canvas.paste(layer, 0, 0)
    ring = ui.atlas("auctionhouse-itemicon-border-white")
    canvas.draw(ring, ox + 23.5 - 34, oy + 23.5 - 34, 68, 68)
    name_x = ox + 47 + 14
    name_w = canvas.text(name_x, oy + 23.5 - 17 - F_MED2.height / 2, item.name, F_MED2)
    fav = ui.atlas("auctionhouse-icon-favorite")
    canvas.draw(fav, name_x + name_w + 4, oy + 23.5 - 17 - 9 - 1, 20, 18, (1, 1, 1, 0.5))
    description_y = oy + 47 + 12
    canvas.text(ox - 1, description_y, f"Craft a {item.name}.", F_SMALL2)
    # Init re-anchors the reagents: TOPLEFT at the description's BOTTOMLEFT (0, -20); the label is 20 high
    # and the slots start at (1, -20).
    rx, ry = ox - 1, description_y + F_SMALL2.height + 20
    canvas.text(rx, ry, "Reagents:", F_NORMAL_SMALL, box_height=20)
    sx, sy = rx + 1, ry + 20
    for reagent in reagents(recipe_id):
        reagent_slot(canvas, sx, sy, reagent)
        sx += 180 + 5
    minimal_checkbox(canvas, x + 17, y + SCHEMATIC_H - 11 - 26, "Track Recipe", color=DISABLED_FONT_COLOR)


def reagent_slot(canvas, x, y, reagent):
    """ProfessionsReagentSlotTemplate (180x50): the 39x39 button at LEFT and "have/need Name" beside it."""
    ui = canvas.ui
    item = ui.item(reagent["itemID"])
    bx, by = x, y + (50 - 39) / 2
    canvas.draw(ui.atlas("Professions-Slot-bg"), bx, by, 39, 39)
    canvas.draw(ui.texture(item.icon), bx, by, 39, 39)
    canvas.draw(ui.atlas("Professions-Slot-Frame"), bx, by, 40, 40)
    text = f"{BAGS.get(reagent['itemID'], 0)}/{reagent['quantity']} {item.name}"
    # The Name box is 108 wide, but the client wraps "23/5 Light Leather" (105.5-106.7 units by our metrics,
    # depending on the render scale) in it, so it keeps some slack at the right edge.
    lines = wrap_text(canvas, text, F_ROW, 108 - 4)
    top = y + 25 - len(lines) * F_ROW.height / 2
    for i, line in enumerate(lines):
        canvas.text(x + 46, top + i * F_ROW.height, line, F_ROW)


def create_controls(canvas, fx, fy, count):
    """CraftingPage's bottom row, Camelot anchors: Create All, the quantity spinner, Create."""
    ui = canvas.ui
    right, bottom = fx + FRAME_W, fy + FRAME_H
    all_text = f"Create All [{count}]"
    all_w = max(80, canvas.text_width(all_text, F_NORMAL) + 30)
    three_slice_button(canvas, right - 362, bottom - 7 - 28, all_w, 28, all_text)
    create_w = max(80, canvas.text_width("Create", F_NORMAL) + 30)
    three_slice_button(canvas, right - 9 - create_w, bottom - 7 - 28, create_w, 28, "Create")
    # CreateMultipleInputBox: NumericInputSpinnerTemplate 31x20 at BOTTOMLEFT (-185, 11).
    ix, iy = right - 185, bottom - 11 - 20
    border = ui.texture("interface/common/common-input-border.blp")
    canvas.draw(crop_coords(border, 0, 0.0625, 0, 0.625), ix - 5, iy, 8, 20)
    canvas.draw(crop_coords(border, 0.0625, 0.9375, 0, 0.625), ix + 3, iy, 31 - 8 - 3, 20)
    canvas.draw(crop_coords(border, 0.9375, 1, 0, 0.625), ix + 31 - 8, iy, 8, 20)
    canvas.text(ix, iy, "1", FONTS["GameFontHighlight"], box_height=20)
    canvas.draw(ui.texture("interface/buttons/ui-spellbookicon-nextpage-up.blp"), ix + 31, iy - 1, 23, 22)
    canvas.draw(ui.texture("interface/buttons/ui-spellbookicon-prevpage-up.blp"), ix - 5 - 6 - 23 + 5, iy - 1, 23, 22)


def profession_tabs(canvas, fx, fy, selected, gear_tab=False):
    """The side tabs on the frame's right: overview, one per profession, then SkillUp's route tab ("route")
    and, when that setting is on, its crafted gear tab ("gear") below it."""
    x, y = fx + FRAME_W, fy + 60
    y += side_tab(canvas, x, y, OVERVIEW_TAB_ICON) + 2
    for name, icon, *_ in PROFESSIONS:
        y += side_tab(canvas, x, y, icon, selected=name == selected) + 2
    y += side_tab(canvas, x, y, "interface/icons/inv_scroll_03.blp", selected=selected == "route") + 2
    if gear_tab:
        side_tab(canvas, x, y, "interface/icons/inv_chest_chain_05.blp", selected=selected == "gear")


# The overview tab's Interface/ICONS/INV_SideTab_Professions_c60 is in neither the community listfile nor
# ManifestInterfaceData, so its file data ID is unknown; Trade_BlacksmithingIcon stands in for it.
OVERVIEW_TAB_ICON = 136241

FRAME_MARGIN = 24  # room for the metal corners and portrait around the frame
TABS_MARGIN = 60


def professions_frame(ui):
    """The Leatherworking window at SKILL with SELECTED selected and HOVERED under the cursor. Returns the
    canvas and the hovered row's rect."""
    m = FRAME_MARGIN
    canvas = ui.canvas(FRAME_W + m + TABS_MARGIN, FRAME_H + 2 * m)
    fx, fy = m, m
    canvas.draw(ui.atlas("Profession-Background-Overview"), fx + 2, fy + 21, FRAME_W - 4, FRAME_H - 23)
    canvas.draw(ui.atlas("Profession-Background-Template2"), fx + 3, fy + 21)
    hovered = recipe_list(canvas, fx + LIST_X, fy + LIST_Y)
    schematic(canvas, fx + LIST_X + LIST_W + 2, fy + LIST_Y, SELECTED)
    create_controls(canvas, fx, fy, craftable_count(SELECTED))
    profession_tabs(canvas, fx, fy, "Leatherworking")
    portrait_frame_art(canvas, fx, fy, FRAME_W, FRAME_H, 136247, "Leatherworking")
    rank_bar(canvas, fx + 110, fy + 40, "Leatherworking", SKILL, MAX_SKILL)
    return canvas, hovered


def beside_window(ui):
    """UI/Tooltip.lua's default recipe tooltip place: its TOPLEFT at the overview side tab's TOPRIGHT, (4, 0)."""
    return FRAME_MARGIN + FRAME_W + ui.atlas("common-sidetab").width + 4, FRAME_MARGIN + 60


def window_scene(ui):
    frame, _ = professions_frame(ui)
    tip = recipe_tooltip(ui, HOVERED)
    return scene(ui, [(frame, 0, 0), (tip, *beside_window(ui))])


# ------------------------------------------------------------------------------- scenes from the Lua's output

F_HIGHLIGHT = FONTS["GameFontHighlight"]
F_CHAT = Font(ARIAL, 14, WHITE, (1, -1))  # ChatFontNormal, InputBoxTemplate's font
F_SHADOW_SMALL = Font(FRIZ, 10, NORMAL, (1, -1))  # SystemFont_Shadow_Small


def expand(ui, text):
    """The harness's {coin:N} and {item:N} as the client renders them."""
    text = re.sub(r"\{coin:(\d+)\}", lambda m: coin_texture_string(int(m.group(1)), COIN_HEIGHT), text)
    return re.sub(r"\{item:(\d+)\}", lambda m: ui.item(int(m.group(1))).name, text)


def icon_texture(ui, icon):
    """A list row's icon: a file ID, an "item:N" from GetItemIconByID, or an Interface path."""
    if isinstance(icon, str) and icon.startswith("item:"):
        return ui.texture(ui.item(int(icon[5:])).icon)
    if isinstance(icon, str):
        return ui.texture(icon.replace("\\", "/").lower() + ".blp")
    return ui.texture(icon)


def fit_text(canvas, text, font, width):
    """A one-line FontString cut at `width`, as the client ends it with an ellipsis."""
    if canvas.text_width(text, font) <= width:
        return text
    while text and canvas.text_width(text + "...", font) > width:
        text = text[:-1]
    return text.rstrip() + "..."


def panel_button(canvas, x, y, w, h, text, enabled=True):
    """UIPanelButtonTemplate, enabled (ui_panel_button) or in its Disabled texture with GameFontDisable."""
    if enabled:
        ui_panel_button(canvas, x, y, w, h, text)
        return
    texture = canvas.ui.texture("interface/buttons/ui-panel-button-disabled.blp")
    canvas.draw(crop_coords(texture, 0, 0.09375, 0, 0.6875), x, y, 12, h)
    canvas.draw(crop_coords(texture, 0.09375, 0.53125, 0, 0.6875), x + 12, y, w - 24, h)
    canvas.draw(crop_coords(texture, 0.53125, 0.625, 0, 0.6875), x + w - 12, y, 12, h)
    canvas.text(x, y, text, F_NORMAL, DISABLED_FONT_COLOR, justify="CENTER", width=w, box_height=h)


def inset_frame(canvas, x, y, w, h, title=None):
    """InsetFrameTemplate: the marble Bg 2 units in, tiled, then the inner NineSlice; Route.lua's CreateInset
    puts a GameFontNormal title above its TOPLEFT (4, 4)."""
    marble = canvas.ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, x + 2, y + 2, w - 4, h - 4, 256, 256)
    canvas.nine_slice(INSET_FRAME_LAYOUT, x, y, w, h)
    if title:
        canvas.text(x + 4, y - 4 - F_NORMAL.height, title, F_NORMAL)


LIST_ROW, LIST_HEADING, LIST_ICON, LIST_MESSAGE_MIN, LIST_SCROLLBAR = 46, 26, 37, 20, 18  # List.lua


def draw_list(canvas, x, y, w, h, rows):
    """List.lua's CreateList in an inset at (x, y, w, h): a full item icon in its stock border with
    the name beside it and the facts under it, headings as stock lines and wrapped messages."""
    ui = canvas.ui
    box_x, box_w = x + 4, w - 4 - LIST_SCROLLBAR
    box_y, box_h = y + 4, h - 8
    top = box_y
    for row in rows:
        kind = row.get("kind")
        if kind == "heading":
            canvas.text(box_x + 6, top, expand(ui, row["text"]), F_NORMAL, box_height=LIST_HEADING)
            top += LIST_HEADING
            continue
        if kind == "message":
            lines = wrap_text(canvas, expand(ui, row["text"]), F_NORMAL, box_w - 12)
            color = tuple(row["color"]) if row.get("color") else DISABLED_FONT_COLOR
            for index, line in enumerate(lines):
                canvas.text(box_x + 6, top + 4 + index * F_NORMAL.height, line, F_NORMAL, color)
            top += max(LIST_MESSAGE_MIN, len(lines) * F_NORMAL.height + 8)
            continue
        icon = row.get("icon")
        if icon is not None:
            icon_y = top + (LIST_ROW - LIST_ICON) / 2
            canvas.draw(icon_texture(ui, icon), box_x + 6, icon_y, LIST_ICON, LIST_ICON)
            canvas.draw(ui.atlas("auctionhouse-itemicon-border-white"), box_x + 6, icon_y, LIST_ICON, LIST_ICON)
        text_x = box_x + 6 + LIST_ICON + 8
        text_w = box_x + box_w - 8 - text_x
        canvas.text(
            text_x,
            top + 2,
            fit_text(canvas, expand(ui, row["text"]), F_HIGHLIGHT, text_w),
            F_HIGHLIGHT,
            tuple(row["color"]) if row.get("color") else WHITE,
        )
        detail = row.get("detail")
        if detail:
            detail_color = tuple(row["detailColor"]) if row.get("detailColor") else DISABLED_FONT_COLOR
            canvas.text(
                text_x,
                top + 2 + F_HIGHLIGHT.height + 2,
                fit_text(canvas, expand(ui, detail), F_NORMAL, text_w),
                F_NORMAL,
                detail_color,
            )
        top += LIST_ROW
    if top - box_y > box_h:
        minimal_scrollbar(canvas, box_x + box_w + 4, box_y, box_h, box_h / (top - box_y))


def dropdown(canvas, x, y, w, text):
    """WowStyle1DropdownTemplate (w x 25): common-dropdown-c-button 7 units outside it, the a-button arrow
    at its RIGHT, and the selection in GameFontHighlight from LEFT 9."""
    ui = canvas.ui
    h = 25
    canvas.draw(ui.atlas("common-dropdown-c-button"), x - 7, y - 7, w + 14, h + 14)
    arrow = ui.atlas("common-dropdown-a-button")
    canvas.draw(arrow, x + w - arrow.width + 3, y + (h - arrow.height) / 2)
    canvas.text(x + 9, y - 1, text, F_HIGHLIGHT, box_height=h)
    return h


def input_box(canvas, x, y, w, h, text):
    """InputBoxTemplate: the common-input-border three-slice (Left 8 at -5) and ChatFontNormal text."""
    border = canvas.ui.texture("interface/common/common-input-border.blp")
    canvas.draw(crop_coords(border, 0, 0.0625, 0, 0.625), x - 5, y, 8, h)
    canvas.draw(crop_coords(border, 0.0625, 0.9375, 0, 0.625), x + 3, y, w - 8 - 3, h)
    canvas.draw(crop_coords(border, 0.9375, 1, 0, 0.625), x + w - 8, y, 8, h)
    canvas.text(x, y, text, F_CHAT, box_height=h)


ROUTE_SHARE = 50  # Route.lua


def route_frame(ui, scene_data):
    """The Professions window on SkillUp's route tab: Route.lua's page where the crafting page was."""
    route = scene_data["route"]
    m = FRAME_MARGIN
    canvas = ui.canvas(FRAME_W + m + TABS_MARGIN, FRAME_H + 2 * m)
    fx, fy = m, m
    canvas.draw(ui.atlas("Profession-Background-Overview"), fx + 2, fy + 21, FRAME_W - 4, FRAME_H - 23)
    # Header: the profession dropdown, "Skill  48/75     Target" and the target box.
    dx, dy, dw = fx + 76, fy + 32, 180
    dh = dropdown(canvas, dx, dy, dw, "Leatherworking")
    skill_x = dx + dw + 16
    skill_w = canvas.text(skill_x, dy, route["skill"]["text"], F_NORMAL, box_height=dh)
    input_box(canvas, skill_x + skill_w + 10, dy + (dh - 20) / 2, 40, 20, route["target"]["text"])
    # The switch sits right of the target it changes, in the header row.
    collect = route["collect"]
    minimal_checkbox(
        canvas,
        skill_x + skill_w + 10 + 40 + 16,
        dy + (dh - 22) / 2,
        route["collectLabel"]["text"],
        checked=collect.get("checked", False),
        color=None if collect.get("enabled", True) else DISABLED_FONT_COLOR,
    )
    # The two insets, split ROUTE_SHARE right of centre, each with its list.
    top, bottom = fy + 88, fy + FRAME_H - 44
    route_x, route_right = fx + 16, fx + FRAME_W / 2 + ROUTE_SHARE - 6
    reagents_x, reagents_right = fx + FRAME_W / 2 + ROUTE_SHARE + 6, fx + FRAME_W - 16
    route_list, reagent_list = route["lists"][0], route["lists"][1]
    inset_frame(canvas, route_x, top, route_right - route_x, bottom - top, "Route")
    draw_list(canvas, route_x, top, route_right - route_x, bottom - top, route_list["rows"])
    inset_frame(canvas, reagents_x, top, reagents_right - reagents_x, bottom - top, "Reagents  (have / need)")
    draw_list(canvas, reagents_x, top, reagents_right - reagents_x, bottom - top, reagent_list["rows"])
    # Nearest vendor at the route's BOTTOMLEFT, Craft at its BOTTOMRIGHT; Track at the reagents'
    # BOTTOMRIGHT.
    vendor = route["vendor"]
    if vendor.get("shown"):
        panel_button(canvas, route_x, bottom + 10, 120, 22, vendor["text"], vendor.get("enabled", True))
    craft = route["craft"]
    craft_w = min(canvas.text_width(craft["text"], F_NORMAL) + 32, 240)
    panel_button(canvas, route_right - craft_w, bottom + 10, craft_w, 22, craft["text"], craft["enabled"])
    track = route["track"]
    panel_button(canvas, reagents_right - 130, bottom + 10, 130, 22, track["text"], track.get("enabled", True))
    profession_tabs(canvas, fx, fy, "route")
    portrait_frame_art(canvas, fx, fy, FRAME_W, FRAME_H, route["portrait"], "Leatherworking")
    return canvas


# The crafted gear page: the doll's slot art, the item borders and the detail pane's own numbers.
GEAR_ICON, GEAR_SLOT_GAP, GEAR_ROW_H = 37, 6, 40
GEAR_SLOT_ART = (
    "Head",
    "Neck",
    "Shoulder",
    "Back",
    "Chest",
    "Wrist",
    "Hands",
    "Waist",
    "Legs",
    "Feet",
    "Finger",
    "Trinket",
    "MainHand",
    "SecondaryHand",
    "Ranged",
)
GEAR_LEFT, GEAR_RIGHT, GEAR_BOTTOM = (0, 1, 2, 3, 4, 5), (6, 7, 8, 9, 10, 11), (12, 13, 14)


def gear_quality(ui, item_id):
    """C_Item.GetItemQualityColor: the quality colour the addon tints a slot's border with."""
    return QUALITY_TEXT[ui.item(item_id).quality]


def gear_requirement(subclass_names, item):
    """UI/Gear.lua Requirement: the item's required level and type, from Item/ItemSubClass."""
    kind = subclass_names.get((item.class_id, item.subclass_id))
    if item.required_level <= 0:
        return kind or ""
    if kind:
        return f"Level {item.required_level} {kind}"
    return f"Level {item.required_level}"


def gear_slot(canvas, x, y, index, slot):
    """SetSlot: the pick's icon in its quality border with the game's known mark, or the sheet's own empty
    art, dimmed, with the stock checked highlight over a selected slot."""
    ui = canvas.ui
    item = slot.get("item")
    if item:
        item_id = item["itemID"]
        canvas.draw(ui.texture(ui.item(item_id).icon), x, y, GEAR_ICON, GEAR_ICON)
        canvas.draw(
            ui.texture("interface/common/whiteiconframe.blp"), x, y, GEAR_ICON, GEAR_ICON, gear_quality(ui, item_id)
        )
        if slot.get("mark"):
            mark = ui.atlas("checkmark-minimal")
            canvas.draw(mark, x + GEAR_ICON + 3 - mark.width, y + GEAR_ICON + 3 - mark.height)
    else:
        art = ui.texture(f"interface/paperdoll/ui-paperdoll-slot-{GEAR_SLOT_ART[index].lower()}.blp")
        # SetDesaturated(true) keeps the art's alpha; convert through L so the transparent corners stay clear.
        canvas.draw(art.convert("LA").convert("RGBA"), x, y, GEAR_ICON, GEAR_ICON)
    if slot.get("selected"):
        canvas.draw(ui.texture("interface/buttons/checkbuttonhilight.blp"), x, y, GEAR_ICON, GEAR_ICON, blend="ADD")


def gear_row(canvas, x, y, w, row, text_color=None):
    """UI/Gear.lua CreateRow/FillRow: the icon in its border, a name and a line under it."""
    ui = canvas.ui
    icon = row.get("icon") or ""
    item_id = int(icon[5:]) if icon.startswith("item:") else None
    if item_id:
        canvas.draw(ui.texture(ui.item(item_id).icon), x, y + (GEAR_ROW_H - GEAR_ICON) / 2, GEAR_ICON, GEAR_ICON)
        canvas.draw(
            ui.texture("interface/common/whiteiconframe.blp"),
            x,
            y + (GEAR_ROW_H - GEAR_ICON) / 2,
            GEAR_ICON,
            GEAR_ICON,
            gear_quality(ui, item_id),
        )
    text_x, text_w = x + GEAR_ICON + 8, w - GEAR_ICON - 8
    text_y = y + (GEAR_ROW_H - GEAR_ICON) / 2 + 2
    detail = expand(ui, row.get("detail") or "")
    covered = detail in ("You know it", "Can learn it")
    if "/" in detail:
        have, need = detail.split("/", 1)
        covered = have.strip().isdigit() and need.strip().isdigit() and int(have) >= int(need)
    canvas.text(
        text_x,
        text_y,
        fit_text(canvas, expand(ui, row.get("text") or ""), F_HIGHLIGHT, text_w),
        F_HIGHLIGHT,
        text_color or WHITE,
    )
    canvas.text(
        text_x,
        text_y + F_HIGHLIGHT.height + 2,
        fit_text(canvas, detail, F_NORMAL, text_w),
        F_NORMAL,
        COLORS["green"] if covered else COLORS["unknown"],
    )


def gear_detail(canvas, x, y, w, detail, subclass_names):
    """RenderDetail: the selected slot's pick, its facts, its reagents and one action button."""
    ui = canvas.ui
    if detail.get("emptyShown"):
        for index, line in enumerate(wrap_text(canvas, expand(ui, detail.get("empty") or ""), F_NORMAL, w)):
            canvas.text(x, y + index * F_NORMAL.height, line, F_NORMAL)
        return
    if not detail.get("bodyShown"):
        return
    item_id = int(detail["icon"][5:])
    item = ui.item(item_id)
    canvas.draw(ui.texture(item.icon), x, y, 47, 47)
    canvas.draw(ui.texture("interface/common/whiteiconframe.blp"), x, y, 47, 47, gear_quality(ui, item_id))
    text_x, text_w = x + 47 + 10, w - 47 - 10 - 8
    name_font, normal_font, state_font = FONTS["GameFontNormalLarge"], F_NORMAL, FONTS["GameFontHighlight"]
    canvas.text(
        text_x,
        y + 2,
        fit_text(canvas, item.name, name_font, text_w),
        name_font,
        gear_quality(ui, item_id),
    )
    requirement_y = y + 2 + name_font.height + 2
    canvas.text(text_x, requirement_y, gear_requirement(subclass_names, item), normal_font)
    learn_y = requirement_y + normal_font.height + 2
    canvas.text(text_x, learn_y, expand(ui, detail.get("learn") or ""), normal_font)
    state_y = learn_y + normal_font.height + 2
    known = detail.get("state") in ("You know it", "Can learn it")
    canvas.text(
        text_x,
        state_y,
        expand(ui, detail.get("state") or ""),
        state_font,
        COLORS["green"] if known else COLORS["unknown"],
    )
    heading_y = state_y + state_font.height + 12
    below = heading_y + normal_font.height
    reagents = [row for row in detail.get("reagents", []) if row.get("shown")]
    if detail.get("reagentsShown"):
        canvas.text(x, heading_y, "Reagents", normal_font)
        if reagents:
            tops = [heading_y + normal_font.height + 2, heading_y + normal_font.height + 2]
            for index, row in enumerate(reagents):
                column = index % 2
                row_x = x if column == 0 else x + w / 2 + 4
                row_w = w / 2 - 4 if column == 0 else w / 2 - 4 - 8
                gear_row(canvas, row_x, tops[column], row_w, row)
                tops[column] += GEAR_ROW_H + 2
            below = tops[(len(reagents) - 1) % 2] - 2
    action_y = below + 10
    action = detail.get("action", {})
    panel_button(canvas, x, action_y, 130, 22, expand(ui, action.get("text") or ""), action.get("enabled", True))
    if detail.get("alsoShown"):
        also_y = action_y + 22 + 10
        canvas.text(x, also_y, "Also for this slot", normal_font)
        tops = also_y + normal_font.height + 2
        for row in detail.get("others", []):
            if row.get("shown"):
                icon = row.get("icon") or ""
                text_color = gear_quality(ui, int(icon[5:])) if icon.startswith("item:") else None
                gear_row(canvas, x, tops, w, row, text_color)
                tops += GEAR_ROW_H


def gear_scene(ui, scene_data):
    """The Professions window on SkillUp's crafted gear tab: Gear.lua's page where the crafting page was."""
    gear = scene_data["gear"]
    subclass_names = {
        (int(row["ClassID"]), int(row["SubClassID"])): row["VerboseName_lang"] or row["DisplayName_lang"]
        for row in ui.wago.db2("ItemSubClass")
    }
    m = FRAME_MARGIN
    canvas = ui.canvas(FRAME_W + m + TABS_MARGIN, FRAME_H + 2 * m)
    fx, fy = m, m
    canvas.draw(ui.atlas("Profession-Background-Overview"), fx + 2, fy + 21, FRAME_W - 4, FRAME_H - 23)
    inset_x, inset_y, inset_w, inset_h = fx + 16, fy + 88, FRAME_W - 32, FRAME_H - 132
    inset_frame(canvas, inset_x, inset_y, inset_w, inset_h, "Crafted gear")
    # The doll: six slots down each side, then the three weapon slots along the bottom.
    for position, index in enumerate(GEAR_LEFT + GEAR_RIGHT):
        side, row = divmod(position, 6)
        x = inset_x + 10 if side == 0 else inset_x + inset_w - 10 - GEAR_ICON
        y = inset_y + 10 + row * (GEAR_ICON + GEAR_SLOT_GAP)
        gear_slot(canvas, x, y, index, gear["slots"][index])
    for position, index in enumerate(GEAR_BOTTOM):
        offset = (position - 1) * (GEAR_ICON + GEAR_SLOT_GAP)
        x = inset_x + inset_w / 2 + offset - GEAR_ICON / 2
        y = inset_y + inset_h - 12 - GEAR_ICON
        gear_slot(canvas, x, y, index, gear["slots"][index])
    # The show-all switch, its label to the left of the box, above the inset's top-right.
    box = 32
    box_x, box_y = inset_x + inset_w - box, inset_y - 8 - box
    canvas.draw(ui.texture("interface/buttons/ui-checkbox-up.blp"), box_x, box_y, box, box)
    if gear.get("showAll"):
        canvas.draw(ui.texture("interface/buttons/ui-checkbox-check.blp"), box_x, box_y, box, box)
    label = expand(ui, gear.get("showAllLabel") or "")
    canvas.text(
        box_x - 4 - canvas.text_width(label, F_NORMAL),
        box_y + (box - F_NORMAL.height) / 2,
        label,
        F_NORMAL,
    )
    detail = dict(gear["detail"], reagents=gear.get("reagents", []), others=gear.get("others", []))
    gear_detail(canvas, inset_x + 56, inset_y + 10, inset_w - 112, detail, subclass_names)
    profession_tabs(canvas, fx, fy, "gear", gear_tab=True)
    portrait_frame_art(canvas, fx, fy, FRAME_W, FRAME_H, 136247, "Leatherworking")
    return scene(ui, [(canvas, 0, 0)])


def tracker_scene(ui, scene_data):
    """ObjectiveTrackerFrame with SkillUp's section laid out by Shopping.lua's LayoutContents."""
    tracker = scene_data["tracker"]
    blocks = []
    for block in tracker["blocks"]:
        lines = []
        for line in block["lines"]:
            text = expand(ui, line["text"])
            if line.get("color"):
                r, g, b = line["color"]
                text = f"|cff{round(r * 255):02x}{round(g * 255):02x}{round(b * 255):02x}{text}|r"
            lines.append((text, line["dash"]))
        blocks.append(TrackerBlock(expand(ui, block["header"]), lines))
    canvas, _ = objective_tracker(ui, [TrackerModule(tracker["header"], blocks)], container=False)
    return scene(ui, [(canvas, 0, 0)])


TRAINER_ROW_W, TRAINER_ROW_H = 298, 47  # ClassTrainerSkillButtonTemplate
TRAINER_INSET_W, TRAINER_INSET_H = 328, 338  # ButtonFrameTemplate 338x424, Inset (4, -60) to (-6, 26)
TRAINER_BOX_W, TRAINER_BOX_H = 302, 330  # the ScrollBox, at the Inset's TOPLEFT (5, -5) with no skill step


def trainer_row(canvas, x, y, service):
    """ClassTrainerFrame_InitServiceButton's service button: icon, name, "Requires:" line, fee, and SkillUp's
    text at its BOTTOMRIGHT (-8, 6). An unavailable service gets the grey name, desaturated icon and
    disabledBG (0.55 MOD, 2 in)."""
    ui = canvas.ui
    available = service["kind"] == "available"
    if not available:
        canvas.fill(x + 2, y + 2, TRAINER_ROW_W - 4, TRAINER_ROW_H - 4, (0, 0, 0, 0.45))
    textures = ui.texture("interface/classtrainerframe/trainertextures.blp")
    canvas.draw(crop_coords(textures, 0.00195313, 0.57421875, 0.65820313, 0.75), x, y, TRAINER_ROW_W, TRAINER_ROW_H)
    item = ui.item(NS["RecipeData"][service["recipeID"]]["output"]["itemID"])
    icon = ui.texture(item.icon)
    if not available:
        icon = ImageOps.grayscale(icon.convert("RGB")).convert("RGBA")
    icon_y = y + (TRAINER_ROW_H - 36) / 2
    canvas.draw(icon, x + 6, icon_y, 36, 36)
    name_x = x + 6 + 36 + 6
    canvas.text(name_x, icon_y + 1, service["name"], F_NORMAL, None if available else DISABLED_FONT_COLOR)
    requirement = requirement_text(service["req"])
    subtext_y = icon_y + 1 + F_NORMAL.height / 2 + 19 - F_SHADOW_SMALL.height / 2
    canvas.text(name_x, subtext_y, requirement, F_SHADOW_SMALL)
    draw_money(canvas, x + TRAINER_ROW_W - 8 - money_width(canvas, service["fee"]), y + 7, service["fee"])
    skill_up = service.get("skillUp")
    if skill_up and skill_up.get("shown"):
        font = FONTS["GameFontHighlightSmall"]
        width = skill_up["width"]
        canvas.text(
            x + TRAINER_ROW_W - 8 - width,
            y + TRAINER_ROW_H - 6 - font.height,
            fit_text(canvas, expand(ui, skill_up["text"]), font, width),
            font,
            tuple(skill_up["color"]),
            justify="RIGHT",
            width=width,
        )


def trainer_scene(ui, scene_data):
    """The trainer window's service list (its Inset) at an Apprentice Leatherworking trainer, rows as the
    default filter lists them, each decorated by Trainer.lua."""
    m = 8
    canvas = ui.canvas(TRAINER_INSET_W + 2 * m, TRAINER_INSET_H + 2 * m)
    x, y = m, m
    # The Inset takes its parent's level: its marble Bg (sublevel -5), the frame's BG from the ScrollBox's
    # (-3, 4) to (3, -4), then the Inset's border.
    marble = ui.texture("interface/framegeneral/ui-background-marble.blp")
    tiled(canvas, marble, x + 2, y + 2, TRAINER_INSET_W - 4, TRAINER_INSET_H - 4, 256, 256)
    box_x, box_y = x + 5, y + 5
    textures = ui.texture("interface/classtrainerframe/trainertextures.blp")
    background = crop_coords(textures, 0.00195313, 0.5859375, 0.00195313, 0.65429688)
    canvas.draw(background, box_x - 3, box_y - 4, TRAINER_BOX_W + 6, TRAINER_BOX_H + 8)
    canvas.nine_slice(INSET_FRAME_LAYOUT, x, y, TRAINER_INSET_W, TRAINER_INSET_H)
    top = box_y + 1  # the view's padding: 1 top, 1 left
    for service in scene_data["trainer"]:
        trainer_row(canvas, box_x + 1, top, service)
        top += TRAINER_ROW_H
    return scene(ui, [(canvas, 0, 0)])


def reagent_tooltip(ui, scene_data):
    """Light Leather's item tooltip with what UI/Tooltip.lua's post-call adds (route mode, Shift up)."""
    item = ui.item(TOOLTIP_ITEM)
    lines = [TooltipLine(item.name, QUALITY_TEXT[item.quality]), TooltipLine("Sell Price:", money=item.sell_price)]
    for line in scene_data["reagent"]:
        lines.append(TooltipLine(expand(ui, line["left"]), tuple(line["color"]) if line.get("color") else WHITE))
    return scene(ui, [(tooltip(ui, lines), 0, 0)])


# The demo levels Leatherworking with the cursor on HOVERED: the rows re-sort by cost per skill-up, their
# colours and chances move, and the tooltip's marker walks across the bar as yellow turns green at 55.
DEMO_SKILLS = [48, 50, 52, 54, 55, 57, 60]
DEMO_HOLD = 12  # each skill's frame lasts 12 x 100 ms, so the whole loop runs 8.4 s
DEMO_MAX_BYTES = 2_000_000  # the stores' gallery limit


def render_demo():
    global SKILL
    ui = Ui(build=BUILD, scale=1)  # at the GIF's final size, so one-pixel lines stay crisp
    states = []
    for skill in DEMO_SKILLS:
        SKILL = skill
        frame, _ = professions_frame(ui)
        tip = recipe_tooltip(ui, HOVERED)
        states.append([(frame, 0, 0), (tip, *beside_window(ui))])
    SKILL = DEMO_SKILLS[0]
    # One frame for every skill: the union of what any state draws, so nothing jumps between states.
    boxes = []
    for layers in states:
        for canvas, x, y in layers:
            left, top, right, bottom = canvas.image.getbbox()
            boxes.append((x + left, y + top, x + right, y + bottom))
    margin = 24
    left, top = min(b[0] for b in boxes) - margin, min(b[1] for b in boxes) - margin
    width, height = max(b[2] for b in boxes) + margin - left, max(b[3] for b in boxes) + margin - top
    frames = []
    for layers in states:
        result = backdrop(ui, width, height)
        for canvas, x, y in layers:
            result.paste(canvas, x - left, y - top)
        frames.append(result.image.convert("RGB"))
    # One shared palette from every state, no dither: text colours hold and repeated encodes are identical.
    sheet = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (0, frame.height * index))
    palette = sheet.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    buffer = io.BytesIO()
    indexed[0].save(
        buffer,
        format="GIF",
        save_all=True,
        append_images=indexed[1:],
        duration=[100 * DEMO_HOLD] * len(indexed),
        loop=0,
        optimize=True,
        disposal=1,
    )
    content = buffer.getvalue()
    assert len(content) <= DEMO_MAX_BYTES, f"demo.gif is {len(content):,} bytes, over {DEMO_MAX_BYTES:,}"
    return content


def main():
    scale = float(os.environ.get("SCALE", "2"))
    ui = Ui(build=BUILD, scale=scale)
    OUT.mkdir(parents=True, exist_ok=True)
    window_scene(ui).save(OUT / "window.png")
    scene(ui, [(recipe_tooltip(ui, HOVERED), 0, 0)]).save(OUT / "tooltip.png")
    data = lua_scene(ui)
    scene(ui, [(route_frame(ui, data), 0, 0)]).save(OUT / "route.png")
    gear_scene(ui, data).save(OUT / "gear.png")
    tracker_scene(ui, data).save(OUT / "tracker.png")
    trainer_scene(ui, data).save(OUT / "trainer.png")
    reagent_tooltip(ui, data).save(OUT / "reagent.png")
    demo = render_demo()
    assert demo == render_demo(), "demo.gif renders differently twice"
    (OUT / "demo.gif").write_bytes(demo)


if __name__ == "__main__":
    main()
