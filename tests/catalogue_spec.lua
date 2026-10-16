-- Run from the repository root: luajit tests/catalogue_spec.lua
-- The catalogue over synthetic QuestieDB and AtlasLoot stubs: which providers are there, when they become
-- ready, what a profession's scrolls resolve to, and how much the queue reads a frame.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local TAILORING = 197
local SHIRT, ROBE, BOOTS, CLOAK = 101, 102, 103, 104
local PATTERN_SHIRT, PATTERN_SHIRT_HORDE, PATTERN_ROBE, PATTERN_BOOTS = 201, 202, 203, 204
local SELLER, HORDE_SELLER, HOSTILE, BOSS, TRAINER = 301, 302, 303, 304, 305
local ELWYNN, DEADMINES, GOLDSHIRE = 12, 1581, 87
-- Holiday vendors QuestieDB calls friendly to both, standing in a capital city or a part of one.
local BLUFF_SELLER, RISE_SELLER, STORMWIND_SELLER = 306, 307, 308
local THUNDER_BLUFF, ELDER_RISE, STORMWIND = 1638, 1639, 1519

local function Database()
	return {
		items = {
			[PATTERN_SHIRT] = { vendors = { SELLER }, quests = { 401 } },
			[PATTERN_SHIRT_HORDE] = { vendors = { HORDE_SELLER } },
			[PATTERN_ROBE] = { drops = { BOSS } },
			-- PATTERN_BOOTS is a record QuestieDB lacks.
		},
		npcs = {
			[SELLER] = {
				name = "Seller",
				spawns = { [GOLDSHIRE] = { { 40, 60 }, { 42, 66 }, { 44, 72 } } },
				side = "A",
			},
			[HORDE_SELLER] = { name = "Horde Seller", spawns = { [ELWYNN] = { { 10, 10 } } }, side = "H" },
			[HOSTILE] = { name = "Hostile", spawns = { [ELWYNN] = { { 20, 20 } } } },
			[BOSS] = { name = "Boss", spawns = { [DEADMINES] = { { -1, -1 } } }, zone = DEADMINES },
			[TRAINER] = { name = "Trainer", spawns = { [ELWYNN] = { { 50, 50 } } }, zone = ELWYNN, side = "AH" },
			[BLUFF_SELLER] = { name = "Bluff Seller", spawns = { [THUNDER_BLUFF] = { { 39, 61 } } }, side = "AH" },
			[RISE_SELLER] = { name = "Rise Seller", spawns = { [ELDER_RISE] = { { 70, 30 } } }, side = "AH" },
			[STORMWIND_SELLER] = { name = "Stormwind Seller", spawns = { [STORMWIND] = { { 62, 70 } } }, side = "AH" },
		},
		quests = {
			[401] = { name = "A Fine Shirt", races = 77, starts = { SELLER } },
			[402] = { name = "For All", races = 0 },
		},
		areas = { [ELWYNN] = 1429 },
		parents = { [GOLDSHIRE] = ELWYNN, [ELDER_RISE] = THUNDER_BLUFF },
	}
end
local function Recipes()
	return {
		recipes = {
			[PATTERN_SHIRT] = { 8, 40, SHIRT },
			[PATTERN_ROBE] = { 8, 90, ROBE },
			[PATTERN_BOOTS] = { 8, 120, BOOTS },
		},
		drops = { [BOSS] = { [PATTERN_ROBE] = 12.5 } },
	}
end

