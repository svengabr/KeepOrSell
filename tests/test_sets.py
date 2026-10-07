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
        self.rt, self.ns = load(CORE_FILES + ("Bags.lua", "Baganator.lua"), STUBS)
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


class UnstackedSetTests(unittest.TestCase):
    BAG = """
    NUM_BAG_SLOTS = 0
    BAG = {[1] = 9, [2] = 9, [3] = 5, [4] = 5, [5] = 3, [6] = 3, [7] = 10}
    C_Container = {
      GetContainerNumSlots = function(bag) return 7 end,
      GetContainerItemInfo = function(bag, slot) return {itemID = BAG[slot], hyperlink = "link" .. BAG[slot]} end,
    }
    C_Item.GetItemMaxStackSizeByID = function(id) return id == 3 and 20 or 1 end
    """

    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Bags.lua", "Baganator.lua"), STUBS + self.BAG)

    def test_rule(self):
        rule = self.ns.IsUnstackedSet
        self.assertTrue(rule(None, True, 2, False))
        self.assertFalse(rule(None, True, 1, False))
        self.assertFalse(rule(None, False, 3, False))
        self.assertFalse(rule(None, True, 3, True))
        self.assertFalse(rule("ah", True, 3, False))
        self.assertFalse(rule("junk", True, 3, False))

    def test_unstacked_copies_shown_one_by_one(self):
        self.assertEqual(names(self.ns, 9), ["Unstacked"])

    def test_single_copy_stays(self):
        self.assertEqual(names(self.ns, 10), [])

    def test_gear_stays(self):
        self.assertEqual(names(self.ns, 5), [])

    def test_other_groups_win(self):
        self.assertEqual(names(self.ns, 3), ["AuctionHouse"])

    def test_slot_counts(self):
        self.assertEqual(self.ns.CountSlots(9), 2)
        self.assertEqual(self.ns.CountSlots(42), 0)


if __name__ == "__main__":
    unittest.main()
