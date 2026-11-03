"""Builds dist/WallOfShameCompanion.exe: background app (no console), Bagarre Club icon.

.venv\\Scripts\\python build.py [output folder, default dist]
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "assets")
DIST = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(HERE, "dist")  # optional output folder
# a private build keeps its own work folder: nothing of the guild's code in the public one
WORK = os.path.join(HERE, "build-private" if os.environ.get("SWF_PRIVATE_BUILD") else "build")

# embedded.py holds a guild's code (build_private.py): never in a public build
if os.path.exists(os.path.join(HERE, "embedded.py")) and not os.environ.get("SWF_PRIVATE_BUILD"):
    sys.exit("embedded.py is there (left by a private build): delete it before a public build.")

subprocess.run([
    sys.executable, "-m", "PyInstaller", "--noconfirm", "--onefile", "--noconsole",
    "--name", "WallOfShameCompanion",
    "--icon", os.path.join(ASSETS, "icon.ico"),
    "--add-data", f"{os.path.join(ASSETS, 'icon.png')}{os.pathsep}assets",
    "--distpath", DIST,
    "--workpath", WORK,
    "--specpath", WORK,
    os.path.join(HERE, "app.py"),
], check=True)
print(os.path.join(DIST, "WallOfShameCompanion.exe"))
