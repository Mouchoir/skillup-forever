"""Reject source decoding errors instead of changing generated names."""

import gzip
import tempfile
import unittest
from pathlib import Path

from gen_trainer import dump_tables, generate


class DumpEncodingTests(unittest.TestCase):
    def test_invalid_utf8_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dump.sql.gz"
            with gzip.open(path, "wb") as stream:
                stream.write(b"CREATE TABLE `npc` (\n  `Name` text\n);\nINSERT INTO `npc` VALUES ('D\xfforf');\n")
            with self.assertRaises(UnicodeDecodeError):
                dump_tables(path, {"npc"})

    def test_valid_utf8_name_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dump.sql.gz"
            with gzip.open(path, "wt", encoding="utf-8") as stream:
                stream.write("CREATE TABLE `npc` (\n  `Name` text\n);\nINSERT INTO `npc` VALUES ('Dörf');\n")
            self.assertEqual(dump_tables(path, {"npc"}), {"npc": [{"Name": "Dörf"}]})


class RequirementTests(unittest.TestCase):
    def trainer(self, spell, required):
        return {
            "entry": "1",
            "spell": str(spell),
            "spellcost": "900",
            "reqskill": "164",
            "reqskillvalue": str(required),
            "reqlevel": "0",
            "ReqAbility1": None,
            "condition_id": "0",
        }

    # Issue #107: classic-db's 125 for Heavy Sharpening Stone is above Forever's grey 115 for it.
    def test_requirement_moves_with_the_recipe_range(self):
        effects = [
            {"SpellID": str(teach), "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": str(taught)}
            for teach, taught in ((10, 2674), (11, 9985), (12, 3), (13, 99))
        ]
        effects.append(
            {"SpellID": "99", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "1", "EffectMiscValue_0": "164"}
        )
        trainer = [self.trainer(10, 125), self.trainer(11, 125), self.trainer(12, 10), self.trainer(13, 50)]
        fees, _, _, inferred = generate({2674, 9985, 3}, trainer, effects, {2674: -25, 3: -25})
        self.assertEqual(fees[2674], (900, 100))
        self.assertEqual(fees[9985], (900, 125))
        self.assertEqual(fees[3], (900, 1))
        # Issue #124: a moved requirement keeps classic-db's, so a trainer visit can confirm or correct it.
        self.assertEqual(inferred, {2674: 125, 3: 10})

    def test_unmoved_zero_requirement_is_not_inferred(self):
        effects = [
            {"SpellID": str(teach), "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": str(taught)}
            for teach, taught in ((10, 5), (13, 99))
        ]
        effects.append(
            {"SpellID": "99", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "1", "EffectMiscValue_0": "164"}
        )
        trainer = [self.trainer(10, 0), self.trainer(13, 50)]
        fees, _, _, inferred = generate({5}, trainer, effects)
        self.assertEqual(fees[5], (900, 1))
        self.assertEqual(inferred, {})

    def test_clamped_requirements_keep_the_strictest(self):
        effects = [
            {"SpellID": str(teach), "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": str(taught)}
            for teach, taught in ((10, 5), (11, 5), (13, 99))
        ]
        effects.append(
            {"SpellID": "99", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "1", "EffectMiscValue_0": "164"}
        )
        for order in ((20, 5), (5, 20)):
            trainer = [self.trainer(10, order[0]), self.trainer(11, order[1]), self.trainer(13, 50)]
            _, _, _, inferred = generate({5}, trainer, effects, {5: -25})
            self.assertEqual(inferred, {5: 20})
