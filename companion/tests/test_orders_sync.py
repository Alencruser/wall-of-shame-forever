"""Craft orders, companion side: the 2|O|... event, the request to the bot, the file written for the
addon, and the background poll."""
import os
import shutil
import sys
import tempfile
import threading
import time
import unittest
import urllib.parse
from unittest import mock

import lupa

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import connection  # noqa: E402
import events  # noqa: E402
import orders  # noqa: E402
import wallofshame_companion as companion  # noqa: E402

PAYLOAD = ("2|O|Chamy Chan-CAMWOWEU5Realm2PvP:O:42:refused|Chamy Chan|CAMWOWEU5Realm2PvP|Bagarre|21|SHAMAN|"
           "1763030000|Alen#1234|42|refused|Pas les compos")

SAVED = '''
WallOfShameForeverDB = {
["connection"] = "swf1.abc",
["orderIdentity"] = {
["battletag"] = "Alen#1234",
["characters"] = {
"Chamy Chan-CAMWOWEU5Realm2PvP", -- [1]
"Gr\\"umbar-Forever", -- [2]
},
},
["outbox"] = {
"2|L|x",
},
}
'''

ORDER = {"id": "o2", "artisan": "Chamy Chan-CAMWOWEU5Realm2PvP",
         "buyer": {"name": "Grumbar", "realm": "Forever", "class": "WARRIOR", "level": 30},
         "itemId": 2152, "itemName": 'Kit "léger"\\ok\nsuite|x\x01', "qty": 2, "note": "", "createdAt": 1763030500}


class Reply:
    def __init__(self, status_code, data=None):
        self.status_code, self.data = status_code, data

    def json(self):
        if self.data is None:
            raise ValueError("no JSON")
        return self.data


class PayloadTest(unittest.TestCase):
    def test_order(self):
        ev = events.parse_payload(PAYLOAD, "savedvariables")
        self.assertEqual(ev["type"], "order")
        self.assertEqual((ev["order"], ev["status"], ev["reason"]), ("42", "refused", "Pas les compos"))
        self.assertEqual((ev["level"], ev["time"], ev["battletag"]), (21, 1763030000, "Alen#1234"))
        self.assertFalse(ev["test"])

    def test_done_with_empty_reason(self):
        ev = events.parse_payload(PAYLOAD.replace("refused|Pas les compos", "done|"), "realtime")
        self.assertEqual((ev["status"], ev["reason"], ev["source"]), ("done", "", "realtime"))

    def test_received_by_the_buyer(self):
        ev = events.parse_payload(PAYLOAD.replace(":42:refused|", ":42:received|").replace("|42|refused|Pas les compos", "|42|received|"),
                                  "realtime")
        self.assertEqual((ev["order"], ev["status"], ev["reason"]), ("42", "received", ""))

    def test_activity_and_cancel(self):
        base = "2|A|Chamy Chan-R:A:1312345678901234567:join:1763030000|Chamy Chan|R|Bagarre|42|SHAMAN|1763030000|Alen#1|"
        ev = events.parse_payload(base + "join|1312345678901234567|heal", "realtime")
        self.assertEqual((ev["type"], ev["action"], ev["activity"], ev["role"]), ("activity", "join", "1312345678901234567", "heal"))
        self.assertIsNotNone(events.parse_payload(base + "leave|1312345678901234567|", "realtime"))
        self.assertIsNone(events.parse_payload(base + "join|1312345678901234567|bard", "realtime"))
        self.assertIsNone(events.parse_payload(base + "join|abc|dps", "realtime"))
        ev = events.parse_payload(PAYLOAD.replace(":42:refused|", ":42:cancelled|").replace("|42|refused|Pas les compos", "|42|cancelled|"),
                                  "realtime")
        self.assertEqual(ev["status"], "cancelled")

    def test_request(self):
        base = "2|R|Chamy Chan-R:R:1763030000:new|Chamy Chan|R|Bagarre|21|SHAMAN|1763030000|Alen#1234|"
        ev = events.parse_payload(base + "new|6a1b2c3d123|1468|5|2 po|Pour la quête des murlocs", "realtime")
        self.assertEqual((ev["type"], ev["action"], ev["request"], ev["item"], ev["qty"], ev["reward"], ev["note"]),
                         ("request", "new", "6a1b2c3d123", 1468, 5, "2 po", "Pour la quête des murlocs"))
        ev = events.parse_payload(base + "take|6a1b2c3d123||||", "realtime")
        self.assertEqual((ev["action"], ev["item"]), ("take", None))
        self.assertIsNone(events.parse_payload(base + "new|6a1b2c3d123||5||", "realtime"))  # no item
        self.assertIsNone(events.parse_payload(base + "steal|6a1b2c3d123||||", "realtime"))
        self.assertIsNone(events.parse_payload(base + "take|bad id!||||", "realtime"))

    def test_outbox_sends_requests_and_activities(self):
        # companion 0.8.0 crashed here (KeyError 'zone'): both fell into the death branch
        req = "2|R|Chamy Chan-R:R:1763030000:new|Chamy Chan|R|Bagarre|21|SHAMAN|1763030000|Alen#1234|new|6a1b2c3d123|1468|5||"
        act = ("2|A|Chamy Chan-R:A:1312345678901234567:join:1763030000|Chamy Chan|R|Bagarre|42|SHAMAN|1763030000|Alen#1|"
               "join|1312345678901234567|heal")
        text = SAVED.replace('"2|L|x",', '"%s",\n"%s",' % (req, act))
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder)
        path = os.path.join(folder, "WallOfShameForever.lua")
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        sender = mock.Mock()
        with mock.patch.object(companion, "log"):
            companion.check_outbox([path], {}, set(), sender)
        sent = [c.args[0]["type"] for c in sender.push.call_args_list]
        self.assertEqual(sent, ["request", "activity"])

    def test_bad_status_or_fields(self):
        self.assertIsNone(events.parse_payload(PAYLOAD.replace("|refused|", "|maybe|"), "realtime"))
        self.assertIsNone(events.parse_payload(PAYLOAD + "|extra", "realtime"))


