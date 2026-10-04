"""Tests for destroying the cheapest junk (Destroy.lua)."""
import unittest

from addon import CORE_FILES, load

# bag 0: linen x3 (cheap trade good, junk), potion (kept), white staff (junk without price),
# grey item (quality 0, sells for nothing)
STUBS = """
ITEMS[20] = {"Broken Fang", 15, 0, "", 2, 0}
SLOTS = {
  [1] = {itemID = 4, stackCount = 3, quality = 1},
  [2] = {itemID = 9, stackCount = 1, quality = 1},
  [3] = {itemID = 10, stackCount = 1, quality = 1},
  [4] = {itemID = 20, stackCount = 5, quality = 0},
}
NUM_BAG_SLOTS = 0
C_Container = {
  GetContainerNumSlots = function(bag) return 4 end,
  GetContainerItemInfo = function(bag, slot)
    local s = SLOTS[slot]
    if not s then return nil end
    return {itemID = s.itemID, hyperlink = "link" .. s.itemID, stackCount = s.stackCount, quality = s.quality,
      isLocked = s.isLocked or false, iconFileID = 100 + s.itemID}
  end,
  GetContainerItemLink = function(bag, slot) return SLOTS[slot] and "link" .. SLOTS[slot].itemID end,
  PickupContainerItem = function(bag, slot) CURSOR = SLOTS[slot] and SLOTS[slot].itemID end,
}
AH = {link9 = 10}
function GetCursorInfo() if CURSOR then return "item", CURSOR, "link" .. CURSOR end end
function CursorHasItem() return CURSOR ~= nil end
function DeleteCursorItem() DELETED = CURSOR; CURSOR = nil end
function ClearCursor() CURSOR = nil end
function GetMoneyString(copper) return copper .. "c" end
PRINTED = {}
print = function(text) table.insert(PRINTED, text) end
"""


def candidate(rt, **kw):
    kw.setdefault("value", 0)
    kw.setdefault("quality", 0)
    return rt.table_from(kw)


class PickTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Destroy.lua"), STUBS)

    def pick(self, *candidates):
        chosen = self.ns.PickCheapest(self.rt.table_from([candidate(self.rt, **c) for c in candidates]))
        return chosen and chosen.slot

    def test_empty(self):
        self.assertIsNone(self.pick())

    def test_lowest_value_wins(self):
        self.assertEqual(self.pick({"slot": 1, "value": 50}, {"slot": 2, "value": 10}, {"slot": 3, "value": 30}), 2)

    def test_no_value_first(self):
        self.assertEqual(self.pick({"slot": 1, "value": 5}, {"slot": 2, "value": 0}), 2)

    def test_tie_keeps_first_slot(self):
        self.assertEqual(self.pick({"slot": 1, "value": 5}, {"slot": 2, "value": 5}), 1)

    def test_locked_skipped(self):
        self.assertEqual(self.pick({"slot": 1, "value": 0, "locked": True}, {"slot": 2, "value": 9}), 2)

    def test_rare_or_better_never(self):
        self.assertIsNone(self.pick({"slot": 1, "quality": 3}, {"slot": 2, "quality": 4}))
        self.assertEqual(self.pick({"slot": 1, "quality": 3}, {"slot": 2, "quality": 2, "value": 9}), 2)


class FindTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Destroy.lua"), STUBS)

    def test_without_scrap_grey_and_own_junk(self):
        # staff 50, grey fang 5 x 2 = 10; linen without auction price and the potion are kept
        target = self.ns.FindDestroyTarget()
        self.assertEqual((target.slot, target.itemID, target.count, target.value), (4, 20, 5, 10))

    def test_grey_only_when_cheapest_is_gone(self):
        self.rt.execute("SLOTS[4] = nil")
        self.assertEqual(self.ns.FindDestroyTarget().slot, 3)

    def test_with_scrap_its_verdict_counts(self):
        # Scrap says only the staff is junk (e.g. the player marked the rest "not junk")
        self.rt.execute("Scrap = {IsJunk = function(self, id, bag, slot) return id == 10 end}")
        self.assertEqual(self.ns.FindDestroyTarget().slot, 3)

    def test_nothing_to_destroy(self):
        self.rt.execute("Scrap = {IsJunk = function() return false end}")
        self.assertIsNone(self.ns.FindDestroyTarget())


class DestroyTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Destroy.lua"), STUBS)
        self.target = self.ns.FindDestroyTarget()

    def test_destroys_target(self):
        self.assertTrue(self.ns.DestroyTarget(self.target))
        self.assertEqual(self.rt.eval("DELETED"), 20)
        self.assertIn("link20", self.rt.eval("PRINTED[1]"))

    def test_not_with_item_on_cursor(self):
        self.rt.execute("CURSOR = 9")
        self.assertFalse(self.ns.DestroyTarget(self.target))
        self.assertIsNone(self.rt.eval("DELETED"))
        self.assertEqual(self.rt.eval("CURSOR"), 9)  # the player's item stays on the cursor

    def test_not_when_slot_changed(self):
        self.rt.execute("SLOTS[4] = {itemID = 9, stackCount = 1, quality = 1}")
        self.assertFalse(self.ns.DestroyTarget(self.target))
        self.assertIsNone(self.rt.eval("DELETED"))

    def test_not_when_stack_grew(self):
        self.rt.execute("SLOTS[4].stackCount = 6")
        self.assertFalse(self.ns.DestroyTarget(self.target))
        self.assertIsNone(self.rt.eval("DELETED"))

    def test_not_when_locked(self):
        self.rt.execute("SLOTS[4].isLocked = true")
        self.assertFalse(self.ns.DestroyTarget(self.target))

    def test_wrong_item_picked_up_is_put_back(self):
        self.rt.execute("C_Container.PickupContainerItem = function() CURSOR = 9 end")
        self.assertFalse(self.ns.DestroyTarget(self.target))
        self.assertIsNone(self.rt.eval("DELETED"))
        self.assertIsNone(self.rt.eval("CURSOR"))

    def test_no_target(self):
        self.assertFalse(self.ns.DestroyTarget(None))


if __name__ == "__main__":
    unittest.main()
