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
    # professions of the character, read when a profession window is opened (see QueueProfessions)
    "P": ("professions", ["id", "name", "realm", "guild", "level", "class", "time", "battletag",
                          "professions"]),
    # craft order ticked done or refused by the artisan in game (orders.py fetches the orders), or
    # received by the buyer (addon 0.6.7, "My orders" tab)
    # technical report for the bot's debug.jsonl (outbox only, never posted): topic + free details
    "X": ("debug", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "topic", "details"]),
    "O": ("order", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "order",
                    "status", "reason"]),
    # guild bank money log, read when the bank opens (see GuildBank.lua); the bot merges the readings
    "B": ("banklog", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "money",
                      "lines"]),
    # time spent following a guildmate (see Follow.lua): a strip every 5 minutes and at the end, the
    # end in the outbox too; the bot keeps the highest seconds per follower and start
    "F": ("follow", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "target", "start",
                     "seconds", "done"]),
    # guild item request (addon 0.8.0, "Demandes" tab): action new (item, qty, reward, note), take, drop
    # (someone takes care of it, or no longer) or close (by who asked); request: its id
    "R": ("request", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "action", "request",
                      "item", "qty", "reward", "note"]),
    # sign-up to a guild activity from the game (addon 0.8.0): action join (role: tank, heal or dps for a
    # dungeon, else empty) or leave; activity: the id of its Discord card
    "A": ("activity", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "action", "activity",
                       "role"]),
    # the character's gear, stats and talents for the site's « Armurerie » (addon 0.9.0, Armory.lua); gear "off":
    # the player turned the option off, the bot hides the character
    "G": ("armory", ["id", "name", "realm", "guild", "level", "class", "time", "battletag", "race", "gear", "stats",
                     "talents"]),
}
NUMBERS = ("level", "killerLevel", "victimLevel", "time", "money", "start", "seconds", "item", "qty")
# give (addon 0.8.3): qty given, reward = mode (mail or hand), note = the gift's id; got / notgot: the asker
# confirms a gift (note = its id)
REQUEST_ACTIONS = ("new", "take", "drop", "close", "give", "got", "notgot")
GIFT_MODES = ("mail", "hand")
ORDER_STATUSES = ("done", "refused", "received", "cancelled")  # cancelled: by the buyer (addon 0.8.0)

