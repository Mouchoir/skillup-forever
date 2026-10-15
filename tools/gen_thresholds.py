#!/usr/bin/env python3
"""Generate recipe spell thresholds for one pinned Forever client (stdlib only)."""

import argparse
import sys
import urllib.error
from collections import Counter, defaultdict
from pathlib import Path

from forever_tools import wago

USER_AGENT = "SkillUpForever/1.0"
BUILD = "1.60.1.70374"
# The Classic Era build Forever's thresholds are compared with: where Forever moved a recipe's yellow and
# grey but kept Classic's minimum, the minimum is stale. gen_trainer.py reads its teaching spells too.
TEACH_BUILD = "1.15.9.70003"
# Date this source snapshot was selected, not the date of each regeneration.
SOURCE_DATE = "2026-10-15"
# SpellEffect.Effect codes the generators read.
DUMMY = 3
TELEPORT_UNITS = 5
CREATE_ITEM = 24
OPEN_LOCK = 33
LEARN_SPELL = 36
TRANS_DOOR = 50  # summons an object: a campfire
ENCHANT_ITEM = 53  # a permanent enchant
SKILL = 118  # sets a skill line's rank: base points 0-3 raise the cap to 75-300
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


def generate(ability_rows, skills, selected, names, effects, classic=None, scrolls=None):
    classic = classic or {}
    scrolls = scrolls or {}
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
        "-- recipe at runtime.",
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
        (
            "SpellID",
            "Effect",
            "DifficultyID",
        ),
        **options,
    )
    classic_rows = db2(
        "SkillLineAbility",
        ("Spell", "MinSkillLineRank", "TrivialSkillLineRankHigh", "TrivialSkillLineRankLow"),
        build=TEACH_BUILD,
        **options,
    )
    scrolls = scroll_requirements(
        {int(row["Spell"]) for row in ability_rows},
        db2("ItemSparse", ("ID", "RequiredSkill", "RequiredSkillRank", "Flags_0"), **options),
        db2("ItemEffect", ("ID", "SpellID"), **options),
        db2("ItemXItemEffect", ("ItemID", "ItemEffectID"), **options),
    )
    skills, selected, excluded = professions(skill_rows)
    names = {int(row["ID"]): row["Name_lang"] for row in name_rows}
    effects = spell_effects(effect_rows)
    emitted, coverage, sources = generate(
        ability_rows, skills, selected, names, effects, ability_values(classic_rows), scrolls
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
