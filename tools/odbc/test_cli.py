"""CLI error handling: missing token file / local file must not print a traceback."""
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def run(*args):
    return subprocess.run([sys.executable, "-I", os.path.join(HERE, "odbc.py")] + list(args),
                          capture_output=True, text=True, timeout=30)


class CliErrors(unittest.TestCase):
    def test_missing_token_file(self):
        r = run("--port", "unix:/nonexistent.sock", "--token-file", "/nonexistent/tok", "info")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("cannot read token file", r.stderr)
        self.assertNotIn("Traceback", r.stderr)

    def test_missing_port_is_clean_error(self):
        r = run("--port", "unix:/nonexistent.sock", "ping")
        self.assertEqual(r.returncode, 5)
        self.assertNotIn("Traceback", r.stderr)


if __name__ == "__main__":
    unittest.main()
