"""Tests for the shared item decision (Gear.lua, Classify.lua)."""
import unittest

from addon import load

WEAPON, ARMOR = 2, 4
SWORD1H, POLEARM, STAFF, WAND = 7, 6, 10, 19
CLOTH, LEATHER, MAIL, PLATE, SHIELD, IDOL = 1, 2, 3, 4, 6, 8


class GearTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Gear.lua",), base=False)

    def unusable(self, cls, class_id, sub, loc="INVTYPE_CHEST"):
        return self.ns.IsUnusableGear(cls, class_id, sub, loc)

    def test_druid_cant_wear_mail_or_swords(self):
        self.assertTrue(self.unusable("DRUID", ARMOR, MAIL))
        self.assertTrue(self.unusable("DRUID", WEAPON, SWORD1H, "INVTYPE_WEAPON"))
        self.assertTrue(self.unusable("DRUID", ARMOR, SHIELD, "INVTYPE_SHIELD"))

    def test_druid_can_wear_leather_staff_idol(self):
        self.assertFalse(self.unusable("DRUID", ARMOR, LEATHER))
        self.assertFalse(self.unusable("DRUID", WEAPON, STAFF, "INVTYPE_2HWEAPON"))
        self.assertFalse(self.unusable("DRUID", ARMOR, IDOL, "INVTYPE_RELIC"))

    def test_later_proficiency_counts_as_wearable(self):
        # hunters and shamans learn mail at level 40, warriors and paladins plate
        self.assertFalse(self.unusable("HUNTER", ARMOR, MAIL))
        self.assertFalse(self.unusable("SHAMAN", ARMOR, MAIL))
        self.assertFalse(self.unusable("PALADIN", ARMOR, PLATE))

    def test_everyone_wears_cloth_and_cloaks(self):
        self.assertFalse(self.unusable("WARRIOR", ARMOR, CLOTH))
        self.assertFalse(self.unusable("MAGE", ARMOR, MAIL, "INVTYPE_CLOAK"))
        self.assertFalse(self.unusable("MAGE", ARMOR, 0, "INVTYPE_FINGER"))

    def test_wand_only_for_casters(self):
        self.assertTrue(self.unusable("WARRIOR", WEAPON, WAND, "INVTYPE_RANGEDRIGHT"))
        self.assertFalse(self.unusable("PRIEST", WEAPON, WAND, "INVTYPE_RANGEDRIGHT"))

    def test_unknown_class_or_subclass_is_kept(self):
        self.assertFalse(self.unusable("DEMONHUNTER", ARMOR, MAIL))
        self.assertFalse(self.unusable("DRUID", WEAPON, 20, "INVTYPE_2HWEAPON"))  # fishing pole


class PlainGearTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Gear.lua",), base=False)

    def test_grey_and_white_gear(self):
        self.assertTrue(self.ns.IsPlainGear(0, ARMOR, CLOTH, "INVTYPE_CHEST"))
        self.assertTrue(self.ns.IsPlainGear(1, WEAPON, STAFF, "INVTYPE_2HWEAPON"))

    def test_green_and_better_not_plain(self):
        self.assertFalse(self.ns.IsPlainGear(2, ARMOR, CLOTH, "INVTYPE_CHEST"))
        self.assertFalse(self.ns.IsPlainGear(None, ARMOR, CLOTH, "INVTYPE_CHEST"))

    def test_shirts_tabards_fishing_poles_kept(self):
        self.assertFalse(self.ns.IsPlainGear(1, ARMOR, 0, "INVTYPE_BODY"))
        self.assertFalse(self.ns.IsPlainGear(1, ARMOR, 0, "INVTYPE_TABARD"))
        self.assertFalse(self.ns.IsPlainGear(1, WEAPON, 20, "INVTYPE_2HWEAPON"))

    def test_other_items_not_plain(self):
        self.assertFalse(self.ns.IsPlainGear(1, 0, 1, ""))


class DecideTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()
        self.db = self.rt.eval("KeepOrSellDB")

    def decide(self, **facts):
        prices = facts.pop("prices", {})
        facts.setdefault("quest", False)
        table = self.rt.table_from(facts)
        table.prices = self.rt.table_from(prices)
        return self.ns.Decide(table, self.db)

    def kind(self, **facts):
        return self.decide(**facts).kind

    FRESH_AH = {"ah": 1000, "vendor": 100, "age": 1, "hasAge": True}
    CHEAP = {"ah": 120, "vendor": 100, "age": 1, "hasAge": True}

    def test_quest_beats_everything(self):
        self.assertEqual(self.kind(quest="open", classID=7, prices=self.FRESH_AH), "quest")
        self.assertEqual(self.kind(classID=12), "quest")

    def test_profession_reagent_kept(self):
        self.assertEqual(self.kind(classID=7, reagent=True, prices=self.CHEAP), "profession")
        self.db.profession = False
        self.assertEqual(self.kind(classID=7, reagent=True, prices=self.CHEAP), "junk")

    def test_tradegoods(self):
        self.assertEqual(self.kind(classID=7, prices=self.FRESH_AH), "ah")
        self.assertEqual(self.kind(classID=7, prices=self.CHEAP), "junk")
        self.db.scrap = False
        self.assertIsNone(self.kind(classID=7, prices=self.CHEAP))

    def test_unknown_name_never_junk(self):
        self.assertIsNone(self.kind(quest=None, classID=7, prices=self.CHEAP))

    def test_tradegood_without_price_needs_price(self):
        verdict = self.decide(classID=7, prices={"vendor": 100})
        self.assertIsNone(verdict.kind)
        self.assertTrue(verdict.needsPrice)
        self.assertEqual(verdict.priceReason, "noprice")

    def test_wearable_gear_never_junk(self):
        verdict = self.decide(classID=4, equipLoc="INVTYPE_CHEST", prices=self.CHEAP)
        self.assertIsNone(verdict.kind)
        self.assertEqual(verdict.reason, "wearable")

    def test_wearable_gear_to_ah_when_tradeable_and_worth_it(self):
        self.assertEqual(self.kind(classID=4, equipLoc="INVTYPE_CHEST", prices=self.FRESH_AH), "ah")
        self.assertIsNone(self.kind(classID=4, equipLoc="INVTYPE_CHEST", bound=True, prices=self.FRESH_AH))

    def test_plain_wearable_gear(self):
        plain = {"classID": 4, "equipLoc": "INVTYPE_CHEST", "plain": True, "priceData": True}
        self.assertEqual(self.kind(prices=self.CHEAP, **plain), "junk")
        self.assertEqual(self.kind(prices={"vendor": 100}, **plain), "junk")  # nobody sells it on the AH
        self.assertEqual(self.kind(prices=self.FRESH_AH, **plain), "ah")
        self.assertEqual(self.kind(bound=True, prices=self.FRESH_AH, **plain), "junk")
        self.assertIsNone(self.kind(quest=None, prices=self.CHEAP, **plain))

    def test_plain_gear_stale_price_kept(self):
        plain = {"classID": 4, "equipLoc": "INVTYPE_CHEST", "plain": True, "priceData": True}
        self.assertIsNone(self.kind(prices={"ah": 120, "vendor": 100, "age": 9, "hasAge": True}, **plain))

    def test_plain_gear_without_price_data_kept(self):
        verdict = self.decide(classID=4, equipLoc="INVTYPE_CHEST", plain=True, priceData=False,
                              prices={"vendor": 100})
        self.assertIsNone(verdict.kind)
        self.assertTrue(verdict.needsPrice)

    def test_plain_gear_switch_off(self):
        self.db.plainGear = False
        self.assertIsNone(self.kind(classID=4, equipLoc="INVTYPE_CHEST", plain=True, priceData=True,
                                    prices=self.CHEAP))

    def test_unusable_gear(self):
        gear = {"classID": 4, "equipLoc": "INVTYPE_CHEST", "unusable": True}
        self.assertEqual(self.kind(prices=self.FRESH_AH, **gear), "ah")
        self.assertEqual(self.kind(prices=self.CHEAP, **gear), "junk")
        self.assertEqual(self.kind(bound=True, prices=self.FRESH_AH, **gear), "junk")
        verdict = self.decide(prices={"vendor": 100}, **gear)
        self.assertIsNone(verdict.kind)  # tradeable without known price: keep
        self.assertTrue(verdict.needsPrice)

    def test_unusable_gear_switch_off(self):
        self.db.gear = False
        self.assertIsNone(self.kind(classID=4, equipLoc="INVTYPE_CHEST", unusable=True, bound=True))

    def test_bound_item_not_for_ah(self):
        self.assertIsNone(self.kind(classID=0, bound=True, prices=self.FRESH_AH))

    def test_stale_price_reported_for_any_item(self):
        verdict = self.decide(classID=0, prices={"ah": 1000, "vendor": 100, "age": 9, "hasAge": True})
        self.assertIsNone(verdict.kind)
        self.assertTrue(verdict.needsPrice)

    def test_stale_price(self):
        verdict = self.decide(classID=7, prices={"ah": 120, "vendor": 100, "age": 9, "hasAge": True})
        self.assertIsNone(verdict.kind)
        self.assertEqual(verdict.priceReason, "stale")


