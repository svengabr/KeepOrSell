"""Tests for the shareable filter parser (Filter.lua)."""
import unittest

from addon import load

EXAMPLE = """KeepOrSell filter 1
name = Leveling
# lines starting with # are comments; text after # on a line is ignored
factor = 3
minProfit = 5
maxAge = 7
recipeJunk = on
keep = 2589, 4306
item 2592 = junk        # Wool Cloth
item 4338 = ah          # Mageweave Cloth
class 7 subclass 5 quality 0-1 = junk   # Trade Goods: Cloth, grey and white
class 0 subclass 5 = keep              # Consumable: Food & Drink
"""


class FilterTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Prices.lua", "Filter.lua"))

    def parse(self, text):
        return self.ns.ParseFilter(text)

    def lst(self, t):
        return [t[i] for i in range(1, len(t) + 1)]

    def test_header_required(self):
        self.assertEqual(tuple(self.parse("factor = 3")), (None, "noheader"))
        self.assertEqual(tuple(self.parse("KeepOrSell filter 2\n")), (None, "version"))
        self.assertEqual(tuple(self.parse("x" * (65 * 1024))), (None, "toolong"))

    def test_full_example(self):
        f, report = self.parse(EXAMPLE)
        self.assertEqual(f.name, "Leveling")
        self.assertEqual(f.options.factor, 3)
        self.assertEqual(f.options.minProfit, 5)
        self.assertEqual(f.options.maxAge, 7)
        self.assertIs(f.options.recipeJunk, True)
        self.assertTrue(f.keep[2589] and f.keep[4306])
        self.assertEqual(f["items"][2592], "junk")
        self.assertEqual(f["items"][4338], "ah")
        c1, c2 = f.categories[1], f.categories[2]
        self.assertEqual((c1["class"], c1.subclass, c1.qmin, c1.qmax, c1.group), (7, 5, 0, 1, "junk"))
        self.assertEqual((c2["class"], c2.subclass, c2.qmin, c2.qmax, c2.group), (0, 5, None, None, "keep"))
        self.assertEqual(report.ignored, 0)
        self.assertFalse(report.truncated)

    def test_unknown_lines_dropped(self):
        f, report = self.parse("KeepOrSell filter 1\ntooltip = off\nitem 12 = quest\nitem x = junk\nhello\n")
        self.assertEqual(report.ignored, 4)
        self.assertEqual(self.lst(report.ignoredLines), [2, 3, 4, 5])
        self.assertIsNone(f.options.tooltip)
        self.assertIsNone(f["items"][12])

    def test_blank_and_comment_lines_not_ignored(self):
        f, report = self.parse("KeepOrSell filter 1\n\n# note\nfactor = 2 # why\n")
        self.assertEqual(report.ignored, 0)
        self.assertEqual(f.options.factor, 2)

    def test_numbers_clamped_or_ignored(self):
        f, report = self.parse("KeepOrSell filter 1\nfactor = 0\nmaxAge = 999\nminProfit = 500\n")
        self.assertEqual(f.options.factor, self.ns.MIN_FACTOR)
        self.assertEqual(f.options.maxAge, 21)
        self.assertEqual(f.options.minProfit, 100)
        f, report = self.parse("KeepOrSell filter 1\nfactor = abc\n")
        self.assertIsNone(f.options.factor)
        self.assertEqual(report.ignored, 1)

    def test_toggle_values(self):
        f, _ = self.parse("KeepOrSell filter 1\nscrap = off\ngear = 1\nquestie = TRUE\nopenable = 0\nplainGear = false\n")
        self.assertIs(f.options.scrap, False)
        self.assertIs(f.options.gear, True)
        self.assertIs(f.options.questie, True)
        self.assertIs(f.options.openable, False)
        self.assertIs(f.options.plainGear, False)
        f, report = self.parse("KeepOrSell filter 1\nscrap = maybe\n")
        self.assertIsNone(f.options.scrap)
        self.assertEqual(report.ignored, 1)

    def test_messy_whitespace_and_bom(self):
        clean, _ = self.parse("KeepOrSell filter 1\nname = Leveling\nitem 2592 = junk\nkeep = 5, 6\nclass 7 quality 1 = ah\n")
        messy = ("\ufeffKeepOrSell filter 1  \r\n\tname =\t|cffff0000Leveling|r  \r\n"
                 "ITEM 2592 = JUNK\r\n  KEEP = 5 ,6 \r\nCLASS 7 QUALITY 1 = AH\r\n")
        f, report = self.parse(messy)
        self.assertEqual(f.name, "Leveling")
        self.assertEqual(f["items"][2592], "junk")
        self.assertTrue(f.keep[5] and f.keep[6])
        self.assertEqual(f.categories[1].group, "ah")
        self.assertEqual(f.categories[1].qmin, 1)
        self.assertEqual(report.ignored, 0)
        self.assertEqual(clean.name, f.name)

    def test_limits(self):
        text = "KeepOrSell filter 1\n" + "".join("item %d = keep\n" % i for i in range(1, 1002))
        f, report = self.parse(text)
        n = sum(1 for _ in f["items"].keys())
        self.assertEqual(n, 1000)
        self.assertTrue(report.truncated)
        f, report = self.parse("KeepOrSell filter 1\nitem 5 = keep\nitem 5 = junk\n")
        self.assertEqual(f["items"][5], "junk")
        self.assertFalse(report.truncated)

    def test_category_limit(self):
        text = "KeepOrSell filter 1\n" + "".join("class %d = junk\n" % (i % 50) for i in range(101))
        f, report = self.parse(text)
        self.assertEqual(len(f.categories), 100)
        self.assertTrue(report.truncated)

    def test_keep_lines_merge(self):
        f, report = self.parse("KeepOrSell filter 1\nkeep = 1, 2\nkeep = 3\nkeep = 4, x\n")
        self.assertTrue(f.keep[1] and f.keep[2] and f.keep[3])
        self.assertIsNone(f.keep[4])
        self.assertEqual(report.ignored, 1)

    def test_quality_single_value(self):
        f, _ = self.parse("KeepOrSell filter 1\nclass 4 quality 2 = disenchant\n")
        c = f.categories[1]
        self.assertEqual((c["class"], c.qmin, c.qmax, c.subclass, c.group), (4, 2, 2, None, "disenchant"))

    def test_bad_rules_dropped(self):
        f, report = self.parse("KeepOrSell filter 1\nclass 4 quality 3-1 = junk\nclass x = junk\nclass 4 = bogus\nclass 4 subclass = junk\n")
        self.assertEqual(len(f.categories), 0)
        self.assertEqual(report.ignored, 4)

    def test_ignored_lines_capped(self):
        f, report = self.parse("KeepOrSell filter 1\n" + "bad\n" * 9)
        self.assertEqual(report.ignored, 9)
        self.assertEqual(self.lst(report.ignoredLines), [2, 3, 4, 5, 6])

    def test_exports_for_other_tasks(self):
        for g in ("keep", "profession", "ah", "disenchant", "junk"):
            self.assertTrue(self.ns.FILTER_GROUPS[g])
        keys = [self.ns.FILTER_OPTIONS[i].key for i in range(1, len(self.ns.FILTER_OPTIONS) + 1)]
        self.assertEqual(keys[:3], ["factor", "minProfit", "maxAge"])
        self.assertEqual(len(keys), 13)

    def test_long_name_cut(self):
        f, _ = self.parse("KeepOrSell filter 1\nname = " + "a" * 100 + "\n")
        self.assertEqual(len(f.name), 40)

    # --- parser hardening ---

    def test_name_strips_escape_sequences(self):
        f, _ = self.parse("KeepOrSell filter 1\nname = A|TInterface/Icons/x:16|tB|Hitem:1:0|h[Z]|hC|K1|kD|cffff0000E|rF|\n")
        self.assertNotIn("|", f.name)
        self.assertEqual(f.name, "AB[Z]CDEF")
        f, _ = self.parse("KeepOrSell filter 1\nname = a\x01b\x7fc\n")
        self.assertEqual(f.name, "abc")

    def test_ids_must_be_positive(self):
        f, report = self.parse("KeepOrSell filter 1\nitem 0 = junk\nkeep = 0\nkeep = 0, 5\nitem 7 = junk\n")
        self.assertIsNone(f["items"][0])
        self.assertIsNone(f.keep[0])
        self.assertIsNone(f.keep[5])
        self.assertEqual(f["items"][7], "junk")
        self.assertEqual(report.ignored, 3)

    def test_whole_number_options_rounded(self):
        f, _ = self.parse("KeepOrSell filter 1\nmaxAge = 7.5\nminProfit = 2.4\nfactor = 2.26\n")
        self.assertEqual(f.options.maxAge, 8)
        self.assertEqual(f.options.minProfit, 2)
        self.assertAlmostEqual(f.options.factor, 2.3)

    def test_lone_cr_line_endings(self):
        f, report = self.parse("KeepOrSell filter 1\rfactor = 3\rkeep = 5\r")
        self.assertEqual(f.options.factor, 3)
        self.assertTrue(f.keep[5])
        self.assertEqual(report.ignored, 0)


