#!/usr/bin/env python3
"""Generate recipe spell thresholds for one pinned Forever client (stdlib only)."""

import argparse
import sys
import urllib.error
from collections import Counter, defaultdict
from pathlib import Path

from forever_tools import wago

USER_AGENT = "SkillUpForever/1.0"
BUILD = "1.60.1.70450"
# The Classic Era build Forever's thresholds are compared with: where Forever moved a recipe's yellow and
# grey but kept Classic's minimum, the minimum is stale. gen_trainer.py reads its teaching spells too.
TEACH_BUILD = "1.15.9.70003"
# Date this source snapshot was selected, not the date of each regeneration.
SOURCE_DATE = "2026-10-17"
# SpellEffect.Effect codes the generators read.
DUMMY = 3
TELEPORT_UNITS = 5
CREATE_ITEM = 24
OPEN_LOCK = 33
LEARN_SPELL = 36
TRANS_DOOR = 50  # summons an object: a campfire
ENCHANT_ITEM = 53  # a permanent enchant
SKILL = 118  # sets a skill line's rank: base points 0-3 raise the cap to 75-300
SKILL_STEP = 44  # the same for Apprentice and Journeyman on Forever, which uses SKILL for Expert and Artisan
# Each rank raises a profession's cap by this much. Classic Era's integer EffectBasePoints holds the tier less
# one; Forever's export has only EffectBasePointsF, which holds the tier itself (1-4).
RANK_SKILL = 75
# ItemSparse.Flags_0 bit the client sets on an item it no longer drops or sells ("Deprecated Recipe: ...",
# "Pattern: ... OLD"). Such an item's requirement is not a skill anyone learns the recipe at.
ITEM_DEPRECATED = 0x10
ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
OUTPUT = ROOT / "Data" / "Thresholds.lua"
REQUIRED_SKILLS = {
    129: "First Aid",
    164: "Blacksmithing",
    165: "Leatherworking",
    171: "Alchemy",
    185: "Cooking",
    186: "Mining",
    197: "Tailoring",
    202: "Engineering",
    333: "Enchanting",
}
# Fishing is category 9 with CanLink=0; unlike racials/riding, it is a profession.
SECONDARY_SKILLS = {356}


def download(url, filename, refresh=False, offline=False):
    data = wago.fetch(url, CACHE / filename, user_agent=USER_AGENT, refresh=refresh, offline=offline)
    return data.decode("utf-8-sig")


def db2(name, columns, refresh=False, offline=False, build=BUILD):
    return wago.db2_rows(name, build, CACHE, user_agent=USER_AGENT, refresh=refresh, offline=offline, required=columns)


def professions(skill_rows):
    """Discover primary professions, linked secondaries, and their child lines."""
    skills = {int(row["ID"]): row for row in skill_rows}
    selected = set(REQUIRED_SKILLS)
    excluded = {}
    for sid, row in skills.items():
        if "[DNT]" in row["DisplayName_lang"] or row["DisplayName_lang"].startswith("Test "):
            excluded[sid] = row["DisplayName_lang"]
        elif (
            int(row["CategoryID"]) == 11
            or sid in SECONDARY_SKILLS
            or (int(row["CategoryID"]) == 9 and row["CanLink"] == "1")
        ):
            selected.add(sid)
    while True:
        children = {
            sid for sid, row in skills.items() if int(row["ParentSkillLineID"]) in selected and sid not in excluded
        }
        if children <= selected:
            break
        selected.update(children)
    return skills, selected, excluded


def spell_effects(rows):
    effects = defaultdict(set)
    for row in rows:
        if int(row["DifficultyID"]) != 0:
            continue
        spell, effect = int(row["SpellID"]), int(row["Effect"])
        effects[spell].add(effect)
    return effects


def ability_values(rows):
    """[spell] = (orange, yellow, grey) of each spell whose SkillLineAbility rows all agree."""
    values = defaultdict(set)
    for row in rows:
        try:
            value = (
                int(row["MinSkillLineRank"]),
                int(row["TrivialSkillLineRankLow"]),
                int(row["TrivialSkillLineRankHigh"]),
            )
        except (ValueError, TypeError):
            continue
        values[int(row["Spell"])].add(value)
    return {spell: next(iter(seen)) for spell, seen in values.items() if len(seen) == 1}


def shift(spell, yellow, grey, classic):
    """How far Forever moved a recipe's yellow and grey from Classic Era's, when both moved together.

    None when Classic Era has no single row for it or its range changed shape."""
    before = classic.get(spell)
    if before is None or yellow - before[1] != grey - before[2]:
        return None
    return yellow - before[1]


