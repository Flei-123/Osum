echo "== 15. relocation of data beyond the new end (end-placed images) =="
rfull() {
    local name=$1 mib=$2 target_mib=$3 disk="$D/$1.disk" psize target code
    mksparse "$disk" "$((mib * 2048))"
    sgdisk -o -n 1:2048:0 -t 1:0700 "$disk" >/dev/null 2>&1
    psize=$(sgdisk -i 1 "$disk" | awk '/Partition size/{print $3}')
    python3 -I tools/ntfsshrink/endmake.py "$D" "$name" "$psize" >/dev/null || { bad "endmake $name"; return 1; }
    dd if="$D/$name.part" of="$disk" bs=512 seek=2048 conv=notrunc 2>/dev/null
    mv "$D/$name.part" "$D/$name.orig"
    target=$((target_mib * 2048))
    echo "$psize" > "$D/$name.psize"; echo "$target" > "$D/$name.target"
    cp "$disk" "$D/$name.pre"
    "$SHC" "$disk" r 2048 "$disk" "$target" > "$D/$name.run" 2>&1
    code=$(awk -F= '$1 == "code" { print $2 }' "$D/$name.run")
    awk -F= '$1 == "writes" { print $2 }' "$D/$name.run" > "$D/$name.writes"
    if [ "$code" != 0 ]; then bad "$name: relocating shrink returned code $code"; return 1; fi
    if res=$(python3 -I tools/ntfsshrink/shrinkcheck.py "$disk" gpt 2048 "$psize" "$target" "$D/$name.orig" "$D/$name.files" "$D/unit" tools/ntfsshrink/check.py reloc 2>&1); then
        ok "$name: $psize -> $target sectors in $(cat "$D/$name.writes") writes; data moved below the reserve, \$MFTMirr moved, all file hashes, ntfsresize/ntfsfix clean"
    else
        bad "$name: $(echo "$res" | tr '\n' ';')"
    fi
}
rfull tail4k 65 32
rfull tail512 49 28
rfull tail64k 65 32
rfull frag4k 65 32
RT="$D/tail4k"
rmut() {
    local label=$1 file=$2 expr=$3
    rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
    sed -i "$expr" "$D/mutlib/ntfsshrink/$file"
    if cmp -s "lib/ntfsshrink/$file" "$D/mutlib/ntfsshrink/$file"; then bad "mutation '$label' did not change the source"; return; fi
    if ! FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutexe" tools/ntfsshrink/shrinkhost.fi > "$D/mut.log" 2>&1; then bad "mutation '$label' does not build"; return; fi
    cp "$RT.pre" "$D/m.disk"
    "$D/mutexe" "$D/m.disk" r 2048 "$D/m.disk" "$(cat "$RT.target")" > "$D/m.out" 2>&1
    if python3 -I tools/ntfsshrink/shrinkcheck.py "$D/m.disk" gpt 2048 "$(cat "$RT.psize")" "$(cat "$RT.target")" "$RT.orig" "$RT.files" "$D/unit" tools/ntfsshrink/check.py reloc > "$D/m.chk" 2>&1; then
        bad "mutation '$label' was not detected"
    else
        ok "relocation mutation '$label' detected ($(head -1 "$D/m.chk" | cut -c1-50))"
    fi
    rm -f "$D/m.disk" "$D/mutexe"
}
rmut "data copy skipped" reloc.fi 's|r = copy_clusters(v, c, src, dst, len)|r = codes.E_OK|'
rmut "record patch skipped" reloc.fi 's|mpatch.apply((\*b).rec, &(\*j).patch)|bytes.zero(0, 0)|'
rmut "source clusters never freed" reloc.fi 's|return balloc.set_range(v, (\*c).bp, (\*c).be, (\*j).src, (\*j).len, false, (\*c).sbuf)|return codes.E_OK|'
rmut "allocation limit ignored" reloc.fi 's|(\*c).limit = limit|(*c).limit = (*v).clusters|'
rmut "mirror boot field not updated" reloc.fi 's|r = set_mirror_boot(v, b, (\*j).dst)|r = codes.E_OK|'
echo "== 16. power loss at every write of a relocating shrink =="
rfull fuzz4k 41 28
rfuzz() {
    local exe=$1 label=$2 expect=$3 w="$D/fzr" res rc
    mkdir -p "$w"
    res=$(python3 -I tools/ntfsshrink/shrinkfuzz.py "$exe" "$D/fuzz4k.pre" "$D/fuzz4k.disk" gpt 2048 "$(cat "$D/fuzz4k.psize")" "$(cat "$D/fuzz4k.target")" "$(cat "$D/fuzz4k.writes")" "$D/fuzz4k.files" "$w" reloc 2>&1)
    rc=$?
    rm -rf "$w"
    if [ "$expect" = green ]; then
        if [ $rc -eq 0 ]; then ok "$label: $(echo "$res" | head -1): recover + shrink again = byte-identical to the undisturbed run"; else bad "$label: $(echo "$res" | tr '\n' ';' | cut -c1-300)"; fi
    else
        if [ $rc -ne 0 ]; then ok "counter-proof $label: $(echo "$res" | head -1)"; else bad "counter-proof $label: defect not detected"; fi
    fi
}
rfuzz "$SHC" "relocation crash points (gpt)" green
rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
sed -i 's|    j.state = rjournal.ST_COPIED\n||' "$D/mutlib/ntfsshrink/reloc.fi"
python3 -I - "$D/mutlib/ntfsshrink/reloc.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace("    j.state = rjournal.ST_COPIED\n    r = rjournal.write(v, (*c).jbuf, &j)\n", "    r = codes.E_OK\n")
open(p, "w").write(s)
PY
if FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutfz" tools/ntfsshrink/shrinkhost.fi > "$D/mut.log" 2>&1; then rfuzz "$D/mutfz" "commit marker never written" red; else bad "fuzz mutation build"; fi
rm -rf "$D/mutlib" "$D/mutfz"
echo "== 17. packed size and progress reports =="
pkv() { awk -F= -v k="$2" '$1 == k { print $2 }' "$1"; }
pinfo() { "$1" "$D/tail4k.pre" i 2048 x > "$D/pinfo.out" 2>&1; }
pinfo "$SHC"
MINS=$(pkv "$D/pinfo.out" min_sectors); PACK=$(pkv "$D/pinfo.out" packed_sectors); TGT=$(cat "$D/tail4k.target")
if [ -n "$MINS" ] && [ -n "$PACK" ] && [ "$PACK" -lt "$MINS" ] && [ "$PACK" -le "$TGT" ] && [ "$MINS" -gt "$TGT" ]; then
    ok "end-placed volume: packed_sectors $PACK <= target $TGT < used_end estimate $MINS"
