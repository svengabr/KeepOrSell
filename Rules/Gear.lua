-- Which gear a class can never wear. Pure logic, no frames.
local _, ns = ...

local WEAPON, ARMOR = 2, 4 -- Enum.ItemClass

-- Enum.ItemWeaponSubclass
local AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H = 0, 1, 2, 3, 4, 5, 6, 7, 8
local STAFF, FIST, DAGGER, THROWN, CROSSBOW, WAND = 10, 13, 15, 16, 18, 19
-- Enum.ItemArmorSubclass
local LEATHER, MAIL, PLATE, SHIELD, LIBRAM, IDOL, TOTEM = 2, 3, 4, 6, 7, 8, 9

local function Set(...)
  local t = {}
  for i = 1, select("#", ...) do t[select(i, ...)] = true end
  return t
end

-- Everything a class can ever learn, including proficiencies trained later (mail at 40 etc.).
-- Generous on purpose: an item that might become wearable is kept.
local WEAPONS = {
  WARRIOR = Set(AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H, STAFF, FIST, DAGGER, THROWN, CROSSBOW),
  PALADIN = Set(AXE1H, AXE2H, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H),
  HUNTER = Set(AXE1H, AXE2H, BOW, GUN, POLEARM, SWORD1H, SWORD2H, STAFF, FIST, DAGGER, THROWN, CROSSBOW),
  ROGUE = Set(AXE1H, BOW, GUN, MACE1H, SWORD1H, FIST, DAGGER, THROWN, CROSSBOW),
  PRIEST = Set(MACE1H, STAFF, DAGGER, WAND),
  SHAMAN = Set(AXE1H, AXE2H, MACE1H, MACE2H, STAFF, FIST, DAGGER),
  MAGE = Set(SWORD1H, STAFF, DAGGER, WAND),
  WARLOCK = Set(SWORD1H, STAFF, DAGGER, WAND),
  DRUID = Set(MACE1H, MACE2H, POLEARM, STAFF, FIST, DAGGER),
}

local ARMORS = {
  WARRIOR = Set(LEATHER, MAIL, PLATE, SHIELD),
  PALADIN = Set(LEATHER, MAIL, PLATE, SHIELD, LIBRAM),
  HUNTER = Set(LEATHER, MAIL),
  ROGUE = Set(LEATHER),
  PRIEST = Set(),
  SHAMAN = Set(LEATHER, MAIL, SHIELD, TOTEM),
  MAGE = Set(),
  WARLOCK = Set(),
  DRUID = Set(LEATHER, IDOL),
}

-- Armor subclasses that are restricted at all; cloth, generic (rings, necks, trinkets, off-hands) and
-- cosmetic items are wearable by everyone
local RESTRICTED_ARMOR = Set(LEATHER, MAIL, PLATE, SHIELD, LIBRAM, IDOL, TOTEM)
local RESTRICTED_WEAPONS = Set(AXE1H, AXE2H, BOW, GUN, MACE1H, MACE2H, POLEARM, SWORD1H, SWORD2H,
  STAFF, FIST, DAGGER, THROWN, CROSSBOW, WAND)

local POOR, COMMON = 0, 1 -- Enum.ItemQuality
local FISHING_POLE = 20
-- white or grey slots players keep for looks, not stats
local KEEP_SLOTS = Set("INVTYPE_BODY", "INVTYPE_TABARD")

-- true = grey or white weapon/armor that is only worth its vendor price (no shirts, tabards, fishing poles)
function ns.IsPlainGear(quality, classID, subclassID, equipLoc)
  if quality ~= POOR and quality ~= COMMON then return false end
  if classID ~= WEAPON and classID ~= ARMOR then return false end
  if KEEP_SLOTS[equipLoc] then return false end
  if classID == WEAPON and subclassID == FISHING_POLE then return false end
  return true
end

-- Items a profession needs in the bags. They look like plain or unusable weapons, so they are listed by ID.
local PROFESSION_TOOLS = Set(
  2901, 5956, 7005, 6219, 10498, -- Mining Pick, Blacksmith Hammer, Skinning Knife, Arclight Spanner, Gyromatic Micro-Adjustor
  6218, 6339, 11130, 11145, 16207, -- runed enchanting rods (copper to arcanite)
  22461, 22462, 22463, 44452, -- runed enchanting rods (fel iron to titanium)
  9149, 12709, 19901, 20723, -- Philosopher's Stone, Pip's Skinner, Zulian Slicer, Brann's Trusty Pick
  20815, 40772, 40892, 40893 -- Jeweler's Kit, Gnomish Army Knife, Hammer Pick, Bladed Pickaxe
)

