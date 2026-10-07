"""Tests for the hints (Hints.lua) and unopened professions (Professions.lua)."""
import unittest

from addon import CORE_FILES, load

STUBS = """
-- bag 0: linen (stale price), silk (no price), potion (fine)
BAG = {[1] = 4, [2] = 3, [3] = 9}
NUM_BAG_SLOTS = 0
C_Container = {
  GetContainerNumSlots = function(bag) return 3 end,
  GetContainerItemInfo = function(bag, slot) return {itemID = BAG[slot], hyperlink = "link" .. BAG[slot]} end,
}
AH = {link4 = 15, link9 = 10}
AGE = {link4 = 30}
function GetProfessions() return 1, 2, nil, 3 end
function GetProfessionInfo(i)
  if i == 1 then return "Tailoring", 0, 50, 75, 0, 0, 197 end
  if i == 2 then return "First Aid", 0, 50, 75, 0, 0, 129 end
  return "Fishing", 0, 1, 75, 0, 0, 356
end
"""


class CollectTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Hints.lua",), STUBS)
        self.db = self.rt.eval("KeepOrSellDB")

    def collect(self, **state):
        state.setdefault("unopened", [])
        table = self.rt.table_from({k: v for k, v in state.items() if k != "unopened"})
        table.unopened = self.rt.table_from(state["unopened"])
        return list(self.ns.CollectHints(table, self.db).values())

    def test_nothing_to_do(self):
        self.assertEqual(self.collect(auctionator=True, ahVisited=True, stale=0), [])

    def test_tsm_alone_needs_no_auctionator_hint(self):
        # TSM prices already sort items into the auction house group
        self.assertEqual(self.collect(auctionator=False, tsm=True, ahVisited=False, stale=0), [])

    def test_without_auctionator(self):
        hints = self.collect(auctionator=False, ahVisited=False, stale=0)
        self.assertEqual(len(hints), 1)
        self.assertIn("Auctionator is not loaded", hints[0])

    def test_never_scanned(self):
        hints = self.collect(auctionator=True, ahVisited=False, stale=3)
        self.assertEqual(len(hints), 1)
        self.assertIn("Visit the auction house", hints[0])

    def test_prices_and_professions(self):
        hints = self.collect(auctionator=True, ahVisited=True, stale=3, unopened=["Tailoring"])
        self.assertIn("older than 7 days for 3 item(s)", hints[0])
        self.assertIn("Tailoring", hints[1])

    def test_professions_hint_follows_option(self):
        self.db.profession = False
        self.assertEqual(self.collect(auctionator=True, ahVisited=True, stale=0, unopened=["Tailoring"]), [])


    def test_items_to_open(self):
        hints = self.collect(auctionator=True, ahVisited=True, stale=0, open=10)
        self.assertEqual(len(hints), 1)
        self.assertIn("10 bag slot(s)", hints[0])


class OpenStateTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Bags.lua", "Hints.lua"), STUBS + """
        ITEM_OPENABLE = "<Right Click to Open>"
        ITEMS[20] = {"Small Barnacled Clam", 15, 0, "", 15}
        BAG = {[1] = 20, [2] = 20, [3] = 9}
        C_TooltipInfo = {GetItemByID = function(id)
          return {lines = id == 20 and {{leftText = ITEM_OPENABLE}} or {{leftText = "x"}}} end}
        """)

    def test_counts_slots_of_items_to_open(self):
        hints = list(self.ns.GetHints().values())
        self.assertTrue(any("2 bag slot(s)" in h for h in hints), hints)
        self.assertEqual(self.ns.CountSlots(20), 2)


class StateTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Hints.lua",), STUBS)

    def test_hints_from_bags_and_professions(self):
        hints = list(self.ns.GetHints().values())
        self.assertEqual(len(hints), 2)  # silk without price is no hint
        self.assertIn("older than 7 days for 1 item(s)", hints[0])
        self.assertIn("First Aid, Tailoring", hints[1])  # fishing has no recipes

    def test_opened_profession_drops_out(self):
        self.rt.execute("""C_TradeSkillUI = {
          GetFilteredRecipeIDs = function() return {} end, GetRecipeInfo = function() end,
          GetRecipeSchematic = function() end,
          GetBaseProfessionInfo = function() return {professionName = "Tailoring"} end}""")
        self.ns.ScanProfession()
        self.assertEqual(list(self.ns.UnopenedProfessions().values()), ["First Aid"])

    def test_print_respects_option(self):
        self.rt.execute("PRINTED = 0; print = function() PRINTED = PRINTED + 1 end")
        self.ns.PrintHints()
        self.assertEqual(self.rt.eval("PRINTED"), 2)
        self.rt.execute("PRINTED = 0; KeepOrSellDB.hints = false")
        self.ns.PrintHints()
        self.assertEqual(self.rt.eval("PRINTED"), 0)


if __name__ == "__main__":
    unittest.main()
