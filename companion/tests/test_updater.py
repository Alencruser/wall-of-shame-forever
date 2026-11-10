import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import updater  # noqa: E402


def asset(name, size=10):
    return {"name": name, "size": size,
            "browser_download_url": f"https://github.com/x/releases/download/t/{name}"}


ALL_ASSETS = [asset("WallOfShameCompanion.exe"), asset("WallOfShameCompanion.dmg"),
              asset("WallOfShameCompanion-Intel.dmg")]

# what the GitHub API gives: addon releases (v0.4.x) mixed with the companion ones, newest first
RELEASES = [
    {"tag_name": "v0.9.0", "draft": False, "prerelease": False, "assets": []},
    {"tag_name": "companion-v0.6.0", "draft": True, "prerelease": False, "assets": ALL_ASSETS},
    {"tag_name": "companion-v0.5.1", "draft": False, "prerelease": True, "assets": ALL_ASSETS},
    {"tag_name": "companion-v0.5.0", "draft": False, "prerelease": False, "assets": ALL_ASSETS},
    {"tag_name": "companion-v0.10.0-beta", "draft": False, "prerelease": False, "assets": ALL_ASSETS},
    {"tag_name": "companion-v0.4.0", "draft": False, "prerelease": False, "assets": ALL_ASSETS},
    {"tag_name": "v0.4.3", "draft": False, "prerelease": False, "assets": []},
]


class VersionTest(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(updater.parse_version("companion-v0.4.1"), (0, 4, 1))
        self.assertEqual(updater.parse_version("0.10.2"), (0, 10, 2))
        for bad in ["", None, "v0.4.3", "companion-v0.4", "companion-v0.4.1-beta", "companion-vx.y.z"]:
            self.assertIsNone(updater.parse_version(bad), bad)

    def test_newer(self):
        self.assertTrue(updater.is_newer("companion-v0.5.0", "0.4.0"))
        self.assertTrue(updater.is_newer("companion-v0.10.0", "0.9.9"))  # numbers, not text
        self.assertFalse(updater.is_newer("companion-v0.4.0", "0.4.0"))
        self.assertFalse(updater.is_newer("companion-v0.3.9", "0.4.0"))
        self.assertFalse(updater.is_newer("v0.9.0", "0.4.0"))  # an addon release
        self.assertFalse(updater.is_newer("garbage", "0.4.0"))


class ReleaseTest(unittest.TestCase):
    def test_pick_release(self):
        # skips addon tags, drafts, prereleases and tags that are not X.Y.Z
        self.assertEqual(updater.pick_release(RELEASES)["tag_name"], "companion-v0.5.0")

    def test_pick_release_none(self):
        self.assertIsNone(updater.pick_release([]))
        self.assertIsNone(updater.pick_release(None))
        self.assertIsNone(updater.pick_release([{"tag_name": "v0.4.3"}, "junk"]))

    def test_asset_per_system(self):
        release = updater.pick_release(RELEASES)
        cases = [("win32", "AMD64", "WallOfShameCompanion.exe"),
                 ("darwin", "arm64", "WallOfShameCompanion.dmg"),
                 ("darwin", "x86_64", "WallOfShameCompanion-Intel.dmg")]
        for system, machine, name in cases:
            self.assertEqual(updater.pick_asset(release, system, machine)["name"], name)
        self.assertIsNone(updater.pick_asset(release, "linux", "x86_64"))

    def test_missing_asset(self):
        release = {"tag_name": "companion-v0.5.0", "assets": [asset("WallOfShameCompanion.exe")]}
        self.assertIsNone(updater.pick_asset(release, "darwin", "arm64"))
        self.assertIsNotNone(updater.pick_asset(release, "win32", "AMD64"))


class CheckTest(unittest.TestCase):
    def setUp(self):
        updater.STATUS.update(state="idle", version="", progress=0, manual=False)
        updater._log = lambda _msg: None

    def fake_get(self, data=None, error=None):
        response = mock.Mock()
        response.json.return_value = data
        response.raise_for_status.side_effect = error
        return mock.patch.object(updater.requests, "get", return_value=response)

    def test_available(self):
        with self.fake_get(RELEASES), mock.patch.object(updater, "VERSION", "0.4.0"), \
                mock.patch.object(updater.sys, "platform", "win32"):
            self.assertEqual(updater.check(manual=False), "available")
        self.assertEqual(updater.STATUS["version"], "0.5.0")
        self.assertTrue(updater.clickable())
        self.assertIn("v0.5.0 available", updater.menu_text())

    def test_up_to_date(self):
        with self.fake_get(RELEASES), mock.patch.object(updater, "VERSION", "0.5.0"):
            self.assertEqual(updater.check(manual=True), "uptodate")
            self.assertEqual(updater.menu_text(), "Up to date (v0.5.0)")
            self.assertEqual(updater.check(manual=False), "idle")  # background: nothing in the menu
        self.assertEqual(updater.menu_text(), "")
        self.assertFalse(updater.clickable())

    def test_failure_never_raises(self):
        with self.fake_get(error=updater.requests.HTTPError("403 rate limit")):
            self.assertEqual(updater.check(manual=True), "failed")
        updater.STATUS.update(state="available", version="0.5.0")
        with self.fake_get(error=updater.requests.ConnectionError("offline")):
            # a background failure keeps the update offered in the menu
            self.assertEqual(updater.check(manual=False), "available")

    def test_bad_json(self):
        with self.fake_get({"message": "Not Found"}):
            self.assertEqual(updater.check(manual=True), "uptodate")


if __name__ == "__main__":
    unittest.main()
