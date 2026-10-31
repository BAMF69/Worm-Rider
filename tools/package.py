#!/usr/bin/env python3
"""Assemble dist/WormRider (drop-in folder for the DuneAwakening game folder) and a release zip.

Needs the tested UE4SS runtime + Dune config archives (MIT) in third_party/ (see third_party/README.md).
"""
import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TP = ROOT / "third_party"
DIST = ROOT / "dist"
OUT = DIST / "WormRider"
VERSION = "0.1.0"

RUNTIME = TP / "UE4SS_v3.0.1-1164-g5e627997.zip"
RUNTIME_SHA = "3C72142A383E25E9F9553AC9E4D5677AA572E98CB369CAC57200EFB2E381E603"
CONFIGS = TP / "zCustomGameConfigs.zip"
CONFIGS_SHA = "1B2420B7DEB237CD680D27306EADF26628699D992A322C89A963D80F580C9B78"


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def crlf(src, dst):
    dst.write_bytes(src.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))


def main():
    subprocess.run([sys.executable, str(ROOT / "tools" / "build.py"), "generate"], check=True)
    for p, h in ((RUNTIME, RUNTIME_SHA), (CONFIGS, CONFIGS_SHA)):
        if sha(p) != h:
            sys.exit(f"checksum mismatch: {p.name}")
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    with zipfile.ZipFile(RUNTIME) as z:
        for info in z.infolist():
            name = info.filename
            if name == "dwmapi.dll" or (name.startswith("ue4ss/") and not name.startswith("ue4ss/Mods/")):
                z.extract(info, OUT)
    with zipfile.ZipFile(CONFIGS) as z:
        for info in z.infolist():
            if info.filename.startswith("DuneAwakening/") and info.filename.endswith(".ini"):
                (OUT / "ue4ss" / Path(info.filename).name).write_bytes(z.read(info))
    (OUT / "ue4ss" / "LICENSE").rename(OUT / "ue4ss" / "UE4SS-LICENSE.txt")

    mod = OUT / "Mods" / "WormRider" / "Scripts"
    mod.mkdir(parents=True)
    for f in ("main.lua", "sheets.lua"):
        shutil.copy(ROOT / "mod" / "WormRider" / "Scripts" / f, mod / f)
    (OUT / "Mods" / "mods.txt").write_text("WormRider : 1\n")

    for f in ("Play Worm Rider.bat", "Remove Loader.bat", "Play-WormRider.ps1"):
        crlf(ROOT / "launcher" / f, OUT / f)
    for f in ("README.txt", "CREDITS.txt"):
        crlf(ROOT / f, OUT / f)
    crlf(ROOT / "LICENSE", OUT / "LICENSE.txt")

    zpath = DIST / f"WormRider-{VERSION}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(OUT.rglob("*")):
            z.write(p, p.relative_to(DIST))
    print(f"packaged {OUT.relative_to(ROOT)} and {zpath.relative_to(ROOT)} ({zpath.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
