import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import results


class PruneResultsTest(unittest.TestCase):
    def make(self, folder, name, age):
        path = os.path.join(folder, name)
        with open(path, 'wb') as f:
            f.write(b'x')
        t = 1_700_000_000 + age
        os.utime(path, (t, t))

    def test_removes_oldest_by_time_not_by_name(self):
        with tempfile.TemporaryDirectory() as d:
            self.make(d, '235959-a.png', 0)
            self.make(d, '000001-b.png', 10)
            self.make(d, '000002-c.png', 20)
            self.assertEqual(results.prune_results(d, 2), 1)
            self.assertEqual(sorted(os.listdir(d)), ['000001-b.png', '000002-c.png'])

    def test_keeps_everything_below_limit(self):
        with tempfile.TemporaryDirectory() as d:
            self.make(d, 'a', 0)
            self.assertEqual(results.prune_results(d, 5), 0)
            self.assertEqual(os.listdir(d), ['a'])

    def test_missing_folder(self):
        self.assertEqual(results.prune_results('/nonexistent/dir/xyz', 3), 0)

    def test_zero_keep_removes_all(self):
        with tempfile.TemporaryDirectory() as d:
            self.make(d, 'a', 0)
            self.make(d, 'b', 1)
            self.assertEqual(results.prune_results(d, 0), 2)
            self.assertEqual(os.listdir(d), [])


if __name__ == '__main__':
    unittest.main()
