"""Tests for the coins in the loot window while the bags are full (LootCoins.lua)."""
import unittest

from addon import CORE_FILES, load
from test_destroy import FRAMES, STUBS, loot

# bags full (no free slot); the loot window has three rows showing loot slots 1-3
LOOT_UI = """
C_Timer = {After = function(_, fn) fn() end}
C_Container.GetContainerNumFreeSlots = function(bag) return FREE or 0, 0 end
local function Row(slot)
  local row = {slot = slot, Item = {}}
  function row:GetSlotIndex() return self.slot end
  function row:CreateTexture()
    local coin = {shown = false}
    function coin:Show() self.shown = true end
    function coin:Hide() self.shown = false end
    for _, name in ipairs({"SetTexture", "SetSize", "SetPoint"}) do coin[name] = function() end end
    row.coin = coin
    return coin
  end
  row.Item.GetParent = function() return row end
  return row
end
ROWS = {Row(1), Row(2), Row(3)}
LootFrame = {ScrollBox = {ForEachFrame = function(self, fn) for _, row in ipairs(ROWS) do fn(row) end end}}
ScrollUtil = {AddInitializedFrameCallback = function(box, fn) ROW_CALLBACK = fn end}
function COIN(i) return ROWS[i].coin ~= nil and ROWS[i].coin.shown end
"""

FILES = CORE_FILES + ("Scrap.lua", "Bags.lua", "Destroy.lua", "LootCoins.lua")


class LootCoinTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, FRAMES + STUBS + LOOT_UI)
        self.rt.execute("KeepOrSellDB.lootCoins = true; KeepOrSellDB.destroy = true")
        self.ns.RegisterDestroy()
        self.ns.UpdateDestroy()
        # cheapest junk: grey fang x5 (10), then the white staff (50)

    def coins(self):
        return [bool(self.rt.eval(f"COIN({i})")) for i in (1, 2, 3)]

    def test_coin_on_loot_worth_more(self):
        loot(self.rt, (4, 1), (21, 1))  # linen 13 > fang 10; pebble 10 vs staff 50
        self.ns.LootCoinsOpened()
        self.assertEqual(self.coins(), [True, False, False])
        self.assertTrue(self.ns.IsDestroyGlowing())

    def test_tooltip_names_the_junk(self):
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        note = self.ns.LootTooltipNote(self.rt.eval("ROWS[1].Item"))
        self.assertIn("link20", note)
        self.assertIn("10c", note)
        self.assertIsNone(self.ns.LootTooltipNote(self.rt.eval("ROWS[2].Item")))

    def test_no_coin_with_a_free_slot(self):
        self.rt.execute("FREE = 1")
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        self.assertEqual(self.coins(), [False, False, False])
        self.assertFalse(self.ns.IsDestroyGlowing())

    def test_coin_comes_back_when_bags_fill_again(self):
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        self.rt.execute("FREE = 1")
        self.ns.LootCoinsChanged()
        self.assertEqual(self.coins(), [False, False, False])
        self.rt.execute("FREE = 0")
        self.ns.LootCoinsChanged()
        self.assertEqual(self.coins(), [True, False, False])

    def test_cleared_when_loot_closes(self):
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        self.ns.LootCoinsClosed()
        self.assertEqual(self.coins(), [False, False, False])
        self.assertIsNone(self.ns.LootTooltipNote(self.rt.eval("ROWS[1].Item")))
        self.ns.LootCoinsChanged()  # bag updates after looting don't bring them back
        self.assertEqual(self.coins(), [False, False, False])

    def test_reused_row_follows_its_slot(self):
        loot(self.rt, (21, 1), (4, 1))
        self.ns.LootCoinsOpened()
        self.assertEqual(self.coins(), [False, True, False])
        # the list scrolls: row 1 now shows loot slot 2
        self.rt.execute("ROWS[1].slot = 2; ROW_CALLBACK(nil, ROWS[1])")
        self.assertTrue(self.rt.eval("COIN(1)"))

    def test_coins_switched_off_button_still_glows(self):
        self.rt.execute("KeepOrSellDB.lootCoins = false")
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        self.assertEqual(self.coins(), [False, False, False])
        self.assertTrue(self.ns.IsDestroyGlowing())

    def test_retries_while_item_data_loads(self):
        self.rt.execute("""
          CALLS = 0
          local link = GetLootSlotLink
          GetLootSlotLink = function(slot) CALLS = CALLS + 1; if CALLS <= 2 then return nil end return link(slot) end
        """)
        loot(self.rt, (4, 1))
        self.ns.LootCoinsOpened()
        self.assertEqual(self.coins(), [True, False, False])


if __name__ == "__main__":
    unittest.main()
