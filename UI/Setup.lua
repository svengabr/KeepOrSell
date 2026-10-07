-- Setup window for new players: which addons KeepOrSell needs, Baganator's category view, the first price scan.
-- Opens after login until the required steps are done or the player ticks "Don't show again"; /kos setup any time.
local _, ns = ...
local L = ns.L

-- Baganator profile with category groups; Baganator fills in its defaults for everything else.
-- Imported as its own profile, so the player's old profile stays and can be picked again.
local PROFILE = '{"addon":"Baganator","version":3,"kind":"profile","bag_view_type":"category","bank_view_type":"category"}'
local PROFILE_NAME = "KeepOrSell"

-- state: {baganator, baganatorSetup, auctionator, tsm, ahVisited, scrap, questie}, all booleans.
-- Returns the steps in display order: {key, done, required}. Pure.
function ns.SetupSteps(state)
  local scanned
  if state.auctionator then
    scanned = state.ahVisited == true
  else
    -- like the hints: TSM alone already brings prices, there is no scan to ask for
    scanned = state.tsm == true
  end
  return {
    {key = "baganator", done = state.baganator == true, required = true},
    {key = "view", done = state.baganator == true and state.baganatorSetup == true, required = true},
    {key = "auctionator", done = state.auctionator == true or state.tsm == true, required = true},
    {key = "scan", done = scanned, required = true},
    {key = "scrap", done = state.scrap == true, required = false},
    {key = "questie", done = state.questie == true, required = false},
  }
end

-- Required steps done and in total, for the progress bar. Pure.
function ns.SetupProgress(steps)
  local done, total = 0, 0
  for _, step in ipairs(steps) do
    if step.required then
      total = total + 1
      if step.done then done = done + 1 end
    end
  end
  return done, total
end

-- true when every required step is done. Pure.
function ns.SetupComplete(steps)
  local done, total = ns.SetupProgress(steps)
  return done == total
end

-- Whether the window opens by itself after login. Pure.
function ns.ShouldShowSetup(hidden, complete)
  return not hidden and not complete
end

function ns.GetSetupState()
  local done = KeepOrSellDB.baganatorSetup
  return {
    baganator = ns.IsDependencyReady("Baganator"),
    -- Baganator keeps the active profile per character
    baganatorSetup = done ~= nil and done[ns.CharacterKey()] == true,
    auctionator = ns.IsDependencyReady("Auctionator"),
    tsm = ns.IsDependencyReady("TradeSkillMaster"),
    ahVisited = KeepOrSellDB.ahVisited == true,
    scrap = ns.IsDependencyReady("Scrap"),
    questie = ns.IsDependencyReady("Questie"),
  }
end

function ns.IsSetupComplete()
  return ns.SetupComplete(ns.SetupSteps(ns.GetSetupState()))
end

function ns.MarkBaganatorSetup()
  KeepOrSellDB.baganatorSetup = KeepOrSellDB.baganatorSetup or {}
  KeepOrSellDB.baganatorSetup[ns.CharacterKey()] = true
end

-- Imports and activates the Baganator profile; false when Baganator can't take it
function ns.SetupBaganator()
  local api = Baganator and Baganator.API
  if not (api and api.ImportString) then return false end
  if not pcall(api.ImportString, PROFILE, PROFILE_NAME) then return false end
  ns.MarkBaganatorSetup()
  return true
end

-- Window ---------------------------------------------------------------------------------------------------
-- Built from Blizzard's own textures (atlases, icons, Morpheus font), nothing is shipped with the addon.
-- Atlases are checked first; a missing one falls back to a plain line.

local ICONS = "Interface\\Icons\\"
local LOGO = "Interface\\AddOns\\KeepOrSell\\Icon"
local HEADER_FONT = "Fonts\\MORPHEUS.TTF"
local GOLD = {0.79, 0.64, 0.29}
local PARCHMENT = {0.95, 0.89, 0.71}

-- title, short text on the tile, long text in its tooltip, icon
local STEPS = {
  baganator = {"SETUP_BAGANATOR", "SETUP_BAGANATOR_SHORT", "SETUP_BAGANATOR_TIP", "INV_Misc_Bag_08"},
  view = {"SETUP_VIEW", "SETUP_VIEW_SHORT", "SETUP_VIEW_TIP", "INV_Misc_Bag_10"},
  auctionator = {"SETUP_AUCTIONATOR", "SETUP_AUCTIONATOR_SHORT", "SETUP_AUCTIONATOR_TIP", "INV_Misc_Coin_01"},
  scan = {"SETUP_SCAN", nil, "SETUP_SCAN_TIP", "INV_Misc_Spyglass_02"},
  scrap = {"SETUP_SCRAP", "SETUP_SCRAP_SHORT", "SETUP_SCRAP_TIP", "INV_Misc_Coin_03"},
  questie = {"SETUP_QUESTIE", "SETUP_QUESTIE_SHORT", "SETUP_QUESTIE_TIP", "INV_Misc_Book_09"},
}

