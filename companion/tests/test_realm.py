"""Realm missing (WoW Forever, 2026-11-21: GetNormalizedRealmName and GetRealmName both returned ""): the
addon used the last name as the realm ("Miss" on realm "Kin"). Now it keeps the full name and the last
realm seen for the character, or an empty realm if it never saw one. Run with lupa."""

import unittest

from test_addon_orders import Addon

REALM = "CAMWOWEU5Realm2PvP"


class RealmTest(unittest.TestCase):
    def identity(self, a):
        name, realm, _, _ = a.ns.Identity()
        return name, realm

    def test_realm_known_is_remembered(self):
        a = Addon(orders=[]).login()
        self.assertEqual(self.identity(a), ("Chamy Chan", REALM))
        self.assertEqual(a.db.realms["Chamy Chan"], REALM)

    def test_realm_missing_uses_the_last_one_seen(self):
        a = Addon(orders=[]).login()
        a.g.STATE.realm = ""
        self.assertEqual(self.identity(a), ("Chamy Chan", REALM))

    def test_realm_never_seen_keeps_the_full_name(self):
        a = Addon(orders=[])
        a.g.STATE.realm = ""
        a.login()
        self.assertEqual(self.identity(a), ("Chamy Chan", ""))

    def test_realm_missing_after_reload_still_known(self):
        a = Addon(orders=[], db={"realms": {"Chamy Chan": REALM}})
        a.g.STATE.realm = ""
        a.login()
        self.assertEqual(self.identity(a), ("Chamy Chan", REALM))


if __name__ == "__main__":
    unittest.main()
