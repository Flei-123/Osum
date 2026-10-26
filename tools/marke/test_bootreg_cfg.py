import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bootreg_cfg


class BootregCfgTest(unittest.TestCase):
    def test_every_legacy_slug_becomes_alt(self):
        text = bootreg_cfg.render("testslug", "TestName")
        self.assertTrue(text.startswith("slug=testslug\nname=TestName\n"))
        for legacy in bootreg_cfg.legacy_slugs():
            self.assertIn("alt=" + legacy + "\n", text)

    def test_legacy_slug_itself_has_no_alt(self):
        legacy = bootreg_cfg.legacy_slugs()[0]
        self.assertNotIn("alt=", bootreg_cfg.render(legacy, "TestName"))

    def test_registry_not_empty(self):
        self.assertTrue(bootreg_cfg.legacy_slugs())


if __name__ == "__main__":
    unittest.main()
