"""macOS layer of the companion (same functions as platform_win.py, used through osplat.py).

- WoW window: the frontmost app .../World of Warcraft/_forever_/World of Warcraft.app, its window
  bounds from Quartz (in points, title bar included: the strip is searched near the corner)
- screen capture needs the Screen Recording permission (System Settings > Privacy & Security)
- install: copy of the .app to ~/Applications, login item in ~/Library/LaunchAgents, data in
  ~/Library/Application Support/WallOfShameCompanion; uninstall from the menu bar icon
- one instance: file lock; another instance asks this one to quit with a request file
"""

import fcntl
import os
import plistlib
import re
import shutil
import subprocess
import sys
import threading
import time

from appinfo import APP, BUNDLE_ID, NAME

STARTUP_LABEL = "Open at login"
UNINSTALL_IN_MENU = True  # macOS has no list of installed apps with an Uninstall button

HOME = os.path.expanduser("~")
INSTALLED_APP = os.path.join(HOME, "Applications", APP + ".app")
DATA_DIR = os.path.join(HOME, "Library", "Application Support", APP)
AGENT = os.path.join(HOME, "Library", "LaunchAgents", BUNDLE_ID + ".plist")
LOCK_PATH = os.path.join(DATA_DIR, "companion.lock")
QUIT_PATH = os.path.join(DATA_DIR, "quit.request")
SCREEN_SETTINGS = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
COMMON_DIRS = ["/Applications/World of Warcraft", os.path.join(HOME, "Applications", "World of Warcraft")]
# the game app sits in its game folder: .../World of Warcraft/_forever_/World of Warcraft.app
GAME_APP_RE = re.compile(r"/_[A-Za-z0-9_]+_/[^/]+\.app$")

FROZEN = getattr(sys, "frozen", False)


def init():
    pass


def _bundle():
    """The running .app (sys.executable is .../X.app/Contents/MacOS/X)."""
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(sys.executable))))


def app_dir():
    return os.path.dirname(_bundle()) if FROZEN else os.path.dirname(os.path.abspath(__file__))


def data_dir():
    """config.toml, state.json, log.txt: never inside the .app."""
    if not FROZEN:
        return app_dir()
    os.makedirs(DATA_DIR, exist_ok=True)
    return DATA_DIR


def _osascript(script):
    return subprocess.run(["osascript", "-e", script], capture_output=True, text=True)


