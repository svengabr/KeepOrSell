-- Account mode: one record per character of the account (faction, class, ruleset, realm, Reagent Economy) in
-- KeepOrSellDB.characters, so items another character needs can be told apart.
local _, ns = ...

-- Name of the ruleset ("PvP", "RP", "HC" or "PvE"); isActive(ruleKey) answers for "PvPRuleset", "RPRuleset" and
-- "HardcoreRuleset". Pure.
function ns.RulesetName(isActive)
  if isActive("PvPRuleset") then return "PvP" end
  if isActive("RPRuleset") then return "RP" end
  if isActive("HardcoreRuleset") then return "HC" end
  return "PvE"
end

-- The current ruleset on clients where all servers of a ruleset play together (Forever), else nil.
-- Enum.GameRule is missing from the generated API docs; Syndicator uses it the same way.
function ns.CurrentRuleset()
  if not (RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled()) then return nil end
  local rules = Enum and Enum.GameRule
  if not (C_GameRules and C_GameRules.IsGameRuleActive and rules) then return nil end
  -- without the rules the answer would always be "PvE" and pool Hardcore with normal characters: unknown instead
  if not (rules.PvPRuleset or rules.RPRuleset or rules.HardcoreRuleset) then return nil end
  return ns.RulesetName(function(key)
    return Enum.GameRule[key] ~= nil and C_GameRules.IsGameRuleActive(Enum.GameRule[key]) == true
  end)
end

-- true = an item can be mailed between the two characters: same faction and same ruleset (the ruleset is the
-- server on Forever). Records written before rulesets were stored compare by realm. Pure.
function ns.SamePool(me, other)
  if not (me and other and me.faction and me.faction == other.faction) then return false end
  if me.ruleset and other.ruleset then return me.ruleset == other.ruleset end
  return me.realm ~= nil and me.realm == other.realm
end

-- Tables in KeepOrSellDB keyed by character
local PER_CHARACTER = {"recipes", "upcoming", "crafts", "recipeProfession", "opened", "baganatorSetup", "characters",
  "altIncluded"}

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

local altIndex -- built once per session: other characters only change in their own sessions

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
  -- versions before the surname kept this character under its first name only
  ns.MoveCharacterData(KeepOrSellDB, ns.CharacterKey(true), key)
  local old = characters[key] or {}
  characters[key] = {
    faction = UnitFactionGroup and UnitFactionGroup("player") or old.faction,
    class = select(2, UnitClass("player")),
    ruleset = ns.CurrentRuleset() or old.ruleset,
    realm = GetRealmName(),
    reagentEconomy = ns.HasReagentEconomy(),
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

-- The alts that count with the player's options: account mode on, the alt ticked in the options
-- (db.altIncluded[key] ~= false) and its need switched on (altProfession, altClassItems). Returns copies
-- without the switched-off reason, or nil when none is left. Pure.
function ns.FilterAlts(alts, db)
  if not (alts and db.accountMode) then return nil end
  local included = db.altIncluded or {}
  local result = {}
  for _, alt in ipairs(alts) do
    local profession = db.altProfession and alt.profession or false
    local class = db.altClassItems and alt.class or false
    if included[alt.key] ~= false and (profession or class) then
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
