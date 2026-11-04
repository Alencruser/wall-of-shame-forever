"""Builds the companion for the current system (PyInstaller cannot build for another one):

- Windows: dist/WallOfShameCompanion.exe, one file, no console
- macOS: dist/WallOfShameCompanion.app (menu bar app, no Dock icon) and
  dist/WallOfShameCompanion.dmg to share it (Apple Silicon), or WallOfShameCompanion-Intel.dmg
  when built on an Intel Mac

.venv\\Scripts\\python build.py [output folder, default dist]      (macOS: .venv/bin/python)
"""

import os
import platform
import plistlib
import shutil
import subprocess
import sys
import time

from appinfo import APP, BUNDLE_ID, VERSION

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
DIST = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "dist")  # optional output folder
# a private build keeps its own work folder: nothing of the guild's code in the public one
WORK = os.path.join(HERE, "build-private" if os.environ.get("SWF_PRIVATE_BUILD") else "build")
MAC = sys.platform == "darwin"

# embedded.py holds a guild's code (build_private.py): never in a public build
if os.path.exists(os.path.join(HERE, "embedded.py")) and not os.environ.get("SWF_PRIVATE_BUILD"):
    sys.exit("embedded.py is there (left by a private build): delete it before a public build.")


def mac_icon():
    """assets/icon.png as an .icns (macOS app icon)."""
    from PIL import Image
    os.makedirs(WORK, exist_ok=True)
    icns = os.path.join(WORK, "icon.icns")
    Image.open(os.path.join(ASSETS, "icon.png")).convert("RGBA").resize((512, 512)).save(icns)
    return icns


common = [
    sys.executable, "-m", "PyInstaller", "--noconfirm", "--name", APP,
    "--add-data", f"{os.path.join(ASSETS, 'icon.png')}{os.pathsep}assets",
    "--distpath", DIST, "--workpath", WORK, "--specpath", WORK,
]
if MAC:
    args = ["--windowed", "--icon", mac_icon(), "--osx-bundle-identifier", BUNDLE_ID]
else:
    args = ["--onefile", "--noconsole", "--icon", os.path.join(ASSETS, "icon.ico")]
subprocess.run(common + args + [os.path.join(HERE, "app.py")], check=True)

if not MAC:
    print(os.path.join(DIST, APP + ".exe"))
    sys.exit()

bundle = os.path.join(DIST, APP + ".app")
info = os.path.join(bundle, "Contents", "Info.plist")
with open(info, "rb") as f:
    plist = plistlib.load(f)
plist.update({
    "LSUIElement": True,  # menu bar only, no Dock icon
    "CFBundleDisplayName": "Wall of Shame Forever companion",
    "CFBundleShortVersionString": VERSION,
    "CFBundleVersion": VERSION,
})
with open(info, "wb") as f:
    plistlib.dump(plist, f)
# Info.plist changed: sign again (ad hoc, no Apple certificate), else Apple Silicon calls it damaged
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", bundle], check=True)
# A .app is a folder: it is shared as a disk image (.dmg), opened with a double click. It only
# holds the app, which copies itself to ~/Applications on first launch (platform_mac.install).
# Apple Silicon: WallOfShameCompanion.dmg; Intel Mac: WallOfShameCompanion-Intel.dmg
dmg = os.path.join(DIST, APP + ("-Intel" if platform.machine() == "x86_64" else "") + ".dmg")
stage = os.path.join(WORK, "dmg")
shutil.rmtree(stage, ignore_errors=True)
os.makedirs(stage)
shutil.copytree(bundle, os.path.join(stage, APP + ".app"), symlinks=True)  # symlinks: keeps the bundle intact
if os.path.exists(dmg):
    os.remove(dmg)
for attempt in range(3):  # hdiutil sometimes fails with "Resource busy" on build machines
    result = subprocess.run(["hdiutil", "create", "-volname", "Wall of Shame Forever", "-srcfolder", stage,
                             "-ov", "-format", "UDZO", dmg])
    if result.returncode == 0:
        break
    time.sleep(5)
else:
    sys.exit("hdiutil could not create the .dmg")
print(bundle)
print(dmg)
