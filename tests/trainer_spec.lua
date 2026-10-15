-- Run from the repository root: luajit tests/trainer_spec.lua
-- The trainer window over a Cooking trainer: what it charges is recorded and replaces the bundled fee in the plan.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local COOKING, CAMPFIRE, BREAD = 185, 818, 37836
local hooks, timers, changes = {}, {}, {}
local tracked = {}
local dropPlans
-- { name, kind, fee, required skill, taught spell }: the window's rows, in its order.
local services = {}
local ns = {
	db = { trainer = {}, trainerRanks = {}, routeTargets = { [COOKING] = 100 }, showTrainer = true },
	Thresholds = { [CAMPFIRE] = { 1, 100, 150, 200 }, [BREAD] = { 1, 30, 35, 38 } },
	RecipeData = {
		[CAMPFIRE] = { skillLine = COOKING, reagents = {} },
		[BREAD] = { skillLine = COOKING, reagents = {} },
	},
	RecipeNames = { [COOKING] = { ["Spice Bread"] = BREAD } },
	TrainerFees = {},
	TrainerInferred = {},
	Gear = {
		ProfessionName = function(skillLine)
			return skillLine == COOKING and "Cooking" or "?"
		end,
	},
	RecipeScrolls = {},
	Catalogue = { Recipe = function() end },
	TrainerRanks = { [COOKING] = { { 150, 500, 50, 10 } } },
	WhenStale = function(name, handler)
		if name == "plans" then
			dropPlans = handler
		end
	end,
	Changed = function(kind)
		changes[#changes + 1] = kind
		dropPlans()
	end,
	AutoTrack = function(skillLine)
		tracked[#tracked + 1] = skillLine
	end,
	IsLearned = function(id)
		return id == CAMPFIRE
	end,
	NetCost = function()
		return 1
	end,
	PlayerProfessions = function()
		return { [COOKING] = { name = "Cooking", base = 60 } }
	end,
}
local frame = {
	IsShown = function()
		return true
	end,
	ScrollBox = { ForEachFrame = function() end },
	skillStepButton = {
		IsShown = function()
			return false
		end,
	},
}
local env = setmetatable({
	APPRENTICE = "Apprentice",
	JOURNEYMAN = "Journeyman",
	EXPERT = "Expert",
	ARTISAN = "Artisan",
	ClassTrainerFrame = frame,
	Enum = { TrainerType = { Tradeskills = 1 } },
	C_Trainer = {
		GetTrainerType = function()
			return 1
		end,
	},
	C_Timer = {
		After = function(_, fn)
			timers[#timers + 1] = fn
		end,
	},
	C_TooltipInfo = {
		GetTrainerService = function(index)
			return { id = services[index][5] }
		end,
	},
	hooksecurefunc = function(name, fn)
		hooks[name] = fn
	end,
	CreateFrame = function()
		return { RegisterEvent = function() end, SetScript = function() end }
	end,
	UnitLevel = function()
		return 20
	end,
	GetMoney = function()
		return 100000
	end,
	GetNumTrainerServices = function()
		return #services
	end,
	GetTrainerServiceInfo = function(index)
		return services[index][1], services[index][2]
	end,
	GetTrainerServiceCost = function(index)
		return services[index][3]
	end,
	GetTrainerServiceSkillReq = function(index)
		return "Cooking", services[index][4], true
	end,
	GetTrainerTradeskillRankValues = function()
		return 60, 75, 0
	end,
	GetTrainerServiceStepIndex = function() end,
	C_Spell = {
		GetSpellName = function(id)
			return ({ [BREAD] = "Spice Bread", [CAMPFIRE] = "Basic Campfire" })[id]
		end,
	},
}, { __index = _G })
for _, file in ipairs({ "Locales/enUS.lua", "Core/Model.lua", "Core/Plan.lua", "Integrations/Trainer.lua" }) do
	setfenv(assert(loadfile(file)), env)("SkillUpForever", ns)
end
ns.AttachTrainer()

-- The window updating, and the frame after it.
local function Open(rows)
	services = rows
	hooks.ClassTrainerFrame_Update()
	table.remove(timers)()
end
local profession =
	{ skillLine = COOKING, name = "Cooking", base = 60, modifier = 0, skill = 60, max = 75, capped = false }
local function Journeyman()
	return ns.PlanRoute(profession).ranks[1]
end

equal(Journeyman().fee, 500, "the bundled fee before a trainer is seen")

-- A rank is the one row that is no recipe and wants the skill the rank does.
Open({ { "Spice Bread", "available", 40, 1, BREAD }, { "Journeyman Cook", "available", 450, 50 } })
equal(tracked[#tracked], COOKING, "opening the Cooking trainer asks to track Cooking")
equal(ns.db.trainer[COOKING][BREAD][1], 40, "a recipe's fee is recorded")
equal(ns.db.trainerRanks[COOKING][150], 450, "and the rank's, under the cap it trains to")
equal(Journeyman().fee, 450, "what the trainer charges replaces the bundled fee")
equal(Journeyman().reqSkill, 50, "the skill it wants is unchanged")
equal(changes[#changes], "fees", "and the plan is told")

-- A rank already trained, a row wanting another skill, or two rows that could each be the rank record nothing.
ns.db.trainerRanks = {}
Open({ { "Journeyman Cook", "used", 0, 50 } })
equal(ns.db.trainerRanks[COOKING], nil, "a rank already trained has no fee to record")
Open({ { "Mystery Stew", "available", 300, 60 } })
equal(ns.db.trainerRanks[COOKING], nil, "a row wanting another skill is not the rank")
Open({ { "Journeyman Cook", "available", 450, 50 }, { "Mystery Stew", "available", 300, 50 } })
equal(ns.db.trainerRanks[COOKING], nil, "two rows that could be the rank record neither")
equal(Journeyman().fee, 500, "so the bundled fee stands")

-- A recipe row that shows no skill requirement is not recorded as needing none.
ns.db.trainer = {}
Open({ { "Spice Bread", "available", 40, nil, BREAD } })
equal(ns.db.trainer[COOKING][BREAD], nil, "an unknown requirement is not saved as 0")
ns.TrainerFees[BREAD] = { 30, 25 }
Open({ { "Spice Bread", "available", 40, nil, BREAD } })
equal(table.concat(ns.db.trainer[COOKING][BREAD], "/"), "40/25", "the fee is kept with the bundled requirement")
ns.TrainerFees[BREAD] = nil

-- Issue #124: the requirement the trainer showed is saved apart from the one the plan uses, and /su trainers
-- compares it with the bundled one, which the generator moved from classic-db's.
equal(ns.db.trainer[COOKING][BREAD][3], nil, "a row showing no requirement saves none as shown")
local STEW, ROAST = 9001, 9002
ns.RecipeData[STEW] = { skillLine = COOKING, reagents = {} }
ns.RecipeData[ROAST] = { skillLine = COOKING, reagents = {} }
ns.TrainerFees = { [BREAD] = { 30, 25 }, [STEW] = { 30, 40 }, [ROAST] = { 30, 65 }, [CAMPFIRE] = { 30, 1 } }
ns.TrainerInferred = { [BREAD] = 65, [STEW] = 70, [ROAST] = 80 }
ns.db.trainer = {}
local function Checks()
	local by = {}
	for _, check in ipairs(ns.TrainerChecks()) do
		by[check.recipeID] = check
	end
	return by
end
equal(Checks()[CAMPFIRE], nil, "a requirement left as classic-db's, never seen otherwise, needs no check")
equal(Checks()[STEW].classic, 70, "a moved one keeps classic-db's")
equal(Checks()[STEW].shown, nil, "and nothing shown before a visit")
local report = table.concat(ns.TrainerReport(), "\n")
equal(report:find("Cooking: 3 moved, 0 confirmed at a trainer, 0 wrong.", 1, true) ~= nil, true, "the summary")
equal(report:find("Spice Bread (" .. BREAD .. "): bundled 25, classic-db 65", 1, true) ~= nil, true, "at 60")
equal(report:find("(" .. STEW .. "): bundled 40, classic-db 70", 1, true) ~= nil, true, "both are due a visit")
equal(report:find("(" .. ROAST .. ")", 1, true), nil, "one bundled above the skill is not yet")

Open({ { "Spice Bread", "available", 40, 25, BREAD }, { "Stew", "available", 40, 60, STEW } })
equal(table.concat(ns.db.trainer[COOKING][BREAD], "/"), "40/25/25", "the shown requirement is saved")
equal(Checks()[BREAD].shown, 25, "and read back")
report = table.concat(ns.TrainerReport(), "\n")
equal(report:find("Cooking: 3 moved, 1 confirmed at a trainer, 1 wrong.", 1, true) ~= nil, true, "after a visit")
equal(report:find("(" .. STEW .. "): bundled 40, the trainer wants 60", 1, true) ~= nil, true, "the miss")
equal(report:find("classic-db", 1, true), nil, "nothing seen is left to check at this skill")

-- A recipe a trainer listed without any requirement has had its visit, and is not asked for again.
ns.db.trainer[COOKING][STEW] = nil
Open({ { "Stew", "available", 40, nil, STEW } })
equal(Checks()[STEW].visited, true, "listed with no requirement")
equal(Checks()[STEW].shown, nil, "shows none")
equal(table.concat(ns.TrainerReport(), "\n"):find("classic-db", 1, true), nil, "and is not due another visit")

-- A trainer teaching a recipe the bundled data has no trainer for is listed too.
ns.db.trainer[COOKING][CAMPFIRE] = nil
ns.TrainerFees[CAMPFIRE] = nil
ns.db.trainer[COOKING][CAMPFIRE] = { 10, 5, 5 }
equal(Checks()[CAMPFIRE].bundled, nil, "no bundled requirement")
report = table.concat(ns.TrainerReport(), "\n")
equal(
	report:find("Basic Campfire (" .. CAMPFIRE .. "): bundled none, the trainer wants 5", 1, true) ~= nil,
	true,
	"listed"
)

ns.TrainerFees, ns.TrainerInferred, ns.db.trainer = {}, {}, {}
equal(ns.TrainerReport()[1], "no trainer requirements to check.", "nothing to check")

Client.report("trainer_spec")
