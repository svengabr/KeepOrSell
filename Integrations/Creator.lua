-- The "KeepOrSell Creator" line in the tooltips of the creator's characters

-- Add a character by the GUID that /dump UnitGUID("player") prints in game.
local CHARACTERS = {
  ["Player-6949-00219DC4"] = true,
  ["Player-6949-0021AECE"] = true,
  ["Player-6949-0021A0D8"] = true,
  ["Player-6949-05E29238"] = true,
}
local LINE = [[|TInterface\AddOns\KeepOrSell\Icon:0|t KeepOrSell Creator]] -- the same in every language

local marked = false -- the line is in the tooltip already, which the game can build again without clearing it

-- In instances and in combat the game hands addons secret values, and looking into one raises an error
local function NotSecret(value)
  if issecretvalue and issecretvalue(value) then return nil end
  return value
end

local function OnTooltip(tooltip, data)
  if marked or tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
  data = NotSecret(data)
  if type(data) ~= "table" or (issecrettable and issecrettable(data)) then return end
  local guid = NotSecret(data.guid)
  if guid == nil then
    local _, unit = tooltip:GetUnit()
    unit = NotSecret(unit)
    if type(unit) ~= "string" then return end
    guid = NotSecret(UnitGUID(unit))
  end
  if type(guid) ~= "string" or not CHARACTERS[guid] then return end
  tooltip:AddLine(LINE, 0, 229 / 255, 1)
  marked = true
end

-- Hooked after PLAYER_LOGIN, where other addons add their Target rows, so the line lands below them
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
  GameTooltip:HookScript("OnTooltipCleared", function() marked = false end)
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltip)
end)
