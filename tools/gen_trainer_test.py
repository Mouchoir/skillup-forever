"""Reject source decoding errors instead of changing generated names."""

import gzip
import re
import tempfile
import unittest
from pathlib import Path

from gen_trainer import ROOT, SEEN_REQUIREMENTS, dump_tables, generate, rank_quests


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

    # Issue #123: a player made Bronze Warhammer at 110 on Forever, where classic-db (unmoved) says 125.
    def test_a_requirement_players_saw_lower_comes_down(self):
        effects = [
            {"SpellID": str(teach), "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": str(taught)}
            for teach, taught in ((10, 9985), (11, 2674), (13, 99))
        ]
        effects.append(
            {"SpellID": "99", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "1", "EffectMiscValue_0": "164"}
        )
        trainer = [self.trainer(10, 125), self.trainer(11, 125), self.trainer(13, 50)]
        fees, _, _, inferred = generate({9985, 2674}, trainer, effects, {2674: -25}, {9985: 110, 2674: 105})
        self.assertEqual(fees[9985], (900, 110))
        # A lower requirement the rule already gives is never raised to what players saw.
        self.assertEqual(fees[2674], (900, 100))
        # It is still a guess: /su trainers lists it with classic-db's number for a trainer to confirm.
        self.assertEqual(inferred, {9985: 125, 2674: 125})

    # The bundled data keeps what players saw: every SEEN_REQUIREMENTS recipe at or below its value, never below 1.
    def test_bundled_requirements_players_saw_lower_hold(self):
        text = (ROOT / "Data" / "Trainer.lua").read_text(encoding="utf-8")
        for recipe, most in SEEN_REQUIREMENTS.items():
            row = re.search(rf"\n\t\[{recipe}\] = {{ \d+, (\d+) }},", text)
            self.assertIsNotNone(row, recipe)
            self.assertTrue(1 <= int(row.group(1)) <= most, recipe)

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


class RankQuestTests(unittest.TestCase):
    # Issue #121: Artisan First Aid comes from Triage (one quest a side), Artisan Cooking from Clamlette Surprise.
    EFFECTS = [
        {"SpellID": "10846", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "3", "EffectMiscValue_0": "129"},
        {"SpellID": "10847", "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": "10846"},
        {"SpellID": "18260", "DifficultyID": "0", "Effect": "118", "EffectBasePoints": "3", "EffectMiscValue_0": "185"},
        {"SpellID": "18261", "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": "18260"},
        {"SpellID": "500", "DifficultyID": "0", "Effect": "36", "EffectTriggerSpell": "501"},
    ]

    @staticmethod
    def quest(entry, spell, cast, races, skill="0", required="0", level="35"):
        return {
            "entry": str(entry),
            "RewSpell": str(spell),
            "RewSpellCast": str(cast),
            "RequiredRaces": str(races),
            "RequiredSkill": skill,
            "RequiredSkillValue": required,
            "MinLevel": level,
        }

    def test_quests_that_teach_a_rank(self):
        quests = [
            self.quest(6624, 10846, 10847, 77, "129", "225"),
            self.quest(6622, 0, 10847, 178, "129", "225"),
            self.quest(6610, 18260, 0, 255, "185", "225"),
            # A reward spell that teaches no rank, and a quest with none, are not rank quests.
            self.quest(7000, 500, 0, 0),
            self.quest(7001, 0, 0, 0),
        ]
        self.assertEqual(
            rank_quests(quests, self.EFFECTS),
            {
                129: [(300, 6624, 225, 35, "A"), (300, 6622, 225, 35, "H")],
                185: [(300, 6610, 225, 35, "A"), (300, 6610, 225, 35, "H")],
            },
        )

    def test_the_quest_asking_least_wins_per_side(self):
        quests = [self.quest(9001, 18260, 0, 0, "185", "250"), self.quest(9000, 0, 18261, 77, "185", "225")]
        self.assertEqual(
            rank_quests(quests, self.EFFECTS), {185: [(300, 9000, 225, 35, "A"), (300, 9001, 250, 35, "H")]}
        )

    def test_a_requirement_at_the_cap_is_refused(self):
        with self.assertRaises(ValueError):
            rank_quests([self.quest(1, 18260, 0, 0, "185", "300")], self.EFFECTS)
