"""Connection code: which bot to send to, and the guild key that bot accepts.

The bot hands it out on Discord (see docs/bot-api.md): "swf1." + base64url(JSON {"url", "key"}).
Nothing about a bot is in this repository: without a code from your guild, the companion
cannot send anything.
"""

import base64
import json
import re

PREFIX = "swf1."
LOCAL_RE = re.compile(r"http://(localhost|127\.0\.0\.1)(:\d+)?/")


def encode(url, key):
    raw = json.dumps({"url": url, "key": key}, separators=(",", ":")).encode()
    return PREFIX + base64.urlsafe_b64encode(raw).decode().rstrip("=")


def decode(code):
    """(url, key), or None when the code is not valid."""
    code = (code or "").strip()
    if not code.startswith(PREFIX):
        return None
    data = code[len(PREFIX):]
    try:
        info = json.loads(base64.urlsafe_b64decode(data + "=" * (-len(data) % 4)))
    except ValueError:
        return None
    if not isinstance(info, dict):
        return None
    url, key = info.get("url"), info.get("key")
    if not (isinstance(url, str) and isinstance(key, str) and key):
        return None
    # https only, except a bot running on this PC for tests
    if not (url.startswith("https://") or LOCAL_RE.match(url)):
        return None
    return url, key
