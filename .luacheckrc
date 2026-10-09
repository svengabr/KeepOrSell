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
  "TSM_API",

  -- WoW API
  "C_AddOns",
  "C_AuctionHouse",
  "C_ChatInfo",
  "C_Container",
  "C_Item",
  "C_QuestLog",
  "C_SpellBook",
  "C_Texture",
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
  "GetLootSlotInfo",
  "GetLootSlotLink",
  "GetNumLootItems",
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
  "BackdropTemplateMixin",
  "ButtonFrameTemplate_HideButtonBar",
  "ButtonFrameTemplate_HidePortrait",
  "CreateSettingsButtonInitializer",
  "UISpecialFrames",
  "GameTooltip",
  "ItemRefTooltip",
  "MinimalSliderWithSteppersMixin",
  "Settings",
  "SettingsListElementMixin",
  "SettingsPanel",
  "TooltipDataProcessor",
  "UIParent",

  -- Constants
  "ERR_INV_FULL",
  "ITEM_OPENABLE",
  "ITEM_SPELL_KNOWN",
  "LOCKED",
  "NUM_BAG_SLOTS",
}
