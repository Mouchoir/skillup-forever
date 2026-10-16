# Changelog

What changed in each release, in the terms someone levelling a profession would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why a number on the screen changed.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves. API changes other addons' authors need go under an
optional `### For addon authors` subsection after a version's player bullets.

## [Unreleased]

- **SkillUp lets go of the quest tracker when it has nothing to show.** To fit the Forever sections above your quests, SkillUp moves the game's quest tracker. It kept holding it there with no route tracked, *Show tracked professions* off or All Objectives collapsed. Now the tracker goes straight back to where the game, Edit Mode or your UI addon put it, and SkillUp moves it again only once a section has something to show. Thanks to chuujitsuna and another player on CurseForge, who found it stuck mid-screen or over the minimap.

- **Bronze Warhammer is trained by 110.** A player made it at 110 on Forever, where SkillUp's data still asked for Classic's 125, so routes put it off until 125. It now plans it from 110, and `/su trainers` lists it among the guesses a trainer visit confirms. Heavy Sharpening Stone (100) and Patterned Bronze Bracers (95), from the same report, were already right. Thanks to kopuliak.

## [0.11.0] - 2026-10-15

- **First Aid and Cooking routes go past 150.** No trainer teaches Expert First Aid or Expert Cooking: you buy a book and read it at 125. The route now plans that step, "Buy and read Expert First Aid - Under Wraps at 125", with the book's price and the nearest vendor that sells it, and carries on to 225 instead of stopping at Journeyman. Artisan comes from a quest the game's data doesn't name, so routes still stop at 225 for now.

- **Herb and ore nodes show the skill they need.** Hovering a node names the Herbalism or Mining skill it asks for and colours it at your skill, orange, yellow, green or grey like a recipe, so you can see which nodes still give skill-ups. It works on English clients, and there's a setting to turn it off. Skinnable corpses show `?` for now, until someone checks that Forever kept Classic's skinning rule.

- **Check the trainer requirements SkillUp guesses with /su trainers.** Where Forever moved a recipe's colours, SkillUp moves the skill its trainer asks for by the same amount, which is right for most recipes but not all. The new command lists those guesses per profession, which ones a trainer you visited agreed with or showed differently, and which ones your trainer should teach at your current skill, so one visit settles them. Paste what it prints into an issue and the wrong ones get fixed in the data.

- **`/su report` gives you something to paste into a bug report.** It opens a small window with the text already selected: your addon and game versions, your character, your professions and where each route gets to, the audit if a profession is open, the trainer checks, your other addons and any errors SkillUp caught this session. Press Ctrl+C and paste it. It fits in one message.

- **No error from a vendor the game hides.** When the game keeps a vendor's name or ID hidden, SkillUp no longer tries to record where that vendor stands.

### For addon authors

- **A rank learned from a book is a step in `SkillUpForever.API.Professions()`.** It is a `buy` step with the book's `itemID`, its price as `cost` and the nearest vendor for `Navigate`, or, once the book is in the bags, a `train` step with the book's `itemID` and no `spellID`. The API version stays 1.

## [0.10.0] - 2026-10-15

- **Data checked against Forever 1.60.1.70374.** The bundled data is unchanged apart from its build pin.

- **Your quests stay below the Forever tracker with EllesmereUI and other UI suites.** When the game, Edit Mode or a UI addon put the quest tracker back in its saved spot, the Forever sections waited for the next quest event to restack, so your quests sat over them until then. The column now follows the quest tracker as soon as it moves, still without touching the game's own tracker code.

- **Value gathered materials at what they'd sell for.** A new Prices setting, off by default, prices a material your professions gather at its Auctionator price after the 5% cut, or its vendor sell price if that is more, instead of free. That is what crafting with it costs you, so the route picks a vendor-reagent recipe over one that burns valuable ore, and recipe rows and tooltips show the same cost. A material with neither price stays free. Thanks to berserkerlxl for the idea.

- **Not this recipe.** Right-click a step or a suggested recipe on the route page and choose *Not this recipe* to leave it out of every route on this character, as training, a sub-craft or a scroll to find. The route plans around it, or says nothing else gets there. A *Skipped* row under the route, the tracker's header menu and `/su unskip` bring a recipe back with *Show again*; `/su skipped` lists them.

