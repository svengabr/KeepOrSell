-- KeepOrSell's own options window: the sections of ns.OPTION_SECTIONS in a sidebar on the left, the selected
-- section's controls on the right in two columns. Looks like the setup window (UI/Style.lua). Every control writes
-- KeepOrSellDB at once, like Blizzard's settings did.
local addonName, ns = ...
local L = ns.L
local Style = ns.Style

local WIDTH, HEIGHT = 760, 486
local NAV_W, PANEL_TOP, MARGIN = 170, -30, 12
local PANEL_H = HEIGHT + PANEL_TOP - MARGIN
local CONTENT_W = WIDTH - 3 * MARGIN - NAV_W
local PAGE_W, PAGE_H = CONTENT_W - 2 * MARGIN, PANEL_H - 2 * MARGIN
local COLUMN_TOP = 40 -- below the section heading
local COLUMN_W = (PAGE_W - MARGIN) / 2
local ROW_H = 22
local DIM = 0.45
local GREY = {0.6, 0.6, 0.6}
local WHITE = {1, 1, 1}

local frame
local pages, navButtons = {}, {}
local widgets = {} -- control key -> widget, for refreshing (and tests)
local altTable

-- The widget the window keeps for a control key ("gear", "button:OPT_KEEP_FORGET", "alt:<key>:<field>",
-- "altprof:<key>:<n>", "nav:<section>", "dep:<addon>" …)
function ns.OptionsWidget(key) return widgets[key] end
function ns.OptionsFrame() return frame end
function ns.OptionsPage(id) return pages[id] end
function ns.OptionsAltTable() return altTable end

local function Ready(key)
  local needs = key and ns.OPTION_NEEDS[key]
  return not needs or ns.IsAnyDependencyReady(needs)
end

local function TooltipText(control)
  local tip = L[control.tip] or ""
  local needs = control.key and ns.OPTION_NEEDS[control.key]
  if needs then tip = tip .. "\n\n" .. L.OPT_NEEDS:format(table.concat(ns.NeedsList(needs), " / ")) end
  return tip
end

local function ShowTip(owner, title, text)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(title)
  if text and text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
  GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

local function Changed(control)
  if control.refresh then ns.SettingsChanged() end
end

-- Controls -----------------------------------------------------------------------------------------------------

local function Checkbox(parent, control, y)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetPoint("TOPLEFT", 0, y)
  box.label = box:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  box.label:SetPoint("LEFT", box, "RIGHT", 2, 0)
  box.label:SetWidth(COLUMN_W - 30)
  box.label:SetJustifyH("LEFT")
  box.label:SetText(L[control.label])
  box:SetScript("OnClick", function(self)
    KeepOrSellDB[control.key] = self:GetChecked() and true or false
    Changed(control)
    if control.key == "accountMode" and altTable then altTable.Refresh() end
  end)
  box:SetScript("OnEnter", function(self) ShowTip(self, L[control.label], TooltipText(control)) end)
  box:SetScript("OnLeave", HideTip)
  box.Refresh = function()
    box:SetChecked(KeepOrSellDB[control.key] == true)
    local ready = Ready(control.key)
    box:SetEnabled(ready)
    box.label:SetTextColor(unpack(ready and WHITE or GREY))
  end
  widgets[control.key] = box
  return 32
end

local function Round(value, step)
  return math.floor(value / step + 0.5) * step
end

-- A plain slider from Blizzard's slider textures: title above, value label on the right
local function Slider(parent, control, y)
  local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", 4, y)
  title:SetText(L[control.label])
  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(COLUMN_W - 70, 16)
  slider:SetPoint("TOPLEFT", 4, y - 18)
  slider:SetHitRectInsets(0, 0, -6, -6)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
  track:SetPoint("TOPLEFT", 0, -3)
  track:SetPoint("BOTTOMRIGHT", 0, 3)
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  slider:SetMinMaxValues(control.min, control.max)
  slider:SetValueStep(control.step)
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  slider.label:SetPoint("LEFT", slider, "RIGHT", 8, 0)
  local pending = false
  slider:SetScript("OnValueChanged", function(self, value, userInput)
    value = Round(value, control.step)
    self.label:SetText(control.format(value))
    if not userInput then return end
    KeepOrSellDB[control.key] = value
    -- dragging fires on every step; sort the bags at most every 0.3 s, the last value always counts
    if not pending then
      pending = true
      C_Timer.After(0.3, function() pending = false; Changed(control) end)
    end
  end)
  slider:SetScript("OnEnter", function(self) ShowTip(self, L[control.label], TooltipText(control)) end)
  slider:SetScript("OnLeave", HideTip)
  slider.Refresh = function()
    slider:SetValue(KeepOrSellDB[control.key] or control.min)
    slider.label:SetText(control.format(Round(KeepOrSellDB[control.key] or control.min, control.step)))
    local ready = Ready(control.key)
    slider:SetEnabled(ready)
    slider:SetAlpha(ready and 1 or DIM)
    title:SetTextColor(unpack(ready and {1, 0.82, 0} or GREY))
  end
  widgets[control.key] = slider
  return 48
