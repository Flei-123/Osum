import os
import sys

APP_FIELDS = 3


def convert_plan(path):
    lines = []
    with open(path) as handle:
        for raw in handle.read().splitlines():
            fields = raw.split("\t")
            if fields[0] == "app" and len(fields) == APP_FIELDS:
                lines.append("%s\t%s\n" % (fields[1], fields[2]))
    with open(path, "w") as handle:
        handle.write("".join(lines))


def main():
    generations = os.path.join(sys.argv[1], "system", "generations")
    for name in sorted(os.listdir(generations)):
        plan = os.path.join(generations, name, "PLAN")
        if os.path.isfile(plan):
            convert_plan(plan)


main()
