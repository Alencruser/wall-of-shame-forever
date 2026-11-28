"""Guild bank money log (GuildBank.lua), run with lupa: the log is queried when the bank opens, read on
GUILDBANKLOG_UPDATE, queued as 2|B|... only when it changed, at most a few readings per character in the
outbox; and the companion's parsing of the payload."""

import os
import unittest

import events
from test_addon_orders import ADDON, Addon

BANK_STUBS = r"""
MAX_GUILDBANK_TABS = 6
STATE.bankLog = {
    { "deposit", "Lwi Zi", 202, 0, 0, 13, 8 },
    { "deposit", "Chamy Chan", 20000, 0, 0, 5, 6 },
    { "withdraw", "Chamy Chan", 10000, 0, 0, 0, 0 },
}
STATE.queried = {}
function GetGuildBankMoney() return 16302 end
function QueryGuildBankLog(tab) table.insert(STATE.queried, tab) end
function GetNumGuildBankMoneyTransactions() return #STATE.bankLog end
function GetGuildBankMoneyTransaction(i) return unpack(STATE.bankLog[i]) end
"""


class GuildBankTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        self.a.lua.execute(BANK_STUBS)
        load = self.a.lua.eval("function(src, ns) assert(loadstring(src, 'GuildBank.lua'))('WallOfShameForever', ns) end")
        with open(os.path.join(ADDON, "GuildBank.lua"), encoding="utf-8") as f:
            load(f.read(), self.a.ns)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.state = self.a.g.STATE

    def open_bank(self):
        self.a.g.Fire("GUILDBANKFRAME_OPENED")
        self.a.g.RunTimers()
        self.a.g.Fire("GUILDBANKLOG_UPDATE")

    def readings(self):
        return [p for p in self.a.lua_list(self.a.db.outbox) if p.split("|")[1] == "B"]

    def test_opening_the_bank_queries_the_money_tab_and_queues_the_log(self):
        self.open_bank()
        self.assertEqual(self.a.lua_list(self.state.queried), [7])
        readings = self.readings()
        self.assertEqual(len(readings), 1)
        ev = events.parse_payload(readings[0], "savedvariables")
        self.assertEqual(ev["type"], "banklog")
        self.assertEqual(ev["guild"], "Bagarre")
        self.assertEqual(ev["time"], 1763030000)
        self.assertEqual(ev["money"], 16302)
        self.assertEqual(ev["lines"][0], {"type": "deposit", "who": "Lwi Zi", "copper": 202, "years": 0,
                                          "months": 0, "days": 13, "hours": 8})
        self.assertEqual(ev["lines"][2]["type"], "withdraw")
        self.assertEqual(ev["lines"][2]["copper"], 10000)

    def test_unchanged_log_not_queued_again_even_if_ages_moved(self):
        self.open_bank()
        self.state.now = self.state.now + 7200
        self.state.bankLog[1][7] = 10
        self.open_bank()
        self.assertEqual(len(self.readings()), 1)

    def test_new_transaction_queues_a_new_reading(self):
        self.open_bank()
        self.state.now = self.state.now + 60
        self.a.lua.execute('table.insert(STATE.bankLog, { "deposit", "Lex Orcist", 5000, 0, 0, 0, 0 })')
        self.open_bank()
        self.assertEqual(len(self.readings()), 2)

    def test_log_update_without_bank_opened_is_ignored(self):
        self.a.g.Fire("GUILDBANKLOG_UPDATE")
        self.assertEqual(self.readings(), [])

    def test_nothing_without_discord_sharing(self):
        self.a.db.discord = False
        self.open_bank()
        self.assertEqual(self.readings(), [])

    def test_at_most_five_readings_per_character(self):
        for i in range(8):
            self.state.now = self.state.now + 60
            self.a.lua.execute(f'table.insert(STATE.bankLog, {{ "deposit", "Lex Orcist", {i + 1}, 0, 0, 0, 0 }})')
            self.open_bank()
        readings = self.readings()
        self.assertEqual(len(readings), 5)
        last = events.parse_payload(readings[-1], "savedvariables")
        self.assertEqual(last["lines"][-1]["copper"], 8)

    def test_separators_in_names_are_cleaned(self):
        self.state.bankLog[1][2] = "Bad:Name;x"
        self.open_bank()
        ev = events.parse_payload(self.readings()[0], "savedvariables")
        self.assertEqual(ev["lines"][0]["who"], "Bad Name x")
        self.assertEqual(len(ev["lines"]), 3)


