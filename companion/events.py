"""Events (deaths, levels): payload format shared with the addon, and the SavedVariables outbox."""

import re

# "2|<kind>|<fields>", see the outbox section of the addon
FIELDS = {
    "D": ("death", ["id", "name", "realm", "guild", "level", "class", "zone", "killer", "killerLevel",
                    "time", "battletag"]),
    "L": ("level", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "up", "zone"]),
    # leaderboard: duel won against a guildmate, killing blow on a player of the other faction
    "W": ("duel", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "opponent", "zone"]),
    "K": ("kill", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "victim",
                   "victimLevel", "victimClass", "zone"]),
}
NUMBERS = ("level", "killerLevel", "victimLevel", "time")

LUA_ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
OUTBOX_RE = re.compile(r'\["outbox"\]\s*=\s*\{')
CONNECTION_RE = re.compile(r'\["connection"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
SKIP_RE = re.compile(r'(?:\s|,|--[^\n]*)*')


def parse_payload(payload, source):
    parts = payload.split("|")
    if len(parts) < 2 or parts[0] != "2" or parts[1] not in FIELDS:
        return None
    kind, fields = FIELDS[parts[1]]
    if len(parts) != 2 + len(fields):
        return None
    ev = {"type": kind, **dict(zip(fields, parts[2:]))}
    for key in NUMBERS:
        if key in ev:
            ev[key] = int(ev[key]) if re.fullmatch(r"-?\d+", ev[key]) else None
    if kind == "death":
        ev["killer"] = ev["killer"] or None
    elif kind == "level":
        ev["up"] = ev["up"] == "1"  # real level-up (posted), not the login snapshot
    ev["test"] = ev["id"].startswith("test:")
    ev["source"] = source
    return ev


def _unescape(s):
    return re.sub(r"\\(.)", lambda m: LUA_ESCAPES.get(m.group(1), m.group(1)), s)


def read_connection(text):
    """ShameWallForeverDB.connection: the bot's code, copied by the addon from the guild info."""
    m = CONNECTION_RE.search(text)
    return _unescape(m.group(1)) if m else None


def read_outbox(text):
    """Payload strings of ShameWallForeverDB.outbox in a SavedVariables file."""
    m = OUTBOX_RE.search(text)
    if not m:
        return []
    pos, payloads = m.end(), []
    while True:
        pos = SKIP_RE.match(text, pos).end()
        s = STRING_RE.match(text, pos)
        if not s:
            return payloads
        payloads.append(_unescape(s.group(1)))
        pos = s.end()
