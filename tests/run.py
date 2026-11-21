"""Run MouseoverMacros' offline tests in Lua 5.1 (same version as WoW) via lupa.

run.lua: the addon end to end in one session (a priest). baseline.lua: the class sets and automatic set-up,
each case in a fresh Lua state (a fresh login).

Usage: python -P tests/run.py
"""
import os
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")


def runtime():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
        lua.execute(f.read())
    return lua


def chunk(lua, name):
    with open(f"{ROOT}/tests/{name}", encoding="utf-8") as f:
        return lua.execute("return function(...) " + "local f = assert(loadstring(...)); return f end")(f.read())


def main() -> int:
    failures = chunk(runtime(), "run.lua")(ROOT)
    cases = chunk(runtime(), "baseline.lua")(ROOT, "list").split(",")
    passed = 0
    for case in cases:
        failed, ok = chunk(runtime(), "baseline.lua")(ROOT, case)
        failures += failed
        passed += ok
    print(f"\nbaseline: {passed} passed; {failures} failed in total")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
