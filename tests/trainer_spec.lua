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
		return { [COOKING] = { name = "Cooking" } }
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

Client.report("trainer_spec")
