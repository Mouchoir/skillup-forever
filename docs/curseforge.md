SkillUp Forever shows skill-up chances, recipe costs and colour thresholds in the Professions window. Its side panel has levelling routes, shopping lists and crafted gear.

![Leatherworking levelling from 48 to 60](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/demo.gif)

From 48 to 60 the rows re-sort by cost per skill-up, and the bracers turn green at 55.

![The Leatherworking window with skill-up chance and cost per skill-up on each row](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/window.png)

Chance and cost, right in the window's own rows.

![Recipe tooltip with thresholds, reagent prices and cost per skill-up](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/tooltip.png)

Colour thresholds and reagent prices for the recipe you hover.

![The SkillUp route tab with training and crafting steps and the reagents they need](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/route.png)

The route tab from 48 to 73: what to train, what to craft and where reagents come from.

![The Crafted gear tab with item slots down both sides and along the bottom, each showing the newest crafted item, and one slot's recipe, reagents and status in the middle](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/gear.png)

The gear tab, turned on in settings: each slot shows the newest thing this character could craft for it.

![The objective tracker with the route's next training step and missing reagents](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/tracker.png)

Track it and the route sits beside your quests.

![A Leatherworking trainer's recipes with skill-up chance, cost and a green arrow on the one to train next](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/trainer.png)

At the trainer, a green arrow marks the one to train next.

![Light Leather's tooltip with how much the tracked route needs](https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/reagent.png)

Hover a reagent to see how much your routes need.

## Features

- **Recipe rows and tooltips** show skill-up chance, cost and colour thresholds. The start of the difficulty range is optional.
- **Sorting** orders recipes by difficulty range start, chance or cheapest skill-ups. *Default* restores the game's categories and filters.
- **Levelling routes** list crafts, trainer visits, skill books and rank quests to your target skill, including fees, tools and stations. Steps allow for unlucky skill-ups. Cheaper crafted reagents become their own steps; routes that stop short name recipes that could extend them. Right-click a recipe and choose *Not this recipe* to plan without it.
- **Shopping lists** count reagents against bags and bank. Choose whether gathered materials are free or bought, track them beside quests, buy vendor stock and keep an Auctionator list up to date.
- **Trainer annotations** mark the best recipe to train next. Reagent tooltips show what tracked routes need.
- **Gathering nodes** show the Herbalism or Mining skill they need, coloured at yours, on English clients.
- **Crafted gear** shows the newest craft for each slot, with its recipe, reagents and learning location. Enable its tab in settings.

## Prices

Each reagent uses the cheapest known vendor or Auctionator price. Visiting a vendor records its prices and reputation discounts. Materials your professions gather can count as free until you choose *Buy reagents*, or, with *Value gathered materials at what they'd sell for* on, cost what selling them would bring.

Auction prices use Auctionator's latest recorded price for reagents and crafted items. SkillUp never scans the auction house itself. Scan with Auctionator to update prices. Missing prices stay unknown and leave affected recipes out of the route.

A craft's vendor sell value comes off its cost by default. You can choose its auction value when higher, after the 5% cut. Profit shows a green `+`.

## Usage

Turn off **Show tracked professions** in settings to hide the profession tracker. Your tracked professions and skill targets are kept.

Open a profession and the numbers are already there.

- `/su` opens the settings (also in Settings > AddOns, or from the addon compartment on the minimap).
- `/su skipped` lists the recipes you said *Not this recipe* to, and `/su unskip <ID>` (or `all`) brings them back.
- `/su audit`, with a profession open, compares the bundled thresholds with the colours the game shows and prints any mismatch.
- `/su report` shows a report to copy into a bug report: versions, your professions and routes, the audit, the trainer checks and any errors SkillUp caught.
- `/su trainers` lists the trainer skill requirements SkillUp guessed, which ones a trainer has confirmed or shown differently, and which your trainer should teach at your skill now.

Thresholds come from the Forever client's recipe data; missing data shows `?`. Settings cover rows and tooltips, prices, the route and crafted gear tabs, trainer annotations, sorting, reagent tooltips and companion hints.

## With my other Forever addons

All optional:

- [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) plans the trip when you click a trainer or vendor in the route. SkillUp then picks the nearest one by travel time.
- [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) shows each profession's next steps in its Professions tab.
- [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) puts unfinished Legacy challenges on the world map and in the tracker.
- [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) adds options for repairs, junk selling, bags and maps to the game's settings.

A tracked route shares one tracker column with the Shortest Path, Adventure Guide and Legacy sections, above your quests.

SkillUp is in English for now; translations are welcome as a pull request or issue.

Source: [github.com/cjber/skillup-forever](https://github.com/cjber/skillup-forever), GPL-3.0-or-later.

Built with AI assistance.