-- Sample bag on the left: the groups in the colors of the gallery, with plain vanilla item icons.
-- Item border colors: 0 grey frame, 2 green, 3 blue.
local SAMPLE = {
  {"SET_QUEST", {1, 0.82, 0}, {{"INV_Misc_Note_01"}, {"INV_Misc_Bone_ElfSkull_01"}}},
  {"SET_PROFESSION", {0.29, 0.66, 1}, {{"INV_Fabric_Linen_01"}, {"INV_Fabric_Silk_01"}, {"INV_Misc_LeatherScrap_02"}}},
  {"SET_AH", {1, 0.71, 0.24}, {{"INV_Potion_51"}, {"INV_Misc_Gem_Emerald_01", 3}}},
  {"SET_DISENCHANT", {0.69, 0.5, 1}, {{"INV_Sword_04", 2}, {"INV_Jewelry_Ring_03", 2}}},
  {"TIP_JUNK", {0.62, 0.62, 0.62}, {{"INV_Misc_Pelt_Wolf_01"}, {"INV_Misc_Food_19"}}},
}
local QUALITY = {[0] = {0.3, 0.3, 0.3}, [2] = {0.12, 1, 0}, [3] = {0, 0.44, 0.87}}

local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_OPEN = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local WIDTH, HEIGHT = 760, 486
local LEFT_W, RIGHT_W, PANEL_H = 278, 452, 410
local INNER = RIGHT_W - 24

local frame
local manualView = false -- the import failed, show the way by hand

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8x8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = {left = 3, right = 3, top = 3, bottom = 3},
}

-- Dark box with a gold-tinted border, like the panels of the quest log
local function Box(parent, shade, border)
  local box = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  if box.SetBackdrop then
    box:SetBackdrop(BACKDROP)
    box:SetBackdropColor(shade, shade * 0.85, shade * 0.6, 0.95)
    box:SetBackdropBorderColor(GOLD[1] * border, GOLD[2] * border, GOLD[3] * border)
  end
  return box
end

local function SetAtlasOr(texture, atlas, r, g, b)
  if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(atlas) then
    texture:SetAtlas(atlas)
  else
    texture:SetColorTexture(r, g, b, 0.8)
  end
end

