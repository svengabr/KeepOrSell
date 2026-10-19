"""Tests for the warnings on deleting or selling items KeepOrSell would keep (Warnings.lua)."""
import unittest

from addon import CORE_FILES, load

# bag 0: slot 1 a Sealed Letter (quest item, 2), slot 2 Linen Cloth (cheap trade good, 4)
STUBS = """
BAG = {[1] = 2, [2] = 4}
C_Container = {
  GetContainerItemInfo = function(bag, slot) return BAG[slot] and {itemID = BAG[slot], hyperlink = "link" .. BAG[slot]} end,
  UseContainerItem = function() end,
}
AH = {link4 = 1}
HOOKS = {}
function hooksecurefunc(a, b, c)
  if type(a) == "table" then
    local original = a[b]
    a[b] = function(...) original(...); c(...) end
  else
    HOOKS[a] = b
  end
end
function StaticPopup_Show(which) if HOOKS.StaticPopup_Show then HOOKS.StaticPopup_Show(which) end end
CURSOR = nil
function GetCursorInfo() if CURSOR then return "item", CURSOR, "link" .. CURSOR end end
NOW = 0
function GetTime() return NOW end
PRINTED, ERRORS = {}, {}
function print(text) PRINTED[#PRINTED + 1] = text end
UIErrorsFrame = {AddMessage = function(_, text) ERRORS[#ERRORS + 1] = text end}
MERCHANT_OPEN = true
MerchantFrame = {IsShown = function() return MERCHANT_OPEN end}
KeepOrSellDB.lossWarnings = true
KeepOrSellDB.keep = {}
"""


class ShouldWarnTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Warnings.lua"), base=False)

    def warn(self, lua):
        return self.ns.ShouldWarnLoss(self.rt.eval(lua))

    def test_kept_verdicts_warn(self):
        for lua in ("{kind = 'quest'}", "{kind = 'profession'}", "{reason = 'kept'}", "{reason = 'classitem'}",
                    "{reason = 'tool'}", "{reason = 'equipset'}", "{kind = 'alt'}"):
            self.assertTrue(self.warn(lua), lua)

    def test_disposable_verdicts_stay_quiet(self):
        for lua in ("{kind = 'junk'}", "{kind = 'ah'}", "{kind = 'disenchant'}", "{kind = 'open'}", "{reason = 'new'}",
                    "{reason = 'wearable'}", "{}"):
            self.assertFalse(self.warn(lua), lua)
        self.assertFalse(self.ns.ShouldWarnLoss(None))

    def test_filter_keep_rule_warns_like_a_keep_mark(self):
        self.assertTrue(self.warn("{reason = 'filter', rule = 'item'}"))
        self.assertTrue(self.warn("{reason = 'filter', rule = 'category'}"))

    def test_other_filter_verdicts_stay_quiet(self):
        # a junk rule, an AH rule, and a category junk rule only waiting for a price
        self.assertFalse(self.warn("{kind = 'junk', reason = 'filter', rule = 'item'}"))
        self.assertFalse(self.warn("{kind = 'ah', reason = 'filter', rule = 'category'}"))
        self.assertFalse(self.warn("{reason = 'filter', rule = 'category', needsPrice = true}"))


class HookTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Tooltip.lua", "Warnings.lua"), STUBS)
        self.ns.HookLossWarnings()

    def printed(self):
        return list(self.rt.eval("PRINTED").values())

    def test_deleting_a_quest_item_warns(self):
        self.rt.execute("CURSOR = 2; StaticPopup_Show('DELETE_QUEST_ITEM')")
        self.assertEqual(len(self.printed()), 1)
        self.assertIn("You're destroying link2!", self.printed()[0])
        self.assertIn("Quest", self.printed()[0])
        self.assertEqual(len(self.rt.eval("ERRORS")), 1)

    def test_deleting_junk_is_quiet(self):
        self.rt.execute("CURSOR = 4; StaticPopup_Show('DELETE_ITEM')")
        self.assertEqual(self.printed(), [])

    def test_other_popups_are_ignored(self):
        self.rt.execute("CURSOR = 2; StaticPopup_Show('CONFIRM_LOOT_ROLL')")
        self.assertEqual(self.printed(), [])

    def test_selling_a_quest_item_warns_once(self):
        self.rt.execute("C_Container.UseContainerItem(0, 1); C_Container.UseContainerItem(0, 1)")
        self.assertEqual(len(self.printed()), 1)
        self.assertIn("You sold link2!", self.printed()[0])
        self.rt.execute("NOW = 5; C_Container.UseContainerItem(0, 1)")
        self.assertEqual(len(self.printed()), 2)

    def test_using_an_item_without_merchant_is_quiet(self):
        self.rt.execute("MERCHANT_OPEN = false; C_Container.UseContainerItem(0, 1)")
        self.assertEqual(self.printed(), [])

    def test_scrap_own_list_is_the_players_choice(self):
        self.rt.execute("Scrap = {IsJunk = function() return true end}; C_Container.UseContainerItem(0, 1)")
        self.assertEqual(self.printed(), [])

    def test_deleting_an_item_with_a_filter_keep_rule_warns(self):
        self.rt.execute("KeepOrSellDB.filter = {items = {[4] = 'keep'}, categories = {}}; CURSOR = 4; StaticPopup_Show('DELETE_ITEM')")
        self.assertEqual(len(self.printed()), 1)

    def test_option_off(self):
        self.rt.execute("KeepOrSellDB.lossWarnings = false; CURSOR = 2; StaticPopup_Show('DELETE_QUEST_ITEM')")
        self.assertEqual(self.printed(), [])


if __name__ == "__main__":
    unittest.main()
