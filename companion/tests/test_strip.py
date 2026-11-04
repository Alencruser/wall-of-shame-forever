"""Round trip: the addon's Lua encoder (run with lupa) -> rendered screen -> Python decoder."""

import os
import random
import sys
import unittest

import lupa
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import events  # noqa: E402
import strip  # noqa: E402

LUA_FILE = os.path.join(os.path.dirname(__file__), "..", "..", "WallOfShameForever", "DeathStrip.lua")


def lua_encoder():
    lua = lupa.LuaRuntime()
    ns = lua.table()
    with open(LUA_FILE, encoding="utf-8") as f:
        lua.eval("function(src, ns) assert(load(src))('WallOfShameForever', ns) end")(f.read(), ns)
    return ns.EncodeStrip


def render(blocks, size=(800, 600), gamma=1.0, noise=0, seed=0, block_px=strip.BLOCK, origin=(0, 0)):
    """Draw the blocks like the addon does, on a random 'game' background (origin: where the strip
    starts, e.g. under a macOS title bar; block_px: block size in the image's pixels)."""
    rnd = random.Random(seed)
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(size[1]):
        for x in range(size[0]):
            px[x, y] = (rnd.randrange(256), rnd.randrange(256), rnd.randrange(256))
    for i, block in enumerate(blocks):
        col, row = i % strip.COLS, i // strip.COLS
        color = tuple(
            max(0, min(255, round(255 * (level / 3) ** gamma) + rnd.randint(-noise, noise)))
            for level in block
        )
        for dy in range(block_px):
            for dx in range(block_px):
                px[origin[0] + col * block_px + dx, origin[1] + row * block_px + dy] = color
    return img


def to_py(lua_blocks):
    return [tuple(lua_blocks[i][k] for k in (1, 2, 3)) for i in range(1, len(lua_blocks) + 1)]


class StripTest(unittest.TestCase):
    encode = staticmethod(lua_encoder())

    def roundtrip(self, payload, **kw):
        img = render(to_py(self.encode(payload)), **kw)
        return strip.decode(img)

    def test_death_payload(self):
        payload = ("2|D|Grumbar-Forever:1762167000|Grumbar|Forever|Les Immortels|12|WARRIOR|Elwynn Forest"
                   "|Hogger|11|1762167000|Pierre#1234")
        decoded, height = self.roundtrip(payload)
        self.assertEqual(decoded, payload)
        self.assertLessEqual(height, strip.MAX_HEIGHT)
        ev = events.parse_payload(decoded, "realtime")
        self.assertEqual((ev["type"], ev["name"], ev["level"], ev["class"], ev["killer"], ev["killerLevel"],
                          ev["battletag"]), ("death", "Grumbar", 12, "WARRIOR", "Hogger", 11, "Pierre#1234"))

    def test_utf8_and_gamma_and_noise(self):
        payload = "2|D|Éloïse-Forever:1|Éloïse|Forever||5|MAGE|Forêt d'Elwynn|Kobold vermine|-1|1|"
        decoded, _ = self.roundtrip(payload, gamma=1.6, noise=12, seed=3)
        self.assertEqual(decoded, payload)
        self.assertEqual(events.parse_payload(decoded, "realtime")["killerLevel"], -1)

    def test_max_length(self):
        payload = "x" * strip.MAX_PAYLOAD
        decoded, height = self.roundtrip(payload)
        self.assertEqual(decoded, payload)
        self.assertLessEqual(height, strip.MAX_HEIGHT)

    def test_macos_offset_and_retina(self):
        payload = "2|D|Thrall-Forever:1|Thrall|Forever||12|SHAMAN|Durotar|Boar|4|1|"
        blocks = to_py(self.encode(payload))
        # capture at 1x of a Retina screen (2 px per block), and at 2x (8 px), under a 28 pt title bar
        for block, origin in ((2, (3, 28)), (4, (0, 56)), (8, (6, 56))):
            img = render(blocks, size=(strip.COLS * block + 20, 170), block_px=block, origin=origin, seed=block)
            found = strip.locate(img, block, 10, 60)
            self.assertIsNotNone(found, (block, origin))
            decoded, bottom = found
            self.assertEqual(decoded, payload)
            rows = -(-len(blocks) // strip.COLS)
            self.assertEqual(bottom, origin[1] + rows * block)

    def test_no_strip(self):
        self.assertIsNone(strip.decode(render([], seed=5)))

    def test_corrupted_block(self):
        blocks = to_py(self.encode("2|D|a|b|c|d|1|MAGE|z|k|1|1|"))
        blocks[12] = tuple((v + 1) % 4 for v in blocks[12])
        self.assertIsNone(strip.decode(render(blocks)))


class OutboxTest(unittest.TestCase):
    def test_read_outbox(self):
        text = (
            'WallOfShameForeverDB = {\n["sound"] = true,\n["outbox"] = {\n'
            '"2|D|A-R:1|A|R|G|3|ROGUE|Zone \\"Q\\"|Wolf|2|1|", -- [1]\n'
            '"2|D|A-R:2|A|R|G|4|ROGUE|Zone|Falling||2|", -- [2]\n'
            '"2|L|A-R:L4|A|R|G|4|ROGUE|2|A#1|1|Durotar", -- [3]\n},\n["log"] = {\n"x",\n},\n}\n'
        )
        payloads = events.read_outbox(text)
        self.assertEqual(len(payloads), 3)
        self.assertEqual(events.parse_payload(payloads[0], "savedvariables")["zone"], 'Zone "Q"')
        ev = events.parse_payload(payloads[1], "savedvariables")
        self.assertEqual((ev["killer"], ev["killerLevel"]), ("Falling", None))
        lv = events.parse_payload(payloads[2], "savedvariables")
        self.assertEqual((lv["type"], lv["level"], lv["class"], lv["battletag"], lv["up"], lv["zone"]),
                         ("level", 4, "ROGUE", "A#1", True, "Durotar"))

    def test_leaderboard_payloads(self):
        duel = events.parse_payload("2|W|A-R:W1.1|A|R|G|30|ROGUE|1|A#1|Thrall|Durotar", "savedvariables")
        self.assertEqual((duel["type"], duel["opponent"], duel["zone"]), ("duel", "Thrall", "Durotar"))
        kill = events.parse_payload("2|K|A-R:K1.2|A|R|G|30|ROGUE|1|A#1|Garrosh|31|WARRIOR|Barrens",
                                    "savedvariables")
        self.assertEqual((kill["type"], kill["victim"], kill["victimLevel"], kill["victimClass"], kill["zone"]),
                         ("kill", "Garrosh", 31, "WARRIOR", "Barrens"))
        self.assertIsNone(events.parse_payload("2|K|A-R:K1|A|R|G|30|ROGUE|1|A#1|Garrosh||", "savedvariables"))

    def test_rejects_old_or_broken_payloads(self):
        for p in ["1|a|b|c|d|1|MAGE|z|k|1|1", "2|X|a", "2|L|too|few", ""]:
            self.assertIsNone(events.parse_payload(p, "savedvariables"), p)

    def test_read_connection(self):
        self.assertEqual(events.read_connection('X = {\n["connection"] = "swf1.abc_-1",\n}'), "swf1.abc_-1")
        self.assertIsNone(events.read_connection('X = {\n["sound"] = true,\n}'))


if __name__ == "__main__":
    unittest.main()
