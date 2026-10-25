echo "== 14. relocation building blocks (balloc, mpatch, rjournal) =="
if RC_OUT=$(python3 -I tools/ntfsshrink/rctest.py "$D" "$FIRNC" rcunit 2>&1); then
    ok "$RC_OUT"
else
    bad "rctest: $(echo "$RC_OUT" | tr '\n' ';' | cut -c1-300)"
fi
mkimg "$D/rj.img" 24
mkntfs -F -q -s 512 -c 4096 "$D/rj.img" >/dev/null 2>&1 || bad "mkntfs rj"
RJ_S=$(python3 -I - "$D/rj.img" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read(512)
print(int.from_bytes(b[40:48], 'little'))
PY
)
cp "$D/rj.img" "$D/rj0.img"
INFO0=$(cd "$D" && "$D/unit" "$D/rj.img" info x 2>&1 | tr '\n' ' ')
"$D/rcunit" j "$D/rj.img" w "$RJ_S" 1 0 5 6 7 8 abcdef01 > "$D/rjw.out" 2>&1
INFO1=$(cd "$D" && "$D/unit" "$D/rj.img" info x 2>&1 | tr '\n' ' ')
if [ -n "$INFO0" ] && [ "$INFO0" = "$INFO1" ] && echo "$INFO0" | grep -q '^open=0\| open=0'; then
    ok "vol.open accepts a journal sector in the old backup-boot slot (info unchanged)"
else
    bad "journal in backup slot: '$INFO0' vs '$INFO1'"
fi
"$D/rcunit" j "$D/rj.img" c "$RJ_S" > "$D/rjc.out" 2>&1
if cmp -s "$D/rj.img" "$D/rj0.img"; then ok "closing the journal restores the volume byte for byte"; else bad "close_session did not restore the volume"; fi
"$D/rcunit" j "$D/rj.img" w "$RJ_S" 2 0 5 6 7 8 abcdef01 > /dev/null 2>&1
rm -rf "$D/mutlib"; cp -r lib "$D/mutlib"
sed -i 's/let jr: bool = tags.eq(alt, tags.T_RJ)/let jr: bool = false/' "$D/mutlib/ntfsshrink/vol.fi"
if FIRNLIB="$D/mutlib" "$FIRNC" -o "$D/mutshc" tools/ntfsshrink/unit.fi > "$D/mut.log" 2>&1; then
    GOT=$(cd "$D" && "$D/mutshc" "$D/rj.img" info x 2>&1 | grep -a -m1 '^open=')
    if [ "$GOT" != "open=0" ]; then ok "counter-probe: vol.open without journal slot support refuses the volume ($GOT)"; else bad "counter-probe open passed"; fi
else
    bad "counter-probe build"
fi
rm -rf "$D/mutlib" "$D/mutshc"
if RM_OUT=$(python3 -I tools/ntfsshrink/rcmut.py "$D" "$FIRNC" 2>&1); then
    ok "$RM_OUT"
else
    bad "rcmut: $(echo "$RM_OUT" | tr '\n' ';' | cut -c1-300)"
fi
rm -f "$D/rj.img" "$D/rj0.img"
