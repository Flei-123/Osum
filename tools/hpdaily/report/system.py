from .common import Check, GREEN, YELLOW, RED, UNKNOWN, graded, integer, num

BOOT_GREEN_S = 10
BOOT_YELLOW_S = 20
RAM_SHM_RED_PERCENT = 80


def build_check(data, expect_build):
    build = integer(data, "ota_installed_build")
    if build is None:
        return Check("build", "Build installed", RED, "ota status not readable")
    detail = "build %d, kernel commit check: %s" % (build, data.get("kernel_has_expected_commit", "not requested"))
    if expect_build is None:
        return Check("build", "Build installed", UNKNOWN, detail + ", no expected build given")
    if build < expect_build:
        return Check("build", "Build installed", RED, "%s, expected %d (HP is behind main)" % (detail, expect_build))
    pending = data.get("ota_pending") == "1"
    return Check("build", "Build installed", YELLOW if pending else GREEN, detail + (", update pending" if pending else ""))


def boot_check(data):
    seconds = num(data, "boot_taskbar_s")
    status = graded(seconds, BOOT_GREEN_S, BOOT_YELLOW_S)
    detail = "kernel start to taskbar %s s, uptime %s s" % (data.get("boot_taskbar_s", "?"), data.get("uptime_s", "?"))
    if seconds is not None and seconds < 0:
        detail = "no boot-time launcher line in taskbar.log, uptime %s s" % data.get("uptime_s", "?")
    return Check("boot", "Boot time", status, detail)


def reset_check(data):
    last = data.get("watchdog_last_boot", "")
    crashes = integer(data, "crash_files_since_boot", 0)
    detail = "last_boot=%s, crash files since boot %d, total %s" % (last or "?", crashes, data.get("crash_files_total", "?"))
    if last and last != "normal":
        return Check("reset", "Reset history", RED, detail)
    return Check("reset", "Reset history", YELLOW if crashes else GREEN, detail)


def ram_check(data):
    objects = num(data, "shm_objects")
    limit = num(data, "shm_objects_max")
    detail = "free %s of %s kB, shm %s of %s" % (data.get("ram_free_kb", "?"), data.get("ram_total_kb", "?"), data.get("shm_objects", "?"), data.get("shm_objects_max", "?"))
    if objects is not None and limit and objects * 100 / limit > RAM_SHM_RED_PERCENT:
        return Check("ram", "RAM", RED, detail + " (shm table nearly full)")
    return Check("ram", "RAM", GREEN if objects is not None else UNKNOWN, detail)


def klog_check(data):
    bad = integer(data, "klog_new_bad")
    if bad is None:
        return Check("klog", "Kernel log", UNKNOWN, "not collected")
    new_crash = integer(data, "crash_files_end", 0) - integer(data, "crash_files_total", 0)
    hits = [value for key, value in sorted(data.items()) if key.startswith("klog_hit_")]
    detail = "new lines %s, bad lines %d, new crash files %d" % (data.get("klog_new_lines", "?"), bad, new_crash)
    if hits:
        detail += "; " + " | ".join(hits[:3])
    return Check("klog", "Kernel log", RED if bad or new_crash > 0 else GREEN, detail)


def system_checks(data, expect_build):
    return [build_check(data, expect_build), boot_check(data), reset_check(data), ram_check(data), klog_check(data)]
