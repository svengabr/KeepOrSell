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
  AddDoubleLine = function(self, left, right) table.insert(lines, left .. " | " .. right) end,
  Show = function() end,
}
Enum = {TooltipDataType = {Item = 0}}
TooltipDataProcessor = {AddTooltipPostCall = function(type, fn) POSTCALL = fn end}
AH = {link3 = 1000, link4 = 15, link5 = 120}
"""


class TooltipTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Bags.lua", "Tooltip.lua"), STUBS)
        self.ns.items = self.rt.eval("{['Lean Wolf Flank'] = 'done'}")
        self.ns.HookTooltip()

    def show(self, item_id):
        self.rt.execute("CURRENT_LINK = 'link%d'; for k in pairs(TOOLTIP_LINES) do TOOLTIP_LINES[k] = nil end" % item_id)
        self.rt.execute("POSTCALL(GameTooltip, {})")
        lines = list(self.rt.eval("TOOLTIP_LINES").values())
        return "\n".join(lines) if lines else None

    def test_empty_line_sets_verdict_apart(self):
        self.show(3)
        lines = list(self.rt.eval("TOOLTIP_LINES").values())
        self.assertEqual(lines[0], " ")
        self.assertIn("KeepOrSell:", lines[1])

    def test_auction_house_with_prices(self):
        text = self.show(3)
        self.assertIn("KeepOrSell:|r Auction house\n", text)
        self.assertIn("|cff66ccff   » Auction house|r | |cff66ccff1000c|r\n|cffaaaaaa      Vendor|r | |cffaaaaaa38c|r", text)

    def test_tsm_price_named(self):
        self.rt.execute("""
          Auctionator = nil
          TSM_API = {ToItemString = function(link) return link end,
                     GetCustomPriceValue = function(_, s) return s == "link3" and 1000 or nil end}
        """)
        self.assertIn("Auction house – (TSM)", self.show(3))

    def test_auctionator_price_not_named_tsm(self):
        self.assertNotIn("(TSM)", self.show(3))

    def test_junk(self):
        text = self.show(4)
        self.assertIn("Junk – (below 2x vendor price)", text)
        self.assertIn("|cffffaa33   » Vendor|r | |cffffaa3313c|r\n|cffaaaaaa      Auction house|r | |cffaaaaaa15c|r", text)

    def test_junk_names_min_profit(self):
        self.rt.execute("AH.link4 = 40; KeepOrSellDB.minProfit = 1")
        self.assertIn("(less than 100c profit)", self.show(4))

    def test_open(self):
        verdict = self.rt.eval('{kind = "open"}')
        db = self.rt.eval("KeepOrSellDB")
        self.assertIn("Open (right-click) – 10 in your bags", self.ns.TooltipText(verdict, None, db, 10))
        self.assertIn("Open (right-click) – frees", self.ns.TooltipText(verdict, None, db, 1))

    def test_unstacked(self):
        db = self.rt.eval("KeepOrSellDB")
        ah = self.ns.TooltipText(self.rt.eval('{kind = "ah"}'), self.rt.eval("{ah = 100, vendor = 15}"), db, 5, True)
        self.assertIn("doesn't stack, takes 5 bag slots", ah)
        alone = self.ns.TooltipText(self.rt.eval("{}"), None, db, 5, True)
        self.assertIn("Doesn't stack – takes 5 bag slots", alone)
        self.assertIsNone(self.ns.TooltipText(self.rt.eval("{}"), None, db, 1, True))
        opened = self.ns.TooltipText(self.rt.eval('{kind = "open"}'), None, db, 5, True)
        self.assertNotIn("stack", opened)

    def test_quest_done(self):
        self.assertIn("objective done", self.show(1))

    def test_unusable_gear(self):
        self.assertIn("your class can't use it", self.show(5))

    def test_missing_price(self):
        self.rt.execute("AH.link4 = nil")
        text = self.show(4)
        self.assertIn("Keep – no auction price", text)
        self.assertIn("» Otherwise: Vendor|r | |cffffaa3313c|r", text)

    def test_plain_gear(self):
        self.assertIn("Junk – plain gear", self.show(10))

    def test_worn_item_skipped(self):
        self.rt.execute("C_Item.GetItemLocation = function() return {IsEquipmentSlot = function() return true end} end")
        self.rt.execute("CURRENT_LINK = 'link10'; POSTCALL(GameTooltip, {guid = 'g'})")
        self.assertEqual(len(list(self.rt.eval("TOOLTIP_LINES").values())), 0)

    def test_buyback_item_with_empty_location(self):
        # buyback items have a GUID, but their location is empty and IsValid() raises
        self.rt.execute("C_Item.IsBound = function() return true end")
        self.rt.execute("""C_Item.GetItemLocation = function() return {
          IsEquipmentSlot = function() return false end,
          IsBagAndSlot = function() return false end,
          IsValid = function() error("bad argument #1 to 'DoesItemExist'") end,
        } end""")
        self.rt.execute("CURRENT_LINK = 'link10'; POSTCALL(GameTooltip, {guid = 'g'})")
        self.assertIn("Junk – plain gear", list(self.rt.eval("TOOLTIP_LINES").values())[1])

    def test_stale_price_on_other_items(self):
        # a potion with an outdated price could be an auction house item; say why it stays
        self.rt.execute("AH.link9 = 1000; AGE.link9 = 30")
        self.assertIn("older than 7 days", self.show(9))

    def test_useless_recipe_text(self):
        text = self.ns.TooltipText(self.rt.eval("{kind = 'junk', reason = 'recipe_known'}"), self.rt.eval("{ah = 120, vendor = 100}"), self.rt.eval("KeepOrSellDB"))
        self.assertIn("Junk – recipe already known", text)
        text = self.ns.TooltipText(self.rt.eval("{kind = 'junk', reason = 'recipe_other', bound = true}"), None, self.rt.eval("KeepOrSellDB"))
        self.assertIn("recipe for a profession you don't have, soulbound", text)
        text = self.ns.TooltipText(self.rt.eval("{kind = 'ah', reason = 'recipe_other'}"), self.rt.eval("{ah = 5000, vendor = 100}"), self.rt.eval("KeepOrSellDB"))
        self.assertIn("Auction house", text)
        self.assertIn("recipe for a profession you don't have", text)

    def test_recipe_text(self):
        text = self.ns.TooltipText(self.rt.eval("{kind = 'profession', reason = 'recipe'}"), None, None)
        self.assertIn("recipe for your profession", text)

    def test_stale_price(self):
        self.rt.execute("AGE.link4 = 30")
        self.assertIn("older than 7 days", self.show(4))

    def test_wearable_gear_names_what_it_would_bring(self):
        self.show(7)
        lines = list(self.rt.eval("TOOLTIP_LINES").values())
        self.assertIn("Keep (wearable)", lines[1])
        self.assertEqual(lines[2], "|cffffaa33   » Otherwise: Vendor|r | |cffffaa33100c|r")

    def test_plain_items_just_kept(self):
        self.assertIn("KeepOrSell:|r Keep\n|cffffaa33   » Otherwise: Vendor|r", self.show(9))

    def test_nothing_without_a_price(self):
        self.assertIsNone(self.ns.TooltipText(self.rt.eval("{}"), self.rt.eval("{}"), self.rt.eval("KeepOrSellDB")))

    def test_profession_tool(self):
        text = self.ns.TooltipText(self.rt.eval("{reason = 'tool'}"), self.rt.eval("{ah = 120, vendor = 100}"), self.rt.eval("KeepOrSellDB"))
        self.assertIn("Keep", text)
        self.assertIn("profession tool", text)

    def test_upcoming_reagent(self):
        text = self.ns.TooltipText(self.rt.eval("{kind = 'profession', reason = 'upcoming'}"), None, None)
        self.assertIn("Profession", text)
        self.assertIn("can still learn", text)

    def test_kept_items_name_the_best_way_otherwise(self):
        # Wool Cloth for a recipe still to learn: the auction house pays more than the vendor
        rows = self.ns.TooltipRows(self.rt.eval("{kind = 'profession', reason = 'upcoming', ahTrusted = true}"),
                                   self.rt.eval("{ah = 65, vendor = 33}"))
        self.assertEqual([tuple(r.values()) for r in rows.values()],
                         [("   » Otherwise: Auction house", "65c", "ff66ccff"), ("      Vendor", "33c", "ffaaaaaa")])

    def test_plain_kept_item_names_the_best_way_otherwise(self):
        # a consumable below the auction factor: kept, but the auction house still pays more than the vendor
        db = self.rt.eval("KeepOrSellDB")
        verdict = self.rt.eval("{ahTrusted = true}")
        prices = self.rt.eval("{ah = 39, vendor = 25}")
        self.assertEqual(self.ns.TooltipText(verdict, prices, db), "|cffffd200KeepOrSell:|r Keep")
        self.assertEqual(list(self.ns.TooltipRows(verdict, prices)[1].values())[0], "   » Otherwise: Auction house")

    def test_kept_items_skip_untrusted_auction_price(self):
        rows = self.ns.TooltipRows(self.rt.eval("{kind = 'quest', reason = 'open', ahTrusted = false}"),
                                   self.rt.eval("{ah = 65, vendor = 33}"))
        self.assertEqual([tuple(r.values()) for r in rows.values()], [("   » Otherwise: Vendor", "33c", "ffffaa33")])

    def test_switch_off(self):
        self.rt.execute("KeepOrSellDB.tooltip = false")
        self.assertIsNone(self.show(3))

    def test_comparison_tooltip_ignored(self):
        self.rt.execute("CURRENT_LINK = 'link3'; POSTCALL({GetItem = GameTooltip.GetItem, AddLine = GameTooltip.AddLine}, {})")
        self.assertEqual(len(list(self.rt.eval("TOOLTIP_LINES").values())), 0)

    def test_shared_price_names_sender(self):
        db = self.rt.eval("KeepOrSellDB")
        text = self.ns.TooltipText(self.rt.eval("{kind = 'ah'}"),
                                   self.rt.eval("{ah = 1000, vendor = 38, age = 2, from = 'Sven'}"), db)
        self.assertIn("Auction house – (price from Sven, 2 days old)", text)
        text = self.ns.TooltipText(self.rt.eval("{kind = 'ah'}"),
                                   self.rt.eval("{ah = 1000, vendor = 38, age = 0, from = 'Sven'}"), db)
        self.assertIn("(price from Sven, today)", text)

    def test_own_price_has_no_sender(self):
        self.assertNotIn("price from", self.show(3))


if __name__ == "__main__":
    unittest.main()
