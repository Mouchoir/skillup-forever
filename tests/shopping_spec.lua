-- Run from the repository root: luajit tests/shopping_spec.lua
-- The objective tracker's lines and the merchant's buy button, with the whole addon loaded: what they show
-- follows the client's prices, bags and merchant through the plan.
local Client = dofile("tests/client.lua")
local equal = Client.equal

local BANDAGE, HEAVY, SILK = 1, 2, 3
local c = Client.load({
	saved = { routeTargets = { [129] = 80 }, trackedProfessions = { [129] = true } },
	-- First Aid in miniature: a known bandage, a better one to train at 40, and Journeyman from 50.
	data = {
		Thresholds = { [BANDAGE] = { 1, 30, 45, 60 }, [HEAVY] = { 40, 50, 75, 100 } },
		RecipeData = {
			[BANDAGE] = { skillLine = 129, reagents = { { itemID = SILK, quantity = 1 } } },
			[HEAVY] = { skillLine = 129, reagents = { { itemID = SILK, quantity = 2 } } },
		},
		TrainerFees = { [HEAVY] = { 100, 40 } },
		TrainerRanks = { [129] = { { 150, 500, 50, 0 } } },
		ItemSellPrices = {},
		GatheredBy = {},
		VendorPrices = {},
		ProfessionTrainers = {},
	},
})
local ns = c.ns
local module = c.G.SkillUpForeverObjectiveTracker
equal(c.host.IsAttached(module), true, "attaches to private host immediately")
c.EnterWorld()
equal(#c.tracker, 1, "native initialization cannot change private ownership")
c.G.ForeverTrackerHost, c.tracker = nil, {}
c.Advance(0)
equal(#c.tracker, 0, "missing private host remains inert")
c.G.ForeverTrackerHost = c.host
c.EnterWorld()
equal(#c.tracker, 0, "late host waits for the deferred callback")
c.Advance(0)
equal(c.tracker[1], module, "deferred callback attaches after late host publication")

c.level = 20
c.spells[HEAVY] = "Heavy Linen Bandage"
c.items[SILK] = { name = "Linen Cloth" }
c.known[BANDAGE] = true
c.auction[SILK] = 10
c.professions = { { name = "First Aid", rank = 40, max = 75, id = 129 } }

-- Heavy Linen Bandage is certain at 40 where the bandage's falling chance already costs more a
-- point, so the plan trains it at once: the tracker leads with the page's first training step.
local lines = c.Tracker()[1].lines
local walked = ns.PlanRoute(ns.RouteProfessions()[129]).steps
equal(walked[1].training and walked[1].training.recipeID, HEAVY, "the route page trains the recipe first")
equal(walked[3].rank and walked[3].rank.name, "Journeyman", "and the rank after")
equal(lines[1].key, "Train", "the tracker leads with training")
equal(lines[1].text, "Train Heavy Linen Bandage at 40 |cff808080(+1 more)|r", "the same training")
equal(lines[2].key, SILK, "then the reagent still missing")

ns.db.showTracker = false
ns.Changed("settings")
equal(#c.Tracker(), 0, "hiding the tracker removes every profession block")
equal(ns.db.trackedProfessions[129], true, "hiding keeps the profession tracked")
equal(ns.db.routeTargets[129], 80, "hiding keeps the profession target")
ns.db.showTracker = true
ns.Changed("settings")
equal(#c.Tracker(), 1, "showing restores the tracked profession")

-- Auctionator loses the only price there was: the scan reaches the tracker, which redraws to say why
-- nothing can be crafted, not that the reagents are in hand.
local redraws = module.dirty or 0
c.auction[SILK] = nil
c.AuctionatorScan()
equal(module.dirty, redraws + 1, "a price change redraws the tracker once")
lines = c.Tracker()[1].lines
equal(#lines, 1, "one line")
equal(lines[1].key, "Blocked", "a blocked route says so")
equal(
	lines[1].text,
	"Auctionator hasn't seen these reagents yet: scan the auction house with it to price them.",
	"with the route page's reason"
)
c.auction[SILK] = 10
c.AuctionatorScan()

-- The merchant's button and its purchase, including missing stack data: seven cloth short of the route.
local function Needed()
	return ns.TrackedNeeds()[1].items[1].need
end
c.bags[SILK] = Needed() - 7
c.money = 10000
c.merchant = { { itemID = SILK, name = "Linen Cloth", price = 100, stackCount = 5 } }
c.Fire("MERCHANT_SHOW")
local button
for _, frame in ipairs(c.frames) do
	if frame.parent == c.G.MerchantFrame then
		button = frame
	end
end
equal(button.shown, true, "known merchant stack enables purchasing")
equal(button.text, "Buy tracked reagents  200c", "purchase price accounts for whole stacks")
-- The button asks first, on a dialog of the addon's own on the merchant's window.
local function Dialog()
	for _, frame in ipairs(c.frames) do
		if frame.parent == c.G.MerchantFrame and frame.Accept then
			return frame
		end
	end
end
equal(Dialog(), nil, "nothing asks before a click")
button.scripts.OnClick()
local dialog = Dialog()
equal(dialog.shown, true, "a click asks before buying")
equal(dialog.Text.text, "Buy 10 Linen Cloth for 200c?", "with what it buys and the total cost")
equal(#c.purchased, 0, "and buys nothing yet")
dialog.Cancel.scripts.OnClick()
equal(dialog.shown, false, "cancel closes it")
equal(#c.purchased, 0, "having bought nothing")
-- The need changes while it is open: what it showed is not what a click would buy, so it goes.
button.scripts.OnClick()
c.bags[SILK] = c.bags[SILK] + 5
c.Fire("BAG_UPDATE_DELAYED")
equal(dialog.shown, false, "a changed cost closes the question")
dialog.Accept.scripts.OnClick()
equal(#c.purchased, 0, "and a late accept buys nothing")
c.bags[SILK] = c.bags[SILK] - 5
c.Fire("BAG_UPDATE_DELAYED")
equal(button.text, "Buy tracked reagents  200c", "the full need is back")
-- The player can do without the button.
c.SetSetting("merchantButton", false)
equal(button.shown, false, "the setting hides the button")
c.SetSetting("merchantButton", true)
equal(button.shown, true, "and brings it back")
-- A click only reaches a button that is enabled, and buys once the player accepts.
local function Click()
	if button:IsEnabled() then
		button.scripts.OnClick()
		if dialog.shown then
			dialog.Accept.scripts.OnClick()
		end
	end
end
Click()
equal(dialog.shown, false, "accepting closes the question")
equal(c.purchased[1].count, 10, "purchase callback buys complete stacks in units")
equal(button:IsEnabled(), false, "the button is off while the order is on its way")
Click()
button.scripts.OnClick()
c.Fire("MERCHANT_UPDATE")
c.AuctionatorScan()
Click()
equal(#c.purchased, 1, "a second click before the bags update orders nothing more")
-- The server refused it (full bags): no bag changes, and the button comes back for another try.
c.Advance(3)
equal(button:IsEnabled(), true, "an order that never arrives gives the button back")
Click()
equal(#c.purchased, 2, "which orders again")
-- The merchant closing ends the wait too, and a settled order's timer cannot cut a later order's wait short.
c.merchant = nil
c.Fire("MERCHANT_CLOSED")
c.merchant = { { itemID = SILK, price = 100, stackCount = 5 } }
c.Fire("MERCHANT_SHOW")
equal(button:IsEnabled(), true, "another merchant starts with the button on")
c.Advance(2)
Click()
equal(#c.purchased, 3, "and takes an order")
c.Advance(1)
equal(button:IsEnabled(), false, "which the earlier order's timer leaves waiting")
c.bags[SILK] = c.bags[SILK] + 5
c.Fire("BAG_UPDATE_DELAYED")
equal(button:IsEnabled(), true, "the bag update gives the button back")
equal(button.text, "Buy tracked reagents  100c", "for what is still missing")
c.Advance(3)
for _, invalid in ipairs({ false, 0, -1 }) do
	c.merchant[1].stackCount = invalid or nil
	c.purchased = {}
	c.Fire("MERCHANT_UPDATE")
	equal(button.shown, false, "unknown or invalid stack hides purchase action")
	button.scripts.OnClick()
	equal(#c.purchased, 0, "unknown or invalid stack cannot buy invented units")
end
c.merchant = nil
c.Fire("MERCHANT_CLOSED")
equal(button.shown, false, "the button goes with the merchant")
equal(#c.chat, 0, "and none of it says anything in chat")

-- The Auctionator list of what the tracked route still buys is kept up to date on its own: written
-- once, left alone while the need is the same, and emptied when the bags cover it.
equal(ns.AuctionListName("First Aid"), "SkillUp: First Aid", "the list is named for the profession")
equal(ns.AuctionatorAutoscan(), nil, "an unread option says nothing")
c.auctionAutoscan = false
equal(ns.AuctionatorAutoscan(), false, "the scan-on-open option reads as off")
equal(c.shoppingLists["SkillUp: First Aid"], nil, "gather mode writes no Auctionator list")
ns.SetCollectMode("auction")
local list = c.shoppingLists["SkillUp: First Aid"]
equal(type(list), "table", "buying keeps an Auctionator list")
equal(#list, 1, "with the route's one auction reagent")
equal(list[1], "Linen Clothx" .. (Needed() - ns.Have(SILK)), "and what the route still needs")
c.Fire("BAG_UPDATE_DELAYED")
equal(c.shoppingLists["SkillUp: First Aid"], list, "an unchanged need does not rewrite the list")
c.bags[SILK] = Needed()
c.Fire("BAG_UPDATE_DELAYED")
equal(#c.shoppingLists["SkillUp: First Aid"], 0, "a covered need empties the list")

-- The section hangs on the shared host, never on Blizzard's tracker manager: a client without the manager
-- still gets it.
local bare = Client.load({ trackerManager = false })
equal(bare.host.IsAttached(bare.G.SkillUpForeverObjectiveTracker), true, "the section needs no tracker manager")
equal(#bare.chat, 0, "and says nothing about a missing tracker")

Client.report("shopping_spec")
