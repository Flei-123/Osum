# SPDX-License-Identifier: GPL-2.0-only
asl_build tools/acpi/asl/thermal.asl "$D/thermal" || { printf '  FAIL  thermal ssdt build\n'; echo fail >> "$RESULTS"; exit 0; }
mkdir -p "$D/bin"
if ! bash tools/sync/build.sh "$D/bin" 0 sh echo sleep cat > "$D/ubuild.txt" 2>&1; then
    printf '  FAIL  user programs build\n'; echo fail >> "$RESULTS"; exit 0
fi
cat > "$D/s.sh" <<'SCRIPT'
sleep -m 1500
echo ==PROC==
cat /proc/thermal
echo ==END==
SCRIPT
python3 tools/osum/mkfs.py build "$D/p.img" 20000 /bin/ /etc/ /run/ /tmp/ /t/ /proc/ /dev/ /system/ /var/ \
    "/bin/sh=$D/bin/sh.elf" "/bin/echo=$D/bin/echo.elf" "/bin/sleep=$D/bin/sleep.elf" "/bin/cat=$D/bin/cat.elf" \
    "/t/s.sh=$D/s.sh" > "$D/mkfs.txt" 2>&1 || { printf '  FAIL  mkfs\n'; echo fail >> "$RESULTS"; exit 0; }
ACPI_MEM=512 qrun "$K" procraw "osum vfs nokbd nosched acpiev thermsim thermms=200 script=sh /t/s.sh;exit" \
    -acpitable "file=$D/thermal.aml" -drive "file=$D/p.img,format=raw,if=ide,index=0"
tr -cd '\11\12\15\40-\176' < "$D/procraw.txt" | tr -d '\r' | sed -n '/^==PROC==$/,/^==END==$/p' > "$D/procc.txt"
ZPA=$(line procc '^zone .*_TZ\.TZA0 ')
ZPC=$(line procc '^zone .*_SB\.TZC0 ')
chk "proc: header" 1 "$(has procc '^thermal zones=3 interval_ms=200$')"
chk "proc: three zone lines" 3 "$(count procc '^zone ')"
chk "proc: zone A temperature" 30.0 "$(val "$ZPA" temp_c)"
chk "proc: zone A critical limit" 100.0 "$(val "$ZPA" crt_c)"
chk_ge "proc: zone A samples" 1 "$(val "$ZPA" valid)"
chk "proc: zone C temperature" 45.0 "$(val "$ZPC" temp_c)"
chk "proc: cpu line" 1 "$(has procc '^cpu temp_c=')"
chk "proc: kernel finished after the read" 21 "$(cat "$D/procraw.rc")"
