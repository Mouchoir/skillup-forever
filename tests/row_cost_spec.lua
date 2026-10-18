-- Run from the repository root: luajit tests/row_cost_spec.lua
-- A recipe row's money: cost per skill-up by default, or what one craft costs or earns, which also prices a recipe
-- that no longer gives skill. A profit leads with a green "+" and a cost with a red "-".
local Client = dofile("tests/client.lua")
local equal = Client.equal

local c = Client.load({})
local ns = c.ns

local PLUS, MINUS = "|cff40ff40+|r", "|cffff2020-|r"
local T = { 10, 20, 30, 40 }

ns.db.showSkill = false
ns.db.showCost = true

equal(ns.db.rowCost, "skillup", "rows show the cost per skill-up by default")
equal(
	ns.FormatRow({ thresholds = T, chance = 0.25, net = 200, perSkillUp = 800 }),
	"25% · " .. MINUS .. "800c",
	"a cost per skill-up leads with a red minus"
)
equal(
	ns.FormatRow({ thresholds = T, chance = 0.25, net = -200, perSkillUp = -800 }),
	"25% · " .. PLUS .. "800c",
	"a profit per skill-up leads with a green plus"
)
equal(
	ns.FormatRow({ thresholds = T, chance = 0, net = -600 }),
	"0%",
	"a recipe that gives no skill has no cost per skill-up"
)

ns.db.rowCost = "craft"
equal(
	ns.FormatRow({ thresholds = T, chance = 0.25, net = -200, perSkillUp = -800 }),
	"25% · " .. PLUS .. "200c",
	"per craft shows one craft's profit"
)
equal(
	ns.FormatRow({ thresholds = T, chance = 0.25, net = 200, perSkillUp = 800 }),
	"25% · " .. MINUS .. "200c",
	"and one craft's cost"
)
equal(
	ns.FormatRow({ thresholds = T, chance = 0, net = -600 }),
	"0% · " .. PLUS .. "600c",
	"and prices a recipe that no longer gives skill"
)
equal(ns.FormatRow({ thresholds = T, chance = 0.5 }), "50%", "an unpriced recipe shows only its chance")

ns.db.showCost = false
equal(ns.FormatRow({ thresholds = T, chance = 0, net = -600 }), "0%", "Show cost per skill-up off hides the money")
ns.db.showCost, ns.db.rowCost = true, "skillup"

Client.report("row_cost_spec")
