"""Updates of the companion from the GitHub Releases of the repository (like the TrollDiscord tray:
the menu says an update is there, one click installs it).

- check: the releases tagged companion-vX.Y.Z (the addon's vX.Y.Z releases are ignored), 30 s
  after start, then every 6 hours, or at once with "Check for updates". Only the menu changes.
- install (a click): downloads the file for this system next to the data (update/), then starts
  it with --quiet-update. The existing install step does the rest (platform_*.install): it stops
  this instance, replaces the installed copy and starts it.
  Windows: WallOfShameCompanion.exe; macOS: the .app inside WallOfShameCompanion.dmg (Apple
  Silicon) or WallOfShameCompanion-Intel.dmg (Intel), copied out with hdiutil and ditto.
- never from the sources; every failure goes to the log and leaves the companion as it is.
"""

import hashlib
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

import requests

from appinfo import APP, VERSION

REPO = "Alencruser/wall-of-shame-forever"
RELEASES_URL = f"https://api.github.com/repos/{REPO}/releases?per_page=30"
TAG_PREFIX = "companion-v"
FIRST_CHECK = 30            # seconds after start
CHECK_INTERVAL = 6 * 3600   # then this often (GitHub allows 60 requests an hour without a token)
TIMEOUT = 15
QUIET_FLAG = "--quiet-update"  # the downloaded copy installs itself without a message box

FROZEN = getattr(sys, "frozen", False)
TAG_RE = re.compile(r"^" + re.escape(TAG_PREFIX) + r"(\d+)\.(\d+)\.(\d+)$")

# For the tray menu (app.py). state: idle, checking, uptodate, available, downloading,
# installing, failed (check failed), error (install failed)
STATUS = {"state": "idle", "version": "", "progress": 0, "manual": False}

_lock = threading.Lock()
_release = None   # the newer release found by the last check
_log = print
_on_change = None  # called when STATUS changes (menu refresh, notification)
_data_dir = None


# --- Pure logic (tests/test_updater.py) -----------------------------------------------------------

def parse_version(text):
    """(0, 4, 1) from "companion-v0.4.1" or "0.4.1", None for anything else (addon tags v0.4.3...)."""
    text = (text or "").strip()
    if not text.startswith(TAG_PREFIX):
        text = TAG_PREFIX + text
    m = TAG_RE.match(text)
    return tuple(int(n) for n in m.groups()) if m else None


def is_newer(remote, local=None):
    r, l = parse_version(remote), parse_version(local or VERSION)
    return bool(r and l and r > l)


def pick_release(releases):
    """The published companion release with the highest version, or None."""
    best, best_version = None, None
    for rel in releases or []:
        if not isinstance(rel, dict) or rel.get("draft") or rel.get("prerelease"):
            continue
        tag = str(rel.get("tag_name") or "")
        version = parse_version(tag) if tag.startswith(TAG_PREFIX) else None
        if version and (best_version is None or version > best_version):
            best, best_version = rel, version
    return best


def asset_name(system=None, machine=None):
    """File of a release for this system: the names given by build.py and the workflow."""
    system = system or sys.platform
    machine = (machine or platform.machine()).lower()
    if system == "darwin":
        return APP + ("-Intel" if machine in ("x86_64", "amd64", "i386") else "") + ".dmg"
    if system.startswith("win"):
        return APP + ".exe"
    return None


def pick_asset(release, system=None, machine=None):
    name = asset_name(system, machine)
    for asset in (release or {}).get("assets") or []:
        if isinstance(asset, dict) and asset.get("name") == name and asset.get("browser_download_url"):
            return asset
    return None


def release_version(release):
    v = parse_version((release or {}).get("tag_name", ""))
    return ".".join(map(str, v)) if v else "?"


# --- Check ----------------------------------------------------------------------------------------

def _set(**values):
    STATUS.update(values)
    if _on_change:
        try:
            _on_change()
        except Exception:
            pass


def _headers():
    return {"Accept": "application/vnd.github+json", "User-Agent": f"{APP}/{VERSION}"}


def check(manual=False):
    """Looks for a newer release. Returns the new STATUS state."""
    global _release
    with _lock:
        if STATUS["state"] in ("checking", "downloading", "installing"):
            return STATUS["state"]
        previous = dict(STATUS)
        _set(state="checking", manual=manual)
    try:
        r = requests.get(RELEASES_URL, headers=_headers(), timeout=TIMEOUT)
        r.raise_for_status()
        release = pick_release(r.json())
        if release and is_newer(release["tag_name"]) and pick_asset(release):
            _release = release
            _set(state="available", version=release_version(release))
            _log(f"update: version {STATUS['version']} available")
        else:
            _release = None
            # the background check stays out of the menu when there is nothing new
            _set(state="uptodate" if manual else "idle", version=VERSION)
            if manual:
                _log("update: up to date")
    except Exception as e:
        _log(f"update: check failed: {e!r}")
        if manual:
            _set(state="failed", version="")
        else:  # a background failure keeps what the menu showed
            _set(**previous)
    return STATUS["state"]


