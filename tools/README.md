Regenerate from the repository root with Python 3 (standard library only):

```sh
python3 tools/gen_thresholds.py
python3 tools/gen_vendor.py
python3 tools/gen_recipes.py
python3 tools/gen_trainer.py
python3 tools/gen_sources.py
luacheck .
tools/typecheck.sh
for s in tests/*_spec.lua; do luajit "$s" || exit 1; done
```

## Pins

`python3 tools/bump_pins.py` moves each pin to its newest upstream and prints what moved, or
nothing when all are current. `.github/workflows/refresh-data.yml` runs it daily, regenerates,
runs the specs and opens a pull request; a scheduled run that fails is re-run once ten minutes
later by `retry-refresh.yml`, and one that fails again opens the issue "Data refresh failed", or comments on it while it is open, and the next passing run closes it.

| Pin | In | Newest upstream |
| --- | --- | --- |
| `BUILD` | `gen_thresholds.py` | highest 1.6x build of `wow_classic_beta` on wago.tools (`tools/latest_build.py` prints it) |
| `TEACH_BUILD` | `gen_thresholds.py` | highest 1.1x build of `wow_classic_era` on wago.tools |
| `PT_COMMIT` | `gen_vendor.py` | last LibPeriodicTable commit that changed the Tradeskill file's bytes |
| `CLASSICDB_COMMIT` | `gen_trainer.py` | moved by hand only: a waiver in `AGENTS.md` |

`SOURCE_DATE` is set to the day a pin moved. `REVISION` in `fetch_tracker_ui.py` (the tracker UI
shared with the other Forever addons) and the annotation revision in `typecheck.sh` are test
inputs, moved by hand with the addons that share them.

## Generators

The generator pins one Forever build (`BUILD`), caches downloads in `tools/.cache/`,
and writes sorted `Data/Thresholds.lua`. Use `--refresh` to download again or
`--offline` to require cached sources. The header date identifies the selected
source snapshot, so repeated runs are byte-identical.

