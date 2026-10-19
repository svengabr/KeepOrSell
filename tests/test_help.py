"""Tests for the shortcut list behind the question mark in Baganator's bag window (Help.lua)."""
import unittest

from addon import CORE_FILES, load


class HelpLineTests(unittest.TestCase):
    def setUp(self):
        self.rt, self.ns = load(CORE_FILES + ("Help.lua",))
        self.L = self.ns.L

    def lines(self, **db):
        table = self.ns.HelpLines(self.rt.table_from(db))
        return [(row[1], row[2]) for row in table.values()]

    def keys(self, **db):
        return [key for key, _ in self.lines(**db)]

    def test_lists_keep_click_and_slash_commands(self):
        rows = self.lines(keepClick=True, destroy=True)
        self.assertIn((self.L.HELP_KEEP_KEY, self.L.HELP_KEEP), rows)
        self.assertIn((self.L.HELP_DESTROY_KEY, self.L.HELP_DESTROY), rows)
        for command in ("/kos", "/kos kept", "/kos keep <item>", "/kos setup", "/kos export", "/kos import"):
            self.assertIn(command, self.keys(keepClick=True, destroy=True))

    def test_keep_click_comes_first(self):
        self.assertEqual(self.keys(keepClick=True, destroy=True)[0], self.L.HELP_KEEP_KEY)

    def test_switched_off_options_are_left_out(self):
        keys = self.keys(keepClick=False, destroy=False)
        self.assertNotIn(self.L.HELP_KEEP_KEY, keys)
        self.assertNotIn(self.L.HELP_DESTROY_KEY, keys)
        self.assertIn("/kos", keys)

    def test_every_row_has_a_text(self):
        for key, text in self.lines(keepClick=True, destroy=True):
            self.assertTrue(key)
            self.assertTrue(text)


if __name__ == "__main__":
    unittest.main()