class RequestTest(unittest.TestCase):
    def test_url(self):
        self.assertEqual(orders.orders_url("https://bot.example.org/shamewall/deaths"),
                         "https://bot.example.org/shamewall/orders")
        self.assertEqual(orders.orders_url("http://127.0.0.1:8787/deaths/?x=1"), "http://127.0.0.1:8787/orders")

    def test_query(self):
        url = orders.request_url("https://bot.example.org/shamewall/deaths", "Alen#1234",
                                 ["Chamy Chan-Realm", "Grumbar-Realm"])
        parts = urllib.parse.urlsplit(url)
        self.assertEqual(parts.path, "/shamewall/orders")
        self.assertEqual(urllib.parse.parse_qs(parts.query, keep_blank_values=True),
                         {"battletag": ["Alen#1234"], "chars": ["Chamy Chan-Realm,Grumbar-Realm"]})
        self.assertIn("battletag=&", orders.request_url("https://b/x/deaths", None, ["A-R"]))

    def test_identity(self):
        self.assertEqual(orders.read_identity(SAVED),
                         ("Alen#1234", ["Chamy Chan-CAMWOWEU5Realm2PvP", 'Gr"umbar-Forever']))
        self.assertIsNone(orders.read_identity('WallOfShameForeverDB = { ["outbox"] = {} }'))

    def test_groups(self):
        groups = orders.group_identities([("A#1", ["X-R"]), ("", ["X-R", "Y-R"]), ("B#2", ["Z-R"]),
                                          ("A#1", ["W-R"])])
        self.assertEqual(groups, {"A#1": ["W-R", "X-R"], "": ["Y-R"], "B#2": ["Z-R"]})
        self.assertEqual(orders.group_identities([("", [])]), {})

    def test_clean_and_merge(self):
        self.assertIsNone(orders.clean_orders({"nope": []}))
        a = orders.clean_orders({"orders": [dict(ORDER, qty="3", extra=1), {"id": ""}, "x"]})
        self.assertEqual(len(a), 1)
        self.assertEqual((a[0]["qty"], list(a[0])), (3, list(orders.ORDER_KEYS)))
        b = orders.clean_orders({"orders": [dict(ORDER, id="o1", createdAt=1), ORDER]})
        self.assertEqual([o["id"] for o in orders.merge([a, b])], ["o1", "o2"])

    def test_reagents_and_reply(self):
        raw = dict(ORDER, reply="Prête vendredi", reagents=[
            {"itemId": 2318, "name": "Cuir léger", "qty": 8, "extra": 1},
            {"itemId": "2320", "name": "Fil grossier", "qty": "2"},  # numbers as text: numbers
            {"itemId": None, "name": "?", "qty": 1},  # no item id: dropped
            "x",
        ])
        order = orders.clean_orders({"orders": [raw]})[0]
        self.assertEqual(order["reply"], "Prête vendredi")
        self.assertEqual(order["reagents"], [{"itemId": 2318, "name": "Cuir léger", "qty": 8},
                                             {"itemId": 2320, "name": "Fil grossier", "qty": 2}])
        # an older bot sends neither: no reply, no materials (the addon says so)
        old = orders.clean_orders({"orders": [ORDER]})[0]
        self.assertEqual((old["reply"], old["reagents"]), (None, []))
        too_many = orders.clean_orders({"orders": [dict(ORDER, reagents=[{"itemId": i, "name": "a", "qty": 1}
                                                                          for i in range(1, 40)])]})[0]
        self.assertEqual(len(too_many["reagents"]), orders.MAX_REAGENTS)

    def test_placed(self):
        raw = {"orders": [], "placed": [
            {"id": "p1", "artisan": "Grumbar-Forever", "artisanClass": "WARRIOR", "buyer": "Chamy-Forever",
             "status": "done", "reason": "", "itemId": 2308, "itemName": "Cape", "qty": 2, "note": "",
             "reply": "Prête", "reagents": [{"itemId": 2318, "name": "Cuir", "qty": 8}],
             "createdAt": 1, "updatedAt": "5"},
            {"id": "x", "status": "cancelled"},  # never shown
            {"id": "", "status": "pending"},
        ]}
        placed = orders.clean_placed(raw)
        self.assertEqual([p["id"] for p in placed], ["p1"])
        self.assertEqual((placed[0]["status"], placed[0]["updatedAt"], placed[0]["reagents"][0]["qty"]),
                         ("done", 5, 8))
        self.assertEqual(orders.clean_placed({"orders": []}), [])  # older bot
        self.assertIsNone(placed[0]["receivedAt"])  # older bot: no Received button in the addon
        raw["placed"][0]["receivedAt"] = 0
        self.assertEqual(orders.clean_placed(raw)[0]["receivedAt"], 0)
        self.assertIn('["receivedAt"] = 0', orders.lua_file([], 1763030000, orders.clean_placed(raw)))

    def test_hub(self):
        """The tabs of the addon's « Bagarre club » window (0.7.9): passed as they come, within limits."""
        raw = {"orders": [], "hub": {
            "titles": {"bank": "Banquier", "bad key!": "x"},
            "next": [{"name": "Fidèle", "share": 0.7}] * 30,
            "bank": {"goal": "a" * 500, "milestones": [{"percent": 25, "reached": True}]},
            "deep": {"a": {"b": {"c": {"d": "too deep"}}}},
        }}
        hub = orders.clean_hub(raw)
        self.assertEqual(hub["titles"], {"bank": "Banquier"})
        self.assertEqual(len(hub["next"]), orders.HUB_MAX_ITEMS)
        self.assertEqual(len(hub["bank"]["goal"]), orders.HUB_MAX_TEXT)
        self.assertEqual(hub["bank"]["milestones"], [{"percent": 25, "reached": True}])
        self.assertEqual(hub["deep"], {"a": {"b": {}}})
        self.assertIsNone(orders.clean_hub({"orders": []}))  # older bot, or a player it does not know
        lua = orders.lua_file([], 1763030000, [], hub)
        self.assertIn('["hub"] = {', lua)
        self.assertIn('["bank"] = "Banquier"', lua)
        self.assertNotIn('["hub"]', orders.lua_file([], 1763030000, []))


