-- Which optional addons are installed and running, for the options window
local _, ns = ...
local L = ns.L

-- name = addon folder; use = what KeepOrSell needs it for
ns.DEPENDENCIES = {
  {name = "Auctionator", use = L.DEP_AUCTIONATOR},
  {name = "ForeverLedger", use = L.DEP_LEDGER},
  {name = "TradeSkillMaster", use = L.DEP_TSM},
  {name = "Baganator", use = L.DEP_BAGANATOR},
  {name = "Scrap", use = L.DEP_SCRAP},
  {name = "Questie", use = L.DEP_QUESTIE},
}

-- Options that do nothing without the addon; a list means any of them is enough
ns.OPTION_NEEDS = {
  factor = {"Auctionator", "ForeverLedger", "TradeSkillMaster"},
  minProfit = {"Auctionator", "ForeverLedger", "TradeSkillMaster"},
  maxAge = {"Auctionator", "ForeverLedger"}, -- TSM has no price age
  greyVendor = {"Auctionator", "ForeverLedger", "TradeSkillMaster"},
  setSource = "Baganator", destroy = "Baganator", bagValue = "Baganator", questie = "Questie",
  groupQuest = "Baganator", groupOpen = "Baganator", groupProfession = "Baganator", groupAH = "Baganator",
  groupDisenchant = "Baganator", groupAlt = "Baganator", groupUnstacked = "Baganator",
}

-- OPTION_NEEDS value as a list of addon names. Pure.
function ns.NeedsList(needs)
  return type(needs) == "table" and needs or {needs}
end

-- "active" | "outdated" (loaded, but its API doesn't match) | "disabled" (installed, not loaded) | "missing". Pure.
function ns.DependencyStatus(loaded, exists, compatible)
  if loaded then return compatible and "active" or "outdated" end
  return exists and "disabled" or "missing"
end

-- KeepOrSell talks to QuestieDB, not Questie itself; Forever Ledger before 0.29.0 has no API
local COMPATIBLE = {
  ForeverLedger = function() return ns.HasForeverLedger ~= nil and ns.HasForeverLedger() end,
  Questie = function() return ns.HasQuestieDB ~= nil and ns.HasQuestieDB() end,
}

function ns.GetDependencyStatus(name)
  local api = C_AddOns
  if not (api and api.IsAddOnLoaded) then return "missing" end
  local compatible = not COMPATIBLE[name] or COMPATIBLE[name]()
  return ns.DependencyStatus(api.IsAddOnLoaded(name), api.DoesAddOnExist and api.DoesAddOnExist(name), compatible)
end

function ns.IsDependencyReady(name)
  return ns.GetDependencyStatus(name) == "active"
end

function ns.IsAnyDependencyReady(needs)
  for _, name in ipairs(ns.NeedsList(needs)) do
    if ns.IsDependencyReady(name) then return true end
  end
  return false
end

local STATUS = {
  active = {"ff20ff20", "DEP_ACTIVE"},
  outdated = {"ffff8020", "DEP_OUTDATED"},
  disabled = {"ffffd200", "DEP_DISABLED"},
  missing = {"ff808080", "DEP_MISSING"},
}

-- The colored status word ("active", "not installed" …)
function ns.DependencyStatusText(dep)
  local color, key = unpack(STATUS[ns.GetDependencyStatus(dep.name)])
  return ("|c%s%s|r"):format(color, L[key])
end

-- "<colored status> · <use>"
function ns.DependencyText(dep)
  return ns.DependencyStatusText(dep) .. " · " .. dep.use
end
