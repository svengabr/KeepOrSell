"""Unit-Tests für die reinen Lua-Kernfunktionen. Aufruf: python -m unittest discover -s tests -v"""
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent


def load_addon(stubs=""):
    """Lädt Objectives.lua wie der Client (addonName, ns), nach optionalen API-Stubs."""
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    if stubs:
        rt.execute(stubs)
    ns = rt.eval("{}")
    rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
        str(ROOT / "Objectives.lua").replace("\\", "/"), ns)
    return rt, ns


RETAIL_STUBS = """
C_QuestLog = {
  GetNumQuestLogEntries = function() return 3 end,
  GetInfo = function(i)
    if i == 1 then return {isHeader = true} end
    if i == 2 then return {questID = 25} end
    return {questID = 26}
  end,
  GetQuestObjectives = function(id)
    if id == 25 then
      return {
        {text = "6/10 Magere Wolfflanke", type = "item", finished = false},
        {text = "Gnoll getötet: 3/5", type = "monster", finished = false},
      }
    end
    return {{text = "Rotes Kopftuch: 8/8", type = "item", finished = true}}
  end,
}
"""

CLASSIC_STUBS = """
GetNumQuestLogEntries = function() return 2 end
GetQuestLogTitle = function(i)
  if i == 1 then return "Westfall", nil, nil, true end
  return "Wolfskebab", 25, nil, false, nil, nil, nil, 25
end
GetNumQuestLeaderBoards = function(i) return i == 2 and 1 or 0 end
GetQuestLogLeaderBoard = function(j, i) return "Magere Wolfflanke: 10/10", "item", true end
"""


class ParseTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load_addon()

    def test_retail_format(self):
        self.assertEqual(self.ns.ParseObjectiveName("6/10 Magere Wolfflanke"), "Magere Wolfflanke")

    def test_classic_format(self):
        self.assertEqual(self.ns.ParseObjectiveName("Magere Wolfflanke: 6/10"), "Magere Wolfflanke")

    def test_without_counter(self):
        self.assertEqual(self.ns.ParseObjectiveName("  Siegel von Ragnaros "), "Siegel von Ragnaros")

    def test_invalid(self):
        self.assertIsNone(self.ns.ParseObjectiveName(None))
        self.assertIsNone(self.ns.ParseObjectiveName("   "))


class CollectTests(unittest.TestCase):
    def test_retail_api_collects_only_items(self):
        _, ns = load_addon(RETAIL_STUBS)
        items = ns.CollectObjectiveItems()
        self.assertEqual(items["Magere Wolfflanke"], "open")
        self.assertEqual(items["Rotes Kopftuch"], "done")
        self.assertIsNone(items["Gnoll getötet"])

    def test_classic_api(self):
        _, ns = load_addon(CLASSIC_STUBS)
        items = ns.CollectObjectiveItems()
        self.assertEqual(items["Magere Wolfflanke"], "done")

    def test_open_wins_over_done(self):
        rt, ns = load_addon(RETAIL_STUBS)
        rt.execute("""C_QuestLog.GetQuestObjectives = function(id)
          return {{text = "Wolfflanke: 1/2", type = "item", finished = (id == 25)}} end""")
        self.assertEqual(ns.CollectObjectiveItems()["Wolfflanke"], "open")

    def test_state_by_item_id(self):
        rt, ns = load_addon(RETAIL_STUBS)
        rt.execute("C_Item = {GetItemNameByID = function(id) if id == 1015 then return 'Magere Wolfflanke' end if id == 2 then return 'Leinenstoff' end end}")
        ns.Refresh()
        self.assertEqual(ns.GetObjectiveState(1015), "open")
        self.assertIsNone(ns.GetObjectiveState(999))  # Name noch nicht im Cache
        self.assertFalse(ns.GetObjectiveState(2))

    def test_refresh_reports_change(self):
        rt, ns = load_addon(RETAIL_STUBS)
        self.assertTrue(ns.Refresh())
        self.assertFalse(ns.Refresh())


if __name__ == "__main__":
    unittest.main()
