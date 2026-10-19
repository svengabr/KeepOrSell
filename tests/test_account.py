"""Tests for account mode: character records, ruleset and alt matching (Account.lua)."""
import unittest

from addon import load

GAME_RULES = """
RegionalUniqueNamesEnabled = function() return true end
Enum = Enum or {}
Enum.GameRule = {PvPRuleset = 1, RPRuleset = 2, HardcoreRuleset = 3}
C_GameRules = {IsGameRuleActive = function(r) return r == ACTIVE_RULE end}
"""


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def rec(self, **kw):
        return self.rt.table_from(kw)

    def test_ruleset_name(self):
        def active(on):
            return self.rt.eval(f"function(k) return k == '{on}' end")
        self.assertEqual(self.ns.RulesetName(active("PvPRuleset")), "PvP")
        self.assertEqual(self.ns.RulesetName(active("RPRuleset")), "RP")
        self.assertEqual(self.ns.RulesetName(active("HardcoreRuleset")), "HC")
        self.assertEqual(self.ns.RulesetName(active("none")), "PvE")

    def test_current_ruleset_needs_regional_names(self):
        self.assertIsNone(self.ns.CurrentRuleset())
        self.rt.execute(GAME_RULES + "ACTIVE_RULE = 2")
        self.assertEqual(self.ns.CurrentRuleset(), "RP")
        self.rt.execute("RegionalUniqueNamesEnabled = function() return false end")
        self.assertIsNone(self.ns.CurrentRuleset())

    def test_same_pool(self):
        me = self.rec(faction="Alliance", ruleset="PvE", realm="A")
        self.assertTrue(self.ns.SamePool(me, self.rec(faction="Alliance", ruleset="PvE", realm="B")))
        self.assertFalse(self.ns.SamePool(me, self.rec(faction="Horde", ruleset="PvE", realm="A")))
        self.assertFalse(self.ns.SamePool(me, self.rec(faction="Alliance", ruleset="HC", realm="A")))

    def test_old_record_matches_by_realm(self):
        me = self.rec(faction="Alliance", ruleset="PvE", realm="A")
        self.assertTrue(self.ns.SamePool(me, self.rec(faction="Alliance", realm="A")))
        self.assertFalse(self.ns.SamePool(me, self.rec(faction="Alliance", realm="B")))

    def test_unknown_own_faction_matches_nobody(self):
        self.assertFalse(self.ns.SamePool(self.rec(ruleset="PvE", realm="A"),
                                          self.rec(faction="Alliance", ruleset="PvE", realm="A")))

    def test_record_character_migrates_factions(self):
        self.rt.execute("function UnitFactionGroup() return 'Horde' end")
        self.rt.execute("KeepOrSellDB.factions = {['Bob-Realm'] = 'Alliance', ['Tester-Realm'] = 'Alliance'}")
        self.ns.RecordCharacter()
        me = self.rt.eval("KeepOrSellDB.characters['Tester-Realm']")
        self.assertEqual((me.faction, me["class"], me.realm, me.ruleset, me.reagentEconomy),
                         ("Horde", "DRUID", "Realm", None, False))
        self.assertEqual(self.rt.eval("KeepOrSellDB.characters['Bob-Realm'].faction"), "Alliance")
        self.assertIsNone(self.rt.eval("KeepOrSellDB.factions"))

    def test_record_character_keeps_faction_when_unknown(self):
        self.rt.execute("function UnitFactionGroup() return nil end")
        self.rt.execute("KeepOrSellDB.characters = {['Tester-Realm'] = {faction = 'Alliance'}}")
        self.ns.RecordCharacter()
        self.assertEqual(self.rt.eval("KeepOrSellDB.characters['Tester-Realm'].faction"), "Alliance")

    def test_class_item_ids(self):
        self.assertEqual(list(self.ns.ClassItemIDs("PRIEST", False).values()), [17028, 17029, 17056])
        self.assertEqual(list(self.ns.ClassItemIDs("PRIEST", True).values()), [17056])
        self.assertEqual(len(self.ns.ClassItemIDs("WARRIOR", False)), 0)
        self.assertEqual(len(self.ns.ClassItemIDs(None, False)), 0)


if __name__ == "__main__":
    unittest.main()
