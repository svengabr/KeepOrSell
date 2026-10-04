"""Tests für das automatische Anlegen der Baganator-Kategorien (Baganator.lua)."""
import json
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent

STUBS = """
IMPORTS = {}
FAIL_IMPORT = false
Baganator = {API = {ImportString = function(text)
  if FAIL_IMPORT then error("Invalid Baganator import") end
  table.insert(IMPORTS, text)
end}}
"""


def load(stubs=STUBS, locale="enUS"):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(f"function GetLocale() return '{locale}' end")
    rt.execute(stubs)
    rt.execute("KeepOrSellDB = {}")
    ns = rt.eval("{}")
    for f in ("Locales.lua", "Baganator.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            str(ROOT / f).replace("\\", "/"), ns)
    return rt, ns


class ImportJSONTests(unittest.TestCase):
    def parse(self, locale="enUS"):
        _, ns = load(locale=locale)
        return json.loads(ns.CategoryImportJSON())

    def test_format_matches_baganator_import(self):
        data = self.parse()
        self.assertEqual(data["addon"], "Baganator")
        self.assertEqual(data["version"], 3)
        self.assertEqual(data["kind"], "categories")
        # ohne "order" hängt Baganator die Kategorien nur an und lässt das restliche Layout in Ruhe
        self.assertNotIn("order", data)

    def test_categories_and_searches(self):
        data = self.parse()
        cats = {c["name"]: c["search"] for c in data["categories"]}
        self.assertEqual(cats, {"Quest": "quest", "AuctionHouse": "auctionhouse & ~quest"})

    def test_german_searches(self):
        data = self.parse("deDE")
        cats = {c["name"]: c["search"] for c in data["categories"]}
        self.assertEqual(cats, {"Quest": "quest", "Auktionshaus": "auktionshaus & ~quest"})

    def test_special_characters_are_escaped(self):
        rt, ns = load()
        name = 'Q"u\\e\n'
        ns.L.CAT_QUEST = name
        data = json.loads(ns.CategoryImportJSON())
        self.assertIn(name, [c["name"] for c in data["categories"]])

    def test_raised_priority_for_every_category(self):
        data = self.parse()
        sources = {c["source"] for c in data["categories"]}
        mods = {m["source"]: m["priority"] for m in data["modifications"]}
        self.assertEqual(set(mods), sources)
        self.assertTrue(all(p >= 1 for p in mods.values()))


class SetupTests(unittest.TestCase):
    def test_imports_once(self):
        rt, ns = load()
        self.assertTrue(ns.SetupBaganatorCategories())
        self.assertIsNone(ns.SetupBaganatorCategories())
        self.assertEqual(rt.eval("#IMPORTS"), 1)
        self.assertTrue(rt.eval("KeepOrSellDB.categoriesImported"))

    def test_force_imports_again(self):
        rt, ns = load()
        ns.SetupBaganatorCategories()
        self.assertTrue(ns.SetupBaganatorCategories(True))
        self.assertEqual(rt.eval("#IMPORTS"), 2)

    def test_failed_import_is_retried_later(self):
        rt, ns = load()
        rt.execute("FAIL_IMPORT = true")
        self.assertIs(ns.SetupBaganatorCategories(), False)
        self.assertIsNone(rt.eval("KeepOrSellDB.categoriesImported"))

    def test_without_baganator(self):
        rt, ns = load(stubs="")
        self.assertIsNone(ns.SetupBaganatorCategories())
        self.assertIsNone(rt.eval("KeepOrSellDB.categoriesImported"))


if __name__ == "__main__":
    unittest.main()
