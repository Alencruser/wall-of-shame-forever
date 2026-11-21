import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import appinfo  # noqa: E402
import wallofshame_companion as companion  # noqa: E402
import wowpath  # noqa: E402

ADDON_DIR = os.path.join("Interface", "AddOns", "WallOfShameForever")


def game_dir(root, name, version_line):
    d = os.path.join(root, name)
    os.makedirs(os.path.join(d, ADDON_DIR))
    with open(os.path.join(d, wowpath.ADDON_TOC), "w", encoding="utf-8") as f:
        f.write(f"## Interface: 16001\n## Title: Wall of Shame Forever\n{version_line}\n")
    return d


class AddonVersion(unittest.TestCase):
    def test_reads_the_toc_highest_of_the_folders(self):
        with tempfile.TemporaryDirectory() as root:
            a = game_dir(root, "_forever_", "## Version: v0.6.6")
            b = game_dir(root, "_classic_era_", "## Version: 0.10.1")
            self.assertEqual(wowpath.addon_version([a]), "0.6.6")
            self.assertEqual(wowpath.addon_version([a, b]), "0.10.1")

    def test_unknown(self):
        with tempfile.TemporaryDirectory() as root:
            c = game_dir(root, "_x_", "## Notes: no version")
            self.assertEqual(wowpath.addon_version([c, os.path.join(root, "missing")]), "")
            self.assertEqual(wowpath.addon_version([]), "")

    def test_header(self):
        with tempfile.TemporaryDirectory() as root:
            a = game_dir(root, "_forever_", "## Version: v0.6.6")
            self.assertEqual(wowpath.version_header([a]),
                             {"X-WoS-Versions": f"companion={appinfo.VERSION}; addon=0.6.6"})
            self.assertEqual(wowpath.version_header([])["X-WoS-Versions"],
                             f"companion={appinfo.VERSION}; addon=?")


class SenderSendsVersions(unittest.TestCase):
    def test_event_post_carries_the_header(self):
        with tempfile.TemporaryDirectory() as root:
            sender = companion.Sender(dry_run=False)
            sender.url, sender.key = "https://bot.example/shamewall/deaths", "k"
            sender.game_dirs = [game_dir(root, "_forever_", "## Version: v0.6.6")]
            reply = mock.Mock(status_code=200)
            with mock.patch.object(companion.requests, "post", return_value=reply) as post:
                sender._send({"id": "x", "type": "death"}, None)
            headers = post.call_args.kwargs["headers"]
            self.assertEqual(headers["Authorization"], "Bearer k")
            self.assertIn("addon=0.6.6", headers["X-WoS-Versions"])


if __name__ == "__main__":
    unittest.main()
