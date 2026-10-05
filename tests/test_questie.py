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
                      "requiredSourceItems", "exclusiveTo", "startedBy", "sourceItemId"}) do
  LibQuestieDB.Quest[key] = field(key)
end
-- item 12 "Okra" is of the quest item class (12); quest 500 "Westfall Stew" (level 14) wants it
ITEMS[12] = {"Okra", 12, 0, "", 15}
QUESTS[500] = {name = "Westfall Stew", questLevel = 14, requiredLevel = 10, requiredRaces = 0, requiredClasses = 0,
               objectives = {nil, nil, {{12}}}}
IDS[#IDS + 1] = 500
-- item 20 "Arcanic Systems Manual" (miscellaneous) starts quest 600 (level 35), item 21 "Explorer's Kit"
-- (miscellaneous) is handed out by quest 700 (level 40); both exist only for their quest
ITEMS[20] = {"Arcanic Systems Manual", 15, 0, "", 0}
ITEMS[21] = {"Explorer's Kit", 15, 0, "", 0}
QUESTS[600] = {name = "Arcanic Systems Manual", questLevel = 35, requiredLevel = 30, requiredRaces = 0,
               requiredClasses = 0, startedBy = {nil, nil, {20}}}
QUESTS[700] = {name = "Into the Wilds", questLevel = 40, requiredLevel = 35, requiredRaces = 0,
               requiredClasses = 0, objectives = {nil, nil, {{4}}}, sourceItemId = 21}
IDS[#IDS + 1] = 600
IDS[#IDS + 1] = 700
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


class PickQuestItemTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Questie.lua",), base=False)
        self.player = self.rt.eval("{level = 20, race = 4, class = 11, completed = function(id) return id == 99 end}")

    def pick_item(self, *quests):
        return self.ns.PickQuestItemQuest(self.rt.eval("function(...) return {...} end")(*quests), self.player)

    def test_any_level(self):
        self.assertEqual(self.pick_item(quest(self.rt, level=50)).name, "Q")

    def test_open_quest_before_done_one(self):
        done = quest(self.rt, id=99, name="Done", level=20)
        far = quest(self.rt, id=1, name="Far", level=40)
        self.assertEqual(self.pick_item(done, far).name, "Far")

    def test_done_quest_is_marked(self):
        q = self.pick_item(quest(self.rt, id=99, name="Done"))
        self.assertEqual((q.name, q.done), ("Done", True))

    def test_other_race_only(self):
        self.assertIsNone(self.pick_item(quest(self.rt, races=2 ** 1)))


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

    def test_quest_item_quest_at_any_level(self):
        self.assertIsNone(self.ns.GetQuestieQuest(12))
        q = self.ns.GetQuestItemQuest(12)
        self.assertEqual((q.name, q.level, q.done), ("Westfall Stew", 14, None))
        self.rt.execute("COMPLETED[500] = true")
        self.assertTrue(self.ns.GetQuestItemQuest(12).done)

    def test_quest_starter_and_handed_out_items_are_quest_only(self):
        self.assertTrue(self.ns.IsQuestOnlyItem(20))
        self.assertTrue(self.ns.IsQuestOnlyItem(21))
        self.assertEqual(self.ns.GetQuestItemQuest(20).name, "Arcanic Systems Manual")
        self.assertEqual(self.ns.GetQuestItemQuest(21).name, "Into the Wilds")

    def test_objectives_are_not_quest_only(self):
        self.assertFalse(self.ns.IsQuestOnlyItem(4))
        self.assertFalse(self.ns.IsQuestOnlyItem(3))
        self.assertFalse(self.ns.IsQuestOnlyItem(9))

    def test_errors_keep_the_item_unprotected_but_quiet(self):
        self.rt.execute("LibQuestieDB.Quest.questLevel = function() error('broken') end")
        self.assertIsNone(self.ns.GetQuestieQuest(4))


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, STUBS)

    def test_nothing_before_the_index_is_built(self):
        self.assertIsNone(self.ns.GetQuestieQuest(4))
        self.assertFalse(self.ns.IsQuestOnlyItem(20))

    def test_questiedb_without_start_fields(self):
        self.rt.execute("LibQuestieDB.Quest.startedBy = nil; LibQuestieDB.Quest.sourceItemId = nil")
        self.ns.BuildQuestieIndex()
        self.assertEqual(self.ns.GetQuestieQuest(4).name, "Wolf Stew")
        self.assertFalse(self.ns.IsQuestOnlyItem(20))

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

    def test_quest_item_names_its_quest(self):
        verdict = self.ns.Classify(12, "link12")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name), ("quest", "questitem", "Westfall Stew"))

    def test_done_quest_item_is_junk(self):
        self.rt.execute("COMPLETED[500] = true; AH.link12 = 5")
        verdict = self.ns.Classify(12, "link12")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name), ("junk", "questitem_done", "Westfall Stew"))

    def test_done_quest_item_worth_auctioning(self):
        self.rt.execute("COMPLETED[500] = true; AH.link12 = 500")
        self.assertEqual(self.ns.Classify(12, "link12").kind, "ah")

    def test_done_quest_item_without_price_stays(self):
        self.rt.execute("COMPLETED[500] = true")
        verdict = self.ns.Classify(12, "link12")
        self.assertIsNone(verdict.kind)
        self.assertTrue(verdict.needsPrice)

    def test_done_quest_item_bound_is_junk(self):
        self.rt.execute("COMPLETED[500] = true; BOUND[12] = true")
        self.assertEqual(self.ns.Classify(12, "link12").kind, "junk")

    def test_done_quest_item_kept_with_questie_off(self):
        self.rt.execute("COMPLETED[500] = true; AH.link12 = 5; KeepOrSellDB.questie = false")
        self.assertEqual(self.ns.Classify(12, "link12").reason, "questitem")

    def test_quest_starter_kept_while_its_quest_is_open(self):
        verdict = self.ns.Classify(20, "link20")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name),
                         ("quest", "questitem", "Arcanic Systems Manual"))

    def test_quest_starter_is_junk_once_its_quest_is_done(self):
        self.rt.execute("COMPLETED[600] = true; BOUND[20] = true")
        verdict = self.ns.Classify(20, "link20")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name),
                         ("junk", "questitem_done", "Arcanic Systems Manual"))

    def test_handed_out_item_is_junk_once_its_quest_is_done(self):
        self.rt.execute("COMPLETED[700] = true; BOUND[21] = true")
        self.assertEqual(self.ns.Classify(21, "link21").reason, "questitem_done")

    def test_quest_starter_left_alone_with_questie_off(self):
        self.rt.execute("COMPLETED[600] = true; BOUND[20] = true; KeepOrSellDB.questie = false")
        self.assertIsNone(self.ns.Classify(20, "link20").kind)
        self.rt.execute("COMPLETED[600] = nil")
        self.assertIsNone(self.ns.Classify(20, "link20").kind)

    def test_objective_never_junk_for_done_quests(self):
        self.rt.execute("for _, id in ipairs({100, 200, 300, 700}) do COMPLETED[id] = true end")
        self.assertNotEqual(self.ns.Classify(4, "link4").reason, "questitem_done")

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

    def test_quest_item_names_its_quest(self):
        self.assertIn('Quest – quest item for "Westfall Stew" (level 14)',
                      self.text("{kind = 'quest', reason = 'questitem', quest = {name = 'Westfall Stew', level = 14}}"))

    def test_quest_item_quest_done(self):
        self.assertIn('quest item for "Westfall Stew" (already done)',
                      self.text("{kind = 'quest', reason = 'questitem', quest = {name = 'Westfall Stew', level = 14, done = true}}"))

    def test_done_quest_item_junk(self):
        text = self.text("{kind = 'junk', reason = 'questitem_done', quest = {name = 'Westfall Stew', done = true}, bound = true}")
        self.assertIn('Junk – "Westfall Stew" already done, soulbound', text)

    def test_quest_item_without_questie(self):
        self.assertIn("Quest – quest item", self.text("{kind = 'quest', reason = 'questitem'}"))


if __name__ == "__main__":
    unittest.main()
