"""Rank books: the profession ranks an item teaches, from the client's spell and item tables."""

import unittest

from gen_recipes import rank_books


def effect(spell, kind, trigger=0, points=0, misc=0):
    return {
        "SpellID": str(spell),
        "DifficultyID": "0",
        "Effect": str(kind),
        "EffectTriggerSpell": str(trigger),
        "EffectBasePointsF": str(points),
        "EffectMiscValue_0": str(misc),
    }


def item(item_id, price=10000, required=125, level=0, flags=0):
    return {
        "ID": str(item_id),
        "BuyPrice": str(price),
        "RequiredSkillRank": str(required),
        "RequiredLevel": str(level),
        "Flags_0": str(flags),
    }


class RankBookTests(unittest.TestCase):
    # Issue #121: Forever's Expert First Aid (7924, tier 3) is taught by spell 19903, which the book 16084 casts.
    effects = [
        effect(7924, 118, points=3, misc=129),
        effect(19903, 36, trigger=7924),
        effect(10846, 118, points=4, misc=129),
        effect(19902, 36, trigger=10846),
        effect(3279, 44, points=1, misc=129),
    ]
    item_effects = [{"ID": "100023", "SpellID": "19903"}, {"ID": "100024", "SpellID": "19902"}]
    links = [{"ItemID": "16084", "ItemEffectID": "100023"}, {"ItemID": "16085", "ItemEffectID": "100024"}]

    def test_book_teaches_its_rank(self):
        books = rank_books(self.effects, [item(16084)], self.item_effects, self.links, {129})
        # The Artisan book 16085 isn't in this build's ItemSparse, so it teaches nobody.
        self.assertEqual(books, {129: [(225, 16084, 10000, 125, 0)]})

    def test_deprecated_or_foreign_books_are_left_out(self):
        self.assertEqual(rank_books(self.effects, [item(16084, flags=0x10)], self.item_effects, self.links, {129}), {})
        self.assertEqual(rank_books(self.effects, [item(16084)], self.item_effects, self.links, {185}), {})

    def test_lowest_requirement_wins(self):
        links = [*self.links, {"ItemID": "20000", "ItemEffectID": "100023"}]
        rows = [item(16084), item(20000, price=500, required=100)]
        books = rank_books(self.effects, rows, self.item_effects, links, {129})
        self.assertEqual(books, {129: [(225, 20000, 500, 100, 0)]})

    def test_contradictory_book_fails(self):
        with self.assertRaisesRegex(ValueError, "Rank book 16084"):
            rank_books(self.effects, [item(16084, required=225)], self.item_effects, self.links, {129})

    def test_a_book_asking_no_skill_is_kept(self):
        books = rank_books(self.effects, [item(16084, required=0)], self.item_effects, self.links, {129})
        self.assertEqual(books, {129: [(225, 16084, 10000, 0, 0)]})


if __name__ == "__main__":
    unittest.main()
