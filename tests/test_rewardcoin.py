"""Tests for the coin on the quest reward with the highest vendor value (RewardCoin.lua)."""
import unittest

from addon import load

# a reward panel with three choice buttons; REWARDS[i] = {itemID, count}
REWARD_UI = """
C_Timer = {After = function(_, fn) TIMERS = (TIMERS or 0) + 1; if TIMERS < 50 then fn() end end}
function GetMoneyString(v) return v .. "c" end
REWARDS = {}
UNCACHED = {}
function GetQuestItemLink(kind, i) return kind == "choice" and REWARDS[i] and "link" .. REWARDS[i][1] or nil end
function GetQuestItemInfo(kind, i) return "name", 0, REWARDS[i] and REWARDS[i][2] or 1 end
function GetQuestLogItemLink(kind, i) return GetQuestItemLink(kind, i) end
function GetQuestLogChoiceInfo(i) return GetQuestItemInfo("choice", i) end
local realInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(link)
  local id = tonumber(link:match("%d+"))
  if UNCACHED[id] then return nil end
  return realInfo(link)
end
local function Button(i)
  local b = {type = "choice", id = i, shown = true, Icon = {}}
  function b:GetID() return self.id end
  function b:IsShown() return self.shown end
  function b:CreateTexture()
    local coin = {shown = false}
    function coin:Show() self.shown = true end
    function coin:Hide() self.shown = false end
    for _, name in ipairs({"SetTexture", "SetSize", "SetPoint"}) do coin[name] = function() end end
    b.coin = coin
    return coin
  end
  return b
end
BUTTONS = {Button(1), Button(2), Button(3)}
QuestInfoFrame = {rewardsFrame = {RewardButtons = BUTTONS, IsShown = function() return true end}}
function QuestInfo_Display() end
function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...) orig(...); fn(...) end
end
function COIN(i) return BUTTONS[i].coin ~= nil and BUTTONS[i].coin.shown end
"""

FILES = ("Locales.lua", "RewardCoin.lua")


class BestRewardTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def best(self, *choices):
        lua = "{" + ",".join(
            "{index=%d, price=%s, count=%d}" % (i, "nil" if p is None else p, c) for i, p, c in choices) + "}"
        result = self.rt.eval(f"function(ns) return ns.BestRewardChoices({lua}) end")(self.ns)
        return dict(result.items())

    def test_highest_value_wins(self):
        self.assertEqual(self.best((1, 100, 1), (2, 250, 1), (3, 50, 1)), {2: 250})

    def test_count_multiplies_price(self):
        self.assertEqual(self.best((1, 100, 1), (2, 30, 5)), {2: 150})

    def test_ties_all_get_the_coin(self):
        self.assertEqual(self.best((1, 100, 1), (2, 100, 1)), {1: 100, 2: 100})

    def test_nothing_to_choose(self):
        self.assertEqual(self.best((1, 100, 1)), {})

    def test_unknown_price_shows_nothing(self):
        self.assertEqual(self.best((1, 100, 1), (2, None, 1)), {})

    def test_nothing_sells(self):
        self.assertEqual(self.best((1, 0, 1), (2, 0, 1)), {})


class RewardCoinTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, REWARD_UI)
        self.rt.execute("KeepOrSellDB.rewardCoin = true")
        self.ns.HookRewardCoin()

    def show(self, *rewards):
        for i, (item, count) in enumerate(rewards, 1):
            self.rt.execute(f"REWARDS[{i}] = {{{item}, {count}}}")
        self.rt.execute(f"for i = 1, 3 do BUTTONS[i].shown = i <= {len(rewards)} end")
        self.rt.execute("QuestInfo_Display()")

    def coins(self):
        return [bool(self.rt.eval(f"COIN({i})")) for i in (1, 2, 3)]

    def test_coin_on_most_valuable_choice(self):
        self.show((4, 1), (5, 1), (9, 1))  # linen 13, mail vest 100, potion 40
        self.assertEqual(self.coins(), [False, True, False])

    def test_tooltip_names_the_value(self):
        self.show((4, 1), (5, 1))
        self.assertIn("100c", self.ns.RewardTooltipNote(self.rt.eval("BUTTONS[2]")))
        self.assertIsNone(self.ns.RewardTooltipNote(self.rt.eval("BUTTONS[1]")))

    def test_off_by_option(self):
        self.rt.execute("KeepOrSellDB.rewardCoin = false")
        self.show((4, 1), (5, 1))
        self.assertEqual(self.coins(), [False, False, False])

    def test_coin_moves_with_the_next_quest(self):
        self.show((4, 1), (5, 1))
        self.show((9, 1), (4, 1))
        self.assertEqual(self.coins(), [True, False, False])

    def test_waits_for_uncached_items(self):
        self.rt.execute("UNCACHED[5] = true")
        self.show((4, 1), (5, 1))
        self.assertEqual(self.coins(), [False, False, False])
        self.rt.execute("UNCACHED[5] = nil; TIMERS = 0")
        self.rt.execute("C_Timer.After = function(_, fn) fn() end")
        self.rt.execute("QuestInfo_Display()")
        self.assertEqual(self.coins(), [False, True, False])

    def test_hidden_buttons_dont_count(self):
        self.show((4, 1), (5, 1), (9, 1))
        self.show((4, 1), (9, 1))
        self.assertEqual(self.coins(), [False, True, False])


if __name__ == "__main__":
    unittest.main()
