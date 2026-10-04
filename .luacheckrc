-- luacheck config: every WoW / third-party global the addon touches must be listed here,
-- so a typo or an accidental global fails CI instead of erroring in the client.
std = "lua51"
max_line_length = false
exclude_files = { "tests/", ".luacheckrc" }

-- Globals the addon writes to
globals = {
  "KeepOrSellDB",       -- SavedVariables
  "SLASH_KEEPORSELL1",
  "SlashCmdList",
  "Scrap",              -- hooks Scrap.IsJunk
  "KeepOrSellDependencyMixin", -- mixin of the template in Options.xml
}

read_globals = {
  -- Third-party addons (all optional)
  "Auctionator",
  "Baganator",
  "LibQuestieDB",

  -- WoW API
  "C_AddOns",
  "C_AuctionHouse",
  "C_ChatInfo",
  "C_Container",
  "C_Item",
  "C_QuestLog",
  "C_Timer",
  "C_TooltipInfo",
  "C_TradeSkillUI",
  "ClearCursor",
  "CreateFrame",
  "CursorHasItem",
  "DeleteCursorItem",
  "CreateSettingsListSectionHeaderInitializer",
  "Enum",
  "GetCursorInfo",
  "GetItemInfo",
  "GetLocale",
  "GetMoneyString",
  "GetNormalizedRealmName",
  "GetNumGroupMembers",
  "GetNumQuestLeaderBoards",
  "GetNumQuestLogEntries",
  "GetProfessionInfo",
  "GetProfessions",
  "GetQuestLogLeaderBoard",
  "GetQuestLogTitle",
  "GetRealmName",
  "GetServerTime",
  "GetTime",
  "hooksecurefunc",
  "InCombatLockdown",
  "IsInGroup",
  "IsInRaid",
  "ItemLocation",
  "UnitClass",
  "UnitFactionGroup",
  "UnitLevel",
  "UnitName",
  "UnitRace",

  -- FrameXML
  "GameTooltip",
  "ItemRefTooltip",
  "MinimalSliderWithSteppersMixin",
  "Settings",
  "SettingsListElementMixin",
  "SettingsPanel",
  "TooltipDataProcessor",
  "UIParent",

  -- Constants
  "ITEM_SPELL_KNOWN",
  "NUM_BAG_SLOTS",
}
