"""Craft orders: fetched from the bot, written as a small addon the WoW addon reads.

The bot keeps the pending orders (asked on Discord). The companion asks for the ones of this
player's characters (GET <bot>/orders, see docs/bot-api.md) and writes them to
Interface/AddOns/WallOfShameForever_Commandes/Commandes.lua in every game folder, as the global
WallOfShameForever_Orders. WoW never writes that file (it is not SavedVariables), so it can be
written while WoW runs; the addon reads it at login or /reload. When the artisan ticks an order
done or refused, the addon sends a "2|O|..." event like the others (events.py).

Which characters: the addon's WallOfShameForeverDB.orderIdentity (battletag and the characters
of the account, written at login) in every SavedVariables file, plus the characters seen in the
events (older SavedVariables without orderIdentity). One request per battletag.
"""

import math
import os
import re
import threading
import time
import urllib.parse

import requests

import events
import wowpath

POLL_INTERVAL = 120.0
REFUSED_RETRY = 3600.0  # 401: asked again after this long, or at once with a new code
FOLDER = "WallOfShameForever_Commandes"
LUA_FILE = "Commandes.lua"
TOC_FILE = FOLDER + ".toc"
DEFAULT_INTERFACE = "16001"
GLOBAL = "WallOfShameForever_Orders"
ORDER_KEYS = ("id", "artisan", "buyer", "itemId", "itemName", "qty", "note", "reply", "reagents",
              "createdAt")
BUYER_KEYS = ("name", "realm", "class", "level")
REAGENT_KEYS = ("itemId", "name", "qty")
NUMBER_KEYS = ("itemId", "qty", "createdAt", "updatedAt", "receivedAt", "level")
MAX_REAGENTS = 20  # a recipe has 6 at most: anything longer is not what the bot sends
# the player's own orders, as a buyer (bot 2026-11 and later): the addon's "My orders" tab
# receivedAt (bot 2026-11-24 and later): 0 = done, hand-over not confirmed yet (the addon's Received button)
PLACED_KEYS = ("id", "artisan", "artisanClass", "buyer", "status", "reason", "itemId", "itemName", "qty",
               "note", "reply", "reagents", "createdAt", "updatedAt", "receivedAt")
PLACED_STATUSES = ("pending", "done", "refused")

IDENTITY_RE = re.compile(r'\["orderIdentity"\]\s*=\s*\{')
BATTLETAG_RE = re.compile(r'\["battletag"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
CHARACTERS_RE = re.compile(r'\["characters"\]\s*=\s*\{')
UPDATED_RE = re.compile(r'\["updated"\] = -?\d+')
INTERFACE_RE = re.compile(r"^##\s*Interface\s*:\s*(.+?)\s*$", re.MULTILINE)


# --- what the bot is asked -------------------------------------------------------------------

def orders_url(url):
    """The connection code's URL with its last path segment replaced by "orders"
    (https://bot/shamewall/deaths -> https://bot/shamewall/orders)."""
    parts = urllib.parse.urlsplit(url)
    base = parts.path.rstrip("/").rsplit("/", 1)[0]
    return urllib.parse.urlunsplit((parts.scheme, parts.netloc, base + "/orders", "", ""))


def request_url(url, battletag, chars):
    query = urllib.parse.urlencode({"battletag": battletag or "", "chars": ",".join(chars)})
    return f"{orders_url(url)}?{query}"


def _block(text, start):
    """The text of the Lua table opened just before start, up to its closing brace."""
    depth, pos, end = 1, start, len(text)
    while pos < end:
        c = text[pos]
        if c == '"':
            s = events.STRING_RE.match(text, pos)
            pos = s.end() if s else pos + 1
            continue
        if c == "-" and text.startswith("--", pos):
            nl = text.find("\n", pos)
            pos = end if nl < 0 else nl
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start:pos]
        pos += 1
    return text[start:]


