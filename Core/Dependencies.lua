-- Which optional addons are installed and running, for the options panel
local _, ns = ...
local L = ns.L

-- name = addon folder; use = what KeepOrSell needs it for
ns.DEPENDENCIES = {
  {name = "Auctionator", use = L.DEP_AUCTIONATOR},
  {name = "TradeSkillMaster", use = L.DEP_TSM},
  {name = "Baganator", use = L.DEP_BAGANATOR},
  {name = "Scrap", use = L.DEP_SCRAP},
  {name = "Questie", use = L.DEP_QUESTIE},
}

-- Options that do nothing without the addon; a list means any of them is enough
ns.OPTION_NEEDS = {
  factor = {"Auctionator", "TradeSkillMaster"}, minProfit = {"Auctionator", "TradeSkillMaster"},
  maxAge = "Auctionator", -- TSM has no price age
  setSource = "Baganator", destroy = "Baganator", bagValue = "Baganator", questie = "Questie",
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

-- KeepOrSell talks to QuestieDB, not Questie itself
local COMPATIBLE = {
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

-- "<colored status> · <use>"
function ns.DependencyText(dep)
  local color, key = unpack(STATUS[ns.GetDependencyStatus(dep.name)])
  return ("|c%s%s|r · %s"):format(color, L[key], dep.use)
end

-- Mixin for KeepOrSellDependencyTemplate (Options.xml): one row per dependency
KeepOrSellDependencyMixin = {}

function KeepOrSellDependencyMixin:Init(initializer)
  -- normally set up by OnLoad (Options.xml); without it Init and Release break the whole list
  if not self.cbrHandles then SettingsListElementMixin.OnLoad(self) end
  SettingsListElementMixin.Init(self, initializer)
  -- status is read whenever the row is shown, so enabling an addon shows up after /reload
  self.Status:SetText(ns.DependencyText(initializer.data))
end
