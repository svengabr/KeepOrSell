"""Tests for the pure description of the options window (OptionSections.lua)."""
import unittest

from addon import load

FILES = ("Locales.lua", "Prices.lua", "OptionSections.lua")

# every option the Blizzard settings page showed before the own window, plus the "? KoS" switch
OPTIONS = ["factor", "minProfit", "maxAge", "share", "scrap", "gear", "plainGear", "recipeJunk", "profession",
           "upcomingReagents", "questie", "disenchant", "openable", "keepClick", "accountMode", "tooltip", "hints",
           "helpButton", "destroy", "lootCoins", "lossWarnings", "bagValue", "setSource"]
REFRESH = {"factor", "minProfit", "maxAge", "share", "scrap", "gear", "plainGear", "recipeJunk", "profession", "upcomingReagents", "questie",
           "disenchant", "openable", "accountMode", "hints", "helpButton", "destroy", "bagValue"}
ACTIONS = {"ForgetKept", "ShowFilterWindow", "UndoFilterCommand", "ClearFilterCommand", "ShowSetup"}


class OptionSectionTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(FILES)

    def sections(self):
        return list(self.ns.OPTION_SECTIONS.values())

    def controls(self, section=None):
        sections = [section] if section else self.sections()
        return [c for s in sections for c in self.ns.SectionControls(s.id).values()]

    def by_key(self, key):
        return next(c for c in self.controls() if c.key == key)

    def test_every_option_exactly_once(self):
        keys = [c.key for c in self.controls() if c.key]
        self.assertEqual(sorted(keys), sorted(OPTIONS))

    def test_section_order(self):
        self.assertEqual([s.id for s in self.sections()], ["ah", "junk", "keep", "account", "filter", "display", "addons"])

    def test_section_controls_left_column_first(self):
        self.assertEqual([c.key for c in self.ns.SectionControls("junk").values()], ["scrap", "gear", "plainGear", "recipeJunk"])

    def test_slider_ranges_and_labels(self):
        factor, profit, age = self.by_key("factor"), self.by_key("minProfit"), self.by_key("maxAge")
        self.assertEqual((factor.min, factor.max, factor.step), (self.ns.MIN_FACTOR, 10, 0.1))
        self.assertEqual(factor.format(2), "2x")
        self.assertEqual((profit.min, profit.max, profit.step), (0, 100, 1))
        self.assertEqual((profit.format(0), profit.format(5)), ("off", "5 s"))
        self.assertEqual((age.min, age.max, age.step), (1, 21, 1))
        self.assertEqual((age.format(21), age.format(7)), ("off", "7 days"))

    def test_refresh_flags(self):
        for c in self.controls():
            if c.key:
                self.assertEqual(bool(c.refresh), c.key in REFRESH, c.key)

    def test_buttons_name_existing_actions(self):
        buttons = [c for c in self.controls() if c.kind == "button"]
        self.assertEqual(len(buttons), 6)
        for b in buttons:
            self.assertIn(b.action, ACTIONS)
        self.assertEqual(sorted(b.arg for b in buttons if b.arg), ["export", "import"])

    def test_profession_icons_in_english_and_german(self):
        icon = self.ns.ProfessionIcon
        self.assertEqual(icon("Tailoring"), "Interface\\Icons\\Trade_Tailoring")
        self.assertEqual(icon("Schneiderei"), "Interface\\Icons\\Trade_Tailoring")
        self.assertEqual(icon("Erste Hilfe"), icon("First Aid"))
        for name in ("Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism", "Leatherworking", "Mining",
                     "Skinning", "Tailoring", "Cooking", "First Aid", "Fishing", "Poisons", "Alchimie", "Schmiedekunst",
                     "Verzauberkunst", "Ingenieurskunst", "Kräuterkunde", "Lederverarbeitung", "Bergbau",
                     "Kürschnerei", "Kochkunst", "Angeln", "Gifte"):
            self.assertNotEqual(icon(name), icon("Unknown craft"), name)
        self.assertEqual(icon("Unknown craft"), "Interface\\Icons\\INV_Misc_QuestionMark")

    def test_professions_sorted_secondary_main_class(self):
        names = self.rt.table_from(["Schneiderei", "Gifte", "Kochkunst", "Erste Hilfe", "Verzauberkunst", "Angeln",
                                    "Arkane Schriften"])
        self.assertEqual(list(self.ns.SortProfessions(names).values()),
                         ["Kochkunst", "Erste Hilfe", "Angeln", "Schneiderei", "Verzauberkunst", "Arkane Schriften", "Gifte"])
        english = self.rt.table_from(["Tailoring", "Fishing", "Poisons", "Cooking", "Alchemy", "First Aid"])
        self.assertEqual(list(self.ns.SortProfessions(english).values()),
                         ["Cooking", "First Aid", "Fishing", "Alchemy", "Tailoring", "Poisons"])

    def test_profession_slots_always_show_the_secondary_ones(self):
        names = self.rt.table_from(["Schneiderei", "Angeln"])
        icons = self.rt.eval("{Angeln = 136245}")
        slots = [(s.name, s.learned, s.icon) for s in self.ns.ProfessionSlots(names, icons, "deDE").values()]
        self.assertEqual(slots, [("Kochkunst", False, "Interface\\Icons\\INV_Misc_Food_15"),
                                 ("Erste Hilfe", False, "Interface\\Icons\\Spell_Holy_SealOfSacrifice"),
                                 ("Angeln", True, 136245),
                                 ("Schneiderei", True, "Interface\\Icons\\Trade_Tailoring")])
        recorded = self.rt.eval("{Angeln = {icon = 136245, rank = 75, maxRank = 150}}")
        fishing = self.ns.ProfessionSlots(self.rt.table_from(["Angeln"]), recorded, "deDE")[3]
        self.assertEqual((fishing.icon, fishing.rank, fishing.maxRank), (136245, 75, 150))
        english = [s.name for s in self.ns.ProfessionSlots(self.rt.table_from([]), None, "enUS").values()]
        self.assertEqual(english, ["Cooking", "First Aid", "Fishing"])

    def test_special_rows(self):
        kinds = [c.kind for c in self.controls()]
        self.assertEqual((kinds.count("alts"), kinds.count("dependencies")), (1, 1))

    def texts(self, ns):
        for s in ns.OPTION_SECTIONS.values():
            yield s.label
            for c in ns.SectionControls(s.id).values():
                for field in ("label", "tip", "text"):
                    if c[field]:
                        yield c[field]

    def test_texts_exist_in_both_languages(self):
        _, de = load(FILES, "function GetLocale() return 'deDE' end")
        for key in self.texts(self.ns):
            self.assertIsNotNone(self.ns.L[key], key)
            self.assertIsNotNone(de.L[key], key)
        for key in ("OPT_WINDOW_TITLE", "OPT_WINDOW_OPEN", "OPT_WINDOW_OPEN_BUTTON", "OPT_WINDOW_OPEN_TIP", "ALTS_HEADER",
                    "ALTS_COL_CHARACTER", "ALTS_COL_PROFESSIONS", "ALTS_COL_PROFESSION", "ALTS_COL_CLASS",
                    "ALTS_COL_INCLUDED", "ALTS_NOT_LEARNED", "ALTS_YOU", "ALTS_HINT", "OPT_HELP_BUTTON", "OPT_HELP_BUTTON_TIP"):
            self.assertIsNotNone(self.ns.L[key], key)
            self.assertNotEqual(de.L[key], self.ns.L[key], key)


if __name__ == "__main__":
    unittest.main()
