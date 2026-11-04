"""Builds the companion for the current system (PyInstaller cannot build for another one):

- Windows: dist/WallOfShameCompanion.exe, one file, no console
- macOS: dist/WallOfShameCompanion.app (menu bar app, no Dock icon) and
  dist/WallOfShameCompanion-mac-<arm64|x86_64>.zip to share it

.venv\\Scripts\\python build.py [output folder, default dist]      (macOS: .venv/bin/python)
"""

import os
import platform
import plistlib
import subprocess
import sys

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
archive = os.path.join(DIST, f"{APP}-mac-{platform.machine()}.zip")
if os.path.exists(archive):
    os.remove(archive)
subprocess.run(["ditto", "-c", "-k", "--keepParent", bundle, archive], check=True)  # keeps the bundle intact
print(bundle)
print(archive)