LUA_ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}
STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
OUTBOX_RE = re.compile(r'\["outbox"\]\s*=\s*\{')
CONNECTION_RE = re.compile(r'\["connection"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
SKIP_RE = re.compile(r'(?:\s|,|--[^\n]*)*')


def _int(text):
    return int(text) if re.fullmatch(r"-?\d+", text or "") else None


def parse_professions(text):
    """"skillLine:level:max:name:recipes;..." -> list; recipes "id=color=name,..." (None: never opened,
    or a gathering profession). color: 0 orange, 1 yellow, 2 green, 3 grey (None: unknown)."""
    professions = []
    for entry in filter(None, (text or "").split(";")):
        parts = entry.split(":")
        if len(parts) != 5 or _int(parts[0]) is None:
            continue
        recipes = None
        if parts[4]:
            recipes = []
            for recipe in parts[4].split(","):
                fields = recipe.split("=")
                if len(fields) == 3 and _int(fields[0]) is not None:
                    recipes.append({"id": _int(fields[0]), "color": _int(fields[1]), "name": fields[2]})
        professions.append({"skillLine": _int(parts[0]), "level": _int(parts[1]), "max": _int(parts[2]),
                            "name": parts[3], "recipes": recipes})
    return professions


def parse_bank_lines(text):
    """"type:copper:years:months:days:hours:who;..." -> list, in the game's order (oldest first)."""
    lines = []
    for entry in filter(None, (text or "").split(";")):
        parts = entry.split(":")
        numbers = [_int(p) for p in parts[1:6]] if len(parts) == 7 else [None]
        if None in numbers or not parts[0] or not parts[6]:
            continue
        copper, years, months, days, hours = numbers
        lines.append({"type": parts[0], "who": parts[6], "copper": copper, "years": years,
                      "months": months, "days": days, "hours": hours})
    return lines


def _num(text):
    if re.fullmatch(r"-?\d+", text or ""):
        return int(text)
    if re.fullmatch(r"-?\d+\.\d+", text or ""):
        return float(text)
    return None


def parse_gear(text):
    """"slot=item.enchant.suffix.ilvl.quality;..." -> list (slots 1 to 19); quality None if unknown."""
    gear = []
    for entry in filter(None, (text or "").split(";")):
        slot, _, rest = entry.partition("=")
        parts = rest.split(".")
        if _int(slot) is None or not 1 <= _int(slot) <= 19 or len(parts) != 5:
            continue
        numbers = [_int(p) for p in parts[:4]]
        if None in numbers or numbers[0] <= 0:
            continue
        gear.append({"slot": _int(slot), "item": numbers[0], "enchant": numbers[1], "suffix": numbers[2],
                     "ilvl": numbers[3], "quality": _int(parts[4])})
    return gear


def parse_stats(text):
    """"key=value;..." -> dict of numbers (keys: letters and digits)."""
    stats = {}
    for entry in filter(None, (text or "").split(";")):
        key, _, value = entry.partition("=")
        if re.fullmatch(r"[a-zA-Z0-9]{1,12}", key) and _num(value) is not None:
            stats[key] = _num(value)
    return stats


def parse_talents(text):
    """"tree/points/spell.tier.column.rank.max.name,...;..." -> list of trees."""
    trees = []
    for entry in filter(None, (text or "").split(";")):
        parts = entry.split("/", 2)
        if len(parts) != 3 or _int(parts[1]) is None:
            continue
        talents = []
        for talent in filter(None, parts[2].split(",")):
            fields = talent.split(".", 5)
            numbers = [_int(f) for f in fields[:5]]
            if len(fields) != 6 or None in numbers:
                continue
            spell, tier, column, rank, max_rank = numbers
            talents.append({"spell": spell or None, "tier": tier, "column": column, "rank": rank, "max": max_rank,
                            "name": fields[5]})
        trees.append({"name": parts[0], "points": _int(parts[1]), "talents": talents})
    return trees


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
    elif kind == "professions":
        ev["professions"] = parse_professions(ev["professions"])
    elif kind == "order" and ev["status"] not in ORDER_STATUSES:
        return None
    elif kind == "follow":
        ev["done"] = ev["done"] == "1"
        if not ev["target"] or ev["start"] is None or ev["seconds"] is None:
            return None
    elif kind == "activity":
        if ev["action"] not in ("join", "leave") or not re.fullmatch(r"\d{5,25}", ev["activity"])                 or ev["role"] not in ("", "tank", "heal", "dps"):
            return None
    elif kind == "request":
        if ev["action"] not in REQUEST_ACTIONS or not re.fullmatch(r"[0-9a-zA-Z]{4,24}", ev["request"]):
            return None
        if ev["action"] == "new" and not (ev["item"] and ev["qty"] and 1 <= ev["qty"] <= 999):
            return None
        if ev["action"] == "give" and not (ev["qty"] and 1 <= ev["qty"] <= 999 and ev["reward"] in GIFT_MODES):
            return None
        if ev["action"] in ("give", "got", "notgot") and not re.fullmatch(r"[0-9a-zA-Z]{4,24}", ev["note"]):
            return None
    elif kind == "armory":
        ev["off"] = ev["gear"] == "off"
        ev["gear"] = [] if ev["off"] else parse_gear(ev["gear"])
        ev["stats"] = parse_stats(ev["stats"])
        ev["talents"] = parse_talents(ev["talents"])
        if not ev["off"] and not ev["gear"]:
            return None
    elif kind == "banklog":
        ev["lines"] = parse_bank_lines(ev["lines"])
        if not ev["lines"]:
            return None
    ev["test"] = ev["id"].startswith("test:")
    ev["source"] = source
    return ev


def _unescape(s):
    return re.sub(r"\\(.)", lambda m: LUA_ESCAPES.get(m.group(1), m.group(1)), s)


def read_connection(text):
    """WallOfShameForeverDB.connection: the bot's code, copied by the addon from the guild info."""
    m = CONNECTION_RE.search(text)
    return _unescape(m.group(1)) if m else None


def read_outbox(text):
    """Payload strings of WallOfShameForeverDB.outbox in a SavedVariables file."""
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
