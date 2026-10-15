<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">SkillUp Forever</h1>

<p align="center">
Classic profession-levelling numbers inside WoW: Forever's Professions window.<br>
<a href="https://github.com/cjber/skillup-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/skillup-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/skillup-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/skillup-forever" alt="Latest release"></a>
</p>

SkillUp Forever shows skill-up chances, recipe costs and colour thresholds in the Professions window. Its side panel has levelling routes, shopping lists and crafted gear.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/demo.gif" width="640" alt="Leatherworking levelling from 48 to 60 in the Professions window"></p>

From 48 to 60 the rows re-sort by cost per skill-up, and Handstitched Leather Bracers turns green at 55.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/window.png" width="640" alt="The Leatherworking window with skill-up chance and cost per skill-up on each recipe row, and a tooltip showing reagent prices and cost per skill-up"></p>

Each row shows its chance and cost, with the tooltip breaking it down per reagent. This character skins, so Light Leather is free.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/tooltip.png" width="640" alt="A recipe tooltip with the orange, yellow, green and grey thresholds on a bar, your skill marked, and each reagent's price and cost per skill-up"></p>

The recipe tooltip draws the thresholds on the game's own bar with your skill marked, then each reagent's price and the cost per skill-up.

## Features

- **Recipe rows and tooltips** show skill-up chance, cost and colour thresholds. The start of the difficulty range is optional.
- **Sorting** orders recipes by difficulty range start, chance or cheapest skill-ups. *Default* restores the game's categories and filters.
- **Levelling routes** list crafts and trainer visits to your target skill, including fees, tools and stations. Steps allow for unlucky skill-ups. Cheaper crafted reagents become their own steps; a route that stops short names recipes that could extend it. Right-click a recipe and choose *Not this recipe* to plan without it. [Route details](docs/route.md#levelling-route).
- **Shopping lists** count reagents against your bags and bank. *Buy reagents* chooses whether materials your professions gather are free or bought. Track the list beside quests, buy vendor stock and keep an Auctionator list up to date. [Shopping details](docs/route.md#shopping-list).
- **Trainer annotations** show chance and cost, with a green arrow on the recipe that best extends or cheapens your route.
- **Reagent tooltips** show what tracked routes need. Hold Shift for every recipe that uses the item and still skills up.
- **Gathering nodes** show the Herbalism or Mining skill they need, coloured at yours, on English clients.
- **Crafted gear** shows the newest item you could craft for each slot, with its recipe, reagents and learning location. Enable its tab in settings. [Gear details](docs/gear.md).

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/route.png" width="640" alt="The SkillUp route tab: training and crafting steps from 48 to 73 with their costs, and the reagents they need"></p>

The route tab from 48 to 73: train the vest, craft 28, and where reagents come from.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/gear.png" width="640" alt="The Crafted gear tab: item slots down both sides and along the bottom, each showing the newest crafted item, with one slot's recipe, reagents and status in the middle"></p>

The gear tab, turned on in settings: each slot shows the newest thing this character could craft for it, with the pick's recipe, reagents and status in the middle.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/tracker.png" width="320" alt="The objective tracker with Leatherworking to 73, the next training step and two missing reagents"></p>

Tracked, the same route sits beside your quests: the next trainer visit and what's still missing.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/trainer.png" width="320" alt="An Apprentice Leatherworking trainer's recipes, each with its skill-up chance and cost, and a green arrow on the vest"></p>

At the trainer, every recipe shows its chance and cost; a green arrow marks the one to train next.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/skillup-forever/main/docs/screenshots/reagent.png" width="320" alt="Light Leather's tooltip with how much the tracked route needs"></p>

Hover a reagent to see how much your tracked routes need.

## Install

Install it from [CurseForge](https://www.curseforge.com/wow/addons/skillup-forever) or [Wago Addons](https://addons.wago.io/addons/skillup-forever), or download the zip from [Releases](https://github.com/cjber/skillup-forever/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/`.

## Usage

Turn off **Show tracked professions** in settings to hide the profession tracker. Your tracked professions and skill targets are kept.

Open a profession and the numbers are already there.

| Command | What it does |
|---|---|
| `/su`, `/skillup` | Open the settings (also in Settings → AddOns, or from the addon compartment on the minimap) |
| `/su skipped` | List the recipes you said *Not this recipe* to on this character, with their IDs |
| `/su unskip <ID>`, `/su unskip all` | Show a skipped recipe, or every one, in the route again |
| `/su audit` | With a profession open, compare the bundled thresholds with the colours the game shows and print any mismatch |
| `/su report` | Show a report to copy into a bug report: versions, your professions and routes, the audit, trainer checks and recent errors |
| `/su trainers` | List the trainer skill requirements SkillUp guessed, which ones a trainer has confirmed or shown differently, and which your trainer should teach at your skill now |

Settings cover rows and tooltips, what crafts count for, sort order, the route and crafted gear tabs, trainer annotations, reagent and gathering tooltips and companion hints.

## Prices

Each reagent uses the cheapest known vendor or Auctionator price. Common vendor supplies have bundled prices; visiting a vendor records its prices and reputation discounts. Materials your professions gather can count as free until you choose *Buy reagents*, or, with *Value gathered materials at what they'd sell for* on, cost what selling them would bring.

Auction prices use Auctionator's latest recorded price for reagents and crafted items. SkillUp never scans the auction house itself. Scan with Auctionator to update prices. Missing prices stay unknown and leave affected recipes out of the route.

A craft's vendor sell value comes off its cost by default. You can choose its auction value when higher, after the 5% cut. Profit shows a green `+`. Cost per skill-up is net craft cost divided by skill-up chance.

## How the numbers work

Each recipe has four thresholds: orange (start of its skill range), yellow, green and grey. Chance follows the Classic formula:

| Colour | Chance |
|---|---|
| Orange | 100% |
| Yellow, green | `(grey − skill) / (grey − yellow)` |
| Grey, or at your skill cap | 0% |

The colour always comes from the game, so the addon never disagrees. Thresholds and recipe data come from the Forever client's `SkillLineAbility` (via [wago.tools](https://wago.tools)). All bundled thresholds use the same Forever build, and the grey threshold is the game's own live value where it reports one. Missing or contradictory ranges show `?`. Training requirements are separate from these difficulty bands.

**Found a wrong number?** Run `/su audit` with that profession open and [open an issue](https://github.com/cjber/skillup-forever/issues/new) with the output.

Turn off **Attach to quest tracker** in Settings to drag the shared Forever column. Its position survives `/reload`; turn the setting back on to attach it above your quests.

## Works alongside

All optional: Auctionator supplies auction prices and takes the shopping list, TomTom draws waypoint arrows, and Syndicator shows your other characters' reagents. [Questie](https://www.curseforge.com/wow/addons/questie) names the vendors, quests and trainers the route points to, and [AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever) tells it which scroll teaches which recipe; without them the route still plans your crafts, and says in one line what to install for the rest. [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) plans the trip when you click a trainer or vendor, and SkillUp then picks the nearest one by travel time. [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) shows each profession's next steps in its Professions tab. A tracked route shares one tracker column with their sections and [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever)'s, above your quests. [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) adds options for repairs, junk selling, bags and maps.

## Development

Link the checkout into the game (`ln -s "$PWD" ".../Interface/AddOns/SkillUpForever"`) and run the gate under [Commands in AGENTS.md](AGENTS.md#commands) ([tools/README.md](tools/README.md) covers the data generators). CI runs the same gate plus actionlint, zizmor, gitleaks and sift; a daily job opens a pull request on a newer Forever build.

Run `luajit tests/bench.lua` from the repository root to measure loading, route rebuilds, event bursts and cached lookups in the headless client. These are CPU timings, not in-game latency measurements.

**Releasing:** follow the [release skill](.agents/skills/release/SKILL.md) for data, copy and screenshot checks, main-branch CI, signed tags and store verification. The BigWigs packager publishes the version's changelog entry to GitHub, CurseForge and Wago.

**Translating:** translations are welcome as a pull request or an issue; [Locales](https://github.com/cjber/skillup-forever/tree/main/Locales) has a template.

**Contributing:** read [CONTRIBUTING.md](https://github.com/cjber/.github/blob/main/CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) first. Report security problems privately, as [SECURITY.md](https://github.com/cjber/.github/blob/main/SECURITY.md) describes.

## Licence

GPL-3.0-or-later. Per-build thresholds come from the game via [wago.tools](https://wago.tools). Trainer fees, who trains what, drop chances and gathered reagents come from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0); vendors, quests, NPC places and scroll recipes are read in game from your own Questie and AtlasLoot, and none of their data is bundled; vendor reagents from [LibPeriodicTable-3.1](https://github.com/doadin/libperiodictable-3-1) (LGPL-2.1). Every input, its pin and licence, and what ships: [THIRD_PARTY.md](THIRD_PARTY.md).

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.