def read_identity(text):
    """WallOfShameForeverDB.orderIdentity: (battletag, ["Name-Realm", ...]), or None."""
    m = IDENTITY_RE.search(text)
    if not m:
        return None
    block = _block(text, m.end())
    tag = BATTLETAG_RE.search(block)
    chars = []
    c = CHARACTERS_RE.search(block)
    if c:
        chars = [events._unescape(s) for s in events.STRING_RE.findall(_block(block, c.end()))]
    return (events._unescape(tag.group(1)) if tag else ""), [ch for ch in chars if ch]


def group_identities(identities):
    """[(battletag, chars)] -> {battletag: sorted chars}. A character known with a battletag
    is not also asked for without one."""
    groups = {}
    for tag, chars in identities:
        groups.setdefault(tag or "", set()).update(chars)
    tagged = set().union(*(chars for tag, chars in groups.items() if tag))
    if "" in groups:
        groups[""] -= tagged
    return {tag: sorted(chars) for tag, chars in groups.items() if chars or tag}


# --- what the bot answers --------------------------------------------------------------------

def _clean(value, number):
    if number:
        if isinstance(value, bool):
            return None
        if isinstance(value, (int, float)):
            return int(value) if math.isfinite(value) else None
        if isinstance(value, str):  # a number as text becomes a number, other text is kept
            return value if events._int(value) is None else events._int(value)
        return None
    return value if isinstance(value, str) else (None if value is None else str(value))


def clean_orders(data):
    """The "orders" of a reply, keeping only the known fields with the right types; None when the
    reply is not what the bot sends."""
    if not isinstance(data, dict) or not isinstance(data.get("orders"), list):
        return None
    orders = []
    for raw in data["orders"]:
        if not isinstance(raw, dict) or raw.get("id") in (None, ""):
            continue
        order = {}
        for key in ORDER_KEYS:
            if key == "buyer":
                buyer = raw.get("buyer") if isinstance(raw.get("buyer"), dict) else {}
                order["buyer"] = {k: _clean(buyer.get(k), k in NUMBER_KEYS) for k in BUYER_KEYS}
            elif key == "reagents":
                order["reagents"] = _clean_reagents(raw.get("reagents"))
            else:
                order[key] = _clean(raw.get(key), key in NUMBER_KEYS)
        orders.append(order)
    return orders


def _clean_reagents(reagents):
    """Materials of the whole order (bot 2026-11 and later); none from an older bot."""
    if not isinstance(reagents, list):
        return []
    return [{k: _clean(r.get(k), k in NUMBER_KEYS) for k in REAGENT_KEYS}
            for r in reagents[:MAX_REAGENTS]
            if isinstance(r, dict) and isinstance(_clean(r.get("itemId"), True), int)]


def clean_placed(data):
    """The "placed" of a reply (the player's own orders as a buyer), same checks as the orders; [] from
    a bot that does not send them."""
    raw_list = data.get("placed") if isinstance(data, dict) else None
    if not isinstance(raw_list, list):
        return []
    placed = []
    for raw in raw_list:
        if not isinstance(raw, dict) or raw.get("id") in (None, "") or raw.get("status") not in PLACED_STATUSES:
            continue
        order = {key: _clean(raw.get(key), key in NUMBER_KEYS) for key in PLACED_KEYS if key != "reagents"}
        order["reagents"] = _clean_reagents(raw.get("reagents"))
        placed.append(order)
    return placed


# the addon's « Bagarre club » window (addon 0.7.0): titles, achievements, activities, bank goal and
# challenges of the player, already worded by the bot. Kept as it comes, within these limits.
HUB_MAX_DEPTH = 4
HUB_MAX_ITEMS = 12
HUB_MAX_TEXT = 200
HUB_KEY_RE = re.compile(r"[A-Za-z][A-Za-z0-9_]{0,30}")


def clean_hub(data):
    """The "hub" of a reply: nested dicts and lists of strings, numbers and booleans, cut to sane sizes;
    None when the bot sends none (older bot, or a player it does not know)."""
    def clean(value, depth):
        if isinstance(value, (bool, int, float)):
            return value
        if isinstance(value, str):
            return value[:HUB_MAX_TEXT]
        if depth >= HUB_MAX_DEPTH:
            return None
        if isinstance(value, dict):
            out = {}
            for k, v in list(value.items())[:40]:
                if isinstance(k, str) and HUB_KEY_RE.fullmatch(k):
                    v = clean(v, depth + 1)
                    if v is not None:
                        out[k] = v
            return out
        if isinstance(value, list):
            return [v for v in (clean(v, depth + 1) for v in value[:HUB_MAX_ITEMS]) if v is not None]
        return None
    hub = data.get("hub") if isinstance(data, dict) else None
    return clean(hub, 0) if isinstance(hub, dict) else None


