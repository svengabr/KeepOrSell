"""Tests for destroying the cheapest junk (Destroy.lua)."""
import unittest

from addon import CORE_FILES, load

# bag 0: linen x3 (no auction price, kept), potion (kept), white staff (junk without price),
# grey fang x5 (quality 0, 2c each)
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
ITEMS[21] = {"Smooth Pebble", 15, 0, "", 10, 0}
-- loot window: slot -> {itemID, quantity}
LOOT = {}
function GetNumLootItems() return #LOOT end
function GetLootSlotLink(slot) return LOOT[slot] and "link" .. LOOT[slot][1] end
function GetLootSlotInfo(slot) return 0, "", LOOT[slot] and LOOT[slot][2] or 0 end
ERR_INV_FULL = "Inventory is full."
"""

# minimal widgets: every unknown method is a no-op returning another widget
FRAMES = """
local function Widget()
  local w = {shown = true}
  return setmetatable(w, {__index = function(_, key)
    if key == "Show" then return function(self) self.shown = true end end
    if key == "Hide" then return function(self) self.shown = false end end
    if key == "IsShown" then return function(self) return self.shown end end
    if key == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if key == "IsMouseOver" then return function() return false end end
    if key == "GetStringWidth" then return function() return 0 end end
    if key == "Play" then return function(self) self.playing = true end end
    if key == "Stop" then return function(self) self.playing = false end end
    if key == "IsPlaying" then return function(self) return self.playing == true end end
    if key == "SetScript" then return function(self, name, fn) self[name] = fn end end
    return function() return Widget() end
  end})
end
CreateFrame = function() return Widget() end
UIParent = Widget()
GameTooltip = Widget()
Baganator = {API = {RegisterRegion = function(_, _, _, _, frame) DESTROY_BUTTON = frame end, RequestLayoutUpdate = function() end}}
"""


def candidate(rt, **kw):
    kw.setdefault("value", 0)
    kw.setdefault("quality", 0)
    return rt.table_from(kw)


class PickTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS)

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
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS)

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
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS)
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


def loot(rt, *items):
    rt.execute("LOOT = {}")
    for item_id, quantity in items:
        rt.execute(f"table.insert(LOOT, {{{item_id}, {quantity}}})")


class LootWorthMoreTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS)
        self.target = self.ns.FindDestroyTarget()  # grey fang x5, worth 10

    def best(self):
        best = self.ns.LootWorthMore(self.ns.LootItems(), self.target)
        return best and best.link

    def test_more_valuable_loot(self):
        loot(self.rt, (4, 1))  # linen, 13 at the vendor
        self.assertEqual(self.best(), "link4")

    def test_same_value_no_hint(self):
        loot(self.rt, (21, 1))
        self.assertIsNone(self.best())

    def test_quantity_counts(self):
        loot(self.rt, (21, 2))
        self.assertEqual(self.best(), "link21")

    def test_auction_price_beats_vendor(self):
        self.rt.execute("AH.link21 = 500")
        loot(self.rt, (4, 1), (21, 1))
        self.assertEqual(self.best(), "link21")

    def test_quest_item_always_worth_it(self):
        self.rt.execute("ITEMS[2][5] = 0")
        loot(self.rt, (2, 1), (4, 1))  # sealed letter, a quest item worth nothing
        self.assertEqual(self.best(), "link2")

    def test_no_junk_no_hint(self):
        loot(self.rt, (4, 1))
        self.assertIsNone(self.ns.LootWorthMore(self.ns.LootItems(), None))

    def test_no_loot(self):
        self.assertIsNone(self.best())


class LootFlowTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), FRAMES + STUBS)
        self.rt.execute("KeepOrSellDB.destroy = true")
        self.assertTrue(self.ns.RegisterDestroy())
        self.ns.UpdateDestroy()
        loot(self.rt, (4, 1))

    def full(self):
        self.ns.InventoryFull(self.rt.eval("ERR_INV_FULL"))

    def test_glows_and_tells_once_per_loot_window(self):
        self.ns.LootOpened()
        self.full()
        self.full()
        self.assertTrue(self.ns.IsDestroyGlowing())
        printed = list(self.rt.eval("PRINTED").values())
        self.assertEqual(len(printed), 1)
        self.assertIn("link4", printed[0])
        self.assertIn("link20", printed[0])

    def test_glow_ends_when_loot_closes(self):
        self.ns.LootOpened()
        self.full()
        self.ns.LootClosed()
        self.assertFalse(self.ns.IsDestroyGlowing())

    def test_glow_ends_after_destroying(self):
        self.ns.LootOpened()
        self.full()
        self.rt.eval("function(b) b.OnClick(b) end")(self.rt.eval("DESTROY_BUTTON"))
        self.assertEqual(self.rt.eval("DELETED"), 20)
        self.assertFalse(self.ns.IsDestroyGlowing())

    def test_other_errors_ignored(self):
        self.ns.LootOpened()
        self.ns.InventoryFull("You are too far away.")
        self.assertFalse(self.ns.IsDestroyGlowing())

    def test_only_while_looting(self):
        self.full()
        self.assertFalse(self.ns.IsDestroyGlowing())

    def test_switched_off(self):
        self.rt.execute("KeepOrSellDB.destroy = false")
        self.ns.LootOpened()
        self.full()
        self.assertFalse(self.ns.IsDestroyGlowing())
        self.assertEqual(len(self.rt.eval("PRINTED")), 0)

    def test_new_loot_window_tells_again(self):
        self.ns.LootOpened()
        self.full()
        self.ns.LootClosed()
        self.ns.LootOpened()
        self.full()
        self.assertEqual(len(self.rt.eval("PRINTED")), 2)


# bag 1: herb bag (family 32) with one free slot holding a grey item
BAGS_STUBS = """
NUM_BAG_SLOTS = 1
BAG1 = {[1] = {itemID = 21, stackCount = 1, quality = 0}}
FAMILY = {[0] = 0, [1] = 32}
FREE = {[0] = 0, [1] = 1}
MAXSTACK = {[4] = 20}
ITEM_FAMILY = {[30] = 32}
ITEMS[30] = {"Peacebloom", 7, 9, "", 5, 1}
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 4 or 2 end
local bag0 = C_Container.GetContainerItemInfo
C_Container.GetContainerItemInfo = function(bag, slot)
  if bag == 0 then return bag0(bag, slot) end
  local s = BAG1[slot]
  if not s then return nil end
  return {itemID = s.itemID, hyperlink = "link" .. s.itemID, stackCount = s.stackCount, quality = s.quality,
    isLocked = false, iconFileID = 100 + s.itemID}
