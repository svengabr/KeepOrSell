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

-- Professions by group, each with its icon and its name as the client stores it (English and German):
-- 1 = secondary (everyone can learn them, in this order), 2 = main professions, 3 = class skills
local PROFESSIONS = {
  {1, "INV_Misc_Food_15", "Cooking", "Kochkunst"},
  {1, "Spell_Holy_SealOfSacrifice", "First Aid", "Erste Hilfe"},
  {1, "Trade_Fishing", "Fishing", "Angeln"},
  {2, "Trade_Alchemy", "Alchemy", "Alchimie"},
  {2, "Trade_BlackSmithing", "Blacksmithing", "Schmiedekunst"},
  {2, "Trade_Engraving", "Enchanting", "Verzauberkunst"},
  {2, "Trade_Engineering", "Engineering", "Ingenieurskunst"},
  {2, "Trade_Herbalism", "Herbalism", "Kräuterkunde"},
  {2, "INV_Misc_ArmorKit_17", "Leatherworking", "Lederverarbeitung"},
  {2, "Trade_Mining", "Mining", "Bergbau"},
  {2, "INV_Misc_Pelt_Wolf_01", "Skinning", "Kürschnerei"},
  {2, "Trade_Tailoring", "Tailoring", "Schneiderei"},
  {3, "Trade_BrewPoison", "Poisons", "Gifte"},
}
local BY_NAME = {} -- name -> {group, icon, position}
for position, entry in ipairs(PROFESSIONS) do
  for i = 3, #entry do BY_NAME[entry[i]] = {group = entry[1], icon = entry[2], position = position} end
end

-- "Interface\\Icons\\…" for a profession name; a question mark for names it doesn't know. Pure.
function ns.ProfessionIcon(name)
  return "Interface\\Icons\\" .. (BY_NAME[name] and BY_NAME[name].icon or "INV_Misc_QuestionMark")
end

-- The icons a row shows: the three secondary professions always (learned or not, named in the client's language),
-- then the others as ns.SortProfessions orders them: {{name, icon, learned, rank, maxRank}, ...}. icons = the
-- recorded professions ({[name] = {icon, rank, maxRank}}; development builds stored the icon alone), else the icon
-- by name. Pure.
function ns.ProfessionSlots(names, icons, locale)
  icons = icons or {}
  local function Slot(name, learned)
    local info = icons[name]
    local icon = type(info) == "table" and info.icon or (type(info) == "number" or type(info) == "string") and info
    return {name = name, icon = icon or ns.ProfessionIcon(name), learned = learned,
      rank = type(info) == "table" and info.rank or nil, maxRank = type(info) == "table" and info.maxRank or nil}
  end
  local have = {}
  for _, name in ipairs(names or {}) do have[name] = true end
  local slots, shown = {}, {}
  for _, entry in ipairs(PROFESSIONS) do
    if entry[1] == 1 then
      local name = have[entry[3]] and entry[3] or have[entry[4]] and entry[4]
        or (locale == "deDE" and entry[4] or entry[3])
      shown[name] = true
      table.insert(slots, Slot(name, have[name] == true))
    end
  end
  for _, name in ipairs(ns.SortProfessions(names)) do
    if not shown[name] then
      table.insert(slots, Slot(name, true))
    end
  end
  return slots
end

-- A sorted copy: secondary professions first (cooking, first aid, fishing), then the main professions, then class
-- skills and every name it doesn't know (Forever's own class professions, other languages), alphabetical within a
-- group. Pure.
function ns.SortProfessions(names)
  local sorted = {}
  for _, name in ipairs(names or {}) do table.insert(sorted, name) end
  local function key(name)
    local known = BY_NAME[name]
    return known and known.group or 3, known and known.group == 1 and known.position or 0
  end
  table.sort(sorted, function(a, b)
    local groupA, posA = key(a)
    local groupB, posB = key(b)
    if groupA ~= groupB then return groupA < groupB end
    if posA ~= posB then return posA < posB end
    return a < b
  end)
  return sorted
end
