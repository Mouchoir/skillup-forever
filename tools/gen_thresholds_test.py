import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gen_thresholds


class Db2Test(unittest.TestCase):
    def rows(self, text, columns=("ID", "Value")):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            (cache / f"T-{gen_thresholds.BUILD}.csv").write_text(text, encoding="utf-8")
            with mock.patch.object(gen_thresholds, "CACHE", cache):
                return gen_thresholds.db2("T", columns, offline=True)

    def test_valid_rows_keep_their_strings(self):
        self.assertEqual(self.rows("ID,Value\n1,2\n3,4\n"), [{"ID": "1", "Value": "2"}, {"ID": "3", "Value": "4"}])

    def test_rejects_duplicate_columns(self):
        with self.assertRaisesRegex(ValueError, "duplicate columns"):
            self.rows("ID,Value,Value\n1,2,3\n")

    def test_rejects_duplicate_ids_and_short_rows(self):
        with self.assertRaisesRegex(ValueError, "duplicate ID"):
            self.rows("ID,Value\n1,2\n1,3\n")
        with self.assertRaisesRegex(ValueError, "malformed CSV row"):
            self.rows("ID,Value\n1\n")

    def test_rejects_missing_columns_and_empty_exports(self):
        with self.assertRaisesRegex(ValueError, "missing required columns"):
            self.rows("ID\n1\n")
        with self.assertRaisesRegex(ValueError, "empty export"):
            self.rows("ID,Value\n")

    def test_invalid_refresh_preserves_cached_source(self):
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)
            path = cache / f"T-{gen_thresholds.BUILD}.csv"
            original = b"ID,Value\n1,2\n"
            path.write_bytes(original)
            with (
                mock.patch.object(gen_thresholds, "CACHE", cache),
                mock.patch.object(gen_thresholds.wago, "read_source", return_value=(b"ID,Value,Value\n1,2,3\n", True)),
                self.assertRaisesRegex(ValueError, "duplicate columns"),
            ):
                gen_thresholds.db2("T", ("ID", "Value"), refresh=True)
            self.assertEqual(path.read_bytes(), original)


