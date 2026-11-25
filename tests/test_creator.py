"""Tests for the creator line in unit tooltips (Creator.lua)."""
import unittest

from addon import load

STUBS = """
LINES, POSTCALLS, SCRIPTS, EVENTS, SECRET, RESTRICTED = {}, {}, {}, {}, {}, {}
function issecretvalue(value) return value ~= nil and SECRET[value] == true end
function issecrettable(value) return RESTRICTED[value] == true end
GUIDS = {}
function UnitGUID(unit) return GUIDS[unit] end
GameTooltip = {
  IsForbidden = function() return FORBIDDEN == true end,
  GetUnit = function() return "Ran", UNIT end,
  AddLine = function(self, text, r, g, b) table.insert(LINES, {text, r, g, b}) end,
  HookScript = function(self, script, fn) SCRIPTS[script] = fn end,
}
Enum = {TooltipDataType = {Unit = 2}}
TooltipDataProcessor = {AddTooltipPostCall = function(kind, fn) table.insert(POSTCALLS, {kind, fn}) end}
function CreateFrame()
  return {
    RegisterEvent = function(self, event) EVENTS[event] = true end,
    UnregisterEvent = function(self, event) EVENTS[event] = nil end,
    SetScript = function(self, script, fn)
      FIRE = function(event) if EVENTS[event] then fn(self, event) end end
    end,
  }
end
function SHOW(data) POSTCALLS[1][2](GameTooltip, data) return #LINES end
function CLEAR() LINES = {} SCRIPTS.OnTooltipCleared(GameTooltip) end
"""

OWN = "Player-6949-00219DC4"


class CreatorTests(unittest.TestCase):
    def setUp(self):
        self.rt, _ = load(("Creator.lua",), STUBS)
        self.hooks_at_load = self.rt.eval("#POSTCALLS")
        self.rt.execute("FIRE('PLAYER_ENTERING_WORLD')")
        self.rt.execute("FIRE('PLAYER_ENTERING_WORLD')")  # a loading screen

    def show(self, data):
        return self.rt.eval(f"SHOW({data})")

    def test_hooks_once_on_entering_the_world(self):
        self.assertEqual(self.hooks_at_load, 0)
        self.assertEqual(self.rt.eval("#POSTCALLS"), 1)
        self.assertEqual(self.rt.eval("POSTCALLS[1][1]"), 2)

    def test_marks_every_character_of_the_creator(self):
        for number in ("00219DC4", "0021AECE", "0021A0D8", "05E29238"):
            self.rt.execute("CLEAR()")
            self.assertEqual(self.show(f"{{guid = 'Player-6949-{number}'}}"), 1, number)
            self.assertEqual(list(self.rt.eval("LINES[1]").values()),
                             [r"|TInterface\AddOns\KeepOrSell\Icon:0|t KeepOrSell Creator", 0, 229 / 255, 1])

    def test_marks_a_tooltip_once_until_cleared(self):
        self.show(f"{{guid = '{OWN}'}}")
        self.assertEqual(self.show(f"{{guid = '{OWN}'}}"), 1)
        self.rt.execute("CLEAR()")
        self.assertEqual(self.show(f"{{guid = '{OWN}'}}"), 1)

    def test_leaves_everyone_else_alone(self):
        for data in ("{guid = 'Player-6949-00000000'}", "{guid = 'Player-5149-00219DC4'}", "{}", "nil"):
            self.assertEqual(self.show(data), 0, data)

    def test_asks_the_tooltip_unit_without_a_guid(self):
        self.rt.execute(f"UNIT = 'target' GUIDS.target = '{OWN}'")
        self.assertEqual(self.show("{}"), 1)

    def test_ignores_secret_and_restricted_data(self):
        self.rt.execute(f"SECRET['{OWN}'] = true")
        self.assertEqual(self.show(f"{{guid = '{OWN}'}}"), 0)
        self.rt.execute("BAD = setmetatable({}, {__index = function() error('restricted') end}) RESTRICTED[BAD] = true")
        self.assertEqual(self.show("BAD"), 0)

    def test_ignores_other_and_forbidden_tooltips(self):
        self.rt.execute(f"POSTCALLS[1][2]({{}}, {{guid = '{OWN}'}}) FORBIDDEN = true")
        self.assertEqual(self.show(f"{{guid = '{OWN}'}}"), 0)


if __name__ == "__main__":
    unittest.main()
