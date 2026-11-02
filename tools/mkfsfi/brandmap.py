import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "marke"))
import brandrender


def main(argv):
    mapping = brandrender.image_mapping()
    with open(argv[1], "wb") as f:
        for name in sorted(mapping):
            f.write(name.encode("ascii") + b"=" + mapping[name] + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
