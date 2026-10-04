-- Texte; deDE überschreibt die englischen Standardtexte
local _, ns = ...

local L = {
  SET_QUEST = "Quest Objective",
  SET_AH = "AuctionHouse",
  ON = "on",
  OFF = "off",
  OPEN = "open",
  DONE = "done",
  FACTOR_SET = "Auction house from %sx vendor price.",
  SCRAP_TOGGLED = "Cheap trade goods as Scrap junk: %s",
  SETS_TOGGLED = "Baganator sets: %s – takes effect after /reload.",
  STATUS = "%d quest objective items. Auction house from %sx vendor price (/kos factor 2), Scrap: %s (/kos scrap), sets: %s (/kos sets)",
  CAT_QUEST = "Quest",
  SETUP_DONE = "Baganator categories \"%s\" and \"%s\" created.",
  SETUP_FAILED = "Could not create the Baganator categories – please set them up by hand (see addon page).",
  SETUP_NO_BAGANATOR = "Baganator is not loaded.",
}

if GetLocale and GetLocale() == "deDE" then
  L.SET_QUEST = "Questziel"
  L.SET_AH = "Auktionshaus"
  L.ON = "an"
  L.OFF = "aus"
  L.OPEN = "offen"
  L.DONE = "erfüllt"
  L.FACTOR_SET = "Auktionshaus ab %sx Händlerpreis."
  L.SCRAP_TOGGLED = "Billige Handwerkswaren als Scrap-Schrott: %s"
  L.SETS_TOGGLED = "Baganator-Sets: %s – wirkt nach /reload."
  L.STATUS = "%d Questziel-Items. Auktionshaus ab %sx Händlerpreis (/kos faktor 2), Scrap: %s (/kos scrap), Sets: %s (/kos sets)"
  L.SETUP_DONE = "Baganator-Kategorien „%s“ und „%s“ angelegt."
  L.SETUP_FAILED = "Baganator-Kategorien konnten nicht angelegt werden – bitte von Hand einrichten (siehe Addon-Seite)."
  L.SETUP_NO_BAGANATOR = "Baganator ist nicht geladen."
end

ns.L = L
