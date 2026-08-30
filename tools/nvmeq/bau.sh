#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nvmeq/bau.sh -- Kernel und Platten EINMAL bauen, dann beliebig
# oft starten. Wird von `run.sh` eingebunden und laesst sich zum
# Nachsehen auch allein benutzen.
#
# Die Trennung ist kein Luxus: diese Runde startet den Kernel ACHTMAL
# mit verschiedenen Gegenproben, und achtmal uebersetzen waere die
# meiste Zeit der Abnahme.
set -uo pipefail

nq_bau() { # <tmpdir>
    NQ_TMP=$1
    export FIRNLIB="$(pwd)/lib"
    NQ_FIRNC=${FIRNC:-vendor/firn/bin/firnc}
    NQ_FC1=${FIRNC1:-vendor/firn/bin/firnc1}
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    local f
    for f in boot isr switch smp hv; do
        as --64 -o "$NQ_TMP/$f.o" "kernel/arch/x86_64/$f.s" 2>"$NQ_TMP/as.err" || return 1
    done
    as --64 -o "$NQ_TMP/crt.o" kernel/user/crt.s 2>/dev/null || return 1
    return 0
}

nq_stufe() { # <0|1>
    local st=$1 cc p
    if [ "$st" = 0 ]; then cc="$NQ_FIRNC"; else cc="$NQ_FC1"; fi
    [ -x "$cc" ] || return 1
    "$cc" kernel/kmain.fi -o "$NQ_TMP/k$st.o" >"$NQ_TMP/e$st" 2>&1 || return 1
    # DER NAME DIESER OBJEKTDATEI IST NICHT BELIEBIG: `kernel/kernel.ld`
    # sammelt den Ring-3-Code mit dem Muster `*uprog*.o(.text .text.*)`.
    # Heisst sie anders, landet `uprog.fi` im Kerneltext, und jedes
    # Programm in Ring 3 faellt beim ersten Befehl.
    "$cc" kernel/uprog.fi -o "$NQ_TMP/uprog$st.o" >>"$NQ_TMP/e$st" 2>&1 || return 1
    ld -n -T kernel/kernel.ld \
        --defsym=KERNEL_MAIN="_F$st.kernel_main" \
        --defsym=KERNEL_TRAP="_F$st.trap__entry" \
        --defsym=KERNEL_SYSCALL="_F$st.sys__entry" \
        --defsym=KERNEL_TASK_MAIN="_F$st.tasks__main" \
        --defsym=KERNEL_USER_START="_F$st.proc__user_start" \
        --defsym=KERNEL_AP_MAIN="_F$st.smp__ap_main" \
        --defsym=USER_MAIN="_F$st.u_enter" \
        -o "$NQ_TMP/k$st.elf" "$NQ_TMP/boot.o" "$NQ_TMP/isr.o" \
        "$NQ_TMP/switch.o" "$NQ_TMP/smp.o" "$NQ_TMP/hv.o" \
        "$NQ_TMP/k$st.o" "$NQ_TMP/uprog$st.o" 2>"$NQ_TMP/ld$st.err" || return 1
    objcopy -O elf32-i386 "$NQ_TMP/k$st.elf" "$NQ_TMP/k$st.mb" 2>/dev/null || return 1
    for p in sh ls cat echo; do
        "$cc" "kernel/user/$p.fi" -o "$NQ_TMP/$p$st.o" >>"$NQ_TMP/e$st" 2>&1 || return 1
        ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F$st.u_start" \
            -o "$NQ_TMP/$p$st.elf" "$NQ_TMP/crt.o" "$NQ_TMP/$p$st.o" 2>/dev/null || return 1
        strip --strip-all "$NQ_TMP/$p$st.elf"
    done
    return 0
}

nq_platten() { # das Wurzeldateisystem (IDE) und die leere NVMe-Platte
    local spec="/bin/" p
    for p in sh ls cat echo; do spec="$spec /bin/$p=$NQ_TMP/${p}0.elf"; done
    python3 tools/osum/mkfs.py build "$NQ_TMP/root.img" 4096 /proc/ /dev/ /mnt/ $spec \
        > "$NQ_TMP/mkfs.txt" 2>&1 || return 1
    # 8 MiB -- 16384 Bloecke zu 512. Der Arbeitsblock des Selbsttests
    # liegt bei 12288, also im letzten Viertel und weit hinter dem
    # Dateisystem, das `hw.disk` vorne anlegt.
    dd if=/dev/zero of="$NQ_TMP/nv.img" bs=1M count=8 2>/dev/null || return 1
    return 0
}

# nq_start <k0|k1> <anhang> <ausgabedatei> [weitere qemu-argumente]
#
# DER AUFRUF GESCHIEHT IM ARBEITSVERZEICHNIS UND MIT RELATIVEN PFADEN,
# und das ist keine Kosmetik, sondern ein Fehler, der diese Runde eine
# Messreihe gekostet hat:
#
#   DER PFAD DES KERNELABBILDS STEHT MIT IN DER KOMMANDOZEILE.
#   Multiboot haengt `-append` HINTER den Namen der Datei, `hw.parse`
#   sucht darin TEILWOERTER -- und ein Arbeitsverzeichnis namens
#   /tmp/osum-nvmeq-XXXX enthaelt das Wort `nvmeq`. Damit lief in JEDEM
#   Lauf der Selbsttest mit, auch in dem, der nur messen sollte.
#
# Mit `cd` und `-kernel k0.mb` heisst die Kommandozeile immer
# "k0.mb <anhang>", egal wie das Verzeichnis heisst.
nq_start() {
    local img=$1 append=$2 out=$3
    shift 3
    cp "$NQ_TMP/root.img" "$NQ_TMP/live.img"
    cp "$NQ_TMP/nv.img" "$NQ_TMP/nvlive.img"
    local abs
    case "$out" in /*) abs=$out ;; *) abs=$(pwd)/$out ;; esac
    # 600 s und nicht 300: auf einer Maschine, auf der mehrere Runden
    # gleichzeitig rechnen (Lastmittel 24 auf 12 Kernen gemessen), braucht
    # allein der Start bis zur Shell ueber eine Minute. Ein Zeitlimit, das
    # die Auslastung des Wirts misst, ist kein Zeitlimit -- ein Lauf ist
    # darin einmal mitten im nqerr-Abschnitt abgeschnitten worden, und
    # sechs Zusagen "fehlten ganz", obwohl nichts kaputt war.
    ( cd "$NQ_TMP" && timeout 600 $QEMU_X86 -kernel "$img.mb" -m 256 \
        -append "$append" \
        -serial "file:$abs" -display none -no-reboot \
        -drive "file=live.img,format=raw,if=ide,index=0" \
        -drive "file=nvlive.img,format=raw,if=none,id=nq0" \
        -device "nvme,drive=nq0,serial=nvmeq0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 "$@" >/dev/null 2>&1 )
    local rc=$?
    tr -d '\000' < "$abs" > "$abs.clean"
    return $rc
}
