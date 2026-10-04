"""Regenerates tests/data/forever_api.json from Blizzard's generated API documentation.

Source: Gethe/wow-ui-source, branch `forever` (WoW: Forever, the only client we test on),
folder Interface/AddOns/Blizzard_APIDocumentationGenerated. Run after a client patch:

    python tests/update_api.py
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import lupa.lua51 as lua51

REPO = "https://github.com/Gethe/wow-ui-source.git"
BRANCH = "forever"
DOCS = "Interface/AddOns/Blizzard_APIDocumentationGenerated"
OUT = Path(__file__).resolve().parent / "data" / "forever_api.json"


def git(*args, cwd=None):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def fetch(target):
    git("clone", "--depth", "1", "--branch", BRANCH, "--filter=blob:none", "--sparse", REPO, str(target))
    git("sparse-checkout", "set", DOCS, cwd=target)
    sha = subprocess.run(["git", "rev-parse", "HEAD"], cwd=target, check=True, capture_output=True, text=True)
    return sha.stdout.strip()


def names(fields):
    return [f["Name"] for f in fields.values()] if fields else []


def collect(folder):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    rt.execute("""
      DOC_TABLES = {}
      APIDocumentation = {}
      function APIDocumentation:AddDocumentationTable(t) table.insert(DOC_TABLES, t) end
      -- some files read Enum.X.Y / Constants.X.Y for default values; any value will do
      local any = setmetatable({}, {__index = function() return 0 end})
      setmetatable(_G, {__index = function() return setmetatable({}, {__index = function() return any end}) end})
    """)
    for path in sorted(folder.glob("*.lua")):
        rt.execute(path.read_text(encoding="utf-8"))
    tables = rt.globals().DOC_TABLES.values()

    functions, events, enums = {}, set(), {}
    for doc in tables:
        prefix = (doc["Namespace"] + ".") if doc["Namespace"] else ""
        for fn in (doc["Functions"] or {}).values():
            functions[prefix + fn["Name"]] = {"args": names(fn["Arguments"]), "returns": names(fn["Returns"])}
        for ev in (doc["Events"] or {}).values():
            events.add(ev["LiteralName"])
        for t in (doc["Tables"] or {}).values():
            if t["Type"] == "Enumeration":
                enums[t["Name"]] = {f["Name"]: f["EnumValue"] for f in (t["Fields"] or {}).values()}
    return {
        "functions": dict(sorted(functions.items())),
        "events": sorted(events),
        "enums": dict(sorted(enums.items())),
    }


def dump(data):
    """JSON with one function / event / enum per line, so a regeneration diffs readably."""
    out = ["{", f'"source": {json.dumps(data["source"])},']
    for i, key in enumerate(("functions", "events", "enums")):
        value = data[key]
        if isinstance(value, dict):
            rows = [f"{json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}" for k, v in value.items()]
            opening, closing = "{", "}"
        else:
            rows = [json.dumps(v, ensure_ascii=False) for v in value]
            opening, closing = "[", "]"
        out.append(f"{json.dumps(key)}: {opening}")
        out.append(",\n".join("  " + r for r in rows))
        out.append(closing + ("," if i < 2 else ""))
    out.append("}")
    return "\n".join(out) + "\n"


def main():
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / "wow-ui-source"
        sha = fetch(target)
        data = collect(target / DOCS)
    data = {"source": f"Gethe/wow-ui-source@{BRANCH} {sha}", **data}
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(dump(data), encoding="utf-8")
    print(f"{OUT.name}: {len(data['functions'])} functions, {len(data['events'])} events, "
          f"{len(data['enums'])} enums from {sha[:10]}")


if __name__ == "__main__":
    sys.exit(main())