def merge(order_lists):
    """One list, each order once, oldest first (then by id): the same orders give the same file."""
    by_id = {}
    for orders in order_lists:
        for order in orders:
            by_id.setdefault(str(order["id"]), order)
    return sorted(by_id.values(), key=lambda o: (
        o["createdAt"] if isinstance(o["createdAt"], int) else 0, str(o["createdAt"]), str(o["id"])))


# --- the file the addon reads ----------------------------------------------------------------

def lua_string(s):
    """A Lua string literal: quotes, backslashes and control characters escaped (UTF-8 kept)."""
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append(f"\\{ord(ch):03d}")
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def lua_value(value, indent=""):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return lua_string(value)
    inner = indent + "\t"
    if isinstance(value, dict):
        items = [f'{inner}[{lua_string(str(k))}] = {lua_value(v, inner)},'
                 for k, v in value.items() if v is not None]
    else:
        items = [f"{inner}{lua_value(v, inner)}," for v in value]
    return "{\n" + "\n".join(items) + "\n" + indent + "}" if items else "{}"


def lua_file(orders, updated, placed=(), hub=None):
    """orders: to craft (artisan side); placed: the player's own (buyer side, "My orders" tab);
    hub: the tabs of the addon's « Bagarre club » window (titles, activities, goals), when the bot sends it."""
    return ("-- Written by the Wall of Shame Forever companion: craft orders for the addon.\n"
            "-- Rewritten when the orders change; edits here are lost.\n"
            f"{GLOBAL} = {{\n"
            f'\t["updated"] = {int(updated)},\n'
            f'\t["orders"] = {lua_value(orders, chr(9))},\n'
            f'\t["placed"] = {lua_value(list(placed), chr(9))},\n'
            + (f'\t["hub"] = {lua_value(hub, chr(9))},\n' if hub else "")
            + "}\n")


def toc_file(interface):
    return (f"## Interface: {interface}\n"
            "## Title: Wall of Shame Forever - Commandes\n"
            "## Notes: Written by the companion: craft orders for the addon\n"
            f"{LUA_FILE}\n")


def addon_interface(game_dir):
    """The "## Interface:" of the WallOfShameForever addon of that game folder."""
    try:
        with open(os.path.join(game_dir, wowpath.ADDON_TOC), encoding="utf-8-sig", errors="replace") as f:
            m = INTERFACE_RE.search(f.read())
    except OSError:
        return DEFAULT_INTERFACE
    return m.group(1) if m else DEFAULT_INTERFACE


def _read(path):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()
    except (OSError, UnicodeDecodeError):
        return None


def _write_if_changed(path, text, same=lambda a, b: a == b):
    """Temp file then replace, so the addon never reads half a file. False when unchanged."""
    old = _read(path)
    if old is not None and same(old, text):
        return False
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def _without_updated(text):
    return UPDATED_RE.sub('["updated"] = 0', text)


def write_orders(game_dir, orders, now=None, placed=(), hub=None):
    """Writes the orders addon in that game folder (only where WallOfShameForever is installed).
    True when a file was written."""
    if not wowpath.has_addon(game_dir):
        return False
    folder = os.path.join(game_dir, "Interface", "AddOns", FOLDER)
    os.makedirs(folder, exist_ok=True)
    toc = _write_if_changed(os.path.join(folder, TOC_FILE), toc_file(addon_interface(game_dir)))
    lua = _write_if_changed(os.path.join(folder, LUA_FILE), lua_file(orders, now or time.time(), placed, hub),
                            same=lambda a, b: _without_updated(a) == _without_updated(b))
    return toc or lua


# --- polling ---------------------------------------------------------------------------------

