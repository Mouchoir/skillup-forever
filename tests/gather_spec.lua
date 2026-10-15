-- Run from the repository root: luajit tests/gather_spec.lua
-- Issue #122: herb and ore node tooltips name the skill the node asks and colour it at yours; a skinnable
-- corpse shows "?" until the skinning rule is confirmed on Forever.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local c = Client.load({ data = { NodeSkills = { ["Copper Vein"] = { 186, 1 }, ["Iron Deposit"] = { 186, 125 } } } })
local ns = c.ns
c.professions = {
	{ name = "Mining", icon = 1, rank = 140, max = 150, id = 186 },
	{ name = "Skinning", icon = 1, rank = 60, max = 75, id = 393 },
}
c.Boot()

-- A tooltip that keeps the double lines it was given.
local function Tooltip(unit)
	local tooltip = { lines = {} }
	function tooltip.IsForbidden()
		return false
	end
	function tooltip.GetUnit()
		return "corpse", unit
	end
	function tooltip.AddDoubleLine(_, left, right, _, _, _, r, g, b)
		tooltip.lines[#tooltip.lines + 1] = { left = left, right = right, color = { r, g, b } }
	end
	return tooltip
end
local function Show(kind, lines, unit)
	local tooltip = Tooltip(unit)
	local data = { lines = {} }
	for i, text in ipairs(lines) do
		data.lines[i] = { leftText = text }
	end
	for _, call in ipairs(c.postCalls[kind]) do
		call(tooltip, data)
	end
	return tooltip.lines
end
local OBJECT, UNIT = c.G.Enum.TooltipDataType.Object, c.G.Enum.TooltipDataType.Unit

local iron = Show(OBJECT, { "Iron Deposit", "Requires Mining" })
equal(#iron, 1, "a node gets one line")
equal(iron[1].left, "Mining 125", "the skill it asks")
equal(iron[1].right, "orange until 150", "orange from there to 25 past it, at 140")
local copper = Show(OBJECT, { "Copper Vein" })
equal(copper[1].right, "grey", "grey 100 past the requirement")
c.professions[1].rank = 120
equal(Show(OBJECT, { "Iron Deposit" })[1].right, "Skill range starts at 125", "below it, where it starts")
c.professions[1].rank = 160
equal(Show(OBJECT, { "Iron Deposit" })[1].right, "yellow until 175", "yellow from 25 past it")
equal(#Show(OBJECT, { "Mailbox" }), 0, "an object that is no node gets nothing")

-- Only for a profession you have, only in English, and only while the setting is on.
c.professions[1].name, c.professions[1].id = "Tailoring", 197
equal(#Show(OBJECT, { "Iron Deposit" }), 0, "no Mining, no line")
c.professions[1].name, c.professions[1].id = "Mining", 186
c.locale = "deDE"
equal(#Show(OBJECT, { "Iron Deposit" }), 0, "another language matches nothing")
c.locale = "enUS"
c.SetSetting("gatherTooltip", false)
equal(#Show(OBJECT, { "Iron Deposit" }), 0, "the setting turns it off")
c.SetSetting("gatherTooltip", true)

-- Skinning: the corpse says it is skinnable in the client's own words, and the rule is not confirmed yet.
local skin = Show(UNIT, { "Plainstrider", "Level 12 Beast", "Skinnable" }, "target")
equal(#skin, 1, "a skinnable corpse gets one line")
equal(skin[1].left, "Skinning", "for Skinning")
equal(skin[1].right, "?", "with ? until the rule is confirmed")
equal(#Show(UNIT, { "Plainstrider", "Level 12 Beast" }, "target"), 0, "a corpse not skinnable gets nothing")
local rock = Show(UNIT, { "Rock Elemental", "Requires Mining" }, "target")
equal(rock[1] and rock[1].left, "Mining", "a corpse to mine is Mining's")
equal(rock[1] and rock[1].right, "?", "with ? too")
equal(#Show(UNIT, { "Bog Beast", "Requires Herbalism" }, "target"), 0, "no Herbalism, no line")
equal(ns.Model.CorpseSkill(12), nil, "the rule answers nothing until it is switched on")
-- The rule it will use once confirmed.
local Rule = ns.Model.ClassicCorpseSkill
equal(Rule(5), 1, "1 up to level 10")
equal(Rule(12), 20, "ten a level from 11 to 20")
equal(Rule(20), 100, "100 at 20")
equal(Rule(30), 150, "five times the level above")
equal(Rule(-1), nil, "a skull level has none")
equal(table.concat(ns.Model.GatherThresholds(125), " "), "125 150 175 225", "Classic's gathering bands")

Client.report("gather_spec")
