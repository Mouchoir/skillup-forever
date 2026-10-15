-- Run from the repository root: luajit tests/report_spec.lua
-- /su report (cjber/adventure-guide-forever#156): one selected block of text with the versions, the character,
-- SkillUp's own lines (settings, providers, each profession's route, the audit, the trainer checks), the errors
-- ns.SafeCall caught and the other addons, never longer than one message; ns.SafeCall keeps errors and still
-- reports them.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local function has(text, part, label)
	equal(text:find(part, 1, true) ~= nil, true, ("%s: %q in\n%s"):format(label, part, text))
end

local BANDAGE, SILK = 1, 3
local function Load()
	local c = Client.load({
		saved = { routeTargets = { [129] = 40 } },
		data = {
			Thresholds = { [BANDAGE] = { 1, 30, 45, 60 } },
			RecipeData = { [BANDAGE] = { skillLine = 129, reagents = { { itemID = SILK, quantity = 1 } } } },
			TrainerFees = {},
			TrainerRanks = {},
			TrainerInferred = {},
			VendorPrices = { [SILK] = 10 },
		},
	})
	c.level = 18
	c.known[BANDAGE] = true
	c.items[SILK] = { name = "Linen Cloth" }
	c.professions = { { name = "First Aid", icon = 1, rank = 10, max = 75, id = 129 } }
	c.Boot()
	return c
end

-- The report window: the frame /su report made, with its edit box.
local function Window(c)
	local edit = c.focus
	return edit and edit:GetParent():GetParent():GetParent(), edit
end

