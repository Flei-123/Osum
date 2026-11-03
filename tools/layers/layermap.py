import os

FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "layers.tsv")


def load(path=FILE):
    order = []
    rules = []
    with open(path) as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if parts[0] == "layer":
                order.append(parts[1])
            else:
                rules.append((parts[0], parts[1]))
    rules.sort(key=lambda r: -len(r[0]))
    return order, rules


def layer_of(path, rules):
    for prefix, layer in rules:
        if prefix.endswith("/."):
            if os.path.dirname(path) == prefix[:-2]:
                return layer
            continue
        if path == prefix or path.startswith(prefix if prefix.endswith("/") else prefix + "/"):
            return layer
    return None
