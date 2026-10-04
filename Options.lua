-- Options panel under Esc > Options > AddOns
local addonName, ns = ...
local L = ns.L

local category

-- Registers the panel; db must already hold the defaults
function ns.RegisterOptions(db, defaults)
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
  local layout
  category, layout = Settings.RegisterVerticalLayoutCategory(addonName)

  local function Add(key, varType, name)
    local variable = addonName .. "_" .. key
    local setting = Settings.RegisterAddOnSetting(category, variable, key, db, varType, name, defaults[key])
    return setting, variable
  end

  -- options that do nothing without their addon say so in the tooltip and are greyed out
  local function Tooltip(key, tooltip)
    local needs = ns.OPTION_NEEDS[key]
    return needs and tooltip .. "\n\n" .. L.OPT_NEEDS:format(needs) or tooltip
  end

  local function NeedsAddon(key, initializer)
    local needs = ns.OPTION_NEEDS[key]
    if needs and initializer and initializer.AddModifyPredicate then
      initializer:AddModifyPredicate(function() return ns.IsDependencyReady(needs) end)
    end
  end

  local function Slider(key, name, tooltip, min, max, step, label)
    local setting, variable = Add(key, Settings.VarType.Number, name)
    local options = Settings.CreateSliderOptions(min, max, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, label)
    NeedsAddon(key, Settings.CreateSlider(category, setting, options, Tooltip(key, tooltip)))
    Settings.SetOnValueChangedCallback(variable, function() ns.SettingsChanged() end)
  end

  local function Checkbox(key, name, tooltip, refresh)
    local setting, variable = Add(key, Settings.VarType.Boolean, name)
    NeedsAddon(key, Settings.CreateCheckbox(category, setting, Tooltip(key, tooltip)))
    if refresh then Settings.SetOnValueChangedCallback(variable, function() ns.SettingsChanged() end) end
  end

  local function Header(name)
    if layout and CreateSettingsListSectionHeaderInitializer then
      layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end
  end

  -- grouped by purpose; the header names the addon a group depends on
  Header(L.SECTION_AH)
  Slider("factor", L.OPT_FACTOR, L.OPT_FACTOR_TIP, ns.MIN_FACTOR, 10, 0.1, function(v) return ("%gx"):format(v) end)
  Slider("minProfit", L.OPT_MIN_PROFIT, L.OPT_MIN_PROFIT_TIP, 0, 100, 1, function(v)
    return v == 0 and L.OFF or L.SILVER:format(v)
  end)
  Slider("maxAge", L.OPT_MAX_AGE, L.OPT_MAX_AGE_TIP, 1, 21, 1, function(v)
    return v >= 21 and L.OFF or L.DAYS:format(v)
  end)
  Checkbox("share", L.OPT_SHARE, L.OPT_SHARE_TIP, true)
  Header(L.SECTION_JUNK)
  Checkbox("scrap", L.OPT_SCRAP, L.OPT_SCRAP_TIP, true)
  Checkbox("gear", L.OPT_GEAR, L.OPT_GEAR_TIP, true)
  Checkbox("plainGear", L.OPT_PLAIN_GEAR, L.OPT_PLAIN_GEAR_TIP, true)
  Checkbox("recipeJunk", L.OPT_RECIPES, L.OPT_RECIPES_TIP, true)
  Header(L.SECTION_KEEP)
  Checkbox("profession", L.OPT_PROFESSION, L.OPT_PROFESSION_TIP, true)
  Checkbox("questie", L.OPT_QUESTIE, L.OPT_QUESTIE_TIP, true)
  Header(L.SECTION_DISPLAY)
  Checkbox("tooltip", L.OPT_TOOLTIP, L.OPT_TOOLTIP_TIP)
  Checkbox("hints", L.OPT_HINTS, L.OPT_HINTS_TIP, true)
  Checkbox("destroy", L.OPT_DESTROY, L.OPT_DESTROY_TIP, true)
  Checkbox("bagValue", L.OPT_BAG_VALUE, L.OPT_BAG_VALUE_TIP, true)
  Checkbox("setSource", L.OPT_SETS, L.OPT_SETS_TIP)

  if layout and CreateSettingsListSectionHeaderInitializer and Settings.CreateElementInitializer then
    Header(L.DEPENDENCIES)
    for _, dep in ipairs(ns.DEPENDENCIES) do
      layout:AddInitializer(Settings.CreateElementInitializer("KeepOrSellDependencyTemplate", dep))
    end
  end

  Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
  if not category then return end
  -- Settings.OpenToCategory goes through C_SettingsUtil.OpenSettingsPanel, which newer
  -- clients only allow from untainted code (ADDON_ACTION_BLOCKED); the panel's own method is not restricted
  if SettingsPanel and SettingsPanel.OpenToCategory then
    SettingsPanel:OpenToCategory(category:GetID())
  else
    Settings.OpenToCategory(category:GetID())
  end
end
