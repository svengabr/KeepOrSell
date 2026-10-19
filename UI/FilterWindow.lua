-- Shareable filters for the player: the export/import window, /kos export|import|rule|rules, and the actions
-- behind the filter buttons in the options (undo, clear). The text format and the rules live in Filter.lua.
local addonName, ns = ...
local L = ns.L

local PREFIX = "|cffffd200KeepOrSell:|r "
local GROUP_ORDER = {"keep", "profession", "ah", "disenchant", "junk"}
local CLEAR_POPUP = "KEEPORSELL_CLEAR_FILTER"

-- Sets or removes the item rule for itemID. word = a group of ns.FILTER_GROUPS or "clear" (any case).
-- Returns true, or false and "item" | "group". Pure.
function ns.FilterRuleCommand(db, itemID, word)
  if not itemID then return false, "item" end
  word = type(word) == "string" and word:lower() or ""
  if word ~= "clear" and not ns.FILTER_GROUPS[word] then return false, "group" end
  db.filter = db.filter or {}
  db.filter.items = db.filter.items or {}
  db.filter.items[itemID] = word ~= "clear" and word or nil
  return true
end

local PARSE_ERRORS = {noheader = "FILTER_ERR_NOHEADER", version = "FILTER_ERR_VERSION", toolong = "FILTER_ERR_TOOLONG"}

-- Parses text for the Check button: filter and the summary lines, or nil and the error text. Pure.
function ns.CheckFilterText(db, text)
  local filter, report = ns.ParseFilter(text)
  if not filter then return nil, L[PARSE_ERRORS[report] or "FILTER_ERR_NOHEADER"] end
  return filter, ns.FilterSummary(db, filter, report)
end

-- An open options panel keeps showing the old slider and checkbox values after an import changed them;
-- NotifyUpdate makes each setting read KeepOrSellDB again. A closed panel reads them when it opens.
local function RefreshOptionsPanel()
  if not (SettingsPanel and SettingsPanel:IsShown() and Settings and Settings.GetSetting) then return end
  for _, option in ipairs(ns.FILTER_OPTIONS) do
    local setting = Settings.GetSetting(addonName .. "_" .. option.key)
    if setting and setting.NotifyUpdate then setting:NotifyUpdate() end
  end
end

local function Changed()
  RefreshOptionsPanel()
  ns.SettingsChanged()
end

-- The filter name only ever goes in as an argument, never as a format string
local function FilterName(db)
  local name = db.filter and db.filter.name
  return type(name) == "string" and name ~= "" and name or nil
end

function ns.ApplyFilterCommand(filter)
  ns.ApplyFilter(KeepOrSellDB, filter)
  Changed()
  local name = FilterName(KeepOrSellDB)
  print(PREFIX .. (name and L.FILTER_APPLIED:format(name) or L.FILTER_APPLIED_UNNAMED))
end

function ns.UndoFilterCommand()
  if not ns.UndoFilter(KeepOrSellDB) then
    print(PREFIX .. L.FILTER_NO_UNDO)
    return
  end
  Changed()
  print(PREFIX .. L.FILTER_UNDONE)
end

local function ClearRules()
  ns.ClearFilterRules(KeepOrSellDB)
  Changed()
  print(PREFIX .. L.FILTER_CLEARED)
end

if StaticPopupDialogs then
  StaticPopupDialogs[CLEAR_POPUP] = {
    text = L.FILTER_CLEAR_CONFIRM,
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = ClearRules,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
  }
end

-- Asks first; the dialog's Yes clears the rules
function ns.ClearFilterCommand()
  if StaticPopup_Show then StaticPopup_Show(CLEAR_POPUP) end
end

-- "Trade Goods: Cloth quality 0-1", from the game's class names when known, else "class 7 subclass 5"
local function CategoryText(rule)
  local GetClass, GetSubClass = C_Item and C_Item.GetItemClassInfo, C_Item and C_Item.GetItemSubClassInfo
  local className = GetClass and GetClass(rule.class)
  local text
  if className then
    text = className
    if rule.subclass then
      local subName = GetSubClass and GetSubClass(rule.class, rule.subclass)
      text = text .. ": " .. (subName or ("subclass %d"):format(rule.subclass))
    end
  else
    text = ("class %d"):format(rule.class)
    if rule.subclass then text = text .. (" subclass %d"):format(rule.subclass) end
  end
  if rule.qmin and rule.qmax then
    local range = rule.qmin == rule.qmax and ("%d"):format(rule.qmin) or ("%d-%d"):format(rule.qmin, rule.qmax)
    text = text .. " " .. L.FILTER_QUALITY:format(range)
  end
  return text
