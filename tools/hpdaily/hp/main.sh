run_all() {
    $BB mkdir -p "$OUT"
    trap fx_restore EXIT
    kv hpdaily_version 1
    klog_mark
    phase_identity
    phase_gpu
    phase_input
    phase_net
    fx_prepare
    fx_stop
    phase_cpu nofx "${IDLE_WINDOW_S:-10}"
    fx_load example "${URL_EXAMPLE:-https://example.com/}" "${FX_DEADLINE_EXAMPLE_S:-90}"
    fx_load youtube "${URL_YOUTUBE:-https://www.youtube.com/watch?v=jNQXAC9IVRk}" "${FX_DEADLINE_YOUTUBE_S:-150}"
    phase_cpu withfx "${IDLE_WINDOW_S:-10}"
    phase_klog "$(grep_klog_start)"
    fx_restore
    phase done
    kv done 1
}

grep_klog_start() {
    $BB awk -F= '$1 == "klog_lines_start" { print $2 }' "$KV"
}

launch() {
    $BB rm -rf "$OUT"
    $BB mkdir -p "$OUT"
    ( $BB sh "$HPD_ROOT/hpdaily.sh" run > "$OUT/run.log" 2>&1 < /dev/null & )
    echo started
}
