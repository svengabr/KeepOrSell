-- Shareable filters: parses the readable text format players paste to share their setup.
-- Pure logic, no WoW frames. The text is data only: nothing is executed, and only whitelisted keys are read.
local _, ns = ...

local MAX_TEXT = 64 * 1024
local MAX_ITEMS = 1000
local MAX_CATEGORIES = 100
local MAX_KEEP = 2000
local MAX_NAME = 40
local MAX_IGNORED_LINES = 5
local MAX_ID = 999999999 -- sanity bound for item IDs
local MAX_CLASS = 99 -- sanity bound for class, subclass
local MAX_QUALITY = 9

ns.FILTER_GROUPS = {keep = true, profession = true, ah = true, disenchant = true, junk = true}

-- Options a filter may set, in display order. Numbers are clamped to min..max, toggles take on/off.
ns.FILTER_OPTIONS = {
  {key = "factor", kind = "number", min = ns.MIN_FACTOR, max = 10, decimals = 1},
  {key = "minProfit", kind = "number", min = 0, max = 100, decimals = 0},
  {key = "maxAge", kind = "number", min = 1, max = 21, decimals = 0},
  {key = "scrap", kind = "toggle"},
  {key = "profession", kind = "toggle"},
  {key = "gear", kind = "toggle"},
  {key = "plainGear", kind = "toggle"},
  {key = "recipeJunk", kind = "toggle"},
  {key = "questie", kind = "toggle"},
  {key = "disenchant", kind = "toggle"},
  {key = "openable", kind = "toggle"},
  {key = "upcomingReagents", kind = "toggle"},
  {key = "altReagents", kind = "toggle"},
}

local OPTION_BY_KEY = {}
for _, o in ipairs(ns.FILTER_OPTIONS) do OPTION_BY_KEY[o.key:lower()] = o end

local TOGGLE_VALUES = {on = true, ["true"] = true, ["1"] = true, off = false, ["false"] = false, ["0"] = false}

-- A whole number within 0..max from text, or nil.
local function ParseInt(text, max)
  if not text or not text:match("^%d+$") or #text > 10 then return nil end
  local n = tonumber(text)
  if n > max then return nil end
  return n
end

