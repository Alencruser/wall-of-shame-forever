"""Wall of Shame Forever companion: sends your own WoW deaths to the guild's Discord bot.

Two sources, both deduplicated on the event id:
- realtime: reads the death strip the addon draws in the top-left corner (WoW must be the
  active window), and takes a screenshot of the death screen at the same moment
- fallback: the outbox in SavedVariables, written by WoW on /reload, logout or exit
"""

import glob
import io
import json
import os
import sys
import threading
import time
import tomllib
import urllib.parse

import mss
import requests
from PIL import Image

import connection
import events
import osplat
import strip
import wowpath

try:  # private builds only (build_private.py, not in the repository): the guild's code
    from embedded import CONNECTION as BUILTIN_CODE
except ImportError:
    BUILTIN_CODE = None

HERE = osplat.app_dir()        # the .exe / .app (or the sources)
DATA_DIR = osplat.data_dir()   # Windows: next to the .exe; macOS: ~/Library/Application Support
CONFIG_PATH = os.path.join(DATA_DIR, "config.toml")
STATE_PATH = os.path.join(DATA_DIR, "state.json")
OUT_DIR = os.path.join(DATA_DIR, "out")
LOG_PATH = os.path.join(DATA_DIR, "log.txt")
MAX_LOG = 1024 * 1024  # log.txt is cut in half when bigger

STRIP_INTERVAL = 0.2   # the strip stays 3 s on screen
OUTBOX_INTERVAL = 2.0
DETECT_INTERVAL = 30.0 # look again for WoW folders (new install, WoW started)
MAX_AGE = 24 * 3600    # never send outbox deaths older than this
MAX_SENT_IDS = 1000

# macOS: the strip is searched this far from the window corner (title bar, frame), in points
MAC_MARGIN_X, MAC_MARGIN_Y = 8, 48
PERMISSION_INTERVAL = 10.0  # macOS Screen Recording permission, checked again this often

osplat.init()  # Windows: per-monitor DPI awareness (real pixels)


# Short status for the tray icon (see app.py)
STATUS = {"wow": "looking for WoW...", "bot": "no connection code yet", "last": "", "screen": ""}


