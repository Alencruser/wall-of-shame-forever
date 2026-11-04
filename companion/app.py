"""Wall of Shame Forever companion as a background app (entry point of the .exe and the .app).

- no window: an icon near the clock (Windows) or in the menu bar (macOS), with the status, the
  log, start with the system, Quit (macOS: also Screen Recording permission and Uninstall)
- first launch: installs itself (Windows: %LOCALAPPDATA% + Settings > Apps; macOS: ~/Applications)
  and starts with the system; launching a newer copy replaces the installed one (update)
- one instance at a time
The system-specific parts are in platform_win.py and platform_mac.py (through osplat.py).
"""

import os
import sys
import threading

import osplat
from appinfo import APP, NAME

FROZEN = getattr(sys, "frozen", False)


def load_icon():
    """Bagarre Club logo (assets/icon.png, bundled by build.py)."""
    from PIL import Image
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return Image.open(os.path.join(base, "assets", "icon.png"))


def ask_screen_permission(companion):
    """macOS: the system prompt, once, and how to give the permission."""
    if osplat.screen_capture_allowed():
        return
    flag = os.path.join(companion.DATA_DIR, "screen-permission-asked")
    osplat.request_screen_capture()
    if not os.path.exists(flag):
        open(flag, "w").close()
        osplat.message("To post your deaths and level-ups right away with a screenshot, allow the "
                       "companion in System Settings > Privacy & Security > Screen Recording, then "
                       "quit and reopen it.\n\nWithout it, events are still sent at /reload or "
                       "logout, without screenshots.")


def run():
    lock = osplat.single_instance()
    if not lock:
        osplat.message("The companion is already running: its icon is "
                       + ("in the menu bar." if sys.platform == "darwin" else "near the clock."))
        return

    import pystray
    import wallofshame_companion as companion

    stop = threading.Event()
    worker = threading.Thread(target=companion_main, args=(companion, stop), daemon=True)
    worker.start()

    def open_log(_icon, _item):
        if os.path.exists(companion.LOG_PATH):
            osplat.open_path(companion.LOG_PATH)

    def toggle_startup(_icon, _item):
        osplat.set_startup(not osplat.startup_enabled())

    def allow_screen(_icon, _item):
        osplat.request_screen_capture()
        osplat.open_screen_capture_settings()

    def uninstall(icon, _item):
        if osplat.uninstall(current_instance=True):
            icon.stop()

    def quit_app(icon, _item):
        icon.stop()

    # same layout as the TrollDiscord tray: status lines, actions, Quit
    menu = pystray.Menu(
        pystray.MenuItem(lambda _i: f"Status: {companion.STATUS['wow']}", None, enabled=False),
        pystray.MenuItem(lambda _i: f"Bot: {companion.STATUS['bot']}", None, enabled=False),
        pystray.MenuItem(lambda _i: companion.STATUS["last"] or "Nothing sent yet", None, enabled=False),
        pystray.MenuItem(lambda _i: companion.STATUS["screen"], None, enabled=False,
                         visible=lambda _i: bool(companion.STATUS["screen"])),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Allow screen recording…", allow_screen,
                         visible=lambda _i: bool(companion.STATUS["screen"])),
        pystray.MenuItem("Open log", open_log),
        pystray.MenuItem(osplat.STARTUP_LABEL, toggle_startup, checked=lambda _i: osplat.startup_enabled(),
                         visible=FROZEN),
        pystray.MenuItem("Uninstall…", uninstall, visible=FROZEN and osplat.UNINSTALL_IN_MENU),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", quit_app),
    )
    icon = pystray.Icon(APP, load_icon(), NAME, menu)

    def refresh():  # tooltip and menu follow the status
        while not stop.wait(3):
            icon.title = f"{NAME}\n{companion.STATUS['wow']}\n{companion.STATUS['bot']}"[:127]
            icon.update_menu()

    threading.Thread(target=refresh, daemon=True).start()
    osplat.watch_quit(icon.stop)  # another instance (update, uninstall) asks us to stop
    if FROZEN:
        threading.Thread(target=ask_screen_permission, args=(companion,), daemon=True).start()
    icon.run()
    stop.set()
    worker.join(timeout=5)


def companion_main(companion, stop):
    try:
        companion.main(stop)
    except Exception as e:  # keep the icon, show the problem in the menu and the log
        companion.STATUS["wow"] = f"error: {e}"[:80]
        companion.log(f"error: {e!r}")


def main():
    if "--uninstall" in sys.argv:
        return osplat.uninstall()
    if osplat.needs_install():
        return osplat.install()
    run()


if __name__ == "__main__":
    main()