do
	local c = Load()
	c.addons = { { "Questie", "9.1.0" }, { "ShortestPathForever", "0.9.0" } }
	local before = #c.frames
	c.G.SlashCmdList.SKILLUPFOREVER("report")
	local frame, edit = Window(c)
	equal(edit ~= nil, true, "the report's edit box has the focus")
	local text = edit:GetText()
	equal(edit.highlighted, text, "the whole report is selected")
	equal(frame.title, "SkillUp report", "its title")
	equal(frame:IsShown(), true, "shown")
	has(text, "SkillUpForever 1.2.3 | WoW 1.60.1 (", "versions, build and locale")
	has(text, "Character: level 18 Orc SHAMAN", "character")
	has(text, "Place: map ", "place")
	has(text, "Settings: crafts count vendor, gathered free, reagent tooltips route, sort blizzard", "settings")
	has(text, "Providers: QuestieDB missing, AtlasLoot missing, Auctionator ready", "providers")
	has(text, "First Aid [129]: 10+0/75; route to 40 reaches 40, ", "each profession and its route")
	has(text, "Audit: no profession open", "the audit needs an open profession")
	has(text, "Trainers: nothing to check", "the trainer checks")
	has(text, "Errors: none caught", "no errors yet")
	has(text, "Other addons (2): Questie 9.1.0, ShortestPathForever 0.9.0", "the other addons with versions")
	equal(#text <= 2000, true, "one message")

	-- Read-only: a key typed in the box puts the report back, selected.
	edit.text, edit.highlighted = "x", nil
	edit.scripts.OnTextChanged(edit, true)
	equal(edit:GetText(), text, "typing restores the report")
	equal(edit.highlighted, text, "and selects it again")
	edit.scripts.OnEscapePressed(edit)
	equal(frame:IsShown(), false, "Escape hides it")
	local made = #c.frames - before
	c.G.SlashCmdList.SKILLUPFOREVER("report")
	equal(frame:IsShown(), true, "shown again")
	equal(#c.frames - before, made, "the window is made once")
	equal(#c.errors, 0, "no errors")
end

-- ns.SafeCall: pcall's answers, and each failure kept and passed to the error handler.
do
	local c = Load()
	local ns = c.ns
	c.allowErrors = true
	local ok, a, b, d = ns.SafeCall("test", function(x)
		return x, nil, 3
	end, 1)
	equal(ok, true, "SafeCall: ok")
	equal(a, 1, "SafeCall: first result")
	equal(b, nil, "SafeCall: a nil result kept in place")
	equal(d, 3, "SafeCall: last result")
	local failed, message = ns.SafeCall("test", error, "boom", 0)
	equal(failed, false, "SafeCall: failure")
	equal(message, "boom", "SafeCall: the error")
	equal(#c.errors, 1, "SafeCall: passed to the error handler")
	ns.SafeCall("test", error, "boom", 0)
	equal(ns.CaughtErrors()[1].count, 2, "SafeCall: a repeat is counted")
	for index = 1, 6 do
		ns.SafeCall("many", error, "error " .. index, 0)
	end
	local caught = ns.CaughtErrors()
	equal(#caught, 5, "SafeCall: the last five kept")
	equal(caught[5].message, "error 6", "SafeCall: newest kept")

	-- A failing view stops neither the others nor the event: the error is kept with the stale view's name.
	local after = 0
	ns.WhenStale("gear", function()
		error("gear failed", 0)
	end)
	ns.WhenStale("tooltip", function()
		after = after + 1
	end)
	ns.Changed("sources")
	equal(after, 1, "the view after a failing one still redraws")
	caught = ns.CaughtErrors()
	equal(caught[#caught].label, "stale gear", "the failure is kept under the view's name")

	c.G.SlashCmdList.SKILLUPFOREVER("report")
	local _, edit = Window(c)
	local text = edit:GetText()
	has(text, "Errors (5):", "report: the caught errors")
	has(text, "- [stale gear] x1 gear failed", "report: newest first")
	equal(#text <= 2000, true, "report: still one message")
end

-- The client's stack lines are kept as LuaJIT's are; a long message is cut on a character boundary; a nested
-- SafeCall names its own label.
do
	local c = Load()
	local ns = c.ns
	c.allowErrors = true
	ns.RecordError(
		"client",
		"boom",
		table.concat({
			'[string "@Interface/AddOns/SkillUpForever/Core/Changes.lua"]:132: in function <...>',
			"[C]: in function 'xpcall'",
			"[Interface/AddOns/SkillUpForever/Core/Core.lua]:600: in function 'Slash'",
		}, "\n")
	)
	local stack = ns.CaughtErrors()[1].stack
	has(stack, 'Changes.lua"]:132', "client stack: a string chunk line")
	has(stack, "Core.lua]:600", "client stack: a file line")
	equal(stack:find("[C]", 1, true), nil, "client stack: C frames left out")
	ns.RecordError("utf8", ("é"):rep(200))
	local message = ns.CaughtErrors()[2].message
	equal(message:sub(-3), "...", "utf8: cut")
	equal(#message <= 300, true, "utf8: within the limit")
	equal(select(2, message:sub(1, -4):gsub("é", "")) * 2, #message - 3, "utf8: whole characters only")
	ns.SafeCall("outer", function()
		ns.SafeCall("inner", error, "inner failed", 0)
	end)
	local caught = ns.CaughtErrors()
	equal(caught[#caught].label, "inner", "nested: the inner label")
	equal(#caught, 3, "nested: the outer call didn't fail")
end

-- Escape closes the window like a panel; long SkillUp lines are capped, so the caught errors and the addon list
-- still fit.
do
	local c = Load()
	local ns = c.ns
	c.allowErrors = true
	ns.SafeCall("kept", error, "still shown", 0)
	local long = {}
	for index = 1, 100 do
		long[index] = ("line %03d "):format(index) .. ("x"):rep(60)
	end
	ns.ReportLines = function()
		return long
	end
	c.G.SlashCmdList.SKILLUPFOREVER("report")
	local frame, edit = Window(c)
	local special = false
	for _, name in ipairs(c.G.UISpecialFrames) do
		special = special or (name == "SkillUpForeverReport" and c.G[name] == frame)
	end
	equal(special, true, "Escape: the window is a special frame")
	local text = edit:GetText()
	equal(#text <= 2000, true, "long lines: one message")
	has(text, "line 001 ", "long lines: the first kept")
	equal(text:find("line 100 ", 1, true), nil, "long lines: the last cut")
	has(text, "- [kept] x1 still shown", "long lines: the errors still shown")
	has(text, "Other addons (", "long lines: the addon list still shown")
end

-- SkillUp's own lines failing still opens the report, with the header and the error.
do
	local c = Load()
	c.allowErrors = true
	c.ns.ReportLines = function()
		error("lines broke", 0)
	end
	c.G.SlashCmdList.SKILLUPFOREVER("report")
	local _, edit = Window(c)
	local text = edit:GetText()
	has(text, "SkillUpForever 1.2.3", "lines failed: the header")
	has(text, "Report lines failed: lines broke", "lines failed: said")
	has(text, "- [report lines] x1 lines broke", "lines failed: caught")
end

-- With a profession open, the audit: its summary, six mismatches and how many more.
do
	local thresholds, recipes = {}, {}
	for id = 301, 308 do
		thresholds[id] = { 1, 30, 45, 60 }
		recipes[id] = { skillLine = 129, reagents = {} }
	end
	local c = Client.load({ data = { Thresholds = thresholds, RecipeData = recipes, TrainerInferred = {} } })
	c.professions = { { name = "First Aid", icon = 1, rank = 30, max = 75, id = 129 } }
	c.Boot()
	for id = 301, 308 do
		-- The game says orange where the table says yellow at 30.
		c.live[id] = { info = { name = "Bandage " .. id, learned = true, relativeDifficulty = 1, maxTrivialLevel = 0 } }
	end
	c.G.ProfessionsFrame = {
		IsShown = function()
			return true
		end,
	}
	c.G.Professions = {
		GetProfessionInfo = function()
			return { skillLevel = 30, maxSkillLevel = 75, displayName = "First Aid" }
		end,
	}
	local text = table.concat(c.ns.ReportLines(), "\n")
	has(text, "Audit: First Aid at 30: 8 checked, 8 mismatched, 0 without data.", "the audit's summary")
	has(text, "  Bandage 301 (301): table 1/30/45/60 says yellow, game says orange", "a mismatch")
	has(text, "  and 2 more", "six shown, the rest counted")
end

-- The trainer checks: only this character's professions, each one a trainer showed differently, six of them
-- and how many more.
do
	local recipes, fees, seen, spells = {}, {}, {}, {}
	for id = 101, 108 do
		recipes[id] = { skillLine = 129, reagents = {} }
		fees[id] = { 100, 10 }
		seen[id] = { 100, 20, 20 }
		spells[id] = "Bandage " .. id
	end
	recipes[201] = { skillLine = 171, reagents = {} }
	fees[201] = { 100, 10 }
	local c = Client.load({
		saved = { trainer = { [129] = seen, [171] = { [201] = { 100, 30, 30 } } } },
		data = {
			Thresholds = {},
			RecipeData = recipes,
			TrainerFees = fees,
			TrainerRanks = {},
			TrainerInferred = { [101] = 5 },
		},
	})
	c.spells = spells
	c.professions = { { name = "First Aid", icon = 1, rank = 30, max = 75, id = 129 } }
	c.Boot()
	local text = table.concat(c.ns.ReportLines(), "\n")
	has(text, "Trainers: First Aid 1 moved, 0 confirmed, 8 wrong", "this character's profession, counted")
	has(text, "  Bandage 101 (101): bundled 10, trainer 20", "each one shown differently")
	has(text, "  and 2 more", "six shown, the rest counted")
	equal(text:find("(201)", 1, true), nil, "a profession this character lacks is left out")
end

-- Many other addons: the list says how many more, and the report stays one message.
do
	local c = Load()
	for index = 1, 300 do
		c.addons[index] = { ("SomeAddon%03d"):format(index), "1.0." .. index }
	end
	c.G.SlashCmdList.SKILLUPFOREVER("report")
	local _, edit = Window(c)
	local text = edit:GetText()
	equal(#text <= 2000, true, "many addons: one message")
	has(text, "Other addons (300): SomeAddon001 1.0.1, ", "many addons: counted")
	equal(text:find("SomeAddon300", 1, true), nil, "many addons: the last left out")
end

Client.report("report_spec")
