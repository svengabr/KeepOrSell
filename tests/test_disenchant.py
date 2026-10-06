"""Tests for the disenchant group (Disenchant.lua, Classify.lua, Tooltip.lua)."""
import unittest

from addon import CORE_FILES, load

WEAPON, ARMOR = 2, 4
UNCOMMON, RARE, EPIC = 2, 3, 4
STRANGE_DUST, LESSER_MAGIC, GREATER_MAGIC, SMALL_GLIMMERING = 10940, 10938, 10939, 10978
LARGE_BRILLIANT, NEXUS, ILLUSION_DUST = 14344, 20725, 16204

FILES = CORE_FILES[:-1] + ("Disenchant.lua", "Classify.lua")


def outcome_map(outcomes):
    """{itemID: (chance, min, max)} from a Lua outcome list."""
    if outcomes is None:
        return None
    return {o.itemID: (round(o.chance, 4), o.min, o.max) for o in outcomes.values()}


class OutcomeTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def outcomes(self, quality, level, class_id):
        return outcome_map(self.ns.DisenchantOutcomes(quality, level, class_id))

    def test_low_uncommon_armor_mostly_dust(self):
        self.assertEqual(self.outcomes(UNCOMMON, 10, ARMOR),
                         {STRANGE_DUST: (0.8, 1, 2), LESSER_MAGIC: (0.2, 1, 2)})

    def test_low_uncommon_weapon_mostly_essence(self):
        self.assertEqual(self.outcomes(UNCOMMON, 15, WEAPON),
                         {STRANGE_DUST: (0.2, 1, 2), LESSER_MAGIC: (0.8, 1, 2)})

    def test_level_boundary_switches_row(self):
        # item level 16 is the first row with a shard
        self.assertEqual(self.outcomes(UNCOMMON, 16, WEAPON),
                         {STRANGE_DUST: (0.2, 2, 3), GREATER_MAGIC: (0.75, 1, 2), SMALL_GLIMMERING: (0.05, 1, 1)})

    def test_rare_gives_a_shard_and_rarely_a_crystal(self):
        self.assertEqual(self.outcomes(RARE, 20, ARMOR), {SMALL_GLIMMERING: (1.0, 1, 1)})
        self.assertEqual(self.outcomes(RARE, 60, WEAPON), {LARGE_BRILLIANT: (0.995, 1, 1), NEXUS: (0.005, 1, 1)})

    def test_epic(self):
        self.assertEqual(self.outcomes(EPIC, 60, ARMOR), {NEXUS: (1.0, 1, 1)})
        self.assertEqual(self.outcomes(EPIC, 70, ARMOR), {NEXUS: (1.0, 1, 2)})

    def test_above_the_table_uses_the_last_row(self):
        self.assertEqual(self.outcomes(UNCOMMON, 80, ARMOR)[ILLUSION_DUST], (0.75, 2, 5))

    def test_nothing_for_other_items(self):
        self.assertIsNone(self.outcomes(1, 20, ARMOR))      # white
        self.assertIsNone(self.outcomes(5, 60, WEAPON))     # legendary
        self.assertIsNone(self.outcomes(UNCOMMON, 20, 7))   # trade goods
        self.assertIsNone(self.outcomes(UNCOMMON, None, ARMOR))

    def test_sorted_by_chance(self):
        outcomes = self.ns.DisenchantOutcomes(UNCOMMON, 16, ARMOR)
        self.assertEqual([o.itemID for o in outcomes.values()], [STRANGE_DUST, GREATER_MAGIC, SMALL_GLIMMERING])


class ValueTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def value(self, quality, level, class_id, prices):
        outcomes = self.ns.DisenchantOutcomes(quality, level, class_id)
        price_of = self.rt.eval("function(p) return function(id) return p[id] end end")(self.rt.table_from(prices))
        return self.ns.DisenchantValue(outcomes, price_of)

    def test_average_value(self):
        # 80% x 1.5 x 100 + 20% x 1.5 x 300 = 120 + 90
        self.assertEqual(self.value(UNCOMMON, 10, ARMOR, {STRANGE_DUST: 100, LESSER_MAGIC: 300}), 210)

    def test_missing_main_price_makes_it_unknown(self):
        self.assertIsNone(self.value(UNCOMMON, 10, ARMOR, {STRANGE_DUST: 100}))

    def test_missing_rare_price_counts_as_zero(self):
        # 20% x 2.5 x 100 + 75% x 1.5 x 200, the 5% shard has no price
        self.assertEqual(self.value(UNCOMMON, 16, WEAPON, {STRANGE_DUST: 100, GREATER_MAGIC: 200}), 275)

    def test_skill_up_material(self):
        self.ns.IsSkillUpReagent = self.rt.eval("function(id) return id == %d end" % GREATER_MAGIC)
        self.assertTrue(self.ns.DisenchantSkillUp(self.ns.DisenchantOutcomes(UNCOMMON, 16, WEAPON)))
        self.assertFalse(self.ns.DisenchantSkillUp(self.ns.DisenchantOutcomes(UNCOMMON, 10, WEAPON)))


class DecideTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)
        self.db = self.rt.eval("KeepOrSellDB")
        self.db.disenchant = True

    def decide(self, disenchant=None, **facts):
        prices = facts.pop("prices", {})
        facts.setdefault("quest", False)
        table = self.rt.table_from(facts)
        table.prices = self.rt.table_from(prices)
        if disenchant is not None:
            table.disenchant = self.rt.table_from(disenchant)
        return self.ns.Decide(table, self.db)

    UNUSABLE = {"classID": WEAPON, "equipLoc": "INVTYPE_WEAPON", "unusable": True}
    # the hammer from the screenshot: AH 7s, vendor 6s 12c
    HAMMER = {"ah": 700, "vendor": 612, "age": 1, "hasAge": True}

    def test_bound_junk_becomes_disenchant(self):
        verdict = self.decide(disenchant={"value": 900}, bound=True, prices={"vendor": 612}, **self.UNUSABLE)
        self.assertEqual(verdict.kind, "disenchant")

    def test_bound_without_value_is_kept_for_disenchanting(self):
        self.assertEqual(self.decide(disenchant={}, bound=True, prices={"vendor": 612}, **self.UNUSABLE).kind,
                         "disenchant")

    def test_bound_worth_less_than_vendor_stays_junk(self):
        self.assertEqual(self.decide(disenchant={"value": 300}, bound=True, prices={"vendor": 612},
                                     **self.UNUSABLE).kind, "junk")

    def test_tradeable_disenchant_beats_auction(self):
        self.assertEqual(self.decide(disenchant={"value": 900}, prices=self.HAMMER, **self.UNUSABLE).kind,
                         "disenchant")

    def test_tradeable_auction_beats_disenchant(self):
        worth = {"ah": 5000, "vendor": 612, "age": 1, "hasAge": True}
        self.assertEqual(self.decide(disenchant={"value": 900}, prices=worth, **self.UNUSABLE).kind, "ah")

    def test_auction_cut_counts(self):
        # 1000 after the 5% cut is 950, below 960
        worth = {"ah": 1000, "vendor": 100, "age": 1, "hasAge": True}
        self.assertEqual(self.decide(disenchant={"value": 960}, prices=worth, **self.UNUSABLE).kind, "disenchant")

    def test_tradeable_without_value_keeps_todays_verdict(self):
        self.assertEqual(self.decide(disenchant={}, prices=self.HAMMER, **self.UNUSABLE).kind, "junk")

    def test_tradeable_without_auction_price(self):
        verdict = self.decide(disenchant={"value": 900}, prices={"vendor": 612}, **self.UNUSABLE)
        self.assertEqual(verdict.kind, "disenchant")

    def test_skill_up_always_wins(self):
        worth = {"ah": 5000, "vendor": 612, "age": 1, "hasAge": True}
        verdict = self.decide(disenchant={"value": 100, "skillUp": True}, prices=worth, **self.UNUSABLE)
        self.assertEqual(verdict.kind, "disenchant")
        self.assertTrue(verdict.forSkill)

    def test_not_for_skill_when_also_worth_more(self):
        verdict = self.decide(disenchant={"value": 9000, "skillUp": True}, prices=self.HAMMER, **self.UNUSABLE)
        self.assertEqual(verdict.kind, "disenchant")
        self.assertIsNone(verdict.forSkill)

    def test_not_for_skill_when_value_unknown(self):
        verdict = self.decide(disenchant={"skillUp": True}, prices=self.HAMMER, **self.UNUSABLE)
        self.assertIsNone(verdict.forSkill)

    def test_wearable_gear_kept_untouched(self):
        verdict = self.decide(disenchant={"value": 900}, classID=ARMOR, equipLoc="INVTYPE_CHEST",
                              prices=self.HAMMER)
        self.assertIsNone(verdict.kind)

    def test_wearable_gear_for_auction_may_be_disenchanted(self):
        worth = {"ah": 1500, "vendor": 612, "age": 1, "hasAge": True}
        self.assertEqual(self.decide(disenchant={"value": 2000}, classID=ARMOR, equipLoc="INVTYPE_CHEST",
                                     prices=worth).kind, "disenchant")

    def test_option_off(self):
        self.db.disenchant = False
        self.assertEqual(self.decide(disenchant={"value": 900}, bound=True, prices={"vendor": 612},
                                     **self.UNUSABLE).kind, "junk")

    def test_no_enchanter_no_facts(self):
        self.assertEqual(self.decide(bound=True, prices={"vendor": 612}, **self.UNUSABLE).kind, "junk")

    def test_quest_item_untouched(self):
        self.assertEqual(self.decide(disenchant={"value": 900}, quest="open", **self.UNUSABLE).kind, "quest")


