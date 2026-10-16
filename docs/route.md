# Levelling route and shopping list

The detail behind the README's *Levelling route* and *Shopping list* features.

## Levelling route

A map tab under the Professions window's side tabs opens a SkillUp page. Pick any of your professions that craft (it starts on the open one) and type a target skill. The page lists the cheapest crafts to get there, each drawn as the game draws an item: a full icon, the recipe's name and, under it, how many crafts, the skill it reaches and the cost, then the total.

### How it picks

- Each skill point takes the recipe with the lowest cost per skill-up at that point.
- A step asks for enough crafts to reach its target in nine runs out of ten, worked out from the chance at each skill point on the way, not from the average. An orange recipe is unchanged; a yellow or green one carries its risk in its price, so the route leans on it less.
- Recipes a trainer teaches are included when they pay for themselves, shown as a *Train* step with its fee. The fee is counted once, and never before the trainer would teach them.
- Recipes with an unpriced reagent are left out and counted.
- Recipes you said *Not this recipe* to are left out (see below).

### Not this recipe

Right-click a step, a *Train* step, a sub-craft or a suggested scroll and choose *Not this recipe*, the way Adventure Guide Forever's *Not this quest* leaves a quest out. The route is planned again without it: it is never crafted, trained, made as a sub-craft or suggested, and the next cheapest recipe takes its place. When nothing else reaches the target, the route stops short as it would anyway.

A *Skipped (N)* row under the route counts what you left out of this profession; click or right-click it and choose *Show again* to bring one back. The tracker's header menu has the same list. `/su skipped` prints every skipped recipe with its ID, and `/su unskip <ID>` or `/su unskip all` brings them back. Skips are saved for each character.

### The steps

Each step is one row: the recipe's full-size icon in its stock border, the name beside it and, under it, the crafts, the skill it reaches and the cost. A *Train* step shows its fee and the skill the trainer wants instead. Hover one for the crafted item, its colour bands, the reagents for that step and its cost, or click it to open the recipe.

*Craft* under the route crafts its first step as many times as it needs and your bags allow, while that profession is open. Its label says what it will make and how many the bags allow now; hover it for how many the route asks for and why a worse run may need more. When the step cannot be crafted, the button and the page name the reagent and how many more are needed.

### Training

The target can go past your current cap, up to the last rank a trainer, book or quest teaches. The route then adds a step for each rank: *Train Journeyman/Expert/Artisan* with the fee, the skill the trainer wants and, while you are below it, the level, a book to buy and read, or a quest to do.

No trainer teaches Expert First Aid or Expert Cooking: you buy a book and read it at 125. The route adds that step, *Buy and read Expert First Aid - Under Wraps at 125*, with the book's price and the nearest vendor that sells it, or only *Read* once you have the book. The price is the game's list price for the book until you see it at a merchant. Artisan First Aid and Artisan Cooking come from a quest at 225 and level 35: *Triage* for First Aid (each side has its own) and *Clamlette Surprise* for Cooking. The route adds *Complete Triage at 225*, and hovering or clicking it points to the quest giver. The quest's name and giver come from Questie; without it the step says *the Artisan quest*.

Fees come from the classic trainer data (CMaNGOS), which also says who trains what. A trainer you have visited quotes its own fees, for recipes and for the ranks it still offers, and those then win.

Where Forever moved a recipe's colours, the bundled skill its trainer asks for moves by the same amount. That is right for most recipes but is a guess. `/su trainers` lists the guesses for each profession, which ones a trainer you visited agreed with or showed differently, and which ones your trainer should teach at your skill now. A requirement a trainer shows replaces the guess.

### Prices

