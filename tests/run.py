#!/usr/bin/env python3
"""Run the headless Lua 5.4 play-through (needs: pip install lupa)."""
import sys
from pathlib import Path
import lupa.lua54 as lupa

root = Path(__file__).resolve().parent.parent
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
g = lua.globals()
g.TESTDIR = str(root / "tests")
g.MODDIR = str(root / "mod" / "WormRider" / "Scripts")
fails = lua.execute(f'return dofile("{root / "tests" / "scenario.lua"}")')
sys.exit(1 if fails else 0)