class Orders:
    """Asks the bot for the pending orders at startup, then every POLL_INTERVAL, while there is a
    connection code. No notification: log lines only, and only when something changes.

    poll() is called from the main loop and never waits: the request and the files run in a
    background thread, one at a time (a slow bot must not delay the strip, on screen for 3 s).
    The state shared with that thread is behind self.lock."""

    def __init__(self, log):
        self.log = log
        self.lock = threading.Lock()
        self.seen = set()       # (battletag, "Name-Realm") from the events
        self.next_poll = 0.0
        self.code = None        # the code of the last poll: a new one is asked at once
        self.last_error = None  # logged once until it changes
        self.count = None       # orders in the last file written
        self.thread = None

    def saw(self, ev):
        """An event of this player (outbox or strip): one of their characters."""
        if ev.get("name") and ev.get("realm"):
            with self.lock:
                self.seen.add((ev.get("battletag") or "", f"{ev['name']}-{ev['realm']}"))

    def identities(self, texts):
        found = [i for i in map(read_identity, texts) if i]
        with self.lock:
            found += [(tag, [char]) for tag, char in self.seen]
        return group_identities(found)

    def poll(self, sender, paths, game_dirs, now=None):
        """Starts a poll in the background when one is due; returns its thread, or None."""
        now = now or time.time()
        if not sender.url or not game_dirs:
            return None
        with self.lock:
            if self.thread and self.thread.is_alive():
                return None
            if sender.code != self.code:
                self.code, self.next_poll, self.last_error = sender.code, 0.0, None
            if now < self.next_poll:
                return None
            self.next_poll = now + POLL_INTERVAL
            self.thread = threading.Thread(
                target=self._run, args=(sender.code, sender.url, sender.key, list(paths), list(game_dirs), now),
                name="orders", daemon=True)
            thread = self.thread
        thread.start()
        return thread

    def _run(self, code, url, key, paths, game_dirs, now):
        try:
            self._fetch_and_write(code, url, key, paths, game_dirs, now)
        except Exception as e:  # never kill the companion for orders
            self._error(f"orders: error, kept the last ones: {e!r}")

    def _fetch_and_write(self, code, url, key, paths, game_dirs, now):
        texts = list(filter(None, map(_read_lossy, paths)))
        groups = self.identities(texts)
        if not groups:
            return self._error("orders: no character known yet (log in once with the addon)")
        results, placed_lists, hub = [], [], None
        for tag, chars in groups.items():
            try:
                r = requests.get(request_url(url, tag, chars),
                                 headers={"Authorization": f"Bearer {key}",
                                          **wowpath.version_header(game_dirs)}, timeout=15)
            except requests.RequestException as e:
                return self._error(f"orders: request failed, kept the last ones: {e}")
            if r.status_code == 401:
                with self.lock:
                    if self.code == code:  # a new code meanwhile is asked at once
                        self.next_poll = now + REFUSED_RETRY
                return self._error("orders: the bot refused the connection code, asked again in "
                                   "an hour or with a new code")
            if r.status_code != 200:
                return self._error(f"orders: HTTP {r.status_code}, kept the last ones")
            try:
                orders = clean_orders(r.json())
            except ValueError:
                orders = None
            if orders is None:
                return self._error("orders: unexpected reply from the bot, kept the last ones")
            results.append(orders)
            placed_lists.append(clean_placed(r.json()))
            hub = hub or clean_hub(r.json())  # the first account the bot knows
        with self.lock:
            self.last_error = None
        orders = merge(results)
        placed = merge(placed_lists)
        written = False
        for game_dir in game_dirs:
            try:
                written = write_orders(game_dir, orders, now, placed, hub) or written
            except OSError as e:
                self.log(f"orders: could not write them to {game_dir}: {e}")
        with self.lock:
            first, self.count = self.count is None, len(orders)
        if written or first:
            self.log(f"orders: {len(orders)} pending, {len(placed)} placed, for "
                     f"{sum(map(len, groups.values()))} character(s)"
                     + (", written for the addon" if written else ", unchanged"))

    def _error(self, message):
        with self.lock:
            new, self.last_error = message != self.last_error, message
        if new:
            self.log(message)


def _read_lossy(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None
