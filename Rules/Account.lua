-- Account mode: one record per character of the account (faction, class, ruleset, Reagent Economy) in
-- KeepOrSellDB.characters, so items another character needs can be told apart.
local _, ns = ...

-- true = an item can be mailed between the two characters: same faction and same ruleset (the ruleset is the
-- server on Forever). Records written before rulesets were stored compare by the realm they stored. Pure.
function ns.SamePool(me, other)
  if not (me and other and me.faction and me.faction == other.faction) then return false end
  if me.ruleset and other.ruleset then return me.ruleset == other.ruleset end
  return me.realm ~= nil and me.realm == other.realm
end

-- Tables in KeepOrSellDB keyed by character
local PER_CHARACTER = {"recipes", "upcoming", "crafts", "recipeProfession", "opened", "baganatorSetup", "characters",
  "altSettings"}

-- Moves a character's data from oldKey to newKey in every per-character table; data already under newKey stays.
-- Pure.
function ns.MoveCharacterData(db, oldKey, newKey)
  if oldKey == newKey then return end
  for _, name in ipairs(PER_CHARACTER) do
    local t = db[name]
    if type(t) == "table" and t[oldKey] ~= nil then
      if t[newKey] == nil then t[newKey] = t[oldKey] end
      t[oldKey] = nil
    end
  end
end

-- Keys under which older versions kept this character, to move to newKey: "Name-Realm" (until Forever stopped telling
-- the realm), "Name-?" (ruleset not known yet) and the first-name-only key from before surnames. A full name with a
-- surname is unique in the region, so every key with it is this character; a first name alone is not, so such a key
-- moves only when exactly one record under it fits me ({faction, class, ruleset}; unknown values fit). Pure.
function ns.OldCharacterKeys(db, name, firstName, newKey, me)
  local keys = {}
  for _, tableName in ipairs(PER_CHARACTER) do
    local t = db[tableName]
    for key in pairs(type(t) == "table" and t or {}) do
      if type(key) == "string" and key ~= newKey then keys[key] = true end
    end
  end
  local result, firstNameKeys = {}, {}
  for key in pairs(keys) do
    local keyName = key:match("^(.-)%-")
    if keyName == name and name ~= firstName then
      table.insert(result, key)
    elseif keyName == firstName then
      local record = db.characters and db.characters[key]
      if type(record) == "table" and (record.faction == nil or me.faction == nil or record.faction == me.faction)
          and (record.class == nil or record.class == me.class)
          and (record.ruleset == nil or me.ruleset == nil or record.ruleset == me.ruleset) then
        table.insert(firstNameKeys, key)
      end
    end
  end
  if #firstNameKeys == 1 then table.insert(result, firstNameKeys[1]) end
  table.sort(result)
  return result
end

local altIndex -- built once per session: other characters only change in their own sessions

-- The current character's professions as {[name] = {icon, rank, maxRank}}, or nil while the client can't tell yet. GetProfessions
-- returns the slots prof1, prof2, archaeology, fishing, cooking, first aid, with gaps for empty ones.
function ns.CurrentProfessions()
  if not (GetProfessions and GetProfessionInfo) then return nil end
  local slots = {GetProfessions()}
  local result, any = {}, false
  for i = 1, select("#", GetProfessions()) do
    if slots[i] then
      local name, icon, rank, maxRank = GetProfessionInfo(slots[i])
      if name then result[name], any = {icon = icon, rank = rank, maxRank = maxRank}, true end
    end
  end
  return any and result or nil
end

