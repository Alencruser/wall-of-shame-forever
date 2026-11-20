"""Follow time (Follow.lua), run with lupa: a session from AUTOFOLLOW_BEGIN to AUTOFOLLOW_END for a guild
member only, a strip every 5 minutes and at the end, one outbox entry per session, logout closes the
session without a strip, a busy screen delays the periodic strip; and the companion's parsing."""

import os
import unittest

import events
from test_addon_orders import ADDON, Addon

TARGET = "Johnny Teitelbaum"


class FollowTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        load = self.a.lua.eval("function(src, ns) assert(loadstring(src, 'Follow.lua'))('WallOfShameForever', ns) end")
        with open(os.path.join(ADDON, "Follow.lua"), encoding="utf-8") as f:
            load(f.read(), self.a.ns)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.a.db.members[TARGET] = self.a.to_lua({"level": 20, "deaths": 0, "inGuild": True})
        self.state = self.a.g.STATE

    def wait(self, seconds):
        self.state.now = self.state.now + seconds
        self.a.g.RunTimers()

    def outbox(self):
        return [events.parse_payload(p, "savedvariables") for p in self.a.lua_list(self.a.db.outbox)
                if p.split("|")[1] == "F"]

    def strips(self):
        return [events.parse_payload(p, "realtime") for p in self.a.strips]

    def test_session_with_periodic_strip_and_end(self):
        start = self.state.now
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.wait(300)
        self.assertEqual(len(self.strips()), 1)
        tick = self.strips()[0]
        self.assertEqual((tick["type"], tick["target"], tick["start"], tick["seconds"], tick["done"]),
                         ("follow", TARGET, start, 300, False))
        self.wait(120)
        self.a.g.Fire("AUTOFOLLOW_END")
        end = self.strips()[-1]
        self.assertEqual((end["seconds"], end["done"]), (420, True))
        self.assertNotEqual(tick["id"], end["id"])  # the companion skips an id it already saw
        out = self.outbox()
        self.assertEqual(len(out), 1)  # only the latest update of the session
        self.assertEqual((out[0]["seconds"], out[0]["done"]), (420, True))

    def test_no_tick_after_the_end(self):
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.state.now = self.state.now + 10
        self.a.g.Fire("AUTOFOLLOW_END")
        self.wait(300)
        self.assertEqual(len(self.strips()), 1)  # the end only

    def test_short_follow_counts(self):
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.state.now = self.state.now + 5
        self.a.g.Fire("AUTOFOLLOW_END")
        self.assertEqual(self.outbox()[0]["seconds"], 5)

    def test_stranger_not_counted(self):
        self.a.g.Fire("AUTOFOLLOW_BEGIN", "Zura Pepa")
        self.state.now = self.state.now + 60
        self.a.g.Fire("AUTOFOLLOW_END")
        self.assertEqual(self.outbox(), [])
        self.assertEqual(self.strips(), [])

    def test_former_member_not_counted(self):
        self.a.db.members[TARGET].inGuild = False
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.a.g.Fire("AUTOFOLLOW_END")
        self.assertEqual(self.outbox(), [])

    def test_new_target_closes_the_previous_session(self):
        self.a.db.members["Lex Orcist"] = self.a.to_lua({"inGuild": True})
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.state.now = self.state.now + 30
        self.a.g.Fire("AUTOFOLLOW_BEGIN", "Lex Orcist")
        self.state.now = self.state.now + 20
        self.a.g.Fire("AUTOFOLLOW_END")
        out = sorted((e["target"], e["seconds"]) for e in self.outbox())
        self.assertEqual(out, [("Johnny Teitelbaum", 30), ("Lex Orcist", 20)])

    def test_logout_closes_without_strip(self):
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.state.now = self.state.now + 90
        self.a.g.Fire("PLAYER_LOGOUT")
        self.assertEqual(self.strips(), [])
        self.assertEqual((self.outbox()[0]["seconds"], self.outbox()[0]["done"]), (90, True))

    def test_busy_screen_delays_the_strip(self):
        self.a.lua.execute("STATE.busy = true")
        self.a.ns.StripBusy = self.a.lua.eval("function() return STATE.busy end")
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.wait(300)
        self.assertEqual(self.strips(), [])
        self.a.lua.execute("STATE.busy = false")
        self.wait(4)  # the stub runs every pending timer at once: the next tick shows too
        self.assertEqual(self.strips()[0]["seconds"], 300)

    def test_nothing_without_discord_sharing(self):
        self.a.db.discord = False
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.wait(300)
        self.a.g.Fire("AUTOFOLLOW_END")
        self.assertEqual(self.outbox(), [])
        self.assertEqual(self.strips(), [])

    def test_payload_fits_the_strip(self):
        self.a.g.Fire("AUTOFOLLOW_BEGIN", TARGET)
        self.state.now = self.state.now + 99999
        self.a.g.Fire("AUTOFOLLOW_END")
        self.assertLessEqual(len(self.a.strips[-1]), 240)


class ParseFollowTest(unittest.TestCase):
    def test_bad_numbers_rejected(self):
        self.assertIsNone(events.parse_payload("2|F|a:F:1:5|A|R|G|20|MAGE|6|B#1|T|x|5|1", "realtime"))
        self.assertIsNone(events.parse_payload("2|F|a:F:1:5|A|R|G|20|MAGE|6|B#1||1|5|1", "realtime"))


if __name__ == "__main__":
    unittest.main()
