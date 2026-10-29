import sys

cycles = int(sys.argv[1])
shot_every = int(sys.argv[2])
lines = [
    "warteauf 'launcher: ready' || 120",
    "warte 6",
]
for i in range(1, cycles + 1):
    lines += [
        "marke (?m)^launcher: start /apps/explorer",
        "taste meta_l",
        "warte 3",
    ]
    if shot_every and i % shot_every == 0:
        lines.append("foto c%03d-menu" % i)
    lines += [
        "tippe file",
        "warte 1.5",
    ]
    if shot_every and i % shot_every == 0:
        lines.append("foto c%03d-typed" % i)
    lines += [
        "taste ret",
        "warteneu (?m)^launcher: start /apps/explorer || 25",
        "marke (?m)^explorer: ready",
        "warteneu (?m)^explorer: ready || 25",
        "warte 2",
        "taste alt-f4",
        "warte 2",
    ]
print("\n".join(lines))
