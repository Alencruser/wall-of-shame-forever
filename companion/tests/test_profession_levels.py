"""Profession levels without a window (WallOfShameForever.lua, RefreshProfessionLevels): read at
login, at logout and when a skill changes; a new 2|P|... reading only when a level changed, known
recipes kept, nothing forgotten while the game has not answered yet. Run with lupa."""

import unittest

import events
from test_addon_orders import Addon

PROF_STUBS = r"""
STATE.profs = {
    { name = "Travail du cuir", level = 160, max = 225, skillLine = 165 },
    { name = "Pêche", level = 115, max = 225, skillLine = 356 },
}
function GetProfessions()
    local out = {}
    for i in ipairs(STATE.profs) do out[#out + 1] = i end
    return unpack(out)
end
function GetProfessionInfo(i)
    local p = STATE.profs[i]
    if not p or STATE.notLoaded then return nil end
    return p.name, nil, p.level, p.max, nil, nil, p.skillLine
end
"""


class ProfessionLevelsTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        self.a.lua.execute(PROF_STUBS)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.state = self.a.g.STATE

    def readings(self):
        out = []
        for p in self.a.lua_list(self.a.db.outbox):
            if p.split("|")[1] == "P":
                out.append({x["skillLine"]: x for x in events.parse_payload(p, "savedvariables")["professions"]})
        return out

    def run_timers(self):
        for _ in range(3):
            self.a.g.RunTimers()

    def test_login_reads_levels_without_window(self):
        self.run_timers()
        readings = self.readings()
        self.assertEqual(len(readings), 1)
        self.assertEqual(readings[0][356]["level"], 115)
        self.assertIsNone(readings[0][356]["recipes"])

    def test_new_reading_only_when_a_level_changed_and_recipes_kept(self):
        self.run_timers()
        store = self.a.db.professions["Chamy Chan-CAMWOWEU5Realm2PvP"]
        store[165].recipes = "2152=3=Light Armor Kit"
        first = self.a.lua_list(self.a.db.outbox)
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        self.assertEqual(self.a.lua_list(self.a.db.outbox), first, "same levels: no new reading")
        self.state.profs[2].level = 191
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        readings = self.readings()
        self.assertEqual(len(readings), 1, "only the latest reading waits")
        self.assertEqual(readings[0][356]["level"], 191)
        self.assertEqual(readings[0][165]["recipes"][0]["id"], 2152)

    def test_logout_reads_right_away(self):
        self.run_timers()
        self.state.profs[2].level = 200
        self.a.g.Fire("PLAYER_LOGOUT")  # no timer: SavedVariables are written just after
        self.assertEqual(self.readings()[0][356]["level"], 200)

    def test_nothing_forgotten_while_the_game_has_no_answer(self):
        self.run_timers()
        self.state.notLoaded = True
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        store = self.a.db.professions["Chamy Chan-CAMWOWEU5Realm2PvP"]
        self.assertIsNotNone(store[356])
        self.assertEqual(len(self.readings()), 1)

    def test_nothing_queued_without_the_companion(self):
        self.a.db.discord = False
        self.run_timers()
        self.assertEqual(self.readings(), [])

    def test_change_made_while_discord_off_is_sent_later(self):
        self.a.db.discord = False
        self.run_timers()
        self.state.profs[2].level = 150
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        self.assertEqual(self.readings(), [])
        self.a.db.discord = True
        self.a.g.Fire("SKILL_LINES_CHANGED")  # same levels as the last reading, but never sent
        self.run_timers()
        self.assertEqual(self.readings()[0][356]["level"], 150)

    def test_new_connection_code_sends_again(self):
        self.run_timers()
        self.a.db.outbox = self.a.lua.table()
        self.a.lua.execute('function GetGuildInfoText() return "Code companion: swf1.other" end '
                           'function GetNumGuildMembers() return 0 end')
        self.a.g.Fire("GUILD_ROSTER_UPDATE")
        self.run_timers()
        self.assertEqual(len(self.readings()), 1)

    def test_all_professions_unlearned_are_forgotten(self):
        self.run_timers()
        self.state.profs = self.a.lua.table()
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        self.assertEqual(self.readings(), [{}])

    def test_empty_list_right_after_login_forgets_nothing(self):
        fresh = Addon(orders=[])
        fresh.lua.execute(PROF_STUBS)
        fresh.login()
        fresh.db.discord, fresh.db.connection = True, "swf1.test"
        fresh.g.STATE.profs = fresh.lua.table()
        store = fresh.lua.table()
        store[165] = fresh.lua.table()
        store[165].level, store[165].max, store[165].name = 160, 225, "Travail du cuir"
        fresh.db.professions = fresh.lua.table()
        fresh.db.professions["Chamy Chan-CAMWOWEU5Realm2PvP"] = store
        for _ in range(3):
            fresh.g.RunTimers()
        self.assertIsNotNone(fresh.db.professions["Chamy Chan-CAMWOWEU5Realm2PvP"][165])

    def test_relearned_profession_loses_old_recipes(self):
        self.run_timers()
        store = self.a.db.professions["Chamy Chan-CAMWOWEU5Realm2PvP"]
        store[165].recipes = "2152=3=Light Armor Kit"
        self.state.profs[1].level = 1
        self.a.g.Fire("SKILL_LINES_CHANGED")
        self.run_timers()
        self.assertIsNone(self.readings()[0][165]["recipes"])