def menu_text():
    """Line of the tray menu, or "" when there is nothing to say."""
    s, v = STATUS["state"], STATUS["version"]
    return {
        "checking": "Checking for updates...",
        "uptodate": f"Up to date (v{VERSION})",
        "available": f"Update v{v} available - click to install",
        "downloading": f"Downloading update v{v}... {STATUS['progress']}%",
        "installing": f"Installing update v{v}...",
        "failed": "Update check failed (see log)",
        "error": f"Update v{v} failed - click to retry (see log)",
    }.get(s, "")


def clickable():
    return STATUS["state"] in ("available", "error")


# --- Install --------------------------------------------------------------------------------------

def _update_dir():
    return os.path.join(_data_dir, "update")


def _download(asset, path):
    """Downloads asset to path (through a .part file), checks size and sha256 when GitHub gives it."""
    part = path + ".part"
    total = int(asset.get("size") or 0)
    digest = hashlib.sha256()
    done = 0
    with requests.get(asset["browser_download_url"], headers={"User-Agent": f"{APP}/{VERSION}"},
                      stream=True, timeout=TIMEOUT) as r:
        r.raise_for_status()
        with open(part, "wb") as f:
            for chunk in r.iter_content(256 * 1024):
                f.write(chunk)
                digest.update(chunk)
                done += len(chunk)
                if total:
                    percent = min(99, done * 100 // total)
                    if percent != STATUS["progress"]:
                        _set(progress=percent)
    if total and done != total:
        raise OSError(f"downloaded {done} bytes instead of {total}")
    expected = str(asset.get("digest") or "")
    if expected.startswith("sha256:") and expected[7:].lower() != digest.hexdigest():
        raise OSError("sha256 does not match the release")
    os.replace(part, path)


def _start_windows(exe):
    """The downloaded .exe installs itself over the installed one (platform_win.install)."""
    subprocess.Popen([exe, QUIET_FLAG], cwd=os.path.dirname(exe),
                     creationflags=0x00000008, close_fds=True)  # DETACHED_PROCESS


def _start_mac(dmg):
    """Copies the .app out of the .dmg, then opens it: it installs itself (platform_mac.install)."""
    staged = os.path.join(os.path.dirname(dmg), APP + ".app")
    shutil.rmtree(staged, ignore_errors=True)
    mount = tempfile.mkdtemp(prefix="wos-update-")
    subprocess.run(["hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount, dmg],
                   check=True, capture_output=True, timeout=120)
    try:
        source = os.path.join(mount, APP + ".app")
        if not os.path.isdir(source):
            raise OSError(f"{APP}.app is not in the .dmg")
        subprocess.run(["ditto", source, staged], check=True, capture_output=True, timeout=120)
    finally:
        subprocess.run(["hdiutil", "detach", mount, "-force"], capture_output=True, timeout=60)
        shutil.rmtree(mount, ignore_errors=True)
    if not os.path.exists(os.path.join(staged, "Contents", "MacOS", APP)):
        raise OSError("the copied .app is incomplete")
    subprocess.run(["xattr", "-dr", "com.apple.quarantine", staged], capture_output=True)
    subprocess.run(["open", "-n", staged, "--args", QUIET_FLAG], check=True, capture_output=True, timeout=60)


def install():
    """Downloads and starts the newer version (a click in the menu). Runs in its own thread."""
    with _lock:
        if not clickable() or not _release:
            return
        _set(state="downloading", progress=0)
    release = _release
    try:
        asset = pick_asset(release)
        if not asset:
            raise OSError(f"no {asset_name()} in {release.get('tag_name')}")
        folder = _update_dir()
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder, exist_ok=True)
        path = os.path.join(folder, asset["name"])
        _log(f"update: downloading {asset['name']} {STATUS['version']}")
        _download(asset, path)
        _set(state="installing", progress=100)
        _log(f"update: installing {STATUS['version']}, the companion restarts")
        if sys.platform == "darwin":
            _start_mac(path)
        else:
            _start_windows(path)
        # the new copy now asks this one to quit (osplat.watch_quit) and replaces it
    except Exception as e:
        _log(f"update: install failed: {e!r}")
        _set(state="error", progress=0)


def install_async():
    threading.Thread(target=install, daemon=True).start()


def check_async(manual=True):
    threading.Thread(target=check, args=(manual,), daemon=True).start()


# --- Background -----------------------------------------------------------------------------------

def _cleanup():
    """The files of the last update, once the new version runs. True if there were some."""
    folder = _update_dir()
    if not os.path.isdir(folder):
        return False
    shutil.rmtree(folder, ignore_errors=True)
    return True


def _loop(stop):
    if stop.wait(FIRST_CHECK):
        return
    try:
        if _cleanup():
            _log(f"update: now running v{VERSION}")
    except Exception as e:
        _log(f"update: cleanup failed: {e!r}")
    while True:
        check(manual=False)
        if stop.wait(CHECK_INTERVAL):
            return


def start(data_dir, log=print, on_change=None, stop=None):
    """Background checks (installed app only, never from the sources)."""
    global _log, _on_change, _data_dir
    _log, _on_change, _data_dir = log, on_change, data_dir
    if not FROZEN:
        return
    threading.Thread(target=_loop, args=(stop or threading.Event(),), daemon=True).start()