DB = """
local db = {
  filter = {name = "Leveling",
    items = {[4338] = "ah", [2592] = "junk"},
    categories = {{class = 7, subclass = 5, qmin = 0, qmax = 1, group = "junk"},
                  {class = 0, group = "keep"},
                  {class = 4, qmin = 2, qmax = 2, group = "disenchant"}}},
  keep = {[4306] = true, [2589] = true, [10] = true},
  factor = 2.5, minProfit = 5, maxAge = 7,
  scrap = true, profession = false, gear = true, plainGear = false, recipeJunk = true,
  questie = true, disenchant = false, openable = true, upcomingReagents = false, altReagents = true,
}
return db
"""


class SerializeTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Prices.lua", "Filter.lua"))

    def db(self):
        return self.rt.execute(DB)

    def test_round_trip(self):
        db = self.db()
        text = self.ns.SerializeFilter(db)
        f, report = self.ns.ParseFilter(text)
        self.assertEqual(report.ignored, 0)
        self.assertEqual(f.name, "Leveling")
        for i in range(1, len(self.ns.FILTER_OPTIONS) + 1):
            key = self.ns.FILTER_OPTIONS[i].key
            self.assertEqual(f.options[key], db[key], key)
        self.assertEqual(sorted(f.keep.keys()), [10, 2589, 4306])
        self.assertEqual(f["items"][2592], "junk")
        self.assertEqual(f["items"][4338], "ah")
        self.assertEqual(len(f.categories), 3)
        c = f.categories
        self.assertEqual((c[1]["class"], c[1].subclass, c[1].qmin, c[1].qmax, c[1].group), (7, 5, 0, 1, "junk"))
        self.assertEqual((c[2]["class"], c[2].subclass, c[2].qmin, c[2].group), (0, None, None, "keep"))
        self.assertEqual((c[3]["class"], c[3].qmin, c[3].qmax, c[3].group), (4, 2, 2, "disenchant"))

    def test_output_is_sorted_and_commented(self):
        names = self.rt.execute("""return {
          item = function(id) if id == 2592 then return "Wool Cloth" end end,
          class = function(c, s) if s then return "Cloth" end return "Trade Goods" end}""")
        lines = self.ns.SerializeFilter(self.db(), names).split("\n")
        self.assertEqual(lines[0], "KeepOrSell filter 1")
        item_lines = [l for l in lines if l.startswith("item ")]
        self.assertEqual(item_lines[0], "item 2592 = junk  # Wool Cloth")
        self.assertEqual(item_lines[1], "item 4338 = ah")
        cats = [l for l in lines if l.startswith("class ")]
        self.assertEqual(cats[0], "class 7 subclass 5 quality 0-1 = junk  # Trade Goods: Cloth")
        self.assertEqual(cats[1], "class 0 = keep  # Trade Goods")
        self.assertEqual(cats[2], "class 4 quality 2 = disenchant  # Trade Goods")
        self.assertIn("keep = 10, 2589, 4306", lines)

    def test_without_keep(self):
        text = self.ns.SerializeFilter(self.db(), None, False)
        self.assertFalse(any(l.startswith("keep") for l in text.split("\n")))
        self.assertIn("item 2592 = junk", text)

    def test_keep_wrapped(self):
        db = self.rt.execute("local k = {} for i = 1, 45 do k[i] = true end return {keep = k}")
        text = self.ns.SerializeFilter(db)
        self.assertEqual(len([l for l in text.split("\n") if l.startswith("keep")]), 3)
        f, _ = self.ns.ParseFilter(text)
        self.assertEqual(len(list(f.keep.keys())), 45)

    def test_empty_db(self):
        for db in (self.rt.execute("return {}"), self.rt.execute("return {filter = {}}")):
            text = self.ns.SerializeFilter(db)
            lines = text.split("\n")
            self.assertEqual(lines[0], "KeepOrSell filter 1")
            self.assertFalse(any(l.startswith(("name", "item", "class", "keep")) for l in lines))
            f, report = self.ns.ParseFilter(text)
            self.assertIsNotNone(f)
            self.assertEqual(report.ignored, 0)

    def test_category_precedence(self):
        f = self.rt.eval("""{categories = {
          {class = 7, group = "ah"},
          {class = 7, qmin = 0, qmax = 1, group = "keep"},
          {class = 7, subclass = 5, group = "profession"},
          {class = 7, subclass = 5, qmin = 0, qmax = 1, group = "junk"},
          {class = 7, subclass = 5, group = "ah"},
        }}""")
        rule = self.ns.FilterCategoryRule
        self.assertEqual(rule(f, 7, 5, 1), "junk")
        self.assertEqual(rule(f, 7, 5, 3), "profession")  # first among equals
        self.assertEqual(rule(f, 7, 8, 0), "keep")
        self.assertEqual(rule(f, 7, 8, 3), "ah")
        self.assertIsNone(rule(f, 4, 0, 1))
        # a quality range needs a known quality
        self.assertEqual(rule(f, 7, 5, None), "profession")
        self.assertEqual(rule(f, 7, 8, None), "ah")
        self.assertIsNone(rule(None, 7, 5, 1))
        self.assertIsNone(rule(self.rt.eval("{}"), 7, 5, 1))

    def test_item_rule(self):
        f = self.rt.eval("{items = {[2589] = 'junk', [4306] = 'bogus'}}")
        self.assertEqual(self.ns.FilterItemRule(f, 2589), "junk")
        self.assertIsNone(self.ns.FilterItemRule(f, 4306))
        self.assertIsNone(self.ns.FilterItemRule(f, 2592))
        self.assertIsNone(self.ns.FilterItemRule(f, None))
        self.assertIsNone(self.ns.FilterItemRule(None, 2589))
        self.assertIsNone(self.ns.FilterItemRule(self.rt.eval("{}"), 2589))


