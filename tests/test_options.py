"""Tests for the options panel (Options.lua) and /kos (Core.lua) against a stubbed Settings API."""
import unittest

from addon import source
from wowapi import runtime

STUBS = """
CALLS = {settings = {}, controls = {}, callbacks = {}, sliders = {}, initializers = {}, tooltips = {}, layout = {},
  subLayout = {}, checkboxCategory = {}}
local subcategory = {GetID = function() return 43 end}
local subLayout = {AddInitializer = function(_, init) table.insert(CALLS.subLayout, init) end}
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
  RegisterVerticalLayoutSubcategory = function(parent, name)
    CALLS.subcategoryName, CALLS.subcategoryParent = name, parent
    return subcategory, subLayout
  end,
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
    CALLS.checkboxCategory[setting.key] = cat == subcategory and "sub" or "main"
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
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Alliance" end
function UnitClass() return "Druid", "DRUID" end
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
      ns.UpdateHelp = function() ns.helpUpdated = (ns.helpUpdated or 0) + 1 end
      ns.ToggleOptionsWindow = function() ns.toggled = (ns.toggled or 0) + 1 end
      ns.ShowOptionsWindow = function() ns.windowShown = (ns.windowShown or 0) + 1 end
    end""")(ns)
    for f in ("Locales.lua", "Keep.lua", "Prices.lua", "Share.lua", "Filter.lua", "Dependencies.lua", "FilterWindow.lua",
              "Gear.lua", "Professions.lua", "Account.lua", "Options.lua", "Warnings.lua", "Core.lua"):
        rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")(
            source(f), ns)
    return rt, ns

class OptionsTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load()
        self.rt.execute("KeepOrSellDB = {factor = 3}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.calls = self.rt.eval("CALLS")

    def test_blizzard_entry_is_one_button(self):
        self.rt.execute("""BUTTONS = {}
          function CreateSettingsButtonInitializer(name, text, click, tip, tags) BUTTONS[name] = click return {} end
          KeepOrSellDB = {}""")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertEqual(self.calls.categoryName, "KeepOrSell")
        self.assertIsNotNone(self.calls.registered)
        self.assertEqual(len(self.calls.controls), 0)
        self.rt.eval("BUTTONS")[self.ns.L.OPT_WINDOW_OPEN]()
        self.assertEqual(self.ns.windowShown, 1)

    def test_old_alt_switches_migrate_on_load(self):
        self.rt.execute("KeepOrSellDB = {altReagents = false, characters = {['Bob-Realm'] = {faction = 'Alliance'}}}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertIs(self.rt.eval("KeepOrSellDB.altSettings['Bob-Realm'].profession"), False)
        self.assertIsNone(self.rt.eval("KeepOrSellDB.altReagents"))
        self.assertIs(self.rt.eval("KeepOrSellDB.accountMode"), True)

    def test_factor_minimum(self):
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

    def test_filter_storage_initialised(self):
        self.rt.execute("KeepOrSellDB = {filter = {name = 'x'}}")
        self.rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertEqual(self.rt.eval("KeepOrSellDB.filter.name"), "x")
        self.assertIsNotNone(self.rt.eval("KeepOrSellDB.filter.items"))
        self.assertIsNotNone(self.rt.eval("KeepOrSellDB.filter.categories"))

    def test_change_refreshes_bags_and_buttons(self):
        self.ns.SettingsChanged()
        self.assertEqual((self.ns.refreshed, self.ns.hintsUpdated, self.ns.destroyUpdated, self.ns.valueUpdated,
                          self.ns.helpUpdated), (1, 1, 1, 1, 1))

    def test_slash_toggles_window(self):
        self.rt.execute("SlashCmdList.KEEPORSELL('')")
        self.rt.execute("SlashCmdList.KEEPORSELL('factor 5')")
        self.assertEqual(self.ns.toggled, 2)
        self.assertEqual(self.rt.eval("KeepOrSellDB.factor"), 3)

    def test_options_need_their_addon(self):
        ready = lambda key: self.ns.IsAnyDependencyReady(self.ns.OPTION_NEEDS[key])
        for key in ("factor", "minProfit", "maxAge", "setSource", "destroy", "bagValue", "questie"):
            self.assertFalse(ready(key), key)
        for key in ("scrap", "gear", "tooltip", "hints", "share", "helpButton"):
            self.assertIsNone(self.ns.OPTION_NEEDS[key], key)
        self.rt.execute("LOADED.Auctionator = true; LOADED.Baganator = true")
        for key in ("factor", "minProfit", "maxAge", "setSource", "destroy", "bagValue"):
            self.assertTrue(ready(key), key)

    def test_price_options_work_with_tsm_alone(self):
        ready = lambda key: self.ns.IsAnyDependencyReady(self.ns.OPTION_NEEDS[key])
        self.rt.execute("LOADED.TradeSkillMaster = true")
        self.assertTrue(ready("factor"))
        self.assertTrue(ready("minProfit"))
        self.assertFalse(ready("maxAge"))  # TSM has no price age

    def test_questie_needs_matching_database(self):
        self.rt.execute("LOADED.Questie = true")
        self.assertFalse(self.ns.IsAnyDependencyReady(self.ns.OPTION_NEEDS["questie"]))
        self.ns.HasQuestieDB = self.rt.eval("function() return true end")
        self.assertTrue(self.ns.IsAnyDependencyReady(self.ns.OPTION_NEEDS["questie"]))

    def test_new_options_on_by_default(self):
        self.assertTrue(self.rt.eval("KeepOrSellDB.keepClick"))
        self.assertTrue(self.rt.eval("KeepOrSellDB.lootCoins"))
        self.assertTrue(self.rt.eval("KeepOrSellDB.upcomingReagents"))
        self.assertTrue(self.rt.eval("KeepOrSellDB.lossWarnings"))
        self.assertTrue(self.rt.eval("KeepOrSellDB.helpButton"))

    def test_slash_filter_commands(self):
        self.rt.eval("function(ns) ns.ShowFilterWindow = function(mode) ns.shown = mode end end")(self.ns)
        self.rt.execute("SlashCmdList.KEEPORSELL('export')")
        self.assertEqual(self.ns.shown, "export")
        self.assertIsNone(self.ns.toggled)

    def test_slash_keep(self):
        self.rt.execute("""
          PRINTED = {}
          print = function(text) table.insert(PRINTED, text) end
          C_Item = {GetItemInfo = function(id) return "Linen", "[Linen]" end}
        """)
        self.rt.execute("SlashCmdList.KEEPORSELL('keep 4')")
        self.assertTrue(self.rt.eval("KeepOrSellDB.keep[4]"))
        self.assertIsNone(self.ns.toggled)
        self.rt.execute("SlashCmdList.KEEPORSELL('kept')")
        self.assertIn("[Linen]", self.rt.eval("PRINTED[#PRINTED]"))

    def test_no_panel_with_gamepad_ui(self):
        rt, ns = load()
        rt.execute("""
          C_InputInterfaceStyle = {GetCurrentStyle = function() return 1 end}
          Enum = {InputDeviceInterfaceType = {Mkb = 0, Gamepad = 1}}
          PRINTED = {}
          print = function(text) table.insert(PRINTED, text) end
          KeepOrSellDB = {}
        """)
        rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertIsNone(rt.eval("CALLS.registered"))
        self.assertTrue(rt.eval("KeepOrSellDB.tooltip"))  # defaults still set
        rt.execute("SlashCmdList.KEEPORSELL('')")
        self.assertEqual(ns.toggled, 1)  # the own window works with the gamepad UI

    def test_panel_with_mouse_ui(self):
        rt, ns = load()
        rt.execute("""
          C_InputInterfaceStyle = {GetCurrentStyle = function() return 0 end}
          Enum = {InputDeviceInterfaceType = {Mkb = 0, Gamepad = 1}}
          KeepOrSellDB = {}
        """)
        rt.execute("FireEvent('ADDON_LOADED', 'KeepOrSell')")
        self.assertIsNotNone(rt.eval("CALLS.registered"))

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
