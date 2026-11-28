wlan_status() {
    safe_cat /proc/wlan > "$OUT/wlan.txt"
    kv wlan_phase "$($BB awk -F= '$1 == "phase" { print $2; exit }' "$OUT/wlan.txt")"
    kv wlan_alive "$(tok alive < "$OUT/wlan.txt")"
    kv wlan_err "$($BB awk -F= '$1 == "err" { print $2; exit }' "$OUT/wlan.txt")"
    kv wlan_driver "$(tok driver < "$OUT/wlan.txt")"
    kv wlan_link_losses "$(tok losses < "$OUT/wlan.txt")"
    kv wlan_reconnects "$(tok reconnects < "$OUT/wlan.txt")"
    kv wlan_ip "$($BB awk '$1 ~ /^ip=/ { sub(/^ip=/, "", $1); print $1; exit }' "$OUT/wlan.txt")"
    kv wlan_nets "$(tok nets < "$OUT/wlan.txt")"
    kv wlan_fw_ver "$(tok fw_ver < "$OUT/wlan.txt")"
    kv wlan_rx_mpdu "$($BB awk '$1 == "diag:" && $2 == "rx" { for (i = 3; i <= NF; i++) if (index($i, "mpdu=") == 1) print substr($i, 6) }' "$OUT/wlan.txt")"
    kv stack_uplink "$($BB awk '$1 == "stack" { for (i = 2; i <= NF; i++) if (index($i, "uplink=") == 1) print substr($i, 8) }' "$OUT/wlan.txt")"
    kv stack_dns "$($BB awk '$1 == "stack" { for (i = 2; i <= NF; i++) if (index($i, "dns=") == 1) print substr($i, 5) }' "$OUT/wlan.txt")"
    kv net_default_iface "$(safe_cat /proc/net/connectivity | $BB awk '/default/ { print $1; exit }')"
    kv net_connectivity "$(safe_cat /proc/net/connectivity | $BB awk '{ printf "%s%s=%s", sep, $1, $2; sep = "," }')"
}

fetch_field() {
    $BB awk -v key="$1" '$1 == "fetch:" && $2 == key { print $3; exit }' "$2"
}

phase_download() {
    phase download
    local url=${DL_URL:-https://store.fleitec.com/osum/hpdaily/blob64m.bin}
    local limit=${DL_TIMEOUT_S:-240}
    local file=$OUT/dl.bin
    $BB timeout 60 /bin/fetch -o "$OUT/dl.sha" "${url%.bin}.sha256" > "$OUT/fetch_sha.out" 2>&1
    local expected
    expected=$($BB head -c 64 "$OUT/dl.sha" 2>/dev/null)
    local usb0=$(if_rx usb0) wlan0=$(if_rx wlan0) t0
    t0=$(up_cs)
    local want=${DL_EXPECT_BYTES:-67108864} size rc
    $BB rm -f "$file"
    $BB timeout "$limit" /bin/fetch -o "$file" "$url" > "$OUT/fetch.out" 2>&1
    rc=$?
    size=$($BB wc -c < "$file" 2>/dev/null | $BB awk '{ print $1 + 0 }')
    kv dl_rc "$rc"
    kv dl_expect_bytes "$want"
    local t1
    t1=$(up_cs)
    kv dl_url "$url"
    kv dl_require_wlan "${DL_REQUIRE_WLAN:-0}"
    kv dl_default_iface "$(safe_cat /proc/net/connectivity | $BB awk '/default/ { print $1; exit }')"
    kv dl_bytes "$size"
    kv dl_seconds "$(ratio $(( t1 - t0 )) 100)"
    kv dl_mib_per_s "$($BB awk -v b="$size" -v cs=$(( t1 - t0 )) 'BEGIN { if (cs > 0) printf "%.2f", b / 1048576 / (cs / 100); else print 0 }')"
    kv dl_http_code "$(fetch_field code "$OUT/fetch.out")"
    kv dl_rx_usb0_bytes "$(( $(if_rx usb0) - usb0 ))"
    kv dl_rx_wlan0_bytes "$(( $(if_rx wlan0) - wlan0 ))"
    kv dl_expected_sha "$expected"
    local s0 s1
    s0=$(up_cs)
    kv dl_file_sha "$($BB timeout 180 $BB sha256sum "$file" 2>/dev/null | $BB awk '{ print $1 }')"
    s1=$(up_cs)
    kv dl_hash_seconds "$(ratio $(( s1 - s0 )) 100)"
    $BB rm -f "$file" "$OUT/dl.sha"
}

phase_net() {
    phase net
    wlan_status
    phase_download
    wlan_status_after
}

wlan_status_after() {
    kv wlan_link_losses_after "$(safe_cat /proc/wlan | tok losses)"
    kv wlan_err_after "$(safe_cat /proc/wlan | $BB awk -F= '$1 == "err" { print $2; exit }')"
}
