import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import connection  # noqa: E402
import wallofshame_companion as companion  # noqa: E402


class Reply:
    def __init__(self, status_code):
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")


def event(event_id):
    return {"id": event_id, "type": "level", "name": "Chamy Chan", "level": 12, "class": "MAGE",
            "guild": "", "source": "savedvariables"}


class SenderTest(unittest.TestCase):
    def setUp(self):
        patches = [mock.patch.object(companion, "log"), mock.patch.dict(companion.STATUS, {"bot": ""})]
        for p in patches:
            p.start()
            self.addCleanup(p.stop)
        self.sender = companion.Sender(dry_run=False)
        self.sender.set_code(connection.encode("https://bot.example.org/deaths", "k3y"))
        self.sender.push(event("a"), None)

    def flush(self, status_code):
        with mock.patch.object(companion.requests, "post", return_value=Reply(status_code)):
            self.sender.flush()

    def test_403_drops_only_that_event(self):
        self.flush(403)
        self.assertEqual(self.sender.queue, [])
        self.assertEqual(companion.STATUS["bot"], "bot.example.org")  # the code is still fine

    def test_401_keeps_the_event_and_says_the_code_is_refused(self):
        self.flush(401)
        self.assertEqual(len(self.sender.queue), 1)
        self.assertEqual(companion.STATUS["bot"], "code refused, ask an officer")


if __name__ == "__main__":
    unittest.main()
