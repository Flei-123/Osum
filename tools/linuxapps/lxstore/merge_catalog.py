import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SOURCE = os.path.join(HERE, "catalog-meta.json")
DEFAULT_TARGET = "/root/orientstore/werkzeug/unified_meta.json"


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def merge(target, source):
    added = []
    for app_id, entry in source["apps"].items():
        if app_id not in target["apps"]:
            target["apps"][app_id] = entry
            added.append(app_id)
    return added


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    parser.add_argument("--target", default=DEFAULT_TARGET)
    parser.add_argument("--dry", action="store_true")
    args = parser.parse_args(argv)
    target = load(args.target)
    added = merge(target, load(args.source))
    if added and not args.dry:
        tmp = args.target + ".merge.tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(target, indent=2, ensure_ascii=False) + "\n")
        os.replace(tmp, args.target)
    print("added %d: %s" % (len(added), " ".join(added)))


if __name__ == "__main__":
    main(sys.argv[1:])
