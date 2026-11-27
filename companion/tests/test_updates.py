"""Out-of-date notices (Updates.lua, addon v0.9.3), run with lupa: a guildmate's newer version (H and S
messages) or the bot's latest versions in the companion's file are told once in chat; the companion writes
its own version in that file."""

import os
import unittest

import appinfo
import orders
from test_addon_orders import ADDON, Addon

STUBS = r"""
STATE.version = "v0.9.3"
C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return STATE.version end end }
C_ChatInfo = { SendAddonMessage = function(prefix, msg) table.insert(STATE.sent, msg) end,
               RegisterAddonMessagePrefix = function() end }
STATE.sent = {}
"""


class UpdatesTest(unittest.TestCase):
    def addon(self, file=None):
        a = Addon(raw_orders=file) if file is not None else Addon(orders=[])
        a.lua.execute(STUBS)
        load = a.lua.eval("function(src, ns) assert(loadstring(src, 'Updates.lua'))('WallOfShameForever', ns) end")
        with open(os.path.join(ADDON, "Updates.lua"), encoding="utf-8") as f:
            load(f.read(), a.ns)
        a.login()
        return a

    def chat(self, a):
        return [m for m in a.lua_list(a.g.STATE.chat) if "version" in m or "compagnon" in m]

    def test_compare(self):
        newer = self.addon().ns.Updates.Newer
        self.assertTrue(newer("0.10.0", "v0.9.9"))
        self.assertTrue(newer("v1.0.0", "0.9.3"))
        self.assertFalse(newer("0.9.3", "0.9.3"))
        self.assertFalse(newer("0.9.2", "0.9.3"))
        self.assertFalse(newer("", "0.9.3"))
        self.assertFalse(newer(None, "0.9.3"))

    def test_my_version_in_login_and_status_messages(self):
        a = self.addon()
        a.g.RunTimers()
        sent = a.lua_list(a.g.STATE.sent)
        self.assertIn("H|0.9.3", sent)
        self.assertTrue(any(m.startswith("S|") and m.endswith("|0.9.3") for m in sent))

    def test_guildmate_with_newer_version_told_once(self):
        a = self.addon()
        a.g.Fire("CHAT_MSG_ADDON", "WALLOFSHAME", "H|0.9.4", "GUILD", "Lex-Realm")
        a.g.Fire("CHAT_MSG_ADDON", "WALLOFSHAME", "S|30|Elwynn|WARRIOR|0|0.9.4", "GUILD", "Wiz-Realm")
        a.g.Fire("CHAT_MSG_ADDON", "WALLOFSHAME", "S|30|Elwynn|WARRIOR|0|0.9.2", "GUILD", "Old-Realm")
        a.g.Fire("CHAT_MSG_ADDON", "WALLOFSHAME", "S|30|Elwynn|WARRIOR|0", "GUILD", "Older-Realm")  # before v0.9.3
        told = self.chat(a)
        self.assertEqual(len(told), 1)
        self.assertIn("0.9.4", told[0])
        self.assertIn("0.9.3", told[0])

    def test_bot_latest_versions_from_the_companion_file(self):
        a = self.addon({"updated": 1, "orders": [], "companion": "0.8.4",
                        "hub": {"latest": {"addon": "0.9.5", "companion": "0.8.6"}}})
        a.g.RunTimers()
        told = self.chat(a)
        self.assertEqual(len(told), 2)
        self.assertIn("0.9.5", told[0])
        self.assertIn("0.8.6", told[1])
        self.assertIn("0.8.4", told[1])

    def test_up_to_date_says_nothing(self):
        a = self.addon({"updated": 1, "orders": [], "companion": "0.8.4",
                        "hub": {"latest": {"addon": "0.9.3", "companion": "0.8.4"}}})
        a.g.RunTimers()
        self.assertEqual(self.chat(a), [])

    def test_companion_without_its_version_is_at_most_0_8_3(self):
        a = self.addon({"updated": 1, "orders": [], "hub": {"latest": {"companion": "0.8.3"}}})
        a.g.RunTimers()
        self.assertEqual(self.chat(a), [])  # 0.8.3 wrote no version: maybe up to date
        a = self.addon({"updated": 1, "orders": [], "hub": {"latest": {"companion": "0.8.4"}}})
        a.g.RunTimers()
        told = self.chat(a)
        self.assertEqual(len(told), 1)
        self.assertIn("plus ancien", told[0])

    def test_companion_writes_its_version(self):
        self.assertIn(f'["companion"] = "{appinfo.VERSION}"', orders.lua_file([], 1763030000))


if __name__ == "__main__":
    unittest.main()
