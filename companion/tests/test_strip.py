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

    def test_macos_display_p3_colours(self):
        """A Mac screen shows the strip in its Display P3 profile: pure colours bleed into each
        other (seen on a 14-inch MacBook Pro: sRGB magenta 255,0,255 captured as 234,51,247).
        The raw decoder rejects it, the P3 -> sRGB conversion brings it back."""
        payload = "2|W|Moi-Forever:W1793832149.1|Moi|Forever||12|WARRIOR|1793832149|Moi#1234|Pote|Dun Morogh"
        img = render(to_py(self.encode(payload)), size=(260, 120))
        # sRGB -> Display P3, what macOS does on screen (inverse of strip.P3_TO_SRGB)
        srgb_to_p3 = (0.8225, 0.1774, 0.0, 0.0, 0.0332, 0.9669, 0.0, 0.0, 0.0171, 0.0724, 0.9108, 0.0)
        lin = [round(strip._to_linear(i) * 255) for i in range(256)] * 3
        gam = [round(strip._to_srgb(i / 255) * 255) for i in range(256)] * 3
        on_mac = img.point(lin).convert("RGB", srgb_to_p3).point(gam)
        magenta = on_mac.getpixel((4 * 4 + 2, 2))  # 5th block: first magic block, (3, 0, 3)
        self.assertGreater(magenta[1], 30)  # green leaked into the magenta, as on the real Mac
        self.assertIsNone(strip.decode(on_mac))
        decoded, _ = strip.decode(strip.from_display_p3(on_mac))
        self.assertEqual(decoded, payload)

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

    def window_with_strip(self, payload, position, width, height, block, origin=(0, 0), seed=0, rounding=0):
        """A game window (capture pixels) with the strip anchored like the addon does: a frame of
        WIDTH x MAX_HEIGHT physical pixels at that point of the game area, which starts at
        origin (macOS title bar). rounding: how the game rounds a centered frame (0 down, 1 up)."""
        blocks = to_py(self.encode(payload))
        sw, sh = strip.COLS * block, -(-strip.MAX_BLOCKS // strip.COLS) * block
        game_w, game_h = width - origin[0], height - origin[1]
        col, row = strip.POSITIONS[position]
        x = origin[0] + (0, (game_w - sw + rounding) // 2, game_w - sw)[col]
        y = origin[1] + (0, (game_h - sh + rounding) // 2, game_h - sh)[row]
        return render(blocks, size=(width, height), block_px=block, origin=(x, y), seed=seed), (x, y)

    def test_every_position_windows(self):
        """Windows: client area in real pixels. Odd sizes and both roundings for the centered ones."""
        payload = "2|L|Chamy Chan-Realm:L13|Chamy Chan|Realm||13|MAGE|1|A#1|1|Duskwood"
        for size in ((640, 400), (641, 401)):
            for rounding in (0, 1):
                for i, position in enumerate(strip.POSITIONS):
                    img, (x, y) = self.window_with_strip(payload, position, *size, strip.BLOCK, seed=i,
                                                         rounding=rounding)
                    area = {"left": 0, "top": 0, "width": size[0], "height": size[1], "exact": True, "scale": 1.0}
                    capture = lambda r: img.crop((r["left"], r["top"], r["left"] + r["width"], r["top"] + r["height"]))
                    found = strip.read(capture, area, position)
                    self.assertIsNotNone(found, (size, rounding, position))
                    decoded, box, per_unit = found
                    self.assertEqual(decoded, payload)
                    self.assertEqual(per_unit, 1.0)
                    self.assertTrue(box[0] <= x + 2 and box[1] <= y + 2, (position, box, x, y))
                    # nowhere else: another position never reads this strip
                    for other in strip.POSITIONS:
                        if other != position:
                            self.assertIsNone(strip.read(capture, area, other), (position, other))

    def test_every_position_macos_retina(self):
        """macOS: window bounds in points with a 28 pt title bar, Retina screen (2 physical pixels per
        point) captured at 2x: the strip, drawn in physical pixels, has 4 px blocks in the capture."""
        payload = "2|D|Tarkos Moss-Realm:1|Tarkos Moss|Realm||23|WARRIOR|Duskwood|Hogger|11|1|"
        width_pt, height_pt, title_pt = 300, 160, 28
        for i, position in enumerate(strip.POSITIONS):
            img, _ = self.window_with_strip(payload, position, width_pt * 2, height_pt * 2, strip.BLOCK,
                                            origin=(0, title_pt * 2), seed=i)
            area = {"left": 0, "top": 0, "width": width_pt, "height": height_pt, "exact": False, "scale": 2.0}
            capture = lambda r: img.crop((r["left"] * 2, r["top"] * 2, (r["left"] + r["width"]) * 2,
                                          (r["top"] + r["height"]) * 2))
            found = strip.read(capture, area, position, 8, 48, display_p3=True)
            self.assertIsNotNone(found, position)
            self.assertEqual(found[0], payload)
            self.assertEqual(found[2], 2.0)

    def test_hide_strip_in_screenshot(self):
        """The screenshot never shows the strip: cut at the top and bottom edges, covered elsewhere."""
        payload = "2|W|Moi-Forever:W1.1|Moi|Forever||12|WARRIOR|1|Moi#1234|Pote|Dun Morogh"
        for i, position in enumerate(strip.POSITIONS):
            img, _ = self.window_with_strip(payload, position, 400, 240, strip.BLOCK, seed=i)
            area = {"left": 0, "top": 0, "width": 400, "height": 240, "exact": True, "scale": 1.0}
            capture = lambda r: img.crop((r["left"], r["top"], r["left"] + r["width"], r["top"] + r["height"]))
            _, box, _ = strip.read(capture, area, position)
            shot = strip.hide(img, box, position)
            self.assertIsNone(strip.find(shot, strip.BLOCK, range(shot.width - strip.WIDTH + 1),
                                         range(shot.height)), position)
            row = strip.POSITIONS[position][1]
            if row == 1:
                self.assertEqual(shot.size, img.size)  # covered, the screenshot keeps its size
            else:
                self.assertGreater(shot.height, img.height - strip.MAX_HEIGHT - 4)

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

    def test_killing_blow_on_the_strip_sent_with_screenshot(self):
        import wallofshame_companion as app

        payload = "2|K|A-R:K1.2|A|R|G|30|ROGUE|1|A#1|?|||Ashenvale"
        pushed = []

        class Sender:
            def push(self, ev, jpeg):
                pushed.append((ev, jpeg))

        saved = (app.osplat.wow_window, app.read_strip, app.grab)
        try:
            app.osplat.wow_window = lambda: {"exact": True}
            app.read_strip = lambda sct, area: (payload, (0, 0, 10, 10), "TOPLEFT")
            app.grab = lambda sct, area: Image.new("RGB", (100, 100))
            state = set()
            app.check_strip(None, state, Sender())
            app.check_strip(None, state, Sender())  # same strip still on screen: sent once
        finally:
            app.osplat.wow_window, app.read_strip, app.grab = saved
        self.assertEqual(len(pushed), 1)
        ev, jpeg = pushed[0]
        self.assertEqual((ev["type"], ev["victim"], ev["source"]), ("kill", "?", "realtime"))
        self.assertTrue(jpeg)

    def test_rejects_old_or_broken_payloads(self):
        for p in ["1|a|b|c|d|1|MAGE|z|k|1|1", "2|X|a", "2|L|too|few", ""]:
            self.assertIsNone(events.parse_payload(p, "savedvariables"), p)

    def test_read_connection(self):
        self.assertEqual(events.read_connection('X = {\n["connection"] = "swf1.abc_-1",\n}'), "swf1.abc_-1")
        self.assertIsNone(events.read_connection('X = {\n["sound"] = true,\n}'))


if __name__ == "__main__":
    unittest.main()
