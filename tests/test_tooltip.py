"""Tests for the tooltip line (Tooltip.lua)."""
import unittest

from addon import CORE_FILES, load

STUBS = """
function GetMoneyString(copper) return copper .. "c" end
local lines = {}
TOOLTIP_LINES = lines
GameTooltip = {
  GetItem = function() return "Item", CURRENT_LINK end,
  AddLine = function(self, text) table.insert(lines, text) end,
  Show = function() end,
}
Enum = {TooltipDataType = {Item = 0}}
TooltipDataProcessor = {AddTooltipPostCall = function(type, fn) POSTCALL = fn end}
AH = {link3 = 1000, link4 = 15, link5 = 120}
"""


class TooltipTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Tooltip.lua",), STUBS)
        self.ns.items = self.rt.eval("{['Lean Wolf Flank'] = 'done'}")
        self.ns.HookTooltip()

    def show(self, item_id):
        self.rt.execute("CURRENT_LINK = 'link%d'; for k in pairs(TOOLTIP_LINES) do TOOLTIP_LINES[k] = nil end" % item_id)
        self.rt.execute("POSTCALL(GameTooltip, {})")
        lines = list(self.rt.eval("TOOLTIP_LINES").values())
        return lines[0] if lines else None

    def test_auction_house_with_prices(self):
        self.assertIn("Auction house – AH 1000c, vendor 38c", self.show(3))

    def test_junk(self):
        self.assertIn("Junk – AH 15c, vendor 13c (below 2x vendor price)", self.show(4))

    def test_junk_names_min_profit(self):
        self.rt.execute("AH.link4 = 40; KeepOrSellDB.minProfit = 1")
        self.assertIn("(less than 100c profit)", self.show(4))

    def test_quest_done(self):
        self.assertIn("objective done", self.show(1))

    def test_unusable_gear(self):
        self.assertIn("your class can't use it", self.show(5))

    def test_missing_price(self):
        self.rt.execute("AH.link4 = nil")
        self.assertIn("Keep – no auction price", self.show(4))

    def test_plain_gear(self):
        self.assertIn("Junk – plain gear", self.show(10))

    def test_worn_item_skipped(self):
        self.rt.execute("C_Item.GetItemLocation = function() return {IsEquipmentSlot = function() return true end} end")
        self.rt.execute("CURRENT_LINK = 'link10'; POSTCALL(GameTooltip, {guid = 'g'})")
        self.assertEqual(len(list(self.rt.eval("TOOLTIP_LINES").values())), 0)

    def test_stale_price_on_other_items(self):
        # a potion with an outdated price could be an auction house item; say why it stays
        self.rt.execute("AH.link9 = 1000; AGE.link9 = 30")
        self.assertIn("older than 7 days", self.show(9))

    def test_recipe_text(self):
        text = self.ns.TooltipText(self.rt.eval("{kind = 'profession', reason = 'recipe'}"), None, None)
        self.assertIn("recipe for your profession", text)

    def test_stale_price(self):
        self.rt.execute("AGE.link4 = 30")
        self.assertIn("older than 7 days", self.show(4))

    def test_nothing_for_wearable_gear_or_plain_items(self):
        self.assertIsNone(self.show(7))
        self.assertIsNone(self.show(9))

    def test_switch_off(self):
        self.rt.execute("KeepOrSellDB.tooltip = false")
        self.assertIsNone(self.show(3))

    def test_comparison_tooltip_ignored(self):
        self.rt.execute("CURRENT_LINK = 'link3'; POSTCALL({GetItem = GameTooltip.GetItem, AddLine = GameTooltip.AddLine}, {})")
        self.assertEqual(len(list(self.rt.eval("TOOLTIP_LINES").values())), 0)


if __name__ == "__main__":
    unittest.main()
