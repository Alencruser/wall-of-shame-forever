"""Builds the addon zip for CurseForge, and can upload it.

companion\\.venv\\Scripts\\python release.py                    zip in release/
companion\\.venv\\Scripts\\python release.py --interface 16002   after a Forever patch (1.60.2)
companion\\.venv\\Scripts\\python release.py --version v0.1.1    new addon version
companion\\.venv\\Scripts\\python release.py --upload            zip, then upload to CurseForge

Upload: the CurseForge project must exist (created once on authors.curseforge.com) and its ID be in
the .toc (## X-Curse-Project-ID). The API token (authors.curseforge.com > API tokens) comes from the
CF_API_TOKEN environment variable or the .curseforge-token file next to this script (not in git).
The CurseForge game version is found from the .toc interface number (16001 -> "1.60.1").
"""

import argparse
import json
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = "WallOfShameForever"
TOC = os.path.join(HERE, ADDON, f"{ADDON}.toc")
CHANGELOG = os.path.join(HERE, ADDON, "CHANGELOG.md")
OUT_DIR = os.path.join(HERE, "release")
API = "https://wow.curseforge.com/api"


def read_toc():
    with open(TOC, encoding="utf-8") as f:
        return f.read()


def toc_field(text, name):
    m = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", text, re.M)
    return m.group(1) if m else None


def set_toc_field(name, value):
    text = read_toc()
    if toc_field(text, name) is None:
        sys.exit(f"## {name} is missing from the .toc")
    text = re.sub(rf"^## {re.escape(name)}:.*$", f"## {name}: {value}", text, count=1, flags=re.M)
    with open(TOC, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    print(f".toc: ## {name}: {value}")


def check_files(text):
    files = [line.strip() for line in text.splitlines() if line.strip() and not line.startswith("#")]
    missing = [f for f in files if not os.path.isfile(os.path.join(HERE, ADDON, f))]
    if missing:
        sys.exit(f"files listed in the .toc but missing: {', '.join(missing)}")


def build_zip(version):
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, f"{ADDON}-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for folder, _, files in os.walk(os.path.join(HERE, ADDON)):
            for name in sorted(files):
                path = os.path.join(folder, name)
                z.write(path, os.path.relpath(path, HERE).replace(os.sep, "/"))  # WallOfShameForever/...
    print(f"zip: {out} ({os.path.getsize(out) // 1024} KB)")
    return out


def changelog_for(version):
    """The section of CHANGELOG.md for this version, as release notes."""
    with open(CHANGELOG, encoding="utf-8") as f:
        text = f.read()
    m = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    return m.group(1).strip() if m else f"Wall of Shame Forever {version}"


def game_version_name(interface):
    """16001 -> 1.60.1 (major, two digits minor, two digits patch)."""
    s = str(interface)
    return f"{int(s[:-4])}.{int(s[-4:-2])}.{int(s[-2:])}"


def token():
    value = os.environ.get("CF_API_TOKEN")
    path = os.path.join(HERE, ".curseforge-token")
    if not value and os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            value = f.read().strip()
    if not value:
        sys.exit("No CurseForge API token: set CF_API_TOKEN or create .curseforge-token "
                 "(authors.curseforge.com > API tokens).")
    return value


def game_versions(session):
    r = session.get(f"{API}/game/versions", timeout=30)
    r.raise_for_status()
    return r.json()


def upload(path, version, interface, game_version_id=None, release_type="release"):
    import requests

    text = read_toc()
    project = toc_field(text, "X-Curse-Project-ID")
    if not project:
        sys.exit("Add the project ID to the .toc first: ## X-Curse-Project-ID: <id> "
                 "(shown on the project page on CurseForge).")
    session = requests.Session()
    session.headers["X-Api-Token"] = token()
    if not game_version_id:
        wanted = game_version_name(interface)
        matches = [v for v in game_versions(session) if v.get("name") == wanted]
        if not matches:
            sys.exit(f'No CurseForge game version named "{wanted}". See them with --list-versions, '
                     "then pass --game-version-id.")
        game_version_id = matches[0]["id"]
    metadata = {
        "changelog": changelog_for(version),
        "changelogType": "markdown",
        "displayName": f"Wall of Shame Forever {version}",
        "gameVersions": [int(game_version_id)],
        "releaseType": release_type,
    }
    with open(path, "rb") as f:
        r = session.post(f"{API}/projects/{project}/upload-file", timeout=120,
                         data={"metadata": json.dumps(metadata)},
                         files={"file": (os.path.basename(path), f, "application/zip")})
    if r.status_code >= 400:
        sys.exit(f"Upload refused ({r.status_code}): {r.text[:500]}")
    print(f"uploaded to CurseForge project {project}: file id {r.json().get('id')}, "
          f"game version {game_version_id}, {release_type}")


def main():
    parser = argparse.ArgumentParser(description="Wall of Shame Forever release")
    parser.add_argument("--interface", help="new ## Interface number, e.g. 16002 after the 1.60.2 patch")
    parser.add_argument("--version", help="new ## Version, e.g. v0.1.1")
    parser.add_argument("--upload", action="store_true", help="upload the zip to CurseForge")
    parser.add_argument("--game-version-id", help="CurseForge game version id, when not found by name")
    parser.add_argument("--release-type", default="release", choices=["release", "beta", "alpha"])
    parser.add_argument("--list-versions", action="store_true", help="list CurseForge WoW game versions")
    args = parser.parse_args()

    if args.list_versions:
        import requests
        session = requests.Session()
        session.headers["X-Api-Token"] = token()
        for v in game_versions(session):
            print(v.get("id"), v.get("name"), v.get("gameVersionTypeID"))
        return

    if args.interface:
        set_toc_field("Interface", args.interface)
    if args.version:
        set_toc_field("Version", args.version)
    text = read_toc()
    check_files(text)
    version, interface = toc_field(text, "Version"), toc_field(text, "Interface")
    print(f"Wall of Shame Forever {version}, interface {interface} (game {game_version_name(interface)})")
    path = build_zip(version)
    if args.upload:
        upload(path, version, interface, args.game_version_id, args.release_type)


if __name__ == "__main__":
    main()
