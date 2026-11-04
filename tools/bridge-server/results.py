import os


def prune_results(folder, keep):
    try:
        names = os.listdir(folder)
    except OSError:
        return 0
    stamped = []
    for name in names:
        path = os.path.join(folder, name)
        try:
            stamped.append((os.stat(path).st_mtime_ns, name, path))
        except OSError:
            continue
    stamped.sort()
    removed = 0
    for _, _, path in stamped[:max(0, len(stamped) - keep)]:
        try:
            os.remove(path)
            removed += 1
        except OSError:
            pass
    return removed
