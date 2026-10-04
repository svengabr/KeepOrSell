"""Tests for upcoming Questie quests (Questie.lua) and their effect on the decision."""
import unittest

from addon import CORE_FILES, load

FILES = CORE_FILES

# Night elf (race 4) druid (class 11), level 20.
# Quest 100 "Wolf Stew" (level 22) wants Linen Cloth (4) as item objective,
# quest 200 "Cloth Drive" (level 30) wants it too, quest 300 "Horde Only" (level 20, races 2 = orc),
# quest 400 "Silk Delivery" (level 18) needs Silk Cloth (3) as required source item and is exclusive to 401.
STUBS = """
function UnitLevel() return PLAYER_LEVEL or 20 end
function UnitRace() return "Night Elf", "NightElf", 4 end
function UnitClass() return "Druid", "DRUID", 11 end
COMPLETED = {}
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return COMPLETED[id] == true end,
  GetNumQuestLogEntries = function() return 0 end,
  GetInfo = function() return nil end,
  GetQuestObjectives = function() return {} end,
}
local QUESTS = {
  [100] = {name = "Wolf Stew", questLevel = 22, requiredLevel = 18, requiredRaces = 0, requiredClasses = 0,
           objectives = {nil, nil, {{4, "Linen"}}}},
  [200] = {name = "Cloth Drive", questLevel = 30, requiredLevel = 25, requiredRaces = 0, requiredClasses = 0,
           objectives = {nil, nil, {{4}}}},
  [300] = {name = "Horde Only", questLevel = 20, requiredLevel = 15, requiredRaces = 2, requiredClasses = 0,
           objectives = {nil, nil, {{4}}}},
  [400] = {name = "Silk Delivery", questLevel = 18, requiredLevel = 14, requiredRaces = 0, requiredClasses = 0,
           objectives = {}, requiredSourceItems = {3}, exclusiveTo = {401}},
}
local function field(key) return function(id) return QUESTS[id] and QUESTS[id][key] end end
IDS = {100, 200, 300, 400}
C_Timer = {After = function(_, fn) fn() end}
LibQuestieDB = {
  RequireContract = function(n) return n == 2 end,
  Quest = {GetAllIds = function() return IDS end},
}
for _, key in ipairs({"name", "questLevel", "requiredLevel", "requiredRaces", "requiredClasses", "objectives",
                      "requiredSourceItems", "exclusiveTo"}) do
  LibQuestieDB.Quest[key] = field(key)
end
KeepOrSellDB.questie = true
"""


def quest(rt, **fields):
    defaults = {"id": 1, "name": "Q", "level": 20, "races": 0, "classes": 0}
    defaults.update(fields)
    body = ", ".join("%s = %s" % (k, repr(v) if isinstance(v, str) else v) for k, v in defaults.items())
    return rt.eval("{%s}" % body.replace("'", '"'))


class PickTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Questie.lua",), base=False)
        self.player = self.rt.eval("{level = 20, race = 4, class = 11, completed = function(id) return id == 99 end}")

    def pick(self, *quests):
        return self.ns.PickQuestieQuest(self.rt.eval("function(...) return {...} end")(*quests), self.player)

    def test_level_window_is_five_levels(self):
        self.assertEqual(self.pick(quest(self.rt, level=25)).name, "Q")
        self.assertEqual(self.pick(quest(self.rt, level=15)).name, "Q")
        self.assertIsNone(self.pick(quest(self.rt, level=26)))
        self.assertIsNone(self.pick(quest(self.rt, level=14)))

    def test_scaling_quest_level_counts(self):
        self.assertIsNotNone(self.pick(quest(self.rt, level=-1)))

    def test_missing_level_falls_back_to_required_level(self):
        self.assertIsNotNone(self.pick(quest(self.rt, level=0, requiredLevel=18)))
        self.assertIsNone(self.pick(quest(self.rt, level=0, requiredLevel=40)))

    def test_race_and_class_masks(self):
        night_elf, orc, druid, mage = 2 ** 3, 2 ** 1, 2 ** 10, 2 ** 7
        self.assertIsNotNone(self.pick(quest(self.rt, races=night_elf + orc)))
        self.assertIsNone(self.pick(quest(self.rt, races=orc)))
        self.assertIsNotNone(self.pick(quest(self.rt, classes=druid)))
        self.assertIsNone(self.pick(quest(self.rt, classes=mage)))

    def test_completed_quest_ignored(self):
        self.assertIsNone(self.pick(quest(self.rt, id=99)))

    def test_exclusive_quest_completed(self):
        q = quest(self.rt)
        q.exclusiveTo = self.rt.eval("{98, 99}")
        self.assertIsNone(self.pick(q))

    def test_closest_level_wins(self):
        far = quest(self.rt, id=1, name="Far", level=24)
        near = quest(self.rt, id=2, name="Near", level=19)
        self.assertEqual(self.pick(far, near).name, "Near")


class LookupTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)
        self.ns.BuildQuestieIndex()

    def test_finds_quest_for_item_objective(self):
        q = self.ns.GetQuestieQuest(4)
        self.assertEqual((q.name, q.level), ("Wolf Stew", 22))

    def test_required_source_item(self):
        self.assertEqual(self.ns.GetQuestieQuest(3).name, "Silk Delivery")

    def test_completed_and_exclusive(self):
        self.rt.execute("COMPLETED[100] = true")
        self.assertIsNone(self.ns.GetQuestieQuest(4))
        self.rt.execute("COMPLETED[401] = true")
        self.assertIsNone(self.ns.GetQuestieQuest(3))

    def test_level_up_moves_the_window(self):
        self.rt.execute("PLAYER_LEVEL = 28")
        self.assertEqual(self.ns.GetQuestieQuest(4).name, "Cloth Drive")

    def test_item_no_quest_needs(self):
        self.assertIsNone(self.ns.GetQuestieQuest(9))

    def test_errors_keep_the_item_unprotected_but_quiet(self):
        self.rt.execute("LibQuestieDB.Quest.questLevel = function() error('broken') end")
        self.assertIsNone(self.ns.GetQuestieQuest(4))


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)

    def test_nothing_before_the_index_is_built(self):
        self.assertIsNone(self.ns.GetQuestieQuest(4))

    def test_built_in_chunks_then_done(self):
        # 600 quests: three chunks, each in its own frame
        self.rt.execute("""
          FRAMES, DONE = 0, false
          C_Timer.After = function(_, fn) FRAMES = FRAMES + 1; fn() end
          for id = 1000, 1595 do IDS[#IDS + 1] = id end
        """)
        self.ns.BuildQuestieIndex(self.rt.eval("function() DONE = true end"))
        self.assertEqual(self.rt.eval("FRAMES"), 2)
        self.assertTrue(self.rt.eval("DONE"))
        self.assertEqual(self.ns.GetQuestieQuest(4).name, "Wolf Stew")

    def test_without_questiedb(self):
        self.rt.execute("LibQuestieDB = nil")
        self.ns.BuildQuestieIndex()
        self.assertIsNone(self.ns.GetQuestieQuest(4))

    def test_contract_mismatch(self):
        self.rt.execute("LibQuestieDB.RequireContract = function() return false, 'old' end")
        self.ns.BuildQuestieIndex()
        self.assertIsNone(self.ns.GetQuestieQuest(4))

    def test_broken_quest_is_skipped(self):
        self.rt.execute("""
          local objectives = LibQuestieDB.Quest.objectives
          LibQuestieDB.Quest.objectives = function(id) if id == 100 then error('broken') end return objectives(id) end
        """)
        self.ns.BuildQuestieIndex()
        self.assertIsNone(self.ns.GetQuestieQuest(4))  # Wolf Stew unreadable, the others out of range
        self.assertEqual(self.ns.GetQuestieQuest(3).name, "Silk Delivery")


class DecideTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)
        self.ns.BuildQuestieIndex()

    def test_cheap_linen_goes_to_quest(self):
        verdict = self.ns.Classify(4, "link4")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name), ("quest", "questie", "Wolf Stew"))

    def test_beats_auction_house(self):
        self.rt.execute("AH.link3 = 1000")
        self.assertEqual(self.ns.Classify(3, "link3").kind, "quest")

    def test_beats_profession(self):
        facts = self.rt.eval("{questie = {name = 'X', level = 20}, reagent = true}")
        self.assertEqual(self.ns.Decide(facts, self.rt.eval("KeepOrSellDB")).kind, "quest")

    def test_quest_log_wins(self):
        facts = self.rt.eval("{quest = 'open', questie = {name = 'X', level = 20}}")
        self.assertEqual(self.ns.Decide(facts, self.rt.eval("KeepOrSellDB")).reason, "open")

    def test_switch_off(self):
        self.rt.execute("KeepOrSellDB.questie = false; AH.link4 = 15")
        self.assertEqual(self.ns.Classify(4, "link4").kind, "junk")


class TooltipTextTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES + ("Tooltip.lua",), STUBS)

    def text(self, lua):
        return self.ns.TooltipText(self.rt.eval(lua), None, self.rt.eval("KeepOrSellDB"))

    def test_names_the_quest(self):
        self.assertIn('Quest – needed for "Wolf Stew" (level 22)',
                      self.text("{kind = 'quest', reason = 'questie', quest = {name = 'Wolf Stew', level = 22}}"))

    def test_scaling_quest_without_level(self):
        text = self.text("{kind = 'quest', reason = 'questie', quest = {name = 'Wolf Stew', level = -1}}")
        self.assertIn('needed for "Wolf Stew"', text)
        self.assertNotIn("level", text)


if __name__ == "__main__":
    unittest.main()
