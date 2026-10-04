"""Tests for the item set groups KeepOrSell reports to Baganator (Baganator.lua)."""
import unittest

from addon import CORE_FILES, load

STUBS = "AH = {link1 = 1000, link3 = 1000, link4 = 15}"


def names(ns, item_id):
    sets = ns.ItemSets(item_id, "link%d" % item_id)
    if sets is None:
        return []
    return [s.name for s in sets.values()]


class ItemSetTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Baganator.lua",), STUBS)
        self.ns.items = self.rt.eval("{['Lean Wolf Flank'] = 'open'}")

    def test_objective_item_is_quest(self):
        # Baganator groups by the first set; quest beats auction house
        self.assertEqual(names(self.ns, 1), ["Quest"])

    def test_quest_class_item_is_quest(self):
        # regular quest items share the group, so the built-in quest category stays empty
        self.assertEqual(names(self.ns, 2), ["Quest"])

    def test_auction_house_item(self):
        self.assertEqual(names(self.ns, 3), ["AuctionHouse"])

    def test_profession_reagent(self):
        self.rt.execute("KeepOrSellDB.recipes = {['Tester-Realm'] = {[100] = {4}}}")
        self.assertEqual(names(self.ns, 4), ["Profession"])

    def test_plain_item_has_no_set(self):
        self.assertEqual(names(self.ns, 4), [])
        self.assertEqual(names(self.ns, 9), [])

    def test_unknown_item(self):
        self.assertEqual(self.ns.ItemSets(None, None), None)

    def test_short_group_name(self):
        self.assertEqual(self.ns.L.SET_QUEST, "Quest")


if __name__ == "__main__":
    unittest.main()
