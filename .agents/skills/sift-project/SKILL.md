---
name: sift-project
description: "Project profile for sift in SkillUp Forever: the exact quality-gate and evidence commands, live roots that must never be deleted as dead code, exclusions, conventions and risk order. Load before running sift or any code-quality, cleanup or dead-code work in this repository."
---

# sift project profile — SkillUp Forever

SkillUp Forever is a World of Warcraft addon for the WoW: Forever client (Classic content on the
mainline 12.x UI/API, `## Interface: 16001`). It runs inside the game's Lua 5.1 sandbox; there is
no `require` — the client loads the files `SkillUpForever.toc` lists, in that order, and each file
receives `local addonName, ns = ...`, the addon's shared table. It ships as a zip built by the
BigWigs packager (`.pkgmeta`) on a `v*` tag and is consumed by players via CurseForge / Wago.
Standard-library Python generators in `tools/` rebuild the `Data/*.lua` tables from wago.tools DB2
exports and CMaNGOS dumps; `refresh-data.yml` runs them daily.

## Gate

Run in order from the repository root. All must pass before and after any audit slice.

| Step | Command | Pass means |
|---|---|---|
| Format (Lua) | `stylua --check .` | exit 0 (StyLua 2.5.2) |
| Format (Python) | `ruff format --check tools` | exit 0 (config: `tools/ruff.toml`) |
| Lint (Lua) | `luacheck .` | `0 warnings / 0 errors`, exit 0 |
| Lint (Python) | `ruff check tools` | exit 0 |
| Types and multi-values | `tools/typecheck.sh` | LuaLS 3.19.1 reports no diagnostics; tokenizer/parser lint and its tests pass |
| Tests | `for s in tests/*_spec.lua; do luajit "$s" \|\| exit 1; done` | exit 0; most print `<name>_spec: N checks passed`, `model_spec` appends its validated-thresholds count, and `recipelist_spec`/`settings_spec` print descriptive sentences |
| Changelog | `python3 tools/changelog.py --check` | every tagged version has a `CHANGELOG.md` entry |
| Workflows | `uvx --from actionlint-py==1.7.12.25 actionlint && uvx zizmor@1.30.1 --offline .github` | exit 0 |
| Secrets | `gitleaks git --redact --no-banner .` | `no leaks found` |
| Project rules | `python3 .sift/gate.py --base origin/main && python3 .sift/agents.py check` | exit 0 |

CI (`.github/workflows/ci.yml`) runs all of these; its `sift` job runs the changelog check and the
vendored `.sift/gate.py` and `.sift/agents.py`. LuaLS checks all TOC files against pinned WoW API annotations plus
`types/`; there is no ast-grep rule set.