else
    bad "packed_sectors $PACK vs target $TGT vs min_sectors $MINS"
fi
PR="$D/tail4k.run"
[ "$(pkv "$PR" prog_regress)" = 0 ] && [ "$(pkv "$PR" prog_final)" = 100 ] && ok "progress never goes backwards inside a phase and ends at 100" || bad "progress regress/final: $(pkv "$PR" prog_regress)/$(pkv "$PR" prog_final)"
[ "$(pkv "$PR" prog_scan_max)" -ge 90 ] && [ "$(pkv "$PR" prog_move_max)" -ge 90 ] && ok "scan phase reached $(pkv "$PR" prog_scan_max) %, move phase $(pkv "$PR" prog_move_max) % ($(pkv "$PR" prog_calls) calls)" || bad "progress phases: $(pkv "$PR" prog_scan_max)/$(pkv "$PR" prog_move_max)"
pmut() {
    local label=$1 expr=$2 file=$3 check=$4
    rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
    sed -i "$expr" "$D/mutlib/ntfsshrink/$file"
    if cmp -s "lib/ntfsshrink/$file" "$D/mutlib/ntfsshrink/$file"; then bad "mutation '$label' did not change the source"; return; fi
    if ! FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutexe" tools/ntfsshrink/shrinkhost.fi > "$D/mut.log" 2>&1; then bad "mutation '$label' does not build"; return; fi
    cp "$D/tail4k.pre" "$D/m.disk"
    "$D/mutexe" "$D/m.disk" r 2048 "$D/m.disk" "$TGT" > "$D/m.out" 2>&1
    "$D/mutexe" "$D/tail4k.pre" i 2048 x > "$D/m.info" 2>&1
    case $check in
        scan) [ "$(pkv "$D/m.out" prog_scan_max)" -ge 90 ] && bad "mutation '$label' was not detected" || ok "progress mutation '$label' detected" ;;
        pack) [ "$(pkv "$D/m.info" packed_sectors)" -lt "$(pkv "$D/m.info" min_sectors)" ] && bad "mutation '$label' was not detected" || ok "packed-size mutation '$label' detected" ;;
    esac
    rm -f "$D/m.disk" "$D/mutexe"
}
pmut "scan never reports" 's|            prog(mode, n \* 100 / nrec)|            n = n + 0|' reloc.fi scan
pmut "packed size ignores allocation" 's|(\*out).packed_sectors = (floor + reserve_clusters(v.cb)) \* v.spc + 1|(*out).packed_sectors = (*out).min_sectors|' shrink.fi pack
rm -rf "$D/mutlib"
