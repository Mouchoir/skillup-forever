#!/usr/bin/env python3
"""Generate what neither QuestieDB nor AtlasLoot holds about where recipes come from, for the pinned Forever
client (stdlib only): a scroll's named drops and their chances, the scrolls that are world drops, which NPC
trains a profession and how far, and which reagents a gathering skill yields. Who sells what, the quests, and
every NPC's name and place are read in game from the player's QuestieDB and AtlasLoot."""

import argparse
import re
import sys
import urllib.error
from collections import defaultdict

from gen_recipes import lua_string, threshold_ids
from gen_thresholds import BUILD, ROOT, db2
from gen_trainer import (
    CLASSICDB_COMMIT,
    TEACH_BUILD,
    classicdb,
    dump_tables,
    spell_maps,
    teach_effects,
    trainable_rows,
)

OUTPUT = ROOT / "Data" / "Sources.lua"
RECIPE_DATA = ROOT / "Data" / "Recipes.lua"
REAGENT = re.compile(r"itemID = (\d+), quantity")
# Lock rows of type LOCK_KEY_SKILL name the gathering skill: 2 Herbalism, 3 Mining.
LOCK_KEY_SKILL = "2"
LOCK_SKILLS = {"2": 182, "3": 186}
SKINNING = 393
CHEST = "3"  # gameobject type; data0 is its lock, data1 its loot
# Below this, a gathered item is a lucky find (gems in veins), not something to plan on.
GATHER_CHANCE = 10
# A group's explicit chances may not sum past 100; the server allows this much rounding before it objects.
GROUP_CHANCE = 101
RECIPE_CLASS = "9"
DROPS_KEPT = 3
TABLES = (
    "item_template",
    "creature_loot_template",
    "reference_loot_template",
    "gameobject_template",
    "gameobject_loot_template",
    "skinning_loot_template",
    "npc_trainer",
)
# A scroll this many creatures drop is a world drop, not worth naming three of them. Measured:
# 211 scrolls drop from under 25 creatures (bosses, a dungeon's trash), world drops from 325-780.
WORLD_DROP = 100


def reagent_items():
    items = {int(m[1]) for m in REAGENT.finditer(RECIPE_DATA.read_text(encoding="utf-8"))}
    if not items:
        raise ValueError("No reagents in Data/Recipes.lua; run gen_recipes.py first")
    return items


def lock_requirements(locks):
    """[lock] = (gathering skill line, required skill), from the client's Lock DB2."""
    requirements = {}
    for row in locks:
        for i in range(8):
            if row[f"Type_{i}"] == LOCK_KEY_SKILL and row[f"_Index_{i}"] in LOCK_SKILLS:
                rank = int(row[f"Skill_{i}"])
                if rank < 0:
                    raise ValueError(f"Lock {row['ID']}: negative required skill {rank}")
                requirements[int(row["ID"])] = (LOCK_SKILLS[row[f"_Index_{i}"]], rank)
    return requirements


def gathered(tables, locks, items):
    """[reagent] = the gathering skill line that yields it at least GATHER_CHANCE% of the time."""
    lock_skill = {lock: need[0] for lock, need in lock_requirements(locks).items()}
    references = defaultdict(list)
    for row in tables["reference_loot_template"]:
        references[int(row["entry"])].append(row)
    loot = defaultdict(list)
    for row in tables["gameobject_loot_template"]:
        loot[int(row["entry"])].append(row)
    sources = []  # (skill line, loot rows)
    for node in tables["gameobject_template"]:
        skill = node["type"] == CHEST and lock_skill.get(int(node["data0"]))
        if skill:
            sources.append((skill, loot.get(int(node["data1"]), [])))
    skinning = defaultdict(list)
    for row in tables["skinning_loot_template"]:
        skinning[int(row["entry"])].append(row)
    sources.extend((SKINNING, rows) for rows in skinning.values())
    found = defaultdict(set)
    for skill, rows in sources:
        for item, share in loot_items(rows, references):
            if item in items and share * 100 >= GATHER_CHANCE:
                found[item].add(skill)
    ambiguous = sorted(item for item, skills in found.items() if len(skills) > 1)
    if ambiguous:
        raise ValueError(f"Reagents gathered by several skills: {ambiguous}")
    return {item: skills.pop() for item, skills in found.items()}


