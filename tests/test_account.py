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

    def test_current_ruleset_unknown_without_rule_keys(self):
        self.rt.execute(GAME_RULES + "ACTIVE_RULE = 1; Enum.GameRule = {}")
        self.assertIsNone(self.ns.CurrentRuleset())

    def test_record_character_keeps_ruleset_when_unknown(self):
        self.rt.execute("KeepOrSellDB.characters = {['Tester-Realm'] = {faction = 'Alliance', ruleset = 'PvP'}}")
        self.ns.RecordCharacter()
        self.assertEqual(self.rt.eval("KeepOrSellDB.characters['Tester-Realm'].ruleset"), "PvP")

    def test_migrated_alt_matches_by_realm_of_its_key(self):
        self.rt.execute("function UnitFactionGroup() return 'Alliance' end")
        self.rt.execute("KeepOrSellDB.factions = {['Bob-Realm'] = 'Alliance'}; KeepOrSellDB.recipes = {['Bob-Realm'] = {[1] = {3}}}")
        self.ns.RecordCharacter()
        self.assertEqual([a.name for a in self.ns.AltsNeedingItem(3).values()], ["Bob"])

    def test_record_character_rebuilds_the_index(self):
        self.rt.execute("function UnitFactionGroup() return 'Alliance' end")
        self.rt.execute("""KeepOrSellDB.characters = {['Bob-Realm'] = {faction = 'Alliance', realm = 'Realm'}}
          KeepOrSellDB.recipes = {['Bob-Realm'] = {[1] = {3}}}""")
        self.assertIsNone(self.ns.AltsNeedingItem(3))  # own record not written yet
        self.ns.RecordCharacter()
        self.assertEqual([a.name for a in self.ns.AltsNeedingItem(3).values()], ["Bob"])

    def test_character_key_has_the_surname_on_forever(self):
        self.rt.execute("function UnitName() return 'Drache', 'Offiziell' end")
        self.assertEqual(self.ns.CharacterKey(), "Drache-Realm")  # no regional names: second value isn't a surname
        self.rt.execute("RegionalUniqueNamesEnabled = function() return true end")
        self.assertEqual(self.ns.CharacterKey(), "Drache Offiziell-Realm")
        self.rt.execute("function UnitName() return 'Drache', nil end")
        self.assertEqual(self.ns.CharacterKey(), "Drache-Realm")

    def test_move_character_data(self):
        db = self.rt.eval("""{recipes = {['Drache-Realm'] = {[1] = {3}}}, opened = {['Drache-Realm'] = {Tailoring = true}},
          crafts = {['Drache-Realm'] = {}, ['Drache Offiziell-Realm'] = {kept = true}},
          altSettings = {['Drache-Realm'] = {included = false}}, baganatorSetup = {['Drache-Realm'] = true}}""")
        self.ns.MoveCharacterData(db, "Drache-Realm", "Drache Offiziell-Realm")
        self.assertIsNone(db.recipes["Drache-Realm"])
        self.assertEqual(db.recipes["Drache Offiziell-Realm"][1][1], 3)
        self.assertTrue(db.opened["Drache Offiziell-Realm"].Tailoring)
        self.assertTrue(db.crafts["Drache Offiziell-Realm"].kept)  # newer data stays
        self.assertIs(db.altSettings["Drache Offiziell-Realm"].included, False)
        self.assertTrue(db.baganatorSetup["Drache Offiziell-Realm"])
        self.ns.MoveCharacterData(db, "Same-Realm", "Same-Realm")  # nothing to do

    def test_record_character_moves_data_to_the_full_name(self):
        self.rt.execute("""function UnitName() return 'Drache', 'Offiziell' end
          RegionalUniqueNamesEnabled = function() return true end
          KeepOrSellDB.recipes = {['Drache-Realm'] = {[1] = {3}}}
          KeepOrSellDB.characters = {['Drache-Realm'] = {faction = 'Horde'}}""")
        self.ns.RecordCharacter()
        self.assertEqual(self.rt.eval("KeepOrSellDB.recipes['Drache Offiziell-Realm'][1][1]"), 3)
        self.assertIsNone(self.rt.eval("KeepOrSellDB.recipes['Drache-Realm']"))
        self.assertIsNone(self.rt.eval("KeepOrSellDB.characters['Drache-Realm']"))
        self.assertEqual(self.rt.eval("KeepOrSellDB.characters['Drache Offiziell-Realm'].faction"), "Horde")

    def test_full_names_listed(self):
        characters = self.rt.eval("""{['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm'},
          ['Drache Offiziell-Realm'] = {faction = 'Alliance', realm = 'Realm'}}""")
        me = self.rt.eval("{key = 'Tester-Realm', faction = 'Alliance', realm = 'Realm'}")
        self.assertEqual(self.ns.AltCharacters(characters, me)[1].name, "Drache Offiziell")

    def test_record_character_remembers_its_professions(self):
        # prof1, prof2, archaeology, fishing, cooking, first aid; a gap where a slot is empty
        self.rt.execute("""
          function GetProfessions() return 1, nil, nil, 4, 5 end
          PROFS = {[1] = {"Schneiderei", 136249}, [4] = {"Angeln", 136245}, [5] = {"Kochkunst", 133971}}
          function GetProfessionInfo(i) return PROFS[i][1], PROFS[i][2] end""")
        self.ns.RecordCharacter()
        professions = self.rt.eval("KeepOrSellDB.characters['Tester-Realm'].professions")
        self.assertEqual(dict(professions.items()), {"Schneiderei": 136249, "Angeln": 136245, "Kochkunst": 133971})

    def test_record_character_keeps_professions_while_unknown(self):
        self.rt.execute("function GetProfessions() end")
        self.rt.execute("KeepOrSellDB.characters = {['Tester-Realm'] = {professions = {Bergbau = 1}}}")
        self.ns.RecordCharacter()
        self.assertEqual(self.rt.eval("KeepOrSellDB.characters['Tester-Realm'].professions.Bergbau"), 1)

    def test_class_item_ids(self):
        self.assertEqual(list(self.ns.ClassItemIDs("PRIEST", False).values()), [17028, 17029, 17056])
        self.assertEqual(list(self.ns.ClassItemIDs("PRIEST", True).values()), [17056])
        self.assertEqual(len(self.ns.ClassItemIDs("WARRIOR", False)), 0)
        self.assertEqual(len(self.ns.ClassItemIDs(None, False)), 0)


class AltIndexTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def index(self, me="Tester-Realm", amy_reagent_economy=False):
        recipes = self.rt.eval("""{
          ["Tester-Realm"] = {[1] = {4}},
          ["Bob-Realm"] = {[1] = {3}, [2] = false},
          ["Amy-Realm"] = {[1] = {3}, [5] = {20}},
          ["Hordie-Realm"] = {[1] = {21}},
          ["Far-Other"] = {[1] = {22}},
        }""")
        crafts = self.rt.eval("{['Bob-Realm'] = {[9] = {output = 3, reagents = {40}}}}")
        professions = self.rt.eval("{['Bob-Realm'] = {[1] = 'Tailoring'}, ['Amy-Realm'] = {[1] = 'Tailoring'}}")
        characters = self.rt.eval(f"""{{
          ["Tester-Realm"] = {{faction = "Alliance", ruleset = "PvE", realm = "Realm", class = "DRUID"}},
          ["Bob-Realm"] = {{faction = "Alliance", ruleset = "PvE", realm = "Realm", class = "WARRIOR"}},
          ["Amy-Realm"] = {{faction = "Alliance", ruleset = "PvE", realm = "Realm", class = "PRIEST",
                           reagentEconomy = {'true' if amy_reagent_economy else 'false'}}},
          ["Hordie-Realm"] = {{faction = "Horde", ruleset = "PvE", realm = "Realm", class = "ROGUE"}},
          ["Far-Other"] = {{faction = "Alliance", ruleset = "HC", realm = "Other", class = "MAGE"}},
        }}""")
        self.raw = self.ns.AltIndex(characters, recipes, crafts, professions, me)
        return self.raw

    def names(self, alts):
        return [a.name for a in alts.values()]

    def test_profession_needs_name_the_profession(self):
        index = self.index()
        self.assertEqual([(a.name, list(a.professions.values()), a.profession) for a in index[3].values()],
                         [("Amy", ["Tailoring"], True), ("Bob", ["Tailoring"], True)])
        self.assertEqual(self.names(index[40]), ["Bob"])  # crafted into silk first

    def test_recipe_without_profession_counts_unnamed(self):
        alt = self.index()[20][1]
        self.assertEqual((alt.name, len(alt.professions), alt.profession), ("Amy", 0, True))

    def test_class_items_follow_the_alts_class_and_reagent_economy(self):
        candle = self.index()[17028][1]
        self.assertEqual((candle.name, candle["class"], candle.profession), ("Amy", True, False))
        self.assertNotIn(17028, self.index(amy_reagent_economy=True))
        self.assertIn(17056, self.index(amy_reagent_economy=True))  # Light Feather stays

    def test_left_out(self):
        index = self.index()
        for item_id in (4, 21, 22, 5530):  # own, other faction, other ruleset, Horde rogue's powder
            self.assertNotIn(item_id, index)

    def test_index_without_own_record_is_empty(self):
        self.assertEqual(len(self.index(me="Nobody-Realm")), 0)

    def filtered(self, item_id, settings="{}", account_mode=True):
        db = self.rt.table_from({"accountMode": account_mode, "altSettings": self.rt.eval(settings)})
        result = self.ns.FilterAlts(self.raw[item_id], db)
        return result and self.names(result)

    def test_filter_alts_reads_per_alt_settings(self):
        self.index()
        self.assertEqual(self.filtered(3, "{['Amy-Realm'] = {included = false}}"), ["Bob"])
        self.assertEqual(self.filtered(3, "{['Amy-Realm'] = {included = true}}"), ["Amy", "Bob"])
        self.assertEqual(self.filtered(3, "{['Amy-Realm'] = {profession = false}}"), ["Bob"])
        self.assertEqual(self.filtered(17028), ["Amy"])
        self.assertEqual(self.filtered(17028, "{['Amy-Realm'] = {profession = false}}"), ["Amy"])
        self.assertIsNone(self.filtered(17028, "{['Amy-Realm'] = {classItems = false}}"))
        self.assertIsNone(self.filtered(3, account_mode=False))
        self.assertIsNone(self.ns.FilterAlts(None, self.rt.table_from({"accountMode": True})))
        self.assertEqual(self.names(self.raw[3]), ["Amy", "Bob"])  # index untouched

    def test_filter_alts_drops_the_switched_off_reason(self):
        self.rt.execute("""TEST_ALTS = {{key = 'Amy-Realm', name = 'Amy', professions = {'Tailoring'},
          profession = true, class = true}}""")
        db = self.rt.eval("{accountMode = true, altSettings = {['Amy-Realm'] = {profession = false}}}")
        alt = self.ns.FilterAlts(self.rt.eval("TEST_ALTS"), db)[1]
        self.assertEqual((len(alt.professions), alt.profession, alt["class"]), (0, False, True))
        self.assertEqual(self.rt.eval("#TEST_ALTS[1].professions"), 1)

    def test_migrates_released_alt_reagents(self):
        db = self.rt.eval("{altReagents = false, characters = {['Bob-Realm'] = {}}, recipes = {['Amy-Realm'] = {}}}")
        self.ns.MigrateAltSettings(db)
        self.assertIs(db.altSettings["Bob-Realm"].profession, False)
        self.assertIs(db.altSettings["Amy-Realm"].profession, False)
        self.assertIsNone(db.altSettings["Bob-Realm"].classItems)
        self.assertIsNone(db.altReagents)

    def test_migrates_branch_switches_and_exclusions(self):
        db = self.rt.eval("""{altClassItems = false, altProfession = true, altIncluded = {['Bob-Realm'] = false},
          characters = {['Bob-Realm'] = {}, ['Amy-Realm'] = {}}, altSettings = {['Amy-Realm'] = {classItems = true}}}""")
        self.ns.MigrateAltSettings(db)
        self.assertIs(db.altSettings["Bob-Realm"].included, False)
        self.assertIs(db.altSettings["Bob-Realm"].classItems, False)
        self.assertIsNone(db.altSettings["Bob-Realm"].profession)
        self.assertIs(db.altSettings["Amy-Realm"].classItems, True)  # existing value wins
        for key in ("altIncluded", "altClassItems", "altProfession"):
            self.assertIsNone(db[key], key)

    def test_migration_without_old_keys_changes_nothing(self):
        db = self.rt.eval("{characters = {['Bob-Realm'] = {}}}")
        self.ns.MigrateAltSettings(db)
        self.assertTrue(db.altSettings is None or db.altSettings["Bob-Realm"] is None)

    def test_lookup_reads_the_saved_variables(self):
        self.rt.execute("""KeepOrSellDB.characters = {
          ['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm'},
          ['Bob-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'WARRIOR'}}
          KeepOrSellDB.recipes = {['Bob-Realm'] = {[1] = {3}}}""")
        self.assertEqual(self.names(self.ns.AltsNeedingItem(3)), ["Bob"])
        self.assertIsNone(self.ns.AltsNeedingItem(4))


class AltRowsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def test_alt_rows(self):
        characters = self.rt.eval("""{['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm'},
          ['Amy-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'PRIEST'},
          ['Bob-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'MAGE'}}""")
        professions = self.rt.eval("{['Amy-Realm'] = {[1] = 'Tailoring', [2] = 'Enchanting', [3] = 'Tailoring'}}")
        settings = self.rt.eval("{['Bob-Realm'] = {included = false}}")
        me = self.rt.eval("{key = 'Tester-Realm', faction = 'Alliance', realm = 'Realm'}")
        rows = self.ns.AltRows(characters, professions, settings, me)
        self.assertTrue(rows[1].isSelf)
        table_remove = self.rt.eval("function(t) table.remove(t, 1) return t end")
        rows = table_remove(rows)
        self.assertEqual([(r.name, r["class"], r.professions, r.included, r.profession, r.classItems)
                          for r in rows.values()],
                         [("Amy", "PRIEST", "Enchanting, Tailoring", True, True, True),
                          ("Bob", "MAGE", None, False, True, True)])
        self.assertEqual(list(rows[1].professionList.values()), ["Enchanting", "Tailoring"])
        self.assertEqual(len(rows[2].professionList), 0)

    def test_alt_rows_start_with_me_and_prefer_recorded_professions(self):
        characters = self.rt.eval("""{['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'DRUID',
            professions = {Kochkunst = 133971}},
          ['Amy-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'PRIEST', professions = {Angeln = 136245}}}""")
        professions = self.rt.eval("{['Amy-Realm'] = {[1] = 'Tailoring'}}")
        me = self.rt.eval("{key = 'Tester-Realm', faction = 'Alliance', realm = 'Realm'}")
        rows = self.ns.AltRows(characters, professions, self.rt.eval("{}"), me)
        self.assertEqual([(r.name, bool(r.isSelf)) for r in rows.values()], [("Tester", True), ("Amy", False)])
        self.assertEqual(list(rows[1].professionList.values()), ["Kochkunst"])
        self.assertEqual(list(rows[2].professionList.values()), ["Angeln"])  # the recorded list wins
        self.assertEqual(rows[2].professionIcons["Angeln"], 136245)

    def test_pool_text(self):
        pool = lambda **kw: self.ns.PoolText(self.rt.table_from(kw))
        self.assertEqual(pool(ruleset="PvP", faction="Horde"), "PvP · Horde")
        self.assertEqual(pool(realm="Realm", faction="Horde"), "Realm · Horde")
        self.rt.execute("FACTION_HORDE = 'Horde (de)'")
        self.assertEqual(pool(ruleset="PvP", faction="Horde"), "PvP · Horde (de)")


class AltCharactersTests(unittest.TestCase):
    def test_lists_the_pool_sorted_without_me(self):
        rt, ns = load()
        characters = rt.eval("""{['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm'},
          ['Bob-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'MAGE'},
          ['Amy-Realm'] = {faction = 'Alliance', ruleset = 'PvE', realm = 'Realm', class = 'PRIEST'},
          ['Hordie-Realm'] = {faction = 'Horde', realm = 'Realm', class = 'ROGUE'}}""")
        me = rt.eval("{key = 'Tester-Realm', faction = 'Alliance', realm = 'Realm'}")
        alts = ns.AltCharacters(characters, me)
        self.assertEqual([(a.key, a.name, a["class"]) for a in alts.values()],
                         [("Amy-Realm", "Amy", "PRIEST"), ("Bob-Realm", "Bob", "MAGE")])


if __name__ == "__main__":
    unittest.main()
