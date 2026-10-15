#!/usr/bin/env python3
"""Generate bundled profession trainer fees and rank training for the pinned Forever client (stdlib only)."""

import argparse
import gzip
import sys
import urllib.error
from collections import Counter, defaultdict

from forever_tools import wago
from gen_recipes import put_unique, threshold_ids
from gen_thresholds import (
    BUILD,
    CACHE,
    LEARN_SPELL,
    ROOT,
    SKILL,
    TEACH_BUILD,
    USER_AGENT,
    ability_values,
    db2,
    shifts,
)

OUTPUT = ROOT / "Data" / "Trainer.lua"
CLASSICDB_COMMIT = "22b51464f1625f6ef6275771de1f5466c6f5d19e"
CLASSICDB_URL = (
    f"https://raw.githubusercontent.com/cmangos/classic-db/{CLASSICDB_COMMIT}/Full_DB/ClassicDB_1_12_1_z2815.sql.gz"
)
CLASSICDB_CACHE = CACHE / f"classicdb-{CLASSICDB_COMMIT[:7]}.sql.gz"
PROFESSION_SKILLS = {129, 164, 165, 171, 182, 185, 186, 197, 202, 333, 356, 393}
RANK_SKILL = 75
# Forever's client leaves out the trainers' teaching spells; Classic Era (TEACH_BUILD, pinned in
# gen_thresholds.py) keeps them, with the same recipe spell IDs.


def classicdb(refresh=False, offline=False):
    """The pinned classic-db dump's path, downloaded first if it isn't cached."""
    wago.fetch(
        CLASSICDB_URL,
        CLASSICDB_CACHE,
        user_agent=USER_AGENT,
        refresh=refresh,
        offline=offline,
        timeout=120,
        validate=gzip.decompress,
    )
    return CLASSICDB_CACHE


def parse_rows(line):
    """The value tuples of one extended INSERT, as lists of strings (None for NULL)."""
    rows, i, n = [], line.index("VALUES") + 6, len(line)
    while i < n:
        if line[i] == ";":
            break
        if line[i] != "(":
            i += 1
            continue
        row, value, i = [], None, i + 1
        while True:
            c = line[i]
            if c == "'":
                j, chars = i + 1, []
                while line[j] != "'" or line[j + 1] == "'":
                    if line[j] == "\\" or line[j] == "'":
                        j += 1
                    chars.append(line[j])
                    j += 1
                value, i = "".join(chars), j + 1
            elif c in ",)":
                row.append(value)
                value, i = None, i + 1
                if c == ")":
                    break
            else:
                j = i
                while line[j] not in ",)":
                    j += 1
                value, i = (None if line[i:j] == "NULL" else line[i:j]), j
        rows.append(row)
    return rows


def dump_tables(path, tables):
    """Each named table's rows, as {column: value} by the dump's own CREATE TABLE."""
    columns, rows, current = {}, defaultdict(list), None
    with gzip.open(path, "rt", encoding="utf-8") as dump:
        for line in dump:
            if line.startswith("CREATE TABLE"):
                name = line.split("`")[1]
                current = name if name in tables else None
                if current:
                    columns[current] = []
            elif current and line.startswith("  `"):
                columns[current].append(line.split("`")[1])
            elif line.startswith("INSERT INTO") and line.split("`")[1] in tables:
                rows[line.split("`")[1]].extend(parse_rows(line))
    missing = set(tables) - columns.keys()
    if missing:
        raise ValueError(f"classic-db dump lacks tables {sorted(missing)}")
    return {table: [dict(zip(columns[table], row, strict=True)) for row in rows[table]] for table in tables}


def teach_effects(refresh=False, offline=False):
    columns = ("SpellID", "DifficultyID", "Effect", "EffectTriggerSpell", "EffectBasePoints", "EffectMiscValue_0")
    return db2("SpellEffect", columns, refresh, offline, build=TEACH_BUILD)


def spell_maps(effect_rows):
    """Teaching spell -> taught spells, and rank spell -> (skill line, new cap)."""
    teaches = defaultdict(set)
    rank_of = {}
    for row in effect_rows:
        if int(row["DifficultyID"]) != 0:
            continue
        if int(row["Effect"]) == LEARN_SPELL:
            teaches[int(row["SpellID"])].add(int(row["EffectTriggerSpell"]))
        elif int(row["Effect"]) == SKILL:
            cap = (int(row["EffectBasePoints"]) + 1) * RANK_SKILL
            put_unique(rank_of, int(row["SpellID"]), (int(row["EffectMiscValue_0"]), cap), "rank effect")
    return teaches, rank_of


def trainable_rows(trainer):
    """(entry, spell, cost, skill, required, level) of each profession npc_trainer row.

    Specialisation-gated rows (condition, required ability) can't be assumed
    trainable; a recipe offered without a gate anywhere is.
    """
    for row in trainer:
        skill = int(row["reqskill"])
        if skill in PROFESSION_SKILLS and row["ReqAbility1"] is None and row["condition_id"] == "0":
            yield (
                int(row["entry"]),
                int(row["spell"]),
                int(row["spellcost"]),
                skill,
                int(row["reqskillvalue"]),
                int(row["reqlevel"]),
            )


