# Third-party inputs

Everything SkillUp Forever is built from that it did not write itself: where each comes from, where its pin lives, its
licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds it, so a data
refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later ([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Skill thresholds, recipes, reagents, the skill books that teach a rank, gathering locks and vendor prices in `Data/*.lua` | `BUILD` in `tools/gen_thresholds.py` (the other generators import it) | Blizzard Entertainment's game data |
| Classic Era client tables, via wago.tools | Which item teaches which recipe, and which spell is a rank, in `Data/Sources.lua` and `Data/Trainer.lua` | `TEACH_BUILD` in `tools/gen_thresholds.py` (the trainer and sources generators import it) | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Trainer fees, who trains what, the quests that teach a rank, drop chances and gathered reagents in `Data/Trainer.lua` and `Data/Sources.lua` | `CLASSICDB_COMMIT` in `tools/gen_trainer.py` (`tools/gen_sources.py` imports it) | GPL-3.0 |
| [LibPeriodicTable-3.1](https://github.com/doadin/libperiodictable-3-1) | Which reagents vendors sell, in `Data/Vendor.lua` | `PT_COMMIT` in `tools/gen_vendor.py` | LGPL-2.1 |

`tools/bump_pins.py` moves `BUILD`, `TEACH_BUILD` and `PT_COMMIT`. No embedded libraries ship. `media/` is this addon's own: the icon is drawn in `media/icon.svg`.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| Questie and QuestieDB, if installed | Vendors, quests and NPC places | QuestieDB carries no licence; nothing is copied |
| AtlasLoot Classic, if installed | Recipe scrolls and where they drop | Its own; nothing is copied |
| Auctionator, Syndicator, TomTom, Shortest Path Forever, if installed | Prices, counts across characters and waypoints, through their public APIs | Their own; nothing is copied |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The native tracker integration spec, fetched into `tools/.cache/` | `REVISION` in `tools/fetch_tracker_ui.py` | Blizzard Entertainment's; fetched, never committed |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/skills/tree/main/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [wow-mock-screenshots](https://github.com/cjber/skills/tree/main/wow-mock-screenshots) and the client art it fetches | `tools/screenshots.py` | `WOWMOCK` (a local checkout); the art at `BUILD` in `tools/gen_thresholds.py` | MIT; the art is Blizzard Entertainment's, fetched at build time and committed only as it appears in `docs/screenshots/` |
| sift gate | `.sift/gate.py` and `.sift/agents.py` in CI | Vendored by `sift setup` | MIT (`.sift/LICENSE`) |

CI tools (StyLua, ruff, luacheck, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never part of it.

## Ideas and contributors

Credit for the ideas and reports behind the addon.

| Who | What | Notes |
|---|---|---|
| [Polestar](https://github.com/fitzforge/polestar) by Fitz | The ideas for Expert and Artisan First Aid and Cooking from books and quests (#121) and the skill colour on gathering nodes and skinnable mobs (#122). From cjber/adventure-guide-forever's issues: `/su report` with its copy box and caught errors (#156), the issue forms (#157), the zip check (#158), `tools/doctor.py` (#160), the stale-screenshot check (#161), this file (#162), the "For addon authors" changelog subsection (#163) and `.editorconfig` (#165). | GPL-3.0. Inspired only; no code was copied. Fitz is welcome to use our code. |
| Brainc3ll | The French lines reused from Legacy Forever's translation (its #99) in `Locales/frFR.lua` | Unmarked lines; the rest of the file is machine translated |
| kopuliak, on CurseForge | Found recipes Forever lets you make earlier than Classic, such as Bronze Warhammer at 110 (#107, #123), the secret-number error on item tooltips (0.10.0) and on recipe tooltips (0.16.0); asked to hide tracked professions (0.9.0) and for Auctionator's latest price (0.9.1) | |
| chuujitsuna, on CurseForge | Found the quest tracker stuck mid-screen while SkillUp held it (#136), and confirmed the secret-number error, on item and recipe tooltips (#161) | |
| berserkerlxl, on CurseForge | Asked to value gathered materials at what they'd sell for (0.10.0) | |
| syrberus, on CurseForge | Reported the secret-number error on recipe tooltips, with the full error (#161, 0.16.0) | |

Thanks also to everyone else who reported a bug or asked for a feature, here or on CurseForge.
