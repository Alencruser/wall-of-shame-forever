"""Find the WoW game folders (e.g. _forever_, _classic_era_) where the addon is installed.

A game folder is the one that contains Interface\\AddOns\\ShameWallForever and WTF.
Tried in order: config wow_path, running WoW process, the companion's own location,
the Blizzard registry key, the usual install folders on every drive.
"""

import ctypes
import os
import string
import winreg
from ctypes import wintypes

ADDON_TOC = os.path.join("Interface", "AddOns", "ShameWallForever", "ShameWallForever.toc")
REGISTRY_KEYS = [
    r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
    r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
]
COMMON_DIRS = [r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft",
               r"World of Warcraft", r"Games\World of Warcraft", r"Battle.net\World of Warcraft"]

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000


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
    return bool(user32.FindWindowW("GxWindowClass", None) or user32.FindWindowW(None, "World of Warcraft"))


def running_wow_dir():
    """Folder of the running WoW executable (Wow.exe sits in the game folder)."""
    hwnd = user32.FindWindowW("GxWindowClass", None) or user32.FindWindowW(None, "World of Warcraft")
    if not hwnd:
        return None
    pid = wintypes.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid.value)
    if not handle:
        return None
    try:
        buf, size = ctypes.create_unicode_buffer(1024), wintypes.DWORD(1024)
        if not kernel32.QueryFullProcessImageNameW(handle, 0, buf, ctypes.byref(size)):
            return None
        return os.path.dirname(buf.value)
    finally:
        kernel32.CloseHandle(handle)


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


def registry_roots():
    roots = []
    for key in REGISTRY_KEYS:
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key) as k:
                install = winreg.QueryValueEx(k, "InstallPath")[0].rstrip("\\/")
        except OSError:
            continue
        # InstallPath points to one game folder (e.g. _retail_): look at its siblings too
        roots += [install, os.path.dirname(install)]
    return roots


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
    for root in registry_roots():
        add(game_dirs_in(root))
    if not found:
        for drive in string.ascii_uppercase:
            for common in COMMON_DIRS:
                add(game_dirs_in(f"{drive}:\\{common}"))
    return found
