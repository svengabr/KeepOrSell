-- The look of KeepOrSell's own windows (setup, options), built from Blizzard's textures (atlases, icons,
-- Morpheus font); nothing is shipped with the addon. Atlases are checked first; a missing one falls back to a
-- plain line.
local _, ns = ...

local Style = {}
ns.Style = Style

Style.ICONS = "Interface\\Icons\\"
local LOGO = "Interface\\AddOns\\KeepOrSell\\Icon"
Style.HEADER_FONT = "Fonts\\MORPHEUS.TTF"
Style.GOLD = {0.79, 0.64, 0.29}
Style.PARCHMENT = {0.95, 0.89, 0.71}
local GOLD, PARCHMENT, HEADER_FONT = Style.GOLD, Style.PARCHMENT, Style.HEADER_FONT

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = {left = 3, right = 3, top = 3, bottom = 3},
}

-- Dark box with a gold-tinted border, like the panels of the quest log
function Style.Box(parent, shade, border)
  local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if box.SetBackdrop then
    box:SetBackdrop(BACKDROP)
    box:SetBackdropColor(shade, shade * 0.85, shade * 0.6, 0.95)
    box:SetBackdropBorderColor(GOLD[1] * border, GOLD[2] * border, GOLD[3] * border)
  end
  return box
end

function Style.SetAtlasOr(texture, atlas, r, g, b)
  if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(atlas) then
    texture:SetAtlas(atlas)
  else
    texture:SetColorTexture(r, g, b, 0.8)
  end
end

-- Heading in the quest book font with an ornamental divider below; y counts from the top of the
-- parent, or from the bottom of below when given
function Style.Heading(parent, text, size, y, below)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  label:SetFont(HEADER_FONT, size, "")
  label:SetTextColor(unpack(PARCHMENT))
  if below then label:SetPoint("TOP", below, "BOTTOM", 0, y) else label:SetPoint("TOP", 0, y) end
  label:SetText(text)
  local divider = parent:CreateTexture(nil, "ARTWORK")
  Style.SetAtlasOr(divider, "Campaign-QuestLog-LoreDivider", unpack(GOLD))
  divider:SetSize(parent:GetWidth() - 40, size > 16 and 10 or 6)
  divider:SetPoint("TOP", label, "BOTTOM", 0, -2)
  return label
end

function Style.Button(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetText(text)
  button:SetSize(120, 22)
  button:SetScript("OnClick", onClick)
  return button
end

-- A hidden, movable window in the style of Blizzard's own (ButtonFrameTemplate with our logo in the portrait;
-- portrait = false hides it), above the settings panel, closed by Esc
function Style.Window(name, title, width, height, portrait)
  local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
  frame:Hide()
  if portrait ~= false and frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(LOGO)
    -- cut the square icon down to the round emblem (Icon.tga: centre 32/32, teal disc r 18 of 64), with room
    -- for the portrait ring, so the emblem fills it and sits in its middle
    if frame.SetPortraitTexCoord then frame:SetPortraitTexCoord(9.5 / 64, 54.5 / 64, 9.5 / 64, 54.5 / 64) end
  elseif ButtonFrameTemplate_HidePortrait then
    ButtonFrameTemplate_HidePortrait(frame)
  end
  if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
  if frame.Inset then frame.Inset:Hide() end
  if frame.SetTitle then frame:SetTitle(title) end
  frame:SetSize(width, height)
  frame:SetFrameStrata("DIALOG") -- above the options panel it can be opened from
  frame:SetToplevel(true)
  frame:SetPoint("CENTER")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  table.insert(UISpecialFrames, name) -- Esc closes it
  return frame
end
