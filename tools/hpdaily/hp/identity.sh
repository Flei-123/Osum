phase_identity() {
    phase identity
    kv started_epoch "$($BB date +%s)"
    kv uptime_s "$($BB awk '{ print int($1) }' /proc/uptime)"
    kv loadavg "$(safe_cat /proc/loadavg)"
    local ota
    ota=$($BB timeout 25 /bin/ota system status 2>&1 | $BB head -4)
    kv ota_installed_build "$(echo "$ota" | $BB awk '/installed build/ { print $4; exit }')"
    kv ota_pending "$(echo "$ota" | $BB grep -c 'no update pending' | $BB awk '{ print ($1 > 0) ? 0 : 1 }')"
    kv kernel_expected_commit "${EXPECT_KERNEL_COMMIT:-}"
    if [ -n "${EXPECT_KERNEL_COMMIT:-}" ]; then
        kv kernel_has_expected_commit "$($BB timeout 5 /bin/grep -c "$EXPECT_KERNEL_COMMIT" /proc/version)"
    fi
    kv brand_product "$(safe_cat /proc/brand | $BB awk -F= '$1 == "product" { print $2 }')"
    local btime
    btime=$($BB awk '$1 == "btime" { print $2 }' /proc/stat)
    kv boot_epoch "$btime"
    kv boot_taskbar_s "$($BB awk -v boot="$btime" '
        /app=launcher/ {
            t = 0; up = -1
            for (i = 1; i <= NF; i++) {
                if (substr($i, 1, 2) == "t=") t = substr($i, 3) + 0
                if (substr($i, 1, 3) == "up=") up = substr($i, 4) + 0
            }
            if (up >= 0 && t - up - boot >= -6 && t - up - boot <= 6) last = up
        }
        END { print (last == "" ? -1 : last) }' /var/log/taskbar.log)"
    kv watchdog_last_boot "$(safe_cat /proc/watchdog | $BB awk '$1 == "last_boot" { print $2 }')"
    kv watchdog_starved "$(safe_cat /proc/watchdog | $BB awk '$1 == "starved" { print $2 }')"
    kv crash_files_since_boot "$($BB ls /var/crash 2>/dev/null | $BB awk -v boot="$btime" '{ n = $1 + 0; if (n >= boot - 300) c++ } END { print c + 0 }')"
    kv crash_files_total "$($BB ls /var/crash 2>/dev/null | $BB wc -l | $BB awk '{ print $1 }')"
    kv ram_total_kb "$(safe_cat /proc/meminfo | $BB awk '$1 == "MemTotal:" { print $2 }')"
    kv ram_free_kb "$(safe_cat /proc/meminfo | $BB awk '$1 == "MemFree:" { print $2 }')"
    kv ram_frames_free "$(safe_cat /proc/meminfo | $BB awk '$1 == "FramesFree:" { print $2 }')"
    kv ram_frames_free_low "$(safe_cat /proc/meminfo | $BB awk '$1 == "FramesFreeLow:" { print $2 }')"
    kv shm_objects "$(safe_cat /proc/meminfo | $BB awk '$1 == "ShmObjects:" { print $2 }')"
    kv shm_objects_max "$(safe_cat /proc/meminfo | $BB awk '$1 == "ShmObjectsMax:" { print $2 }')"
    kv cpus_online "$(safe_cat /proc/cpus | $BB head -1 | tok cpus_online)"
}
