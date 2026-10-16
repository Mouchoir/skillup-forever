-- Run from the repository root: luajit tests/locale_spec.lua
-- Every phrase the player reads goes through L, so CurseForge's translators see it.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local function Read(path)
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	return text
end

-- The calls and fields this addon draws text through, each up to the text argument.
local SINKS = {
	":SetText%(%s*",
	":SetFormattedText%(%s*",
	":AddLine%(%s*",
	":AddDoubleLine%(%s*",
	":AddDoubleLine%([^,\n]+,%s*",
	"GameTooltip_%w+%(%s*[%w_]+,%s*",
	"[^:]AddLine%(%s*[%w_]+,%s*",
	"ns%.Print%(%s*",
	"ns%.AddNearest%(%s*[%w_]+,%s*",
	":Message%(%s*",
	":CreateButton%(%s*",
	":CreateTitle%(%s*",
	":CreateRadio%(%s*",
	":AddObjective%(%s*[^,\n]+,%s*",
	":SetHeader%(%s*",
	"CreateInset%(%s*",
	'Checkbox%(%s*"[^"]*",%s*',
	'Checkbox%(%s*"[^"]*",%s*[^\n]+\n%s*',
	'Dropdown%(%s*"[^"]*",%s*',
	"tooltipText%s*=%s*",
	"headerText%s*=%s*",
	"[{,]%s*text%s*=%s*",
	"reason%s*=%s*",
	"title%s*=%s*",
}
-- A settings option, { value, label }, closes after its label.
local OPTION = '{%s*"%l+",%s*"([^"\n]*)"%s*}'

-- Literals that may stay English. /su audit and /su report build their lines as data, so none pass a sink.
local ALLOWED = {}

