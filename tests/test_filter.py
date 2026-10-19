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


if __name__ == "__main__":
    unittest.main()
