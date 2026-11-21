"""Find the WoW game folders (e.g. _forever_, _classic_era_) where the addon is installed.

A game folder is the one that contains Interface/AddOns/WallOfShameForever and WTF.
Tried in order: config wow_path, running WoW process, the companion's own location, the
platform's install locations (Windows: Blizzard registry key), the usual install folders.
"""

import os
import re

import appinfo
import osplat

ADDON_TOC = os.path.join("Interface", "AddOns", "WallOfShameForever", "WallOfShameForever.toc")


def addon_version(game_dirs):
    """Version of the installed addon (## Version: of its .toc), the highest of the game folders,
    or "" when none can be read."""
    found = []
    for game_dir in game_dirs or []:
        try:
            with open(os.path.join(game_dir, ADDON_TOC), encoding="utf-8", errors="replace") as f:
                m = re.search(r"^##\s*Version:\s*v?(\d+\.\d+\.\d+)", f.read(), re.MULTILINE)
        except OSError:
            continue
        if m:
            found.append(m.group(1))
    return max(found, key=lambda v: tuple(map(int, v.split("."))), default="")


def version_header(game_dirs):
    """Sent with every request to the bot: the admins see who is behind (bot: versions.js)."""
    return {"X-WoS-Versions": f"companion={appinfo.VERSION}; addon={addon_version(game_dirs) or '?'}"}


def has_addon(game_dir):
    return os.path.isfile(os.path.join(game_dir, ADDON_TOC))


def game_dirs_in(root):
    """root itself when it is a game folder, else its game subfolders (_forever_, ...)."""
    if not root or not os.path.isdir(root):
        return []
    if has_addon(root):
        return [root]
    try:
        subdirs = [os.path.join(root, d) for d in os.listdir(root)]
    except OSError:
        return []
    return [d for d in subdirs if os.path.isdir(d) and has_addon(d)]


def wow_running():
    return osplat.wow_running()


def running_wow_dir():
    return osplat.running_wow_dir()


def own_location_dir(here):
    """When the companion sits somewhere inside a game folder (e.g. under Interface)."""
    path = here
    while True:
        if has_addon(path):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def find_game_dirs(configured, here):
    found, seen = [], set()

    def add(dirs):
        for d in dirs:
            d = os.path.abspath(d)
            if os.path.normcase(d) not in seen:
                seen.add(os.path.normcase(d))
                found.append(d)

    if configured:
        add(game_dirs_in(configured))
        return found  # explicit choice: nothing else
    add(game_dirs_in(running_wow_dir()))
    add(game_dirs_in(own_location_dir(here)))
    for root in osplat.install_roots():
        add(game_dirs_in(root))
    if not found:
        for root in osplat.fallback_roots():
            add(game_dirs_in(root))
    return found
