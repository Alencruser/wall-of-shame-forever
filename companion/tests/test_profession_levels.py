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


if __name__ == "__main__":
    unittest.main()
