import sys

rows = int(sys.argv[1])
head = open(sys.argv[2]).read().split("klick 500,700")[0]
out = [head.rstrip("\n"), "klick 500,700", "warte 2"]
for i in range(1, rows + 1):
    out.append("tippe ROW%02d" % i)
    out.append("taste ret")
    if i % 6 == 0:
        out.append("warte 1")
out.append("tippe END")
out.append("warte 3")
out.append("foto end")
print("\n".join(out))