def log(msg):
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}"
    if sys.stdout:  # no console in the background app
        print(line, flush=True)
    try:
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > MAX_LOG:
            with open(LOG_PATH, encoding="utf-8", errors="replace") as f:
                keep = f.read()[-MAX_LOG // 2:]
            with open(LOG_PATH, "w", encoding="utf-8") as f:
                f.write(keep)
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_config():
    try:
        with open(CONFIG_PATH, "rb") as f:
            cfg = tomllib.load(f)
    except FileNotFoundError:
        cfg = {}
    cfg.setdefault("wow_path", "")
    cfg.setdefault("connection", "")
    cfg.setdefault("realtime", True)
    return cfg


class State:
    def __init__(self):
        try:
            with open(STATE_PATH, encoding="utf-8") as f:
                self.sent = json.load(f)["sent"]
        except (OSError, ValueError, KeyError):
            self.sent = []

    def __contains__(self, event_id):
        return event_id in self.sent

    def add(self, event_id):
        self.sent = (self.sent + [event_id])[-MAX_SENT_IDS:]
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            json.dump({"sent": self.sent}, f)


class Refused(Exception):
    pass


class Rejected(Exception):
    """403: the code is good, the bot does not want this one event (older bots: another guild)."""


class Sender:
    """Posts events to the bot, retrying failures; in dry run, saves them to ./out.

    The connection code comes from the guild information (via the addon's SavedVariables):
    events wait in the queue until there is one.
    """

    def __init__(self, dry_run):
        self.dry_run = dry_run
        self.code, self.url, self.key, self.pinned = None, None, None, False
        self.queue = []  # [event, jpeg bytes or None, next try, delay]
        self.warned = False

    def set_code(self, code, pinned=False):
        if self.dry_run or self.pinned or code == self.code:
            return
        if code is None:
            self.code = self.url = self.key = None
            self.warned = False
            self.queue.clear()  # never send them later to another guild's bot
            STATUS["bot"] = "no connection code (left the guild?)"
            log("the connection code was removed (left the guild): deaths are no longer sent")
            return
        found = connection.decode(code)
        if not found:
            return
        self.pinned = pinned
        first = self.code is None
        self.code, (self.url, self.key) = code, found
        STATUS["bot"] = urllib.parse.urlsplit(self.url).netloc
        log(("sending your deaths to " if first else "new connection code from the guild, now sending to ")
            + self.url)
        for item in self.queue:  # retry right away, also what the old code got refused for
            item[2], item[3] = 0, 5

    def queued(self, event_id):
        return any(item[0]["id"] == event_id for item in self.queue)

    def push(self, ev, jpeg):
        self.queue.append([ev, jpeg, 0, 5])

    def flush(self):
        if not self.dry_run and not self.url:
            if self.queue and not self.warned:
                log("waiting for the guild's connection code: an officer must put it in the guild "
                    "information, then WoW saves it on /reload or logout")
                self.warned = True
            return
        now = time.time()
        for item in list(self.queue):
            ev, jpeg, next_try, delay = item
            if next_try > now:
                continue
            try:
                self._send(ev, jpeg)
                self.queue.remove(item)
                STATUS["last"] = f"last sent: {ev.get('type', 'death')} at {time.strftime('%H:%M')}"
                if ev.get("type") in ("duel", "kill"):
                    log(f"sent {ev['type']} of {ev['name']} vs {ev.get('opponent') or ev.get('victim')} "
                        f"({ev['source']}, screenshot: {'yes' if jpeg else 'no'})")
                elif ev.get("type") == "level":
                    log(f"sent level {ev['level']} of {ev['name']} ({ev['class']}, {ev['source']}, "
                        f"screenshot: {'yes' if jpeg else 'no'})")
                else:
                    log(f"sent {ev['id']} ({ev['source']}, screenshot: {'yes' if jpeg else 'no'})")
            except Refused:
                # kept: retried as soon as the guild information has a new code
                item[2] = now + 3600
                STATUS["bot"] = "code refused, ask an officer"
                log("the bot refused the guild's connection code: officers must put the current "
                    "one in the guild information")
            except Rejected:  # never accepted: not kept, the code itself is fine
                self.queue.remove(item)
                log(f"the bot rejected {ev.get('type', 'death')} {ev['id']} (guild "
                    f"\"{ev.get('guild', '')}\"): not sent")
            except Exception as e:  # network, HTTP error: retry later
                item[2], item[3] = now + delay, min(delay * 2, 300)
                log(f"send failed for {ev['id']}, retry in {delay}s: {e}")

    def _send(self, ev, jpeg):
        if self.dry_run:
            os.makedirs(OUT_DIR, exist_ok=True)
            base = os.path.join(OUT_DIR, ev["id"].replace(":", "_"))
            with open(base + ".json", "w", encoding="utf-8") as f:
                json.dump(ev, f, ensure_ascii=False, indent=2)
            if jpeg:
                with open(base + ".jpg", "wb") as f:
                    f.write(jpeg)
            return
        files = {"screenshot": ("death.jpg", jpeg, "image/jpeg")} if jpeg else None
        r = requests.post(self.url, headers={"Authorization": f"Bearer {self.key}"},
                          data={"event": json.dumps(ev, ensure_ascii=False)}, files=files, timeout=15)
        if r.status_code == 401:
            raise Refused()
        if r.status_code == 403:
            raise Rejected()
        r.raise_for_status()


def grab(sct, area):
    shot = sct.grab(area)
    return Image.frombytes("RGB", shot.size, shot.bgra, "raw", "BGRX")


# Strip positions (strip.POSITIONS): the one of the last strip first, then one other per pass,
# so every position is looked at within 1.6 s while a strip stays 3 s on screen
SCAN = {"last": "TOPLEFT", "turn": 0}


def read_strip(sct, area):
    """(payload, strip box in capture pixels, position), or None.
    Windows: the client area in real pixels, the strip exactly at its anchor. macOS: the window
    bounds in points (title bar included), the strip drawn in physical pixels: searched around its
    anchor, with the block size of the capture (Retina captures can be 1x or 2x)."""
    others = [p for p in strip.POSITIONS if p != SCAN["last"]]
    other = others[SCAN["turn"] % len(others)]
    SCAN["turn"] += 1
    margins = (0, 0) if area["exact"] else (MAC_MARGIN_X, MAC_MARGIN_Y)
    for position in (SCAN["last"], other):
        found = strip.read(lambda region: grab(sct, region), area, position, *margins,
                           display_p3=not area["exact"])
        if found:
            SCAN["last"] = position
            payload, box, _ = found
            return payload, box, position
    return None


def check_strip(sct, state, sender):
    area = osplat.wow_window()
    if not area:
        return
    found = read_strip(sct, area)
    if not found:
        return
    payload, box, position = found
    ev = events.parse_payload(payload, "realtime")
    if not ev or ev["type"] not in ("death", "level", "duel", "kill") or ev["id"] in state:
        return
    state.add(ev["id"])
    # the game screen without the strip (and, strip at the top, on macOS without the title bar)
    screen = strip.hide(grab(sct, area), box, position)
    buf = io.BytesIO()
    screen.save(buf, "JPEG", quality=85)
    if ev["type"] == "level":
        log(f"level-up seen on screen: {ev['name']} level {ev['level']} in {ev['zone']}")
    elif ev["type"] == "duel":
        log(f"duel won seen on screen: {ev['name']} vs {ev['opponent']} in {ev['zone']}")
    elif ev["type"] == "kill":
        log(f"killing blow seen on screen: {ev['name']} on {ev['victim']} in {ev['zone']}")
    else:
        log(f"death seen on screen: {ev['name']} level {ev['level']} in {ev['zone']}, killer: {ev['killer']}")
    sender.push(ev, buf.getvalue())


def check_outbox(paths, mtimes, state, sender):
    """New events from the SavedVariables files. The connection code is the one of the most
    recently written file (none there = the player left the guild: forget it)."""
    changed = []  # (mtime, text)
    for path in paths:
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtimes.get(path) != mtime:
            mtimes[path] = mtime
            with open(path, encoding="utf-8", errors="replace") as f:
                changed.append((mtime, f.read()))
    if not changed:
        return
    sender.set_code(events.read_connection(max(changed)[1]))

    for _, text in changed:
        for payload in events.read_outbox(text):
            ev = events.parse_payload(payload, "savedvariables")
            if not ev:
                continue
            if ev["type"] == "level":
                # sent again on every /reload or logout: the bot keeps the highest level per class,
                # so resending is harmless, and levels come back after /shamewall reset-niveaux
                if not sender.queued(ev["id"]):
                    sender.push(ev, None)
                continue
            if ev["id"] in state:
                continue
            state.add(ev["id"])
            if ev["type"] == "professions":  # a new id per reading: the bot keeps the latest
                log(f"professions found in SavedVariables: {ev['name']}, "
                    + ", ".join(f"{p['name']} {p['level']}" for p in ev["professions"]))
                sender.push(ev, None)
                continue
            if ev["type"] in ("duel", "kill"):  # leaderboard: late is fine
                log(f"{ev['type']} found in SavedVariables: {ev['name']} vs "
                    f"{ev.get('opponent') or ev.get('victim')}")
                sender.push(ev, None)
                continue
            if ev["time"] and time.time() - ev["time"] > MAX_AGE:
                continue
            log(f"death found in SavedVariables: {ev['name']} level {ev['level']} in {ev['zone']}")
            sender.push(ev, None)


DB_START = "WallOfShameForeverDB = {"


def write_builtin_code(game_dirs):
    """Private build: gives the built-in code to the addon, so players type nothing in game.
    Only while WoW is closed (WoW rewrites the file on logout), never over an existing code."""
    if not BUILTIN_CODE or wowpath.wow_running():
        return
    for game_dir in game_dirs:
        for account in glob.glob(os.path.join(game_dir, "WTF", "Account", "*", "")):
            if os.path.basename(os.path.dirname(account)) == "SavedVariables":
                continue
            path = os.path.join(account, "SavedVariables", "WallOfShameForever.lua")
            entry = f'["connection"] = "{BUILTIN_CODE}",'
            try:
                if os.path.exists(path):
                    with open(path, encoding="utf-8", errors="replace") as f:
                        text = f.read()
                    if '["connection"]' in text or DB_START not in text:
                        continue
                    text = text.replace(DB_START, f"{DB_START}\n{entry}", 1)
                else:
                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    text = f"{DB_START}\n{entry}\n}}\n"
                with open(path, "w", encoding="utf-8") as f:
                    f.write(text)
                log(f"built-in connection code given to the addon ({os.path.basename(os.path.dirname(account))})")
            except OSError as e:
                log(f"could not write the built-in code to {path}: {e}")


def saved_variables(game_dirs):
    return [p for d in game_dirs for p in glob.glob(
        os.path.join(d, "WTF", "Account", "*", "SavedVariables", "WallOfShameForever.lua"))]


def main(stop=None):
    """Runs until stop (a threading.Event) is set; the console version runs until Ctrl+C."""
    stop = stop or threading.Event()
    cfg = load_config()
    dry_run = "--dry-run" in sys.argv
    state, sender = State(), Sender(dry_run)
    if dry_run:
        log(f"dry run: events and screenshots saved to {OUT_DIR}")
    elif cfg["connection"]:
        sender.set_code(cfg["connection"], pinned=True)  # manual override, e.g. to test another bot

    game_dirs, mtimes, last_outbox, last_detect = [], {}, 0.0, 0.0
    capture_ok, last_permission = True, 0.0
    log("companion started")
    with mss.mss() as sct:
        while not stop.is_set():
            if time.time() - last_permission > PERMISSION_INTERVAL:
                allowed = osplat.screen_capture_allowed()
                if allowed != capture_ok or not last_permission:
                    STATUS["screen"] = "" if allowed else "Screen Recording not allowed: no screenshots"
                    if not allowed:
                        log("macOS Screen Recording permission missing: events wait for /reload, "
                            "without screenshots")
                capture_ok, last_permission = allowed, time.time()
            if cfg["realtime"] and capture_ok:
                check_strip(sct, state, sender)
            if time.time() - last_detect > DETECT_INTERVAL:
                dirs = wowpath.find_game_dirs(cfg["wow_path"], HERE)
                if dirs != game_dirs or not last_detect:  # always say it on the first pass
                    log("WoW folders with the addon: " + (", ".join(dirs) or
                        "none found yet (start WoW, or set wow_path in config.toml)"))
                    STATUS["wow"] = ("WoW: " + ", ".join(os.path.basename(d) for d in dirs)
                                     if dirs else "WoW: addon not found yet")
                    game_dirs = dirs or game_dirs
                write_builtin_code(game_dirs)
                last_detect = time.time()
            if time.time() - last_outbox > OUTBOX_INTERVAL:
                check_outbox(saved_variables(game_dirs), mtimes, state, sender)
                last_outbox = time.time()
            sender.flush()
            stop.wait(STRIP_INTERVAL)
    log("companion stopped")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
