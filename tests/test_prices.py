"""Tests für die Preis-Einstufung (Prices.lua)."""
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent


def load(stubs=""):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    if stubs:
        rt.execute(stubs)
    ns = rt.eval("{}")
    rt.eval("function(path, ns) assert(loadfile(path))('BagQuestMarks', ns) end")(
        str(ROOT / "Prices.lua").replace("\\", "/"), ns)
    return rt, ns


class ClassifyTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def test_ah_at_least_factor(self):
        self.assertEqual(self.ns.ClassifyPrice(200, 100, 2), "ah")
        self.assertEqual(self.ns.ClassifyPrice(500, 100, 2), "ah")

    def test_vendor_below_factor(self):
        self.assertEqual(self.ns.ClassifyPrice(199, 100, 2), "vendor")

    def test_unknown_ah_price(self):
        self.assertIsNone(self.ns.ClassifyPrice(None, 100, 2))
        self.assertIsNone(self.ns.ClassifyPrice(0, 100, 2))

    def test_not_vendorable_but_ah_price(self):
        self.assertEqual(self.ns.ClassifyPrice(50, 0, 2), "ah")
        self.assertEqual(self.ns.ClassifyPrice(50, None, 2), "ah")


class LookupTests(unittest.TestCase):
    STUBS = """
    Auctionator = {API = {v1 = {GetAuctionPriceByItemLink = function(caller, link)
      if link == "flanke" then return 200 end end}}}
    C_Item = {GetItemInfo = function(link) return link, nil, nil, nil, nil, nil, nil, nil, nil, nil, 24 end}
    """

    def test_lookup_uses_auctionator_and_vendor(self):
        rt, ns = load(self.STUBS)
        self.assertEqual(ns.GetPriceClass("flanke", 2), "ah")
        self.assertEqual(ns.GetPriceClass("flanke", 10), "vendor")
        self.assertIsNone(ns.GetPriceClass("unbekannt", 2))

    def test_without_auctionator(self):
        rt, ns = load()
        self.assertIsNone(ns.GetPriceClass("flanke", 2))


if __name__ == "__main__":
    unittest.main()
