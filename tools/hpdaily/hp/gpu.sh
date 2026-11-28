GPU_WORDS="intelgpu intelgpuflip intelgpublit"

gpu_words_missing() {
    local word missing=""
    for word in $GPU_WORDS; do
        $BB grep -q -w "$word" /proc/cmdline || missing="$missing $word"
    done
    echo "$missing"
}

phase_gpu() {
    phase gpu
    kv gpu_words_missing "$(gpu_words_missing)"
    kv gpu_words_wanted "${GPU_WORDS_WANTED:-0}"
    local f
    for f in /proc/intelgpu*; do
        [ -e "$f" ] || continue
        safe_cat "$f" > "$OUT/gpu.txt"
        for key in edid_status mfg product mode plane_enabled panel_on edp_enabled ddi_buf_enabled dpll0_locked writes denied \
                flip_status flip_count blit_status blit_count hang_count; do
            kv "gpu_$key" "$($BB awk -F= -v k="$key" '$1 == k { print $2; exit }' "$OUT/gpu.txt")"
        done
        $BB grep -E '^(flip|blit|bcs|rcs|hang)' "$OUT/gpu.txt" | $BB head -12 | $BB awk '{ printf "gpu_extra_%d=%s\n", NR, $0 }' >> "$KV"
    done
    local frames1 frames2
    frames1=$(safe_cat /proc/gpu | $BB awk '$1 == "gpu0.frames" { print $2 }')
    $BB sleep 5
    frames2=$(safe_cat /proc/gpu | $BB awk '$1 == "gpu0.frames" { print $2 }')
    kv gpu_frames_start "$frames1"
    kv gpu_frames_delta_5s "$(( ${frames2:-0} - ${frames1:-0} ))"
    kv gpu_name "$(safe_cat /proc/gpu | $BB awk '$1 == "gpu0.name" { print $2 }')"
}
