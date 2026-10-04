"""Checks the addon source against the WoW: Forever API (tests/data/forever_api.json).

Catches calls to C_* functions, Enum values and events the client doesn't have, and forces every
global in .luacheckrc to be either documented or listed below with a reason.
Refresh the API data after a client patch: python tests/update_api.py
"""
import re
import unittest
from pathlib import Path

import lupa.lua51 as lua51

from wowapi import api, is_function

ROOT = Path(__file__).resolve().parent.parent
SOURCES = sorted(p for p in ROOT.glob("*.lua"))

# Globals from .luacheckrc that Blizzard's generated docs don't cover, and why they're fine.
NOT_IN_DOCS = {
    # SavedVariables, slash command and optional third-party addons
    "KeepOrSellDB": "our SavedVariables",
    "SLASH_KEEPORSELL1": "our slash command",
    "KeepOrSellDependencyMixin": "our mixin for the template in Options.xml",
    "Auctionator": "optional dependency, public API",
    "Baganator": "optional dependency, public API",
    "LibQuestieDB": "optional dependency (QuestieDB), public API in src/api.lua",
    "Scrap": "optional dependency, public API",
    # FrameXML (Lua/XML side of the client UI), not C API
    "CreateFrame": "core widget API, used throughout FrameXML",
    "GameTooltip": "FrameXML frame",
    "ItemRefTooltip": "FrameXML frame",
    "UIParent": "FrameXML frame",
    "SettingsPanel": "FrameXML frame (Blizzard_Settings)",
    "Settings": "FrameXML namespace (Blizzard_Settings)",
    "MinimalSliderWithSteppersMixin": "FrameXML mixin",
    "SettingsListElementMixin": "FrameXML mixin (Blizzard_Settings_Shared/Blizzard_SettingControls.lua)",
    "CreateSettingsListSectionHeaderInitializer": "FrameXML (Blizzard_Settings_Shared/Blizzard_SettingControls.lua)",
    "TooltipDataProcessor": "FrameXML (Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)",
    "ItemLocation": "FrameXML mixin factory (ItemLocation:CreateFromBagAndSlot)",
    "GetMoneyString": "FrameXML (Blizzard_SharedXML/FormattingUtil.lua)",
    "SlashCmdList": "FrameXML (Blizzard_ChatFrameBase)",
    "ITEM_SPELL_KNOWN": "GlobalStrings",
    "NUM_BAG_SLOTS": "FrameXML constant (Blizzard_FrameXMLBase/Constants.lua)",
    "Enum": "checked per value below",
    # Legacy global C functions without generated docs
    "GetProfessions": "legacy global, used by Blizzard_Professions on Forever",
    "hooksecurefunc": "core global for post-hooks, used throughout FrameXML",
    "GetProfessionInfo": "legacy global, used by Blizzard_Professions on Forever",
    "GetItemInfo": "fallback where C_Item.GetItemInfo is missing (always guarded)",
    "GetQuestLogTitle": "Classic quest log fallback, only used without C_QuestLog.GetInfo",
    "GetNumQuestLogEntries": "Classic quest log fallback, only used without C_QuestLog",
    "GetQuestLogLeaderBoard": "legacy global, used by Blizzard_ObjectiveTracker on Forever",
    "GetNumQuestLeaderBoards": "legacy global, used by Blizzard_ObjectiveTracker on Forever",
    "IsInGroup": "legacy global, used by Blizzard_FrameXMLUtil/PartyUtil and the unit frames on Forever",
    "IsInRaid": "legacy global, used by the raid frames on Forever",
    "GetNumGroupMembers": "legacy global, used by the party and raid frames on Forever",
    "InCombatLockdown": "legacy global, used throughout FrameXML for secure frames",
}


def code(path):
    """Source without comments, so commented-out or explained API names don't count."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"--\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def luacheck_globals():
    rt = lua51.LuaRuntime()
    rt.execute((ROOT / ".luacheckrc").read_text(encoding="utf-8"))
    g = rt.globals()
    return [*g.globals.values(), *g.read_globals.values()]


class ForeverApiTests(unittest.TestCase):
    def setUp(self):
        self.api = api()
        self.sources = {p.name: code(p) for p in SOURCES}

    def calls(self):
        """(file, 'C_Ns.Func') for direct calls and for locals aliasing a namespace (local api = C_Ns)."""
        found = set()
        for name, text in self.sources.items():
            for ns, fn in re.findall(r"\b(C_\w+)\.(\w+)", text):
                found.add((name, f"{ns}.{fn}"))
            for alias, ns in re.findall(r"\blocal\s+(\w+)\s*=\s*(C_\w+)(?![\w.:(])", text):
                for fn in re.findall(rf"\b{alias}[.:](\w+)", text):
                    found.add((name, f"{ns}.{fn}"))
        return sorted(found)

    def test_c_functions_exist(self):
        missing = [f"{f}: {call}" for f, call in self.calls() if not is_function(call)]
        self.assertEqual(missing, [], "C_* functions not on Forever (add to UNDOCUMENTED_FUNCTIONS with a reason "
                                      "if guarded or known to exist)")

    def test_enums_exist(self):
        enums = self.api["enums"]
        missing = []
        for name, text in self.sources.items():
            for enum, key in re.findall(r"\bEnum\.(\w+)(?:\.(\w+))?", text):
                if enum not in enums:
                    missing.append(f"{name}: Enum.{enum}")
                elif key and key not in enums[enum]:
                    missing.append(f"{name}: Enum.{enum}.{key}")
        self.assertEqual(missing, [])

    def test_events_exist(self):
        events = set(self.api["events"])
        used = set()
        for name, text in self.sources.items():
            for ev in re.findall(r'RegisterEvent\(\s*"(\w+)"', text) + re.findall(r'event\s*==\s*"(\w+)"', text):
                used.add((name, ev))
        self.assertTrue(used)
        self.assertEqual(sorted(f"{f}: {ev}" for f, ev in used if ev not in events), [])

    def test_luacheck_globals_are_known(self):
        functions = self.api["functions"]
        unknown = []
        for name in luacheck_globals():
            if name in NOT_IN_DOCS or name in functions:
                continue
            if name.startswith("C_") and any(f.startswith(name + ".") for f in functions):
                continue
            unknown.append(name)
        self.assertEqual(unknown, [], "global not in Forever docs: add to NOT_IN_DOCS with a reason")

    def test_not_in_docs_is_current(self):
        stale = [name for name in NOT_IN_DOCS if name not in luacheck_globals()]
        self.assertEqual(stale, [], "NOT_IN_DOCS lists globals .luacheckrc no longer has")

    def test_scanner_finds_calls(self):
        calls = {c for _, c in self.calls()}
        self.assertIn("C_Item.GetItemInfo", calls)
        self.assertIn("C_TradeSkillUI.GetRecipeSchematic", calls)  # via local alias


if __name__ == "__main__":
    unittest.main()