-- true = a profession tool that must never be sold
function ns.IsProfessionTool(itemID)
  return itemID ~= nil and PROFESSION_TOOLS[itemID] == true
end

-- Spell reagents and class tools by class. Some come from class quests, so QuestieDB sees them as
-- handed-out quest items; others drop or are worth auctioning, but the class needs them all the same.
local CLASS_ITEMS = {
  DRUID = Set(17021, 17026, 17034, 17035, 17036, 17037, 17038), -- Wild Berries, Wild Thornroot, Rebirth seeds
  MAGE = Set(17020, 17031, 17032, 17056), -- Arcane Powder, Rune of Teleportation, Rune of Portals, Light Feather
  PALADIN = Set(17033, 21177), -- Symbol of Divinity, Symbol of Kings
  PRIEST = Set(17028, 17029, 17056), -- Holy Candle, Sacred Candle, Light Feather
  ROGUE = Set(
    5060, 5140, 5530, -- Thieves' Tools, Flash Powder, Blinding Powder
    6947, 6949, 6950, 8926, 8927, 8928, -- Instant Poison I-VI
    2892, 2893, 8984, 8985, 20844, -- Deadly Poison I-V
    3775, 3776, 5237, 6951, 9186, -- Crippling Poison I-II, Mind-numbing Poison I-III
    10918, 10920, 10921, 10922, -- Wound Poison I-IV
    2928, 2930, 5173, 8923, 8924, -- poison reagents: Dust of Decay, Essence of Pain, Deathweed, Essence of Agony,
    3371, 3372, 8925 -- Dust of Deterioration, and the Empty, Leaded and Crystal Vials
  ),
  SHAMAN = Set(5175, 5176, 5177, 5178, 17030), -- Earth, Fire, Water and Air Totem, Ankh
  WARLOCK = Set(6265, 5565, 16583), -- Soul Shard, Infernal Stone, Demonic Figurine
}

-- Vendor reagents that class spells no longer need with the legacy talent "Reagent Economy" (Forever).
-- Left out (checked in game): Rebirth still asks for its seed, Slow Fall still for the Light Feather.
local VENDOR_REAGENTS = Set(
  17021, 17026, -- Wild Berries, Wild Thornroot
  17020, 17031, 17032, -- Arcane Powder, Rune of Teleportation, Rune of Portals
  17033, 21177, 17028, 17029, -- Symbol of Divinity, Symbol of Kings, Holy Candle, Sacred Candle
  5140, 17030, 5565, 16583 -- Flash Powder, Ankh, Infernal Stone, Demonic Figurine
)

-- Spell ID of the legacy talent "Reagent Economy"
ns.REAGENT_ECONOMY_SPELL = 1225503

-- true = the player's class needs the item for its spells or abilities; it must never be sold.
-- reagentFree = the player has "Reagent Economy", so vendor reagents are no longer needed
function ns.IsClassItem(classFile, itemID, reagentFree)
  local items = classFile and CLASS_ITEMS[classFile]
  if items == nil or itemID == nil or items[itemID] ~= true then return false end
  return not (reagentFree and VENDOR_REAGENTS[itemID])
end

-- true = the player has learned "Reagent Economy"
function ns.HasReagentEconomy()
  return C_SpellBook ~= nil and C_SpellBook.IsSpellKnown ~= nil
    and C_SpellBook.IsSpellKnown(ns.REAGENT_ECONOMY_SPELL) == true
end

-- true = this class can never wear the item; false otherwise, also for unknown classes and subclasses
function ns.IsUnusableGear(classFile, classID, subclassID, equipLoc)
  if equipLoc == "INVTYPE_CLOAK" then return false end
  if classID == WEAPON and RESTRICTED_WEAPONS[subclassID] then
    local allowed = WEAPONS[classFile]
    return allowed ~= nil and not allowed[subclassID]
  end
  if classID == ARMOR and RESTRICTED_ARMOR[subclassID] then
    local allowed = ARMORS[classFile]
    return allowed ~= nil and not allowed[subclassID]
  end
  return false
end