def node_skills(tables, locks):
    """[enUS node name] = (gathering skill line, required skill): what a herb or ore node asks, by the name its
    tooltip shows. classic-db ties a node to its lock (`data0`), the client's Lock DB2 gives that lock's skill
    and rank (#122). A name two nodes share with different requirements is left out: the tooltip can't tell
    them apart; the second value lists those names, for the run's output."""
    lock_rank = lock_requirements(locks)
    found = defaultdict(set)
    for node in tables["gameobject_template"]:
        need = node["type"] == CHEST and lock_rank.get(int(node["data0"]))
        # A lock asking no skill (quest plants, bushes) gives no skill-up to colour.
        if need and need[1] > 0 and node["name"]:
            found[node["name"]].add(need)
    shared = sorted(name for name, needs in found.items() if len(needs) > 1)
    return {name: needs.pop() for name, needs in found.items() if len(needs) == 1}, shared


def trainer_caps(trainer, teaches, rank_of):
    """[skill line][npc] = the highest rank cap that trainer teaches."""
    caps = defaultdict(dict)
    for entry, spell, _, skill, _, _ in trainable_rows(trainer):
        for taught in teaches.get(spell, ()):
            line_cap = rank_of.get(taught)
            if line_cap and line_cap[0] == skill:
                caps[skill][entry] = max(caps[skill].get(entry, 0), line_cap[1])
    if not caps:
        raise ValueError("No profession trainers resolved; leaving existing output untouched")
    return caps


def loot_chances(rows, group=0):
    """(row, chance %) per row one roll of the loot can give a player without its quest: all of it, or
    only the items of `group`. An item outside a group (group 0) and every reference rolls on its own, and the
    server drops a 0 there as it loads: it never rolls. The items sharing a group give one of them: 0 is an
    equal share of what the group's explicit chances leave."""
    groups = defaultdict(list)
    for row in rows:
        chance, own = float(row["ChanceOrQuestChance"]), int(row["groupid"])
        if own > 0 and int(row["mincountOrRef"]) > 0:
            groups[own].append((row, chance))
        elif group == 0 and chance > 0:
            yield row, chance
    for own, members in groups.items():
        if group not in (0, own):
            continue
        # A quest row (negative chance) takes its part of the group's roll like any other.
        explicit = sum(abs(chance) for _, chance in members)
        if explicit > GROUP_CHANCE:
            raise ValueError(f"Loot {members[0][0]['entry']} group {own} has chances summing to {explicit:g}%")
        shared = sum(chance == 0 for _, chance in members)
        for row, chance in members:
            if chance >= 0:
                yield row, chance or max(0.0, 100 - explicit) / shared


def loot_items(rows, refs, group=0, seen=frozenset()):
    """(item, chance 0-1) per item the loot rows can give, through referenced loot at its chance of rolling.
    A reference's group is the one group of the referenced loot it rolls (0 for all of it), and it rolls
    that maxcount times over: the chance is of the item turning up at least once."""
    for row, chance in loot_chances(rows, group):
        ref, share = -int(row["mincountOrRef"]), chance / 100
        if ref < 0:
            yield int(row["item"]), share
        elif ref not in seen:
            times = int(row["maxcount"])
            for item, inside in loot_items(refs[ref], refs, int(row["groupid"]), seen | {ref}):
                yield item, share * (1 - (1 - inside) ** times)


def scroll_drops(tables, scrolls):
    """Per scroll, {creature: chance %} through direct and referenced loot; and the world drops, scrolls
    that too many creatures drop to name or that only chests and containers hold."""
    refs, loot = defaultdict(list), defaultdict(list)
    for row in tables["reference_loot_template"]:
        refs[int(row["entry"])].append(row)
    for row in tables["creature_loot_template"]:
        loot[int(row["entry"])].append(row)

    def reached(rows, seen):
        for row in rows:
            ref = -int(row["mincountOrRef"])
            if ref > 0 and ref not in seen:
                seen.add(ref)
                reached(refs[ref], seen)
        return seen

    drops = defaultdict(dict)
    for entry, rows in loot.items():
        for item, share in loot_items(rows, refs):
            if item in scrolls and share > 0:
                drops[item][entry] = max(drops[item].get(entry, 0), share * 100)
    world = {item for item, by in drops.items() if len(by) > WORLD_DROP}
    creature_refs = set()
    for rows in loot.values():
        reached(rows, creature_refs)
    for ref in refs.keys() - creature_refs:
        world |= {int(row["item"]) for row in refs[ref] if int(row["item"]) in scrolls} - drops.keys()
    return {item: by for item, by in drops.items() if item not in world}, world


def scroll_items(ids, rows, teaches):
    """The recipe items that teach one of the recipes `ids`, at once or through a spell that teaches it."""
    scrolls = set()
    for item in rows:
        if item["class"] != RECIPE_CLASS:
            continue
        spells = {int(item[f"spellid_{k}"]) for k in range(1, 6)}
        if any(taught in ids for spell in spells for taught in teaches.get(spell, set()) | {spell}):
            scrolls.add(int(item["entry"]))
    if not scrolls:
        raise ValueError("No recipe items resolved; leaving existing output untouched")
    return scrolls


