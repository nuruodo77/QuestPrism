"""Run QuestPrism logic tests under Lua 5.1 with a WoW API mock."""
import os
import sys
import glob
from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)

# Files loaded for logic tests (TOC order, UI/AceGUI excluded)
CORE_FILES = [
    "Locales/enUS.lua",
    "QuestPrism.lua",
    "Core/Settings.lua",
    "Core/Filter.lua",
    "Core/Sources.lua",
    "Core/Rules.lua",
    "Sources/Zygor.lua",
    "Sources/RXP.lua",
    "Sources/BtWQuests.lua",
    "Hooks/WorldMap.lua",
    "Hooks/Minimap.lua",
    "Hooks/ObjectiveTracker.lua",
    "Hooks/WorldQuests.lua",
]


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def syntax_check_all():
    lua = LuaRuntime()
    loadstring = lua.globals().loadstring
    bad = 0
    for path in sorted(glob.glob(os.path.join(ADDON, "**", "*.lua"), recursive=True)):
        res = loadstring(read(path), "@" + os.path.relpath(path, ADDON))
        if isinstance(res, tuple):  # (nil, errmsg)
            bad += 1
            print("SYNTAX ERROR:", res[1])
    print(f"syntax check: {'OK' if bad == 0 else str(bad) + ' file(s) failed'}")
    return bad == 0


def fresh_runtime():
    lua = LuaRuntime()
    # Let tests load extra addon files (UI smoke tests)
    lua.globals().LOAD_ADDON_FILE = lambda rel: lua.execute(read(os.path.join(ADDON, rel)))
    lua.execute(read(os.path.join(HERE, "mock.lua")))
    for rel in CORE_FILES:
        path = os.path.join(ADDON, rel)
        if os.path.exists(path):
            lua.execute(read(path))
    return lua


def run_tests():
    passed = failed = 0
    for path in sorted(glob.glob(os.path.join(HERE, "test_*.lua"))):
        lua = fresh_runtime()
        lua.execute(read(os.path.join(HERE, "assert.lua")))
        try:
            lua.execute(read(path))
        except Exception as e:  # file-level error
            failed += 1
            print(f"FAIL {os.path.basename(path)}: {e}")
            continue
        results = lua.globals().TEST_RESULTS
        for i in range(1, len(results) + 1):
            r = results[i]
            if r.ok:
                passed += 1
            else:
                failed += 1
                print(f"FAIL {os.path.basename(path)} :: {r.name}: {r.err}")
    print(f"tests: {passed} passed, {failed} failed")
    return failed == 0


if __name__ == "__main__":
    ok = syntax_check_all()
    ok = run_tests() and ok
    sys.exit(0 if ok else 1)
