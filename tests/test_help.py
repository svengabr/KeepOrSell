"""Tests for the shortcut list behind the question mark in Baganator's bag window (Help.lua)."""
import unittest

from addon import CORE_FILES, load


class HelpLineTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Help.lua",))
        self.L = self.ns.L

    def lines(self, **db):
        table = self.ns.HelpLines(self.rt.table_from(db))
        return [(row[1], row[2]) for row in table.values()]

    def keys(self, **db):
        return [key for key, _ in self.lines(**db)]

    def test_lists_keep_click_and_slash_commands(self):
        rows = self.lines(keepClick=True, destroy=True)
        self.assertIn((self.L.HELP_KEEP_KEY, self.L.HELP_KEEP), rows)
        self.assertIn((self.L.HELP_DESTROY_KEY, self.L.HELP_DESTROY), rows)
        for command in ("/kos", "/kos kept", "/kos keep <item>", "/kos setup", "/kos export", "/kos import"):
            self.assertIn(command, self.keys(keepClick=True, destroy=True))

    def test_keep_click_comes_first(self):
        self.assertEqual(self.keys(keepClick=True, destroy=True)[0], self.L.HELP_KEEP_KEY)

    def test_switched_off_options_are_left_out(self):
        keys = self.keys(keepClick=False, destroy=False)
        self.assertNotIn(self.L.HELP_KEEP_KEY, keys)
        self.assertNotIn(self.L.HELP_DESTROY_KEY, keys)
        self.assertIn("/kos", keys)

    def test_every_row_has_a_text(self):
        for key, text in self.lines(keepClick=True, destroy=True):
            self.assertTrue(key)
            self.assertTrue(text)


BAGANATOR = """
local function Widget()
  local w = {shown = true}
  return setmetatable(w, {__index = function(_, key)
    if key == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if key == "IsShown" then return function(self) return self.shown end end
    if key == "SetWidth" then return function(self, v) self.width = v end end
    if key == "GetTextWidth" then return function() return 40 end end
    if key == "SetScript" then return function(self, name, fn) self[name] = fn end end
    return function() return Widget() end
  end})
end
CreateFrame = function() return Widget() end
UIParent = Widget()
GameTooltip = Widget()
Baganator = {API = {RegisterRegion = function(_, _, _, _, frame) REGION = frame end}}
"""


class HelpButtonTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Help.lua",), BAGANATOR)
        self.rt.execute("KeepOrSellDB.helpButton = true")
        self.ns.RegisterHelp()

    def test_option_hides_the_button(self):
        self.ns.UpdateHelp()
        self.assertTrue(self.rt.eval("REGION.shown"))
        self.rt.execute("KeepOrSellDB.helpButton = false")
        self.ns.UpdateHelp()
        self.assertFalse(self.rt.eval("REGION.shown"))
        self.assertEqual(self.rt.eval("REGION.width"), 1)  # a hidden region still takes its width
        self.rt.execute("KeepOrSellDB.helpButton = true")
        self.ns.UpdateHelp()
        self.assertTrue(self.rt.eval("REGION.shown"))
        self.assertEqual(self.rt.eval("REGION.width"), 60)

    def test_click_opens_the_window(self):
        self.rt.eval("function(ns) ns.ShowOptionsWindow = function() OPENED = true end end")(self.ns)
        self.rt.eval("REGION").OnClick()
        self.assertTrue(self.rt.eval("OPENED"))


if __name__ == "__main__":
    unittest.main()
