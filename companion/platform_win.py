"""Windows layer of the companion (same functions as platform_mac.py, used through osplat.py).

- WoW window: GxWindowClass, client area in real pixels (per-monitor DPI aware)
- install: copy to %LOCALAPPDATA%\\WallOfShameCompanion, quoted HKCU Run entry, entry in
  Settings > Apps with an Uninstall button (no admin rights)
- one instance: named mutex; another instance asks this one to quit with a named event
"""

import ctypes
import os
import shutil
import string
import subprocess
import sys
import threading
import time
import winreg
from ctypes import wintypes

from appinfo import APP, NAME, VERSION

STARTUP_LABEL = "Start with Windows"
UNINSTALL_IN_MENU = False  # uninstalled from Windows Settings > Apps

INSTALL_DIR = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), APP)
INSTALLED_EXE = os.path.join(INSTALL_DIR, APP + ".exe")
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
UNINSTALL_KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall" + "\\" + APP
MUTEX_NAME = "Local\\WallOfShameCompanionRunning"
QUIT_EVENT_NAME = "Local\\WallOfShameCompanionQuit"  # set by another instance to stop this one
BLIZZARD_KEYS = [
    r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft",
    r"SOFTWARE\Blizzard Entertainment\World of Warcraft",
]
COMMON_DIRS = [r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft",
               r"World of Warcraft", r"Games\World of Warcraft", r"Battle.net\World of Warcraft"]

FROZEN = getattr(sys, "frozen", False)
user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32
kernel32.CreateMutexW.restype = kernel32.OpenMutexW.restype = ctypes.c_void_p
kernel32.CreateEventW.restype = kernel32.OpenEventW.restype = ctypes.c_void_p
kernel32.SetEvent.argtypes = kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
kernel32.WaitForSingleObject.argtypes = [ctypes.c_void_p, ctypes.c_uint32]

ERROR_ALREADY_EXISTS = 183
SYNCHRONIZE = 0x00100000
EVENT_MODIFY_STATE = 0x0002
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
INFINITE = 0xFFFFFFFF
MB_ICONINFO, MB_ICONWARNING, MB_YESNO, IDYES = 0x40, 0x30, 0x04, 6
CREATE_NO_WINDOW, DETACHED_PROCESS = 0x08000000, 0x00000008


def init():
    try:
        user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))  # per-monitor v2: real pixels
    except AttributeError:
        user32.SetProcessDPIAware()


def app_dir():
    """Folder of the .exe (or of the sources)."""
    return os.path.dirname(os.path.abspath(sys.executable if FROZEN else __file__))


def data_dir():
    """config.toml, state.json, log.txt: next to the installed .exe."""
    return app_dir()


def message(text, warning=False):
    user32.MessageBoxW(None, text, NAME, MB_ICONWARNING if warning else MB_ICONINFO)


def confirm(text):
    return user32.MessageBoxW(None, text, NAME, MB_YESNO | MB_ICONWARNING) == IDYES


def open_path(path):
    os.startfile(path)


# --- WoW ------------------------------------------------------------------------------------------

def _wow_hwnd():
    return user32.FindWindowW("GxWindowClass", None) or user32.FindWindowW(None, "World of Warcraft")


def wow_window():
    """Screen rectangle of the WoW client area in real pixels, or None if WoW is not the active
    window. exact: the strip is right at the top-left corner."""
    hwnd = _wow_hwnd()
    if not hwnd or user32.GetForegroundWindow() != hwnd:
        return None
    rect, origin = wintypes.RECT(), wintypes.POINT(0, 0)
    user32.GetClientRect(hwnd, ctypes.byref(rect))
    user32.ClientToScreen(hwnd, ctypes.byref(origin))
    return {"left": origin.x, "top": origin.y, "width": rect.right, "height": rect.bottom,
            "exact": True, "scale": 1.0}


def wow_running():
    return bool(_wow_hwnd())


def running_wow_dir():
    """Folder of the running WoW executable (Wow.exe sits in the game folder)."""
    hwnd = _wow_hwnd()
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


def install_roots():
    """Blizzard registry key InstallPath (one game folder, e.g. _retail_, and its siblings)."""
    roots = []
    for key in BLIZZARD_KEYS:
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, key) as k:
                install = winreg.QueryValueEx(k, "InstallPath")[0].rstrip("\\/")
        except OSError:
            continue
        roots += [install, os.path.dirname(install)]
    return roots


def fallback_roots():
    """Usual install folders on every drive."""
    return [f"{drive}:\\{common}" for drive in string.ascii_uppercase for common in COMMON_DIRS]


# --- Screen capture: no permission on Windows -----------------------------------------------------

def screen_capture_allowed():
    return True