def shifts(ability_rows, classic):
    """[spell] = how far Forever moved each recipe's range from Classic Era's, for those it moved."""
    moved = {}
    for spell, (_, yellow, grey) in ability_values(ability_rows).items():
        delta = shift(spell, yellow, grey, classic)
        if delta:
            moved[spell] = delta
    return moved


def scroll_requirements(ids, item_rows, item_effect_rows, effect_link_rows):
    """[spell] = (item, skill): the pattern or recipe item that teaches each spell and the skill it asks.

    Its own profession requirement is the skill at which the recipe can first be learned. Where several
    items teach one spell, the lowest requirement is the earliest any of them can be learned. A deprecated
    item (ITEM_DEPRECATED) teaches nobody, so its requirement is left out."""
    taught = {int(row["ID"]): int(row["SpellID"]) for row in item_effect_rows}
    requirements = {
        int(row["ID"]): (int(row["RequiredSkill"]), int(row["RequiredSkillRank"]))
        for row in item_rows
        if not int(row.get("Flags_0") or 0) & ITEM_DEPRECATED
    }
    scrolls = {}
    for row in effect_link_rows:
        spell = taught.get(int(row["ItemEffectID"]))
        item = int(row["ItemID"])
        required = requirements.get(item)
        if spell not in ids or not required or required[0] == 0 or required[1] <= 0:
            continue
        held = scrolls.get(spell)
        if held is None or required[1] < held[1] or (required[1] == held[1] and item < held[0]):
            scrolls[spell] = (item, required[1])
    return scrolls


# Recipes the game no longer lets anyone learn or make, left out of every Data/ file. ItemSparse is partial (about
# 40% of Item rows have no ItemSparse row, the Arcanist set and many live patterns among them), so a missing row
# alone does not mean an item is gone; an item that leaves ItemSparse between pinned builds does. Each entry names
# the build that retired it, and check_retired fails the run if a later build brings back an item that teaches or
# makes it, so it gets reviewed rather than staying hidden.
RETIRED = {
    # Forever 70425 took every Tinkerbox schematic, the Tinkerbox (238737) and the three Tinkerbox kits out of
    # ItemSparse, all of which 70374 had (owner decision 2026-10-16).
    1226206: "Tinkerbox, retired in 1.60.1.70425",
    1226207: "Tinkerbox: Teleport, retired in 1.60.1.70425",
    1226208: "Tinkerbox: Nitro Boosts, retired in 1.60.1.70425",
    1226209: "Tinkerbox: Magnetic Displacement, retired in 1.60.1.70425",
    1226210: "Tinker: Teleport, retired in 1.60.1.70425",
    1226211: "Tinker: Nitro Boosts, retired in 1.60.1.70425",
    1226212: "Tinker: Magnetic Displacement, retired in 1.60.1.70425",
}


def check_retired(retired, spells, effect_rows, sparse_ids, item_effect_rows, effect_link_rows, reagent_rows):
    """Fail when a RETIRED recipe can be learned or made again in this build, or is no longer a recipe in it.

    It can be learned or made when an item that teaches it (directly, or through a LEARN_SPELL teaching spell) is
    in ItemSparse and not deprecated, or the item it makes is, or for a recipe that makes no item, every one of its
    reagents. `sparse_ids` holds the ItemSparse items, deprecated ones left out by the caller.
    """
    gone = sorted(set(retired) - spells)
    if gone:
        raise ValueError(f"RETIRED recipes are no longer in SkillLineAbility; remove them: {gone}")
    learns = defaultdict(set)
    outputs = defaultdict(set)
    for row in effect_rows:
        if int(row["DifficultyID"]) != 0:
            continue
        effect, spell = int(row["Effect"]), int(row["SpellID"])
        if effect == LEARN_SPELL:
            learns[int(row["EffectTriggerSpell"])].add(spell)
        elif effect == CREATE_ITEM and spell in retired and int(row["EffectItemType"]) > 0:
            outputs[spell].add(int(row["EffectItemType"]))
    effects_of = defaultdict(set)
    for row in item_effect_rows:
        effects_of[int(row["SpellID"])].add(int(row["ID"]))
    items_of = defaultdict(set)
    for row in effect_link_rows:
        items_of[int(row["ItemEffectID"])].add(int(row["ItemID"]))
    reagents = {
        int(row["SpellID"]): {int(row[f"Reagent_{i}"] or 0) for i in range(8)} - {0}
        for row in reagent_rows
        if int(row["SpellID"]) in retired
    }
    back = []
    for spell in sorted(retired):
        teachers = {
            item
            for teaching in {spell} | learns.get(spell, set())
            for effect in effects_of.get(teaching, ())
            for item in items_of.get(effect, ())
        }
        made, needs = outputs.get(spell), reagents.get(spell)
        if made:
            craftable = bool(made & sparse_ids)
        else:
            craftable = bool(needs) and needs <= sparse_ids
        if teachers & sparse_ids or craftable:
            back.append(f"{spell} ({retired[spell]})")
    if back:
        raise ValueError(f"RETIRED recipes can be learned or made again; review and remove them: {', '.join(back)}")