end

local function ActionButton(parent, control, y)
  local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("TOPLEFT", 4, y)
  label:SetText(L[control.label])
  local button = Style.Button(parent, L[control.text], function() ns[control.action](control.arg) end)
  button:SetPoint("TOPLEFT", 4, y - 18)
  button:SetWidth(140)
  button:SetScript("OnEnter", function(self) ShowTip(self, L[control.label], L[control.tip]) end)
  button:SetScript("OnLeave", HideTip)
  widgets["button:" .. control.label] = button
  return 50
end

-- Each addon takes two lines: name and status, then what KeepOrSell needs it for
local DEP_H = 38

local function Dependencies(parent, _, y)
  for i, dep in ipairs(ns.DEPENDENCIES) do
    local line = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    line:SetPoint("TOPLEFT", 4, y - (i - 1) * DEP_H)
    line:SetWidth(COLUMN_W - 8)
    line:SetJustifyH("LEFT")
    line.Refresh = function() line:SetText(("|cffffd200%s|r  %s"):format(dep.name, ns.DependencyStatusText(dep))) end
    local use = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    use:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -2)
    use:SetWidth(COLUMN_W - 8)
    use:SetJustifyH("LEFT")
    use:SetText(dep.use)
    widgets["dep:" .. dep.name] = line
    widgets["depuse:" .. dep.name] = use
  end
  return #ns.DEPENDENCIES * DEP_H
end

-- Alt table ----------------------------------------------------------------------------------------------------

local ALT_COLUMNS = {
  {field = "profession", header = "ALTS_COL_PROFESSION"},
  {field = "classItems", header = "ALTS_COL_CLASS"},
  {field = "included", header = "ALTS_COL_INCLUDED"},
}
-- the rows must fit the scroll area (page width minus the scroll bar): 125 + 135 + 8 + 3 * 78 = 502 <= 504
local NAME_W, PROF_W, CHECK_W = 125, 135, 78
local SCROLL_W = PAGE_W - 26
local HEAD_Y, ROWS_Y = -20, -52 -- column headers may wrap to two lines

local function OwnRecord()
  local key = ns.CharacterKey()
  local own = KeepOrSellDB.characters and KeepOrSellDB.characters[key] or {}
  return {key = key, faction = own.faction, ruleset = own.ruleset, realm = own.realm}
end

local function ClassName(name, class)
  local color = class and C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class)
  return color and color.WrapTextInColorCode and color:WrapTextInColorCode(name) or name
end

local PROF_ICON, MAX_PROF_ICONS = 20, 6

local function ProfessionIcon(row, index)
  local holder = CreateFrame("Frame", nil, row)
  holder:SetSize(PROF_ICON, PROF_ICON)
  holder:SetPoint("LEFT", NAME_W + 4 + (index - 1) * (PROF_ICON + 2), 0)
  holder.icon = holder:CreateTexture(nil, "ARTWORK")
  holder.icon:SetAllPoints()
  holder.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  holder:SetScript("OnEnter", function(self) ShowTip(self, self.profession) end)
  holder:SetScript("OnLeave", HideTip)
  return holder
end