class ClassRestrictionTests(unittest.TestCase):
    STUBS = """
    Enum = {TooltipDataLineType = {UsageRequirement = 43}, TooltipDataUsageRequirementType = {RaceClass = 0}}
    RED, WHITE = {r = 1, g = 0.125, b = 0.125}, {r = 1, g = 1, b = 1}
    LINES = {
      [12] = {{type = 22}, {type = 43, requirementType = 0, leftColor = RED}},   -- mage scroll, player is a druid
      [13] = {{type = 22}, {type = 43, requirementType = 0, leftColor = WHITE}}, -- druid item
      [14] = {{type = 22}, {type = 43, requirementType = 5, leftColor = RED}},   -- level too low only
    }
    ITEMS[12] = {"Scroll: KWYJIBO", 0, 8, "", 15}
    ITEMS[13] = {"Druid Scroll", 0, 8, "", 15}
    ITEMS[14] = {"High Level Potion", 0, 1, "", 15}
    C_TooltipInfo = {GetItemByID = function(id) CALLS = (CALLS or 0) + 1; return {lines = LINES[id] or {}} end}
    """

    def setUp(self):
        self.rt, self.ns = load(stubs=self.STUBS)

    def test_other_class_item_unusable(self):
        self.assertTrue(self.ns.ItemFacts(12, "link12").unusable)

    def test_own_class_or_level_requirement_usable(self):
        self.assertFalse(self.ns.ItemFacts(13, "link13").unusable)
        self.assertFalse(self.ns.ItemFacts(14, "link14").unusable)

    def test_other_class_item_to_ah_or_junk(self):
        self.rt.execute('AH.link12 = 100')
        self.assertEqual(self.ns.Classify(12, "link12").kind, "ah")
        self.rt.execute('AH.link12 = 16')
        self.ns.ClearCache()  # new prices arrive with a refresh
        self.assertEqual(self.ns.Classify(12, "link12").kind, "junk")

    def test_result_cached(self):
        self.ns.ItemFacts(12, "link12")
        self.ns.ItemFacts(12, "link12")
        self.assertEqual(self.rt.eval("CALLS"), 1)

    def test_not_loaded_asked_again(self):
        self.rt.execute("LINES[15] = nil")
        self.ns.ItemFacts(15, "link15")
        self.ns.ItemFacts(15, "link15")
        self.assertEqual(self.rt.eval("CALLS"), 2)


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(stubs="AH.link4 = 15; NOW = 0; GetTime = function() return NOW end")
        self.ns.items = self.rt.eval("{}")

    def test_cached_until_cleared(self):
        self.assertEqual(self.ns.Classify(4, "link4").kind, "junk")
        self.rt.execute("AH.link4 = 1000")
        self.assertEqual(self.ns.Classify(4, "link4").kind, "junk")
        self.ns.ClearCache()
        self.assertEqual(self.ns.Classify(4, "link4").kind, "ah")

    def test_expires_as_prices_age(self):
        self.ns.Classify(4, "link4")
        self.rt.execute("AH.link4 = 1000; NOW = 301")
        self.assertEqual(self.ns.Classify(4, "link4").kind, "ah")

    def test_bound_copy_cached_separately(self):
        self.rt.execute("AH.link3 = 1000; C_Item.IsBound = function(loc) return loc.bound end")
        self.assertEqual(self.ns.Classify(3, "link3", self.rt.eval("{bound = false}")).kind, "ah")
        self.assertIsNone(self.ns.Classify(3, "link3", self.rt.eval("{bound = true}")).kind)

    def test_unloaded_name_not_cached(self):
        self.rt.execute("ITEMS[4][1] = nil")
        self.assertIsNone(self.ns.Classify(4, "link4").kind)
        self.rt.execute("ITEMS[4][1] = 'Linen Cloth'")
        self.assertEqual(self.ns.Classify(4, "link4").kind, "junk")


class FactsTests(unittest.TestCase):
    def test_facts_from_api(self):
        rt, ns = load(stubs='BOUND[5] = true; AH["link5"] = 900')
        ns.items = rt.eval("{['Lean Wolf Flank'] = 'open'}")
        facts = ns.ItemFacts(5, "link5")
        self.assertEqual((facts.classID, facts.equipLoc, facts.unusable, facts.bound, facts.quest),
                         (4, "INVTYPE_CHEST", True, True, False))
        self.assertEqual(facts.prices.ah, 900)
        self.assertFalse(facts.plain)  # green
        self.assertTrue(ns.ItemFacts(10, "link10").plain)
        self.assertTrue(facts.priceData)
        self.assertEqual(ns.ItemFacts(1, "link1").quest, "open")

    def test_location_decides_binding(self):
        rt, ns = load(stubs="C_Item.IsBound = function(loc) return loc.bound end")
        self.assertTrue(ns.ItemFacts(5, "link5", rt.eval("{bound = true}")).bound)
        self.assertFalse(ns.ItemFacts(5, "link5", rt.eval("{bound = false}")).bound)


if __name__ == "__main__":
    unittest.main()
