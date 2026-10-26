import hashlib
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "marke"))
import brandrender

CONF = os.path.join(ROOT, "marke.conf")
RENDER = os.path.join(ROOT, "tools", "marke", "brandrender.py")
MKFS = os.path.join(ROOT, "tools", "osum", "mkfs.py")
TEST_ENV = {
    "OSUM_MARKE_PRODUKT": "TestMarke",
    "OSUM_MARKE_KURZ": "testmarke",
    "OSUM_MARKE_HERSTELLER": "Test Vendor",
    "OSUM_MARKE_WEB": "https://test.example",
}
SOURCES = ("locale", "assets/apps", "assets/shapes")
OLD_NAMES = (b"OrientOS", b"XoffiOS", b"Orient OS")


def run(args, env=None):
    full = dict(os.environ)
    for key in list(full):
        if key.startswith("OSUM_MARKE_"):
            del full[key]
    full.update(env or {})
    return subprocess.run([sys.executable] + args, env=full, cwd=ROOT,
                          capture_output=True, text=True)


def tree_hash(path):
    digest = hashlib.sha256()
    for base, dirs, names in os.walk(path):
        dirs.sort()
        for name in sorted(names):
            full = os.path.join(base, name)
            digest.update(full.encode())
            with open(full, "rb") as f:
                digest.update(f.read())
    return digest.hexdigest()


class RenderBytes(unittest.TestCase):
    MAP = {"PRODUCT": b"Acme", "SLUG": b"acme", "VENDOR": b"Acme Inc",
           "WEB": b"https://acme.example"}

    def test_all_placeholders(self):
        out = brandrender.render_bytes(
            b"{{PRODUCT}} {{SLUG}} {{VENDOR}} {{WEB}}", self.MAP)
        self.assertEqual(out, b"Acme acme Acme Inc https://acme.example")

    def test_repeated(self):
        out = brandrender.render_bytes(b"{{PRODUCT}}{{PRODUCT}}", self.MAP)
        self.assertEqual(out, b"AcmeAcme")

    def test_unknown_placeholder_fails(self):
        with self.assertRaises(brandrender.UnknownPlaceholder):
            brandrender.render_bytes(b"x {{NOPE}} y", self.MAP)

    def test_unknown_placeholder_lenient(self):
        out = brandrender.render_bytes(b"x {{NOPE}} y", self.MAP, strict=False)
        self.assertEqual(out, b"x {{NOPE}} y")

    def test_lowercase_braces_untouched(self):
        data = b"{{not_a_token}} {x} {{ }}"
        self.assertEqual(brandrender.render_bytes(data, self.MAP), data)

    def test_binary_untouched(self):
        data = b"\0\1{{NOPE}}{{PRODUCT}}"
        self.assertEqual(brandrender.render_bytes(data, self.MAP), data)

    def test_strict_paths(self):
        self.assertTrue(brandrender.is_strict_path("/x/locale/de/messages"))
        self.assertTrue(brandrender.is_strict_path("/x/assets/apps/a.osp/INFO"))
        self.assertTrue(brandrender.is_strict_path("/x/buendel/a.osp/INFO"))
        self.assertFalse(brandrender.is_strict_path("/x/docs/readme.txt"))


class RenderCommand(unittest.TestCase):
    def test_default_brand_from_conf(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = run([RENDER, CONF, "locale", os.path.join(tmp, "o")])
            self.assertEqual(r.returncode, 0, r.stderr)
            conf = brandrender.brand_values.read_conf(CONF)
            with open(os.path.join(tmp, "o", "en", "messages"), "rb") as f:
                text = f.read()
            self.assertIn(("Install " + conf["PRODUKT"]).encode(), text)
            self.assertNotIn(b"{{", text)

    def test_env_overrides_conf(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = run([RENDER, CONF, "locale", os.path.join(tmp, "o")], TEST_ENV)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(os.path.join(tmp, "o", "en", "messages"), "rb") as f:
                self.assertIn(b"Install TestMarke", f.read())

    def test_unknown_placeholder_is_build_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "locale")
            os.makedirs(src)
            with open(os.path.join(src, "messages"), "w") as f:
                f.write("a.b = {{PRODUCT}} {{BOGUS}}\n")
            r = run([RENDER, CONF, src, os.path.join(tmp, "o")])
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("BOGUS", r.stderr)

    def test_overlong_name_is_build_error(self):
        r = run([RENDER, CONF, "locale", "/dev/null/never"],
                {"OSUM_MARKE_PRODUKT": "x" * 40})
        self.assertNotEqual(r.returncode, 0)

    def test_source_tree_not_modified(self):
        before = {s: tree_hash(os.path.join(ROOT, s)) for s in SOURCES}
        with tempfile.TemporaryDirectory() as tmp:
            for s in SOURCES:
                r = run([RENDER, CONF, s, os.path.join(tmp, s)], TEST_ENV)
                self.assertEqual(r.returncode, 0, r.stderr)
        after = {s: tree_hash(os.path.join(ROOT, s)) for s in SOURCES}
        self.assertEqual(before, after)

    def test_no_old_name_in_rendered_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            for s in SOURCES:
                r = run([RENDER, CONF, s, os.path.join(tmp, s)], TEST_ENV)
                self.assertEqual(r.returncode, 0, r.stderr)
            hits = []
            for base, _, names in os.walk(tmp):
                for name in names:
                    with open(os.path.join(base, name), "rb") as f:
                        data = f.read()
                    if b"\0" in data:
                        continue
                    for old in OLD_NAMES:
                        if old in data:
                            hits.append((os.path.join(base, name), old))
                    if b"{{" in data:
                        hits.append((os.path.join(base, name), b"{{"))
            self.assertEqual(hits, [])

    def test_no_old_name_in_sources(self):
        hits = []
        for s in SOURCES:
            for base, _, names in os.walk(os.path.join(ROOT, s)):
                for name in names:
                    with open(os.path.join(base, name), "rb") as f:
                        data = f.read()
                    if b"\0" in data:
                        continue
                    for old in OLD_NAMES:
                        if old in data:
                            hits.append((os.path.join(base, name), old))
        self.assertEqual(hits, [])


class ImageHook(unittest.TestCase):
    def build(self, tmp, host, env=None):
        img = os.path.join(tmp, "t.img")
        return run([MKFS, "build", img, "2000", "/d/",
                    "/d/f=" + host], env), img

    def test_image_gets_rendered_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            host = os.path.join(tmp, "assets", "INFO")
            os.makedirs(os.path.dirname(host))
            with open(host, "w") as f:
                f.write("name=Install {{PRODUCT}}\n")
            r, img = self.build(tmp, host, TEST_ENV)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(img, "rb") as f:
                data = f.read()
            self.assertIn(b"name=Install TestMarke", data)
            self.assertNotIn(b"{{PRODUCT}}", data)

    def test_image_rejects_unknown_in_strict_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            host = os.path.join(tmp, "locale", "messages")
            os.makedirs(os.path.dirname(host))
            with open(host, "w") as f:
                f.write("a = {{BOGUS}}\n")
            r, _ = self.build(tmp, host)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("BOGUS", r.stderr)

    def test_image_keeps_unknown_in_other_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            host = os.path.join(tmp, "payload.txt")
            with open(host, "w") as f:
                f.write("template {{BOGUS}} {{PRODUCT}}\n")
            r, img = self.build(tmp, host, TEST_ENV)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(img, "rb") as f:
                data = f.read()
            self.assertIn(b"template {{BOGUS}} TestMarke", data)


if __name__ == "__main__":
    unittest.main()
