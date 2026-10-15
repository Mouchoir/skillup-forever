"""Check which gathered reagents gen_sources keeps, on hand-built loot tables."""

import unittest
from unittest.mock import patch

import gen_sources
from gen_sources import CHEST, gathered, node_skills

MINE, VEIN, LOOT = "7", "70", "700"


def loot(entry, item, chance, ref=0, group=0, times=1):
    return {
        "entry": entry,
        "item": str(item),
        "ChanceOrQuestChance": str(chance),
        "groupid": str(group),
        "mincountOrRef": str(-ref if ref else 1),
        "maxcount": str(times),
    }


def lock(lock_id=MINE, rank=125):
    row = {"ID": lock_id}
    for i in range(8):
        row[f"Type_{i}"], row[f"_Index_{i}"], row[f"Skill_{i}"] = "0", "0", "0"
    row["Type_0"], row["_Index_0"], row["Skill_0"] = "2", "3", str(rank)  # LOCK_KEY_SKILL, Mining
    return row


class NodeSkillTests(unittest.TestCase):
    # Issue #122: a node's required skill is its classic-db lock's in the client's Lock DB2, by its name.
    def nodes(self, *nodes):
        rows = [{"type": CHEST, "data0": lock_id, "name": name} for name, lock_id in nodes]
        locks = [lock(), lock("8", 175), lock("9", 0)]
        return node_skills({"gameobject_template": rows}, locks)

    def test_a_node_asks_its_locks_skill(self):
        self.assertEqual(self.nodes(("Iron Deposit", MINE)), ({"Iron Deposit": (186, 125)}, []))

    def test_a_lock_asking_no_skill_is_left_out(self):
        self.assertEqual(self.nodes(("Doom Weed", "9")), ({}, []))

    def test_a_name_asking_two_skills_is_left_out_and_reported(self):
        both = self.nodes(("Iron Deposit", MINE), ("Iron Deposit", "8"), ("Mithril Deposit", "8"))
        self.assertEqual(both, ({"Mithril Deposit": (186, 175)}, ["Iron Deposit"]))


class GatheredTests(unittest.TestCase):
    def found(self, node_loot, references):
        tables = {
            "gameobject_template": [{"type": CHEST, "data0": MINE, "data1": LOOT, "entry": VEIN}],
            "gameobject_loot_template": node_loot,
            "reference_loot_template": references,
            "skinning_loot_template": [],
        }
        return gathered(tables, [lock()], {1, 2, 3, 4})

    def test_references_scale_and_nest(self):
        found = self.found(
            [loot(LOOT, 0, 100, ref=10), loot(LOOT, 0, 50, ref=20)],
            [
                loot("10", 1, 5),  # a 5% find inside a sure reference
                loot("10", 0, 100, ref=11),
                loot("11", 2, 100),  # a sure drop one reference deeper
                loot("20", 3, 15),  # 15% of a 50% roll: 7.5%
            ],
        )
        self.assertEqual(found, {2: 186})

    def test_zero_chance_is_a_share_only_inside_a_group(self):
        found = self.found(
            [
                loot(LOOT, 1, 0),  # no group to share: the server never rolls it
                loot(LOOT, 2, 80, group=1),
                loot(LOOT, 3, 0, group=1),  # the 20% the group's other chance leaves
            ],
            [],
        )
        self.assertEqual(found, {2: 186, 3: 186})

    def test_reference_is_no_member_of_its_group(self):
        refs = {10: [loot("10", 3, 100, group=1), loot("10", 4, 100, group=2), loot("10", 5, 100)]}
        rows = [
            loot(LOOT, 1, 60, group=1),
            loot(LOOT, 2, 0, group=1),  # the 40% the other item leaves: the reference takes none of it
            loot(LOOT, 0, 100, ref=10, group=1),
            loot(LOOT, 0, 30, ref=10, group=2),
        ]
        # Each reference rolls on its own, and only the group of the referenced loot that it names.
        self.assertEqual(sorted(gen_sources.loot_items(rows, refs)), [(1, 0.6), (2, 0.4), (3, 1.0), (4, 0.3)])

    def test_overfull_group_is_an_error(self):
        rows = [loot(LOOT, 1, 60, group=1), loot(LOOT, 2, 60, group=1)]
        with self.assertRaisesRegex(ValueError, "Loot 700 group 1 has chances summing to 120%"):
            list(gen_sources.loot_chances(rows))

    def test_reference_rolls_its_loot_maxcount_times(self):
        refs = {10: [loot("10", 1, 50)]}

        def chance(times):
            return dict(gen_sources.loot_items([loot(LOOT, 0, 40, ref=10, times=times)], refs))[1]

        self.assertAlmostEqual(chance(1), 0.2)
        self.assertAlmostEqual(chance(2), 0.3)  # 40% of at least one of two 50% rolls
        self.assertEqual(chance(0), 0)

    def test_generate_keeps_only_what_no_provider_holds(self):
        def scroll(entry, spell):
            row = {"class": "9", "entry": str(entry)}
            row.update({f"spellid_{k}": "0" for k in range(1, 6)})
            row["spellid_1"] = str(spell)
            return row

        tables = {name: [] for name in gen_sources.TABLES}
        # 500 teaches recipe 700 through spell 600; 501 teaches a recipe outside the set.
        tables["item_template"] = [scroll(500, 600), scroll(501, 601), {"class": "7", "entry": "502"}]
        tables["creature_loot_template"] = [
            loot("900", 500, 5),
            loot("901", 500, 20),
            loot("902", 500, 1),
            loot("903", 500, 0.5),
            loot("900", 501, 50),
        ]
        with (
            patch.object(gen_sources, "spell_maps", return_value=({600: {700}}, {})),
            patch.object(gen_sources, "reagent_items", return_value=set()),
            patch.object(gen_sources, "trainer_caps", return_value={197: {31: 150, 30: 300}}),
        ):
            data = gen_sources.generate({700}, tables, [], [])
        # The three likeliest, likeliest first, whether or not the creature has a spawn or a side.
        self.assertEqual(data["drops"], {500: [(901, 20.0), (900, 5.0), (902, 1.0)]})
        self.assertEqual(data["world"], [])
        self.assertEqual(data["trainers"], {197: [(30, 300), (31, 150)]})
        rendered = gen_sources.render(data)
        self.assertIn("\t[500] = { { 901, 20 }, { 900, 5 }, { 902, 1 } },", rendered)
        self.assertIn("\t[197] = { { 30, 300 }, { 31, 150 } },", rendered)
        for moved in ("RecipeSources", "SourceNPCs", "SourceQuests", "ReagentVendors", "InstanceNames"):
            self.assertNotIn(moved, rendered)

    def test_no_scroll_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "No recipe items resolved"):
            gen_sources.scroll_items({700}, [{"class": "7", "entry": "502"}], {})


if __name__ == "__main__":
    unittest.main()
