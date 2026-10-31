import sys

d = open(sys.argv[1], "rb").read()
f = []
at = 2
while len(f) < 3:
    while d[at:at + 1].isspace():
        at += 1
    s = at
    while not d[at:at + 1].isspace():
        at += 1
    f.append(int(d[s:at]))
at += 1
w = f[0]
x, y = int(sys.argv[2]), int(sys.argv[3])
o = at + (y * w + x) * 3
print(d[o], d[o + 1], d[o + 2])
