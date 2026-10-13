-- Run from the repository root: luajit tests/api_spec.lua
-- The public API over a small recipe set, with the whole addon loaded: every step, price and NPC comes from what
-- the client holds, through the same files the game runs.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local THREAD, LEATHER, SILK, BAR = 2321, 2319, 4306, 2840
local GLOVES, HILLMANS, LEATHER_RECIPE, SHIRT, BRACERS = 1, 2, 9, 3, 4
local GINA, TELONIS = 77, 88

local c = Client.load({
	boot = false,
	saved = { routeTargets = { [197] = 60, [164] = 20 }, trackedProfessions = { [197] = true } },
	data = {
		Thresholds = {
			[GLOVES] = { 125, 140, 155, 165 },
			[HILLMANS] = { 145, 155, 165, 175 },
			[SHIRT] = { 40, 60, 70, 80 },
			[BRACERS] = { 1, 20, 40, 60 },
		},
		RecipeData = {
			[GLOVES] = {
				skillLine = 165,
				reagents = { { itemID = LEATHER, quantity = 6 }, { itemID = THREAD, quantity = 2 } },
				output = { itemID = 4253, quantity = 1 },
			},
			[HILLMANS] = {
				skillLine = 165,
				reagents = { { itemID = LEATHER, quantity = 8 }, { itemID = THREAD, quantity = 1 } },
				output = { itemID = 4247, quantity = 1 },
			},
			[LEATHER_RECIPE] = { skillLine = 165, reagents = {}, output = { itemID = LEATHER, quantity = 1 } },
			[SHIRT] = { skillLine = 197, reagents = { { itemID = SILK, quantity = 1 } } },
			[BRACERS] = { skillLine = 164, reagents = { { itemID = BAR, quantity = 1 } } },
		},
		TrainerFees = { [HILLMANS] = { 1800, 145 } },
		TrainerRanks = {},
		ItemSellPrices = {},
		GatheredBy = {},
		VendorPrices = { [THREAD] = 100, [BAR] = 10 },
		ProfessionTrainers = { [165] = { { TELONIS, 300 } } },
		ScrollDrops = {},
		WorldDrops = {},
	},
	-- Who sells thread and where the trainer stands come from the player's QuestieDB.
	questie = {
		items = { [THREAD] = { class = 7, vendors = { GINA } } },
		npcs = {
			[GINA] = { name = "Gina", spawns = { [10] = { { 50, 50 } } }, side = "AH" },
			[TELONIS] = { name = "Telonis", spawns = { [141] = { { 50, 50 } } }, side = "AH" },
		},
		areas = { [10] = 10, [141] = 11 },
	},
})
local ns, API = c.ns, c.G.SkillUpForever.API
equal(API.version, 1, "version 1")
equal(#API.Professions(), 0, "nothing before the saved variables load")

c.spells = {
	[GLOVES] = "Toughened Leather Gloves",
	[HILLMANS] = "Hillman's Leather Gloves",
	[BRACERS] = "Copper Bracers",
}
c.known = { [GLOVES] = true, [LEATHER_RECIPE] = true, [SHIRT] = true, [BRACERS] = true }
-- The gloves sell for nothing; Hillman's sell for most of their reagents, so they are the cheaper craft from
-- 145, where a trainer teaches them: 8 leather and a thread is 4100, less 3100.
c.items = {
	[THREAD] = { name = "Fine Thread" },
	[LEATHER] = { name = "Medium Leather" },
	[4253] = { sell = 0 },
	[4247] = { sell = 3100 },
}
c.bags = { [LEATHER] = 40, [SILK] = 20, [BAR] = 20 }
c.auction = { [LEATHER] = 500, [SILK] = 50 }
c.maps = { [0] = { mapID = 10, name = "Darkshire" }, [1] = { mapID = 11, name = "Darnassus" } }
-- Tailoring and Blacksmithing plan ten sure crafts; Leatherworking plans to its cap.
c.professions = {
	{ name = "Leatherworking", icon = 136247, rank = 142, max = 150, id = 8165 },
	{ name = "Tailoring", icon = 136247, rank = 50, max = 75, id = 8197 },
	{ name = "Blacksmithing", icon = 136247, rank = 10, max = 75, id = 8164 },
	{ name = "Alchemy", icon = 136247, rank = 0, max = 0, id = 8171 },
}
c.Boot()
equal(#c.chat, 0, "the addon starts without a word")

local list = API.Professions()
-- Until the vendors and trainers are read from QuestieDB, a step says what to find and routes nowhere.
local early = list[3].steps
equal(early[1].detail, "Vendor · 800c", "before the vendors are read a buy names none")
equal(early[1].nav, false, "and routes nowhere")
equal(early[3].detail, "Leatherworking trainer · 1800c", "nor does training name a trainer")
c.Advance(0)
list = API.Professions()
-- Tracked first, then reagents in hand, then a purchase first, then nothing to do.
equal(#list, 4, "one entry per profession")
equal(list[1].name, "Tailoring", "a tracked profession leads")
equal(list[2].name, "Blacksmithing", "a craft ready to go beats a shopping trip")
equal(list[3].name, "Leatherworking", "a purchase first comes after")
equal(list[4].name, "Alchemy", "nothing to do comes last")

local lw = list[3]
equal(lw.skillLineID, 165, "skill line")
equal(lw.icon, 136247, "icon")
equal(lw.rank, 142, "rank is base skill")
equal(lw.maxRank, 150, "max rank is the cap")
equal(lw.title, "Journeyman", "the 150 cap is Journeyman")
equal(#lw.steps, 3, "at most three steps")

local buy, craft, train = lw.steps[1], lw.steps[2], lw.steps[3]
equal(buy.kind, "buy", "the thread the bags lack is bought first")
equal(buy.text, "Buy 8 Fine Thread", "buy text")
equal(buy.detail, "Gina, Darkshire · 800c", "buy detail names the nearest vendor and cost")
equal(buy.itemID, THREAD, "buy item")
equal(buy.count, 8, "buy count")
equal(buy.cost, 800, "buy cost")
equal(buy.nav, true, "a vendor can be routed to")
equal(craft.kind, "craft", "then the craft")
-- Three points at 23/25, 22/25 and 21/25 a craft: 3.4 crafts expected, so four.
equal(craft.text, "Craft 4 Toughened Leather Gloves", "craft text")
equal(craft.detail, "142 to 145", "craft detail is its skill range")
equal(craft.spellID, GLOVES, "craft spell")
equal(craft.itemID, 4253, "craft product")
equal(craft.count, 4, "craft count")
equal(craft.cost, nil, "the craft's cost is in its purchases")
equal(craft.nav, false, "a craft has nowhere to go")
equal(train.kind, "train", "then the recipe the route trains next")
equal(train.text, "Train Hillman's Leather Gloves", "train text")
equal(train.detail, "Telonis, Darnassus · 1800c", "train detail names the nearest trainer and fee")
equal(train.spellID, HILLMANS, "train spell")
equal(train.cost, 1800, "train fee")
equal(train.nav, true, "a trainer can be routed to")

equal(#lw.recipes, 2, "the route's crafts")
local gloves, hillmans = lw.recipes[1], lw.recipes[2]
equal(gloves.name, "Toughened Leather Gloves", "recipe name")
equal(gloves.spellID, GLOVES, "recipe spell")
equal(gloves.itemID, 4253, "recipe product")
equal(gloves.count, 4, "recipe crafts")
equal(gloves.fromRank, 142, "recipe from")
equal(gloves.toRank, 145, "recipe to")
equal(gloves.learned, true, "known recipe")
equal(gloves.color, "yellow", "colour at its first skill")
equal(gloves.trainAt, nil, "a known recipe needs no training")
equal(gloves.cost, nil, "and costs no fee")
equal(hillmans.learned, false, "a recipe still to train")
equal(hillmans.trainAt, 145, "trained where the route first uses it")
equal(hillmans.cost, 1800, "its fee")
equal(hillmans.color, "orange", "orange at 145")

local byItem = {}
for _, reagent in ipairs(lw.reagents) do
	byItem[reagent.itemID] = reagent
end
equal(byItem[THREAD].need, 13, "thread for the whole route")
equal(byItem[THREAD].have, 0, "thread in the bags")
equal(byItem[THREAD].source, "vendor", "thread from a vendor")
equal(byItem[LEATHER].need, 64, "leather for the whole route")
equal(byItem[LEATHER].have, 40, "leather in the bags")
equal(byItem[LEATHER].source, "craft", "a learned recipe makes the leather")

-- Nil where SkillUp can't tell: no name, no rank title, no price, nothing planned.
local tailoring = list[1]
equal(tailoring.steps[1].text, "Craft 10 recipe 3", "an unnamed recipe still reads")
equal(tailoring.recipes[1].name, nil, "an unnamed recipe has no name")
equal(tailoring.recipes[1].itemID, nil, "a recipe without a product has no item")
equal(tailoring.reagents[1].source, "auction", "a reagent only Auctionator prices is from the auction house")
local alchemy = list[4]
equal(alchemy.title, nil, "a cap no rank ends at has no title")
equal(#alchemy.steps, 0, "no steps")
equal(#alchemy.recipes, 0, "no recipes")
equal(#alchemy.reagents, 0, "no reagents")

-- Kept until an event says otherwise.
equal(API.Professions(), list, "a second call is the cache")
c.Fire("ITEM_DATA_LOAD_RESULT")
equal(API.Professions(), list, "item data with no name waiting keeps the cache")
c.Fire("BAG_UPDATE_DELAYED")
local rebuilt = API.Professions()
equal(rebuilt ~= list, true, "a bag update rebuilds")
equal(API.Professions(), rebuilt, "once")
ns.Changed("fees")
equal(API.Professions() ~= rebuilt, true, "dropped plans rebuild it")

-- Steps route by travel time to the NPC they name.
local estimates, routed = 0, nil
c.G.ShortestPathForever = {
	API = {
		version = 1,
		Estimate = function()
			estimates = estimates + 1
			return 60
		end,
		Navigate = function(_, _, _, _, title)
			routed = title
			return true
		end,
	},
}
equal(API.Navigate(165, 1), true, "the vendor step routes")
equal(routed, "Gina", "to the vendor")
equal(estimates, 1, "picked by travel")
equal(API.Navigate(165, 3), true, "the training step routes")
equal(routed, "Telonis", "to the trainer")
equal(API.Navigate(165, 2), false, "a craft doesn't route")
equal(API.Navigate(999, 1), false, "an unknown profession doesn't route")

equal(API.OpenRecipes(165), true, "opens a profession")
equal(c.opened[1], 8165, "by the ID the client reported")
equal(API.OpenRecipes(999), false, "not one the character lacks")
-- A refused request is asked once more only by another ID.
local OpenTradeSkill = c.G.C_TradeSkillUI.OpenTradeSkill
c.G.C_TradeSkillUI.OpenTradeSkill = function(id)
	OpenTradeSkill(id)
	return false
end
c.opened = {}
equal(API.OpenRecipes(165), false, "a profession the client will not open")
equal(table.concat(c.opened, " "), "8165 165", "is asked by its own ID, then the skill line")
c.professions[1].id = 165
c.opened = {}
API.OpenRecipes(165)
equal(table.concat(c.opened, " "), "165", "and once when the client reports the skill line itself")
c.professions[1].id = 8165
c.G.C_TradeSkillUI.OpenTradeSkill = OpenTradeSkill

-- Tracking changes the order, so the next call rebuilds.
local tracked = API.Professions()
ns.SetTracked(165, true)
equal(API.Professions() ~= tracked, true, "tracking a profession rebuilds the list")
equal(API.Professions()[2].name, "Leatherworking", "and it moves ahead of the untracked ones")

-- What the client reports reaches the list through every file between: a merchant seen to sell thread for
-- less re-prices the purchase.
local function Leatherworking()
	for _, entry in ipairs(API.Professions()) do
		if entry.skillLineID == 165 then
			return entry
		end
	end
end
c.merchant = { { itemID = THREAD, price = 250, stackCount = 5 } }
c.Fire("MERCHANT_SHOW")
equal(Leatherworking().steps[1].cost, 400, "a cheaper vendor price reaches the buy step")
equal(Leatherworking().steps[1].detail, "Gina, Darkshire · 400c", "and its text")
c.merchant = nil
c.Fire("MERCHANT_CLOSED")
-- Thread in the bags: nothing to buy, so the craft leads.
c.bags[THREAD] = 8
c.Fire("BAG_UPDATE_DELAYED")
equal(Leatherworking().steps[1].kind, "craft", "reagents arriving in the bags drop the purchase")
-- Hillman's stays on the route even with its sale counted for nothing: the gloves' 0.8 chance needs two
-- crafts a point, which costs more than Hillman's certain one.
equal(#Leatherworking().recipes, 2, "Hillman's is on the route while its sale counts")
c.SetSetting("craftValue_choice", 1)
equal(ns.db.craftValue, "none", "the options panel's slider writes the saved choice")
equal(#Leatherworking().recipes, 2, "a setting changed in the options panel re-plans the public list")
equal(Leatherworking().recipes[1].spellID, GLOVES, "with the gloves first")
equal(Leatherworking().recipes[2].spellID, HILLMANS, "and Hillman's carrying the rest")

Client.report("api_spec")