-- Up to MAX_PROF_ICONS icons, then the rest in the last icon's tooltip
local function ShowProfessions(row, alt)
  local names = alt.professionList or {}
  for key in pairs(widgets) do
    if key:match("^altprof:" .. alt.key:gsub("%p", "%%%0") .. ":") then widgets[key] = nil end
  end
  for i = 1, math.max(#names, #row.professionIcons) do
    local name = names[i]
    if name and i <= MAX_PROF_ICONS then
      local holder = row.professionIcons[i] or ProfessionIcon(row, i)
      row.professionIcons[i] = holder
      holder.profession = i == MAX_PROF_ICONS and table.concat(names, ", ", i) or name
      holder.icon:SetTexture(ns.ProfessionIcon(name))
      holder:Show()
      widgets["altprof:" .. alt.key .. ":" .. i] = holder
    elseif row.professionIcons[i] then
      row.professionIcons[i]:Hide()
    end
  end
  row.noProfessions:SetText(#names == 0 and L.ALTS_NO_PROFESSIONS or "")
  widgets["altnoprof:" .. alt.key] = row.noProfessions
end

local function AltRow(parent, index)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(SCROLL_W, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
  row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.name:SetPoint("LEFT", 2, 0)
  row.name:SetWidth(NAME_W)
  row.name:SetJustifyH("LEFT")
  -- professions as icons with their name in the tooltip; the text only when none is known
  row.noProfessions = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  row.noProfessions:SetPoint("LEFT", NAME_W + 4, 0)
  row.noProfessions:SetWidth(PROF_W)
  row.noProfessions:SetJustifyH("LEFT")
  row.professionIcons = {}
  row.checks = {}
  for i, column in ipairs(ALT_COLUMNS) do
    local box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("LEFT", NAME_W + PROF_W + 8 + (i - 1) * CHECK_W + (CHECK_W - 22) / 2, 0)
    box:SetScript("OnClick", function(self)
      KeepOrSellDB.altSettings = KeepOrSellDB.altSettings or {}
      local s = KeepOrSellDB.altSettings[row.key] or {}
      KeepOrSellDB.altSettings[row.key] = s
      s[column.field] = self:GetChecked() and true or false
      ns.SettingsChanged()
      if column.field == "included" then row:SetAlpha(s.included == false and DIM or 1) end
    end)
    row.checks[column.field] = box
  end
  return row
end

local function AltTable(parent, _, y)
  local t = CreateFrame("Frame", nil, parent)
  -- from y below the column top down to the page bottom
  t.top, t.width, t.height = y, PAGE_W, PAGE_H - COLUMN_TOP + y
  t:SetSize(t.width, t.height)
  t:SetPoint("TOPLEFT", 0, y)
  t.header = t:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  t.header:SetPoint("TOPLEFT", 4, 0)
  local heads = {{L.ALTS_COL_CHARACTER, 2}, {L.ALTS_COL_PROFESSIONS, NAME_W + 4}}
  for i, column in ipairs(ALT_COLUMNS) do
    table.insert(heads, {L[column.header], NAME_W + PROF_W + 8 + (i - 1) * CHECK_W, CHECK_W})
  end
  for _, head in ipairs(heads) do
    local text = t:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", head[2], HEAD_Y)
    if head[3] then text:SetWidth(head[3]); text:SetJustifyH("CENTER") end
    text:SetText(head[1])
  end
  -- rows scroll when there are more alts than room
  t.scroll = CreateFrame("ScrollFrame", nil, t, "UIPanelScrollFrameTemplate")
  t.scroll:SetPoint("TOPLEFT", 0, ROWS_Y)
  t.scroll:SetPoint("BOTTOMRIGHT", -(PAGE_W - SCROLL_W), 34)
  local child = CreateFrame("Frame", nil, t.scroll)
  child:SetSize(SCROLL_W, ROW_H)
  t.scroll:SetScrollChild(child)
  t.hint = t:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  t.hint:SetPoint("BOTTOMLEFT", 4, 6)
  t.hint:SetWidth(PAGE_W - 8)
  t.hint:SetJustifyH("LEFT")
  t.hint:SetText(L.ALTS_HINT)
  t.rows = {}

  t.Refresh = function()
    local me = OwnRecord()
    t.header:SetText(L.ALTS_HEADER:format(ns.PoolText(me)))
    local data = ns.AltRows(KeepOrSellDB.characters, KeepOrSellDB.recipeProfession, KeepOrSellDB.altSettings, me)
    for key in pairs(widgets) do
      if key:match("^alt") then widgets[key] = nil end
    end
    local on = KeepOrSellDB.accountMode == true
    for i, alt in ipairs(data) do
      local row = t.rows[i] or AltRow(child, i)
      t.rows[i] = row
      row.key = alt.key
      row.name:SetText(ClassName(alt.name, alt.class))
      ShowProfessions(row, alt)
      for _, column in ipairs(ALT_COLUMNS) do
        local box = row.checks[column.field]
        box:SetChecked(alt[column.field])
        box:SetEnabled(on)
        widgets["alt:" .. alt.key .. ":" .. column.field] = box
      end
      row:SetAlpha(alt.included and 1 or DIM)
      row:Show()
      widgets["altrow:" .. alt.key] = row
      widgets["altname:" .. alt.key] = row.name
    end
    for i = #data + 1, #t.rows do t.rows[i]:Hide() end
    child:SetHeight(math.max(ROW_H, #data * ROW_H))
    local bar = t.scroll.ScrollBar
    if type(bar) == "table" and bar.SetShown then bar:SetShown(#data * ROW_H > t.height + ROWS_Y - 34) end
    t:SetAlpha(on and 1 or DIM)
  end
  altTable = t
  return 0
end

-- The numbers the layout rests on (tests)
function ns.OptionsLayout()
  return {pageWidth = PAGE_W, pageHeight = PAGE_H, columnTop = COLUMN_TOP,
    altRowWidth = NAME_W + PROF_W + 8 + #ALT_COLUMNS * CHECK_W, altScrollWidth = SCROLL_W}
end

-- Pages and sidebar --------------------------------------------------------------------------------------------

local BUILDERS = {checkbox = Checkbox, slider = Slider, button = ActionButton, dependencies = Dependencies,
  alts = AltTable}

local function BuildPage(parent, section)
  -- a fixed size, so the heading's divider knows its width before the window was ever shown
  local page = CreateFrame("Frame", nil, parent)
  page:SetSize(PAGE_W, PAGE_H)
  page:SetPoint("TOPLEFT", MARGIN, -MARGIN)
  Style.Heading(page, L[section.label], 20, 0)
  for i, controls in ipairs(section.columns) do
    local column = CreateFrame("Frame", nil, page)
    column:SetSize(COLUMN_W, PAGE_H - COLUMN_TOP)
    column:SetPoint("TOPLEFT", (i - 1) * (COLUMN_W + MARGIN), -COLUMN_TOP)
    local y = 0
    for _, control in ipairs(controls) do
      y = y - BUILDERS[control.kind](column, control, y)
    end
  end
  page:Hide()
  return page
end

local function Select(id)
  if not pages[id] then id = ns.OPTION_SECTIONS[1].id end
  KeepOrSellDB.optionsSection = id
  for key, page in pairs(pages) do page:SetShown(key == id) end
  for key, button in pairs(navButtons) do button.selected:SetShown(key == id) end
end

-- The sidebar has no room for "(Auctionator)": the page heading still names the addon. Pure.
function ns.NavLabel(text)
  return text:match("^(.-)%s*%(.*%)$") or text
end

local function NavButton(parent, section, index)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(NAV_W - 16, 30)
  button:SetPoint("TOPLEFT", 8, -8 - (index - 1) * 34)
  button.selected = button:CreateTexture(nil, "BACKGROUND")
  button.selected:SetAllPoints()
  button.selected:SetColorTexture(Style.GOLD[1], Style.GOLD[2], Style.GOLD[3], 0.25)
  button.selected:Hide()
  button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetSize(22, 22)
  icon:SetPoint("LEFT", 4, 0)
  icon:SetTexture(Style.ICONS .. section.icon)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local text = button:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  text:SetWidth(NAV_W - 50)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  text:SetText(ns.NavLabel(L[section.label]))
  widgets["nav:" .. section.id] = text
  button:SetScript("OnClick", function() Select(section.id) end)
  navButtons[section.id] = button
end

function ns.RefreshOptionsWindow()
  if not frame then return end
  for _, widget in pairs(widgets) do
    if widget.Refresh then widget.Refresh() end
  end
  if altTable then altTable.Refresh() end
end

local function CreateWindow()
  -- no portrait: it would reach into the sidebar's first entry
  frame = Style.Window(addonName .. "OptionsFrame", L.OPT_WINDOW_TITLE, WIDTH, HEIGHT, false)
  local nav = Style.Box(frame, 0.08, 0.7)
  nav:SetSize(NAV_W, PANEL_H)
  nav:SetPoint("TOPLEFT", MARGIN, PANEL_TOP)
  local content = Style.Box(frame, 0.08, 0.7)
  content:SetSize(CONTENT_W, PANEL_H)
  content:SetPoint("TOPRIGHT", -MARGIN, PANEL_TOP)
  for i, section in ipairs(ns.OPTION_SECTIONS) do
    NavButton(nav, section, i)
    pages[section.id] = BuildPage(content, section)
  end
  frame:SetScript("OnShow", ns.RefreshOptionsWindow)
end

-- Opens the window, on the given section or the one shown last
function ns.ShowOptionsWindow(id)
  if not frame then CreateWindow() end
  Select(id or KeepOrSellDB.optionsSection)
  frame:Show()
  ns.RefreshOptionsWindow()
end

function ns.ToggleOptionsWindow()
  if frame and frame:IsShown() then frame:Hide() else ns.ShowOptionsWindow() end
end
