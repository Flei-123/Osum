import sys


def load(p):
    return open(p, "rb").read()


ref, ours, max_mean, max_big = load(sys.argv[1]), load(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4])
if len(ref) != len(ours) or not ref:
    print("size mismatch")
    sys.exit(2)
total = sum(abs(a - b) for a, b in zip(ref, ours))
big = sum(1 for i in range(0, len(ref), 4) if max(abs(ref[i + k] - ours[i + k]) for k in range(4)) > 2)
mean = total / len(ref)
print("mean=%.4f big=%d" % (mean, big))
sys.exit(0 if mean <= max_mean and big <= max_big else 1)
