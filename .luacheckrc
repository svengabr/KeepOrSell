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
}

read_globals = {
  -- Third-party addons (all optional)
  "Auctionator",
  "Baganator",

  -- WoW API
  "C_Container",
  "C_Item",
  "C_QuestLog",
  "C_Timer",
  "C_TooltipInfo",
  "C_TradeSkillUI",
  "CreateFrame",
  "Enum",
  "GetItemInfo",
  "GetLocale",
  "GetMoneyString",
  "GetNumQuestLeaderBoards",
  "GetNumQuestLogEntries",
  "GetProfessionInfo",
  "GetProfessions",
  "GetQuestLogLeaderBoard",
  "GetQuestLogTitle",
  "GetRealmName",
  "GetTime",
  "ItemLocation",
  "UnitClass",
  "UnitName",

  -- FrameXML
  "GameTooltip",
  "ItemRefTooltip",
  "MinimalSliderWithSteppersMixin",
  "Settings",
  "SettingsPanel",
  "TooltipDataProcessor",
  "UIParent",

  -- Constants
  "ITEM_SPELL_KNOWN",
  "NUM_BAG_SLOTS",
}
