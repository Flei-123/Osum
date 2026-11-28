from .common import Check, GREEN, YELLOW, RED, UNKNOWN, MIB, integer, num

MIN_DOWNLOAD_BYTES = 50 * MIB
MIN_SPEED_MIB_S = 0.5
WLAN_SHARE_PERCENT = 90


def link_check(data):
    ok = data.get("wlan_phase") == "ready" and data.get("wlan_alive") == "yes" and data.get("wlan_err") == "0"
    losses = integer(data, "wlan_link_losses_after", integer(data, "wlan_link_losses", 0))
    detail = "phase=%s alive=%s err=%s ip=%s nets=%s losses=%s uplink=%s default=%s" % (
        data.get("wlan_phase", "?"), data.get("wlan_alive", "?"), data.get("wlan_err", "?"), data.get("wlan_ip", "-"),
        data.get("wlan_nets", "?"), losses, data.get("stack_uplink", "?"), data.get("net_default_iface", "?"))
    if not ok:
        return Check("wlan_link", "WLAN link", RED, detail)
    return Check("wlan_link", "WLAN link", YELLOW if losses else GREEN, detail)


def download_check(data):
    size = num(data, "dl_bytes", 0)
    expected = data.get("dl_expected_sha", "")
    hashes = (data.get("dl_fetch_bodysha"), data.get("dl_file_sha"))
    detail = "%.1f MiB in %s s (%s MiB/s), rc=%s http=%s" % (size / MIB, data.get("dl_seconds", "?"), data.get("dl_mib_per_s", "?"), data.get("dl_rc", "?"), data.get("dl_http_code", "?"))
    if size < MIN_DOWNLOAD_BYTES:
        return Check("download", "Download >= 50 MiB", RED, detail + ", too small or aborted")
    if not expected or any(value != expected for value in hashes):
        return Check("download", "Download >= 50 MiB", RED, detail + ", hash mismatch (fetch %s, file %s, expected %s)" % (hashes[0], hashes[1], expected))
    speed = num(data, "dl_mib_per_s", 0)
    return Check("download", "Download >= 50 MiB", YELLOW if speed < MIN_SPEED_MIB_S else GREEN, detail + ", hash ok")


def wlan_path_check(data):
    wlan = num(data, "dl_rx_wlan0_bytes", 0)
    usb = num(data, "dl_rx_usb0_bytes", 0)
    detail = "download rx: wlan0 %.1f MiB, usb0 %.1f MiB" % (wlan / MIB, usb / MIB)
    total = wlan + usb
    if total <= 0:
        return Check("wlan_path", "Download over WLAN", UNKNOWN, detail)
    if wlan * 100 / total >= WLAN_SHARE_PERCENT:
        return Check("wlan_path", "Download over WLAN", GREEN, detail)
    return Check("wlan_path", "Download over WLAN", YELLOW, detail + " (carried by wired/USB uplink, WLAN data path not exercised)")


def network_checks(data):
    return [link_check(data), download_check(data), wlan_path_check(data)]