ITEM_STUBS = r"""
STATE.tabs = {
    {
        { "deposit", "Lwi Zi", "|cffffffff|Hitem:2589::::::::20:::::|h[Etoffe de lin]|h|r", 20, 1, 2, 0, 0, 3, 4 },
        { "move", "Lwi Zi", "|cffffffff|Hitem:2589::::::::20:::::|h[Etoffe de lin]|h|r", 5, 1, 2, 0, 0, 0, 1 },
    },
    {
        { "withdraw", "Chamy Chan", "|cff1eff00|Hitem:1715::::::::20:::::|h[Armure]|h|r", 1, 2, 2, 0, 0, 0, 2 },
    },
}
function GetNumGuildBankTabs() return #STATE.tabs end
function GetNumGuildBankTransactions(tab) return #(STATE.tabs[tab] or {}) end
function GetGuildBankTransaction(tab, i) return unpack(STATE.tabs[tab][i]) end
Auctionator = { API = { v1 = {
    GetAuctionPriceByItemLink = function(caller, link)
        assert(caller == "WallOfShameForever")
        if link:find("item:2589:") then return 45 end
    end,
    GetAuctionAgeByItemLink = function(caller, link) return 2 end,
} } }
"""


class GuildBankItemsTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        self.a.lua.execute(BANK_STUBS)
        self.a.lua.execute(ITEM_STUBS)
        load = self.a.lua.eval("function(src, ns) assert(loadstring(src, 'GuildBank.lua'))('WallOfShameForever', ns) end")
        with open(os.path.join(ADDON, "GuildBank.lua"), encoding="utf-8") as f:
            load(f.read(), self.a.ns)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.state = self.a.g.STATE

    def open_bank(self):
        self.a.g.Fire("GUILDBANKFRAME_OPENED")
        for _ in range(10):  # the money log, then each item tab one after the other, then the reading
            self.a.g.RunTimers()
            self.a.g.Fire("GUILDBANKLOG_UPDATE")

    def readings(self):
        return [p for p in self.a.lua_list(self.a.db.outbox) if p.split("|")[1] == "I"]

    def test_item_tabs_queried_one_after_the_other_and_queued_with_prices(self):
        self.open_bank()
        self.assertEqual(self.a.lua_list(self.state.queried), [7, 1, 2])
        readings = self.readings()
        self.assertEqual(len(readings), 1)
        ev = events.parse_payload(readings[0], "savedvariables")
        self.assertEqual(ev["type"], "bankitems")
        self.assertEqual(len(ev["lines"]), 2)  # the move is left out
        self.assertEqual(ev["lines"][0], {"type": "deposit", "who": "Lwi Zi", "item": 2589, "count": 20, "years": 0,
                                          "months": 0, "days": 3, "hours": 4, "price": 45, "age": 2, "tab": 1})
        self.assertEqual(ev["lines"][1]["type"], "withdraw")
        self.assertIsNone(ev["lines"][1]["price"])  # Auctionator never saw it
        self.assertEqual(ev["lines"][1]["tab"], 2)

    def test_unchanged_item_log_not_queued_again(self):
        self.open_bank()
        self.state.now = self.state.now + 3600
        self.open_bank()
        self.assertEqual(len(self.readings()), 1)

    def test_without_auctionator_no_price(self):
        self.a.lua.execute("Auctionator = nil")
        self.open_bank()
        ev = events.parse_payload(self.readings()[0], "savedvariables")
        self.assertIsNone(ev["lines"][0]["price"])
        self.assertIsNone(ev["lines"][0]["age"])


class ParseBankLinesTest(unittest.TestCase):
    def test_bank_items_bad_entries_skipped(self):
        lines = events.parse_bank_items("deposit:2589:20:0:0:1:2:Lex:45:3:1;move:2589:5:0:0:0:0:Lex:::1;"
                                        "withdraw:x:1:0:0:0:0:Bob:::2;withdraw:1715:1:0:0:0:0:Bob:::2")
        self.assertEqual([(l["type"], l["item"], l["price"]) for l in lines], [("deposit", 2589, 45), ("withdraw", 1715, None)])

    def test_unknown_money_is_none(self):
        ev = events.parse_payload("2|B|C-R:B:1|C|R|G|20|SHAMAN|1|A#1||deposit:5:0:0:0:1:Lex", "savedvariables")
        self.assertIsNone(ev["money"])
        self.assertEqual(ev["lines"][0]["copper"], 5)

    def test_bad_entries_skipped(self):
        lines = events.parse_bank_lines("deposit:100:0:0:1:2:Lex;withdraw:x:0:0:0:0:Bob;:5:0:0:0:0:Nobody;oops")
        self.assertEqual(lines, [{"type": "deposit", "who": "Lex", "copper": 100, "years": 0, "months": 0,
                                  "days": 1, "hours": 2}])

    def test_empty_log_is_no_event(self):
        payload = "2|B|Chamy-R:B:1|Chamy|R|Bagarre|20|SHAMAN|1|A#1||"
        self.assertIsNone(events.parse_payload(payload, "savedvariables"))


if __name__ == "__main__":
    unittest.main()