The tests are a headless harness, not the game client. `tests/client.lua` is the one stub client: it loads
every file `SkillUpForever.toc` lists, in its order, against stubs of the client API, and a spec sets what the
client holds (professions, bags, a merchant, Auctionator's prices, the clock), fires its events and asserts on
what the addon produces, with nothing on `ns` faked. Over it run `api_spec` (the public list, down to a merchant's
price or a changed setting reaching it), `shopping_spec` (the objective tracker's lines and the merchant's buy
button), `changes_spec` (which caches drop and which views redraw for each game event and writer) and `prices_spec`
(where a price comes from). A new spec of headless behaviour starts there; a bundled table it needs small goes in
`Client.load`'s `data`. The rest each `loadfile` the file under test with their own stubs. Five of them take
only `Client.equal` and `Client.report` from `tests/client.lua`: `plan_spec` (Core/Plan.lua's levelling plan over
the bundled data, with costs and known recipes given directly so its arithmetic stays legible), `route_spec` (the
route page drawn into stub frames from a real plan), `core_spec` (Core/Core.lua's init guard, SavedVariables
migration and what's-new notice), `waypoint_spec` (Integrations/Sources.lua's waypoints and Shortest Path Forever
travel) and `locale_spec` (enUS phrases, `Locales/phrases.txt`, no packager keywords). Five never load it:
`model_spec` (Core/Model.lua, Data/Thresholds.lua, Integrations/Prices.lua), `recipelist_spec`
(UI/RecipeList.lua's native provider replacement, sorting and recursion), `settings_spec` (UI/Settings.lua),
`tracker_host_spec` (UI/TrackerHost.lua's frame lifecycle and combat placement, plus the pinned Forever tracker
source when `TRACKER_UI_ROOT` is set) and `tracker_geometry_spec` (where the host sits for each anchor, scale
and UI scale). Everything else
(UI hooks, menus, tooltips, in-game rendering, the trainer) is only verified in game. The
in-game check for data is `/su audit` with a profession open.

## Evidence

On-demand tools for audits. Output is candidates, never verdicts.

| Concern | Command | Known false positives |
|---|---|---|
| Types (Lua) | `tools/typecheck.sh` | Zero-diagnostic gate; missing Forever FrameXML surfaces are typed in `types/Client.lua` |
| Types (Python) | `uvx ty check tools --extra-search-path tools --output-format concise` | exits 1; baseline 7: `re.fullmatch(...).groups()` on a possible `None` (gen_thresholds.py), `defaultdict(Counter)` inferred as `Counter[str]` (gen_trainer.py, twice), untyped `json.load` result (latest_build.py), `ast.Module(body=...)` given a narrower list type (screenshots_test.py), unresolved `wowmock` (the wow-mock-screenshots library, put on `sys.path` at run time; screenshots.py) and unresolved `PIL` when ty cannot see Pillow |
| Dead code (Lua) | `luacheck . --no-color` (unused locals/values) + the live-root searches below | a function stored on `ns` is never "unused" to luacheck — search every file for `ns.<Name>` |
| Dead code (Python) | `uvx vulture tools --min-confidence 60` | clean at baseline; generator functions are imported across files (`from gen_thresholds import …`) |
| Duplication | `npx --yes jscpd@4 --silent --reporters json --output .sift/runs/jscpd --ignore "Data/**,tools/.cache/**,.sift/**" .` | 4 Python clones: the `argparse` preamble repeated in each `tools/gen_*.py` (a small idiom); 1 Lua clone: the stub frame in the two tracker specs, which are shared files (see Conventions) |
| Live roots | `rg -n 'hooksecurefunc|RegisterEvent|RegisterCallback|SetScript|AddTooltipPostCall|AddInitializedFrameCallback|Menu.ModifyMenu|SLASH_|SlashCmdList' -g '*.lua'` | — |
| Data byte-compare | copy the primary checkout's ignored `tools/.cache/`, then `python3 tools/gen_<name>.py --offline` and `git status Data` | only `gen_thresholds` and `gen_vendor` run from the usual cache; the others need the classic-db and era DB2 downloads (drop `--offline` once) |
| Standards | `python3 <sift>/scripts/agents.py standards` | resolves the pinned `wow-forever-addon` URL from cache; offline with no cached copy it prints `unknown-standard` (set `SIFT_STANDARDS_PATH=~/skills` to use the local clone) |

## Live roots

Things reached indirectly. The dead-code lens must treat these as referenced.

- `SkillUpForever.toc` file list: loads the Lua and XML files it lists under `Locales/`, `Data/`, `Core/`, `Integrations/` and `UI/`, in that order, except `UI/ForeverFamily.lua`, which loads between `Data/` and `Core/` (Core needs `ns.Family`, and `tests/client.lua` injects fixtures before the first non-Locales, non-Data file); nothing `require`s them.
- `ns.*` — the shared addon table; a function defined in one file is typically called from another. Search all files for `ns.Name`, not the local file.
- `## SavedVariables: SkillUpForeverDB` — persisted per account; keys in `Core/Core.lua` `DEFAULTS` and anything read from `SkillUpForeverDB` may hold data written by older versions.
- `Locales/<locale>.lua` — translators' files, loaded from the TOC after `enUS.lua`; `tools/phrases.py` runs from `tests/locale_spec.lua`.
- `SkillUpForever.API` (Core/API.lua) — the public API other addons (Adventure Guide Forever) call; `types/API.lua` is its contract.
- `## AddonCompartmentFunc: SkillUpForever_OnAddonCompartmentClick` — global called by the client by name.
- `SLASH_SKILLUPFOREVER1/2` + `SlashCmdList.SKILLUPFOREVER` — `/su` commands.
- `hooksecurefunc("ClassTrainerFrame_InitServiceButton" | "ClassTrainerFrame_Update", …)`, `EventUtil.ContinueAfterAllEvents` — Blizzard trainer functions hooked by string name, plus a load-sequencing callback.
- `EventRegistry:RegisterCallback("Professions.RecipeListOnEnter")`, `Menu.ModifyMenu("MENU_PROFESSIONS_FILTER")`, `TooltipDataProcessor.AddTooltipPostCall` — host callbacks.
- `ScrollUtil.AddInitializedFrameCallback(recipeList.ScrollBox, DecorateRow, ns)` (UI/RecipeList.lua) and `Auctionator.API.v1.RegisterForDBUpdate(addonName, PricesChanged)` (Integrations/Prices.lua `ns.InitPrices`) — callbacks the plain live-root search misses.
- `ns.WhenStale(name, fn)` and `ns.WhenEvent(event, fn)` — handlers Core/Changes.lua calls by cache/view name and by event; its `EVENTS` table registers the game events.
- `RegisterEvent("…")` + `OnEvent` dispatch on the event string — handlers are reached by event name.
- Optional integrations (`## OptionalDeps: Auctionator, TomTom, Syndicator, ShortestPathForever`) — code guarded by `if Auctionator` etc. is live only with that addon installed.
- `tools/gen_*.py` public names imported by sibling generators; `tools/bump_pins.py` (which imports `tools/latest_build.py`) and `tools/changelog.py` run from workflows.
- `tools/screenshots.py` — run by hand (WFA-9) to rewrite `docs/screenshots/`; the route, tracker, trainer and reagent scenes run the addon's own Lua under luajit, while the recipe-list scenes port Model/Core maths to Python, so check its ports against the Lua (`round_money` vs `Model.RoundMoney`) rather than treating it as its own source of truth.

## Zones

How each part of the tree is reviewed. Unlisted paths are `production`.

| Path | Zone | Reason |
|---|---|---|
| `Data/*.lua` | generated | written by `tools/gen_*.py`; never hand-edit, fix the generator |
| `tools/` | script | data generators, CI helpers; not shipped |
| `tests/` | test | headless LuaJIT harness |
| `.github/`, `.pkgmeta`, `.luacheckrc`, `.luarc.json`, `stylua.toml`, `.gitleaks.toml`, `.gitattributes`, `.gitignore`, `.styluaignore`, `tools/ruff.toml`, `SkillUpForever.toc` | config | the TOC's `## Notes` is user-facing |
| `types/` | config | LuaLS `---@meta` annotations; not shipped. Check them against the code they describe |
| `README.md`, `CHANGELOG.md`, `docs/`, `tools/README.md` | docs | `docs/curseforge.md` is the store listing |
| `media/`, `docs/screenshots/` | assets | |

## Conventions

- One feature per file under `Core/`, `Integrations/` or `UI/`; each starts `local addonName, ns = ...` (or `local _, ns = ...`) and exports through `ns.Name = …` / `function ns.Name(…)`. File-private helpers are `local function`.
- Tabs, 120 columns, double quotes (StyLua). PascalCase for functions, camelCase for locals and DB keys.
- Unknown data renders `?`/`nil` rather than a guess; generators raise instead of clamping bad data (see `tools/README.md`). A silent fallback that invents a number is a defect here.
- Comments explain *why* (client quirks, Forever beta bugs, data provenance), not what.
- Host globals go in `.luacheckrc` `read_globals`. LuaLS uses pinned Ketho annotations and typed gaps in `types/`, never a bare globals allowlist.
- Text shown in game (Settings tooltips, `ns.Print` messages) and the store listing `docs/curseforge.md` are user-facing: audits propose changes, never make them.
- New dev-only root files must be added to `.pkgmeta` `ignore:` so they don't ship in the zip. Dot paths
  never ship (the pinned packager prunes them before `ignore:`), so they need no entry.
- Some guards and annotations exist for LuaLS, not at run time: `---@class` on a table built field by
  field (UI/List.lua `CreateList`) and `if not module then return end` narrowing an optional upvalue
  (UI/Shopping.lua `Attach`). Removing either fails `tools/typecheck.sh`.
- `UI/TrackerHost.lua`, `tests/tracker_host_spec.lua` and `tests/tracker_geometry_spec.lua` are shared byte
  for byte with the sibling Forever addons. A defect in one is `decide`, since every copy changes together.

## Risk order

Audit slices from lowest to highest risk:

1. `tools/` — scripts, not shipped; output is diffable.
2. `tests/` — harness only.
3. `Core/Model.lua`, `UI/Settings.lua`, `Integrations/Sources.lua`, `UI/List.lua`, `types/` — pure maths / settings / lookups /
   the shared list widget, partly under test.
4. `Locales/enUS.lua` — copy: every phrase a player reads. Reviewed for WFA-23/24 voice with
   `docs/curseforge.md` and the README; audits propose wording, never change it (see Conventions).
5. `UI/Tooltip.lua`, `UI/RecipeList.lua`, `Integrations/Trainer.lua` — UI hooks, in-game verification only.
6. `Integrations/Prices.lua`, `Core/Core.lua`, `Core/Changes.lua`: SavedVariables, vendor prices, the Auctionator price seam and
   what each change drops and redraws; persisted data.
7. `Core/Plan.lua`, `UI/Route.lua`, `UI/Shopping.lua`, `UI/Shopping.xml`, `UI/TrackerHost.lua`, `Core/API.lua`: the levelling plan and the largest, most stateful UI over it (crafting, buying and tracker
   integration), and the public API other addons call (`types/API.lua` is its contract).

Tiers 6 and 7 get a second, independent reviewer (Codex): on 2026-09-24 it found the two route and
price bugs the first reviewer missed, each with an in-memory LuaJIT repro.

## Settled

Shapes that look like defects here but are not. Reviewers and verifiers read this before raising a
finding; audits add an entry when verifiers keep dismissing the same shape for the same reason.

- Client-capability checks (`defensive-noise`): a guard on a host global or field (`C_TooltipInfo`,
  `issecretvalue`, `GameTooltip.RefreshData`) stays even when `types/Client.lua` annotates it; the
  annotations never run in the client, e.g. `UI/Tooltip.lua`, `Integrations/Trainer.lua`
- Host-mirroring annotations (`dead-code`): `types/Client.lua` members that mirror a real client table
  or a shape the host reads (`VarType.Number`, `colorStyle.reverse`) stay though the addon never names them
- Money and name one-liners (`parallel-implementations`): signed-money text and "name or placeholder"
  lookups composed from `Model.RoundMoney`/`ns.FormatNet`/`L[...]` are a small idiom; Tooltip keeps copper
  precision and API formats positive fees on purpose, e.g. `UI/Route.lua` `Money`, `Core/Core.lua` `Describe`
- Price provenance vs shopping bucket (`stringly-typed`): `SkillUpPriceSource` (`vendor`/`auctionator`/`gather`)
  and the shopping bucket (`auction`, ...) are distinct literal-union contracts; `PriceAge` reads
  Auctionator-only age data, so its `"auctionator"` test is not the bucket, e.g. `UI/Route.lua` `PriceAge`

## Anti-patterns

Recurring judgment defects; check new code for them.

- **Hand port drift**: a hand port drifts from its Lua source (`parallel-implementations`): `tools/screenshots.py`
  `round_money`/`model_recipe_cost`/`price()` vs `Model.RoundMoney`/Prices.lua's `ReagentCost`/`ns.Price`.
- **Shopping bucket list restated**: the bucket list `gather`/`vendor`/`auction`/`unknown` enumerated
  by hand (`stringly-typed`) instead of walking `Model.SHOPPING_SOURCES`; an added bucket silently drops items.
  `route_spec` checks every bucket gets a Source label; Core/API.lua's `ReagentSource` maps buckets onto the public
  API's own sources on purpose.
- **Unvalidated saved setting**: a saved choice read without checking it against its options
  (`silent-fallbacks`). `LoadDB` resets `craftValue`, `sortMode` and `reagentTooltip` to their defaults when the
  saved value isn't one of `ns.*_OPTIONS`; a new dropdown setting joins that loop.
- **View left out of a change**: a `STALE` row in `Core/Changes.lua` drops a cache but not the views that show
  what it holds (`silent-fallbacks`), e.g. `fees` and `level` rebuild the plan or the API while the route page
  and tracker keep the old text. `changes_spec` pins each row as written, so check a row against every reader
  of the input that changed.

## Project rules and lenses

- Rules: none yet (no repeated shape a tool can match without judgment).
- Lenses: none yet.

The type gate also runs `python3 -m tools.lint_taint` and `python3 tools/typecheck_coverage.py`: native-method hooks, shared UI-state writes and omitted runtime type coverage fail CI. TrackerHost owns addon sections and pools outside Blizzard's registry; first rendering follows both native load events, deferred one frame. CI runs the private host against pinned Forever module/block/animation source.
