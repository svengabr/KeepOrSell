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
  if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum and Enum.GameRule) then return nil end
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

-- Writes the current character's record; older versions kept only the faction in KeepOrSellDB.factions.
function ns.RecordCharacter()
  if not KeepOrSellDB then return end
  local characters = KeepOrSellDB.characters or {}
  KeepOrSellDB.characters = characters
  for key, faction in pairs(KeepOrSellDB.factions or {}) do
    characters[key] = characters[key] or {}
    characters[key].faction = characters[key].faction or faction
  end
  KeepOrSellDB.factions = nil
  local key = ns.CharacterKey()
  local old = characters[key] or {}
  characters[key] = {
    faction = UnitFactionGroup and UnitFactionGroup("player") or old.faction,
    class = select(2, UnitClass("player")),
    ruleset = ns.CurrentRuleset(),
    realm = GetRealmName(),
    reagentEconomy = ns.HasReagentEconomy(),
  }
end