def reconcile(spell, orange, yellow, grey, classic, scroll):
    """The orange a recipe's row gets, and where it came from.

    The client's MinSkillLineRank is kept when it is a real value inside the range. It is not when it is
    the placeholder 1, sits above yellow, or is Classic Era's minimum left behind on a range Forever moved.
    Then the same build's pattern or recipe requirement is the minimum; else a stale minimum moves with
    its range; else the row keeps the client's placeholder 1 and the learn requirement gates it at runtime.
    """
    delta = shift(spell, yellow, grey, classic)
    stale = bool(delta) and orange > 1 and orange == classic[spell][0]
    if 1 < orange <= yellow and not stale:
        return orange, "client"
    if scroll is not None and 1 <= scroll <= yellow:
        return scroll, "scroll"
    if orange > 1 and delta is not None and 1 <= orange + delta <= yellow:
        return orange + delta, "shifted"
    return 1, "placeholder" if orange <= 1 else "dropped"


def generate(ability_rows, skills, selected, names, effects, classic=None, scrolls=None, retired=None):
    classic = classic or {}
    scrolls = scrolls or {}
    retired = retired or set()
    stats = {sid: Counter() for sid in selected}
    candidates = defaultdict(list)
    for row in ability_rows:
        sid = int(row["SkillLine"])
        if sid not in selected:
            continue
        counts = stats[sid]
        counts["rows"] += 1
        try:
            spell = int(row["Spell"])
            orange = int(row["MinSkillLineRank"])
            yellow = int(row["TrivialSkillLineRankLow"])
            grey = int(row["TrivialSkillLineRankHigh"])
            if spell <= 0 or min(orange, yellow, grey) < 0:
                raise ValueError
        except (ValueError, TypeError):
            counts["skip:missing/invalid data"] += 1
            continue
        if grey <= yellow:
            counts["skip:grey<=yellow"] += 1
            continue
        # Mining's open-lock gathering abilities have thresholds but are not
        # crafting recipes. Do not emit them as smelting recipes.
        if effects.get(spell) == {OPEN_LOCK}:
            counts["skip:gathering ability"] += 1
            continue
        if spell in retired:
            counts["skip:retired"] += 1
            continue
        candidates[spell].append((sid, (orange, yellow, grey)))

    emitted, sources = {}, {}
    for spell, rows in sorted(candidates.items()):
        if len({t for _, t in rows}) != 1:
            for sid, _ in rows:
                stats[sid]["skip:conflicting recipe rows"] += 1
            continue
        client, yellow, grey = rows[0][1]
        scroll = scrolls.get(spell)
        orange, source = reconcile(spell, client, yellow, grey, classic, scroll and scroll[1])
        seen = set()
        for sid, _ in sorted(rows):
            if sid in seen:
                stats[sid]["skip:duplicate recipe row"] += 1
                continue
            seen.add(sid)
            stats[sid]["emitted"] += 1
            if source != "client":
                stats[sid][f"orange:{source}"] += 1
            if not names.get(spell):
                stats[sid]["missing spell name"] += 1
        emitted[spell] = (orange, yellow, (yellow + grey) // 2, grey)
        if source in ("scroll", "shifted", "dropped") and client > 1:
            sources[spell] = f"client orange {client}: {source}"

    coverage = []
    for sid in sorted(selected):
        counts = stats[sid]
        name = skills[sid]["DisplayName_lang"] if sid in skills else REQUIRED_SKILLS[sid]
        skipped = sum(value for key, value in counts.items() if key.startswith("skip:"))
        reasons = ", ".join(f"{key[5:]}={value}" for key, value in sorted(counts.items()) if key.startswith("skip:"))
        line = f"{name} ({sid}): {counts['emitted']} emitted / {skipped} skipped"
        if reasons:
            line += f" ({reasons})"
        oranges = ", ".join(f"{key[7:]}={value}" for key, value in sorted(counts.items()) if key.startswith("orange:"))
        if oranges:
            line += f"; orange {oranges}"
        if not counts["rows"]:
            line += "; no SkillLineAbility rows"
        if sid not in skills:
            line += "; MISSING SkillLine"
        coverage.append(line)
        print(line)
        if counts["missing spell name"]:
            print(f"  Missing SpellName: {counts['missing spell name']} (comments only)")
    return emitted, coverage, sources


def render(emitted, coverage, names, sources=None):
    lines = [
        "-- Generated by tools/gen_thresholds.py - do not edit.",
        f"-- Source: wago.tools DB2, wow_classic_beta {BUILD}, {SOURCE_DATE}.",
        f"-- DB2: https://wago.tools/db2/SkillLineAbility/csv?build={BUILD}",
        "-- SkillLine, SpellName, and SpellEffect: same source and build.",
        "-- {orange, yellow, green, grey}; green = floor((yellow + grey) / 2).",
        "-- Yellow and grey are this Forever build's. Orange is its MinSkillLineRank where that is a real value",
        "-- inside the range; else the same build's pattern requirement (ItemSparse, ItemEffect), deprecated",
        f"-- patterns left out; else, for a minimum left at Classic Era {TEACH_BUILD}'s on a range Forever moved,",
        "-- that minimum moved as far; else the client's placeholder 1, and the learn requirement gates the",
        "-- recipe at runtime. Recipes the game retired (RETIRED in gen_thresholds.py) are left out.",
        f"-- {len(emitted)} unique recipe spell IDs; a shared recipe counts in each profession below.",
    ]
    lines.extend("-- " + line for line in coverage)
    lines.extend(["---@type string, SkillUpNamespace", "local _, ns = ...", "ns.Thresholds = {"])
    for spell, thresholds in sorted(emitted.items()):
        name = " ".join(names.get(spell, "SpellName unavailable").split())
        values = ", ".join(map(str, thresholds))
        flag = f"; {sources[spell]}" if sources and spell in sources else ""
        lines.append(f"\t[{spell}] = {{ {values} }}, -- {name}{flag}")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    options = {"refresh": args.refresh, "offline": args.offline}
    ability_rows = db2(
        "SkillLineAbility",
        (
            "Spell",
            "SkillLine",
            "MinSkillLineRank",
            "TrivialSkillLineRankHigh",
            "TrivialSkillLineRankLow",
        ),
        **options,
    )
    skill_rows = db2(
        "SkillLine",
        (
            "ID",
            "DisplayName_lang",
            "CategoryID",
            "CanLink",
            "ParentSkillLineID",
        ),
        **options,
    )
    name_rows = db2("SpellName", ("ID", "Name_lang"), **options)
    effect_rows = db2(
        "SpellEffect",
        ("SpellID", "Effect", "DifficultyID", "EffectItemType", "EffectTriggerSpell"),
        **options,
    )
    classic_rows = db2(
        "SkillLineAbility",
        ("Spell", "MinSkillLineRank", "TrivialSkillLineRankHigh", "TrivialSkillLineRankLow"),
        build=TEACH_BUILD,
        **options,
    )
    spells = {int(row["Spell"]) for row in ability_rows}
    sparse_rows = db2("ItemSparse", ("ID", "RequiredSkill", "RequiredSkillRank", "Flags_0"), **options)
    item_effect_rows = db2("ItemEffect", ("ID", "SpellID"), **options)
    effect_link_rows = db2("ItemXItemEffect", ("ItemID", "ItemEffectID"), **options)
    scrolls = scroll_requirements(spells, sparse_rows, item_effect_rows, effect_link_rows)
    check_retired(
        RETIRED,
        spells,
        effect_rows,
        {int(row["ID"]) for row in sparse_rows if not int(row.get("Flags_0") or 0) & ITEM_DEPRECATED},
        item_effect_rows,
        effect_link_rows,
        db2("SpellReagents", ("SpellID", *(f"Reagent_{i}" for i in range(8))), **options),
    )
    skills, selected, excluded = professions(skill_rows)
    names = {int(row["ID"]): row["Name_lang"] for row in name_rows}
    effects = spell_effects(effect_rows)
    emitted, coverage, sources = generate(
        ability_rows, skills, selected, names, effects, ability_values(classic_rows), scrolls, set(RETIRED)
    )
    if not emitted:
        raise ValueError("No usable recipes; leaving existing generated output untouched")
    for sid, name in sorted(excluded.items()):
        print(f"Excluded test skill line: {name} ({sid})")
    missing = [str(sid) for sid in sorted(REQUIRED_SKILLS) if sid not in skills]
    print("Missing required skill lines: " + (", ".join(missing) or "none"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(emitted, coverage, names, sources), encoding="utf-8")
    print(f"Wrote {len(emitted)} unique recipe spell IDs to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
