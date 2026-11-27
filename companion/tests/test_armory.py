"""Gear, stats and talents for the site's « Armurerie » (Armory.lua), run with lupa: read a moment after login,
queued as 2|G|... only when the gear, talents or level changed, one reading per character in the outbox, the
option turned off tells the bot once; and the companion's parsing of the payload."""

import os
import unittest

import events
from test_addon_orders import ADDON, Addon

ARMORY_STUBS = r"""
STATE.gear = {
    [1] = "|cff0070dd|Hitem:10763:0:0:0:0:0:0:0:50:0:0:0:0|h[Barbute en glace-acier]|h|r",
    [5] = "|cff0070dd|Hitem:7939:1891:0:0:0:0:0:0:50:0:0:0:0|h[Cuirasse en vrai-argent]|h|r",
    [16] = "|cff0070dd|Hitem:7960:1897:0:0:0:0:1199:0:50:0:0:0:0|h[Championne en vrai-argent]|h|r",
}
STATE.ilvl = { [10763] = 43, [7939] = 49, [7960] = 52 }
STATE.ranks = { 3, 0 }
function GetInventoryItemLink(_, slot) return STATE.gear[slot] end
function GetInventoryItemQuality(_, slot) if STATE.gear[slot] then return 3 end end
function GetDetailedItemLevelInfo(link) return STATE.ilvl[tonumber(link:match("item:(%d+)"))] end
function UnitStat(_, i) return 50, ({ 168, 96, 172, 32, 51 })[i], ({ 61, 19, 58, 0, 4 })[i], 0 end
function UnitArmor() return 3000, 3420, 3420, 420, 0 end
function UnitAttackPower() return 400, 46, 0 end
function UnitDamage() return 138.4, 191.25, 0, 0, 0, 0, 1 end
function GetCritChance() return 9.4 end
function GetSpellBonusDamage(school) return ({ [3] = 12, [5] = 20 })[school] or 0 end
function UnitRace() return "Humain", "Human" end
function GetNumTalentTabs() return 2 end
function GetTalentTabInfo(tab) return 160 + tab, ({ "Armes", "Fureur" })[tab], "description", 132355, 0 end
function GetNumTalents() return 2 end
function GetTalentInfo(tab, i)
    if tab == 1 then
        return ({ "Frappe héroïque améliorée", "Déviation" })[i], 1, 1, i, STATE.ranks[i], ({ 3, 5 })[i]
    end
    return ({ "Cruauté", "Colère: débridée" })[i], 1, 1, i + 1, 0, 5
end
"""


class ArmoryTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        self.a.lua.execute(ARMORY_STUBS)
        load = self.a.lua.eval("function(src, ns) assert(loadstring(src, 'Armory.lua'))('WallOfShameForever', ns) end")
        with open(os.path.join(ADDON, "Armory.lua"), encoding="utf-8") as f:
            load(f.read(), self.a.ns)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.state = self.a.g.STATE

    def readings(self):
        return [p for p in self.a.lua_list(self.a.db.outbox) if p.split("|")[1] == "G"]

    def reports(self):
        return [p for p in self.a.lua_list(self.a.db.outbox) if p.split("|")[1] == "X"]

    def test_read_after_login_and_parsed_by_the_companion(self):
        self.a.g.RunTimers()
        readings = self.readings()
        self.assertEqual(len(readings), 1)
        ev = events.parse_payload(readings[0], "savedvariables")
        self.assertEqual(ev["type"], "armory")
        self.assertFalse(ev["off"])
        self.assertEqual(ev["race"], "Humain")
        self.assertEqual(ev["gear"][0], {"slot": 1, "item": 10763, "enchant": 0, "suffix": 0, "ilvl": 43, "quality": 3})
        self.assertEqual(ev["gear"][2], {"slot": 16, "item": 7960, "enchant": 1897, "suffix": 1199, "ilvl": 52,
                                         "quality": 3})
        self.assertEqual(ev["stats"]["str"], 168)
        self.assertEqual(ev["stats"]["strB"], 61)
        self.assertEqual(ev["stats"]["armor"], 3420)
        self.assertEqual(ev["stats"]["ap"], 446)
        self.assertEqual(ev["stats"]["dmgMin"], 138.4)
        self.assertEqual(ev["stats"]["dmgMax"], 191.25)
        self.assertEqual(ev["stats"]["sp"], 20)
        self.assertNotIn("dodge", ev["stats"])  # not on this client: left out
        self.assertEqual([t["name"] for t in ev["talents"]], ["Armes", "Fureur"])
        self.assertEqual(ev["talents"][0]["points"], 3)
        self.assertEqual(ev["talents"][0]["talents"][0], {"spell": None, "tier": 1, "column": 1, "rank": 3, "max": 3,
                                                         "name": "Frappe héroïque améliorée"})
        self.assertEqual(ev["talents"][1]["talents"][1]["name"], "Colère  débridée")  # separators cleaned
        self.assertEqual(len(self.reports()), 1)  # what the client gave, once

    def test_unchanged_not_queued_again_but_new_gear_or_talents_are(self):
        self.a.g.RunTimers()
        self.state.now = self.state.now + 60
        self.a.g.Fire("PLAYER_EQUIPMENT_CHANGED")
        self.a.g.RunTimers()
        self.assertEqual(len(self.readings()), 1)
        self.state.now = self.state.now + 60
        self.state.ranks[2] = 1
        self.a.g.Fire("CHARACTER_POINTS_CHANGED")
        self.a.g.RunTimers()
        readings = self.readings()
        self.assertEqual(len(readings), 1)  # the newer reading replaced the older one
        self.assertEqual(events.parse_payload(readings[0], "savedvariables")["talents"][0]["points"], 4)
        self.assertEqual(len(self.reports()), 1)

    def test_logout_reads_right_away(self):
        self.a.g.Fire("PLAYER_LOGOUT")
        self.assertEqual(len(self.readings()), 1)

    def test_option_off_tells_the_bot_once(self):
        self.a.g.RunTimers()
        self.a.db.shareGear = False
        self.a.ns.Armory.OnOptionChanged()
        self.a.g.RunTimers()
        self.a.g.Fire("PLAYER_LOGOUT")
        readings = self.readings()
        self.assertEqual(len(readings), 1)
        ev = events.parse_payload(readings[0], "savedvariables")
        self.assertTrue(ev["off"])
        self.assertEqual(ev["gear"], [])

    def test_option_on_by_default(self):
        self.assertTrue(self.a.db.shareGear)

    def test_nothing_without_discord_sharing(self):
        self.a.db.discord = False
        self.a.g.RunTimers()
        self.assertEqual(self.readings(), [])

    def test_nothing_before_the_client_gives_the_gear(self):
        self.a.lua.execute("STATE.gear = {}")
        self.a.g.RunTimers()
        self.assertEqual(self.readings(), [])


class ParseTest(unittest.TestCase):
    def test_bad_entries_skipped(self):
        gear = events.parse_gear("1=10763.0.0.43.3;x=1.2.3.4.5;2=0.0.0.0.1;20=5.0.0.0.1;3=12.0.0.0.")
        self.assertEqual([g["item"] for g in gear], [10763, 12])
        self.assertIsNone(gear[1]["quality"])
        self.assertEqual(events.parse_stats("str=10;bad key=3;crit=abc;hit=-1.5"), {"str": 10, "hit": -1.5})
        trees = events.parse_talents("Armes/3/0.1.1.3.3.Nom. avec point,bad;Rien/x/")
        self.assertEqual(len(trees), 1)
        self.assertEqual(trees[0]["talents"][0]["name"], "Nom. avec point")

    def test_payload_without_gear_refused(self):
        payload = "2|G|a-b:G:1|a|b|g|10|WARRIOR|1|bt|Humain||str=1|"
        self.assertIsNone(events.parse_payload(payload, "savedvariables"))


if __name__ == "__main__":
    unittest.main()
