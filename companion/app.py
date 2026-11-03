"""Shame Wall Forever companion as a Windows background app (the .exe entry point).

- no console: an icon in the notification area (status, log, start with Windows, quit)
- first launch of the .exe: copies itself to %LOCALAPPDATA%\\ShameWallCompanion, starts with
  Windows, and shows up in Settings > Apps with an Uninstall button (no admin rights needed)
- launching a newer .exe replaces the installed one (update)
- one instance at a time
"""

import ctypes
import os
import shutil
import subprocess
import sys
import threading
import time
import winreg

APP = "ShameWallCompanion"
NAME = "Shame Wall Forever companion"
VERSION = "0.1.0"
INSTALL_DIR = os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~")), APP)
INSTALLED_EXE = os.path.join(INSTALL_DIR, APP + ".exe")
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
UNINSTALL_KEY = r"Software\Microsoft\Windows\CurrentVersion\Uninstall" + "\\" + APP
MUTEX_NAME = "Local\\ShameWallCompanionRunning"
QUIT_EVENT_NAME = "Local\\ShameWallCompanionQuit"  # set by another instance to stop this one

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
INFINITE = 0xFFFFFFFF
MB_ICONINFO, MB_ICONWARNING, MB_YESNO, IDYES = 0x40, 0x30, 0x04, 6
CREATE_NO_WINDOW, DETACHED_PROCESS = 0x08000000, 0x00000008


def message(text, flags=MB_ICONINFO):
    return user32.MessageBoxW(None, text, NAME, flags)


def load_icon():
    """Bagarre Club logo (assets/icon.png, bundled into the .exe by build.py)."""
    from PIL import Image
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return Image.open(os.path.join(base, "assets", "icon.png"))


# --- Registry: start with Windows, entry in Settings > Apps -------------------------------------

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


def register_uninstall():
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY) as k:
        values = {
            "DisplayName": NAME,
            "DisplayVersion": VERSION,
            "Publisher": "Shame Wall Forever",
            "DisplayIcon": INSTALLED_EXE,
            "InstallLocation": INSTALL_DIR,
            "UninstallString": f'"{INSTALLED_EXE}" --uninstall',
        }
        for name, value in values.items():
            winreg.SetValueEx(k, name, 0, winreg.REG_SZ, value)
        for name in ("NoModify", "NoRepair"):
            winreg.SetValueEx(k, name, 0, winreg.REG_DWORD, 1)
        winreg.SetValueEx(k, "EstimatedSize", 0, winreg.REG_DWORD, os.path.getsize(INSTALLED_EXE) // 1024)


def unregister():
    set_startup(False)
    try:
        winreg.DeleteKey(winreg.HKEY_CURRENT_USER, UNINSTALL_KEY)
    except OSError:
        pass


# --- Other instances ------------------------------------------------------------------------------

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

def install():
    """Run from anywhere else than the install folder: copy there, register, start it."""
    updating = os.path.exists(INSTALLED_EXE)
    if not stop_running_instance():
        message("The companion is still running and could not be stopped. Quit it from its icon "
                "near the clock, then try again.", MB_ICONWARNING)
        return
    os.makedirs(INSTALL_DIR, exist_ok=True)
    for attempt in range(10):
        try:
            shutil.copy2(sys.executable, INSTALLED_EXE)
            break
        except PermissionError:  # the old one is still closing
            time.sleep(0.5)
    else:
        message(f"Could not copy the companion to {INSTALL_DIR}.", MB_ICONWARNING)
        return
    register_uninstall()
    if not updating:
        set_startup(True)
    subprocess.Popen([INSTALLED_EXE], cwd=INSTALL_DIR, creationflags=DETACHED_PROCESS, close_fds=True)
    message(("Updated." if updating else "Installed.") + "\n\n"
            "The companion runs in the background: its icon is near the clock (click ^ if hidden). "
            "It starts with Windows.\n\nYou can delete this downloaded file. To uninstall: "
            "Windows Settings > Apps > Installed apps > Shame Wall Forever companion.")


def uninstall():
    if message("Uninstall the Shame Wall Forever companion?\n\nYour deaths and level-ups will no "
               "longer be sent to Discord.", MB_YESNO | MB_ICONWARNING) != IDYES:
        return
    stop_running_instance()
    unregister()
    message("The companion is uninstalled.")
    # the folder (this .exe included) can only be removed once this process has ended
    subprocess.Popen(f'cmd /c ping 127.0.0.1 -n 3 > nul & rmdir /s /q "{INSTALL_DIR}"',
                     creationflags=CREATE_NO_WINDOW, close_fds=True)


# --- The background app ---------------------------------------------------------------------------

def run():
    mutex = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS:
        message("The companion is already running: its icon is near the clock.")
        return
    quit_event = kernel32.CreateEventW(None, True, False, QUIT_EVENT_NAME)

    import pystray
    import shamewall_companion as companion

    stop = threading.Event()
    worker = threading.Thread(target=companion_main, args=(companion, stop), daemon=True)
    worker.start()

    def status(_item):
        return companion.STATUS["wow"]

    def open_log(_icon, _item):
        if os.path.exists(companion.LOG_PATH):
            os.startfile(companion.LOG_PATH)

    def toggle_startup(_icon, _item):
        set_startup(not startup_enabled())

    def quit_app(icon, _item):
        icon.stop()

    # same layout as the TrollDiscord tray: status lines, actions, Quit
    menu = pystray.Menu(
        pystray.MenuItem(lambda _i: f"Status: {status(_i)}", None, enabled=False),
        pystray.MenuItem(lambda _i: f"Bot: {companion.STATUS['bot']}", None, enabled=False),
        pystray.MenuItem(lambda _i: companion.STATUS["last"] or "Nothing sent yet", None, enabled=False),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Open log", open_log),
        pystray.MenuItem("Start with Windows", toggle_startup, checked=lambda _i: startup_enabled(),
                         visible=FROZEN),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", quit_app),
    )
    icon = pystray.Icon(APP, load_icon(), NAME, menu)

    def refresh():  # tooltip and menu follow the status
        while not stop.wait(3):
            icon.title = f"{NAME}\n{companion.STATUS['wow']}\n{companion.STATUS['bot']}"[:127]
            icon.update_menu()

    def wait_quit():  # another instance (update, uninstall) asks us to stop
        kernel32.WaitForSingleObject(quit_event, INFINITE)
        icon.stop()

    threading.Thread(target=refresh, daemon=True).start()
    threading.Thread(target=wait_quit, daemon=True).start()
    icon.run()
    stop.set()
    worker.join(timeout=5)
    kernel32.CloseHandle(mutex)


def companion_main(companion, stop):
    try:
        companion.main(stop)
    except Exception as e:  # keep the icon, show the problem in the menu and the log
        companion.STATUS["wow"] = f"error: {e}"[:80]
        companion.log(f"error: {e!r}")


def main():
    if "--uninstall" in sys.argv:
        return uninstall()
    if FROZEN and os.path.normcase(os.path.abspath(sys.executable)) != os.path.normcase(INSTALLED_EXE):
        return install()
    run()


if __name__ == "__main__":
    main()
