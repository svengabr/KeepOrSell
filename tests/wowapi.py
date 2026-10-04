"""The WoW: Forever API as documented by Blizzard (tests/data/forever_api.json, see update_api.py),
plus a Lua runtime that rejects stubs of C_* functions or Enum values the client doesn't have."""
import json
from functools import lru_cache
from pathlib import Path

import lupa.lua51 as lua51

DATA = Path(__file__).resolve().parent / "data" / "forever_api.json"


# C_* functions missing from Blizzard's generated docs, each with the reason we may still use or stub it.
UNDOCUMENTED_FUNCTIONS = {
    "C_TradeSkillUI.GetFilteredRecipeIDs": "exists on Forever: called by Blizzard_ProfessionsTemplates/Blizzard_Professions.lua",
    "C_TradeSkillUI.GetAllRecipeIDs": "not on Forever; Professions.lua prefers it where present, else GetFilteredRecipeIDs",
}


@lru_cache(maxsize=None)
def api():
    return json.loads(DATA.read_text(encoding="utf-8"))


def is_function(name):
    return name in api()["functions"] or name in UNDOCUMENTED_FUNCTIONS


# Lists every C_* function and Enum value currently defined in the runtime's globals.
COLLECT = """
local functions, enums = {}, {}
for name, value in pairs(_G) do
  if type(name) == "string" and name:match("^C_") and type(value) == "table" then
    for key, fn in pairs(value) do
      if type(fn) == "function" then table.insert(functions, name .. "." .. key) end
    end
  end
end
if type(Enum) == "table" then
  for name, values in pairs(Enum) do
    if type(values) == "table" then
      for key, value in pairs(values) do table.insert(enums, {name, key, value}) end
    else
      table.insert(enums, {name})
    end
  end
end
return functions, enums
"""


def stub_errors(rt):
    """Stubs that don't match Forever: unknown C_* functions, unknown Enums or wrong Enum values."""
    doc = api()
    functions, enums = lua51.LuaRuntime.execute(rt, COLLECT)
    errors = [f"{name} is not a Forever API function" for name in functions.values() if not is_function(name)]
    for entry in enums.values():
        name = entry[1]
        if name not in doc["enums"]:
            errors.append(f"Enum.{name} does not exist on Forever")
        elif entry[2] is not None:
            key, value = entry[2], entry[3]
            if key not in doc["enums"][name]:
                errors.append(f"Enum.{name}.{key} does not exist on Forever")
            elif doc["enums"][name][key] != value:
                errors.append(f"Enum.{name}.{key} is {doc['enums'][name][key]} on Forever, stub says {value}")
    return sorted(errors)


class StubCheckError(AssertionError):
    pass


class CheckedRuntime(lua51.LuaRuntime):
    """LuaRuntime that checks the stubbed C_* / Enum globals against Forever after every execute()."""

    def execute(self, *args, **kwargs):
        result = super().execute(*args, **kwargs)
        errors = stub_errors(self)
        if errors:
            raise StubCheckError("stubs don't match the Forever API:\n  " + "\n  ".join(errors))
        return result


def runtime():
    return CheckedRuntime(unpack_returned_tuples=True)