def _quote(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def message(text, warning=False):
    _osascript(f'display dialog {_quote(text)} with title {_quote(NAME)} buttons {{"OK"}} default button "OK"'
               + (" with icon caution" if warning else ""))


def confirm(text):
    result = _osascript(f'display dialog {_quote(text)} with title {_quote(NAME)} '
                        'buttons {"Cancel", "Uninstall"} default button "Cancel" with icon caution')
    return "Uninstall" in result.stdout


def open_path(path):
    subprocess.run(["open", path])


# --- WoW ------------------------------------------------------------------------------------------

def _wow_apps():
    from AppKit import NSWorkspace
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        url = app.bundleURL()
        path = url.path() if url else None
        if path and GAME_APP_RE.search(path):
            yield app, path


def wow_running():
    return any(True for _ in _wow_apps())


def running_wow_dir():
    """The game folder holds the game app (World of Warcraft.app sits in _forever_)."""
    for _, path in _wow_apps():
        return os.path.dirname(path)
    return None


def wow_window():
    """Bounds of the WoW window (points, title bar included) when WoW is the frontmost app, else
    None. scale: physical pixels per point (Retina: 2), the strip is drawn in physical pixels."""
    import Quartz
    from AppKit import NSScreen, NSWorkspace

    front = NSWorkspace.sharedWorkspace().frontmostApplication()
    url = front.bundleURL() if front else None
    if not url or not GAME_APP_RE.search(url.path() or ""):
        return None
    pid = front.processIdentifier()
    options = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    best = None
    for window in Quartz.CGWindowListCopyWindowInfo(options, Quartz.kCGNullWindowID) or []:
        if window.get("kCGWindowOwnerPID") != pid or window.get("kCGWindowLayer", 0) != 0:
            continue
        bounds = window.get("kCGWindowBounds") or {}
        size = bounds.get("Width", 0) * bounds.get("Height", 0)
        if not best or size > best[0]:
            best = (size, bounds)
    if not best:
        return None
    bounds = best[1]
    screen = NSScreen.mainScreen()  # the screen of the key window: WoW's, it is frontmost
    return {"left": int(bounds["X"]), "top": int(bounds["Y"]), "width": int(bounds["Width"]),
            "height": int(bounds["Height"]), "exact": False,
            "scale": float(screen.backingScaleFactor()) if screen else 1.0}


def install_roots():
    return []


def fallback_roots():
    return COMMON_DIRS


# --- Screen Recording permission ------------------------------------------------------------------

def screen_capture_allowed():
    try:
        import Quartz
        return bool(Quartz.CGPreflightScreenCaptureAccess())
    except (ImportError, AttributeError):  # older macOS: no such permission
        return True


def request_screen_capture():
    """Shows the system prompt (once); the app must be reopened after the permission is given."""
    try:
        import Quartz
        Quartz.CGRequestScreenCaptureAccess()
    except (ImportError, AttributeError):
        pass


def open_screen_capture_settings():
    subprocess.run(["open", SCREEN_SETTINGS])


# --- Open at login --------------------------------------------------------------------------------

def startup_enabled():
    return os.path.exists(AGENT)


def set_startup(enabled):
    if not enabled:
        if os.path.exists(AGENT):
            os.remove(AGENT)
        return
    os.makedirs(os.path.dirname(AGENT), exist_ok=True)
    with open(AGENT, "wb") as f:
        plistlib.dump({"Label": BUNDLE_ID, "ProgramArguments": ["/usr/bin/open", INSTALLED_APP],
                       "RunAtLoad": True, "ProcessType": "Interactive"}, f)


# --- One instance ---------------------------------------------------------------------------------

def single_instance():
    """Lock for this instance, or None when another one is running."""
    os.makedirs(DATA_DIR, exist_ok=True)
    lock = open(LOCK_PATH, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        lock.close()
        return None
    if os.path.exists(QUIT_PATH):  # left by an old request
        os.remove(QUIT_PATH)
    return lock


def _lock_free():
    try:
        with open(LOCK_PATH, "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(lock, fcntl.LOCK_UN)
        return True
    except OSError:
        return False


def watch_quit(callback):
    """Calls callback when another instance (update, uninstall) asks this one to stop."""
    def wait():
        while not os.path.exists(QUIT_PATH):
            time.sleep(1)
        os.remove(QUIT_PATH)
        callback()

    threading.Thread(target=wait, daemon=True).start()


def stop_running_instance(timeout=10):
    """Asks a running companion to quit and waits for it. True if none is left."""
    os.makedirs(DATA_DIR, exist_ok=True)
    if _lock_free():
        return True
    open(QUIT_PATH, "w").close()
    deadline = time.time() + timeout
    while time.time() < deadline:
        if _lock_free():
            return True
        time.sleep(0.2)
    return False


# --- Install, update, uninstall -------------------------------------------------------------------

def needs_install():
    """The .app runs from anywhere else than ~/Applications (Downloads...)."""
    return FROZEN and os.path.realpath(_bundle()) != os.path.realpath(INSTALLED_APP)


def install():
    """Copy the .app to ~/Applications, open at login, start the installed copy."""
    updating = os.path.exists(INSTALLED_APP)
    if not stop_running_instance():
        message("The companion is still running and could not be stopped. Quit it from its icon in "
                "the menu bar, then try again.", warning=True)
        return
    try:
        if updating:
            shutil.rmtree(INSTALLED_APP)
        os.makedirs(os.path.dirname(INSTALLED_APP), exist_ok=True)
        shutil.copytree(_bundle(), INSTALLED_APP, symlinks=True)
    except OSError as e:
        message(f"Could not copy the companion to {INSTALLED_APP}: {e}", warning=True)
        return
    # downloaded once, opened once: the installed copy needs no second Gatekeeper confirmation
    subprocess.run(["xattr", "-dr", "com.apple.quarantine", INSTALLED_APP], capture_output=True)
    if not updating:
        set_startup(True)
    subprocess.Popen(["open", INSTALLED_APP])
    message(("Updated." if updating else "Installed.") + "\n\n"
            "The companion runs in the background: its icon is in the menu bar, at the top right. "
            "It opens at login.\n\nmacOS will ask for the Screen Recording permission: it is needed "
            "for the screenshots and the instant posts.\n\nYou can delete this downloaded copy. To "
            "uninstall: menu bar icon > Uninstall.")


def uninstall(current_instance=False):
    """From the menu bar icon (current_instance) or from a second copy."""
    if not confirm("Uninstall the Wall of Shame Forever companion?\n\nYour deaths and level-ups will "
                   "no longer be sent to Discord."):
        return False
    if not current_instance:
        stop_running_instance()
    set_startup(False)
    shutil.rmtree(INSTALLED_APP, ignore_errors=True)
    shutil.rmtree(DATA_DIR, ignore_errors=True)
    message("The companion is uninstalled.")
    return True
