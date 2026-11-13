"""The check of docs/annonces.md done by release.py --upload (release.py is at the repository root)."""

import importlib.util
import os
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
_spec = importlib.util.spec_from_file_location("release", os.path.join(ROOT, "release.py"))
release = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(release)  # only defines functions: main() runs under __main__ alone

TEXT = """<!--
  ## Addon vX.Y.Z (format in the header comment, indented: not a heading)
-->

## Addon v0.5.0 + Compagnon 0.6.0

- **Métiers** : ouvrez chaque fenêtre de métier

## compagnon v0.5.0

- Mise à jour depuis le menu

## Addon v0.4.4

- Le code reste sur un personnage sans guilde
Addon v0.4.3 named outside a heading
"""


class HasAnnouncementTest(unittest.TestCase):
    def test_addon(self):
        self.assertTrue(release.has_announcement(TEXT, "Addon", "v0.5.0"))
        self.assertTrue(release.has_announcement(TEXT, "Addon", "0.5.0"))  # "v" optional
        self.assertTrue(release.has_announcement(TEXT, "addon", "V0.4.4"))  # case-insensitive

    def test_companion(self):
        self.assertTrue(release.has_announcement(TEXT, "Compagnon", "0.6.0"))
        self.assertTrue(release.has_announcement(TEXT, "Compagnon", "0.5.0"))  # "compagnon v0.5.0"
        self.assertFalse(release.has_announcement(TEXT, "Addon", "0.6.0"))  # 0.6.0 is the companion's

    def test_missing(self):
        self.assertFalse(release.has_announcement(TEXT, "Addon", "v0.5.1"))
        self.assertFalse(release.has_announcement(TEXT, "Addon", "v0.4.3"))  # not in a heading
        self.assertFalse(release.has_announcement(TEXT, "Compagnon", "0.4.0"))
        self.assertFalse(release.has_announcement("", "Addon", "v0.5.0"))

    def test_longer_version_is_not_a_match(self):
        self.assertFalse(release.has_announcement("## Addon v0.5.01\n", "Addon", "v0.5.0"))
        self.assertFalse(release.has_announcement("## Addon v0.5.0.1\n", "Addon", "v0.5.0"))
        self.assertFalse(release.has_announcement("## Addon v10.5.0\n", "Addon", "v0.5.0"))
        self.assertTrue(release.has_announcement("## Addon v0.5.0 (13 nov.)\n", "Addon", "v0.5.0"))

    def test_other_heading_level_is_not_a_match(self):
        self.assertFalse(release.has_announcement("### Addon v0.5.0\n", "Addon", "v0.5.0"))
        self.assertFalse(release.has_announcement("# Addon v0.5.0\n", "Addon", "v0.5.0"))


if __name__ == "__main__":
    unittest.main()