-- Heading in the quest book font with an ornamental divider below
local function Heading(parent, text, size, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  label:SetFont(HEADER_FONT, size, "")
  label:SetTextColor(unpack(PARCHMENT))
  label:SetPoint("TOP", 0, y)
  label:SetText(text)
  local divider = parent:CreateTexture(nil, "ARTWORK")
  SetAtlasOr(divider, "Campaign-QuestLog-LoreDivider", unpack(GOLD))
  divider:SetSize(parent:GetWidth() - 40, size > 16 and 10 or 6)
  divider:SetPoint("TOP", label, "BOTTOM", 0, -2)
  return label
end

local function Icon(parent, file, size, quality)
  local border = parent:CreateTexture(nil, "BORDER")
  border:SetSize(size + 2, size + 2)
  border:SetColorTexture(unpack(QUALITY[quality] or GOLD))
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetSize(size, size)
  icon:SetPoint("CENTER", border)
  icon:SetTexture(ICONS .. file)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- cut the icon's own frame
  return border
end

local function Button(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetText(text)
  button:SetSize(120, 22)
  button:SetScript("OnClick", onClick)
  return button
end

local function ShowTileTooltip(tile)
  GameTooltip:SetOwner(tile, "ANCHOR_RIGHT")
  GameTooltip:SetText(tile.title)
  GameTooltip:AddLine(tile.tip, 1, 1, 1, true)
  GameTooltip:Show()
end

-- One step as a tile: icon, title, short text, status badge; the long explanation is in the tooltip
local function Tile(parent, key, width, height)
  local title, short, tip, icon = unpack(STEPS[key])
  local tile = Box(parent, 0.13, 0.45)
  tile:SetSize(width, height)
  tile:EnableMouse(true)
  tile.title, tile.tip = L[title], L[tip]
  tile:SetScript("OnEnter", ShowTileTooltip)
  tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local size = height < 56 and 28 or 36
  Icon(tile, icon, size):SetPoint("TOPLEFT", 8, -8)
  tile.Title = tile:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  tile.Title:SetPoint("TOPLEFT", size + 18, -9)
  tile.Title:SetPoint("RIGHT", -26, 0)
  tile.Title:SetJustifyH("LEFT")
  tile.Title:SetText(L[title])
  if short then
    tile.Short = tile:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tile.Short:SetPoint("TOPLEFT", tile.Title, "BOTTOMLEFT", 0, -3)
    tile.Short:SetPoint("RIGHT", -10, 0)
    tile.Short:SetJustifyH("LEFT")
    tile.Short:SetText(L[short])
  end
  tile.Badge = tile:CreateTexture(nil, "OVERLAY")
  tile.Badge:SetSize(18, 18)
  tile.Badge:SetPoint("TOPRIGHT", -6, -6)
  frame.tiles[key] = tile
  return tile
end

-- The three scan steps as small numbered boxes
local function ScanSteps(tile)
  local width = (INNER - 52 - 2 * 6 - 10) / 3
  for i = 1, 3 do
    local box = Box(tile, 0.05, 0.35)
    box:SetSize(width, 50)
    box:SetPoint("TOPLEFT", 52 + (i - 1) * (width + 6), -32)
    local number = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    number:SetFont(HEADER_FONT, 18, "")
    number:SetPoint("TOP", 0, -4)
    number:SetText(i)
    local text = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("TOP", number, "BOTTOM", 0, -1)
    text:SetWidth(width - 8)
    text:SetText(L["SETUP_SCAN_STEP" .. i])
  end
end

local function BuildLeft(panel)
  -- the logo already sits in the portrait, so the name leads here
  local name = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
  name:SetFont(HEADER_FONT, 26, "")
  name:SetTextColor(1, 0.82, 0)
  name:SetPoint("TOPLEFT", 14, -16)
  name:SetText("KeepOrSell")
  local tagline = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  tagline:SetFont(HEADER_FONT, 13, "")
  tagline:SetTextColor(unpack(PARCHMENT))
  tagline:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  tagline:SetWidth(LEFT_W - 28) -- the German tagline needs two lines
  tagline:SetJustifyH("LEFT")
  tagline:SetText(L.SETUP_TAGLINE)
  local about = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  about:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -8)
  about:SetWidth(LEFT_W - 28)
  about:SetJustifyH("LEFT")
  about:SetText(L.SETUP_ABOUT)

  local bag = Box(panel, 0.04, 0.5)
  bag:SetSize(LEFT_W - 24, 5 * 28 + 12)
  bag:SetPoint("TOPLEFT", 12, -126)
  for row, group in ipairs(SAMPLE) do
    local key, color, items = unpack(group)
    local y = -8 - (row - 1) * 28
    local label = bag:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, y - 6)
    label:SetTextColor(unpack(color))
    label:SetText(L[key])
    for i, item in ipairs(items) do
      Icon(bag, item[1], 22, item[2] or 0):SetPoint("TOPLEFT", 102 + (i - 1) * 26, y)
    end
  end

  Heading(panel, L.SETUP_PROGRESS, 15, -292)
  frame.ProgressText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  frame.ProgressText:SetPoint("TOPLEFT", 16, -326)
  frame.Progress = CreateFrame("StatusBar", nil, panel)
  frame.Progress:SetSize(LEFT_W - 32, 12)
  frame.Progress:SetPoint("TOPLEFT", 16, -346)
  frame.Progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  frame.Progress:SetStatusBarColor(unpack(GOLD))
  local track = frame.Progress:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(0, 0, 0, 0.6)
  frame.Done = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.Done:SetPoint("TOPLEFT", 16, -366)
  frame.Done:SetWidth(LEFT_W - 32)
  frame.Done:SetJustifyH("LEFT")
end

local function BuildRight(panel)
  Heading(panel, L.SETUP_HEADER, 20, -10)
  local half = (INNER - 8) / 2
  Tile(panel, "baganator", half, 66):SetPoint("TOPLEFT", 12, -46)
  Tile(panel, "auctionator", half, 66):SetPoint("TOPRIGHT", -12, -46)

  local view = Tile(panel, "view", INNER, 84)
  view:SetPoint("TOPLEFT", 12, -120)
  view.SetUp = Button(view, L.SETUP_VIEW_BUTTON, function()
    manualView = not ns.SetupBaganator()
    ns.RefreshBaganator()
    ns.UpdateSetup()
  end)
  view.SetUp:SetPoint("BOTTOMLEFT", 52, 8)
  -- for players who already picked category groups in Baganator's own welcome window
  view.Already = Button(view, L.SETUP_VIEW_ALREADY, function()
    ns.MarkBaganatorSetup()
    ns.UpdateSetup()
  end)
  view.Already:SetPoint("LEFT", view.SetUp, "RIGHT", 8, 0)

  local scan = Tile(panel, "scan", INNER, 92)
  scan:SetPoint("TOPLEFT", 12, -212)
  ScanSteps(scan)

  Heading(panel, L.SETUP_OPTIONAL, 14, -316)
  Tile(panel, "scrap", half, 46):SetPoint("TOPLEFT", 12, -346)
  Tile(panel, "questie", half, 46):SetPoint("TOPRIGHT", -12, -346)
