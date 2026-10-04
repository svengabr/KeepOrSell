"""Tests for the Scrap extension (Scrap.lua)."""
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent

STUBS = """
-- itemID -> {name, classID}; 1 = wolf flank (objective), 2 = linen cloth, 3 = sword, 4 = silk (worth auctioning)
ITEMS = {[1] = {"Magere Wolfflanke", 7}, [2] = {"Leinenstoff", 7}, [3] = {"Schwert", 2}, [4] = {"Seidenstoff", 7}}
C_Item = {
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
  GetItemInfoInstant = function(id) return id, nil, nil, nil, nil, ITEMS[id] and ITEMS[id][2] end,
  GetItemInfo = function(id) return nil, "link" .. id end,
}
Scrap = {junk = {}, IsJunk = function(self, id) return id == 99 end}
"""


def load():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(STUBS)
    ns = rt.eval("{}")
    rt.execute("KeepOrSellDB = {factor = 2, scrap = true}")
    for f in ("Objectives.lua", "Scrap.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            str(ROOT / f).replace("\\", "/"), ns)
    # stub price classification and quest objectives
    rt.eval("""function(ns)
      ns.GetPriceClass = function(link) if link == "link4" then return "ah" end return "vendor" end
      ns.items = {["Magere Wolfflanke"] = "open"}
    end""")(ns)
    ns.HookScrap()
    return rt, ns


class ScrapTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()
        self.is_junk = self.rt.eval("function(id) return Scrap:IsJunk(id, 0, 1) end")

    def test_cheap_tradegood_is_junk(self):
        self.assertTrue(self.is_junk(2))

    def test_quest_objective_never_junk(self):
        self.assertFalse(self.is_junk(1))

    def test_ah_worthy_not_junk(self):
        self.assertFalse(self.is_junk(4))

    def test_equipment_untouched(self):
        self.assertFalse(self.is_junk(3))

    def test_scrap_own_junk_kept(self):
        self.assertTrue(self.is_junk(99))

    def test_user_marked_not_junk_respected(self):
        self.rt.execute("Scrap.junk[2] = false")
        self.assertFalse(self.is_junk(2))

    def test_switch_off(self):
        self.rt.execute("KeepOrSellDB.scrap = false")
        self.assertFalse(self.is_junk(2))


if __name__ == "__main__":
    unittest.main()
