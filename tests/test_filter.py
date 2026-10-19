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


if __name__ == "__main__":
    unittest.main()
