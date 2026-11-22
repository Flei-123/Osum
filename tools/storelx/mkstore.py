import argparse
import os
import sys
import tempfile

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "linuxapps", "lxstore"))
import mkpkgs

APP_FIELDS = {"name": "stubapp", "title": "Stub app", "summary": "Stub Linux app", "keys": "stub,linux", "category": "Tools",
              "icon": "terminal", "version": "1.0.0"}
RUNTIME_FIELDS = {"name": "linuxrt", "title": "Linux runtime", "summary": "Shared libraries for Linux apps", "keys": "linux,runtime",
                  "category": "System", "icon": "terminal", "version": "1.0.0"}
APP_CONFIG = "exec=stubapp one two\nproc=stubapp\ncheck=/usr/bin/stubapp\nenv=STUB_MARK=yes\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures", required=True)
    parser.add_argument("--launcher", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--key", required=True)
    args = parser.parse_args()
    args.limit = mkpkgs.packsplit.DEFAULT_LIMIT
    os.makedirs(args.out)
    with tempfile.TemporaryDirectory() as work:
        mkpkgs.build_package(RUNTIME_FIELDS, mkpkgs.RUNTIME_CONFIG, [], os.path.join(args.fixtures, "linuxrt.tar"), args, work, args.out)
        mkpkgs.build_package(APP_FIELDS, APP_CONFIG, [mkpkgs.RUNTIME], os.path.join(args.fixtures, "stubapp.tar"), args, work, args.out)
    mkpkgs.sign(args.out, args.key)


if __name__ == "__main__":
    main()
