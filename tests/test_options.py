"""Tests for the options panel (Options.lua) and /kos (Core.lua) against a stubbed Settings API."""
import unittest
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent

STUBS = """
CALLS = {settings = {}, controls = {}, callbacks = {}, sliders = {}}
local category = {GetID = function() return 42 end}
Settings = {
  VarType = {Boolean = "boolean", Number = "number"},
  RegisterVerticalLayoutCategory = function(name) CALLS.categoryName = name return category end,
  RegisterAddOnSetting = function(cat, variable, key, tbl, varType, name, default)
    local s = {variable = variable, key = key, tbl = tbl, varType = varType, default = default}
    CALLS.settings[key] = s
    return s
  end,
  CreateSliderOptions = function(min, max, step)
    return {min = min, max = max, step = step, SetLabelFormatter = function(self, _, fn) self.label = fn end}
  end,
  CreateSlider = function(cat, setting, options)
    table.insert(CALLS.controls, "slider:" .. setting.key)
    CALLS.sliders[setting.key] = options
  end,
  CreateCheckbox = function(cat, setting) table.insert(CALLS.controls, "checkbox:" .. setting.key) end,
  SetOnValueChangedCallback = function(variable, cb) CALLS.callbacks[variable] = cb end,
  RegisterAddOnCategory = function(cat) CALLS.registered = cat end,
  OpenToCategory = function(id) CALLS.opened = id end,
}
MinimalSliderWithSteppersMixin = {Label = {Right = 1}}
local handler
CreateFrame = function()
  return {SetScript = function(_, _, fn) handler = fn end, RegisterEvent = function() end}
end
function FireEvent(...) handler(nil, ...) end
SlashCmdList = {}
"""


def load():
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(STUBS)
    ns = rt.eval("{}")
    rt.eval("""function(ns)
      ns.HookScrap = function() end
      ns.RefreshBaganator = function() ns.refreshed = (ns.refreshed or 0) + 1 end
    end""")(ns)
    for f in ("Locales.lua", "Options.lua", "Core.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            str(ROOT / f).replace("\\", "/"), ns)
    return rt, ns


class OptionsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()
        self.rt.execute("KeepOrSellDB = {factor = 3}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.calls = self.rt.eval("CALLS")

    def test_panel_registered(self):
        self.assertEqual(self.calls.categoryName, "KeepOrSell")
        self.assertIsNotNone(self.calls.registered)
        self.assertEqual(list(self.calls.controls.values()), [
            "slider:factor", "slider:minProfit", "slider:maxAge", "checkbox:scrap", "checkbox:gear",
            "checkbox:plainGear", "checkbox:profession", "checkbox:tooltip", "checkbox:setSource"])

    def test_slider_labels(self):
        self.assertEqual(self.calls.sliders["minProfit"].label(0), "off")
        self.assertEqual(self.calls.sliders["minProfit"].label(5), "5 s")
        self.assertEqual(self.calls.sliders["maxAge"].label(7), "7 days")
        self.assertEqual(self.calls.sliders["maxAge"].label(21), "off")

    def test_defaults_for_new_options(self):
        db = self.rt.eval("KeepOrSellDB")
        self.assertEqual((db.minProfit, db.maxAge, db.gear, db.plainGear, db.profession, db.tooltip),
                         (0, 7, True, True, True, True))

    def test_settings_bound_to_saved_variables(self):
        factor = self.calls.settings["factor"]
        self.assertTrue(self.rt.eval("CALLS.settings.factor.tbl == KeepOrSellDB"))
        self.assertEqual(factor.default, 2)
        self.assertEqual(self.rt.eval("KeepOrSellDB.factor"), 3)  # existing value kept
        self.assertEqual(self.calls.settings["scrap"].varType, "boolean")

    def test_change_refreshes_baganator(self):
        keys = ("factor", "minProfit", "maxAge", "scrap", "gear", "plainGear", "profession")
        for key in keys:
            self.calls.callbacks["KeepOrSell_" + key]()
        self.assertEqual(self.ns.refreshed, len(keys))

    def test_slash_opens_panel(self):
        self.rt.execute("SlashCmdList.KEEPORSELL('factor 5')")
        self.assertEqual(self.calls.opened, 42)
        self.assertEqual(self.rt.eval("KeepOrSellDB.factor"), 3)

    def test_slash_prefers_panel_method(self):
        # Settings.OpenToCategory is blocked for addons on newer clients
        self.rt.execute("SettingsPanel = {OpenToCategory = function(self, id) CALLS.panelOpened = id end}")
        self.rt.execute("SlashCmdList.KEEPORSELL('')")
        self.assertEqual(self.calls.panelOpened, 42)
        self.assertIsNone(self.calls.opened)

    def test_without_settings_api(self):
        rt, ns = load()
        rt.execute("Settings = nil; KeepOrSellDB = nil")
        rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        rt.execute("SlashCmdList.KEEPORSELL('')")  # must not error


if __name__ == "__main__":
    unittest.main()
