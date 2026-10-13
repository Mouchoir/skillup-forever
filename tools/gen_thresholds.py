#!/usr/bin/env python3
"""Generate recipe spell thresholds for one pinned Forever client (stdlib only)."""

import argparse
import sys
import urllib.error
from collections import Counter, defaultdict
from pathlib import Path

from forever_tools import wago

USER_AGENT = "SkillUpForever/1.0"
BUILD = "1.60.1.70338"
# Date this source snapshot was selected, not the date of each regeneration.
SOURCE_DATE = "2026-10-13"
# SpellEffect.Effect codes the generators read.
DUMMY = 3
TELEPORT_UNITS = 5
CREATE_ITEM = 24
OPEN_LOCK = 33
LEARN_SPELL = 36
TRANS_DOOR = 50  # summons an object: a campfire
ENCHANT_ITEM = 53  # a permanent enchant
SKILL = 118  # sets a skill line's rank: base points 0-3 raise the cap to 75-300
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


def generate(ability_rows, skills, selected, names, effects):
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
        t = (orange, yellow, (yellow + grey) // 2, grey)
        candidates[spell].append((sid, t))

    emitted = {}
    for spell, rows in sorted(candidates.items()):
        if len({t for _, t in rows}) != 1:
            for sid, _ in rows:
                stats[sid]["skip:conflicting recipe rows"] += 1
            continue
        seen = set()
        for sid, thresholds in sorted(rows):
            if sid in seen:
                stats[sid]["skip:duplicate recipe row"] += 1
                continue
            seen.add(sid)
            stats[sid]["emitted"] += 1
            if thresholds[0] > thresholds[1]:
                stats[sid]["inconsistent orange>yellow"] += 1
                print(
                    f"WARNING: recipe {spell} ({names.get(spell, 'SpellName unavailable')}): "
                    f"keeping inconsistent DB2 thresholds {thresholds}",
                    file=sys.stderr,
                )
            if not names.get(spell):
                stats[sid]["missing spell name"] += 1
        emitted[spell] = rows[0][1]

    coverage = []
    for sid in sorted(selected):
        counts = stats[sid]
        name = skills[sid]["DisplayName_lang"] if sid in skills else REQUIRED_SKILLS[sid]
        skipped = sum(value for key, value in counts.items() if key.startswith("skip:"))
        reasons = ", ".join(f"{key[5:]}={value}" for key, value in sorted(counts.items()) if key.startswith("skip:"))
        line = f"{name} ({sid}): {counts['emitted']} emitted / {skipped} skipped"
        if reasons:
            line += f" ({reasons})"
        if counts["inconsistent orange>yellow"]:
            line += f"; inconsistent DB2 orange>yellow={counts['inconsistent orange>yellow']} retained"
        if not counts["rows"]:
            line += "; no SkillLineAbility rows"
        if sid not in skills:
            line += "; MISSING SkillLine"
        coverage.append(line)
        print(line)
        if counts["missing spell name"]:
            print(f"  Missing SpellName: {counts['missing spell name']} (comments only)")
    return emitted, coverage


def render(emitted, coverage, names):
    lines = [
        "-- Generated by tools/gen_thresholds.py - do not edit.",
        f"-- Source: wago.tools DB2, wow_classic_beta {BUILD}, {SOURCE_DATE}.",
        f"-- DB2: https://wago.tools/db2/SkillLineAbility/csv?build={BUILD}",
        "-- SkillLine, SpellName, and SpellEffect: same source and build.",
        "-- {orange, yellow, green, grey}; green = floor((yellow + grey) / 2).",
        "-- All bundled thresholds use this Forever build; contradictory ranges are unavailable at runtime.",
        f"-- {len(emitted)} unique recipe spell IDs; a shared recipe counts in each profession below.",
    ]
    lines.extend("-- " + line for line in coverage)
    lines.extend(["---@type string, SkillUpNamespace", "local _, ns = ...", "ns.Thresholds = {"])
    for spell, thresholds in sorted(emitted.items()):
        name = " ".join(names.get(spell, "SpellName unavailable").split())
        values = ", ".join(map(str, thresholds))
        flag = "; inconsistent orange>yellow" if thresholds[0] > thresholds[1] else ""
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
    skills, selected, excluded = professions(skill_rows)
    names = {int(row["ID"]): row["Name_lang"] for row in name_rows}
    effects = spell_effects(effect_rows)
    emitted, coverage = generate(ability_rows, skills, selected, names, effects)
    if not emitted:
        raise ValueError("No usable recipes; leaving existing generated output untouched")
    for sid, name in sorted(excluded.items()):
        print(f"Excluded test skill line: {name} ({sid})")
    missing = [str(sid) for sid in sorted(REQUIRED_SKILLS) if sid not in skills]
    print("Missing required skill lines: " + (", ".join(missing) or "none"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(render(emitted, coverage, names), encoding="utf-8")
    print(f"Wrote {len(emitted)} unique recipe spell IDs to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        sys.exit(f"error: {error}")
