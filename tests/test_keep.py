"""Tests for the player's keep marks (Keep.lua)."""
import unittest

from addon import load

STUBS = """
PRINTED = {}
print = function(text) table.insert(PRINTED, text) end
MOUSE, ALT, CTRL, SHIFT = "RightButton", true, false, false
function GetMouseButtonClicked() return MOUSE end
function IsAltKeyDown() return ALT end
function IsControlKeyDown() return CTRL end
function IsShiftKeyDown() return SHIFT end
HOOKS = {}
function HandleModifiedItemClick() end
function hooksecurefunc(name, fn) HOOKS[name] = fn end
BAG_SLOT = {IsBagAndSlot = function() return true end}
EQUIPPED = {IsBagAndSlot = function() return false end}
"""


class KeepTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(("Locales.lua", "Keep.lua"), STUBS)
        self.rt.execute("KeepOrSellDB.keepClick = true")
        self.ns.SettingsChanged = self.rt.eval("function() CHANGED = (CHANGED or 0) + 1 end")
        self.ns.HookKeepClick()

    def click(self, link="link4", location="BAG_SLOT"):
        self.rt.eval("function(link, loc) HOOKS.HandleModifiedItemClick(link, loc) end")(link, self.rt.eval(location))

    def test_keep_click(self):
        self.assertTrue(self.ns.IsKeepClick("RightButton", True, False, False))
        self.assertFalse(self.ns.IsKeepClick("LeftButton", True, False, False))
        self.assertFalse(self.ns.IsKeepClick("RightButton", False, False, False))
        self.assertFalse(self.ns.IsKeepClick("RightButton", True, True, False))  # Ctrl: dressing room
        self.assertFalse(self.ns.IsKeepClick("RightButton", True, False, True))  # Shift: chat link

    def test_alt_right_click_toggles(self):
        self.click()
        self.assertTrue(self.ns.IsKept(4))
        self.assertEqual(self.rt.eval("CHANGED"), 1)
        self.assertIn("link4", self.rt.eval("PRINTED[1]"))
        self.click()
        self.assertFalse(self.ns.IsKept(4))
        self.assertIsNone(self.rt.eval("KeepOrSellDB.keep[4]"))

    def test_only_bag_items(self):
        self.click(location="EQUIPPED")
        self.click(location="nil")
        self.assertFalse(self.ns.IsKept(4))

    def test_other_clicks_ignored(self):
        self.rt.execute("MOUSE = 'LeftButton'")
        self.click()
        self.assertFalse(self.ns.IsKept(4))

    def test_switched_off(self):
        self.rt.execute("KeepOrSellDB.keepClick = false")
        self.click()
        self.assertFalse(self.ns.IsKept(4))

    def test_slash_keep_and_unkeep(self):
        self.assertTrue(self.ns.HandleKeepCommand("keep |cffffffff|Hitem:4::::|h[Linen Cloth]|h|r"))
        self.assertTrue(self.ns.IsKept(4))
        self.assertTrue(self.ns.HandleKeepCommand("unkeep 4"))
        self.assertFalse(self.ns.IsKept(4))

    def test_slash_usage_and_list(self):
        self.assertTrue(self.ns.HandleKeepCommand("keep"))
        self.assertIn("/kos keep", self.rt.eval("PRINTED[1]"))
        self.ns.HandleKeepCommand("keep 3")
        self.ns.HandleKeepCommand("kept")
        self.assertIn("link3", self.rt.eval("PRINTED[#PRINTED]"))
        self.assertFalse(self.ns.HandleKeepCommand("setup"))
        self.assertFalse(self.ns.HandleKeepCommand(""))

    def test_forget_all(self):
        self.ns.HandleKeepCommand("keep 3")
        self.ns.HandleKeepCommand("keep 4")
        self.assertEqual(self.ns.ForgetKept(), 2)
        self.assertFalse(self.ns.IsKept(3))
        self.ns.HandleKeepCommand("kept")
        self.assertIn("No kept items", self.rt.eval("PRINTED[#PRINTED]"))


if __name__ == "__main__":
    unittest.main()