APPLY_TEXT = """KeepOrSell filter 1
name = Imported
factor = 3
scrap = off
keep = 1, 2, 9
item 100 = junk
item 101 = ah
class 7 = keep
"""


class ApplyTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Prices.lua", "Filter.lua"))
        self.rt.globals().NS = self.ns
        self.rt.globals().IMPORT = APPLY_TEXT
        self.rt.execute("""
          DB = {factor = 2, scrap = true, minProfit = 4, keep = {[9] = true},
                filter = {name = "Old", items = {[5] = "keep"}, categories = {{class = 0, group = "junk"}}}}
          FILTER, REPORT = NS.ParseFilter(IMPORT)
        """)

    def apply(self):
        return self.rt.eval("(function() local a = NS.ApplyFilter(DB, FILTER) return a end)()")

    def test_apply_merges_keep_and_replaces_rules(self):
        added = self.apply()
        self.assertEqual(self.lst(added), [1, 2])
        db = self.rt.globals().DB
        self.assertEqual(sorted(db.keep.keys()), [1, 2, 9])
        self.assertEqual(db.filter.name, "Imported")
        self.assertEqual(sorted(db.filter["items"].keys()), [100, 101])
        self.assertIsNone(db.filter["items"][5])
        self.assertEqual(len(db.filter.categories), 1)
        self.assertEqual((db.factor, db.scrap, db.minProfit), (3, False, 4))  # absent option stays

    def lst(self, t):
        return [t[i] for i in range(1, len(t) + 1)]

    def test_apply_writes_backup(self):
        self.apply()
        backup = self.rt.globals().DB.filterBackup
        self.assertEqual(self.lst(backup.addedKeep), [1, 2])
        self.assertIn("name = Old", backup.text)
        self.assertIn("factor = 2", backup.text)
        self.assertIn("scrap = on", backup.text)
        self.assertIn("item 5 = keep", backup.text)
        self.assertNotIn("keep = 9", backup.text)

    def test_undo_restores_options_and_rules(self):
        self.apply()
        self.assertTrue(self.rt.eval("NS.UndoFilter(DB)"))
        db = self.rt.globals().DB
        self.assertEqual((db.factor, db.scrap, db.minProfit), (2, True, 4))
        self.assertEqual(db.filter.name, "Old")
        self.assertEqual(list(db.filter["items"].keys()), [5])
        self.assertEqual(db.filter.categories[1]["class"], 0)
        self.assertIsNone(db.filterBackup)
        self.assertEqual(sorted(db.keep.keys()), [9])

    def test_undo_keeps_marks_set_after_import(self):
        self.apply()
        self.rt.execute("DB.keep[3] = true")
        self.assertTrue(self.rt.eval("NS.UndoFilter(DB)"))
        self.assertEqual(sorted(self.rt.globals().DB.keep.keys()), [3, 9])

    def test_clear_rules_is_undoable(self):
        self.rt.execute("NS.ClearFilterRules(DB)")
        db = self.rt.globals().DB
        self.assertEqual(len(list(db.filter["items"].keys())), 0)
        self.assertEqual(len(db.filter.categories), 0)
        self.assertIsNone(db.filter.name)
        self.assertEqual((db.factor, sorted(db.keep.keys())), (2, [9]))
        self.assertTrue(self.rt.eval("NS.UndoFilter(DB)"))
        db = self.rt.globals().DB
        self.assertEqual(db.filter.name, "Old")
        self.assertEqual(list(db.filter["items"].keys()), [5])
        self.assertEqual(sorted(db.keep.keys()), [9])

    def test_undo_without_backup_returns_false(self):
        self.assertFalse(self.rt.eval("NS.UndoFilter(DB)"))

    def test_undo_removes_rules_when_backup_had_none(self):
        self.rt.execute("DB.filter = {}")
        self.apply()
        self.assertTrue(self.rt.eval("NS.UndoFilter(DB)"))
        db = self.rt.globals().DB
        self.assertIsNone(db.filter.name)
        self.assertEqual(len(list(db.filter["items"].keys())), 0)
        self.assertEqual(len(db.filter.categories), 0)

    def test_summary_lines(self):
        text = "KeepOrSell filter 1\nfactor = 3\nkeep = 1, 9\nitem 100 = junk\nitem 101 = ah\nxx\nyy\n"
        self.rt.globals().IMPORT = text
        self.rt.execute("FILTER, REPORT = NS.ParseFilter(IMPORT); REPORT.ignoredLines = {3, 17}; REPORT.ignored = 2")
        lines = self.lst(self.rt.eval("NS.FilterSummary(DB, FILTER, REPORT)"))
        self.assertEqual(lines, ["2 item rules (1 junk)", "1 keep marks added", "2 lines ignored (3, 17)",
                                 "factor: 2 → 3"])

    def test_summary_omits_unchanged_options(self):
        self.rt.globals().IMPORT = "KeepOrSell filter 1\nfactor = 2\nscrap = off\ncolor = x\nclass 7 = keep"
        self.rt.execute("FILTER, REPORT = NS.ParseFilter(IMPORT)")
        lines = self.lst(self.rt.eval("NS.FilterSummary(DB, FILTER, REPORT)"))
        self.assertEqual(lines, ["1 category rules", "1 lines ignored (4)", "scrap: on → off"])

    def test_summary_puts_rules_first_and_options_on_one_line(self):
        self.rt.globals().IMPORT = ("KeepOrSell filter 1\nfactor = 3\nminProfit = 9\nscrap = off\nmaxAge = 3\n"
                                    "item 100 = junk\nclass 7 = keep\nkeep = 1")
        self.rt.execute("FILTER, REPORT = NS.ParseFilter(IMPORT)")
        lines = self.lst(self.rt.eval("NS.FilterSummary(DB, FILTER, REPORT)"))
        self.assertEqual(lines, ["1 item rules (1 junk)", "1 category rules", "1 keep marks added",
                                 "factor: 2 → 3, minProfit: 4 → 9, maxAge: - → 3, scrap: on → off"])


