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

Client.report("locale_spec")