-- Writes the current character's record; older versions kept only the faction in KeepOrSellDB.factions (the
-- realm comes from the key "Name-Realm"). Runs at ADDON_LOADED and again at PLAYER_LOGIN; values the client can't
-- tell yet keep the stored ones.
function ns.RecordCharacter()
  if not KeepOrSellDB then return end
  local characters = KeepOrSellDB.characters or {}
  KeepOrSellDB.characters = characters
  for key, faction in pairs(KeepOrSellDB.factions or {}) do
    characters[key] = characters[key] or {}
    characters[key].faction = characters[key].faction or faction
    characters[key].realm = characters[key].realm or key:match("%-(.+)$")
  end
  KeepOrSellDB.factions = nil
  local key = ns.CharacterKey()
  local faction, class = UnitFactionGroup and UnitFactionGroup("player"), select(2, UnitClass("player"))
  local ruleset = ns.CurrentRuleset()
  local me = {faction = faction, class = class, ruleset = ruleset or ns.StoredRuleset(characters, ns.CharacterName())}
  for _, oldKey in ipairs(ns.OldCharacterKeys(KeepOrSellDB, ns.CharacterName(), ns.CharacterName(true), key, me)) do
    ns.MoveCharacterData(KeepOrSellDB, oldKey, key)
  end
  local old = characters[key] or {}
  characters[key] = {
    faction = faction or old.faction,
    class = class,
    ruleset = ruleset or old.ruleset,
    -- only where there is no ruleset to pool by (other clients): Forever no longer tells addons the realm
    realm = not (ruleset or old.ruleset) and GetRealmName and GetRealmName() or nil,
    reagentEconomy = ns.HasReagentEconomy(),
    professions = ns.CurrentProfessions() or old.professions,
  }
  altIndex = nil -- built without the own record so far
end

-- Adds why an alt needs itemID to result ({[itemID] = {[key] = alt}} while building).
local function Need(result, itemID, key, name)
  result[itemID] = result[itemID] or {}
  local alt = result[itemID][key]
  if not alt then
    alt = {key = key, name = name, professions = {}, profession = false, class = false}
    result[itemID][key] = alt
  end
  return alt
end

-- {[itemID] = {alt, ...}}: what the other characters of the account (same pool as meKey, see ns.SamePool) need.
-- alt = {key, name, professions = {profession name, ...}, profession, class}: profession = a known, non-grey recipe
-- still gains skill from it (professions names it when the recipe's profession is stored), class = a class item of
-- the alt's class. recipes/crafts/recipeProfession are the per-character tables of Professions.lua. Lists sorted
-- by name, professions sorted. Pure.
function ns.AltIndex(characters, recipes, crafts, recipeProfession, meKey)
  characters = characters or {}
  local me = characters[meKey]
  local building = {}
  for key, record in pairs(characters) do
    if key ~= meKey and ns.SamePool(me, record) then
      local name = key:match("^(.-)%-") or key
      -- recipes grouped by profession; false = recipes stored before professions were
      local groups = {}
      local owners = recipeProfession and recipeProfession[key] or {}
      for recipeID, reagents in pairs(recipes and recipes[key] or {}) do
        local profession = owners[recipeID] or false
        groups[profession] = groups[profession] or {}
        groups[profession][recipeID] = reagents
      end
      for profession, group in pairs(groups) do
        for itemID in pairs(ns.ReagentIndex(group, crafts and crafts[key])) do
          local alt = Need(building, itemID, key, name)
          alt.profession = true
          if profession then table.insert(alt.professions, profession) end
        end
      end
      for _, itemID in ipairs(ns.ClassItemIDs(record.class, record.reagentEconomy)) do
        Need(building, itemID, key, name).class = true
      end
    end
  end
  local result = {}
  for itemID, byKey in pairs(building) do
    local list = {}
    for _, alt in pairs(byKey) do
      table.sort(alt.professions)
      table.insert(list, alt)
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    result[itemID] = list
  end
  return result
end

-- The other characters of the account that need the item (see ns.AltIndex), or nil
function ns.AltsNeedingItem(itemID)
  if not (itemID and KeepOrSellDB) then return nil end
  if not altIndex then
    altIndex = ns.AltIndex(KeepOrSellDB.characters, KeepOrSellDB.recipes, KeepOrSellDB.crafts,
      KeepOrSellDB.recipeProfession, ns.CharacterKey())
  end
  return altIndex[itemID]
end

-- The alts that count with the player's options: account mode on, and per alt (db.altSettings[key], a missing
-- value means on) included and its need switched on (profession, classItems). Returns copies without the
-- switched-off reason, or nil when none is left. Pure.
function ns.FilterAlts(alts, db)
  if not (alts and db.accountMode) then return nil end
  local settings = db.altSettings or {}
  local result = {}
  for _, alt in ipairs(alts) do
    local s = settings[alt.key] or {}
    local profession = alt.profession and s.profession ~= false or false
    local class = alt.class and s.classItems ~= false or false
    if s.included ~= false and (profession or class) then
      table.insert(result, {key = alt.key, name = alt.name, professions = profession and alt.professions or {},
        profession = profession, class = class})
    end
  end
  return #result > 0 and result or nil