-- Removes every WoW escape sequence and control character, so a name printed in chat can't inject links or textures.
local function StripEscapes(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|T.-|t", ""):gsub("|K.-|k", ""):gsub("|H.-|h", "")
  text = text:gsub("|%a", ""):gsub("|", ""):gsub("%c", "")
  return (text:match("^%s*(.-)%s*$"))
end

-- Strips BOM, color codes and comments, trims.
local function CleanLine(line)
  line = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  line = line:gsub("#.*$", "")
  return (line:match("^%s*(.-)%s*$"))
end

-- Splits "class 7 subclass 5 quality 0-1" (lowercase, without "= group") into a rule, or nil if malformed.
local function ParseCategory(left)
  local class, rest = left:match("^class%s+(%d+)%s*(.*)$")
  class = ParseInt(class, MAX_CLASS)
  if not class then return nil end
  local rule = {class = class}
  local sub, rest2 = rest:match("^subclass%s+(%d+)%s*(.*)$")
  if sub then
    rule.subclass = ParseInt(sub, MAX_CLASS)
    if not rule.subclass then return nil end
    rest = rest2
  end
  local lo, hi, rest3 = rest:match("^quality%s+(%d+)%s*%-%s*(%d+)%s*(.*)$")
  if not lo then
    lo, rest3 = rest:match("^quality%s+(%d+)%s*(.*)$")
    hi = lo
  end
  if lo then
    rule.qmin, rule.qmax = ParseInt(lo, MAX_QUALITY), ParseInt(hi, MAX_QUALITY)
    if not rule.qmin or not rule.qmax or rule.qmin > rule.qmax then return nil end
    rest = rest3
  end
  if rest ~= "" then return nil end
  return rule
end

-- Parses filter text. Returns filter, report; or nil, "noheader" | "version" | "toolong".
function ns.ParseFilter(text)
  if type(text) ~= "string" then return nil, "noheader" end
  if #text > MAX_TEXT then return nil, "toolong" end
  text = text:gsub("^\239\187\191", ""):gsub("\r\n", "\n"):gsub("\r", "\n")

  local filter = {options = {}, keep = {}, items = {}, categories = {}}
  local report = {ignored = 0, ignoredLines = {}, truncated = false}
  local counts = {items = 0, keep = 0}
  local headerSeen = false

  local function ignore(lineNo)
    report.ignored = report.ignored + 1
    if #report.ignoredLines < MAX_IGNORED_LINES then report.ignoredLines[#report.ignoredLines + 1] = lineNo end
  end

  local lineNo, pos, len = 0, 1, #text
  while pos <= len + 1 do
    local nl = text:find("\n", pos, true)
    local raw = text:sub(pos, (nl or len + 1) - 1)
    pos = (nl or len + 1) + 1
    lineNo = lineNo + 1
    local line = CleanLine(raw)

    if not headerSeen then
      if line ~= "" then
        local version = line:lower():match("^keeporsell%s+filter%s+(%d+)$")
        if not version then return nil, "noheader" end
        if tonumber(version) > 1 then return nil, "version" end
        headerSeen = true
      end
    elseif line ~= "" then
      local lower = line:lower()
      local left, right = lower:match("^(.-)%s*=%s*(.-)$")
      local ok = false
      if left and left ~= "" then
        local itemID = left:match("^item%s+(%d+)$")
        if itemID then
          local id = ParseInt(itemID, MAX_ID)
          if id and id >= 1 and ns.FILTER_GROUPS[right] then
            ok = true
            if filter.items[id] == nil and counts.items >= MAX_ITEMS then
              report.truncated, ok = true, false
            else
              if filter.items[id] == nil then counts.items = counts.items + 1 end
              filter.items[id] = right
            end
          end
        elseif left:match("^class%s") then
          local rule = ParseCategory(left)
          if rule and ns.FILTER_GROUPS[right] then
            ok = true
            rule.group = right
            if #filter.categories >= MAX_CATEGORIES then
              report.truncated, ok = true, false
            else
              filter.categories[#filter.categories + 1] = rule
            end
          end
        elseif left == "name" then
          -- keep the original case, from the cleaned line
          local name = line:match("^[^=]*=%s*(.-)$")
          name = name and StripEscapes(name)
          if name and name ~= "" then
            filter.name = name:sub(1, MAX_NAME)
            ok = true
          end
        elseif left == "keep" then
          local ids, valid = {}, true
          for token in right:gmatch("[^,]+") do
            token = token:match("^%s*(.-)%s*$")
            if token ~= "" then
              local id = ParseInt(token, MAX_ID)
              if not id or id < 1 then valid = false break end
              ids[#ids + 1] = id
            end
          end
          if valid and #ids > 0 then
            ok = true
            for _, id in ipairs(ids) do
              if not filter.keep[id] then
                if counts.keep >= MAX_KEEP then
                  report.truncated = true
                else
                  counts.keep = counts.keep + 1
                  filter.keep[id] = true
                end
              end
            end
          end
        else
          local option = OPTION_BY_KEY[left]
          if option and option.kind == "number" then
            local n = right:match("^%-?%d+%.?%d*$") and tonumber(right)
            if n then
              local mult = 10 ^ option.decimals
              n = math.floor(n * mult + 0.5) / mult
              filter.options[option.key] = math.min(math.max(n, option.min), option.max)
              ok = true
            end
          elseif option then
            local v = TOGGLE_VALUES[right]
            if v ~= nil then
              filter.options[option.key] = v
              ok = true
            end
          end
        end
      end
      if not ok then ignore(lineNo) end
    end
  end

  if not headerSeen then return nil, "noheader" end
  return filter, report
end

local KEEP_PER_LINE = 20

-- A " # text" comment from a name, or "". Control characters would break the one-statement-per-line format.
local function Comment(text)
  if type(text) ~= "string" then return "" end
  text = text:gsub("%c", ""):match("^%s*(.-)%s*$")
  if text == "" then return "" end
  return "  # " .. text
end

-- Writes the filter text for a KeepOrSellDB-shaped table. names (optional) = {item = fn(id), class = fn(classID,
-- subclassID)} only feed the trailing comments. withKeep == false leaves the keep marks out (nil includes them).
function ns.SerializeFilter(db, names, withKeep)
  db = db or {}
  names = names or {}
  local filter = db.filter or {}
  local lines = {"KeepOrSell filter 1"}

  if type(filter.name) == "string" then
    local name = StripEscapes((filter.name:gsub("#", ""))):sub(1, MAX_NAME)
    if name ~= "" then lines[#lines + 1] = "name = " .. name end
  end

  for _, option in ipairs(ns.FILTER_OPTIONS) do
    local v = db[option.key]
    if option.kind == "number" and type(v) == "number" then
      lines[#lines + 1] = ("%s = %g"):format(option.key, v)
    elseif option.kind == "toggle" and type(v) == "boolean" then
      lines[#lines + 1] = ("%s = %s"):format(option.key, v and "on" or "off")
    end
  end

  if withKeep ~= false and type(db.keep) == "table" then
    local ids = {}
    for id, marked in pairs(db.keep) do
      if marked and type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    for first = 1, #ids, KEEP_PER_LINE do
      local chunk = {}
      for i = first, math.min(first + KEEP_PER_LINE - 1, #ids) do chunk[#chunk + 1] = ("%d"):format(ids[i]) end
      lines[#lines + 1] = "keep = " .. table.concat(chunk, ", ")
    end
  end

  local ids = {}
  for id, group in pairs(filter.items or {}) do
    if type(id) == "number" and ns.FILTER_GROUPS[group] then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local name = names.item and names.item(id)
    lines[#lines + 1] = ("item %d = %s%s"):format(id, filter.items[id], Comment(name))
  end

  for _, rule in ipairs(filter.categories or {}) do
    if type(rule.class) == "number" and ns.FILTER_GROUPS[rule.group] then
      local left = ("class %d"):format(rule.class)
      if rule.subclass then left = left .. (" subclass %d"):format(rule.subclass) end
      if rule.qmin and rule.qmax then
        left = left .. (rule.qmin == rule.qmax and " quality %d" or " quality %d-%d"):format(rule.qmin, rule.qmax)
      end
      local comment = ""
      if names.class then
        local className = names.class(rule.class)
        if className and rule.subclass then
          local subName = names.class(rule.class, rule.subclass)
          if subName then className = className .. ": " .. subName end
        end
        comment = Comment(className)
      end
      lines[#lines + 1] = ("%s = %s%s"):format(left, rule.group, comment)
    end
  end

  return table.concat(lines, "\n")
end
