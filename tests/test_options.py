"""Tests for the options panel (Options.lua) and /kos (Core.lua) against a stubbed Settings API."""
import unittest

from addon import source
from wowapi import runtime

STUBS = """
CALLS = {settings = {}, controls = {}, callbacks = {}, sliders = {}, initializers = {}, tooltips = {}, layout = {}}
local category = {GetID = function() return 42 end}
local layout = {AddInitializer = function(_, init) table.insert(CALLS.layout, init) end}
local function Initializer(key)
  local init = {predicates = {}, AddModifyPredicate = function(self, fn) table.insert(self.predicates, fn) end}
  CALLS.initializers[key] = init
  return init
end
function ENABLED(key)
  for _, fn in ipairs(CALLS.initializers[key].predicates) do if not fn() then return false end end
  return true
end
function CreateSettingsListSectionHeaderInitializer(name) return {header = name} end
LOADED, EXISTS = {}, {}
C_AddOns = {
  IsAddOnLoaded = function(name) return LOADED[name] == true end,
  DoesAddOnExist = function(name) return EXISTS[name] == true or LOADED[name] == true end,
}
Settings = {
  VarType = {Boolean = "boolean", Number = "number"},
  RegisterVerticalLayoutCategory = function(name) CALLS.categoryName = name return category, layout end,
  CreateElementInitializer = function(template, data) return {template = template, data = data} end,
  RegisterAddOnSetting = function(cat, variable, key, tbl, varType, name, default)
    local s = {variable = variable, key = key, tbl = tbl, varType = varType, default = default}
    CALLS.settings[key] = s
    return s
  end,
  CreateSliderOptions = function(min, max, step)
    return {min = min, max = max, step = step, SetLabelFormatter = function(self, _, fn) self.label = fn end}
  end,
  CreateSlider = function(cat, setting, options, tooltip)
    table.insert(CALLS.controls, "slider:" .. setting.key)
    CALLS.sliders[setting.key] = options
    CALLS.tooltips[setting.key] = tooltip
    return Initializer(setting.key)
  end,
  CreateCheckbox = function(cat, setting, tooltip)
    table.insert(CALLS.controls, "checkbox:" .. setting.key)
    CALLS.tooltips[setting.key] = tooltip
    return Initializer(setting.key)
  end,
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
C_Timer = {After = function(_, fn) fn() end}
"""

