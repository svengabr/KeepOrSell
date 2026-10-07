"""Tests for the setup window logic (Setup.lua)."""
import json
import unittest

from addon import CORE_FILES, load

FILES = CORE_FILES + ("Dependencies.lua", "Setup.lua")


def steps_by_key(ns, rt, **state):
    steps = ns.SetupSteps(rt.table_from(state))
    return {step.key: step for step in steps.values()}, steps


class StepsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def test_fresh_install_needs_everything(self):
        steps, raw = steps_by_key(self.ns, self.rt)
        for key in ("baganator", "view", "auctionator", "scan"):
            self.assertFalse(steps[key].done, key)
            self.assertTrue(steps[key].required, key)
        self.assertFalse(steps["scrap"].required)
        self.assertFalse(steps["questie"].required)
        self.assertFalse(self.ns.SetupComplete(raw))

    def test_all_required_done(self):
        _, raw = steps_by_key(self.ns, self.rt, baganator=True, baganatorSetup=True, auctionator=True, ahVisited=True)
        self.assertTrue(self.ns.SetupComplete(raw))

    def test_optional_steps_dont_block(self):
        steps, raw = steps_by_key(self.ns, self.rt, baganator=True, baganatorSetup=True, auctionator=True,
                                  ahVisited=True, scrap=False, questie=False)
        self.assertFalse(steps["scrap"].done)
        self.assertTrue(self.ns.SetupComplete(raw))

    def test_scan_needs_a_visit(self):
        steps, _ = steps_by_key(self.ns, self.rt, auctionator=True, ahVisited=False)
        self.assertTrue(steps["auctionator"].done)
        self.assertFalse(steps["scan"].done)

    def test_visit_without_auctionator_is_no_scan(self):
        steps, _ = steps_by_key(self.ns, self.rt, auctionator=False, ahVisited=True)
        self.assertFalse(steps["scan"].done)

    def test_tsm_alone_brings_prices(self):
        # like the hints: TSM prices already sort items, there is no scan to hint at
        steps, _ = steps_by_key(self.ns, self.rt, tsm=True)
        self.assertTrue(steps["auctionator"].done)
        self.assertTrue(steps["scan"].done)

    def test_steps_keep_their_order(self):
        _, raw = steps_by_key(self.ns, self.rt)
        self.assertEqual([s.key for s in raw.values()],
                         ["baganator", "view", "auctionator", "scan", "scrap", "questie"])


class ProgressTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def test_counts_required_steps_only(self):
        _, raw = steps_by_key(self.ns, self.rt, baganator=True, auctionator=True, scrap=True, questie=True)
        self.assertEqual(self.ns.SetupProgress(raw), (2, 4))

    def test_complete(self):
        _, raw = steps_by_key(self.ns, self.rt, baganator=True, baganatorSetup=True, auctionator=True, ahVisited=True)
        self.assertEqual(self.ns.SetupProgress(raw), (4, 4))


# minimal widgets: every unknown method is a no-op returning another widget
FRAMES = """
local function Widget()
  local w = {shown = false}
  return setmetatable(w, {__index = function(_, key)
    if key == "Show" then return function(self) self.shown = true; if self.OnShow then self.OnShow(self) end end end
    if key == "Hide" then return function(self) self.shown = false end end
    if key == "IsShown" then return function(self) return self.shown end end
    if key == "Inset" then return Widget() end -- child frame of ButtonFrameTemplate
    if key == "GetWidth" then return function() return 400 end end
    if key == "SetText" then return function(self, text) self.text = text end end
    if key == "SetScript" then return function(self, name, fn) self[name] = fn end end
    return function() return Widget() end
  end})
end
CreateFrame = function() return Widget() end
UIParent = Widget()
GameTooltip = Widget()
UISpecialFrames = {}
"""


class WindowTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES + ("Baganator.lua",), FRAMES)

    def test_builds_and_shows(self):
        self.ns.ShowSetup()
        frame = self.rt.eval("UISpecialFrames[1]")
        self.assertEqual(frame, "KeepOrSellSetupFrame")

    def test_opens_after_login_while_incomplete(self):
        self.ns.MaybeShowSetup()
        self.assertEqual(len(self.rt.eval("UISpecialFrames")), 1)

    def test_stays_closed_when_hidden(self):
        self.rt.execute("KeepOrSellDB.setupHidden = true")
        self.ns.MaybeShowSetup()
        self.assertEqual(len(self.rt.eval("UISpecialFrames")), 0)

    def test_waits_for_baganator_welcome(self):
        self.rt.execute("""
        Baganator_WelcomeFrame = {shown = true, IsShown = function(self) return self.shown end,
          HookScript = function(self, _, fn) self.onHide = fn end}
        """)
        self.ns.MaybeShowSetup()
        self.assertEqual(len(self.rt.eval("UISpecialFrames")), 0)
        self.rt.execute("Baganator_WelcomeFrame.shown = false; Baganator_WelcomeFrame.onHide()")
        self.assertEqual(len(self.rt.eval("UISpecialFrames")), 1)


class ShowTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def test_shows_while_incomplete(self):
        self.assertTrue(self.ns.ShouldShowSetup(False, False))

    def test_hidden_by_checkbox(self):
        self.assertFalse(self.ns.ShouldShowSetup(True, False))

    def test_not_when_complete(self):
        self.assertFalse(self.ns.ShouldShowSetup(False, True))


class StateTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, """
        C_AddOns = {
          IsAddOnLoaded = function(name) return LOADED[name] or false end,
          DoesAddOnExist = function(name) return LOADED[name] ~= nil end,
        }
        LOADED = {Baganator = true, Auctionator = true}
        """)

    def test_reads_addons_and_db(self):
        state = self.ns.GetSetupState()
        self.assertTrue(state.baganator)
        self.assertTrue(state.auctionator)
        self.assertTrue(state.ahVisited)  # BASE_STUBS has ahVisited
        self.assertFalse(state.baganatorSetup)
        self.assertFalse(state.scrap)

    def test_baganator_setup_is_per_character(self):
        self.ns.MarkBaganatorSetup()
        self.assertTrue(self.ns.GetSetupState().baganatorSetup)
        self.rt.execute('function UnitName() return "Alt" end')
        self.assertFalse(self.ns.GetSetupState().baganatorSetup)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, """
        IMPORTS = {}
        Baganator = {API = {ImportString = function(text, name) table.insert(IMPORTS, {text, name}) end}}
        """)

    def test_imports_category_profile(self):
        self.assertTrue(self.ns.SetupBaganator())
        imports = list(self.rt.eval("IMPORTS").values())
        self.assertEqual(len(imports), 1)
        profile = json.loads(imports[0][1])
        self.assertEqual(imports[0][2], "KeepOrSell")
        self.assertEqual(profile["addon"], "Baganator")
        self.assertEqual(profile["kind"], "profile")
        self.assertEqual(profile["bag_view_type"], "category")
        self.assertEqual(profile["bank_view_type"], "category")
        self.assertTrue(self.ns.GetSetupState().baganatorSetup)

    def test_failed_import_is_not_marked(self):
        self.rt.execute('Baganator.API.ImportString = function() error("Invalid Baganator import") end')
        self.assertFalse(self.ns.SetupBaganator())
        self.assertFalse(self.ns.GetSetupState().baganatorSetup)

    def test_without_baganator(self):
        self.rt.execute("Baganator = nil")
        self.assertFalse(self.ns.SetupBaganator())


if __name__ == "__main__":
    unittest.main()