- **A detached tracker with nothing to show leaves the screen.** Its "Forever tracker" title hides with the empty column and comes back, where you left it, as soon as a section has something to show.

- **A trainer that shows no skill requirement is not saved as needing none.** Such a recipe keeps the bundled requirement, and one saved as 0 by an earlier version is dropped, so the route no longer plans to learn it before you can.

- **No more secret-number errors on item tooltips.** When the game hands over an item count, sell price or tooltip item it won't let addons read, SkillUp uses the last count it saw (or the bundled price) instead of failing with "attempt to perform arithmetic on a secret number value". Before, one such read could keep failing until `/reload`.

- **The merchant's buy button asks first.** *Buy tracked reagents* now lists what it will buy and the total cost, and buys nothing until you click *Buy*. A change in your bags or route while it is open closes the question. Turn off *Show the buy button at merchants* under Route and trainer to remove the button.

- **Recipes start where Forever lets you make them.** Forever lowered many recipes' skill ranges but its data kept the old Classic starting skill on some, so Runed Copper Belt and Breastplate showed red while the game showed orange, and Heavy Sharpening Stone showed `?`. A recipe now starts at what its pattern asks, or moves down with its range, and a bundled trainer requirement moves down the same way: Heavy Sharpening Stone is trained at 100, not 125, and about 40 trainer recipes that went grey before the trainer would teach them are back in the route. A trainer's own number, once you visit, still wins (#107).

- **Retired patterns are left out.** The game still lists a few patterns nobody can get, such as *Pattern: Double-stitched Leather Gloves OLD* and *Formula: Imbue Cloak - Protection*. SkillUp no longer offers them as a recipe's scroll or takes their skill as where a recipe starts, so Guardian Cloak starts at 160, what its real pattern asks, and Enchant Cloak - Minor Protection, Enchant Boots - Minor Stamina and Goblin Rocket Boots are learned from their trainers.

## [0.9.3] - 2026-10-13

- **Data checked against Forever 1.60.1.70338.** The bundled data is unchanged apart from its build pin.

- **Tracker stays put when Edit Mode places it by its centre or bottom.** Attaching to the quest tracker no longer pushes it down the screen when it has been moved away from the default top-anchored spot.

- **How the Forever addons work together.** The README and store page list each of the other Forever addons and what it adds when installed alongside this one.

## [0.9.2] - 2026-10-09

- **Latest Auctionator prices.** Reagents and crafted items use Auctionator's latest recorded price. Scan with Auctionator to update prices; SkillUp no longer stores or averages daily prices.

## [0.9.1] - 2026-10-09

- **Recipe thresholds** use one pinned Forever client build, with no older Classic overrides. Contradictory difficulty ranges show unknown and are excluded from plans. Trainer recommendations respect learning requirements separately.

- **Latest Auctionator price option.** A new Prices setting prices reagents and crafted items at Auctionator's latest price instead of the median of the last seven days. The median stays the default.

- **Keep Blizzard's tracker methods intact.** The shared Forever tracker responds to objective and player events without wrapping native layout methods.

## [0.9.0] - 2026-10-08

- **Shorter addon descriptions.** The README and store pages explain the features directly and keep the author and licence credits.

- **Quest text stays on screen when the Forever tracker is smaller.** The native quest column and its header keep their full width at the edge of the screen.

- **Hide tracked professions without losing your route.** Turn off *Show tracked professions* to remove SkillUp from the objective tracker. Your tracked professions and target levels are kept.

- **Shared tracker scaling.** SkillUp follows the tracker scale selected in Shortest Path Forever.

## [0.8.4] - 2026-10-07

- **Quest objectives stay below the Forever tracker after reload.** The shared tracker no longer resizes Blizzard's quest container, which could move it over the addon sections.

## [0.8.3] - 2026-10-07

- **Data checked against Forever 1.60.1.70245.** The bundled game data is unchanged.

## [0.8.2] - 2026-10-06

- **Current profession data.** Recipe, trainer and threshold data are refreshed for Forever build 1.60.1.70235.

## [0.8.1] - 2026-10-05

- **The tooltip's skill bar keeps the game's own shape.** The bar under a recipe's tooltip was drawn narrower than the profession window's bar it copies, which squashed its end caps. It is drawn at the game's proportions, a little slimmer than before.

## [0.8.0] - 2026-10-05

- **The route reads the game's own recipe numbers and crafts what it can make cheaper.** A recipe's grey threshold now comes from the client where it reports one, with the bundled yellow and green kept under it, so the chance a row shows matches what the profession window implies. A craft that grants several skill points is counted and priced for every point, so the route asks for fewer crafts where the client says so. When a reagent is made by a recipe you know and crafting it beats buying, it becomes its own step before the craft that needs it (for example *Craft 3 Cured Light Hide*) and the shopping list names the raw materials it is made from, followed three levels deep and never through a cycle. Recipes also report the tool and station they need from the client: a step names where it is made, and a tool you are not carrying disables *Craft next* with the reason and joins the shopping list once. Reading a profession's recipe list now happens once per burst of window events instead of once per event.
- **The tracker returns after Edit Mode is locked.** Hiding and locking Edit Mode without leaving it no longer keeps the Forever sections hidden.
- **The tracker reads in game order.** The game's All Objectives header leads the shared column, the Forever sections follow it, and your quests stay below them. In combat the game keeps its quest list in its own slot, so the header and quests stay together and the Forever sections sit directly below them, keeping the tracker to one column.
- **The route asks for enough crafts to cover bad luck.** A yellow or green recipe does not give a skill-up every craft, and the route counted the average, so a run could end a point short with no reagents left. Each step now asks for the crafts that reach its target in nine runs out of ten, worked out from the chance at each skill point on the way, and a recipe with a low chance carries that risk in its price so the route leans on it less. An orange recipe is unchanged. The page, the craft button, the reagent list and the tracker redraw as you craft and as your skill rises, so a lucky run shrinks what is left and an unlucky one grows it. A step that cannot be crafted names the reagent and how many more are needed, and hovering *Craft* says what a click makes, how many the bags allow now, and that a worse run may need more.
- **The bottom row of the route page no longer overlaps.** *Craft* and *Nearest vendor* sat under the route and could meet when the craft label was long. They now share one bottom row with *Track* and stay clear of each other whatever the label says.
- **Auctionator's shopping list keeps itself up to date.** The *To Auctionator* button and the tracker menu's *Send missing to Auctionator* are gone. With Auctionator installed and the route set to buy rather than gather, the addon keeps its *SkillUp: <profession>* list in step with what the route still needs, leaves it alone while nothing changed, empties it once the bags cover the need, and names the list in the reagent list. When a price is missing or old and Auctionator's own scan-when-the-auction-house-opens option is off, the page says where to turn it on (Auctionator, Basic Options).
- **No false "can't identify the profession" message.** Learning a recipe with no profession window open printed "can't identify the profession (0); please report it." That line now appears only for a real profession the addon does not know.
- **The data matches client build 1.60.1.70205.** In this build Winter Boots and the ten camp furnishings (Incense Candle, Greenhouse, Fish Bowl, Fishing Rack, Camp Chair, Field Guide, First Aid Kit, Toxin Study, Lodestone and Rock Garden) no longer give skill-ups, so they show `?` in place of a chance and routes leave them out. Eight wands, from Lesser Magic Wand to Greater Eternal Wand, now sell to a vendor for 1 copper, so crafting one nets a higher cost.
- **A vendor reagent's tooltip gains its vendor line when the read finishes.** The first hover of a reagent sold by a vendor showed no *Nearest vendor* line while the addon was still reading who sells it, and kept the tooltip without it until the next hover. The row now draws its tooltip again once that read has finished.
- **Tracking starts when you open the profession you are levelling.** Opening a profession's window, or a trainer that teaches it, now tracks it on its own when its route still has steps, so the tracker, the next training step and the waypoint to where to train are there without pressing *Track*. A profession you stop tracking by hand stays stopped until you start it again.
- **One click to the vendor for the reagents your route still buys.** The route page now has a *Nearest vendor* button that sets a waypoint to the closest vendor selling any of the route's missing vendor reagents, instead of a trip through each reagent's line.
- **A crafted gear view, off until you want it.** A *Gear* tab on the Professions window, turned on in settings, draws your character sheet a second time: one item slot down each side and the weapon slots along the bottom, each showing the newest crafted item this character could equip for it, in the game's own empty-slot art, quality border and known mark. The pane in the middle names the pick, its level and type, the profession and the skill its recipe is learned at, its state, its reagents with how many you have, and one button that opens a recipe you know or sets a waypoint to where one you can learn is taught; *Also for this slot* lists the slot's other picks. By default it holds only what the character can make now; a *Show gear I cannot make yet* switch in the header adds the rest and is saved per character. An item the class cannot wear, a weapon whose skill this character has not trained, an item whose own profession rank is above the character's, and an item a use consumes are all left out. Within a slot the newest required level comes first, then the higher skill, then the name. The skill shown is the pattern's own requirement, not the client's placeholder orange of 1, so a Forever-added hood reads `Leatherworking, 100` where it used to read `1`, and a recipe whose source the data does not know says its source is unknown instead of naming a skill. It names the newest thing craftable for a slot, not a best-in-slot list.
- **Choose gathering or buying from the route itself.** A *Buy reagents* switch on the route page decides whether a reagent another of your professions could gather is free to gather or bought and priced at a vendor or the auction house. It is saved per character and no longer hides in the settings. When the route has nothing your professions gather, the switch is disabled and its tooltip says so.
- **The route page is drawn the game's way.** The *Route* and *Reagents  (have / need)* lists are now rows like the window's own items: a full-size icon in its stock border, the name beside it and, underneath, what the row is about, such as `18 crafts to 66, +27s` or `gather, 23/200`. Headings, totals and the auction-price note use the game's own fonts at their normal size, and the lists scroll with its own scroll box. The *Buy reagents* switch sits in the header and *Nearest vendor* in the bottom row, so nothing is drawn under a heading.
- **Prices come from a median of recent scans, and an unpriced reagent is called out.** Auction prices were Auctionator's single last listing, so one cheap auction moved the whole route. The addon now keeps each item's lowest buyout for the last seven days and prices from the middle of those days, saying on the page how many days that is, and a vendor price still wins when it is cheaper. A reagent nobody has priced is unknown, not free: its recipes are left out of the route, the route is marked incomplete and the reagent is named in the reagent list. A vendor whose window you open now carries the client build you saw it on and stops being named once two builds have gone by without seeing it, though nothing is deleted.
- **The route lists keep their own rows.** The *Route* and *Reagents  (have / need)* lists now draw into the game's scroll box list, which keeps a pool of row frames and lays out only the ones on screen. The rows look and behave as before; the addon no longer hides frames by hand as a list redraws, so scrolling stays smooth while a route refreshes.

## [0.7.1] - 2026-10-04

- **An AtlasLoot that is switched off is no longer called missing.** With AtlasLoot installed but not running, because it is unticked or held back as out of date, the route said to install it. It now says to enable it in the AddOns list, or to update it.
- **A suggested recipe's source can be read.** Where the route stops, each recipe scroll's row ran its source into its name and cut it short, so *vendor*, *quest* and *drop* all read as a few letters. The source now sits whole beside the columns and a long name is the part that is shortened.
- **A vendor inside the other faction's capital is not yours.** The holiday vendors stand in every capital and count as friendly to both sides, so an Alliance character could be sent to one in Thunder Bluff. A vendor or trainer inside a capital city now counts as that city's side only: it is shown in red in a scroll's tooltip and never gets the waypoint.
- **A long list of sellers fits on the screen.** A scroll sold by many vendors listed every one and its tooltip ran past the bottom of the screen. It now lists four, starting with the one a click takes you to and then the nearest you can buy from, and counts the rest.
- **A route row's tooltip is whole on the first hover.** The first time you hovered a recipe or reagent on the route page after logging in, its tooltip showed the item and none of the route's own lines, such as *Requires*, *Sold by* and the click hints; they only appeared on a second hover. The game was redrawing the item once its details arrived, and the row now draws its lines again when that happens. Pressing Shift over a row dropped them the same way, and no longer does.
- **A scroll's tooltip names it once.** Under the crafted item's own tooltip the route repeated the item's name. The name is now added only when the recipe is called something else, as with *Train* steps.

## [0.7.0] - 2026-10-03

- **A vendor you have bought from is the one a step names.** Standing at a vendor Questie does not know, the buy step still sent you to one it did. Opening a merchant's window now notes which of your reagents and recipe scrolls that vendor sells and where you stood, so from then on the step, its tooltip and its waypoint use that vendor whenever it is the nearest, with or without Questie.
- **A far vendor is no longer called the nearest.** With every known vendor or trainer on another continent, or with you inside a dungeon, the route picked whichever came first in its data and showed it as the nearest. Now a step names one only when it can tell which is nearest: by distance on your continent, by Shortest Path Forever's travel time when you hover or click, or because there is only one. Otherwise it reads *Vendor* or the trainer's profession, with no waypoint.
- **A detached tracker keeps clear of your quests.** With Attach to quest tracker off, the Forever column could open on top of the quest list. Until you drag it, it now sits beside the quest tracker, level with its top; once dragged, it stays where you put it.
- **Recipe sources, vendors and trainers come from Questie and AtlasLoot.** Where a recipe's scroll is sold, which quest rewards it, who sells a reagent and where a trainer stands are now read from the Questie and AtlasLoot you have installed, so they follow those addons as they are corrected for Forever. Both are optional: without AtlasLoot the route cannot tell which scroll teaches which recipe, and without Questie it names no vendor, quest or trainer and sets no waypoint to one. One line where the route stops, and in a step's tooltip, says which to install. Everything else works as before.
- **A scroll's price is the one you have seen.** The route showed a recipe scroll's classic vendor price and ranked vendors with limited stock after the others. Neither is known for Forever, so a scroll now shows what it cost at the auction house or at a merchant's window you have opened, `?` until then, and every vendor of your faction counts the same.
- **A rank's fee is the one your trainer quotes.** The route's *Train Journeyman*, *Expert* and *Artisan* steps always showed the classic base fee, even after a trainer had shown you a different one. Once you have opened a trainer who still offers the rank, the route and its total use the fee that trainer charges you.

## [0.6.11] - 2026-10-03

- **Trainer fees and level-ups reach the route at once.** After a trainer's fees were recorded, or after you gained a level, the route page and the tracked reagents kept showing the old plan until something else refreshed them. They now update straight away.
- **/su no longer raises an error after an incomplete update.** When the addon asked for a game restart because files were missing, typing /su or clicking its minimap menu entry raised a Lua error. It now does nothing until the restart.
- **Buy tracked reagents can't order twice.** Clicking the merchant button again before the reagents reached your bags bought them all a second time. The button now greys out until the purchase arrives, and comes back after a moment if the merchant refuses it, for instance when your bags are full.
- **Boss drop chances for recipes are worked out the way bosses roll their loot.** The glove and cloak enchanting formulas from Ahn'Qiraj showed 14% from the Ruins bosses; they are about 1% a boss, best from the Temple. Plans and patterns from Azuregos, Kazzak and Onyxia showed 1.3% and are nearer 3%, since those bosses roll that loot more than once.

## [0.6.10] - 2026-10-02

- **A newly learned recipe joins the route at once.** Learning a recipe, or opening a profession, now re-plans the route and the tracked reagents straight away; before, they could keep the old plan until the recipe list next updated.
- **The guides stay put in a fight.** In combat the game stretches its quest tracker and nudges it back on screen, which shoved the Forever sections sideways across the screen until the fight ended. They now stay stacked above the quest list.
- **The what's-new setting fits the settings panel.** Its name was cut off with an ellipsis; it now reads *What's new after an update*.

## [0.6.9] - 2026-10-01

- **Keep guides clear of quests in combat.** Companion sections stay clear when the quest list grows during a fight. Detaching restores the quest tracker’s original Edit Mode position.

## [0.6.8] - 2026-09-30

- **Move the shared tracker.** Turn off Attach to quest tracker in Settings to drag all Forever sections together. The position survives `/reload`.

- **Keep the source easy to audit.** Core logic, integrations and UI now live in matching folders; the shipped load order and player-facing behaviour are unchanged.

## [0.6.7] - 2026-09-30

- **Development disclosure.** This release was developed with AI assistance. Changes were reviewed and checked with automated tests, linting and type checks; live verification remains ongoing.

- **Settings are grouped into subpages.** *Recipe rows*, *Prices*, *Route and trainer*, *Tooltips and sorting* and *Addon* each open from a short index, so no single page runs long. Saved choices, defaults and tooltips are kept.

- **Choose settings without opening a menu.** Craft prices, reagent tooltips and recipe sorting use labelled sliders, avoiding the native dropdown path implicated in a Forever client crash. Your saved choices and recipe-list sorting stay in sync.

- **Keep tracker sections apart in combat.** Companion sections move above the protected quest tracker while fighting, then return to one column afterward, regardless of which addon loads first.

## [0.6.6] - 2026-09-29

- **Keep one tracker column.** Addon sections stack above the quest tracker regardless of which companion addon loads first, while keeping their frame pools separate from Blizzard's tracker.

## [0.6.5] - 2026-09-28

- **Separate addon tracking from Blizzard’s layout.** Addon sections now use their own frame pools and sit beside the quest tracker, avoiding the shared tracker registration implicated in Edit Mode aura errors.
- **Check the client integration in CI.** Regression checks run against pinned Forever tracker source and reject native tracker registration.

## [0.6.4] - 2026-09-27

- **Recipe sorting and shopping tracking use native callbacks and load events.** They no longer hook Blizzard object methods; lifecycle regressions and release checks guard these integrations.

## [0.6.3] - 2026-09-27

- **Profession tab updates stay separate from Blizzard's methods.** The route tab follows skill changes and window events without hooking the profession frame's tab refresh functions. This fixes the fishing skill-up error confirmed on the Forever beta.

## [0.6.2] - 2026-09-27

- **A craft whose sell price isn't known yet shows no cost** instead of the full reagent cost, and the route leaves it out until the price loads. It used to count the craft as selling for nothing, then change its mind.
- **A vendor that doesn't say how many come in a stack no longer overwrites a price.** The addon keeps the last unit price it saw rather than guessing the stack is one.
- **A saved setting the menu no longer offers goes back to its default.** A bad *Count what crafts sell for* or *Sort recipes* value used to stick, quietly acting like vendor price or no sort.
- **A recipe suggestion with no known scroll price shows `?`** instead of an empty cost.
- **The trainer's pick no longer runs into the *Requires:* line.** The recipe to train next now gets the green arrow your bags put on an upgrade instead of the words *Best next*, and a row's chance and cost end in `...` rather than write over the requirement.
- **The cost setting's tooltip says where prices come from**: common vendor reagents priced from the start, reagents you gather free, auction prices from Auctionator.

## [0.6.1] - 2026-09-27

- **The route no longer charges for a rank it never gets to.** When your known recipes ran out before the target, the total still had the next rank's fee in it, though the route stopped short of needing it.
- **Rank training comes where you can do it.** A craft that ran through your cap from below the skill the trainer asks for (First Aid from 40 to 90, say) put *Train Journeyman at 50* before it. The craft is now split at 50, with the training in between.
- **Recipe suggestions show up when your only unpriced recipe is grey.** A grey recipe with no price made the route tab ask for Auctionator instead of listing the scrolls that would carry you on.
- **Unpriced reagents on the route tab get their names** instead of staying as *item 1234* until something else loaded them.
- **The tracker's next training step matches the route tab.** It sorted ranks and recipes by skill on its own, so it could send you to a different trainer than the route does.
- **The tracker says why a route is stuck**, like the route tab does, instead of *Reagents in hand* when nothing you know can be priced or skill up.
- **Tracking or untracking a profession reorders it in Adventure Guide Forever straight away**, not after your next bag change.

## [0.6.0] - 2026-09-25

- **Ready for translation.** Every line SkillUp writes, from recipe tooltips to the route tab and tracker, can now be translated: send a file for your language as a pull request, or paste it into an issue, on [GitHub](https://github.com/cjber/skillup-forever/tree/main/Locales). Rank names, *Default*, *Off* and *Total* already use the game's own words, so they follow your client's language now. English is unchanged.
- **A line in chat after an update says what's new**, once, the first time the new version loads. A fresh install stays quiet, and *Tell me what's new after an update* in settings turns it off.
- **Waypoint tooltips mention Shortest Path Forever when it isn't running.** Trainer, vendor and recipe-source tooltips add a grey line saying to install it, or enable it if it's turned off, for walked routes and boat times. *Suggest companion addons* in settings hides the line.

## [0.5.0] - 2026-09-25

- **Other addons can show your profession progress.** `SkillUpForever.API` hands out each profession's next three steps, next recipes and reagents from the same plan as the levelling route tab, so Adventure Guide Forever can draw them in its Professions tab.
- **Auction prices now come from [Auctionator](https://www.curseforge.com/wow/addons/auctionator).** SkillUp no longer scans the auction house itself: opening it no longer sends searches, and `/su scan` and the *Scan the auction house* setting are gone. With Auctionator installed its prices are used as before; without it, reagents you can only buy at the auction house show no cost, and the tooltips say *Auction prices need Auctionator*. Vendor prices, reputation discounts and the crafted-item sale option are unchanged. Old scanned prices are cleared from your saved settings.

## [0.4.1] - 2026-09-25

Updated for Forever build 1.60.1.70009.

- **Four Leatherworking recipes cost less**, among them Cloudy Gustwoven Trousers: Forever no longer lists Spider Silk Slippers among their reagents, so the cost per skill-up leaves them out.
- **Linen Reagent Bag sells to a vendor for 2s**, down from 50s, as in the game.
- **Potion of Demon Slaying, Potion of Beast Slaying and Potion of Elemental Purging** carry their new names, and the six Spiritcaller pieces follow the game's reshuffle of their recipes.

## [0.4.0] - 2026-09-25

Getting there quicker: waypoints and nearest picks through Shortest Path Forever, clickable tracker
lines, and a round of fixes to prices and the route.

- **Waypoints go through [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever)** when it is installed: clicking a trainer, vendor or reagent like Coarse Thread starts its travel route there. When it can't (in combat, or with its journeys off), TomTom's arrow or the map's own waypoint is set as before.
- **The nearest trainer or vendor is the quickest to reach** with Shortest Path Forever installed: tooltips and clicks rank the closest few by its travel time, flights and boats included, instead of a straight line.
- **Click a tracker line for a waypoint**: the next training step goes to the nearest trainer, and a missing vendor reagent like `12/20 Coarse Thread` to the nearest vendor. Hover the line to see who and where.
- **Your own auction house searches no longer wipe scanned prices.** One that found nothing used to clear them; only SkillUp's own searches now mark an item as unlisted.
- **Free recipes show as free.** One made only from reagents you gather used to show a cost of 1c per skill-up.
- **No more error on `/reload` right after an update.** It used to fire before the "restart the game" message could show.
- **The Craft button stops at your skill cap.** It used to offer crafts past it; now it stops where skill-ups do, until you train the next rank.
- **A scan you walk away from still counts.** Prices from an auction house scan left mid-way used to stay hidden until something else changed.
- **A recipe with no reagent data shows `?`.** It used to count as free.
- **A newer scan beats an old Auctionator price.** When the scan found nobody selling the item, the older Auctionator price used to win.
- **Searching the game's settings no longer blames SkillUp** for a blocked button (Social's Discord Sign In).
- **Hovering some items no longer errors.** An item whose tooltip hid its id tripped a check before the guard for it ran; recipe tooltips had the same fault.
- **Trainer steps in the route** read the same as elsewhere, with one space before "(level N)".
- **The sort setting's tooltip** now says that sorting puts every recipe in one list, and Default restores categories.
- **Thresholds, recipes, trainers and prices are updated** for Forever build 1.60.1.69977.

## [0.3.0] - 2026-09-21

Where to go next, not just what each recipe costs: a route to your target, what to buy for it, and what to
train.

- **A levelling route page on the Professions window**, for any of your professions. Type a target skill
  and it lists the cheapest crafts, training recipes where the fee pays for itself, like `12× Heavy Linen Bandage to 90`, each with its cost, and the total. Every
  skill point takes whichever recipe has the lowest cost per skill-up at that point. Recipes with an
  unpriced reagent are left out and counted rather than treated as free, and a route that runs out of
  recipes stops and says where. Hover any step or reagent for details (click a step to open its recipe),
  and the page shows how old its auction prices are.
  The target can pass your current cap: the route adds each rank to train on the way, with its fee,
  the skill the trainer wants and the level it needs.
  When the recipes you know run out, the route lists the scrolls that would carry it on, from vendors,
  quests and drops, easiest to get first, with every source's zone and coordinates; click one for a
  waypoint to the nearest vendor or the likeliest drop (TomTom's arrow when installed).
  Training steps and vendor reagents show the nearest trainer or vendor of your faction, and a click
  (or the tracker's menu) sets a waypoint there.
- **Craft the next step in one click**: a button under the route (and the tracker's menu) crafts the
  route's first step as many times as it needs and your bags allow, while that profession is open.
- **Gather it yourself.** Reagents another of your professions gathers (Light Leather with Skinning, ore
  with Mining, herbs with Herbalism) count as free, so the route uses them and the shopping list says to
  gather them; turn it off in the settings to price them at market. With Syndicator installed, reagent
  tooltips show what your other characters hold.
- **A shopping list from the route.** The page lists every reagent the route needs against what's in your
  bags and bank. Track it to see the next thing to train and the reagents still missing in the objective tracker, above your quests; at a vendor, one button on the
  merchant window buys the missing reagents that vendor sells. With Auctionator installed, the auction house
  reagents still missing become an Auctionator shopping list.
- **The profession trainer shows the same numbers** as recipe rows, and marks the recipe that most cheapens
  or extends your route, training fee included, as `Best next` (closes #2).
- **Reagent tooltips say what your routes need.** Hovering an item shows how much of it each tracked route
  needs, like `Route: 28/567 · Leatherworking to 150`; hold Shift for every recipe of yours that uses it
  and still skills up, with its colour now, like `yellow until 115`. A setting shows that full list
  always, or turns the section off.
- **Recipes you haven't opened can be priced.** Ones you haven't opened in the Professions window now have reagents
  and crafted items from the game's data, so the trainer and tooltips can price them.

## [0.2.0] - 2026-09-21

What a skill-up costs, so the cheapest way to level is on the screen next to the chance of getting one.

- **Every recipe row shows its cost per skill-up.** That is the reagents, less what the crafted item sells
  for, divided by the chance of a skill-up, so a yellow recipe at 50% costs twice its reagents per point.
  It is shown in coin icons after the chance. A skill-up that makes money shows a green +.
- **The tooltip shows where the number comes from.** Each reagent is listed with its price and its source
  (a vendor, the auction house and how long ago, or Auctionator), then what the craft sells for, the net
  cost of one craft and the cost or profit per skill-up. A recipe with any unpriced reagent shows no cost
  rather than one that looks cheap because part of it is missing, and says how to price it.
- **Prices are gathered as you play.** About 50 common vendor supplies (thread, vials, flux, dyes, spices)
  are priced from the start from the game's own data. A vendor you visit updates its prices, reputation
  discount included. Opening the auction house searches it for the reagents and crafts of every profession
  you have opened, at most once an hour (`/su scan` forces it), and your own searches update prices too.
  Auctionator's prices fill anything not scanned.
- **What a craft sells for counts.** By default its vendor price comes off the cost; a setting can use its
  auction price instead when that is higher, after the 5% cut, or leave it out.
- **Sorting is in the Filter menu, and now does something.** A *Sort by* section at the bottom of the recipe
  list's own Filter menu offers required skill, skill-up chance and the new *Cheapest skill-up*. Forever's
  categories hold one or two recipes each, so the old sort inside each category never visibly changed the
  list; a sort now lists every recipe in one ordered list, learned first, then unlearned. *Default* brings
  the categories back.
- **Rows lead with the chance.** The required skill is now a setting and off by default. A recipe you can't
  make yet still shows it in red, since it is the one number that matters there.

## [0.1.0] - 2026-09-21

First release.

- **Every recipe row shows the skill it needs and your skill-up chance**, coloured by difficulty.
- **The recipe tooltip shows the orange / yellow / green / grey thresholds** on a bar with your skill marked. The bar
  is the Professions window's own header bar and the marker is Forever's rested pip, so it looks like part of the
  window. Settings turn the row text or the tooltip off.
- **Recipes can be sorted within each category** by required skill or by skill-up chance.
- **`/su audit` checks the bundled data** against the colours the game shows.
- **Thresholds for 2,356 recipes** from Forever build 1.60.1.69913.
