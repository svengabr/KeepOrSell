"""Tests for the price classification (Prices.lua)."""
import unittest

from addon import load


class ClassifyTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",), base=False)

    def test_ah_at_least_factor(self):
        self.assertEqual(self.ns.ClassifyPrice(200, 100, 2), "ah")
        self.assertEqual(self.ns.ClassifyPrice(500, 100, 2), "ah")

    def test_vendor_below_factor(self):
        self.assertEqual(self.ns.ClassifyPrice(199, 100, 2), ("vendor", "factor"))

    def test_unknown_ah_price(self):
        self.assertIsNone(self.ns.ClassifyPrice(None, 100, 2))
        self.assertIsNone(self.ns.ClassifyPrice(0, 100, 2))

    def test_not_vendorable_but_ah_price(self):
        self.assertEqual(self.ns.ClassifyPrice(50, 0, 2), "ah")
        self.assertEqual(self.ns.ClassifyPrice(50, None, 2), "ah")

    def test_min_profit_after_cut(self):
        # 1000 * 0.95 - 100 = 850 copper profit
        self.assertEqual(self.ns.ClassifyPrice(1000, 100, 2, 850), "ah")
        self.assertEqual(self.ns.ClassifyPrice(1000, 100, 2, 851), ("vendor", "minprofit"))

    def test_min_profit_without_vendor_price_keeps(self):
        # can't be sold to a vendor either
        self.assertIsNone(self.ns.ClassifyPrice(50, 0, 2, 100))


class PricesTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",), base=False)
        self.db = self.rt.eval("{factor = 2, minProfit = 0, maxAge = 7}")

    def classify(self, **prices):
        result = self.ns.ClassifyPrices(self.rt.table_from(prices), self.db)
        # lupa unpacks two return values into a tuple, a single one stays as is
        return result if isinstance(result, tuple) else (result, None)

    def test_fresh_price(self):
        self.assertEqual(self.classify(ah=300, vendor=100, age=2, hasAge=True), ("ah", None))

    def test_factor_at_least_minimum(self):
        # below 1.1x the 5% AH cut can make the vendor pay more (Auctionator warns then)
        self.db.factor = 1
        self.assertEqual(self.classify(ah=105, vendor=100), ("vendor", "factor"))
        self.assertEqual(self.classify(ah=110, vendor=100), ("ah", None))

    def test_stale_price_kept(self):
        self.assertEqual(self.classify(ah=300, vendor=100, age=8, hasAge=True), (None, "stale"))

    def test_older_than_auctionator_keeps_age_is_stale(self):
        self.assertEqual(self.classify(ah=300, vendor=100, hasAge=True), (None, "stale"))

    def test_age_check_off_at_21(self):
        self.db.maxAge = 21
        self.assertEqual(self.classify(ah=300, vendor=100, hasAge=True), ("ah", None))

    def test_no_age_api(self):
        self.assertEqual(self.classify(ah=300, vendor=100), ("ah", None))

    def test_no_price(self):
        self.assertEqual(self.classify(vendor=100), (None, "noprice"))

    def test_min_profit_in_silver(self):
        self.db.minProfit = 9  # 900 copper
        self.assertEqual(self.classify(ah=1000, vendor=100, age=0, hasAge=True), ("vendor", "minprofit"))


class LookupTests(unittest.TestCase):
    def test_lookup_uses_auctionator_and_vendor(self):
        rt, ns = load(("Prices.lua",), stubs='AH["link4"] = 200; AGE["link4"] = 1')
        prices = ns.GetPrices("link4")
        self.assertEqual((prices.ah, prices.vendor, prices.age, prices.hasAge), (200, 13, 1, True))
        self.assertIsNone(ns.GetPrices("link3").ah)

    def test_without_auctionator(self):
        rt, ns = load(("Prices.lua",), stubs="Auctionator = nil")
        prices = ns.GetPrices("link4")
        self.assertEqual((prices.ah, prices.vendor), (None, 13))

    def test_without_link(self):
        rt, ns = load(("Prices.lua",))
        self.assertIsNone(ns.GetPrices(None).vendor)


DAY = 86400
NOW = 100 * DAY


class FreshnessTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",), base=False)

    def fresh(self, days, visit=None):
        return self.rt.table_from({"days": days, "visit": visit} if visit else {"days": days})

    def test_fewer_days_win_regardless_of_scan_time(self):
        self.assertTrue(self.ns.IsFresher(self.fresh(0), self.fresh(1, NOW)))
        self.assertFalse(self.ns.IsFresher(self.fresh(2, NOW), self.fresh(1)))

    def test_same_day_later_full_scan_wins(self):
        self.assertTrue(self.ns.IsFresher(self.fresh(0, NOW - 300), self.fresh(0, NOW - 3 * 3600)))
        self.assertFalse(self.ns.IsFresher(self.fresh(0, NOW - 3 * 3600), self.fresh(0, NOW - 300)))
        # less than a minute apart counts as the same scan
        self.assertFalse(self.ns.IsFresher(self.fresh(0, NOW - 30), self.fresh(0, NOW - 60)))

    def test_same_day_without_scan_time_is_a_tie(self):
        self.assertFalse(self.ns.IsFresher(self.fresh(0, NOW), self.fresh(0)))
        self.assertFalse(self.ns.IsFresher(self.fresh(0), self.fresh(0, NOW - 3600)))
        self.assertFalse(self.ns.IsFresher(self.fresh(1), self.fresh(1)))

    def test_anything_beats_no_price(self):
        self.assertTrue(self.ns.IsFresher(self.fresh(5), None))
        self.assertFalse(self.ns.IsFresher(None, self.fresh(5)))

    def test_own_freshness_uses_full_scan_only_for_todays_prices(self):
        own = self.ns.OwnFreshness(0, NOW - 3600, NOW)
        self.assertEqual((own.days, own.visit), (0, NOW - 3600))
        self.assertIsNone(self.ns.OwnFreshness(1, NOW - 3600, NOW).visit)
        self.assertIsNone(self.ns.OwnFreshness(0, NOW - 2 * DAY, NOW).visit)  # scan was before today's price
        self.assertIsNone(self.ns.OwnFreshness(0, None, NOW).visit)
        self.assertIsNone(self.ns.OwnFreshness(None, NOW, NOW))  # no age, no usable price

    def test_shared_freshness(self):
        entry = self.rt.table_from({"price": 1, "seen": NOW - 300, "visit": NOW - 300})
        fresh = self.ns.SharedFreshness(entry, NOW)
        self.assertEqual((fresh.days, fresh.visit), (0, NOW - 300))
        fresh = self.ns.SharedFreshness(self.rt.table_from({"price": 1, "seen": NOW - 2 * DAY}), NOW)
        self.assertEqual((fresh.days, fresh.visit), (2, None))


class SharedPriceTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",), base=False)

    def pick(self, own, shared):
        shared = self.rt.table_from(shared) if shared else None
        return self.ns.PickPrice(self.rt.table_from(own), shared, NOW)

    def test_no_shared_price_keeps_own(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 1, "hasAge": True}, None)
        self.assertEqual((prices.ah, prices.age), (300, 1))

    def test_shared_fills_missing_price(self):
        prices = self.pick({"vendor": 100}, {"price": 500, "seen": NOW - 2 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices.vendor, prices.age, prices.hasAge, prices["from"]),
                         (500, 100, 2, True, "Sven"))

    def test_shared_replaces_older_own(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 9, "hasAge": True},
                           {"price": 500, "seen": NOW - 1 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices["from"]), (500, "Sven"))
        # own price older than Auctionator reports (age nil) counts as old too
        prices = self.pick({"ah": 300, "hasAge": True}, {"price": 500, "seen": NOW - 1 * DAY, "from": "Sven"})
        self.assertEqual(prices.ah, 500)

    def test_fresher_own_wins(self):
        prices = self.pick({"ah": 300, "vendor": 100, "age": 1, "hasAge": True},
                           {"price": 500, "seen": NOW - 3 * DAY, "from": "Sven"})
        self.assertEqual((prices.ah, prices["from"]), (300, None))

    def test_own_without_age_api_wins(self):
        # older Auctionator without an age: its price is trusted as before
        prices = self.pick({"ah": 300}, {"price": 500, "seen": NOW, "from": "Sven"})
        self.assertEqual(prices.ah, 300)

    def test_same_day_newer_full_scan_wins(self):
        # both today: the later full scan (here the sender's, 5 minutes ago) beats ours from 3 hours ago
        shared = {"price": 40, "seen": NOW - 300, "visit": NOW - 300, "from": "Sven"}
        own = {"ah": 35, "age": 0, "hasAge": True}
        prices = self.ns.PickPrice(self.rt.table_from(own), self.rt.table_from(shared), NOW, NOW - 3 * 3600)
        self.assertEqual((prices.ah, prices.age, prices["from"]), (40, 0, "Sven"))
        # our own full scan is the later one: keep ours
        prices = self.ns.PickPrice(self.rt.table_from(own), self.rt.table_from(shared), NOW, NOW - 60)
        self.assertEqual(prices.ah, 35)

    def test_same_day_without_own_full_scan_keeps_own(self):
        # only searched single items today: no scan time to compare, a tie keeps our price
        shared = {"price": 40, "seen": NOW - 300, "visit": NOW - 300, "from": "Sven"}
        prices = self.ns.PickPrice(self.rt.table_from({"ah": 35, "age": 0, "hasAge": True}),
                                   self.rt.table_from(shared), NOW, None)
        self.assertEqual(prices.ah, 35)

    def lookup(self, share):
        rt, ns = load(("Prices.lua",), stubs="""
          function GetServerTime() return %d end
          KeepOrSellDB.share = %s
          function GetNormalizedRealmName() return "Realm" end
          function UnitFactionGroup() return "Horde" end
          KeepOrSellDB.sharedPrices = {["Realm-Horde"] = {[3] = {price = 700, seen = %d, from = "Sven"}}}
        """ % (NOW, share, NOW - DAY))
        return ns.GetPrices("link3")

    def test_lookup_uses_shared_price(self):
        prices = self.lookup("true")
        self.assertEqual((prices.ah, prices.vendor, prices.age, prices["from"]), (700, 38, 1, "Sven"))

    def test_lookup_ignores_shared_price_when_option_off(self):
        self.assertIsNone(self.lookup("false").ah)


class MergeFallbackTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Prices.lua",))

    def merge(self, prices, fallback):
        return self.ns.MergeFallback(self.rt.eval(prices), fallback, "tsm")

    def test_own_price_wins(self):
        p = self.merge("{ah = 200, vendor = 13, age = 1, hasAge = true}", 999)
        self.assertEqual((p.ah, p.hasAge, p.source), (200, True, None))

    def test_fills_missing_price(self):
        p = self.merge("{vendor = 13}", 500)
        self.assertEqual((p.ah, p.vendor, p.hasAge, p.source), (500, 13, False, "tsm"))

    def test_no_fallback_keeps_prices(self):
        self.assertIsNone(self.merge("{vendor = 13}", None).ah)
        self.assertIsNone(self.merge("{vendor = 13}", 0).ah)

    def test_stale_own_price_not_replaced(self):
        p = self.merge("{ah = 200, vendor = 13, age = 15, hasAge = true}", 999)
        self.assertEqual((p.ah, p.age), (200, 15))

    def test_tsm_price_never_stale(self):
        p = self.merge("{vendor = 13}", 500)
        self.assertEqual(self.ns.ClassifyPrices(p, self.rt.eval("{factor = 2, maxAge = 3}")), "ah")


TSM_STUB = """
TSM = {}           -- itemString -> copper
TSM_CALLS = 0
TSM_API = {
  ToItemString = function(link) local id = link:match("%d+") return id and ("i:" .. id) end,
  GetCustomPriceValue = function(str, itemString)
    TSM_CALLS = TSM_CALLS + 1
    assert(str == "first(DBMinBuyout, DBMarket)")
    if TSM_FAIL then error("bad argument") end
    return TSM[itemString]
  end,
}
"""


class TSMLookupTests(unittest.TestCase):
    def load(self, extra=""):
        return load(("Prices.lua", "TSM.lua"), stubs=TSM_STUB + extra)

    def test_only_tsm(self):
        rt, ns = self.load('Auctionator = nil; TSM["i:4"] = 300')
        p = ns.GetPrices("link4")
        self.assertEqual((p.ah, p.vendor, p.hasAge, p.source), (300, 13, False, "tsm"))

    def test_auctionator_wins_without_calling_tsm(self):
        rt, ns = self.load('AH["link4"] = 200; TSM["i:4"] = 300')
        self.assertEqual(ns.GetPrices("link4").ah, 200)
        self.assertEqual(rt.eval("TSM_CALLS"), 0)

    def test_tsm_fills_gap_next_to_auctionator(self):
        rt, ns = self.load('TSM["i:3"] = 900')
        self.assertEqual(ns.GetPrices("link3").source, "tsm")

    def test_shared_price_beats_tsm(self):
        rt, ns = self.load("""
          TSM["i:3"] = 900
          function GetServerTime() return %d end
          KeepOrSellDB.share = true
          function GetNormalizedRealmName() return "Realm" end
          function UnitFactionGroup() return "Horde" end
          KeepOrSellDB.sharedPrices = {["Realm-Horde"] = {[3] = {price = 700, seen = %d, from = "Sven"}}}
        """ % (NOW, NOW - DAY))
        p = ns.GetPrices("link3")
        self.assertEqual((p.ah, p["from"], p.source), (700, "Sven", None))
        self.assertEqual(rt.eval("TSM_CALLS"), 0)

    def test_tsm_error_gives_no_price(self):
        rt, ns = self.load('Auctionator = nil; TSM_FAIL = true')
        self.assertIsNone(ns.GetPrices("link4").ah)

    def test_unparsable_link(self):
        rt, ns = self.load('Auctionator = nil; TSM_API.ToItemString = function() return nil end')
        self.assertIsNone(ns.GetTSMPrice("link4"))
        self.assertEqual(rt.eval("TSM_CALLS"), 0)

    def test_no_data_for_realm(self):
        rt, ns = self.load("Auctionator = nil")
        self.assertIsNone(ns.GetPrices("link4").ah)

    def test_without_tsm(self):
        rt, ns = load(("Prices.lua", "TSM.lua"), stubs="Auctionator = nil")
        self.assertIsNone(ns.GetTSMPrice("link4"))
        self.assertIsNone(ns.GetPrices("link4").ah)


if __name__ == "__main__":
    unittest.main()
