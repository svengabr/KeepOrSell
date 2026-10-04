-- Texte; deDE überschreibt die englischen Standardtexte
local _, ns = ...

local L = {
  SET_QUEST = "Quest",
  SET_AH = "AuctionHouse",
  ON = "on",
  OFF = "off",
  OPEN = "open",
  DONE = "done",
  FACTOR_SET = "Auction house from %sx vendor price.",
  SCRAP_TOGGLED = "Cheap trade goods as Scrap junk: %s",
  SETS_TOGGLED = "Baganator sets: %s – takes effect after /reload.",
  STATUS = "%d quest objective items. Auction house from %sx vendor price (/kos factor 2), Scrap: %s (/kos scrap), sets: %s (/kos sets)",
}

if GetLocale and GetLocale() == "deDE" then
  L.SET_AH = "Auktionshaus"
  L.ON = "an"
  L.OFF = "aus"
  L.OPEN = "offen"
  L.DONE = "erfüllt"
  L.FACTOR_SET = "Auktionshaus ab %sx Händlerpreis."
  L.SCRAP_TOGGLED = "Billige Handwerkswaren als Scrap-Schrott: %s"
  L.SETS_TOGGLED = "Baganator-Sets: %s – wirkt nach /reload."
  L.STATUS = "%d Questziel-Items. Auktionshaus ab %sx Händlerpreis (/kos faktor 2), Scrap: %s (/kos scrap), Sets: %s (/kos sets)"
end

ns.L = L