if __name__ == "__main__":
    unittest.main()


LOCK_STUBS = r"""
STATE.class = "ROGUE"
C_SkillInfo = {
    GetSkillLineInfoByID = function(id)
        if id ~= 633 or STATE.noLockpicking then return nil end
        return { skillID = 633, name = "Crochetage", skillRank = STATE.lockpicking or 175, maxRank = 225 }
    end,
}
"""


class LockpickingTest(unittest.TestCase):
    """v0.7.2: a rogue's lockpicking (C_SkillInfo, skill line 633) goes with the professions, no recipes;
    one diagnostic per character for the bot's debug.jsonl; nothing for the other classes."""

    def addon(self, stubs):
        a = Addon(orders=[])
        a.lua.execute(PROF_STUBS)
        a.lua.execute(stubs)
        a.login()
        a.db.discord = True
        a.db.connection = "swf1.test"
        for _ in range(3):
            a.g.RunTimers()
        return a

    def test_rogue(self):
        a = self.addon(LOCK_STUBS)
        payloads = a.lua_list(a.db.outbox)
        readings = [events.parse_payload(p, "savedvariables") for p in payloads if p.split("|")[1] == "P"]
        lock = {x["skillLine"]: x for x in readings[-1]["professions"]}[633]
        self.assertEqual((lock["name"], lock["level"], lock["max"], lock["recipes"]), ("Crochetage", 175, 225, None))
        debug = [events.parse_payload(p, "savedvariables") for p in payloads if p.split("|")[1] == "X"]
        self.assertEqual(len(debug), 1)
        self.assertEqual(debug[0]["topic"], "crochetage")
        self.assertIn("rank=175(skillRank)", debug[0]["details"])
        # a skill-up: a new reading, no second diagnostic
        a.g.STATE.lockpicking = 180
        a.g.Fire("SKILL_LINES_CHANGED")
        for _ in range(3):
            a.g.RunTimers()
        payloads = a.lua_list(a.db.outbox)
        readings = [events.parse_payload(p, "savedvariables") for p in payloads if p.split("|")[1] == "P"]
        self.assertEqual({x["skillLine"]: x for x in readings[-1]["professions"]}[633]["level"], 180)
        self.assertEqual(len([p for p in payloads if p.split("|")[1] == "X"]), 1)

    def test_not_a_rogue(self):
        a = self.addon(LOCK_STUBS.replace('STATE.class = "ROGUE"', ""))
        readings = [events.parse_payload(p, "savedvariables") for p in a.lua_list(a.db.outbox) if p.split("|")[1] == "P"]
        self.assertNotIn(633, {x["skillLine"] for x in readings[-1]["professions"]})
