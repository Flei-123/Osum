import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import apkdb
import mkpkgs

DB = """P:libshared
V:1
p:so:libshared.so.1
F:usr/lib
R:libshared.so.1

P:appa
V:1
D:so:libshared.so.1 libonlya
F:usr/bin
R:appa

P:libonlya
V:1
p:so:libonlya.so

P:appb
V:1
D:so:libshared.so.1
F:usr/bin
R:appb

"""


def main():
    root = tempfile.mkdtemp()
    os.makedirs(os.path.join(root, "lib", "apk", "db"))
    with open(os.path.join(root, apkdb.DB), "w") as handle:
        handle.write(DB)
    packages = apkdb.parse(root)
    assert sorted(apkdb.closure(packages, ["appa"])) == ["appa", "libonlya", "libshared"], apkdb.closure(packages, ["appa"])
    shared, own = mkpkgs.plan(packages, [{"name": "appa"}, {"name": "appb"}])
    assert shared == ["libshared"], shared
    assert sorted(own["appa"]) == ["appa", "libonlya"], own
    assert own["appb"] == ["appb"], own
    print("3 checks")


main()