end

function ns.PrintFilterRules()
  local filter = KeepOrSellDB.filter or {}
  local byGroup, any = {}, false
  for itemID, group in pairs(filter.items or {}) do
    if type(itemID) == "number" and ns.FILTER_GROUPS[group] then
      byGroup[group] = byGroup[group] or {}
      table.insert(byGroup[group], itemID)
      any = true
    end
  end
  local categories = filter.categories or {}
  if not any and #categories == 0 then
    print(PREFIX .. L.FILTER_RULES_EMPTY)
    return
  end
  local name = FilterName(KeepOrSellDB)
  print(PREFIX .. (name and L.FILTER_RULES_NAMED:format(name) or L.FILTER_RULES_HEADER))
  for _, group in ipairs(GROUP_ORDER) do
    local ids = byGroup[group]
    if ids then
      table.sort(ids)
      local links = {}
      for i, itemID in ipairs(ids) do links[i] = ns.ItemText(itemID) end
      print(L.FILTER_RULES_ITEMS:format(group, table.concat(links, " ")))
    end
  end
  for _, rule in ipairs(categories) do
    if type(rule.class) == "number" and ns.FILTER_GROUPS[rule.group] then
      print(L.FILTER_RULES_CATEGORY:format(CategoryText(rule), rule.group))
    end
  end
end

-- /kos rule <item link or ID> <group|clear>; the link may hold spaces, the group is the last word
local function RuleCommand(rest)
  local itemText, word = rest:match("^(.-)%s+(%S+)$")
  local itemID = ns.ItemIDFromText(itemText)
  local ok = itemID and ns.FilterRuleCommand(KeepOrSellDB, itemID, word)
  if not ok then
    print(PREFIX .. L.FILTER_RULE_USAGE)
    return
  end
  local group = KeepOrSellDB.filter.items[itemID]
  print(PREFIX .. (group and L.FILTER_RULE_SET:format(ns.ItemText(itemID), group)
    or L.FILTER_RULE_CLEARED:format(ns.ItemText(itemID))))
  ns.SettingsChanged()
  if GameTooltip and GameTooltip:IsShown() and GameTooltip.RefreshData then GameTooltip:RefreshData() end
end

