"""Tests for the item set groups KeepOrSell reports to Baganator (Baganator.lua)."""
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent

STUBS = """
function GetLocale() return "enUS" end
-- itemID -> {name, classID}; 1 = wolf flank (objective), 2 = letter (quest item), 3 = silk (AH), 4 = cloth
ITEMS = {[1] = {"Lean Wolf Flank", 7}, [2] = {"Sealed Letter", 12}, [3] = {"Silk Cloth", 7}, [4] = {"Linen Cloth", 7}}
C_Item = {
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
  GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, ITEMS[id] and ITEMS[id][2] end,
}
KeepOrSellDB = {factor = 2}
"""


def load():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(STUBS)
    ns = rt.eval("{}")
    for f in ("Locales.lua", "Objectives.lua", "Baganator.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            str(ROOT / f).replace("\\", "/"), ns)
    rt.eval("""function(ns)
      ns.GetPriceClass = function(link) if link == "link3" or link == "link1" then return "ah" end return "vendor" end
      ns.items = {["Lean Wolf Flank"] = "open"}
    end""")(ns)
    return rt, ns


def names(ns, item_id):
    sets = ns.ItemSets(item_id, "link%d" % item_id)
    if sets is None:
        return []
    return [s.name for s in sets.values()]


class ItemSetTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def test_objective_item_is_quest(self):
        self.assertEqual(names(self.ns, 1)[0], "Quest")

    def test_quest_class_item_is_quest(self):
        # regular quest items share the group, so the built-in quest category stays empty
        self.assertEqual(names(self.ns, 2), ["Quest"])

    def test_quest_group_comes_first(self):
        # Baganator groups by the first set; quest beats auction house
        self.assertEqual(names(self.ns, 1), ["Quest", "AuctionHouse"])

    def test_auction_house_item(self):
        self.assertEqual(names(self.ns, 3), ["AuctionHouse"])

    def test_plain_item_has_no_set(self):
        self.assertEqual(names(self.ns, 4), [])

    def test_unknown_item(self):
        self.assertEqual(self.ns.ItemSets(None, None), None)

    def test_short_group_name(self):
        self.assertEqual(self.ns.L.SET_QUEST, "Quest")


if __name__ == "__main__":
    unittest.main()
