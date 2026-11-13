"""Professions event (2|P|...): parsed from the addon's outbox, sent to the bot as a list."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import events  # noqa: E402

PAYLOAD = ("2|P|Chamy Chan-CAMWOWEU5Realm2PvP:P:1763030000|Chamy Chan|CAMWOWEU5Realm2PvP|Bagarre|21|SHAMAN|"
           "1763030000|Alen#1234|165:146:225:Travail du cuir:2152=3=Light Armor Kit,9070=2=Ceinture noire;"
           "393:221:225:Dépeçage:;185:79:150:Cuisine:")


class ProfessionsTest(unittest.TestCase):
    def test_payload(self):
        ev = events.parse_payload(PAYLOAD, "savedvariables")
        self.assertEqual(ev["type"], "professions")
        self.assertEqual((ev["name"], ev["level"], ev["battletag"]), ("Chamy Chan", 21, "Alen#1234"))
        by = {p["skillLine"]: p for p in ev["professions"]}
        self.assertEqual(by[165]["recipes"], [{"id": 2152, "color": 3, "name": "Light Armor Kit"},
                                              {"id": 9070, "color": 2, "name": "Ceinture noire"}])
        self.assertEqual((by[165]["level"], by[165]["max"], by[165]["name"]), (146, 225, "Travail du cuir"))
        self.assertIsNone(by[393]["recipes"])  # gathering
        self.assertIsNone(by[185]["recipes"])  # never opened

    def test_bad_entries_skipped(self):
        self.assertEqual(events.parse_professions("x:1:2:a:;165:1:2:Cuir:1=?=A,bad"),
                         [{"skillLine": 165, "level": 1, "max": 2, "name": "Cuir",
                           "recipes": [{"id": 1, "color": None, "name": "A"}]}])
        self.assertEqual(events.parse_professions(""), [])


if __name__ == "__main__":
    unittest.main()
