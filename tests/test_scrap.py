"""Tests for the Scrap extension (Scrap.lua)."""
import unittest

from addon import CORE_FILES, load

# 3 silk is worth auctioning, 4 linen is cheap, 5 mail vest is unusable for a druid
STUBS = """
AH = {link3 = 1000, link4 = 15, link5 = 120}
Scrap = {junk = {}, IsJunk = function(self, id) return id == 99 end}
"""


class ScrapTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Scrap.lua",), STUBS)
        self.ns.items = self.rt.eval("{['Lean Wolf Flank'] = 'open'}")
        self.ns.HookScrap()
        self.is_junk = self.rt.eval("function(id) return Scrap:IsJunk(id) end")

    def test_cheap_tradegood_is_junk(self):
        self.assertTrue(self.is_junk(4))

    def test_quest_objective_never_junk(self):
        self.rt.execute("AH.link1 = 6")
        self.assertFalse(self.is_junk(1))

    def test_ah_worthy_not_junk(self):
        self.assertFalse(self.is_junk(3))

    def test_wearable_equipment_never_junk(self):
        self.rt.execute("AH.link7 = 1")
        self.assertFalse(self.is_junk(7))

    def test_white_gear_without_price_is_junk(self):
        self.assertTrue(self.is_junk(10))

    def test_white_gear_kept_before_auction_house_visit(self):
        self.rt.execute("KeepOrSellDB.ahVisited = nil")
        self.assertFalse(self.is_junk(10))

    def test_white_shirt_kept(self):
        self.assertFalse(self.is_junk(11))

    def test_unusable_equipment_is_junk(self):
        self.assertTrue(self.is_junk(5))

    def test_scrap_own_junk_kept(self):
        self.assertTrue(self.is_junk(99))

    def test_user_marked_not_junk_respected(self):
        self.rt.execute("Scrap.junk[4] = false")
        self.assertFalse(self.is_junk(4))

    def test_switch_off(self):
        self.rt.execute("KeepOrSellDB.scrap = false")
        self.assertFalse(self.is_junk(4))


if __name__ == "__main__":
    unittest.main()