def make_game(test, toc="## Interface: 11508\n## Title: Wall of Shame Forever\nCore.lua\n"):
    game = tempfile.mkdtemp()
    test.addCleanup(shutil.rmtree, game)
    addon = os.path.join(game, "Interface", "AddOns", "WallOfShameForever")
    os.makedirs(addon)
    with open(os.path.join(addon, "WallOfShameForever.toc"), "w", encoding="utf-8") as f:
        f.write(toc)
    return game


class WriterTest(unittest.TestCase):
    def setUp(self):
        self.game = make_game(self)
        self.folder = os.path.join(self.game, "Interface", "AddOns", orders.FOLDER)

    def read(self, name):
        with open(os.path.join(self.folder, name), encoding="utf-8") as f:
            return f.read()

    def test_lua_round_trip(self):
        self.assertTrue(orders.write_orders(self.game, orders.merge([[ORDER]]), now=1000))
        lua = lupa.LuaRuntime()
        lua.execute(self.read(orders.LUA_FILE))
        data = lua.globals().WallOfShameForever_Orders
        self.assertEqual(data.updated, 1000)
        order = data.orders[1]
        self.assertEqual(order.itemName.decode() if isinstance(order.itemName, bytes) else order.itemName,
                         ORDER["itemName"])
        self.assertEqual((order.qty, order.buyer.level, order.note), (2, 30, ""))
        self.assertIsNone(data.orders[2])

    def test_lua_reagents(self):
        order = orders.clean_orders({"orders": [dict(ORDER, reagents=[{"itemId": 2318, "name": "Cuir", "qty": 8}])]})[0]
        orders.write_orders(self.game, [order], now=1000)
        lua = lupa.LuaRuntime()
        lua.execute(self.read(orders.LUA_FILE))
        reagent = lua.globals().WallOfShameForever_Orders.orders[1].reagents[1]
        self.assertEqual((reagent.itemId, reagent.qty), (2318, 8))

    def test_lua_placed(self):
        placed = orders.clean_placed({"placed": [{"id": "p1", "artisan": "Grumbar-Forever", "status": "pending",
                                                  "qty": 1, "createdAt": 1, "reagents": []}]})
        orders.write_orders(self.game, [], now=1000, placed=placed)
        lua = lupa.LuaRuntime()
        lua.execute(self.read(orders.LUA_FILE))
        p = lua.globals().WallOfShameForever_Orders.placed[1]
        self.assertEqual((p.id, p.status), ("p1", "pending"))

    def test_escaping(self):
        self.assertEqual(orders.lua_string('a"b\\c\nd\r\te\x01|é'), '"a\\"b\\\\c\\nd\\r\\te\\001|é"')

    def test_no_rewrite_when_unchanged(self):
        orders.write_orders(self.game, [ORDER], now=1000)
        self.assertFalse(orders.write_orders(self.game, [ORDER], now=2000))
        self.assertIn('["updated"] = 1000', self.read(orders.LUA_FILE))
        self.assertTrue(orders.write_orders(self.game, [], now=3000))
        self.assertIn('["orders"] = {}', self.read(orders.LUA_FILE))
        self.assertFalse(os.path.exists(os.path.join(self.folder, orders.LUA_FILE + ".tmp")))

    def test_toc(self):
        orders.write_orders(self.game, [], now=1)
        toc = self.read(orders.TOC_FILE)
        self.assertTrue(toc.startswith("## Interface: 11508\n"))
        self.assertIn("## Title: Wall of Shame Forever - Commandes\n", toc)
        self.assertTrue(toc.endswith("\nCommandes.lua\n"))

    def test_toc_fallback(self):
        os.remove(os.path.join(self.game, "Interface", "AddOns", "WallOfShameForever", "WallOfShameForever.toc"))
        self.assertEqual(orders.addon_interface(self.game), orders.DEFAULT_INTERFACE)
        self.assertFalse(orders.write_orders(self.game, [], now=1))  # no addon: no folder
        self.assertFalse(os.path.exists(self.folder))


