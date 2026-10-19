-- What the options window shows, as data: the sections of the sidebar and the controls in their two columns.
-- UI/OptionsWindow.lua only draws this. Labels are keys into ns.L. Pure.
local _, ns = ...
local L = ns.L

local function Check(key, label, refresh)
  return {kind = "checkbox", key = key, label = label, tip = label .. "_TIP", refresh = refresh or nil}
end

local function Button(label, action, arg)
  return {kind = "button", label = label, text = label .. "_BUTTON", tip = label .. "_TIP", action = action, arg = arg}
end

-- id, label, icon (Interface\Icons\...), {left column, right column}
ns.OPTION_SECTIONS = {
  {id = "ah", label = "SECTION_AH", icon = "INV_Misc_Coin_01", columns = {
    {
      {kind = "slider", key = "factor", label = "OPT_FACTOR", tip = "OPT_FACTOR_TIP", min = ns.MIN_FACTOR, max = 10,
        step = 0.1, refresh = true, format = function(v) return ("%gx"):format(v) end},
      {kind = "slider", key = "minProfit", label = "OPT_MIN_PROFIT", tip = "OPT_MIN_PROFIT_TIP", min = 0, max = 100,
        step = 1, refresh = true, format = function(v) return v == 0 and L.OFF or L.SILVER:format(v) end},
      {kind = "slider", key = "maxAge", label = "OPT_MAX_AGE", tip = "OPT_MAX_AGE_TIP", min = 1, max = 21, step = 1,
        refresh = true, format = function(v) return v >= 21 and L.OFF or L.DAYS:format(v) end},
    },
    {Check("share", "OPT_SHARE", true)},
  }},
  {id = "junk", label = "SECTION_JUNK", icon = "INV_Misc_Pelt_Wolf_01", columns = {
    {Check("scrap", "OPT_SCRAP", true), Check("gear", "OPT_GEAR", true)},
    {Check("plainGear", "OPT_PLAIN_GEAR", true), Check("recipeJunk", "OPT_RECIPES", true)},
  }},
  {id = "keep", label = "SECTION_KEEP", icon = "INV_Misc_Note_01", columns = {
    {Check("profession", "OPT_PROFESSION", true), Check("upcomingReagents", "OPT_UPCOMING", true),
      Check("questie", "OPT_QUESTIE", true)},
    {Check("disenchant", "OPT_DISENCHANT", true), Check("openable", "OPT_OPEN", true), Check("keepClick", "OPT_KEEP_CLICK"),
      Button("OPT_KEEP_FORGET", "ForgetKept")},
  }},
  {id = "account", label = "SECTION_ACCOUNT", icon = "INV_Letter_15", columns = {
    {Check("accountMode", "OPT_ACCOUNT_MODE", true), {kind = "alts"}},
    {},
  }},
  {id = "filter", label = "OPT_FILTER_HEADER", icon = "INV_Scroll_03", columns = {
    {Button("OPT_FILTER_EXPORT", "ShowFilterWindow", "export"), Button("OPT_FILTER_IMPORT", "ShowFilterWindow", "import")},
    {Button("OPT_FILTER_UNDO", "UndoFilterCommand"), Button("OPT_FILTER_CLEAR", "ClearFilterCommand")},
  }},
  {id = "display", label = "SECTION_DISPLAY", icon = "INV_Misc_Spyglass_02", columns = {
    {Check("tooltip", "OPT_TOOLTIP"), Check("hints", "OPT_HINTS", true), Check("helpButton", "OPT_HELP_BUTTON", true),
      Check("destroy", "OPT_DESTROY", true)},
    {Check("lootCoins", "OPT_LOOT_COINS"), Check("lossWarnings", "OPT_LOSS_WARNINGS"), Check("bagValue", "OPT_BAG_VALUE", true),
      Check("setSource", "OPT_SETS")},
  }},
  {id = "addons", label = "DEPENDENCIES", icon = "INV_Misc_Gear_01", columns = {
    {{kind = "dependencies"}},
    {Button("OPT_SETUP", "ShowSetup")},
  }},
}

-- All controls of a section, left column first, or {} for an unknown id
function ns.SectionControls(id)
  local controls = {}
  for _, section in ipairs(ns.OPTION_SECTIONS) do
    if section.id == id then
      for _, column in ipairs(section.columns) do
        for _, control in ipairs(column) do table.insert(controls, control) end
      end
    end
  end
  return controls
end