-- /kos export|import|rule|rules; returns true when msg was one of these
function ns.HandleFilterCommand(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = cmd:lower()
  if cmd == "export" or cmd == "import" then
    ns.ShowFilterWindow(cmd)
  elseif cmd == "rule" then
    RuleCommand(rest)
  elseif cmd == "rules" then
    ns.PrintFilterRules()
  else
    return false
  end
  return true
end

-- Window -----------------------------------------------------------------------------------------------------
-- Blizzard templates only, like the setup window: ButtonFrameTemplate, a UIPanelScrollFrameTemplate around a
-- multi-line edit box, UIPanelButtonTemplate buttons.

local WIDTH, HEIGHT = 520, 440

local frame

local function SetSummary(text, r, g, b)
  frame.Summary:SetText(text or "")
  frame.Summary:SetTextColor(r or 1, g or 1, b or 1)
end

local function Check()
  local filter, result = ns.CheckFilterText(KeepOrSellDB, frame.Edit:GetText())
  frame.checked = filter
  if not filter then
    SetSummary(result, 1, 0.3, 0.1)
    frame.Apply:Disable()
    return
  end
  local lines = {}
  for i, line in ipairs(result) do lines[i] = line end
  SetSummary(#lines > 0 and table.concat(lines, "\n") or L.FILTER_CHECK_NOTHING, 1, 0.82, 0)
  frame.Apply:Enable()
end

local function Apply()
  if not frame.checked then return end
  ns.ApplyFilterCommand(frame.checked)
  frame:Hide()
end

local function Button(parent, text, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetText(text)
  button:SetSize(math.max(96, button:GetTextWidth() + 24), 22)
  button:SetScript("OnClick", onClick)
  return button
end

local function CreateFilterFrame()
  frame = CreateFrame("Frame", "KeepOrSellFilterFrame", UIParent, "ButtonFrameTemplate")
  frame:Hide()
  if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(frame) end
  if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(frame) end
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetFrameStrata("DIALOG") -- above the options panel it can be opened from
  frame:SetToplevel(true)
  frame:SetPoint("CENTER")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  table.insert(UISpecialFrames, "KeepOrSellFilterFrame") -- Esc closes it

  frame.Hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.Hint:SetPoint("TOPLEFT", 14, -30)
  frame.Hint:SetPoint("TOPRIGHT", -14, -30)
  frame.Hint:SetJustifyH("LEFT")

  -- the template's inset frames the text; the scroll bar sits inside its right edge
  local inset = frame.Inset
  if inset then
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 10, -46)
    inset:SetPoint("BOTTOMRIGHT", -10, 142)
  end
  local scroll = CreateFrame("ScrollFrame", "KeepOrSellFilterScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 18, -52)
  scroll:SetPoint("BOTTOMRIGHT", -34, 148)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetMaxLetters(0) -- unlimited: ParseFilter reports a text over 64 KB instead of the box cutting it
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(WIDTH - 60)
  edit:SetScript("OnEscapePressed", function() frame:Hide() end)
  -- keep the cursor in view while typing or pasting (Blizzard's helpers for scrolling edit boxes)
  if ScrollingEdit_OnCursorChanged then edit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged) end
  if ScrollingEdit_OnUpdate then
    edit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
  end
  -- a change after Check needs a new Check before Apply
  edit:SetScript("OnTextChanged", function(_, userInput)
    if userInput and frame.mode == "import" then
      frame.checked = nil
      frame.Apply:Disable()
      SetSummary(nil)
    end
  end)
  scroll:SetScrollChild(edit)
  -- a click anywhere in the box puts the cursor there
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
  frame.Edit = edit

  frame.Summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  frame.Summary:SetPoint("TOPLEFT", inset or scroll, "BOTTOMLEFT", 4, -8)
  frame.Summary:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  frame.Summary:SetJustifyH("LEFT")
  frame.Summary:SetJustifyV("TOP")
  -- room for about seven lines: up to four rule lines plus the option changes, which share one wrapping line
  frame.Summary:SetWordWrap(true)
  frame.Summary:SetNonSpaceWrap(true)
  frame.Summary:SetHeight(96)

  frame.Close = Button(frame, L.FILTER_CLOSE, function() frame:Hide() end)
  frame.Close:SetPoint("BOTTOMRIGHT", -14, 12)
  frame.Apply = Button(frame, L.FILTER_APPLY, Apply)
  frame.Apply:SetPoint("RIGHT", frame.Close, "LEFT", -6, 0)
  frame.Check = Button(frame, L.FILTER_CHECK, Check)
  frame.Check:SetPoint("RIGHT", frame.Apply, "LEFT", -6, 0)

  frame:SetScript("OnHide", function() frame.Edit:ClearFocus() end)
end

-- mode = "export": the current filter, selected for Ctrl+C; "import": an empty box with Check and Apply
function ns.ShowFilterWindow(mode)
  if not frame then CreateFilterFrame() end
  frame.mode = mode
  frame.checked = nil
  SetSummary(nil)
  local export = mode == "export"
  if frame.SetTitle then frame:SetTitle(export and L.FILTER_TITLE_EXPORT or L.FILTER_TITLE_IMPORT) end
  frame.Hint:SetText(export and L.FILTER_EXPORT_HINT or L.FILTER_IMPORT_HINT)
  frame.Check:SetShown(not export)
  frame.Apply:SetShown(not export)
  frame.Apply:Disable()
  local text = ""
  if export then
    local names = {
      item = C_Item.GetItemNameByID,
      class = function(classID, subclassID)
        if subclassID then return C_Item.GetItemSubClassInfo(classID, subclassID) end
        return C_Item.GetItemClassInfo(classID)
      end,
    }
    text = ns.SerializeFilter(KeepOrSellDB, names, true)
  end
  frame.Edit:SetText(text)
  frame:Show()
  frame.Edit:SetFocus()
  if export then frame.Edit:HighlightText() end
end