end
C_Container.GetContainerNumFreeSlots = function(bag) return FREE[bag], FAMILY[bag] end
C_Item.GetItemMaxStackSizeByID = function(id) return MAXSTACK[id] or 1 end
C_Item.GetItemFamily = function(id) return ITEM_FAMILY[id] or 0 end
"""


class FitsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS + BAGS_STUBS)

    def test_fits_on_stacks(self):
        fits = self.ns.FitsOnStacks
        self.assertTrue(fits(17, 20, 1, 3))
        self.assertFalse(fits(18, 20, 1, 3))
        self.assertTrue(fits(10, 20, 2, 30))  # loot fills every stack with room
        self.assertFalse(fits(1, 20, 0, 0))   # no stack yet
        self.assertFalse(fits(1, 1, 3, 3))    # doesn't stack
        self.assertFalse(fits(1, None, 1, 1))

    def test_family_matches(self):
        self.assertTrue(self.ns.FamilyMatches(32, 32))
        self.assertTrue(self.ns.FamilyMatches(32 + 8, 32))
        self.assertFalse(self.ns.FamilyMatches(8, 32))
        self.assertFalse(self.ns.FamilyMatches(0, 32))
        self.assertFalse(self.ns.FamilyMatches(32, 0))

    def test_free_slots_only_regular_bags(self):
        self.assertEqual(self.ns.FreeSlots(), 0)
        self.rt.execute("FREE[0] = 2")
        self.assertEqual(self.ns.FreeSlots(), 2)

    def test_loot_fits(self):
        self.assertTrue(self.ns.LootFits(4, 17))   # linen x3 in the bags, stacks to 20
        self.assertFalse(self.ns.LootFits(4, 18))
        self.assertTrue(self.ns.LootFits(30, 1))   # herb into the herb bag's free slot
        self.rt.execute("FREE[1] = 0")
        self.assertFalse(self.ns.LootFits(30, 1))
        self.assertFalse(self.ns.LootFits(9, 1))   # potion doesn't stack

    def test_junk_in_profession_bag_not_destroyed(self):
        # the pebble in the herb bag is cheapest, but destroying it frees no regular slot
        self.rt.execute("ITEMS[21][5] = 1")
        target = self.ns.FindDestroyTarget()
        self.assertEqual((target.bag, target.itemID), (0, 20))
        self.assertTrue(all(not c.special for c in self.ns.DestroyCandidates().values()))

    def test_fitting_loot_needs_no_junk(self):
        loot(self.rt, (4, 5))
        items = self.ns.LootItems()
        self.assertTrue(items[1].fits)
        self.assertIsNone(self.ns.LootWorthMore(items, self.ns.FindDestroyTarget()))


def item(rt, slot, value, keep=False, fits=False):
    return rt.table_from({"slot": slot, "link": f"loot{slot}", "value": value, "keep": keep, "fits": fits})


class PairLootTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua"), STUBS)
        self.junk = self.rt.table_from([self.rt.table_from({"link": f"junk{v}", "value": v}) for v in (5, 10, 50)])

    def pair(self, loot, free=0):
        result = self.ns.PairLoot(self.rt.table_from(loot), self.junk, free)
        return [(p.loot.slot, p.target and p.target.link, p.worth) for p in result.values()]

    def test_most_valuable_loot_gets_cheapest_junk(self):
        loot = [item(self.rt, 1, 8), item(self.rt, 2, 30), item(self.rt, 3, 7)]
        self.assertEqual(self.pair(loot), [(2, "junk5", True), (1, "junk10", False), (3, "junk50", False)])

    def test_kept_loot_first_and_always_worth_it(self):
        loot = [item(self.rt, 1, 30), item(self.rt, 2, 0, keep=True)]
        self.assertEqual(self.pair(loot), [(2, "junk5", True), (1, "junk10", True)])

    def test_free_slots_go_to_the_best_loot(self):
        loot = [item(self.rt, 1, 8), item(self.rt, 2, 30)]
        self.assertEqual(self.pair(loot, free=1), [(2, None, None), (1, "junk5", True)])

    def test_fitting_loot_skipped(self):
        loot = [item(self.rt, 1, 100, fits=True), item(self.rt, 2, 30)]
        self.assertEqual(self.pair(loot), [(2, "junk5", True)])

    def test_out_of_junk(self):
        loot = [item(self.rt, i, 100 + i) for i in range(1, 5)]
        self.assertEqual(len(self.pair(loot)), 3)


if __name__ == "__main__":
    unittest.main()
