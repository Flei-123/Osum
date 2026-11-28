input_counters() {
    local diag
    diag=$(safe_cat /proc/inputdiag)
    echo "$diag" | $BB awk '$1 == "hid" { for (i = 2; i <= NF; i++) { split($i, a, "="); sum += a[2] } } END { print sum + 0 }'
}

hotkey_counters() {
    safe_cat /proc/hotkeys | $BB awk '$1 == "events" || $1 == "kbd" { for (i = 2; i <= NF; i++) { split($i, a, "="); if (a[2] ~ /^[0-9]+$/ && a[1] != "irq" && a[1] != "ghost") sum += a[2] } if ($1 == "events") sum += $2 } END { print sum + 0 }'
}

phase_input() {
    phase input
    local devs
    devs=$(safe_cat /proc/inputdevs)
    kv input_hid_devs "$(echo "$devs" | $BB head -1 | tok hid_devs)"
    kv input_i2c_ctrls "$(echo "$devs" | $BB head -1 | tok i2c_ctrls)"
    kv input_i2c_hung_ctrls "$(echo "$devs" | $BB grep -c 'state=hung')"
    kv input_usb_devices "$(safe_cat /proc/inputdiag | $BB awk '$1 == "usb" { for (i = 1; i <= NF; i++) if (index($i, "ndev=") == 1) sum += substr($i, 6) } END { print sum + 0 }')"
    kv input_ps2_present "$(safe_cat /proc/inputdiag | $BB awk '$1 == "ps2" { split($2, a, "="); print a[2] }')"
    kv input_kbd_irq "$(safe_cat /proc/hotkeys | $BB awk '$1 == "kbd" { for (i = 2; i <= NF; i++) if (index($i, "irq=") == 1) print substr($i, 5) }')"
    kv input_touchev "$(safe_cat /proc/touchev | $BB head -1 | $BB awk '{ print $1 }')"
    local window=${INPUT_WINDOW_S:-0}
    kv input_window_s "$window"
    if [ "$window" -gt 0 ]; then
        local before_hid before_hot
        before_hid=$(input_counters)
        before_hot=$(hotkey_counters)
        $BB sleep "$window"
        kv input_hid_delta "$(( $(input_counters) - before_hid ))"
        kv input_hotkey_delta "$(( $(hotkey_counters) - before_hot ))"
    fi
}
