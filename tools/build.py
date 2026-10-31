#!/usr/bin/env python3
"""Worm Rider sheet tooling.

  build.py preflight   lay every sheet over each other; list unfilled cells,
                       unresolved cross-sheet references and code references
                       that do not resolve to a sheet row. Exit 1 if any.
  build.py generate    preflight, then write mod/WormRider/Scripts/sheets.lua
                       (one Lua struct per row).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "sheets"
SCRIPTS = ROOT / "mod" / "WormRider" / "Scripts"
OUT = SCRIPTS / "sheets.lua"

# Key names the bundled UE4SS runtime exposes in its Lua Key table
# (checked against UE4SS.dll strings; single letters are always present).
UE4SS_KEYS = {"UP_ARROW", "DOWN_ARROW", "LEFT_ARROW", "RIGHT_ARROW", "SPACE",
              "SHIFT", "CONTROL", "PAGE_UP", "PAGE_DOWN", "F6", "F7", "F8", "HOME", "END"} | {chr(c) for c in range(ord("A"), ord("Z") + 1)}
# Unreal EKeys names used by APlayerController::IsInputKeyDown.
UE_KEYS = {"Up", "Down", "Left", "Right", "SpaceBar", "LeftShift", "LeftControl", "PageUp", "PageDown", "F6", "F7", "F8", "Home", "End"} | \
          {chr(c) for c in range(ord("A"), ord("Z") + 1)}

NULLABLE = {("hud", "text"), ("hud", "fields")}
TABLE_FOR = {"game_refs": "REF", "stages": "STAGE", "controls": "CTRL", "config": "CFG", "hud": "HUD", "pose_words": "POSEWORD", "anims": "ANIM", "assets": "ASSET", "bone_skip": "BONESKIP", "seat_bones": "SEAT"}


def load():
    return {p.stem: json.loads(p.read_text()) for p in sorted(SHEETS.glob("*.json"))}


def preflight(sheets):
    problems = []
    ids = {}
    for name, sheet in sheets.items():
        cols = sheet["columns"]
        seen = set()
        for i, row in enumerate(sheet["rows"]):
            rid = row.get("id", f"<row {i}>")
            if rid in seen:
                problems.append(f"{name}.{rid}: duplicate id")
            seen.add(rid)
            for c in cols:
                v = row.get(c)
                empty = v is None or (isinstance(v, str) and v.strip() == "") or (isinstance(v, list) and not v)
                if isinstance(v, bool): empty = False
                if empty and (name, c) not in NULLABLE:
                    problems.append(f"{name}.{rid}.{c}: unfilled")
            for c in row:
                if c not in cols:
                    problems.append(f"{name}.{rid}.{c}: column not declared in sheet")
        ids[name] = seen

    def ref(sheet, rid, col, target, value, extra=()):
        if value not in ids[target] and value not in extra:
            problems.append(f"{sheet}.{rid}.{col}: '{value}' does not resolve in {target}")

    for r in sheets["stages"]["rows"]:
        ref("stages", r["id"], "hud", "hud", r["hud"])
        ref("stages", r["id"], "next_ok", "stages", r["next_ok"])
        ref("stages", r["id"], "next_fail", "stages", r["next_fail"])
        ref("stages", r["id"], "timeout_cfg", "config", r["timeout_cfg"], ("none",))
        if r["worm_ai"] not in ("game", "released"):
            problems.append(f"stages.{r['id']}.worm_ai: must be game|released")
        if r["worm_driver"] not in ("none", "hold", "wild", "rider", "call"):
            problems.append(f"stages.{r['id']}.worm_driver: unknown driver {r['worm_driver']}")
    for r in sheets["controls"]["rows"]:
        for s in r["stages"]:
            ref("controls", r["id"], "stages", "stages", s)
        if r["ue4ss_key"] not in UE4SS_KEYS:
            problems.append(f"controls.{r['id']}.ue4ss_key: '{r['ue4ss_key']}' is not a UE4SS Key name")
        if r["alt_key"] != "none" and r["alt_key"] not in UE4SS_KEYS:
            problems.append(f"controls.{r['id']}.alt_key: '{r['alt_key']}' is not a UE4SS Key name")
        if r["ue_key"] not in UE_KEYS:
            problems.append(f"controls.{r['id']}.ue_key: '{r['ue_key']}' is not an Unreal key name")
        if r["input"] not in ("press", "hold"):
            problems.append(f"controls.{r['id']}.input: must be press|hold")
    colors = sheets["hud"]["colors"]
    for r in sheets["hud"]["rows"]:
        if r["color"] not in colors:
            problems.append(f"hud.{r['id']}.color: '{r['color']}' not in colors")
        tokens = set(re.findall(r"\{(\w+)\}", r["text"]))
        if tokens != set(r["fields"]):
            problems.append(f"hud.{r['id']}: text tokens {sorted(tokens)} != fields {sorted(r['fields'])}")
    for r in sheets["anims"]["rows"]:
        if not r["path"].startswith("/Game/") or "." not in r["path"].rsplit("/", 1)[1]:
            problems.append(f"anims.{r['id']}.path: not a /Game/... object path")
        for col in ("loop", "hold_end"):
            if not isinstance(r[col], bool):
                problems.append(f"anims.{r['id']}.{col}: must be true/false")
    for r in sheets["assets"]["rows"]:
        if not (r["path"].startswith("/Game/") or r["path"].startswith("/Engine/")) or "." not in r["path"].rsplit("/", 1)[1]:
            problems.append(f"assets.{r['id']}.path: not an object path")
    for r in sheets["config"]["rows"]:
        if not isinstance(r["value"], (int, float)):
            problems.append(f"config.{r['id']}.value: not a number")

    # Rows referenced by another sheet count as used.
    sheet_used = {n: set() for n in TABLE_FOR}
    for r in sheets["stages"]["rows"]:
        sheet_used["hud"].add(r["hud"])
        sheet_used["config"].add(r["timeout_cfg"])
        sheet_used["stages"].update([r["next_ok"], r["next_fail"]])

    # Code must only use rows that exist, and every row should be used.
    files = [p for p in SCRIPTS.glob("*.lua") if p.name != "sheets.lua"] + list((ROOT / "launcher").glob("*.ps1"))
    code = "\n".join(p.read_text() for p in files)
    for name, tbl in TABLE_FOR.items():
        code_used = set(re.findall(rf"\b{tbl}\.(\w+)", code))
        for u in sorted(code_used - ids[name]):
            problems.append(f"code uses {tbl}.{u} but {name} has no such row")
        used = code_used | sheet_used[name]
        if re.search(rf"pairs\({tbl}\)", code):  # code walks every row
            used |= ids[name]
        for unused in sorted(ids[name] - used):
            problems.append(f"{name}.{unused}: row is never used by the code (unimplemented)")
    return problems


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)  # JSON string escapes are valid Lua
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join(f"{k} = {lua(x)}" for k, x in v.items()) + "}"
    raise TypeError(v)


def generate(sheets):
    out = ["-- GENERATED by tools/build.py from sheets/*.json. Do not edit; change the sheet.", "local S = {}"]
    for name, tbl in TABLE_FOR.items():
        sheet = sheets[name]
        out.append(f"\n-- {name}: {sheet['about']}")
        out.append(f"S.{tbl} = {{}}")
        for row in sheet["rows"]:
            fields = ", ".join(f"{c} = {lua(row[c])}" for c in sheet["columns"])
            out.append(f"S.{tbl}.{row['id']} = {{ {fields} }}")
    out.append("\nS.COLORS = " + lua(sheets["hud"]["colors"]))
    out.append("\nreturn S\n")
    OUT.write_text("\n".join(out))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "preflight"
    sheets = load()
    problems = preflight(sheets)
    total = sum(len(s["rows"]) * len(s["columns"]) for s in sheets.values())
    if problems:
        print(f"PREFLIGHT FAILED: {len(problems)} problem(s) across {total} cells")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print(f"preflight clean: {len(sheets)} sheets, {sum(len(s['rows']) for s in sheets.values())} rows, {total} cells checked")
    if cmd == "generate":
        generate(sheets)
        print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
