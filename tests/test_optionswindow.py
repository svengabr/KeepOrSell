"""Tests for the own options window (OptionsWindow.lua) against stubbed widgets."""
import unittest

from addon import CORE_FILES, load

FILES = CORE_FILES + ("Dependencies.lua", "Style.lua", "OptionSections.lua", "OptionsWindow.lua")

# Widgets that remember what the window does to them; unknown methods are no-ops returning another widget
FRAMES = """
local function Widget(kind, parent)
  local w = {kind = kind, parent = parent, shown = true, enabled = true, checked = false, alpha = 1, value = 0}
  local methods = {
    Show = function(self) self.shown = true; if self.OnShow then self.OnShow(self) end end,
    Hide = function(self) self.shown = false end,
    IsShown = function(self) return self.shown end,
    SetShown = function(self, v) self.shown = v and true or false end,
    Enable = function(self) self.enabled = true end,
    Disable = function(self) self.enabled = false end,
    SetEnabled = function(self, v) self.enabled = v and true or false end,
    IsEnabled = function(self) return self.enabled end,
    SetChecked = function(self, v) self.checked = v and true or false end,
    GetChecked = function(self) return self.checked end,
    SetValue = function(self, v) self.value = v; if self.OnValueChanged then self.OnValueChanged(self, v, false) end end,
    GetValue = function(self) return self.value end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text end,
    SetAlpha = function(self, a) self.alpha = a end,
    GetAlpha = function(self) return self.alpha end,
    SetScript = function(self, name, fn) self[name] = fn end,
    GetScript = function(self, name) return self[name] end,
    SetScrollChild = function(self, child) self.scrollChild = child end,
    SetTexture = function(self, texture) self.texture = texture end,
    SetSize = function(self, w, h) self.width, self.height = w, h end,
    GetWidth = function() return 400 end,
    GetHeight = function() return 400 end,
    GetStringWidth = function() return 50 end,
    GetTextWidth = function() return 50 end,
    CreateFontString = function(self) return Widget("FontString", self) end,
    CreateTexture = function(self) return Widget("Texture", self) end,
  }
  return setmetatable(w, {__index = function(_, key)
    if methods[key] then return methods[key] end
    if key == "Inset" then return Widget("Frame") end
    return function() return Widget("Frame") end
  end})
end
CreateFrame = function(kind, name, parent)
  local w = Widget(kind, parent)
  w.name = name
  if kind == "ScrollFrame" then w.ScrollBar = Widget("Slider", w) end -- UIPanelScrollFrameTemplate's bar
  return w
end
UIParent = Widget("Frame")
GameTooltip = Widget("Frame")
UISpecialFrames = {}
C_Timer = {After = function(_, fn) fn() end}
LOADED = {Auctionator = true, Scrap = true}
C_AddOns = {
  IsAddOnLoaded = function(name) return LOADED[name] == true end,
  DoesAddOnExist = function(name) return LOADED[name] == true end,
}
function UnitFactionGroup() return "Alliance" end
"""

ALTS = """KeepOrSellDB.characters = {
  ['Tester-Realm'] = {faction = 'Alliance', realm = 'Realm'},
  ['Amy-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'PRIEST'},
  ['Bob-Realm'] = {faction = 'Alliance', realm = 'Realm', class = 'MAGE'}}
KeepOrSellDB.altSettings = {}"""


class OptionsWindowTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES, FRAMES)
        self.rt.execute("""
          KeepOrSellDB.destroy, KeepOrSellDB.keepClick, KeepOrSellDB.accountMode = true, true, true
          KeepOrSellDB.altSettings = {}
          CHANGED = 0
        """)
        self.rt.eval("function(ns) ns.SettingsChanged = function() CHANGED = CHANGED + 1 end end")(self.ns)

    def widget(self, key):
        return self.ns.OptionsWidget(key)

    def click(self, key):
        w = self.widget(key)
        w.checked = not w.checked
        w.OnClick(w)

    def frame(self):
        return self.rt.eval("_G")["KeepOrSellOptionsFrame"] or self.ns.OptionsFrame()

    def test_builds_and_toggles(self):
        self.ns.ToggleOptionsWindow()
        self.assertTrue(self.ns.OptionsFrame().shown)
        self.assertIn("KeepOrSellOptionsFrame", list(self.rt.eval("UISpecialFrames").values()))
        self.ns.ToggleOptionsWindow()
        self.assertFalse(self.ns.OptionsFrame().shown)

    def test_checkbox_shows_and_writes_saved_variable(self):
        self.ns.ShowOptionsWindow("junk")
        self.assertTrue(self.widget("gear").checked)
        self.click("gear")
        self.assertIs(self.rt.eval("KeepOrSellDB.gear"), False)
        self.assertEqual(self.rt.eval("CHANGED"), 1)

    def test_checkbox_without_refresh_flag(self):
        self.ns.ShowOptionsWindow("keep")
        self.click("keepClick")
        self.assertIs(self.rt.eval("KeepOrSellDB.keepClick"), False)
        self.assertEqual(self.rt.eval("CHANGED"), 0)

    def test_slider_shows_value_and_label(self):
        self.ns.ShowOptionsWindow("ah")
        factor = self.widget("factor")
        self.assertEqual(factor.value, 2)
        factor.OnValueChanged(factor, 3.04, True)
        self.assertAlmostEqual(self.rt.eval("KeepOrSellDB.factor"), 3.0)
        self.assertEqual(factor.label.text, "3x")

    def test_remembers_section(self):
        self.ns.ShowOptionsWindow("display")
        self.assertEqual(self.rt.eval("KeepOrSellDB.optionsSection"), "display")
        self.ns.OptionsFrame().Hide(self.ns.OptionsFrame())
        self.ns.ShowOptionsWindow()
        self.assertTrue(self.ns.OptionsPage("display").shown)
        self.assertFalse(self.ns.OptionsPage("ah").shown)

    def test_controls_grey_out_without_their_addon(self):
        self.ns.ShowOptionsWindow("display")
        self.assertFalse(self.widget("destroy").enabled)  # Baganator missing
        self.rt.execute("LOADED.Baganator = true")
        self.ns.RefreshOptionsWindow()
        self.assertTrue(self.widget("destroy").enabled)

    def test_buttons_call_their_action(self):
        self.rt.eval("function(ns) ns.ShowFilterWindow = function(mode) EXPORTED = mode end end")(self.ns)
        self.ns.ShowOptionsWindow("filter")
        button = self.widget("button:OPT_FILTER_EXPORT")
        button.OnClick(button)
        self.assertEqual(self.rt.eval("EXPORTED"), "export")

    def test_alt_table_rows_and_settings(self):
        self.rt.execute(ALTS)
        self.ns.ShowOptionsWindow("account")
        self.assertEqual(self.widget("altname:Amy-Realm").text[-3:], "Amy")
        self.assertTrue(self.widget("alt:Bob-Realm:included").checked)
        self.click("alt:Bob-Realm:included")
        self.assertIs(self.rt.eval("KeepOrSellDB.altSettings['Bob-Realm'].included"), False)
        self.assertEqual(self.rt.eval("CHANGED"), 1)
        self.assertLess(self.widget("altrow:Bob-Realm").alpha, 1)

    def test_alt_table_dims_without_account_mode(self):
        self.rt.execute(ALTS)
        self.ns.ShowOptionsWindow("account")
        self.click("accountMode")
        self.assertFalse(self.widget("alt:Bob-Realm:included").enabled)
        self.assertLess(self.ns.OptionsAltTable().alpha, 1)

    def test_alt_table_scrolls_with_many_alts(self):
        self.rt.execute(ALTS)
        self.rt.execute("for i = 1, 25 do KeepOrSellDB.characters['Alt' .. i .. '-Realm'] = {faction = 'Alliance', realm = 'Realm'} end")
        self.ns.ShowOptionsWindow("account")
        row = self.widget("altrow:Alt7-Realm")
        same = self.rt.eval("function(a, b) return rawequal(a, b) end")
        self.assertTrue(same(row.parent, self.ns.OptionsAltTable().scroll.scrollChild))

    def test_no_alts_shows_hint(self):
        self.ns.ShowOptionsWindow("account")
        self.assertEqual(self.ns.OptionsAltTable().hint.text, self.ns.L.ALTS_HINT)
        self.assertIsNone(self.widget("altrow:Bob-Realm"))

    def test_alt_table_stays_inside_the_page(self):
        self.ns.ShowOptionsWindow("account")
        layout, table = self.ns.OptionsLayout(), self.ns.OptionsAltTable()
        bottom = layout.columnTop - table.top + table.height  # table.top is negative (below the column top)
        self.assertLessEqual(bottom, layout.pageHeight)
        self.assertLessEqual(table.width, layout.pageWidth)

    def test_alt_columns_fit_the_scroll_area(self):
        layout = self.ns.OptionsLayout()
        self.assertLessEqual(layout.altRowWidth, layout.altScrollWidth)

    def test_window_has_no_portrait(self):
        self.rt.execute("HIDDEN_PORTRAIT = nil; function ButtonFrameTemplate_HidePortrait(f) HIDDEN_PORTRAIT = f.name end")
        self.ns.ShowOptionsWindow()
        self.assertEqual(self.rt.eval("HIDDEN_PORTRAIT"), "KeepOrSellOptionsFrame")

    def test_pages_have_a_fixed_size(self):
        self.ns.ShowOptionsWindow("junk")
        layout = self.ns.OptionsLayout()
        self.assertEqual((self.ns.OptionsPage("junk").width, self.ns.OptionsPage("junk").height),
                         (layout.pageWidth, layout.pageHeight))

    def test_dependency_rows(self):
        self.ns.ShowOptionsWindow("addons")
        self.assertIn("Auctionator", self.widget("dep:Auctionator").text)
        self.assertIn("active", self.widget("dep:Auctionator").text)
        # what the addon is for goes on its own line, so a long text can't run into the next addon
        self.assertEqual(self.widget("depuse:Auctionator").text, self.ns.L.DEP_AUCTIONATOR)
        self.assertNotIn(self.ns.L.DEP_AUCTIONATOR, self.widget("dep:Auctionator").text)

    def test_nav_labels_drop_the_addon_name(self):
        self.assertEqual(self.ns.NavLabel("Auction house (Auctionator)"), "Auction house")
        self.assertEqual(self.ns.NavLabel("Keep"), "Keep")
        self.ns.ShowOptionsWindow()
        self.assertEqual(self.widget("nav:ah").text, "Auction house")

    def test_scroll_bar_only_when_needed(self):
        self.rt.execute(ALTS)
        self.ns.ShowOptionsWindow("account")
        self.assertFalse(self.ns.OptionsAltTable().scroll.ScrollBar.shown)
        self.rt.execute("for i = 1, 25 do KeepOrSellDB.characters['Alt' .. i .. '-Realm'] = {faction = 'Alliance', realm = 'Realm'} end")
        self.ns.RefreshOptionsWindow()
        self.assertTrue(self.ns.OptionsAltTable().scroll.ScrollBar.shown)

    def test_professions_as_icons_with_tooltip(self):
        self.rt.execute(ALTS)
        self.rt.execute("KeepOrSellDB.recipeProfession = {['Amy-Realm'] = {[1] = 'Tailoring', [2] = 'Enchanting'}}")
        self.ns.ShowOptionsWindow("account")
        first, second = self.widget("altprof:Amy-Realm:1"), self.widget("altprof:Amy-Realm:2")
        self.assertEqual((first.profession, second.profession), ("Enchanting", "Tailoring"))
        self.assertEqual(first.icon.texture, "Interface\\Icons\\Trade_Engraving")
        self.assertTrue(first.shown)
        self.assertIsNone(self.widget("altprof:Amy-Realm:3"))
        self.assertEqual(self.widget("altnoprof:Bob-Realm").text, self.ns.L.ALTS_NO_PROFESSIONS)
        first.OnEnter(first)
        self.assertEqual(self.rt.eval("GameTooltip.text"), "Enchanting")


if __name__ == "__main__":
    unittest.main()
