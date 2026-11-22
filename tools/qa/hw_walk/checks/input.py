from kv import as_int, merge_tokens
from registry import group
from report import fail, info, verdict

G = "input"


@group(G, commands=["/bin/cat /proc/inputdevs", "/bin/cat /proc/hotkeys"])
def input_devices(ctx):
    kv = merge_tokens(ctx.text("/bin/cat /proc/inputdevs"))
    if not kv:
        return [fail(G, "/proc/inputdevs", "no answer")]
    out = [verdict(G, "I2C controllers found", as_int(kv.get("i2c_ctrls")) > 0, "ctrls=%s hung=%s" % (kv.get("i2c_ctrls"), kv.get("i2c_hung")))]
    out.append(verdict(G, "I2C-HID device bound (touchpad / touchscreen)", as_int(kv.get("i2c_devs")) > 0 or as_int(kv.get("hid_devs")) > 0,
                       "i2c_devs=%s hid_devs=%s aml=%s" % (kv.get("i2c_devs"), kv.get("hid_devs"), kv.get("i2c_aml"))))
    keys = merge_tokens(ctx.text("/bin/cat /proc/hotkeys"))
    out.append(info(G, "hotkeys", "events=%s actions=%s unknown=%s" % (keys.get("events"), keys.get("actions"), keys.get("unknown"))))
    return out