COMMAND_STUBS = """
PRINTED = {}
function print(text) PRINTED[#PRINTED + 1] = text end
POPUPS = {}
StaticPopupDialogs = {}
function StaticPopup_Show(which) POPUPS[#POPUPS + 1] = which end
C_Item.GetItemClassInfo = function(class) return ({[7] = "Trade Goods"})[class] end
C_Item.GetItemSubClassInfo = function(class, sub) return ({[5] = "Cloth"})[sub] end
"""


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Keep.lua", "Prices.lua", "Filter.lua", "FilterWindow.lua"),
                                COMMAND_STUBS)
        self.L = self.ns.L
        self.rt.eval("""function(ns)
          ns.SettingsChanged = function() ns.changed = (ns.changed or 0) + 1 end
          ns.ShowFilterWindow = function(mode) ns.shown = mode end
          KeepOrSellDB.filter = {items = {}, categories = {}}
        end""")(self.ns)
        self.db = self.rt.eval("KeepOrSellDB")
        # always two results, also when the Lua function returns only true
        self.rule = self.rt.eval("function(ns, db, id, word) local ok, err = ns.FilterRuleCommand(db, id, word) return ok, err end")

    def parse(self, text):
        return self.ns.ParseFilter(text)[0]

    def printed(self):
        return list(self.rt.eval("PRINTED").values())

    def test_rule_command_sets_and_clears(self):
        ok, err = self.rule(self.ns, self.db, 4, "junk")
        self.assertTrue(ok)
        self.assertEqual(self.db.filter["items"][4], "junk")
        ok, err = self.rule(self.ns, self.db, 4, "clear")
        self.assertTrue(ok)
        self.assertIsNone(self.db.filter["items"][4])
        ok, err = self.rule(self.ns, self.db, 4, "quest")
        self.assertFalse(ok)
        self.assertEqual(err, "group")
        self.assertIsNone(self.db.filter["items"][4])

    def test_rule_command_takes_any_case_and_creates_storage(self):
        db = self.rt.eval("{}")
        self.assertTrue(self.rule(self.ns, db, 4, "AH")[0])
        self.assertEqual(db.filter["items"][4], "ah")
        self.assertEqual(self.rule(self.ns, db, None, "junk")[1], "item")

    def test_slash_routes(self):
        self.assertTrue(self.ns.HandleFilterCommand("export"))
        self.assertEqual(self.ns.shown, "export")
        self.assertTrue(self.ns.HandleFilterCommand(" IMPORT "))
        self.assertEqual(self.ns.shown, "import")
        self.assertFalse(self.ns.HandleFilterCommand("keep 4"))
        self.assertFalse(self.ns.HandleFilterCommand(""))
        self.assertFalse(self.ns.HandleFilterCommand(None))

    def test_slash_rule_with_link(self):
        self.assertTrue(self.ns.HandleFilterCommand("rule |cffffffff|Hitem:4::::|h[Linen Cloth]|h|r junk"))
        self.assertEqual(self.db.filter["items"][4], "junk")
        self.assertEqual(self.ns.changed, 1)
        self.assertIn("link4", self.printed()[-1])
        self.assertTrue(self.ns.HandleFilterCommand("rule 4 clear"))
        self.assertIsNone(self.db.filter["items"][4])

    def test_slash_rule_bad_input_shows_usage(self):
        for msg in ("rule 4 quest", "rule junk", "rule", "rule [Linen] junk"):
            self.assertTrue(self.ns.HandleFilterCommand(msg), msg)
            self.assertIn(self.L.FILTER_RULE_USAGE, self.printed()[-1], msg)
        self.assertIsNone(self.db.filter["items"][4])
        self.assertIsNone(self.ns.changed)

    def test_slash_rules_lists_items_and_categories(self):
        self.rt.execute("""KeepOrSellDB.filter = {name = "Leveling", items = {[4] = "junk", [3] = "ah", [999] = "junk"},
          categories = {{class = 7, subclass = 5, qmin = 0, qmax = 1, group = "junk"}, {class = 0, group = "keep"}}}""")
        self.assertTrue(self.ns.HandleFilterCommand("rules"))
        text = "\n".join(self.printed())
        self.assertIn("Leveling", text)
        self.assertIn("link4", text)
        self.assertIn("link3", text)
        self.assertIn("item:999", text)  # not cached
        self.assertIn("Trade Goods: Cloth", text)
        self.assertIn("class 0", text)  # no class name known

    def test_slash_rules_empty(self):
        self.assertTrue(self.ns.HandleFilterCommand("rules"))
        self.assertIn(self.L.FILTER_RULES_EMPTY, self.printed()[-1])

    def test_undo_without_backup_says_so(self):
        self.ns.UndoFilterCommand()
        self.assertIn(self.L.FILTER_NO_UNDO, self.printed()[-1])
        self.assertIsNone(self.ns.changed)

    def test_undo_restores_and_refreshes(self):
        self.rt.execute("KeepOrSellDB.filter.items[4] = 'junk'; KeepOrSellDB.factor = 2")
        filt = self.parse("KeepOrSell filter 1\nfactor = 5\nitem 3 = ah")
        self.ns.ApplyFilter(self.db, filt)
        self.ns.UndoFilterCommand()
        self.assertEqual(self.db.factor, 2)
        self.assertEqual(self.db.filter["items"][4], "junk")
        self.assertEqual(self.ns.changed, 1)
        self.assertIn(self.L.FILTER_UNDONE, self.printed()[-1])

    def test_clear_asks_first(self):
        self.rt.execute("KeepOrSellDB.filter.items[4] = 'junk'")
        self.ns.ClearFilterCommand()
        self.assertEqual(self.rt.eval("POPUPS[1]"), "KEEPORSELL_CLEAR_FILTER")
        self.assertEqual(self.db.filter["items"][4], "junk")
        dialog = self.rt.eval("StaticPopupDialogs.KEEPORSELL_CLEAR_FILTER")
        self.assertEqual(dialog.text, self.L.FILTER_CLEAR_CONFIRM)
        dialog.OnAccept()
        self.assertIsNone(self.db.filter["items"][4])
        self.assertEqual(self.ns.changed, 1)
        self.assertIsNotNone(self.db.filterBackup)

    def test_check_text(self):
        filt, lines = self.ns.CheckFilterText(self.db, "KeepOrSell filter 1\nitem 4 = junk")
        self.assertIsNotNone(filt)
        self.assertIn("1 item rules (1 junk)", list(lines.values()))
        for text, err in (("hello", "FILTER_ERR_NOHEADER"), ("KeepOrSell filter 9", "FILTER_ERR_VERSION")):
            filt, message = self.ns.CheckFilterText(self.db, text)
            self.assertIsNone(filt)
            self.assertEqual(message, self.L[err])

    def test_apply_text(self):
        filt = self.parse("KeepOrSell filter 1\nname = Leveling\nitem 4 = junk")
        self.ns.ApplyFilterCommand(filt)
        self.assertEqual(self.db.filter["items"][4], "junk")
        self.assertEqual(self.ns.changed, 1)
        self.assertIn("Leveling", self.printed()[-1])

    def test_apply_unnamed_filter(self):
        self.ns.ApplyFilterCommand(self.parse("KeepOrSell filter 1\nitem 4 = junk"))
        self.assertIn(self.L.FILTER_APPLIED_UNNAMED, self.printed()[-1])


if __name__ == "__main__":
    unittest.main()