class ThresholdSourceTest(unittest.TestCase):
    def test_forever_requirement_is_used_unchanged(self):
        row = {
            "SkillLine": "164",
            "Spell": "9985",
            "MinSkillLineRank": "1",
            "TrivialSkillLineRankLow": "155",
            "TrivialSkillLineRankHigh": "185",
        }
        emitted, _, _ = gen_thresholds.generate(
            [row],
            {},
            {164},
            {9985: "Bronze Warhammer"},
            {9985: {24}},
        )
        self.assertEqual(emitted[9985], (1, 155, 170, 185))

    def row(self, spell, orange, yellow, grey, skill_line="164"):
        return {
            "SkillLine": skill_line,
            "Spell": str(spell),
            "MinSkillLineRank": str(orange),
            "TrivialSkillLineRankLow": str(yellow),
            "TrivialSkillLineRankHigh": str(grey),
        }

    def emit(self, rows, classic=(), scrolls=None):
        classic = gen_thresholds.ability_values([self.row(*values) for values in classic])
        spells = {int(row["Spell"]) for row in rows}
        emitted, _, sources = gen_thresholds.generate(
            rows, {}, {164}, {}, {spell: {24} for spell in spells}, classic, scrolls or {}
        )
        return emitted, sources

    # Issue #107: Forever moved these ranges 25 points down and left Classic's minimum on them.
    def test_stale_minimum_moves_with_its_range(self):
        emitted, sources = self.emit(
            [self.row(2666, 80, 85, 125), self.row(2672, 120, 125, 155)],
            classic=[(2666, 80, 110, 150), (2672, 120, 150, 180)],
        )
        self.assertEqual(emitted[2666], (55, 85, 105, 125))
        self.assertEqual(emitted[2672], (95, 125, 140, 155))
        self.assertEqual(sources[2666], "client orange 80: shifted")

    def test_minimum_above_yellow_is_never_emitted(self):
        emitted, _ = self.emit(
            [self.row(2674, 125, 100, 115), self.row(2665, 75, 40, 55)],
            classic=[(2674, 125, 125, 140), (2665, 75, 65, 80)],
        )
        self.assertEqual(emitted[2674], (100, 100, 107, 115))
        # Moved as far, 50 is still above yellow: no number the sources agree on, so the placeholder.
        self.assertEqual(emitted[2665], (1, 40, 47, 55))

    def test_pattern_requirement_replaces_placeholder_and_stale_minimum(self):
        emitted, sources = self.emit(
            [self.row(2667, 90, 95, 135), self.row(2158, 1, 95, 125), self.row(22757, 1, 275, 295)],
            classic=[(2667, 90, 120, 160)],
            scrolls={2667: (2881, 55), 2158: (5083, 65), 22757: (18260, 300)},
        )
        self.assertEqual(emitted[2667], (55, 95, 115, 135))
        self.assertEqual(sources[2667], "client orange 90: scroll")
        self.assertEqual(emitted[2158], (65, 95, 110, 125))
        # A pattern asking more than yellow cannot start the orange range.
        self.assertEqual(emitted[22757], (1, 275, 285, 295))

    def test_deprecated_pattern_teaches_nobody(self):
        # Enchant Cloak - Minor Protection (7771): Forever's only item for it is the deprecated
        # "Formula: Imbue Cloak - Protection" (6345, asks 90), while a trainer teaches it at 70.
        items = [
            {"ID": "6345", "RequiredSkill": "333", "RequiredSkillRank": "90", "Flags_0": "80"},
            {"ID": "4295", "RequiredSkill": "165", "RequiredSkillRank": "125", "Flags_0": "16"},
            {"ID": "5974", "RequiredSkill": "165", "RequiredSkillRank": "160", "Flags_0": "64"},
        ]
        effects = [{"ID": "1", "SpellID": "7771"}, {"ID": "2", "SpellID": "7153"}, {"ID": "3", "SpellID": "7153"}]
        links = [
            {"ItemID": "6345", "ItemEffectID": "1"},
            {"ItemID": "4295", "ItemEffectID": "2"},
            {"ItemID": "5974", "ItemEffectID": "3"},
        ]
        scrolls = gen_thresholds.scroll_requirements({7771, 7153}, items, effects, links)
        self.assertEqual(scrolls, {7153: (5974, 160)})
        emitted, _ = self.emit([self.row(7771, 1, 110, 150)], classic=[(7771, 1, 110, 150)], scrolls=scrolls)
        self.assertEqual(emitted[7771], (1, 110, 130, 150))

    def test_real_client_minimum_is_kept(self):
        emitted, sources = self.emit(
            [self.row(7, 40, 50, 100), self.row(8, 50, 70, 100)],
            classic=[(7, 40, 50, 100), (8, 60, 90, 120)],
            scrolls={7: (1, 30)},
        )
        self.assertEqual(emitted[7], (40, 50, 75, 100))
        self.assertEqual(emitted[8], (50, 70, 85, 100))
        self.assertEqual(sources, {})

    def test_shifts_only_ranges_that_moved_together(self):
        classic = gen_thresholds.ability_values(
            [self.row(1, 1, 110, 150), self.row(2, 1, 50, 100), self.row(3, 1, 50, 100)]
        )
        forever = [self.row(1, 1, 85, 125), self.row(2, 1, 50, 100), self.row(3, 1, 40, 95)]
        self.assertEqual(gen_thresholds.shifts(forever, classic), {1: -25})


class GeneratedThresholdsTest(unittest.TestCase):
    # Model.Get answers nil for a row that is not ordered, and the recipe shows "?".
    def test_every_bundled_row_is_ordered(self):
        content = (gen_thresholds.OUTPUT).read_text(encoding="utf-8")
        rows = re.findall(r"^\t\[(\d+)\] = \{ (\d+), (\d+), (\d+), (\d+) \},", content, re.MULTILINE)
        self.assertGreater(len(rows), 1000)
        for spell, *values in rows:
            orange, yellow, green, grey = map(int, values)
            self.assertTrue(1 <= orange <= yellow <= green < grey, f"{spell}: {values}")


if __name__ == "__main__":
    unittest.main()