-- A fresh addon over the given providers. `options.cost` is the ms each record takes to read.
local function Load(questieDB, atlasLootDB, options)
	options = options or {}
	local timers, clock, changes, watchers = {}, 0, {}, {}
	local ns = {
		db = { sellers = {} },
		RecipeData = {
			[SHIRT] = { skillLine = TAILORING },
			[ROBE] = { skillLine = TAILORING },
			[BOOTS] = { skillLine = TAILORING },
			[CLOAK] = { skillLine = TAILORING },
			[900] = { skillLine = 165 },
		},
		ScrollDrops = { [PATTERN_ROBE] = { { BOSS, 4 } } },
		WorldDrops = { [PATTERN_BOOTS] = true },
		ProfessionTrainers = { [TAILORING] = { { TRAINER, 150 } } },
		Changed = function(kind)
			changes[#changes + 1] = kind
		end,
		WhenEvent = function(event, watcher)
			watchers[event] = watcher
		end,
	}
	local lib = questieDB and Client.QuestieDB(questieDB)
	for _, entity in ipairs(options.cost and { lib.Item, lib.Npc, lib.Quest } or {}) do
		local read = entity.GetAll
		entity.GetAll = function(...)
			clock = clock + options.cost
			return read(...)
		end
	end
	local env = setmetatable({
		LibQuestieDB = lib,
		AtlasLoot = atlasLootDB and Client.AtlasLoot(atlasLootDB),
		Questie = options.questie,
		C_AddOns = {
			GetAddOnMetadata = function(_, field)
				return field == "X-Flavor" and (options.flavour or "Forever") or nil
			end,
			DoesAddOnExist = function(name)
				return options.installed == name
			end,
		},
		C_Timer = {
			After = function(delay, fn)
				timers[#timers + 1] = { delay = delay, fn = fn }
			end,
		},
		debugprofilestop = function()
			return clock
		end,
	}, { __index = _G })
	for _, file in ipairs({
		"Locales/enUS.lua",
		"Integrations/Questie.lua",
		"Integrations/AtlasLoot.lua",
		"Integrations/Catalogue.lua",
	}) do
		setfenv(assert(loadfile(file)), env)("SkillUpForever", ns)
	end
	ns.InitCatalogue()
	local c = { ns = ns, env = env, changes = changes, watchers = watchers, db = questieDB }
	-- Runs the next frame's timers (delay 0); true while more are waiting.
	function c.Frame()
		local due = {}
		for index = #timers, 1, -1 do
			if timers[index].delay == 0 then
				table.insert(due, 1, table.remove(timers, index))
			end
		end
		for _, timer in ipairs(due) do
			timer.fn()
		end
		return #due > 0
	end
	function c.Settle()
		local frames = 0
		while c.Frame() do
			frames = frames + 1
		end
		return frames
	end
	-- The one-shot wait for a Questie that never reports ready.
	function c.Timeout()
		for index, timer in ipairs(timers) do
			if timer.delay > 0 then
				table.remove(timers, index).fn()
				return true
			end
		end
		return false
	end
	return c
end

--[[ Both providers ]]

local c = Load(Database(), Recipes())
local C = c.ns.Catalogue
equal(C.Status().questie, "ready", "QuestieDB alone is read at once")
equal(C.Status().atlasLoot, true, "AtlasLoot is there")
equal(C.Hint(), nil, "with both there is nothing to install")
equal(C.Recipe(SHIRT), nil, "nothing is known before the profession is asked for")
equal(C.EnsureProfession(TAILORING), false, "the first ask starts the reading")
equal(c.db.reads, 0, "and reads nothing itself")
equal(C.Status().reading, true, "the queue is reading")
c.Settle()
equal(C.EnsureProfession(TAILORING), true, "then the profession is ready")
equal(#c.changes, 1, "and what depends on it is redrawn once")
equal(c.changes[1], "sources", "as a change of sources")
equal(C.Status().reading, false, "with no timer left running")

local shirt = C.Recipe(SHIRT)
equal(shirt.item, PATTERN_SHIRT, "the scroll is AtlasLoot's")
equal(shirt.skill, 40, "with the skill it needs")
equal(shirt.vendors[1], SELLER, "its vendor is QuestieDB's")
equal(shirt.quests[1], 401, "and its quest")
equal(C.Quest(401).title, "A Fine Shirt", "a quest's title")
equal(C.Quest(401).side, "A", "a quest only Alliance races may take")
equal(C.Quest(402).side, "", "a quest anyone may take")
equal(C.Quest(401).starters[1], SELLER, "who gives a quest")
equal(#C.Quest(402).starters, 0, "and none for a quest QuestieDB names no giver for")
local robe = C.Recipe(ROBE)
equal(robe.drops[1][1], BOSS, "a drop is the bundled one")
equal(robe.drops[1][2], 12.5, "at AtlasLoot's chance where it has one")
equal(C.Recipe(CLOAK), nil, "a recipe no scroll teaches has no source")
equal(C.Recipe(900), nil, "another profession has not been read")
equal(#C.Trainers(TAILORING, 150), 1, "a trainer who teaches that far")
equal(#C.Trainers(TAILORING, 225), 0, "none teaches further")

-- Missing records: the scroll is known, QuestieDB has nothing on it, and the miss is not read twice.
local boots = C.Recipe(BOOTS)
equal(#boots.vendors, 0, "a scroll QuestieDB lacks has no vendors")
equal(boots.world, true, "but keeps its bundled world drop")
local reads = c.db.reads
equal(C.ItemSources(PATTERN_BOOTS), nil, "a missing item is nil")
equal(C.NPC(999), nil, "a missing NPC is nil")
C.NPC(999)
equal(c.db.reads, reads + 1, "a miss is cached: the item was read with its profession, the NPC once")

-- Coordinate conversion: QuestieDB's 0-100 on an area's map to 0-1 on the zone map, a subzone through
-- its parent zone, the spawn nearest the middle of the area's spawns.
local seller = C.NPC(SELLER)
equal(seller.map, 1429, "a subzone's spawn is on its parent zone's map")
equal(seller.x, 0.42, "x in 0-1")
equal(seller.y, 0.66, "y in 0-1")
local boss = C.NPC(BOSS)
equal(boss.map, nil, "a dungeon spawn has no map point")
equal(boss.area, DEADMINES, "only its area")

-- Sides: who can deal with an NPC; hostile to both is nil.
equal(seller.side, "A", "an Alliance vendor")
equal(C.NPC(HORDE_SELLER).side, "H", "a Horde vendor")
equal(C.NPC(TRAINER).side, "", "friendly to both")
equal(C.NPC(HOSTILE).side, nil, "hostile to both")
equal(C.NPC(BLUFF_SELLER).side, "H", "friendly to both inside a Horde capital deals with the Horde")
equal(C.NPC(RISE_SELLER).side, "H", "as it does in a part of that city")
equal(C.NPC(STORMWIND_SELLER).side, "A", "and inside an Alliance capital with the Alliance")
equal(c.Frame(), false, "nothing is left running once settled")

--[[ Either provider ]]

c = Load(Database(), nil)
C = c.ns.Catalogue
equal(C.Hint(), "Install AtlasLoot to see the recipes vendors, quests and drops would add.", "without AtlasLoot")
equal(
	Load(Database(), nil, { installed = "AtlasLootClassic" }).ns.Catalogue.Hint(),
	"AtlasLoot is installed but not running: enable it in the AddOns list, or update it if out of date.",
	"an AtlasLoot that is installed but not running is not called missing"
)
C.EnsureProfession(TAILORING)
c.Settle()
equal(C.Recipe(SHIRT), nil, "QuestieDB names no recipe on its scrolls here, so none is found")
equal(C.NPC(SELLER).name, "Seller", "NPCs are still read")

-- Duplicate scrolls: QuestieDB names two scrolls for the shirt; the one a vendor sells is kept, and with
-- both sold the lower item.
local db = Database()
db.items[PATTERN_SHIRT].teaches, db.items[PATTERN_SHIRT_HORDE].teaches = SHIRT, SHIRT
db.items[PATTERN_SHIRT].vendors = nil
db.items[500] = { class = 7, teaches = ROBE }
c = Load(db, nil)
C = c.ns.Catalogue
C.EnsureProfession(TAILORING)
c.Settle()
equal(#C.Scrolls(SHIRT), 2, "QuestieDB's items name both scrolls")
equal(C.Recipe(SHIRT).item, PATTERN_SHIRT_HORDE, "the one a vendor sells is kept")
equal(C.Recipe(SHIRT).skill, nil, "its skill is unknown without AtlasLoot")
equal(#C.Scrolls(ROBE), 0, "an item that is no recipe scroll teaches nothing")
db = Database()
db.items[PATTERN_SHIRT].teaches, db.items[PATTERN_SHIRT_HORDE].teaches = SHIRT, SHIRT
c = Load(db, Recipes())
C = c.ns.Catalogue
C.EnsureProfession(TAILORING)
c.Settle()
equal(#C.Scrolls(SHIRT), 2, "with AtlasLoot too, QuestieDB's two scrolls are both known")
equal(C.Recipe(SHIRT).item, PATTERN_SHIRT, "with both sold, the lower item")
equal(C.Recipe(ROBE).item, PATTERN_ROBE, "a recipe QuestieDB names no scroll for falls back to AtlasLoot's")

c = Load(nil, Recipes())
C = c.ns.Catalogue
equal(C.Status().questie, "missing", "no QuestieDB")
equal(
	C.Hint(),
	"Install Questie to see vendors, quests and trainers, with waypoints to them.",
	"without Questie one line says what to install"
)
C.EnsureProfession(TAILORING)
c.Settle()
equal(C.Recipe(SHIRT).item, PATTERN_SHIRT, "AtlasLoot still names the scroll")
equal(#C.Recipe(SHIRT).vendors, 0, "with no seller")
equal(C.Recipe(ROBE).drops[1][2], 12.5, "and the drop chance")
equal(C.NPC(SELLER), nil, "no NPC has a name or place")

--[[ Neither ]]

c = Load(nil, nil)
C = c.ns.Catalogue
equal(
	C.Hint(),
	"Install Questie and AtlasLoot to see where recipes, vendors and trainers are.",
	"with neither, one line names both"
)
equal(C.EnsureProfession(TAILORING), true, "there is nothing to read")
equal(C.Recipe(SHIRT), nil, "and no source")
equal(c.Frame(), false, "no timer runs")

--[[ Contract rejection ]]

db = Database()
db.contract = 3
c = Load(db, Recipes())
equal(c.ns.Catalogue.Status().questie, "unfit", "another contract is not read")
equal(c.ns.Catalogue.NPC(SELLER), nil, "so no NPC")
db = Database()
db.without = "vendors"
equal(Load(db, nil).ns.Catalogue.Status().questie, "unfit", "a schema without a field read is not read")
-- A quest's givers are optional: a schema without them is still read, and its quests have no giver.
db = Database()
db.without = "startedBy"
c = Load(db, nil)
equal(c.ns.Catalogue.Status().questie, "ready", "a schema without quest givers is read")
equal(c.ns.Catalogue.Quest(401).title, "A Fine Shirt", "its quests are named")
equal(#c.ns.Catalogue.Quest(401).starters, 0, "with no giver")
equal(Load(Database(), nil, { flavour = "Vanilla" }).ns.Catalogue.Status().questie, "unfit", "nor another game's")

--[[ Delayed readiness ]]

local ready
c = Load(Database(), Recipes(), {
	questie = {
		API = {
			RegisterOnReady = function(fn)
				ready = fn
			end,
		},
	},
})
C = c.ns.Catalogue
equal(C.Status().questie, "waiting", "with Questie installed its start is waited for")
equal(C.Hint(), nil, "which is nothing to install")
C.EnsureProfession(TAILORING)
c.Settle()
equal(#C.Recipe(SHIRT).vendors, 0, "until then a scroll has no seller")
equal(C.NPC(SELLER), nil, "and an NPC is a miss")
ready()
equal(C.Status().questie, "ready", "Questie reports ready")
equal(c.changes[#c.changes], "sources", "which redraws what depends on it")
equal(C.EnsureProfession(TAILORING), false, "the profession is read again")
c.Settle()
equal(C.Recipe(SHIRT).vendors[1], SELLER, "and now has its seller")
equal(C.NPC(SELLER).name, "Seller", "the miss was dropped")
-- A Questie that never reports ready is not waited on for ever.
c = Load(Database(), Recipes(), { questie = { API = { RegisterOnReady = function() end } } })
equal(c.Timeout(), true, "one timer waits for Questie")
equal(c.ns.Catalogue.Status().questie, "ready", "and reads the database when it runs out")
equal(c.Timeout(), false, "no other timer is left")
-- A provider that loads later is picked up.
c = Load(nil, nil)
c.env.AtlasLoot = Client.AtlasLoot(Recipes())
c.watchers.ADDON_LOADED()
equal(c.ns.Catalogue.Status().atlasLoot, true, "AtlasLoot loading later is seen")
equal(c.changes[#c.changes], "sources", "and redraws")
c.env.LibQuestieDB = Client.QuestieDB(Database())
c.watchers.ADDON_LOADED()
equal(c.ns.Catalogue.Status().questie, "ready", "so is QuestieDB")

--[[ Queue limits ]]

-- Many scrolls: each frame reads at most 32 records.
db, reads = Database(), Recipes()
for index = 1, 200 do
	db.items[1000 + index] = { vendors = { SELLER } }
	reads.recipes[1000 + index] = { 8, 1, 2000 + index }
end
c = Load(db, reads)
for index = 1, 200 do
	c.ns.RecipeData[2000 + index] = { skillLine = TAILORING }
end
C = c.ns.Catalogue
C.EnsureProfession(TAILORING)
local most, before = 0, 0
while c.Frame() do
	most, before = math.max(most, db.reads - before), db.reads
end
equal(most <= 32, true, "no frame reads more than 32 records")
equal(most > 1, true, "and a frame reads several")
equal(C.Recipe(2200).vendors[1], SELLER, "every recipe is read in the end")
-- Slow reads: a frame stops once it has spent its millisecond.
c = Load(Database(), Recipes(), { cost = 0.6 })
c.ns.Catalogue.EnsureProfession(TAILORING)
most, before = 0, 0
while c.Frame() do
	most, before = math.max(most, c.db.reads - before), c.db.reads
end
equal(most <= 2, true, "at 0.6 ms a read, a frame stops after two")
equal(c.ns.Catalogue.EnsureProfession(TAILORING), true, "and still finishes")
-- An item's vendors go through the same queue.
c = Load(Database(), Recipes())
C = c.ns.Catalogue
equal(C.EnsureVendors(PATTERN_SHIRT), false, "an item's vendors are read on the queue")
equal(c.db.reads, 0, "not at once")
c.Settle()
equal(C.EnsureVendors(PATTERN_SHIRT), true, "then they are ready")
equal(#c.changes, 1, "with one redraw")

Client.report("catalogue_spec")