-- Hardcoded text passed straight to a sink, as "file: literal" lines.
local function Unwrapped(name, source)
	local found, used = {}, {}
	-- Comment lines hold examples of the output, not code.
	source = ("\n" .. source):gsub("\n%s*%-%-[^\n]*", "\n")
	local patterns = { OPTION }
	for _, sink in ipairs(SINKS) do
		patterns[#patterns + 1] = sink .. '"([^"\n]*)"'
		patterns[#patterns + 1] = sink .. 'string%.format%(%s*"([^"\n]*)"'
	end
	for _, pattern in ipairs(patterns) do
		for text in source:gmatch(pattern) do
			-- Colour codes and format specifiers are not words.
			local words = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%%[%-%d%.]*%a", "")
			local allowed = ALLOWED[name] and ALLOWED[name][text]
			if allowed then
				used[text] = true
			elseif words:find("%a") then
				found[#found + 1] = name .. ": " .. text
			end
		end
	end
	return found, used
end

-- The guard itself: a bare literal is caught, a wrapped one and a colour code are not.
equal(#Unwrapped("x.lua", 'label:SetText("Hello")'), 1, "a bare SetText literal is caught")
equal(#Unwrapped("x.lua", 'ns.Print(string.format("%d left", n))'), 1, "a bare format string is caught")
equal(#Unwrapped("x.lua", 'label:SetText(L["Hello"])'), 0, "a wrapped phrase passes")
equal(#Unwrapped("x.lua", 'ns.Print("|cffff4040" .. L["Hi"] .. "|r")'), 0, "colour codes are not words")
equal(#Unwrapped("x.lua", '\t-- label:SetText("Hello")'), 0, "comments are skipped")

local unwrapped = {}
for line in Read("SkillUpForever.toc"):gmatch("[^\r\n]+") do
	local path = line:gsub("\\", "/")
	if path:match("%.lua$") and not path:match("^Locales/") and not path:match("^Data/") then
		local found, used = Unwrapped(path, Read(path))
		for _, hit in ipairs(found) do
			unwrapped[#unwrapped + 1] = hit
		end
		for text in pairs(ALLOWED[path] or {}) do
			equal(used[text], true, path .. " still prints the allowed literal " .. text)
		end
	end
end
equal(table.concat(unwrapped, "\n"), "", "player-visible literals outside L")

local pipe = assert(io.popen("python3 tools/phrases.py"))
local phrases = pipe:read("*a")
pipe:close()
equal(#phrases > 0, true, "tools/phrases.py prints the phrases")
equal(Read("Locales/phrases.txt"), phrases, "Locales/phrases.txt is python3 tools/phrases.py's output")
assert(loadfile("Locales/phrases.txt"), "the translation template is valid Lua")

-- CurseForge's localization export is gone: the packager fails a release on any keyword asking for it.
local keyword = "@local" .. "ization"
pipe = assert(io.popen("git grep -n -F -e '" .. keyword .. "' -- ."))
equal(pipe:read("*a"), "", "no " .. keyword .. " keyword in the tree")
pipe:close()

-- Untranslated phrases fall back to the English key.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("SkillUpForever", ns)
equal(ns.L["Craft next"], "Craft next", "a missing translation is the English phrase")

-- A sample argument for each placeholder in the English key, in order (a positional %2$s counts as one).
local function Samples(key)
	local args = {}
	for conversion in key:gsub("%%%%", ""):gsub("%%%d+%$", "%%"):gmatch("%%[%-+#0]*%d*%.?%d*([a-zA-Z])") do
		args[#args + 1] = conversion == "s" and "Sample" or 7
	end
	return args
end

-- string.format with WoW's positional placeholders (%2$s), which LuaJIT's lacks.
local function Format(text, args)
	if not text:find("%%%d+%$") then
		return string.format(text, unpack(args))
	end
	local ordered = {}
	local plain = text:gsub("%%(%d+)%$", function(position)
		ordered[#ordered + 1] = args[tonumber(position)]
		return "%"
	end)
	return string.format(plain, unpack(ordered))
end
equal(Format("%2$s, %1$d", { 3, "a" }), "a, 3", "positional placeholders reorder their arguments")

-- Every translation the TOC loads: its GetLocale guard, then each line formats with the English key's arguments.
local loaded = 0
for line in Read("SkillUpForever.toc"):gmatch("[^\r\n]+") do
	local locale = line:match("^Locales\\(%a%a%u%u)%.lua$")
	if locale and locale ~= "enUS" then
		loaded = loaded + 1
		local path = "Locales/" .. locale .. ".lua"
		-- A file with machine lines says so on its first line; one that people have fully translated need not.
		local source = Read(path)
		local marked = source:find("^%-%- Machine translated %(%d+%-%d+%-%d+%); corrections welcome: https://") ~= nil
		equal(marked or not source:find("%-%- mt\n"), true, path .. " starts with the machine-translation note")
		local stub = { L = setmetatable({}, getmetatable(ns.L)) }
		local chunk = assert(loadfile(path))
		local env = setmetatable({
			GetLocale = function()
				return "enUS"
			end,
		}, { __index = _G })
		setfenv(chunk, env)
		chunk("SkillUpForever", stub)
		equal(next(stub.L), nil, path .. " leaves another client's phrases alone")
		env.GetLocale = function()
			return locale
		end
		chunk("SkillUpForever", stub)
		local count = 0
		for key, text in pairs(stub.L) do
			count = count + 1
			local args = Samples(key)
			equal(type(text), "string", path .. ": " .. key .. " is text")
			-- A line with no placeholder is shown as it is ("5% cut"), never formatted.
			-- Lua ignores spare arguments, so a dropped placeholder is caught by counting.
			equal(#Samples(text), #args, path .. ": " .. key .. " keeps its placeholders")
			if #args > 0 or key:find("%%%%") then
				local ok, result = pcall(Format, text, args)
				equal(ok, true, path .. ": " .. key .. " formats (" .. tostring(result) .. ")")
			end
		end
		equal(count > 0, true, path .. " translates something")
	end
end
-- check_locales checks every Locales/<locale>.lua is in the TOC; this only needs some to have run.
equal(loaded > 0, true, "the TOC loads the translations")

Client.report("locale_spec")
