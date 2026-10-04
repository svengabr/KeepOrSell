"""Tests for the bag value line (BagValue.lua)."""
import unittest

from addon import CORE_FILES, load
from test_destroy import FRAMES, STUBS

FILES = CORE_FILES + ("Scrap.lua", "Bags.lua", "BagValue.lua")


def item(rt, **kw):
    kw.setdefault("value", 0)
    kw.setdefault("count", 1)
    return rt.table_from(kw)


class SumTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)

    def sum(self, *items):
        return self.ns.SumBagValue(self.rt.table_from([item(self.rt, **i) for i in items]))

    def test_empty(self):
        total = self.sum()
        self.assertEqual((total.junk, total.ah, total.junkCount, total.ahCount), (0, 0, 0, 0))
        self.assertEqual(len(total.top), 0)

    def test_junk_and_auction_house(self):
        total = self.sum({"link": "a", "junk": True, "value": 30}, {"link": "b", "junk": True, "value": 5},
                         {"link": "c", "value": 40, "ah": 900}, {"link": "d", "value": 99})
        self.assertEqual((total.junk, total.ah, total.junkCount, total.ahCount), (35, 900, 2, 1))

    def test_top_three_by_auction_value(self):
        total = self.sum(*({"link": f"i{v}", "ah": v} for v in (100, 400, 50, 300)))
        self.assertEqual([t.link for t in total.top.values()], ["i400", "i300", "i100"])


class FormatTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)

    def line(self, junk, ah):
        return self.ns.FormatBagValue(self.rt.table_from({"junk": junk, "ah": ah}))

    def test_both(self):
        self.assertEqual(self.line(120, 1540), "Junk 120c · AH 1540c")

    def test_only_junk(self):
        self.assertEqual(self.line(120, 0), "Junk 120c")

    def test_only_auction_house(self):
        self.assertEqual(self.line(0, 1540), "AH 1540c")

    def test_nothing(self):
        self.assertIsNone(self.line(0, 0))


class ScanTests(unittest.TestCase):
    def setUp(self):
        # the potion (slot 2) is worth auctioning: 300 at auction, 40 at the vendor
        self.rt, self.ns = load(FILES, STUBS + "AH.link9 = 300")

    def test_bags_summed(self):
        total = self.ns.SumBagValue(self.ns.ScanBags())
        # junk: white staff 50 + grey fang 5 x 2
        self.assertEqual((total.junk, total.junkCount, total.ah, total.ahCount), (60, 2, 300, 1))


class DisplayTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, FRAMES + STUBS + "AH.link9 = 300")
        self.rt.execute("""
          Baganator.API.RegisterRegion = function(_, _, _, _, frame) VALUE_FRAME = frame end
          KeepOrSellDB.bagValue = true""")
        self.assertTrue(self.ns.RegisterBagValue())

    def test_shown_with_value(self):
        self.ns.UpdateBagValue()
        self.assertTrue(self.rt.eval("VALUE_FRAME:IsShown()"))

    def test_hidden_when_switched_off(self):
        self.rt.execute("KeepOrSellDB.bagValue = false")
        self.ns.UpdateBagValue()
        self.assertFalse(self.rt.eval("VALUE_FRAME:IsShown()"))

    def test_hidden_when_nothing_to_sell(self):
        self.ns.UpdateBagValue()
        self.rt.execute("SLOTS = {}")
        self.ns.UpdateBagValue()
        self.assertFalse(self.rt.eval("VALUE_FRAME:IsShown()"))


if __name__ == "__main__":
    unittest.main()
