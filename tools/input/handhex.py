# SPDX-License-Identifier: GPL-2.0-only
HAND_HEX = {
    ("touchpad-045e-09af", "1finger-down"):
        "04" + "0b" + "e803" + "bc02" + "00" * 20 + "d204" + "01" + "00",
    ("touchpad-045e-09af", "2finger-down"):
        "04" + "0b" + "e803" + "bc02" + "0f" + "dc05" + "8403" + "00" * 15 + "e204" + "02" + "00",
    ("touchscreen-045e-0c32", "tip-down-center"):
        "40" + "01" + "0040" + "0020",
    ("touchscreen-045e-0c32", "tip-down-max"):
        "40" + "01" + "ff7f" + "ff7f",
    ("pen-045e-0c32", "tip-pressure-2048"):
        "01" + "18" + "c012" + "100e" + "0008" + "2823" + "2823" + "9213" + "00" + "00",
    ("inputmode-045e-09af", "feat-mode-ptp"): "07" + "03",
}