end

-- {{key, name, class}, ...} sorted by name: the characters in the same pool as me ({key, faction, ruleset, realm}),
-- without me; the options list them. Pure.
function ns.AltCharacters(characters, me)
  local result = {}
  for key, record in pairs(characters or {}) do
    if key ~= me.key and ns.SamePool(me, record) then
      table.insert(result, {key = key, name = key:match("^(.-)%-") or key, class = record.class})
    end
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

-- Folds the account mode switches of older versions into db.altSettings, for every character known now (keys of
-- characters and recipes): altReagents (0.18-0.19) and altProfession = false turn profession materials off,
-- altClassItems = false class items, altIncluded[key] = false leaves the alt out. Values already in altSettings
-- stay. The old keys are removed. Pure.
function ns.MigrateAltSettings(db)
  local profession = db.altReagents == false or db.altProfession == false
  local classItems = db.altClassItems == false
  local excluded = db.altIncluded or {}
  local known = {}
  for key in pairs(db.characters or {}) do known[key] = true end
  for key in pairs(db.recipes or {}) do known[key] = true end
  for key in pairs(excluded) do known[key] = true end
  for key in pairs(known) do
    local off = {profession = profession or nil, classItems = classItems or nil, included = excluded[key] == false or nil}
    if next(off) then
      db.altSettings = db.altSettings or {}
      local s = db.altSettings[key] or {}
      db.altSettings[key] = s
      for field in pairs(off) do
        if s[field] == nil then s[field] = false end
      end
    end
  end
  db.altReagents, db.altProfession, db.altClassItems, db.altIncluded = nil, nil, nil, nil
end

-- A character's professions, sorted: the ones recorded at its last login ({[name] = {icon, rank, maxRank}}), else
-- the names its stored recipes carry
local function ProfessionNames(record, recipeProfessions)
  local seen, names = {}, {}
  local recorded = record and record.professions
  for name in pairs(recorded or {}) do table.insert(names, name) end
  if not recorded then
    for _, name in pairs(recipeProfessions or {}) do
      if not seen[name] then seen[name] = true; table.insert(names, name) end
    end
  end
  table.sort(names)
  return names, recorded or {}
end

-- One row per character for the options window: me first (isSelf), then the alts sorted by name:
-- {key, name, class, isSelf, professions = "A, B" or nil, professionList = {"A", "B"}, professionIcons = the
-- recorded professions as stored, included, profession, classItems}. Pure.
function ns.AltRows(characters, recipeProfession, altSettings, me)
  characters = characters or {}
  local list = ns.AltCharacters(characters, me)
  local own = characters[me.key] or {}
  table.insert(list, 1, {key = me.key, name = me.key:match("^(.-)%-") or me.key, class = own.class, isSelf = true})
  local rows = {}
  for _, alt in ipairs(list) do
    local names, icons = ProfessionNames(characters[alt.key], recipeProfession and recipeProfession[alt.key])
    local s = altSettings and altSettings[alt.key] or {}
    table.insert(rows, {key = alt.key, name = alt.name, class = alt.class, isSelf = alt.isSelf,
      professions = #names > 0 and table.concat(names, ", ") or nil, professionList = names, professionIcons = icons,
      included = s.included ~= false, profession = s.profession ~= false, classItems = s.classItems ~= false})
  end
  return rows
end

local FACTION_NAMES = {Alliance = "FACTION_ALLIANCE", Horde = "FACTION_HORDE"}

-- "PvP · Horde": the pool the alts share; the realm when the ruleset is unknown. Pure apart from the client's
-- faction names (globals FACTION_ALLIANCE / FACTION_HORDE when they exist).
function ns.PoolText(me)
  local faction = me.faction and (_G[FACTION_NAMES[me.faction] or ""] or me.faction) or "?"
  local ruleset = me.ruleset == "RPPvP" and "RP-PvP" or me.ruleset
  return ("%s · %s"):format(ruleset or me.realm or "?", faction)
end
