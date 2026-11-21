-- Who the player is for data kept per character or per auction house: name, ruleset and the keys built from them.
-- Forever no longer tells addons the realm (since the patch of 20 November 2026); it has one realm per ruleset, so
-- the ruleset takes the realm's place.
local _, ns = ...

-- Name of the ruleset ("HC", "RPPvP", "RP", "PvP" or "PvE"); isActive(ruleKey) answers for "PvPRuleset",
-- "RPRuleset" and "HardcoreRuleset". RP-PvP has both rules active. Pure.
function ns.RulesetName(isActive)
  if isActive("HardcoreRuleset") then return "HC" end
  local rp, pvp = isActive("RPRuleset"), isActive("PvPRuleset")
  if rp and pvp then return "RPPvP" end
  if rp then return "RP" end
  if pvp then return "PvP" end
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

-- The ruleset stored for a character name (the name part of the keys "Name-Ruleset"), nil when none. Pure.
function ns.StoredRuleset(characters, name)
  for key, record in pairs(characters or {}) do
    if type(record) == "table" and record.ruleset and key:match("^(.-)%-") == name then return record.ruleset end
  end
  return nil
end

-- What stands behind the name in per-character keys and auction house keys: the ruleset (one realm per ruleset on
-- Forever), the one stored for this character while the client can't tell yet, else the realm (other clients).
function ns.PoolName()
  local ruleset = ns.CurrentRuleset()
    or ns.StoredRuleset(KeepOrSellDB and KeepOrSellDB.characters, ns.CharacterName())
  if ruleset then return ruleset end
  local realm = GetRealmName and GetRealmName()
  return realm ~= nil and realm ~= "" and realm or "?"
end

-- The character's name. Forever's characters have a surname (UnitName returns it second while regional unique
-- names are on): "Drache Offiziell", unique in the region. firstNameOnly gives the name older versions used.
function ns.CharacterName(firstNameOnly)
  local name, surname = UnitName("player")
  name = name or "?"
  if not firstNameOnly and surname and surname ~= "" and RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
    local separators = Constants and Constants.CharacterNameSeparatorConsts
    name = name .. (separators and separators.CHARACTERNAME_SURNAME_SEPARATOR or " ") .. surname
  end
  return name
end

-- "Name-Ruleset", for data KeepOrSell keeps per character: "Drache Offiziell-PvP" (ns.PoolName).
function ns.CharacterKey()
  return ns.CharacterName() .. "-" .. ns.PoolName()
end