def request_screen_capture():
    pass


def open_screen_capture_settings():
    pass


# --- Start with Windows, entry in Settings > Apps -------------------------------------------------

def startup_enabled():
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, APP)
            return True
    except OSError:
        return False


def set_startup(enabled):
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
        if enabled:
            winreg.SetValueEx(k, APP, 0, winreg.REG_SZ, f'"{INSTALLED_EXE}"')
        else:
            try:
                winreg.DeleteValue(k, APP)
            except OSError:
                pass


def _register_uninstall():
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY) as k:
        values = {
            "DisplayName": NAME,
            "DisplayVersion": VERSION,
            "Publisher": "Wall of Shame Forever",
            "DisplayIcon": INSTALLED_EXE,
            "InstallLocation": INSTALL_DIR,
            "UninstallString": f'"{INSTALLED_EXE}" --uninstall',
        }
        for name, value in values.items():
            winreg.SetValueEx(k, name, 0, winreg.REG_SZ, value)
        for name in ("NoModify", "NoRepair"):
            winreg.SetValueEx(k, name, 0, winreg.REG_DWORD, 1)
        winreg.SetValueEx(k, "EstimatedSize", 0, winreg.REG_DWORD, os.path.getsize(INSTALLED_EXE) // 1024)


def _unregister():
    set_startup(False)
    try:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY)
    except OSError:
        pass


# --- One instance ---------------------------------------------------------------------------------

def single_instance():
    """Lock for this instance, or None when another one is running."""
    mutex = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        return None
    return mutex


def watch_quit(callback):
    """Calls callback when another instance (update, uninstall) asks this one to stop."""
    event = kernel32.CreateEventW(None, True, False, QUIT_EVENT_NAME)

    def wait():
        kernel32.WaitForSingleObject(event, INFINITE)
        callback()

    threading.Thread(target=wait, daemon=True).start()


def stop_running_instance(timeout=10):
    """Asks a running companion to quit and waits for it. True if none is left."""
    event = kernel32.OpenEventW(EVENT_MODIFY_STATE, False, QUIT_EVENT_NAME)
    if event:
        kernel32.SetEvent(event)
        kernel32.CloseHandle(event)
    deadline = time.time() + timeout
    while time.time() < deadline:
        mutex = kernel32.OpenMutexW(SYNCHRONIZE, False, MUTEX_NAME)
        if not mutex:
            return True
        kernel32.CloseHandle(mutex)
        time.sleep(0.2)
    return False


# --- Install, update, uninstall -------------------------------------------------------------------

def needs_install():
    """The .exe runs from anywhere else than the install folder (Downloads...)."""
    return FROZEN and os.path.normcase(os.path.abspath(sys.executable)) != os.path.normcase(INSTALLED_EXE)


def install(quiet=False):
    """Copy to the install folder, register, start the installed copy. quiet: an update from the
    menu (updater.py), no message box."""
    updating = os.path.exists(INSTALLED_EXE)
    if not stop_running_instance():
        message("The companion is still running and could not be stopped. Quit it from its icon "
                "near the clock, then try again.", warning=True)
        return
    os.makedirs(INSTALL_DIR, exist_ok=True)
    for _ in range(10):
        try:
            shutil.copy2(sys.executable, INSTALLED_EXE)
            break
        except PermissionError:  # the old one is still closing
            time.sleep(0.5)
    else:
        message(f"Could not copy the companion to {INSTALL_DIR}.", warning=True)
        return
    _register_uninstall()
    if not updating:
        set_startup(True)
    subprocess.Popen([INSTALLED_EXE], cwd=INSTALL_DIR, creationflags=DETACHED_PROCESS, close_fds=True)
    if quiet:
        return
    message(("Updated." if updating else "Installed.") + "\n\n"
            "The companion runs in the background: its icon is near the clock (click ^ if hidden). "
            "It starts with Windows.\n\nYou can delete this downloaded file. To uninstall: "
            "Windows Settings > Apps > Installed apps > Wall of Shame Forever companion.")


def uninstall(current_instance=False):
    """From Windows Settings > Apps (a second copy started with --uninstall)."""
    if not confirm("Uninstall the Wall of Shame Forever companion?\n\nYour deaths and level-ups will "
                   "no longer be sent to Discord."):
        return False
    if not current_instance:
        stop_running_instance()
    _unregister()
    message("The companion is uninstalled.")
    # the folder (this .exe included) can only be removed once this process has ended
    subprocess.Popen(f'cmd /c ping 127.0.0.1 -n 3 > nul & rmdir /s /q "{INSTALL_DIR}"',
                     creationflags=CREATE_NO_WINDOW, close_fds=True)
    return True
