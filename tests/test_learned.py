"""Tests for quests remembered from the quest log (Objectives.lua) that QuestieDB doesn't know."""
import unittest

from addon import CORE_FILES, load

# Quest 900 "A Forever Tale" (level 30) is in the log, wants Linen Cloth (4) and gives the Torn Note (30)
# to use; QuestieDB knows quest 100 but not 900.
STUBS = """
function UnitLevel() return 20 end
function UnitRace() return "Night Elf", "NightElf", 4 end
function UnitFactionGroup() return "Alliance", "Alliance" end
ITEMS[30] = {"Torn Note", 15, 0, "", 0}
COMPLETED = {}
LOG = {
  {questID = 900, title = "A Forever Tale", level = 30, objectives = {{type = "item", text = "Linen Cloth: 2/5"}},
   special = "|cffffffff|Hitem:30::::::::20:::::|h[Torn Note]|h|r"},
  {questID = 100, title = "Wolf Stew", level = 22, objectives = {{type = "item", text = "Silk Cloth: 0/3"}}},
}
C_QuestLog = {
  IsQuestFlaggedCompleted = function(id) return COMPLETED[id] == true end,
  GetNumQuestLogEntries = function() return #LOG end,
  GetInfo = function(i) return LOG[i] and {questID = LOG[i].questID, title = LOG[i].title, level = LOG[i].level} end,
  GetQuestObjectives = function(id)
    for _, q in ipairs(LOG) do if q.questID == id then return q.objectives end end
    return {}
  end,
}
function GetQuestLogSpecialItemInfo(i) return LOG[i] and LOG[i].special end
C_Timer = {After = function(_, fn) fn() end}
LibQuestieDB = {
  RequireContract = function(n) return n == 2 end,
  Quest = {GetAllIds = function() return {} end, name = function(id) return id == 100 and "Wolf Stew" or nil end},
}
KeepOrSellDB.questie = true
"""


class PickLearnedTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Objectives.lua",), base=False)
        self.player = self.rt.eval("{faction = 'Alliance', completed = function(id) return id == 99 end}")

    def pick(self, lua):
        return self.ns.PickLearnedQuest(self.rt.eval(lua), self.player)

    def test_open_quest_of_the_own_faction(self):
        self.assertEqual(self.pick("{[1] = {name = 'A', level = 10, faction = 'Alliance'}}").name, "A")

    def test_other_faction_and_done_quests_left_out(self):
        self.assertIsNone(self.pick("{[1] = {name = 'H', faction = 'Horde'}, [99] = {name = 'D', faction = 'Alliance'}}"))

    def test_lowest_level_first(self):
        self.assertEqual(self.pick("{[1] = {name = 'High', level = 40, faction = 'Alliance'},"
                                   " [2] = {name = 'Low', level = 12, faction = 'Alliance'}}").name, "Low")

    def test_nothing_learned(self):
        self.assertIsNone(self.pick("{}"))


class LearnTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES, STUBS)
        self.ns.Refresh()

    def learned(self):
        return self.rt.eval("KeepOrSellDB.learnedQuests")

    def test_remembers_quests_questie_lacks(self):
        quest = self.learned()["Linen Cloth"][900]
        self.assertEqual((quest.name, quest.level, quest.faction), ("A Forever Tale", 30, "Alliance"))

    def test_remembers_the_item_to_use(self):
        self.assertEqual(self.learned()["Torn Note"][900].name, "A Forever Tale")

    def test_quests_questie_knows_are_not_remembered(self):
        self.assertIsNone(self.learned()["Silk Cloth"])

    def test_nothing_learned_without_questiedb(self):
        self.rt.execute("LibQuestieDB = nil; KeepOrSellDB.learnedQuests = nil")
        rt, ns = load(CORE_FILES, STUBS + "LibQuestieDB = nil")
        ns.Refresh()
        self.assertIsNone(next(iter(rt.eval("KeepOrSellDB.learnedQuests or {}").items()), None))

    def test_alt_keeps_the_item_after_the_quest_left_the_log(self):
        self.rt.execute("LOG = {}")
        self.ns.Refresh()
        verdict = self.ns.Classify(30, "link30")
        self.assertEqual((verdict.kind, verdict.reason, verdict.quest.name), ("quest", "learned", "A Forever Tale"))

    def test_done_quest_frees_the_item(self):
        self.rt.execute("LOG = {}; COMPLETED[900] = true")
        self.ns.Refresh()
        self.assertNotEqual(self.ns.Classify(30, "link30").reason, "learned")

    def test_questie_option_off(self):
        self.rt.execute("LOG = {}; KeepOrSellDB.questie = false")
        self.ns.Refresh()
        self.assertNotEqual(self.ns.Classify(30, "link30").reason, "learned")

    def test_tooltip(self):
        rt, ns = load(CORE_FILES + ("Tooltip.lua",), STUBS)
        text = ns.TooltipText(rt.eval("{kind = 'quest', reason = 'learned', quest = {name = 'A Forever Tale'}}"),
                              None, rt.eval("KeepOrSellDB"))
        self.assertIn('Quest – needed for "A Forever Tale" (seen in a quest log)', text)


if __name__ == "__main__":
    unittest.main()
