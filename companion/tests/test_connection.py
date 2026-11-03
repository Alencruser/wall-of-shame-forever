import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import connection  # noqa: E402


class ConnectionTest(unittest.TestCase):
    def test_roundtrip(self):
        code = connection.encode("https://bot.example.org/deaths", "k3y")
        self.assertTrue(code.startswith("swf1."))
        self.assertEqual(connection.decode("  " + code + "\n"), ("https://bot.example.org/deaths", "k3y"))

    def test_local_http_for_tests(self):
        self.assertIsNotNone(connection.decode(connection.encode("http://127.0.0.1:8787/shamewall/deaths", "k")))
        self.assertIsNotNone(connection.decode(connection.encode("http://localhost:8787/x", "k")))

    def test_invalid(self):
        for code in ["", "hello", "swf1.", "swf1.!!!", "swf1.WzFd",
                     connection.encode("http://insecure.example.org", "k"),
                     connection.encode("http://localhost.evil.org/x", "k"),
                     connection.encode("https://bot.example.org", "")]:
            self.assertIsNone(connection.decode(code), code)


if __name__ == "__main__":
    unittest.main()