def load():
    rt = runtime()
    rt.execute(STUBS)
    ns = rt.eval("{}")
    rt.eval("""function(ns)
      ns.HookScrap = function() end
      ns.UpdateHints = function() ns.hintsUpdated = (ns.hintsUpdated or 0) + 1 end
      ns.UpdateDestroy = function() ns.destroyUpdated = (ns.destroyUpdated or 0) + 1 end
      ns.UpdateBagValue = function() ns.valueUpdated = (ns.valueUpdated or 0) + 1 end
      ns.RefreshBaganator = function() ns.refreshed = (ns.refreshed or 0) + 1 end
    end""")(ns)
    for f in ("Locales.lua", "Prices.lua", "Share.lua", "Dependencies.lua", "Options.lua", "Core.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            source(f), ns)
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
            "slider:factor", "slider:minProfit", "slider:maxAge", "checkbox:share", "checkbox:scrap", "checkbox:gear",
            "checkbox:plainGear", "checkbox:recipeJunk", "checkbox:profession", "checkbox:questie", "checkbox:disenchant", "checkbox:tooltip", "checkbox:hints", "checkbox:destroy", "checkbox:bagValue", "checkbox:setSource"])

    def test_sections(self):
        headers = [i.header for i in self.calls.layout.values() if i.header]
        self.assertEqual(headers, ["Auction house (Auctionator)", "Junk (Scrap)", "Keep", "Display", "Dependencies"])

    def test_slider_labels(self):
        self.assertEqual(self.calls.sliders["minProfit"].label(0), "off")
        self.assertEqual(self.calls.sliders["minProfit"].label(5), "5 s")
        self.assertEqual(self.calls.sliders["maxAge"].label(7), "7 days")
        self.assertEqual(self.calls.sliders["maxAge"].label(21), "off")

    def test_share_option(self):
        self.assertTrue(self.rt.eval("KeepOrSellDB.share"))
        self.assertEqual(self.calls.settings["share"].varType, "boolean")
        # receiving works without Auctionator, so the option is never greyed out
        self.assertNotIn("Needs", self.calls.tooltips["share"])
        self.assertTrue(self.rt.eval("ENABLED('share')"))

    def test_factor_minimum(self):
        self.assertEqual(self.calls.sliders["factor"].min, 1.1)
        self.assertEqual(self.calls.sliders["factor"].label(1.1), "1.1x")
        self.rt.execute("KeepOrSellDB = {factor = 1}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertEqual(self.rt.eval("KeepOrSellDB.factor"), 1.1)  # old saved value raised

    def test_defaults_for_new_options(self):
        db = self.rt.eval("KeepOrSellDB")
        self.assertEqual((db.minProfit, db.maxAge, db.gear, db.plainGear, db.recipeJunk, db.profession, db.tooltip),
                         (0, 7, True, True, True, True, True))

    def test_shared_prices_without_realm_dropped(self):
        # 0.8.0/0.8.1 stored shared prices by item ID for all realms
        self.rt.execute("KeepOrSellDB = {sharedPrices = {[3] = {price = 1, seen = 1}, ['Realm-Horde'] = {[4] = {price = 2, seen = 1}}}}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertEqual(list(self.rt.eval("KeepOrSellDB.sharedPrices").keys()), ["Realm-Horde"])
        self.assertIsNotNone(self.rt.eval("KeepOrSellDB.fullScans"))

    def test_settings_bound_to_saved_variables(self):
        factor = self.calls.settings["factor"]
        self.assertTrue(self.rt.eval("CALLS.settings.factor.tbl == KeepOrSellDB"))
        self.assertEqual(factor.default, 2)
        self.assertEqual(self.rt.eval("KeepOrSellDB.factor"), 3)  # existing value kept
        self.assertEqual(self.calls.settings["scrap"].varType, "boolean")

    def test_change_refreshes_baganator(self):
        keys = ("factor", "minProfit", "maxAge", "scrap", "gear", "plainGear", "recipeJunk", "profession", "hints", "destroy", "bagValue", "share")
        for key in keys:
            self.calls.callbacks["KeepOrSell_" + key]()
        self.assertEqual(self.ns.refreshed, len(keys))
        self.assertEqual(self.ns.hintsUpdated, len(keys))
        self.assertEqual(self.ns.destroyUpdated, len(keys))
        self.assertEqual(self.ns.valueUpdated, len(keys))

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

    def test_options_need_their_addon(self):
        for key in ("factor", "minProfit", "maxAge", "setSource", "destroy", "bagValue", "questie"):
            self.assertFalse(self.rt.eval("ENABLED")(key), key)
        for key in ("scrap", "gear", "tooltip", "hints"):
            self.assertTrue(self.rt.eval("ENABLED")(key), key)
        self.rt.execute("LOADED.Auctionator = true; LOADED.Baganator = true")
        for key in ("factor", "minProfit", "maxAge", "setSource", "destroy", "bagValue"):
            self.assertTrue(self.rt.eval("ENABLED")(key), key)

    def test_price_options_work_with_tsm_alone(self):
        self.rt.execute("LOADED.TradeSkillMaster = true")
        self.assertTrue(self.rt.eval("ENABLED")("factor"))
        self.assertTrue(self.rt.eval("ENABLED")("minProfit"))
        # TSM has no price age
        self.assertFalse(self.rt.eval("ENABLED")("maxAge"))

    def test_questie_needs_matching_database(self):
        self.rt.execute("LOADED.Questie = true")
        self.assertFalse(self.rt.eval("ENABLED")("questie"))
        self.ns.HasQuestieDB = self.rt.eval("function() return true end")
        self.assertTrue(self.rt.eval("ENABLED")("questie"))

    def test_tooltip_names_the_addon(self):
        self.assertIn("Needs Auctionator / TradeSkillMaster.", self.calls.tooltips["factor"])
        self.assertIn("Needs Auctionator.", self.calls.tooltips["maxAge"])
        self.assertIn("Needs Baganator.", self.calls.tooltips["setSource"])
        self.assertNotIn("Needs", self.calls.tooltips["scrap"])

    def test_dependency_list(self):
        layout = list(self.calls.layout.values())[4:]
        self.assertEqual(layout[0].header, "Dependencies")
        self.assertEqual([i.data.name for i in layout[1:]], ["Auctionator", "TradeSkillMaster", "Baganator", "Scrap", "Questie"])
        self.assertEqual(layout[1].template, "KeepOrSellDependencyTemplate")

    def test_without_settings_api(self):
        rt, ns = load()
        rt.execute("Settings = nil; KeepOrSellDB = nil")
        rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        rt.execute("SlashCmdList.KEEPORSELL('')")  # must not error

class DependencyStatusTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()

    def test_status(self):
        status = self.ns.DependencyStatus
        self.assertEqual(status(True, True, True), "active")
        self.assertEqual(status(True, True, False), "outdated")
        self.assertEqual(status(False, True, True), "disabled")
        self.assertEqual(status(False, False, True), "missing")

    def test_from_client(self):
        self.rt.execute("LOADED.Scrap = true; EXISTS.Baganator = true")
        get = self.ns.GetDependencyStatus
        self.assertEqual((get("Scrap"), get("Baganator"), get("Auctionator")), ("active", "disabled", "missing"))

    def test_questie_without_database(self):
        self.rt.execute("LOADED.Questie = true")
        self.assertEqual(self.ns.GetDependencyStatus("Questie"), "outdated")

    def test_needs_list(self):
        self.assertEqual(list(self.ns.NeedsList("Scrap").values()), ["Scrap"])
        both = self.rt.eval("{'Auctionator', 'TradeSkillMaster'}")
        self.assertEqual(list(self.ns.NeedsList(both).values()), ["Auctionator", "TradeSkillMaster"])

    def test_any_dependency_ready(self):
        both = self.rt.eval("{'Auctionator', 'TradeSkillMaster'}")
        self.assertFalse(self.ns.IsAnyDependencyReady(both))
        self.rt.execute("LOADED.TradeSkillMaster = true")
        self.assertTrue(self.ns.IsAnyDependencyReady(both))
        self.assertFalse(self.ns.IsAnyDependencyReady("Auctionator"))

    def test_status_text(self):
        self.rt.execute("LOADED.Auctionator = true")
        text = self.ns.DependencyText(self.rt.eval("{name = 'Auctionator', use = 'auction prices'}"))
        self.assertIn("active", text)
        self.assertIn("auction prices", text)

if __name__ == "__main__":
    unittest.main()