ENCHANTER = """
ITEMS[20] = {"Reliable Sword", 2, 7, "INVTYPE_WEAPON", 612, 2, 15}
ITEMS[10940] = {"Strange Dust", 7, 12, "", 25, 1}
ITEMS[10938] = {"Lesser Magic Essence", 7, 12, "", 40, 2}
BOUND[20] = true
ITEMS[21] = {"Linen Cloak", 4, 1, "INVTYPE_CLOAK", 67, 2, 12}
BOUND[21] = true
PROFESSIONS = {333}
function GetProfessions() return 1 end
function GetProfessionInfo(i) return "Enchanting", 0, 40, 75, 0, 0, PROFESSIONS[i] end
OWN = {}
Auctionator.API.v1.GetAuctionPriceByItemID = function(_, id) return OWN[id] end
Auctionator.API.v1.GetAuctionAgeByItemID = function() return 1 end
function GetMoneyString(copper) return copper .. "c" end
"""


class FactsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES + ("Tooltip.lua",), ENCHANTER)
        self.db = self.rt.eval("KeepOrSellDB")
        self.db.disenchant = True

    def test_enchanter_gets_disenchant_facts(self):
        self.rt.execute("OWN[10940] = 300; OWN[10938] = 600")
        facts = self.ns.ItemFacts(20, "link20")
        self.assertEqual(facts.disenchant.value, 810)  # weapon: 20% x 1.5 x 300 + 80% x 1.5 x 600
        self.assertEqual(self.ns.Decide(facts, self.db).kind, "disenchant")

    def test_stale_material_price_is_unknown(self):
        self.rt.execute("OWN[10940] = 100; OWN[10938] = 300")
        self.rt.execute("Auctionator.API.v1.GetAuctionAgeByItemID = function() return 15 end")
        self.assertIsNone(self.ns.ItemFacts(20, "link20").disenchant.value)

    def test_not_an_enchanter(self):
        self.rt.execute("PROFESSIONS = {197}")
        self.assertIsNone(self.ns.ItemFacts(20, "link20").disenchant)

    def test_tooltip_lists_chances_and_prices(self):
        self.rt.execute("OWN[10940] = 300; OWN[10938] = 600")
        facts = self.ns.ItemFacts(20, "link20")
        text = self.ns.TooltipText(self.ns.Decide(facts, self.db), facts.prices, self.db)
        self.assertIn("Disenchant ~810c\n"
                      "    |cffaaaaaa80% Lesser Magic Essence ×1–2|r\n"
                      "    |cffaaaaaa20% Strange Dust ×1–2|r\n"
                      "    |cffaaaaaasoulbound, vendor 612c|r", text)

    def test_tooltip_without_value(self):
        facts = self.ns.ItemFacts(20, "link20")
        text = self.ns.TooltipText(self.ns.Decide(facts, self.db), facts.prices, self.db)
        self.assertIn("Disenchant\n    |cffaaaaaa80% Lesser Magic Essence", text)

    def test_tooltip_names_the_skill_up_material(self):
        self.rt.execute("function ns_skill(id) return id == 10940 end")
        self.ns.IsSkillUpReagent = self.rt.eval("ns_skill")
        facts = self.ns.ItemFacts(20, "link20")
        text = self.ns.TooltipText(self.ns.Decide(facts, self.db), facts.prices, self.db)
        self.assertIn("20% Strange Dust ×1–2 – still gives skill points|r", text)
        self.assertNotIn("Essence ×1–2 – still", text)

    def test_tooltip_for_skill_headline(self):
        # materials worth 30c on average, the vendor pays 612c
        self.rt.execute("OWN[10940] = 20; OWN[10938] = 20")
        self.ns.IsSkillUpReagent = self.rt.eval("function(id) return id == 10938 end")
        facts = self.ns.ItemFacts(20, "link20")
        text = self.ns.TooltipText(self.ns.Decide(facts, self.db), facts.prices, self.db)
        self.assertIn("Disenchant for skill points ~30c (selling pays more)\n", text)


    def tooltip(self, item_id):
        facts = self.ns.ItemFacts(item_id, "link%d" % item_id)
        return self.ns.TooltipText(self.ns.Decide(facts, self.db), facts.prices, self.db)

    def test_wearable_hint_disenchant(self):
        # cloth cloak: 80% x 1.5 x 229 + 20% x 1.5 x 300 = 365
        self.rt.execute("OWN[10940] = 229; OWN[10938] = 300")
        self.assertIn("Keep – wearable\n    |cffaaaaaaIf you no longer need it: Disenchant ~365c (vendor 67c)|r",
                      self.tooltip(21))

    def test_wearable_hint_auction_house(self):
        # below the 2x threshold, so the cloak stays, but the AH still pays more than the vendor
        self.rt.execute("PROFESSIONS = {197}; BOUND[21] = nil; AH.link21 = 100")
        self.assertIn("If you no longer need it: auction house 100c (vendor 67c)", self.tooltip(21))

    def test_wearable_hint_bound_ignores_auction_house(self):
        self.rt.execute("PROFESSIONS = {197}; AH.link21 = 100")
        text = self.tooltip(21)
        self.assertIn("If you no longer need it: vendor 67c|r", text)
        self.assertNotIn("auction", text)

    def test_wearable_hint_compares_all(self):
        self.rt.execute("OWN[10940] = 229; OWN[10938] = 300; BOUND[21] = nil; AH.link21 = 100")
        self.assertIn("If you no longer need it: Disenchant ~365c (auction house 100c, vendor 67c)", self.tooltip(21))


if __name__ == "__main__":
    unittest.main()