end

local function Refresh()
  local steps = ns.SetupSteps(ns.GetSetupState())
  for _, step in ipairs(steps) do
    local tile = frame.tiles[step.key]
    -- optional addons that are missing get no badge, they are no task
    tile.Badge:SetShown(step.done or step.required)
    tile.Badge:SetTexture(step.done and ICON_DONE or ICON_OPEN)
    if step.done then
      tile.Title:SetTextColor(0.5, 0.85, 0.45)
    elseif step.required then
      tile.Title:SetTextColor(1, 0.82, 0)
    else
      tile.Title:SetTextColor(0.6, 0.55, 0.45)
    end
  end
  local view = frame.tiles.view
  view.Short:SetText(manualView and L.SETUP_VIEW_MANUAL_SHORT or L.SETUP_VIEW_SHORT)
  view.tip = manualView and L.SETUP_VIEW_MANUAL or L.SETUP_VIEW_TIP
  local baganator = ns.IsDependencyReady("Baganator")
  view.SetUp:SetEnabled(baganator)
  view.Already:SetEnabled(baganator)

  local done, total = ns.SetupProgress(steps)
  frame.ProgressText:SetText(L.SETUP_PROGRESS_TEXT:format(done, total))
  frame.Progress:SetMinMaxValues(0, total)
  frame.Progress:SetValue(done)
  frame.Done:SetText(done == total and L.SETUP_DONE or "")
  frame.HideCheck:SetChecked(KeepOrSellDB.setupHidden == true)
end

local function CreateSetupFrame()
  frame = CreateFrame("Frame", "KeepOrSellSetupFrame", UIParent, "ButtonFrameTemplate")
  frame:Hide()
  frame.tiles = {}
  -- our logo in the round portrait, like Blizzard's own windows
  if frame.SetPortraitToAsset then
    frame:SetPortraitToAsset(LOGO)
  elseif ButtonFrameTemplate_HidePortrait then
    ButtonFrameTemplate_HidePortrait(frame)
  end
  if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
  if frame.Inset then frame.Inset:Hide() end
  if frame.SetTitle then frame:SetTitle(L.SETUP_TITLE) end
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetFrameStrata("DIALOG") -- above the options panel it can be opened from
  frame:SetToplevel(true)
  frame:SetPoint("CENTER")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  table.insert(UISpecialFrames, "KeepOrSellSetupFrame") -- Esc closes it

  local left = Box(frame, 0.08, 0.7)
  left:SetSize(LEFT_W, PANEL_H)
  left:SetPoint("TOPLEFT", 12, -30)
  BuildLeft(left)
  local right = Box(frame, 0.08, 0.7)
  right:SetSize(RIGHT_W, PANEL_H)
  right:SetPoint("TOPRIGHT", -12, -30)
  BuildRight(right)

  frame.HideCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.HideCheck:SetSize(24, 24)
  frame.HideCheck:SetPoint("BOTTOMLEFT", 12, 10)
  frame.HideCheck:SetScript("OnClick", function(self) KeepOrSellDB.setupHidden = self:GetChecked() and true or false end)
  local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("LEFT", frame.HideCheck, "RIGHT", 2, 0)
  label:SetText(L.SETUP_DONT_SHOW)

  local close = Button(frame, L.SETUP_CLOSE, function() frame:Hide() end)
  close:SetPoint("BOTTOMRIGHT", -14, 12)

  frame:SetScript("OnShow", Refresh)
end

function ns.ShowSetup()
  if not frame then CreateSetupFrame() end
  if frame:IsShown() then Refresh() else frame:Show() end
end

-- Status changed (auction house visited, prices scanned): update the open window
function ns.UpdateSetup()
  if frame and frame:IsShown() then Refresh() end
end

-- After login: open once unless done or hidden. Waits for Baganator's own welcome window,
-- which asks the same question about the view and would sit on top of ours.
function ns.MaybeShowSetup()
  if not ns.ShouldShowSetup(KeepOrSellDB.setupHidden == true, ns.IsSetupComplete()) then return end
  local welcome = _G.Baganator_WelcomeFrame
  if welcome and welcome:IsShown() then
    local waiting = true
    welcome:HookScript("OnHide", function()
      if not waiting then return end
      waiting = false
      ns.MaybeShowSetup()
    end)
    return
  end
  ns.ShowSetup()
end
