"""Shared loader: runs addon files like the client does (addonName, ns), after WoW API stubs."""
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parent.parent

# itemID -> name, classID, subclassID, equipLoc, vendor price, quality
# 1 wolf flank (objective), 2 letter (quest item), 3 silk (worth auctioning), 4 linen (cheap),
# 5 mail chest, 6 sword, 7 leather chest, 8 mail cloak, 9 potion, 10 white staff, 11 white shirt
BASE_STUBS = """
function GetLocale() return "enUS" end
function UnitClass() return "Druid", PLAYER_CLASS or "DRUID" end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
ITEMS = {
  [1] = {"Lean Wolf Flank", 7, 8, "", 5},
  [2] = {"Sealed Letter", 12, 0, "", 0},
  [3] = {"Silk Cloth", 7, 5, "", 38},
  [4] = {"Linen Cloth", 7, 5, "", 13},
  [5] = {"Mail Vest", 4, 3, "INVTYPE_CHEST", 100, 2},
  [6] = {"Rusty Sword", 2, 7, "INVTYPE_WEAPON", 100, 2},
  [7] = {"Leather Vest", 4, 2, "INVTYPE_CHEST", 100, 2},
  [8] = {"Mail Cloak", 4, 3, "INVTYPE_CLOAK", 100, 2},
  [9] = {"Healing Potion", 0, 1, "", 40, 1},
  [10] = {"Wooden Staff", 2, 10, "INVTYPE_2HWEAPON", 50, 1},
  [11] = {"White Shirt", 4, 0, "INVTYPE_BODY", 5, 1},
}
BOUND = {}     -- itemID -> true when soulbound
AH = {}        -- link -> auction price
AGE = {}       -- link -> days since seen
C_Item = {
  GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id][1] end,
  GetItemInfoInstant = function(id)
    if type(id) == "string" then id = tonumber(id:match("%d+")) end
    local i = ITEMS[id]
    if not i then return nil end
    return id, nil, nil, i[4], nil, i[2], i[3]
  end,
  GetItemInfo = function(link)
    local id = type(link) == "string" and tonumber(link:match("%d+")) or link
    local i = ITEMS[id]
    if not i then return nil end
    return i[1], "link" .. id, i[6] or 1, nil, nil, nil, nil, nil, nil, nil, i[5], nil, nil, BOUND[id] and 1 or 2
  end,
}
Auctionator = {API = {v1 = {
  GetAuctionPriceByItemLink = function(caller, link) return AH[link] end,
  GetAuctionAgeByItemLink = function(caller, link) return AGE[link] or 0 end,
}}}
KeepOrSellDB = {factor = 2, minProfit = 0, maxAge = 7, scrap = true, gear = true, plainGear = true,
  profession = true, tooltip = true, ahVisited = true}
"""

CORE_FILES = ("Locales.lua", "Objectives.lua", "Prices.lua", "Gear.lua", "Professions.lua", "Classify.lua")


def load(files=CORE_FILES, stubs="", base=True):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    if base:
        rt.execute(BASE_STUBS)
    if stubs:
        rt.execute(stubs)
    ns = rt.eval("{}")
    run = rt.eval("function(path, ns) assert(loadfile(path))('KeepOrSell', ns) end")
    for f in files:
        run(str(ROOT / f).replace("\\", "/"), ns)
    return rt, ns
