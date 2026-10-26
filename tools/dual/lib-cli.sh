# SPDX-License-Identifier: GPL-2.0-only
# Einen Lauf fahren. $1 = Plattendatei, $2 = Argumente fuer dualcli,
# $3 = Protokolldatei.
lauf() {
    local img=$1 arg=$2 ser=$3
    rm -f "$ser"
    # ============================ WARUM KEIN `-initrd` UND KEIN `modfs`
    #
    # GEMESSEN, nicht vermutet: mit `modfs` liegt die Wurzel als
    # Boot-Modul im Speicher, und darin steht `/etc/ziel` auf `grafik`.
    # `init` startet dann die Oberflaeche und `script=` kommt nie an --
    # auf der Leitung endet es bei "init: dienste=1".
    #
    # Also derselbe Aufbau wie in tools/k14/run.sh: die WURZEL ist eine
    # gewoehnliche Platte (hda), und die fremde Platte, um die es geht,
    # haengt als ZWEITE daran (hdb). Der Kern findet seine Wurzel auf
    # hda, `script=` laeuft, und `dualcli` bekommt /dev/hdb als Ziel --
    # das ist ausserdem naeher an der Wirklichkeit: ein Mensch
    # installiert von einem Medium auf eine ANDERE Platte.
    cp -f "$BAU/root.img" "$OUT/wurzel.img"
    # ============================ UND WARUM `/etc/ziel` UMGESCHRIEBEN WIRD
    #
    # Auch ohne `modfs` liest `init` seine Wurzel von der Platte, und
    # dort steht `/etc/ziel` auf `grafik`. Dann startet `kgui` die
    # Oberflaeche, und `script=` kommt nie an -- gemessen: die Leitung
    # endet bei "init: dienste=1", ohne eine einzige `dual:`-Zeile.
    #
    # Fuer DIESEN Lauf soll die Maschine in die Konsole starten. Also
    # wird in der KOPIE des Wurzelabbilds das Wort ausgetauscht --
    # `mkfs.py where` sagt, in welchem Block es liegt. Das ist eine
    # Aenderung am Messaufbau und keine am System: das ausgelieferte
    # Abbild bleibt `grafik`.
    local zblk
    zblk=$(python3 tools/osum/mkfs.py where "$OUT/wurzel.img" /etc/ziel 2>/dev/null \
        | sed -n 's/.*first=\([0-9]*\).*/\1/p')
    if [ -n "$zblk" ]; then
        # NICHT LAENGER ALS DAS ALTE WORT: die Laenge steht in der
        # Inode, und die wird hier nicht angefasst. "grafik\n" sind
        # sieben Oktette. `init` kennt das Wort "kons" nicht und faellt
        # dann ausdruecklich auf die Konsole zurueck (read_target:
        # target_of == 0 -> Z_KONSOLE) -- genau das ist gewollt.
        printf 'kons\n\0\0' | dd of="$OUT/wurzel.img" bs=512 seek="$zblk" \
            conv=notrunc status=none
    fi
    timeout "${LIMIT:-600}" $QEMU_X86 -m "${QEMU_MEM:-512}" \
        -kernel "$BAU/osum.mb" \
        -append "osum vfs nokbd nosched noproc noring3 script=$arg;exit" \
        -serial "file:$ser" -display none -no-reboot \
        -drive "file=$OUT/wurzel.img,format=raw,if=ide,index=0" \
        -drive "file=$img,format=raw,if=ide,index=1" \
        > "$OUT/qemu.log" 2>&1
    rm -f "$OUT/wurzel.img"
    return 0
}
