"""Tests for the profession reagent memory (Professions.lua)."""
import unittest

from addon import load

# recipe 10 orange (linen 4), 11 grey (wool 20), 12 not learned (silk 3), 13 green (linen 4 + thread 21),
# 14 grey: dust 40 into particles 41, 15 orange (particles 41), 16 grey: shard 42 into dust 40
STUBS = """
RECIPES = {
  [10] = {learned = true, relativeDifficulty = 0, reagents = {4}},
  [11] = {learned = true, relativeDifficulty = 3, reagents = {20}},
  [12] = {learned = false, relativeDifficulty = 0, reagents = {3}},
  [13] = {learned = true, relativeDifficulty = 2, reagents = {4, 21}},
  [14] = {learned = true, relativeDifficulty = 3, reagents = {40}, output = 41},
  [15] = {learned = true, relativeDifficulty = 0, reagents = {41}},
  [16] = {learned = true, relativeDifficulty = 3, reagents = {42}, output = 40},
}
SHOWN = {10, 11, 12, 13, 14, 15, 16}
local function Schematic(id)
  local slots = {}
  for _, itemID in ipairs(RECIPES[id].reagents) do table.insert(slots, {reagents = {{itemID = itemID}}}) end
  return {reagentSlotSchematics = slots, outputItemID = RECIPES[id].output}
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

    def test_reagent_crafted_into_skill_up_reagent(self):
        self.ns.ScanProfession()
        self.assertTrue(self.ns.IsSkillUpReagent(40))  # dust -> particles
        self.assertTrue(self.ns.IsSkillUpReagent(42))  # shard -> dust -> particles

    def test_crafted_chain_ends_when_recipe_turns_grey(self):
        self.ns.ScanProfession()
        self.rt.execute("RECIPES[15].relativeDifficulty = 3")
        self.assertTrue(self.ns.ScanProfession())
        self.assertFalse(self.ns.IsSkillUpReagent(40))

    def test_crafted_reagent_kept_from_auction_house(self):
        self.ns.ScanProfession()
        self.rt.execute("ITEMS[40] = {'Strange Dust', 7, 12, '', 1}; AH.link40 = 175")
        self.assertEqual(self.ns.Classify(40, "link40").kind, "profession")

    def test_upcoming_reagents(self):
        self.ns.ScanProfession()
        self.assertTrue(self.ns.IsUpcomingReagent(3))  # recipe 12 not learned yet
        self.assertFalse(self.ns.IsUpcomingReagent(20))

    def test_upcoming_reagent_unknown_difficulty(self):
        self.rt.execute("RECIPES[12].relativeDifficulty = nil")
        self.ns.ScanProfession()
        self.assertTrue(self.ns.IsUpcomingReagent(3))

    def test_upcoming_grey_recipe_ignored(self):
        self.rt.execute("RECIPES[12].relativeDifficulty = 3")
        self.ns.ScanProfession()
        self.assertFalse(self.ns.IsUpcomingReagent(3))

    def test_learning_upcoming_recipe(self):
        self.ns.ScanProfession()
        self.rt.execute("RECIPES[12].learned = true")
        self.assertTrue(self.ns.ScanProfession())
        self.assertFalse(self.ns.IsUpcomingReagent(3))
        self.assertTrue(self.ns.IsSkillUpReagent(3))

    def test_upcoming_reagent_never_junk(self):
        self.ns.ScanProfession()
        self.rt.execute("ITEMS[3] = {'Silk Cloth', 7, 5, '', 100}; AH.link3 = 110")
        verdict = self.ns.Classify(3, "link3")
        self.assertEqual((verdict.kind, verdict.reason), ("profession", "upcoming"))
        self.rt.execute("KeepOrSellDB.profession = false")
        self.ns.ClearCache()
        self.assertEqual(self.ns.Classify(3, "link3").kind, "junk")

    def test_upcoming_reagent_without_price(self):
        self.ns.ScanProfession()
        self.rt.execute("ITEMS[3] = {'Silk Cloth', 7, 5, '', 100}")
        self.assertEqual(self.ns.Classify(3, "link3").kind, "profession")

    def test_upcoming_reagent_still_auctioned(self):
        self.ns.ScanProfession()
        self.rt.execute("ITEMS[3] = {'Silk Cloth', 7, 5, '', 100}; AH.link3 = 50000")
        self.assertEqual(self.ns.Classify(3, "link3").kind, "ah")

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


RECIPE_STUBS = """
Enum = {TooltipDataLineType = {UsageRequirement = 43}, TooltipDataUsageRequirementType = {Skill = 2, NotAlreadyKnown = 14}}
ITEM_SPELL_KNOWN = "Already known"
RED, WHITE = {r = 1, g = 0.125, b = 0.125}, {r = 1, g = 1, b = 1}
LINES = {
  [30] = {{type = 43, requirementType = 2, leftColor = WHITE}},                       -- first aid book, skill ok
  [31] = {{type = 43, requirementType = 2, leftColor = RED}},                         -- skill too low
  [32] = {{type = 43, requirementType = 14, leftColor = RED}},                        -- already known
  [33] = {{type = 0, leftText = "Already known", leftColor = RED}},                   -- known, plain text
}
ITEMS[30] = {"First Aid Book", 9, 7, "", 2500}
ITEMS[31] = {"First Aid Manual", 9, 7, "", 2500}
ITEMS[32] = {"Known Bandage Recipe", 9, 7, "", 100}
ITEMS[33] = {"Known Cooking Recipe", 9, 5, "", 100}
ITEMS[34] = {"Tailoring Pattern", 9, 2, "", 100}
C_TooltipInfo = {GetItemByID = function(id) return {lines = LINES[id] or {}} end}
-- first aid (129) and cooking (185)
function GetProfessions() return nil, nil, nil, nil, 2, 1 end
function GetProfessionInfo(i) if i == 1 then return "First Aid", 0, 125, 225, 0, 0, 129 end return "Cooking", 0, 1, 75, 0, 0, 185 end
"""


class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(stubs=RECIPE_STUBS)

    def state(self, item_id):
        return self.ns.ItemFacts(item_id, "link%d" % item_id).recipe

    def test_unknown_recipe_of_own_profession(self):
        self.assertEqual(self.state(30), "learn")
        self.assertEqual(self.state(31), "learn")  # learn it later

    def test_known_recipe(self):
        self.assertEqual(self.state(32), "known")
        self.assertEqual(self.state(33), "known")

    def test_other_profession(self):
        self.assertEqual(self.state(34), "other")

    def test_not_a_recipe(self):
        self.assertIsNone(self.state(4))

    def test_without_profession_api_skill_line_decides(self):
        self.rt.execute("GetProfessions = nil")
        self.assertEqual(self.state(30), "learn")
        self.assertIsNone(self.state(31))

    def test_unknown_recipe_kept_in_profession_group(self):
        self.rt.execute("AH.link30 = 15000")
        verdict = self.ns.Classify(30, "link30")
        self.assertEqual((verdict.kind, verdict.reason), ("profession", "recipe"))
        self.rt.execute("AH.link32 = 15000")
        self.assertEqual(self.ns.Classify(32, "link32").kind, "ah")

    def test_known_recipe_sold_when_not_worth_auctioning(self):
        self.rt.execute("AH.link32 = 120")
        verdict = self.ns.Classify(32, "link32")
        self.assertEqual((verdict.kind, verdict.reason), ("junk", "recipe_known"))

    def test_other_profession_recipe(self):
        self.rt.execute("AH.link34 = 120")
        verdict = self.ns.Classify(34, "link34")
        self.assertEqual((verdict.kind, verdict.reason), ("junk", "recipe_other"))
        self.rt.execute("AH.link34 = 15000")
        self.ns.ClearCache()
        self.assertEqual(self.ns.Classify(34, "link34").kind, "ah")

    def test_recipe_without_price_kept(self):
        verdict = self.ns.Classify(34, "link34")
        self.assertIsNone(verdict.kind)
        self.assertTrue(verdict.needsPrice)

    def test_bound_known_recipe_is_junk(self):
        self.rt.execute("BOUND[32] = true")
        self.assertEqual(self.ns.Classify(32, "link32").kind, "junk")

    def test_recipes_option_off(self):
        self.rt.execute("AH.link32 = 120; KeepOrSellDB.recipeJunk = false")
        self.assertIsNone(self.ns.Classify(32, "link32").kind)


if __name__ == "__main__":
    unittest.main()
