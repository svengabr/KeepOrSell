"""Tests for the profession reagent memory (Professions.lua)."""
import unittest

from addon import load

# recipe 10 orange (linen 4), 11 grey (wool 20), 12 not learned (silk 3), 13 green (linen 4 + thread 21)
STUBS = """
RECIPES = {
  [10] = {learned = true, relativeDifficulty = 0, reagents = {4}},
  [11] = {learned = true, relativeDifficulty = 3, reagents = {20}},
  [12] = {learned = false, relativeDifficulty = 0, reagents = {3}},
  [13] = {learned = true, relativeDifficulty = 2, reagents = {4, 21}},
}
SHOWN = {10, 11, 12, 13}
local function Schematic(id)
  local slots = {}
  for _, itemID in ipairs(RECIPES[id].reagents) do table.insert(slots, {reagents = {{itemID = itemID}}}) end
  return {reagentSlotSchematics = slots}
end
C_TradeSkillUI = {
  GetFilteredRecipeIDs = function() return SHOWN end,
  GetRecipeInfo = function(id) return RECIPES[id] end,
  GetRecipeSchematic = function(id, isRecraft) return Schematic(id) end,
  IsNPCCrafting = function() return NPC end,
}
"""


class ProfessionTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(stubs=STUBS)

    def test_skill_up_reagents(self):
        self.assertTrue(self.ns.ScanProfession())
        self.assertTrue(self.ns.IsSkillUpReagent(4))
        self.assertTrue(self.ns.IsSkillUpReagent(21))
        self.assertFalse(self.ns.IsSkillUpReagent(20))  # only grey recipes left
        self.assertFalse(self.ns.IsSkillUpReagent(3))  # recipe not learned

    def test_recipe_turning_grey_drops_reagent(self):
        self.ns.ScanProfession()
        self.rt.execute("RECIPES[10].relativeDifficulty = 3; RECIPES[13].relativeDifficulty = 3")
        self.assertTrue(self.ns.ScanProfession())
        self.assertFalse(self.ns.IsSkillUpReagent(4))

    def test_no_change_reported(self):
        self.ns.ScanProfession()
        self.assertFalse(self.ns.ScanProfession())

    def test_filtered_list_keeps_unseen_recipes(self):
        self.ns.ScanProfession()
        self.rt.execute("SHOWN = {11}")
        self.ns.ScanProfession()
        self.assertTrue(self.ns.IsSkillUpReagent(4))

    def test_npc_crafting_ignored(self):
        self.rt.execute("NPC = true")
        self.assertFalse(self.ns.ScanProfession())
        self.assertFalse(self.ns.IsSkillUpReagent(4))

    def test_stored_per_character(self):
        self.ns.ScanProfession()
        self.assertIsNotNone(self.rt.eval("KeepOrSellDB.recipes['Tester-Realm'][10]"))

    def test_without_api(self):
        rt, ns = load()
        self.assertFalse(ns.ScanProfession())
        self.assertFalse(ns.IsSkillUpReagent(4))


if __name__ == "__main__":
    unittest.main()