def generate(ids, trainer, effect_rows, moved=None):
    """moved: [recipe] = how far Forever moved its yellow and grey from Classic Era's (gen_thresholds.shifts).

    classic-db's required skill is Classic's. Where Forever moved a recipe's range, it moved the skill its
    pattern asks for by as much (all but a few of the patterns both clients have), so the trainer's moves too.
    """
    moved = moved or {}
    teaches, rank_of = spell_maps(effect_rows)
    fees = defaultdict(Counter)
    classic = {}
    ranks = defaultdict(Counter)
    for _, spell, cost, skill, required, level in trainable_rows(trainer):
        for taught in teaches.get(spell, ()):
            if taught in ids:
                entry = (cost, max(required + moved.get(taught, 0), 1))
                fees[taught][entry] += 1
                # Requirements the clamp to 1 merges keep the strictest, whatever the row order.
                classic[(taught, entry)] = max(required, classic.get((taught, entry), required))
            if rank_of.get(taught, (None,))[0] == skill:
                ranks[skill][(rank_of[taught][1], cost, required, level)] += 1
    if not fees:
        raise ValueError("No trainer fees resolved; leaving existing output untouched")
    # Duplicate trainers almost always agree; take the most common (fee, skill), cheaper on a tie.
    chosen = {recipe: min(c.items(), key=lambda kv: (-kv[1], kv[0]))[0] for recipe, c in fees.items()}
    conflicts = sorted(recipe for recipe, c in fees.items() if len(c) > 1)
    # The requirements this rule moved, with classic-db's own: what a trainer visit confirms or corrects (#124).
    inferred = {
        recipe: classic[(recipe, entry)]
        for recipe, entry in chosen.items()
        if moved.get(recipe) and classic[(recipe, entry)] != entry[1]
    }
    by_cap = defaultdict(dict)
    for skill, seen in ranks.items():
        for (cap, cost, required, level), count in seen.items():
            best = by_cap[skill].get(cap)
            if best is None or (-count, cost) < (-best[1], best[0][1]):
                by_cap[skill][cap] = ((cap, cost, required, level), count)
    rank_rows = {skill: sorted(entry for entry, _ in caps.values()) for skill, caps in by_cap.items()}
    if not rank_rows:
        raise ValueError("No profession ranks resolved; leaving existing output untouched")
    return chosen, conflicts, rank_rows, inferred


def render(fees, conflicts, ranks, inferred):
    lines = [
        "-- Generated by tools/gen_trainer.py — do not edit.",
        f"-- Source: CMaNGOS classic-db {CLASSICDB_COMMIT} npc_trainer (GPL-3.0), base fees before",
        "-- reputation discounts; teaching spell -> recipe via wago.tools SpellEffect (LEARN_SPELL),",
        f"-- wow_classic_era {TEACH_BUILD}; recipes limited to wow_classic_beta {BUILD} thresholds.",
        "-- Specialisation-gated rows are left out. Fees seen at a trainer win.",
        f"-- A required skill moves as far as Forever {BUILD} moved the recipe's yellow and grey from",
        f"-- Classic Era {TEACH_BUILD}'s (SkillLineAbility).",
        f"-- recipes={len(fees)}; conflicts resolved to the most common: {conflicts}.",
        "---@type string, SkillUpNamespace",
        "local _, ns = ...",
        "-- stylua: ignore",
        "-- [recipeID] = { fee in copper, required base skill }",
        "ns.TrainerFees = {",
    ]
    lines.extend(f"\t[{recipe}] = {{ {fee}, {skill} }}," for recipe, (fee, skill) in sorted(fees.items()))
    lines.extend(
        [
            "}",
            "",
            "-- [skill line] = rank trainings above Apprentice: { cap, fee, required base skill, level }",
            "-- stylua: ignore",
            "ns.TrainerRanks = {",
        ]
    )
    for skill, rows in sorted(ranks.items()):
        entries = ", ".join(
            f"{{ {cap}, {cost}, {required}, {level} }}" for cap, cost, required, level in rows if cap > RANK_SKILL
        )
        lines.append(f"\t[{skill}] = {{ {entries} }},")
    lines.append("}")
    lines.extend(
        [
            "",
            "-- [recipeID] = classic-db's required skill, for each requirement above that was moved from it",
            "-- stylua: ignore",
            "ns.TrainerInferred = {",
        ]
    )
    lines.extend(f"\t[{recipe}] = {required}," for recipe, required in sorted(inferred.items()))
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    options = {"refresh": args.refresh, "offline": args.offline}
    fees, conflicts, ranks, inferred = generate(
        threshold_ids(),
        dump_tables(classicdb(**options), ("npc_trainer",))["npc_trainer"],
        teach_effects(**options),
        shifts(
            db2(
                "SkillLineAbility",
                ("Spell", "MinSkillLineRank", "TrivialSkillLineRankHigh", "TrivialSkillLineRankLow"),
                **options,
            ),
            ability_values(
                db2(
                    "SkillLineAbility",
                    ("Spell", "MinSkillLineRank", "TrivialSkillLineRankHigh", "TrivialSkillLineRankLow"),
                    build=TEACH_BUILD,
                    **options,
                )
            ),
        ),
    )
    content = render(fees, conflicts, ranks, inferred)
    OUTPUT.write_text(content, encoding="utf-8")
    print(
        f"Wrote {OUTPUT.relative_to(ROOT)}: {len(fees)} recipes, {len(inferred)} requirements moved, "
        f"conflicts {conflicts}"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