Reagents show where each price comes from. Auction prices use [Auctionator](https://www.curseforge.com/wow/addons/auctionator)'s latest recorded price, with the age of its observation. Scan with Auctionator to update prices. Without Auctionator, a reagent sold only at the auction house has no price.

A missing price is unknown, never free. A reagent nobody has priced leaves every recipe that needs it out of the route, the page marks the route incomplete and names those reagents in the reagent list, and buying pays the cheaper of the vendor and auction prices.

### When the route stops short

If nothing you know skills up far enough, the route stops there and says so. It then lists the recipes from vendors, quests and drops that would carry it on, easiest to get first:

1. a vendor of your faction
2. quests
3. named drops
4. world drops

These come from the [Questie](https://www.curseforge.com/wow/addons/questie) and [AtlasLoot](https://www.curseforge.com/wow/addons/atlaslootclassic) you have installed. AtlasLoot says which scroll teaches which recipe; Questie says who sells it, which quest rewards it and where they are. Without one, a line says which to install, and the list holds what the other can still tell.

Each shows the scroll's price (what it cost at the auction house or at a merchant's window you have opened, `?` until then) and how far it reaches. Hover one for its vendors (the nearest four, and a count of the rest), quests and drops, with zone and coordinates. Click it for a waypoint to the nearest vendor or the likeliest drop.

### Waypoints

*Train* steps and vendor reagents name the nearest trainer (one who teaches that far, of your faction) or vendor, with its zone and coordinates. A click sets a waypoint there. A *Nearest vendor* button in the route page does the same for every vendor reagent the route still needs at once. Names and places come from Questie: without it a step names nobody and its tooltip says so.

A vendor whose window you open is remembered, with where you stood and what it sold, so it is named from then on even without Questie. It is used for the client build you saw it on and the build after; once two builds have gone by without seeing it, it stops being named, though nothing is forgotten.

- With [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) installed, you get its travel route, and "nearest" means quickest to reach by its travel time.
- Otherwise [TomTom](https://www.curseforge.com/wow/addons/tomtom)'s arrow, else the map's own.

## Shopping list

Beside the route is every reagent it needs, one row each: a full icon, the name and, under it, where it comes from and how many you have (bags and bank), green once covered. Hover one for what your other characters hold ([Syndicator](https://www.curseforge.com/wow/addons/syndicator), same realm and faction).

### Gathered reagents

*Buy reagents* in the route page chooses where a reagent another of your professions could gather comes from: off, it costs nothing, so the route uses it and the list says *gather*; on, it is bought and priced at a vendor or the auction house like any other reagent. The choice is saved for this character. When the route has nothing your professions gather, the switch is disabled and its tooltip says so.

Gathering is free time, but the materials are not: you could sell them instead. Turn on *Value gathered materials at what they'd sell for* (Settings, Prices) and a gathered material, with *Buy reagents* off, costs what selling it would bring: its Auctionator price after the auction house's 5% cut, or its vendor sell price if that is more. The route then weighs that cost like any other, so it leaves valuable ore for a vendor-reagent recipe when that is cheaper, and the reagent's tooltip says which price it used. A material with neither price stays free.

### Track

*Track* puts the list in the objective tracker beside your quests, like `12/20 Linen Cloth`, kept up to date as you buy, craft and skill up.

Opening a profession's own window, or a trainer that teaches it, starts tracking that profession on its own when its route still has steps, so the tracker and its waypoints arrive without pressing *Track*. A profession you stop tracking by hand stays stopped until you track it again.

- Click the training line or a vendor reagent's line for a waypoint to the nearest trainer or vendor. Hover it to see who and where.
- Its header menu crafts the next step while that profession is open, and sets a waypoint to a trainer or to a vendor for a missing reagent.

### Buying

- **At a vendor:** *Buy tracked reagents* on the merchant window buys what that vendor sells, with the total cost on the button. It lists what it will buy and asks before spending anything; turn off *Show the buy button at merchants* to remove it.
- **At the auction house:** with [Auctionator](https://www.curseforge.com/wow/addons/auctionator) installed and the route set to buy rather than gather, the addon keeps an Auctionator shopping list (`SkillUp: <profession>`) of the auction house reagents still missing, updated as you buy, craft and skill up. The reagent list names that list. An unchanged need leaves it alone, and a need the bags now cover empties it. Auction purchases stay manual, as the game requires. When a price is missing or old and Auctionator's own *scan when the auction house opens* option is off, the page says so and points at it (Auctionator, Basic Options).
- **One recipe at the auction house:** with the auction house open, the Professions window shows *Reagents for [ ] crafts* and *Search* beside *Create All*. The count starts at what the route plans for that recipe, or 1, and you can change it. The search covers the auction house reagents that many crafts still need after your bags and bank, so you don't have to work it out. Reagents a vendor sells, or that you gather, are left out, as on the route's list. Hover the button for the list. With Auctionator, it writes the `SkillUp: crafting` shopping list with those quantities and searches it. Without Auctionator, each click puts the next reagent's name in the game's search box (on the Buy tab) and says how many you need; press the auction house's own *Search* to run it. It only searches. Turn it off with *Search reagents at the auction house* (Settings, Route and trainer).