That build's `SkillLineAbility` supplies yellow and grey; green is the floored
midpoint of yellow and grey. Its `MinSkillLineRank` is the orange only where it is a
real value inside the range: Forever leaves most at the placeholder 1, and where it
moved a recipe's yellow and grey from Classic Era's (`TEACH_BUILD`) it often kept
Classic's minimum, which then sits too high or above yellow (issue #107). Such a row
takes the same build's pattern or recipe requirement (`ItemSparse`, `ItemEffect`,
`ItemXItemEffect`) when it is at most yellow, leaving out a pattern the client flags
deprecated (`Flags_0` 0x10: "Deprecated Recipe: ...", "... OLD"), which nobody learns from; else a stale minimum moves as far as
its range did; else the row keeps the placeholder 1 and the learn requirement
(`Core/Plan.lua`'s `LearnSkill`) gates the recipe at runtime. A replaced client value
is named in the row's comment, and every emitted row is ordered. `SkillLine` discovers professions and child
lines, `SpellName` supplies comments, and `SpellEffect` excludes gathering abilities.
`Model.Get` returns unknown for a contradictory row, including one a live grey
threshold makes, so displays and plans cannot use it.

Coverage prints per skill line, including skipped/duplicate rows and missing
names. Gathering abilities and test professions are excluded. Shared recipes
count once per profession but occupy one output key. DB2 download/schema failures
leave existing output untouched.

`gen_vendor.py` writes `Data/Vendor.lua`: unit prices (`BuyPrice / VendorStackCount`
from the same build's `ItemSparse`) for the items in LibPeriodicTable-3.1's
`Tradeskill.Mat.BySource.Vendor` set (pinned commit, LGPL-2.1), since which items
vendors sell is server data the client doesn't ship. Listed items missing from the
build are reported and skipped; a stack count below one fails the run. It shares the build pin and cache with `gen_thresholds.py`.

A recipe with no skill range in the build (`TrivialSkillLineRankHigh` not above
`TrivialSkillLineRankLow`) never gives a skill-up and gets no row, so the addon shows `?` for it.

`gen_recipes.py` writes `Data/Recipes.lua`, using only spell IDs already present in
the same-build `Data/Thresholds.lua`. `ns.ProfessionSkillLines` names every profession the
build has, including the gathering ones with no skill-up recipe. `ns.ItemGear` holds each crafted
item's required level, class and subclass (its armour or weapon type), inventory type (its slot) and
`AllowableClass`, from the same build's `Item` and `ItemSparse`; the gear view filters that with
`Core/Gear.lua`'s class proficiency table (the client's `SkillRaceClassInfo`). `ns.RecipeScrolls`
holds, per recipe spell, the pattern or recipe item that teaches it and the skill that item asks for,
from the same build's `ItemEffect` and `ItemSparse`: where the client's `SkillLineAbility` orange sits
at its placeholder 1, this is the recipe's real learn requirement. `ns.RankBooks` holds the profession ranks a book teaches
(Forever's Expert First Aid, Cooking and Fishing): the rank spell (`SpellEffect` SKILL or SKILL_STEP, tier in
its base points), the spell that learns it (LEARN_SPELL), the item that casts that (`ItemEffect`) and what the
book asks and costs (`ItemSparse`). The route reads a rank from a book only where no trainer teaches it. It imports the threshold generator's build,
snapshot date, cache and profession discovery; run thresholds first when changing
builds. All five generators accept `--offline` and `--refresh`. To verify the data
is fresh and reproducible:

```sh
python3 tools/check_generated.py --offline
```

It regenerates all five `Data` files in a scratch copy, fails if any differs from the
committed file, then regenerates again and fails if any is not byte-stable.

`gen_trainer.py` writes `Data/Trainer.lua`: base trainer fees for recipes with
thresholds, from the pinned CMaNGOS classic-db `npc_trainer` table (GPL-3.0). It reads
the dump by the column names in its own `CREATE TABLE` (`dump_tables`, which
`gen_sources.py` shares), and a row whose value count differs fails the run. Its
rows name teaching spells; Classic Era's `SpellEffect` (LEARN_SPELL) maps them to
recipe spells, since Forever's client leaves the teaching spells out.
Specialisation-gated rows are skipped, and fees recorded at a trainer in game win.
classic-db's required skill is Classic's: where Forever moved a recipe's yellow and grey
together from Classic Era's, the requirement moves as far (Forever moved its patterns'
requirements that way for all but a few recipes both clients teach by pattern), never below 1. It also writes `ns.TrainerRanks`: each profession rank a trainer teaches (the
taught spell's `SKILL` effect gives the skill line and the new cap), with fee,
required skill and level. Ranks that come from books or quests are absent. `ns.TrainerInferred` keeps classic-db's
requirement for each one the range rule moved, so `/su trainers` can show which a trainer confirmed (#124).
`SEEN_REQUIREMENTS` in `gen_trainer.py` holds requirements players saw lower in game (Bronze Warhammer at 110,
#123): a bundled requirement above one comes down to it, and it lists in `ns.TrainerInferred` like a moved one.
A trainer miss confirmed with `/su trainers` goes there, with its source and a test.

`gen_sources.py` writes `Data/Sources.lua`: what neither QuestieDB nor AtlasLoot holds about
where recipes come from, from the same classic-db dump. Who sells a scroll or a reagent, the
quests that reward one, which scroll teaches which recipe and every NPC's name, side and place
are not generated: the addon reads them in game from the player's QuestieDB and AtlasLoot.

Scroll items (`item_template` class 9) are those that teach a recipe through Classic Era's
LEARN_SPELL effects, as trainer spells do. For each, `ns.ScrollDrops` keeps the three likeliest
creature drops from `creature_loot_template` (following `reference_loot_template`), and
`ns.WorldDrops` marks the world drops: scrolls more than 100 creatures drop, or that only
reference tables no creature reaches hold.

Loot chances follow the rules the dump is written for. An item outside a group and every
reference rolls on its own; the items sharing a `groupid` give one of them, a chance of 0
being an equal share of what the others leave. A reference's `groupid` names the one group
of the referenced loot it rolls (0 for all of it) and its `maxcount` how many times. Read
that way no group in the dump sums past 100; one that does fails the run.

`ns.ProfessionTrainers` lists each profession's trainers with the highest rank they teach
(their `npc_trainer` rank spells). Where a trainer stands, and whether your side can use it,
comes from QuestieDB.

`ns.GatheredBy` maps reagents to the gathering profession that yields them at least
10% of the time: herb and mining nodes (`gameobject_template` chests whose `Lock`
needs the skill) and `skinning_loot_template`, with reference loot expanded. Rarer
finds (gems in veins) are left out.

`ns.NodeSkills` maps a herb or ore node's enUS name to the gathering skill and rank it asks for: the node's
`gameobject_template` lock (`data0`) joined to the client's `Lock` DB2 (a WFA-28 waiver in `AGENTS.md`). A lock
asking no skill (quest plants) is left out, and so is a name that nodes asking different skills share.

The recipe generator joins `SkillLineAbility` to `SpellReagents` and base-difficulty
`SpellEffect` rows. Reagents are sorted by item ID and repeated slots combined.
Missing or unresolved reagent rows are omitted, never converted into free recipes.
Conflicting memberships, reagent rows, outputs or names fail before replacing the
generated file. Output quantities are mean yields from `EffectBasePointsF`; zero
create-item amounts become one, and `Variance` validates that random yields do not
cross the minimum. Scaled or unsupported outputs fail for review. Permanent
enchants and summoned campfires have `output = false`; absence of create-item data
alone does not establish a non-item output. A valid live schematic takes precedence.

`ItemSellPrices` includes positive `ItemSparse.SellPrice` values for bundled recipe
outputs only. Missing ItemSparse rows are reported and have no bundled value.
`RecipeNames[skillLine][name]` uses exact `SpellName.Name_lang` strings from the enUS
export; ambiguous names map to `false`, including ambiguity between old and new
recipe variants. Name matching is a trainer fallback; other client locales need a
verified spell ID. Counts, omissions and file size print on each generation.

Runtime consumers filter `RecipeData[recipeID].skillLine` by the skill line
`ns.ProfessionSkillLine` (Core/Core.lua) resolves from the open profession's name.
These are parent skill-line IDs: First Aid 129, Blacksmithing 164, Leatherworking
165, Alchemy 171, Herbalism 182, Cooking 185, Mining 186, Tailoring 197, Engineering
202, Enchanting 333, Fishing 356 and Skinning 393; expansion child lines 2937–2948
are not recipe filters. Guard unavailable profession info and filter learned
recipes before building a route snapshot. `snapshot.skill` and `snapshot.target`
must use the same effective-skill coordinates (base plus modifier); `Core/Plan.lua`
is the one caller, and hands everything on in base skill with the trained cap applied. Shopping uses segment `crafts`, the ceiling of accumulated
expected crafts, and subtracts owned items once. Unknown reagent arrays contribute
no shopping rows, so only use priced route segments for a complete list.

## Screenshots

`docs/screenshots/*.png` and `demo.gif` are mocks rendered from the
client's own UI art, not in-game captures. Regenerate them from the repository
root with:

```sh
python3 tools/screenshots.py
```

It needs Pillow and `wowmock.py` from the `wow-mock-screenshots` skill in the
cjber/skills checkout, found at `~/.claude/skills/wow-mock-screenshots` by
default; set `WOWMOCK` to another directory that holds it. Art and fonts come
from wago.tools for the pinned Forever build and are cached under
`~/.cache/wowmock/`. Every number drawn comes from `Data/*.lua` through a port
of `Core/Model.lua`, or (route, tracker, trainer and reagent scenes) from the addon's own Lua run
under `luajit` with the client stubbed; only the scene's state (skill, bags, auction prices) is chosen
in the script. Repeated runs are byte-identical. `SCALE` (default 2) sets the
render scale.

## Shared tooling

`tools/forever_tools/` is the shared, offline Python (changelog and release checks, TOC traversal, the Lua
taint, multi-value and art lints, strict DB2 CSV parsing, atomic writes, the generated-data gate). It is vendored
byte for byte from `cjber/skills` (`wow-forever-addon/tooling`) and pinned by `forever_tools/MANIFEST.json`:
never edit it here. `python3 tools/forever_tools/sync.py check` verifies it offline (it runs in
`typecheck.sh`); `python3 tools/forever_tools/sync.py update --source <skills checkout>` refreshes it from a
clean checkout of the producer. The other `tools/*.py` entry points stay thin and carry only this repo's policy.

`python3 tools/data_report.py [--base REV]` prints what the generated data adds, removes and changes since a
revision (default `HEAD`), by record key; `tools/check_generated.py` prints the same when output is stale.

## Type checking

Install LuaLS 3.19.1, then run `tools/typecheck.sh` from any directory. The script
fetches Ketho's WoW annotations at `d0b5b51fac4c52c493371b9b18e66ce604ea4326`,
verifies that checkout is clean, runs the Python checker tests, the taint lint
(`python3 -m tools.lint_taint`), the TOC/XML coverage check
(`tools/typecheck_coverage.py`), the TOC-wide multi-value lint and the art lint
(`tools/lint_art.py`), and fails on any
LuaLS diagnostic. CI downloads LuaLS with a
pinned SHA-256. Editors use the same `.luarc.json` and `.types/` library.

`types/Namespace.lua` describes the shared addon table and data shapes;
`types/Client.lua` fills gaps in Ketho's FrameXML coverage using the Forever
client source; `types/Integrations.lua` describes optional addon APIs;
`types/API.lua` is the public API's contract and `types/TrackerHost.lua` the shared
tracker host's. Runtime
files annotate their parameters and custom frames. Generated files receive their
namespace annotation from the generators. Tests and tools are outside the LuaLS
workspace; every TOC-loaded Lua file is checked.

`python3 tools/lint_multivalue.py [files...]` also runs alone. A final bare
`select(...)` expands in a call, table constructor or return. Use `(select(...))`
for one value, or a local. Intentional expansion needs a trailing line comment:
`return select(2, ...) -- multi-value: forward the remaining results`.