class PollTest(unittest.TestCase):
    def setUp(self):
        self.game = make_game(self, toc="")
        self.saved = os.path.join(self.game, "SavedVariables.lua")
        with open(self.saved, "w", encoding="utf-8") as f:
            f.write(SAVED)
        with mock.patch.object(companion, "log"):
            self.sender = companion.Sender(dry_run=False)
            self.sender.set_code(connection.encode("https://bot.example.org/shamewall/deaths", "k3y"))
        self.logs = []
        self.poller = orders.Orders(self.logs.append)
        self.lua = os.path.join(self.game, "Interface", "AddOns", orders.FOLDER, orders.LUA_FILE)

    def poll(self, reply, now):
        """A poll, waiting for its background thread; the mock of requests.get."""
        with mock.patch.object(orders.requests, "get", return_value=reply) as get:
            thread = self.poller.poll(self.sender, [self.saved], [self.game], now=now)
            if thread:
                thread.join(5)
        return get

    def test_writes_then_waits(self):
        self.poller.saw({"name": "Other", "realm": "R", "battletag": ""})
        get = self.poll(Reply(200, {"orders": [ORDER]}), now=1000)
        self.assertEqual(get.call_count, 2)  # Alen#1234, and the character seen without battletag
        headers = get.call_args_list[0].kwargs["headers"]
        self.assertEqual(headers["Authorization"], "Bearer k3y")
        self.assertIn("X-WoS-Versions", headers)  # who is behind (bot: versions.js)
        self.assertTrue(os.path.exists(self.lua))
        self.assertEqual(self.poll(Reply(200, {"orders": []}), now=1060).call_count, 0)  # not due yet

    def test_401_logged_once_and_waits_an_hour(self):
        self.poll(Reply(401), now=1000)
        self.poll(Reply(401), now=1000 + orders.POLL_INTERVAL)
        self.assertEqual(len(self.logs), 1)
        self.assertFalse(os.path.exists(os.path.dirname(self.lua)))
        self.assertEqual(self.poll(Reply(200, {"orders": []}), now=1000 + orders.REFUSED_RETRY).call_count, 1)

    def test_error_keeps_the_last_file(self):
        self.poll(Reply(200, {"orders": [ORDER]}), now=1000)
        self.poll(Reply(500), now=2000)
        with open(self.lua, encoding="utf-8") as f:
            self.assertIn('"o2"', f.read())

    def test_no_code_no_request(self):
        self.sender.url = None
        self.assertEqual(self.poll(Reply(200, {"orders": []}), now=1000).call_count, 0)

    def test_never_blocks_and_one_at_a_time(self):
        release, calls = threading.Event(), []

        def slow_get(*_args, **_kwargs):  # a bot that answers only when released
            calls.append(1)
            release.wait(5)
            return Reply(200, {"orders": [ORDER]})

        with mock.patch.object(orders.requests, "get", side_effect=slow_get):
            start = time.monotonic()
            thread = self.poller.poll(self.sender, [self.saved], [self.game], now=1000)
            self.assertLess(time.monotonic() - start, 1)  # back to the main loop at once
            self.assertIsNotNone(thread)
            # still running, even when the next one is due: skipped
            self.assertIsNone(self.poller.poll(self.sender, [self.saved], [self.game], now=5000))
            release.set()
            thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(len(calls), 1)  # one battletag, one request
        self.assertTrue(os.path.exists(self.lua))


if __name__ == "__main__":
    unittest.main()
