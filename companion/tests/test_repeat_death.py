"""One death per life in the addon (WallOfShameForever.lua, NewDeath): a second PLAYER_DEAD for the
same death (hunters got two) is not sent again, and leaves a 2|X|... diagnostic in the outbox for
the bot's debug.jsonl; a resurrection starts a new life. Run with lupa on stubbed WoW APIs."""

import unittest

from test_addon_orders import Addon

DEATH_STUBS = r"""
STATE.dead, STATE.ghost, STATE.pet, STATE.petDead = false, false, true, false
function UnitIsDead(unit) if unit == "pet" then return STATE.petDead end return STATE.dead end
function UnitIsGhost() return STATE.ghost end
function UnitIsDeadOrGhost() return STATE.dead or STATE.ghost end
function UnitHealth(unit) if unit == "pet" then return STATE.petDead and 0 or 500 end return STATE.dead and 0 or 1000 end
function UnitExists(unit) if unit == "pet" then return STATE.pet end return true end
"""


class RepeatDeathTest(unittest.TestCase):
    def setUp(self):
        self.a = Addon(orders=[])
        self.a.lua.execute(DEATH_STUBS)
        self.a.login()
        self.a.db.discord = True
        self.a.db.connection = "swf1.test"
        self.state = self.a.g.STATE

    def outbox(self, kind):
        return [p for p in self.a.lua_list(self.a.db.outbox) if p.split("|")[1] == kind]

    def die(self, seconds_later=0):
        self.state.now = self.state.now + seconds_later
        self.state.dead = True
        self.a.g.Fire("PLAYER_DEAD")
        self.a.g.RunTimers()

    def test_second_player_dead_is_ignored_and_reported(self):
        self.die()
        self.assertEqual(len(self.outbox("D")), 1)
        self.state.pet = False  # the pet goes away with its master
        self.a.g.Fire("UNIT_PET", "player")
        self.die(seconds_later=2)
        self.assertEqual(len(self.outbox("D")), 1, "the same death is not sent twice")
        reports = self.outbox("X")
        self.assertEqual(len(reports), 1)
        fields = reports[0].split("|")
        self.assertEqual(len(fields), 12)
        self.assertEqual(fields[7], "SHAMAN")
        self.assertEqual(fields[10], "mort-double")
        details = fields[11]
        self.assertIn("dtMs=2000", details)
        self.assertIn("first=dead=1", details)
        self.assertIn("UNIT_PET", details)
        self.assertIn("pet=0", details)
        self.assertIn("PLAYER_DEAD", details)

    def test_release_is_the_same_death_resurrection_a_new_life(self):
        self.die()
        # release: dead → ghost, PLAYER_ALIVE fires but the player is still a ghost
        self.state.dead, self.state.ghost = False, True
        self.a.g.Fire("PLAYER_ALIVE")
        self.die(seconds_later=60)
        self.assertEqual(len(self.outbox("D")), 1)
        # back to the body: a new life, the next death counts
        self.state.dead, self.state.ghost = False, False
        self.a.g.Fire("PLAYER_UNGHOST")
        self.die(seconds_later=120)
        self.assertEqual(len(self.outbox("D")), 2)

    def test_companion_reads_the_report(self):
        import events
        self.die()
        self.die(seconds_later=3)
        ev = events.parse_payload(self.outbox("X")[0], "savedvariables")
        self.assertEqual(ev["type"], "debug")
        self.assertEqual(ev["topic"], "mort-double")
        self.assertTrue(ev["details"].startswith("dtMs=3000;"))
        self.assertEqual(ev["level"], 21)
        self.assertTrue(ev["id"].startswith("Chamy Chan-CAMWOWEU5Realm2PvP:X:"))

    def test_no_report_without_the_companion(self):
        self.a.db.discord = False
        self.die()
        self.die(seconds_later=1)
        self.assertEqual(self.outbox("X"), [])


if __name__ == "__main__":
    unittest.main()