def generate(ids, tables, effect_rows, locks):
    teaches, rank_of = spell_maps(effect_rows)
    drops, world = scroll_drops(tables, scroll_items(ids, tables["item_template"], teaches))
    return {
        "drops": {item: sorted(by.items(), key=lambda kv: (-kv[1], kv[0]))[:DROPS_KEPT] for item, by in drops.items()},
        "world": sorted(world),
        "trainers": {
            skill: sorted(caps.items()) for skill, caps in trainer_caps(tables["npc_trainer"], teaches, rank_of).items()
        },
        "gathered": gathered(tables, locks, reagent_items()),
        **dict(zip(("nodes", "shared_nodes"), node_skills(tables, locks), strict=True)),
    }


def render(data):
    lines = [
        "-- Generated by tools/gen_sources.py — do not edit.",
        f"-- Source: CMaNGOS classic-db {CLASSICDB_COMMIT} (GPL-3.0): item_template, creature_loot_template,",
        "-- reference_loot_template, npc_trainer, gameobject(_loot)_template, skinning_loot_template. Which item",
        f"-- is a recipe scroll and which spell is a rank: wago.tools SpellEffect, wow_classic_era {TEACH_BUILD};",
        f"-- gathering locks: wago.tools Lock, wow_classic_beta {BUILD}.",
        "-- Neither QuestieDB nor AtlasLoot holds these; all else about a recipe's sources is read from them.",
        f"-- scrolls with named drops={len(data['drops'])}, world drops={len(data['world'])}.",
        "---@type string, SkillUpNamespace",
        "local _, ns = ...",
        "",
        "-- [scroll item] = { { npc, chance % } }: its likeliest named drops",
        "-- stylua: ignore",
        "ns.ScrollDrops = {",
    ]
    for item, rows in sorted(data["drops"].items()):
        lines.append(f"\t[{item}] = {{ " + ", ".join(f"{{ {e}, {round(c, 2):g} }}" for e, c in rows) + " },")
    lines += ["}", "", "-- [scroll item] = true: a world drop, too widely dropped to name", "-- stylua: ignore"]
    lines.append("ns.WorldDrops = {")
    lines += [f"\t[{item}] = true," for item in data["world"]]
    lines += [
        "}",
        "",
        "-- [skill line] = { { trainer npc, highest cap it teaches } }",
        "-- stylua: ignore",
        "ns.ProfessionTrainers = {",
    ]
    for skill, rows in sorted(data["trainers"].items()):
        lines.append(f"\t[{skill}] = {{ " + ", ".join(f"{{ {e}, {c} }}" for e, c in rows) + " },")
    lines += [
        "}",
        "",
        f"-- [reagent item] = gathering skill line that yields it ({GATHER_CHANCE}%+ of the time)",
        "-- stylua: ignore",
        "ns.GatheredBy = {",
    ]
    lines += [f"\t[{item}] = {skill}," for item, skill in sorted(data["gathered"].items())]
    lines += [
        "}",
        "",
        "-- [node name, enUS] = { gathering skill line, required skill }: classic-db's lock for the node, the",
        "-- client's Lock DB2 for what that lock asks. A name shared by nodes asking different skills is left out.",
        "-- stylua: ignore",
        "ns.NodeSkills = {",
    ]
    lines += [
        f"\t[{lua_string(name)}] = {{ {skill}, {rank} }}," for name, (skill, rank) in sorted(data["nodes"].items())
    ]
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--refresh", action="store_true", help="redownload the pinned sources")
    mode.add_argument("--offline", action="store_true", help="use cached sources only")
    args = parser.parse_args()
    options = {"refresh": args.refresh, "offline": args.offline}
    data = generate(
        threshold_ids(),
        dump_tables(classicdb(**options), TABLES),
        teach_effects(**options),
        db2("Lock", ["ID"] + [f"{c}_{i}" for c in ("Type", "_Index", "Skill") for i in range(8)], **options),
    )
    OUTPUT.write_text(render(data), encoding="utf-8")
    print(
        f"Wrote {OUTPUT.relative_to(ROOT)}: {len(data['drops'])} scrolls with named drops, "
        f"{len(data['world'])} world drops, {sum(map(len, data['trainers'].values()))} trainers, "
        f"{len(data['gathered'])} gathered reagents, {len(data['nodes'])} gathering nodes "
        f"(left out, shared by nodes asking different skills: {data['shared_nodes']})"
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
