from .common import Check, GREEN, YELLOW, RED, UNKNOWN, IDLE_CORE_GREEN, IDLE_CORE_YELLOW, integer

GPU_FLAG_OK = "7"


def idle_check(data, label, title):
    cores = sorted((key, int(value)) for key, value in data.items() if key.startswith("cpu_%s_cpu" % label) and key.endswith("_idle_pct"))
    if not cores:
        return Check("idle_" + label, title, UNKNOWN, "not measured")
    low = min(value for _, value in cores)
    detail = ", ".join("%s %d%%" % (key.split("_")[2], value) for key, value in cores)
    detail += " idle over %ss" % data.get("cpu_%s_window_s" % label, "?")
    if low < 0:
        return Check("idle_" + label, title, UNKNOWN, detail)
    if low >= IDLE_CORE_GREEN:
        return Check("idle_" + label, title, GREEN, detail)
    return Check("idle_" + label, title, YELLOW if low >= IDLE_CORE_YELLOW else RED, detail)


def gpu_flag(data, key, label):
    value = data.get(key, "")
    if not value:
        return None, "%s absent (boot word not set)" % label
    return value == GPU_FLAG_OK, "%s=%s" % (label, value)


def gpu_check(data):
    base = data.get("gpu_edid_status") == "ok" and data.get("gpu_plane_enabled") == "1" and data.get("gpu_panel_on") == "1"
    denied = integer(data, "gpu_denied", 0)
    detail = "edid=%s %s %s mode=%s plane=%s panel=%s writes=%s denied=%d frames+%s/5s" % (
        data.get("gpu_edid_status", "?"), data.get("gpu_mfg", ""), data.get("gpu_product", ""), data.get("gpu_mode", "?"),
        data.get("gpu_plane_enabled", "?"), data.get("gpu_panel_on", "?"), data.get("gpu_writes", "?"), denied, data.get("gpu_frames_delta_5s", "?"))
    if "gpu_edid_status" not in data:
        return Check("gpu", "Intel GPU", UNKNOWN, "no /proc/intelgpu")
    flip_ok, flip_text = gpu_flag(data, "gpu_flip_status", "flip_status")
    blit_ok, blit_text = gpu_flag(data, "gpu_blit_status", "blit_status")
    detail += "; %s; %s" % (flip_text, blit_text)
    if not base or denied:
        return Check("gpu", "Intel GPU", RED, detail)
    if flip_ok is False or blit_ok is False:
        return Check("gpu", "Intel GPU", YELLOW, detail)
    return Check("gpu", "Intel GPU", GREEN if flip_ok and blit_ok else YELLOW, detail)


def input_checks(data):
    hid = integer(data, "input_hid_devs", 0)
    hung = integer(data, "input_i2c_hung_ctrls", 0)
    usb = integer(data, "input_usb_devices", 0)
    touchpad = Check("touchpad", "Touchpad", GREEN if hid > 0 else RED,
                     "hid_devs=%d i2c_hung_ctrls=%d usb_devices=%d" % (hid, hung, usb) + ("" if hid > 0 else " (no touchpad enumerated)"))
    keyboard = Check("keyboard", "Keyboard", GREEN if data.get("input_ps2_present") == "1" else RED,
                     "ps2 present=%s kbd_irq=%s" % (data.get("input_ps2_present", "?"), data.get("input_kbd_irq", "?")))
    window = integer(data, "input_window_s", 0)
    if window > 0:
        events = integer(data, "input_hid_delta", 0) + integer(data, "input_hotkey_delta", 0)
        activity = Check("input_activity", "Input events in window", GREEN if events > 0 else RED, "%d events in %d s" % (events, window))
        return [touchpad, keyboard, activity]
    return [touchpad, keyboard]


def hardware_checks(data):
    return [idle_check(data, "nofx", "Idle CPU per core (no Firefox)"), idle_check(data, "withfx", "Idle CPU per core (Firefox loaded)"), gpu_check(data)]
