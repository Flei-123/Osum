from .common import Check, GREEN, YELLOW, RED, UNKNOWN, graded, integer, num

PAGE_LIMITS_S = {"example": (20, 60), "youtube": (40, 90)}
FAILED_STATES = ("no_window", "crashed", "stalled_no_network")


def page_check(data, label):
    prefix = "ff_%s_" % label
    state = data.get(prefix + "state")
    title = "Firefox %s" % label
    if state is None:
        return Check("ff_" + label, title, UNKNOWN, "not run")
    settle = num(data, prefix + "settle_s", -1)
    green_max, yellow_max = PAGE_LIMITS_S[label]
    detail = "state=%s wayd_ready=%ss settle=%ss rx=%s B procs=%s threads=%s rss=%s kB ticks fx/wayd/xremoted=%s/%s/%s" % (
        state, data.get(prefix + "wayd_ready_s", "?"), data.get(prefix + "settle_s", "?"), data.get(prefix + "rx_bytes", "?"),
        data.get(prefix + "procs", "?"), data.get(prefix + "threads", "?"), data.get(prefix + "rss_kb", "?"),
        data.get(prefix + "ticks", "?"), data.get(prefix + "wayd_ticks", "?"), data.get(prefix + "xremoted_ticks", "?"))
    if state in FAILED_STATES:
        return Check("ff_" + label, title, RED, detail)
    if state == "busy_not_settled":
        return Check("ff_" + label, title, YELLOW, detail + " (still burning CPU at deadline, check screenshot)")
    return Check("ff_" + label, title, graded(settle, green_max, yellow_max), detail)


def hang_lines(data, label):
    prefix = "thread_%s_" % label
    return [value for key, value in sorted(data.items(), key=lambda item: item[0]) if key.startswith(prefix)]


def firefox_checks(data):
    return [page_check(data, "example"), page_check(data, "youtube")]
