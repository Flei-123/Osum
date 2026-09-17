#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fremdfs/run.sh -- DIE ABNAHME DER RUNDE FREMDFS.
#
# DIE FRAGE DIESER RUNDE: kommt OrientOS an die Daten des Systems, neben
# das es sich seit der Runde DUALBOOT installieren laesst? Also: liest
# es ext4 (Linux) und NTFS (Windows)?
#
# WIE HIER GEMESSEN WIRD, und warum es so und nicht anders geht:
#
#   DER WIRT BAUT DIE ABBILDER, mit den ECHTEN Werkzeugen --
#   `mkfs.ext4`/`debugfs`/`e2fsck` und `mkntfs`/libntfs-3g. Er legt
#   einen BEKANNTEN Baum an und merkt sich JEDE SHA-256.
#
#   OSUM LIEST SIE, im laufenden Kernel, in Ring 3, ueber `mount` und
#   ganz gewoehnliche `open`/`read`-Aufrufe (`/bin/fremdfs`), und
#   rechnet die SHA-256 SELBST -- mit `kernel/user/sha.fi`, das in der
#   Runde TRESOR gegen die Vektoren aus FIPS 180-4 gemessen wurde.
#
#   DIE ZWEI SUMMEN WERDEN VERGLICHEN. Stimmen sie, ist die Datei
#   Oktett fuer Oktett dieselbe -- und das ist eine Aussage und keine
#   Ansicht. "Sieht richtig aus" kommt hier nicht vor.
#
# DIE GEGENPROBEN, ohne die das kein Messgeraet waere, sondern eine
# Vorfuehrung:
#
#   - ein ext4 mit ZERSTOERTER MAGIE muss abgelehnt werden -- nicht
#     haengen, nicht Muell liefern;
#   - ein FAT32 darf NICHT als ext4 durchgehen (und umgekehrt);
#   - ein ABGESCHNITTENES Abbild muss auffallen, statt ueber das Ende
#     hinaus zu lesen;
#   - ein NTFS mit zerstoerter Kennung muss abgelehnt werden;
#   - ein UNSAUBER ausgehaengtes ext4 muss ERKANNT werden (und wird
#     dann nur lesend mit Warnung eingehaengt -- die Begruendung steht
#     in kernel/ext4.fi);
#   - SCHREIBEN muss auf beiden scheitern.
#
# Aufruf:  bash tools/fremdfs/run.sh
#          OSUM_FF_NUR=ext4   nur der ext4-Teil
#          OSUM_FF_NUR=ntfs   nur der NTFS-Teil
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=8192
PROGS="sh cat echo ls cp rm mkdir wc true false mount umount fremdfs"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

num() { # name wert op soll
    if [ -z "${2:-}" ]; then bad "$1: keine Zahl gefunden (erwartet $3 $4)"; return; fi
    if [ "$2" -"$3" "$4" ] 2>/dev/null; then ok "$1: $2"
    else bad "$1: $2, erwartet $3 $4"; fi
}
gleich() { # name soll ist
    if [ "$2" = "$3" ]; then ok "$1"
    else
        bad "$1"
        printf '        soll: %s\n' "$(printf '%s' "$2" | head -c 200)"
        printf '        ist : %s\n' "$(printf '%s' "$3" | head -c 200)"
    fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }

# Ein Wert aus der Ausgabe von /bin/fremdfs ("ff: name = zahl").
wert() { # datei name
    grep -a -m1 "^ff: $2 = " "$1" 2>/dev/null | sed 's/.* = //' | tr -d '\r\000'
}
sagt() { # datei name soll beschreibung
    local got
    got=$(wert "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile 'ff: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}
# Eine Pruefsumme aus der Ausgabe ("ff: sha /mnt/x = <hex>").
shawert() { # datei pfad
    grep -a -m1 "^ff: sha $2 = " "$1" 2>/dev/null | sed 's/.* = //' \
        | tr -d '\r\000'
}

echo "== 0. die Vorbedingungen =="
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1 \
    || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || {
    echo "FREMDFS: uebersprungen, qemu-system-x86_64 fehlt"; exit 0; }
for w in mkfs.ext4 debugfs e2fsck mkntfs sha256sum gcc python3; do
    command -v "$w" >/dev/null 2>&1 || {
        echo "FREMDFS: uebersprungen, $w fehlt"; exit 0; }
done
ok "die Werkzeuge des Wirts sind da (e2fsprogs, ntfs-3g, qemu, gcc)"

# ---------------------------------------------------- 1. die Speicherkarte

echo "== 1. die Speicherkarte von kdata =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Karte: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -10
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"

# Die zwei neuen Seiten liegen da, wo sie liegen sollen, und nirgends
# sonst. Diese Stelle hat dem Projekt schon vier Kollisionen beschert.
for r in EXT4_OFF NTFS_OFF; do
    v=$(grep -aE "^const $r: u64 = 0x[0-9A-Fa-f]+" kernel/lib/kstate.fi \
        | head -1 | grep -oE '0x[0-9A-Fa-f]+')
    d=$((v))
    # MERGE 14.09.2026: die beiden Bereiche sind hinter die alte
    # kdata-Grenze gezogen (0x100000/0x103000), weil vier parallele
    # Runden sich denselben freien Raum ab 0xF2000 genommen hatten.
    # Siehe den Merge-Vermerk in kernel/kstate.fi.
    if [ "$d" -ge $((0x100000)) ] && [ "$d" -lt $((0x106000)) ]; then
        ok "$r = $v liegt im zugeteilten Bereich 0x100000..0x106000"
    else
        bad "$r = ${v:-fehlt} liegt AUSSERHALB von 0x100000..0x106000"
    fi
done

# GEGENPROBE ZUR KARTE: eine Seite auf eine fremde Adresse gelegt MUSS
# anschlagen. Ohne diese Zeilen prueft die Karte nur das, woran jemand
# gedacht hat.
mkdir -p "$TMPD/kollision/arch/x86_64"
cp kernel/*.fi "$TMPD/kollision/"
cp kernel/arch/x86_64/*.fi "$TMPD/kollision/arch/x86_64/"
sed -i 's/^const EXT4_OFF: u64 = 0x100000$/const EXT4_OFF: u64 = 0xF2000/' \
    "$TMPD/kollision/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/kollision" > "$TMPD/karte2.txt" 2>&1; then
    bad "GEGENPROBE: EXT4_OFF auf 0xF2000 (= VGPU_OFF) und der Pruefer schweigt"
else
    ok "GEGENPROBE: EXT4_OFF auf VGPU_OFF gelegt -- der Kartenpruefer schlaegt an"
fi

# DIE AUFTEILUNG DER SEITE, NACHGERECHNET.
#
# Die Knotentafel faengt bei NODE_OFF an und ist MAX_NODES *
# NODE_BYTES lang; der erste grosse Puffer steht dahinter. Ragt die
# Tafel in den Puffer, ueberschreibt jeder gelesene Block die letzten
# Knoten -- und genau das ist in dieser Runde passiert (24 x 48 = 0x480
# ab 0x400 endet bei 0x880, der Puffer beginnt bei 0x800). Die Wirkung
# war eine Datei, die nach einem Block zu Ende war. Deshalb steht die
# Rechnung jetzt hier und nicht nur im Kommentar.
for f in ext4 ntfs; do
    zahl() { grep -aE "^const $1: u64 = " "kernel/$f.fi" | head -1 \
        | sed -E 's/.*= *//; s/ *\/\/.*//'; }
    # `$(( ))` versteht 0x-Zahlen, `[ -le ]` NICHT -- deshalb werden
    # beide Seiten erst durch die Arithmetik geschickt.
    no=$(( $(zahl NODE_OFF) )); nb=$(( $(zahl NODE_BYTES) ))
    mn=$(( $(zahl MAX_NODES) ))
    if [ "$f" = ext4 ]; then pb=$(( $(zahl BLKBUF) )); else pb=$(( $(zahl MFTBUF) )); fi
    ende=$(( no + nb * mn ))
    if [ "$ende" -le "$pb" ]; then
        ok "$f.fi: die Knotentafel endet bei $(printf '0x%X' $ende), der Puffer beginnt bei $(printf '0x%X' $pb)"
    else
        bad "$f.fi: die Knotentafel ragt in den Puffer ($(printf '0x%X' $ende) > $(printf '0x%X' $pb))"
    fi
done

# Und: die zwei Treiber tragen NUR die vier lesenden Bits.
for f in ext4 ntfs; do
    if grep -qaE '^\s*mask: vfsops\.OP_READONLY,' "kernel/$f.fi"; then
        ok "kernel/$f.fi sagt OP_READONLY zu (und nichts darueber hinaus)"
    else
        bad "kernel/$f.fi traegt nicht OP_READONLY"
    fi
done

# --------------------------------------------------------------- 2. bauen

echo "== 2. bauen: der Kern und der Werkzeugkasten, aus beiden Uebersetzern =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null \
    || bad "crt.s laesst sich nicht assemblieren"

baue_stufe() { # 0 | 1
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" \
        > "$TMPD/k$s.log" 2>&1 || {
        bad "firnc$s: der Kern laesst sich nicht bauen"
        sed 's/^/        /' "$TMPD/k$s.log" | head -12
        return 1
    }
    for p in $PROGS; do
        "$cc" "kernel/user/$p.fi" -o "$TMPD/$p$s.o" > "$TMPD/e$p$s" 2>&1 || {
            bad "firnc$s uebersetzt $p.fi nicht"
            sed 's/^/        /' "$TMPD/e$p$s" | head -8
            rc=1
            continue
        }
        ld -T "$ULD" --defsym=USER_ENTRY="_F$s.u_start" \
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" \
            2>"$TMPD/ld.err" || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
baue_stufe 0 || { echo "FREMDFS: $pass bestanden, $((fail+1)) gescheitert"; exit 1; }
ok "firnc0: der Kern und $(echo $PROGS | wc -w) Programme sind gebaut"
if baue_stufe 1; then
    ok "firnc1: dasselbe aus dem Uebersetzer, der in Firn geschrieben ist"
else
    bad "firnc1 baut diese Runde nicht"
fi

# ------------------------------------------------------- 3. die Pruefbilder

echo "== 3. die Pruefbilder, vom WIRT gebaut =="
BILD="$TMPD/bild"
if bash tools/fremdfs/bild.sh "$BILD" > "$TMPD/bild.log" 2>&1; then
    ok "die Abbilder stehen: $(grep -c . "$BILD/baum.sha") Dateien im Baum"
else
    bad "tools/fremdfs/bild.sh scheitert"
    sed 's/^/        /' "$TMPD/bild.log" | tail -15
    echo "FREMDFS: $pass bestanden, $fail gescheitert"
    exit 1
fi
hat "$TMPD/bild.log" "ntfsfix -n sagt: in Ordnung" \
    "ntfs-3g haelt das NTFS-Abbild fuer gesund"
abw=$(grep -a 'NTFS-Gegenlesung' "$TMPD/bild.log" | grep -oE '[0-9]+ Abweichungen' | grep -oE '^[0-9]+')
num "ntfscat liest das NTFS-Abbild ohne Abweichung" "${abw:-99}" eq 0

# DASS DER EXTENT-BAUM WIRKLICH EINER IST. Ohne diese Zahl waere
# "der Treiber kann Extent-Baeume" eine Hoffnung: bei Tiefe 0 stehen
# alle Extents im Inode, und der Baum wird nie betreten.
tiefe=$(cat "$BILD/ext4-tiefe.txt" 2>/dev/null)
num "der Extent-Baum von gross.bin hat Tiefe" "${tiefe:-0}" ge 1
extents=$(cat "$BILD/ext4-extents.txt" 2>/dev/null)
num "und so viele Blatt-Extents" "${extents:-0}" ge 10
htree=$(cat "$BILD/ext4-htree.txt" 2>/dev/null)
num "/viele ist htree-indiziert (EXT4_INDEX_FL)" "${htree:-0}" eq 1

# Die Pruefsummen des Wirts, nach Pfad.
soll() { # pfad
    grep -a " $1\$" "$BILD/baum.sha" | head -1 | cut -d' ' -f1
}

# -------------------------------------------- 4. die Wurzelplatte von Osum

echo "== 4. die Wurzelplatte =="
MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ $MKARGS > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | head -5; }

# Die fremden Abbilder bekommen eine MBR-Tafel, damit sie als
# PARTITION eingehaengt werden -- so, wie sie auf einer echten Platte
# neben OrientOS laegen. Der Typ ist 0x83 (Linux) bzw. 0x07 (NTFS).
partitionieren() { # quelle ziel typ
    local quelle=$1 ziel=$2 typ=$3
    local groesse
    groesse=$(stat -c %s "$quelle")
    # MIT LOECHERN. `dd if=/dev/zero` belegt die volle Groesse wirklich;
    # bei einem Dutzend Abbildern ist das knapp ein Gigaoktett, und
    # genau daran ist dieser Lauf schon einmal gescheitert.
    rm -f "$ziel"
    python3 - "$ziel" $(( groesse / 1048576 + 2 )) <<'PYEOF'
import sys
ziel, mib = sys.argv[1], int(sys.argv[2])
with open(ziel, 'wb') as f:
    f.seek(mib * 1048576 - 1)
    f.write(b'\0')
PYEOF
    printf 'label: dos\nstart=2048, type=%s\n' "$typ" \
        | sfdisk "$ziel" >/dev/null 2>&1 || return 1
    dd if="$quelle" of="$ziel" bs=512 seek=2048 conv=notrunc status=none
    return 0
}

# ------------------------------------------------------------ der Lauf

lauf() { # name wurzel zweite kommandozeile [zeitlimit]
    local name=$1 root=$2 second=$3 app=$4 t=${5:-300}
    cp --sparse=always "$root" "$TMPD/live-$name.img"
    local drives=(-drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0")
    if [ -n "$second" ]; then
        cp --sparse=always "$second" "$TMPD/live2-$name.img"
        drives+=(-drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1")
    fi
    timeout "$t" $QEMU_X86 -cpu host -kernel "$TMPD/k0.mb" -m 512 \
        -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${drives[@]}" > /dev/null 2>&1
    echo $?
}
# -cpu host geht nur mit KVM; unter TCG waere es ein Fehler.
if [ "$OSUM_QEMU_ACCEL" != kvm ]; then
    lauf() {
        local name=$1 root=$2 second=$3 app=$4 t=${5:-300}
        cp --sparse=always "$root" "$TMPD/live-$name.img"
        local drives=(-drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0")
        if [ -n "$second" ]; then
            cp --sparse=always "$second" "$TMPD/live2-$name.img"
            drives+=(-drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1")
        fi
        timeout "$t" $QEMU_X86 -kernel "$TMPD/k0.mb" -m 512 -append "$app" \
            -serial "file:$TMPD/$name.txt" -display none -no-reboot \
            -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
            "${drives[@]}" > /dev/null 2>&1
        echo $?
    }
fi

# Ein ganzer Durchgang ueber ein Abbild: einhaengen, alles lesen,
# jede Summe vergleichen.
durchgang() { # name abbild art erwartet_verweise(0/1)
    local name=$1 abbild=$2 art=$3 mit_verweisen=$4
    local D="$TMPD/$name.txt"
    local rc
    rc=$(lauf "$name" "$TMPD/root.img" "$abbild" \
        "osum nokbd vfs script=fremdfs $art /dev/hdb1 /mnt")
    num "[$name] der Kernel beendet sich selbst (21)" "$rc" eq 21
    if [ ! -f "$D" ]; then
        bad "[$name] keine serielle Ausgabe"
        return
    fi
    sagt "$D" mount 1 "[$name] das Dateisystem wird eingehaengt"

    # DIE VERZEICHNISSE, gegen die Zahlen des Wirts.
    local soll_wurzel soll_viele
    soll_wurzel=$(grep -a '^\. ' "$BILD/baum.liste" | awk '{print $2}')
    soll_viele=$(grep -a '^viele ' "$BILD/baum.liste" | awk '{print $2}')
    # ext4 hat zusaetzlich lost+found und die zwei Verweise in der
    # Wurzel; NTFS hat weder das eine noch das andere.
    local ist_wurzel
    ist_wurzel=$(wert "$D" wurzel)
    # DIE ZAHL IST FUER BEIDE ANDERS, UND ZWAR AUS EINEM GRUND, DER IM
    # DATEISYSTEM LIEGT UND NICHT IM TREIBER:
    #
    #   ext4: der Baum PLUS `lost+found` (legt `mkfs.ext4` an) PLUS die
    #         zwei symbolischen Verweise, die es nur hier gibt.
    #   NTFS: GENAU der Baum. Die Systemdateien ($MFT, $Boot, ...) sind
    #         echte Indexeintraege, werden aber uebergangen -- so wie
    #         Windows und ntfs-3g es tun (siehe MFT_ERSTE_FREIE in
    #         kernel/ntfs.fi). Verweise legt `ntfsbaum.c` keine an.
    if [ "$art" = ext4 ]; then
        num "[$name] die Wurzel hat alle Eintraege" "${ist_wurzel:-0}" ge \
            $(( soll_wurzel + 1 ))
    else
        gleich "[$name] die Wurzel hat GENAU die Eintraege des Baums (ohne die Systemdateien von NTFS)" \
            "$soll_wurzel" "${ist_wurzel:-0}"
    fi
    sagt "$D" viele "$soll_viele" "[$name] /viele zeigt ALLE $soll_viele Eintraege"
    sagt "$D" tief 1 "[$name] das tiefste Verzeichnis hat einen Eintrag"
    sagt "$D" a 1 "[$name] /a hat einen Eintrag"

    # DIE GROESSEN.
    sagt "$D" gr-gross 6291456 "[$name] gross.bin ist 6 MiB gross"
    sagt "$D" gr-leer 0 "[$name] leer.bin hat NULL Oktette"
    sagt "$D" gr-mittel 204800 "[$name] mittel.bin ist 200 KiB gross"
    sagt "$D" art-dir 16384 "[$name] /viele meldet sich als Verzeichnis"

    # ========================= DIE PRUEFSUMMEN =========================
    # Das ist die Zusage dieser Runde: Oktett fuer Oktett dasselbe.
    local p
    for p in hallo.txt leer.bin mittel.bin gross.bin \
             a/b/c/d/tief.txt a/b/zwischen.txt \
             viele/datei-000 viele/datei-511; do
        local s i
        s=$(soll "$p")
        i=$(shawert "$D" "/mnt/$p")
        if [ -z "$s" ]; then
            bad "[$name] $p: der Wirt hat keine Summe"
        elif [ -z "$i" ]; then
            bad "[$name] $p: Osum liefert keine Summe"
        elif [ "$s" = "$i" ]; then
            ok "[$name] $p: SHA-256 stimmt (${s:0:16}...)"
        else
            bad "[$name] $p: SHA-256 WEICHT AB"
            printf '        Wirt: %s\n        Osum: %s\n' "$s" "$i"
        fi
    done
    # Die Datei mit Umlauten im Namen -- sie prueft den NAMEN, also
    # muss sie ueber ihren Namen gefunden werden.
    local su iu
    su=$(soll 'umlaut-äöü.txt')
    iu=$(shawert "$D" '/mnt/umlaut-äöü.txt')
    if [ -n "$su" ] && [ "$su" = "$iu" ]; then
        ok "[$name] umlaut-äöü.txt: der Name mit Umlauten wird gefunden UND gelesen"
    else
        bad "[$name] umlaut-äöü.txt: SHA-256 weicht ab oder der Name wird nicht gefunden"
        printf '        Wirt: %s\n        Osum: %s\n' "$su" "$iu"
    fi

    # DAS LESEN AB EINER STELLE. Der Wirt rechnet dieselbe Summe.
    local soll_mitte ist_mitte
    soll_mitte=$(python3 - "$BILD" <<'PY'
import sys
# Dieselben 4096 Oktette wie /bin/fremdfs sie liest: ab 3000000.
import subprocess, os
baum = None
# Der Baum liegt nicht mehr da -- die Datei wird neu erzeugt, genau wie
# in bild.sh, und das ist zulaessig, weil sie dort auch erzeugt wurde.
n = 6291456
buf = bytearray()
i = 0
while len(buf) < n:
    s = b'%d\n' % i
    buf += s[:n - len(buf)]
    i += 1
print(sum(buf[3000000:3000000 + 4096]))
PY
)
    ist_mitte=$(wert "$D" mitte)
    gleich "[$name] lesen ab Oktett 3000000 (Quersumme von 4096 Oktetten)" \
        "$soll_mitte" "$ist_mitte"

    # DIE SYMBOLISCHEN VERWEISE -- nur ext4.
    if [ "$mit_verweisen" = 1 ]; then
        sagt "$D" art-lnk 40960 "[$name] verweis.txt meldet sich als VERWEIS"
        local zk zl
        zk=$(grep -a -m1 '^ff: ziel /mnt/verweis.txt = ' "$D" \
            | sed 's/.* = //' | tr -d '\r\000')
        zl=$(grep -a -m1 '^ff: ziel /mnt/langverweis.txt = ' "$D" \
            | sed 's/.* = //' | tr -d '\r\000')
        gleich "[$name] das KURZE Verweisziel (steht im Inode)" \
            "$(cat "$BILD/verweis-kurz.txt")" "$zk"
        gleich "[$name] das LANGE Verweisziel (steht in einem Datenblock)" \
            "$(cat "$BILD/verweis-lang.txt")" "$zl"
    fi

    # WAS NICHT GEHEN DARF.
    sagt "$D" schreib 0 "[$name] SCHREIBEN scheitert (nur lesend)"
    sagt "$D" umount 1 "[$name] aushaengen geht sauber"
}

NUR=${OSUM_FF_NUR:-beide}

# ----------------------------------------------------------- 5. ext4

if [ "$NUR" = beide ] || [ "$NUR" = ext4 ]; then
echo "== 5. ext4: der ganze Baum, jede Pruefsumme =="
partitionieren "$BILD/ext4.img" "$TMPD/ext4-part.img" 83 \
    && ok "die ext4-Partition steht (MBR, Typ 0x83)" \
    || bad "sfdisk scheitert"
durchgang ext4 "$TMPD/ext4-part.img" ext4 1

echo "== 5b. ext4 mit 4096er Bloecken -- dieselbe Arbeit, andere Geometrie =="
partitionieren "$BILD/ext4-4k.img" "$TMPD/ext4-4k-part.img" 83 >/dev/null
durchgang ext4-4k "$TMPD/ext4-4k-part.img" ext4 1
fi

# ----------------------------------------------------------- 6. NTFS

if [ "$NUR" = beide ] || [ "$NUR" = ntfs ]; then
echo "== 6. NTFS: der ganze Baum, jede Pruefsumme =="
partitionieren "$BILD/ntfs.img" "$TMPD/ntfs-part.img" 7 \
    && ok "die NTFS-Partition steht (MBR, Typ 0x07)" \
    || bad "sfdisk scheitert"
durchgang ntfs "$TMPD/ntfs-part.img" ntfs 0
fi

# ------------------------------------------------------- 7. die Gegenproben

echo "== 7. die Gegenproben: was NICHT gelesen werden darf =="

# 7a. Ein ext4 mit zerstoerter Magie. Es MUSS abgelehnt werden -- und
#     zwar ohne zu haengen (das Zeitlimit von QEMU ist der Zeuge).
partitionieren "$BILD/kaputt-ext4.img" "$TMPD/kaputt-part.img" 83 >/dev/null
rc=$(lauf kaputt "$TMPD/root.img" "$TMPD/kaputt-part.img" \
    "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
num "[kaputt] der Kernel beendet sich selbst statt zu haengen" "$rc" eq 21
sagt "$TMPD/kaputt.txt" mount 0 \
    "[kaputt] ein ext4 mit zerstoerter Magie wird ABGELEHNT"
hat "$TMPD/kaputt.txt" "ext4: nicht ext4 (1" \
    "[kaputt] und der Treiber sagt WARUM (Grund 1: keine Magie)"

# 7c. Ein FAT32 darf NICHT als ext4 durchgehen. Das ist die Probe
#     darauf, dass die Erkennung wirklich prueft und nicht nur hofft.
partitionieren "$BILD/fat-als-ext4.img" "$TMPD/fat-part.img" 83 >/dev/null
rc=$(lauf fatext "$TMPD/root.img" "$TMPD/fat-part.img" \
    "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
num "[fat-als-ext4] der Kernel beendet sich selbst" "$rc" eq 21
sagt "$TMPD/fatext.txt" mount 0 \
    "[fat-als-ext4] ein FAT32 geht NICHT als ext4 durch"

# 7c. Und die Gegenrichtung: ein ext4 geht nicht als vfat durch.
rc=$(lauf extfat "$TMPD/root.img" "$TMPD/ext4-part.img" \
    "osum nokbd vfs script=fremdfs vfat /dev/hdb1 /mnt")
num "[ext4-als-vfat] der Kernel beendet sich selbst" "$rc" eq 21
sagt "$TMPD/extfat.txt" mount 0 \
    "[ext4-als-vfat] ein ext4 geht NICHT als FAT32 durch"

# 7d. Ein ABGESCHNITTENES ext4. Der Superblock nennt mehr Bloecke, als
#     das Geraet hat -- ein Treiber, der das nicht prueft, liest ueber
#     das Ende hinaus.
partitionieren "$BILD/kurz-ext4.img" "$TMPD/kurz-part.img" 83 >/dev/null
rc=$(lauf kurz "$TMPD/root.img" "$TMPD/kurz-part.img" \
    "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
num "[kurz] der Kernel beendet sich selbst" "$rc" eq 21
sagt "$TMPD/kurz.txt" mount 0 \
    "[kurz] ein abgeschnittenes ext4 wird ABGELEHNT"
hat "$TMPD/kurz.txt" "ext4: nicht ext4 (6" \
    "[kurz] und der Treiber sagt WARUM (Grund 6: kuerzer als der Kopf behauptet)"

# 7e. Ein NTFS mit zerstoerter Kennung.
partitionieren "$BILD/kaputt-ntfs.img" "$TMPD/kntfs-part.img" 7 >/dev/null
rc=$(lauf kntfs "$TMPD/root.img" "$TMPD/kntfs-part.img" \
    "osum nokbd vfs script=fremdfs ntfs /dev/hdb1 /mnt")
num "[kaputt-ntfs] der Kernel beendet sich selbst" "$rc" eq 21
sagt "$TMPD/kntfs.txt" mount 0 \
    "[kaputt-ntfs] ein NTFS mit zerstoerter Kennung wird ABGELEHNT"

# 7f. DAS UNSAUBER AUSGEHAENGTE ext4. Es wird eingehaengt (nur lesend,
#     das ist dieser Treiber immer) -- ABER die Warnung MUSS kommen.
#     Die Begruendung fuer diese Entscheidung steht in kernel/ext4.fi.
partitionieren "$BILD/ext4-schmutzig.img" "$TMPD/schmutz-part.img" 83 >/dev/null
rc=$(lauf schmutz "$TMPD/root.img" "$TMPD/schmutz-part.img" \
    "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
num "[unsauber] der Kernel beendet sich selbst" "$rc" eq 21
sagt "$TMPD/schmutz.txt" mount 1 \
    "[unsauber] ein unsauber ausgehaengtes ext4 wird NUR LESEND eingehaengt"
hat "$TMPD/schmutz.txt" "ext4: WARNUNG unsauber ausgehaengt" \
    "[unsauber] und der Treiber WARNT im Klartext"

# ------------------------------------------------- 7b. DIE ABSCHALTBARKEIT
#
# Justins Zusatzvorgabe vom 14.09.2026: die zwei Dateisysteme muessen
# sich EINZELN aus dem Abbild nehmen lassen, das System muss ohne sie
# unveraendert laufen, und ein Einhaengeversuch muss einen klaren
# Fehler geben statt zu haengen.
#
# Gemessen wird das hier an vier Abbildern -- voll, ohne ext4, ohne
# NTFS, ohne beide -- und an einem LAUF mit dem Abbild ohne beide.

echo "== 7b. die Abschaltbarkeit (--ohne-ext4 / --ohne-ntfs) =="

baue_variante() { # name optionen...
    local name=$1; shift
    if bash tools/build-kernel.sh "$TMPD/v-$name.mb" --stufe 0 "$@" \
        > "$TMPD/v-$name.log" 2>&1; then
        stat -c%s "$TMPD/v-$name.mb"
    else
        echo 0
    fi
}

gr_voll=$(baue_variante voll)
gr_oe=$(baue_variante ohne-ext4 --ohne-ext4)
gr_on=$(baue_variante ohne-ntfs --ohne-ntfs)
gr_ob=$(baue_variante ohne-beide --ohne-fremdfs)

num "das volle Abbild ist gebaut" "${gr_voll:-0}" gt 1000000
num "das Abbild ohne ext4 ist gebaut" "${gr_oe:-0}" gt 1000000
num "das Abbild ohne NTFS ist gebaut" "${gr_on:-0}" gt 1000000
num "das Abbild ohne beide ist gebaut" "${gr_ob:-0}" gt 1000000

# JEDES ABSCHALTEN MUSS DAS ABBILD WIRKLICH KLEINER MACHEN. Eine
# Bauoption, die nichts spart, hat nichts ausgebaut -- dann stuende der
# Treiber noch drin und die Zusage waere eine Behauptung.
if [ "${gr_oe:-0}" -lt "${gr_voll:-0}" ] 2>/dev/null; then
    ok "--ohne-ext4 spart $(( gr_voll - gr_oe )) Oktette ($(( (gr_voll - gr_oe) / 1024 )) KiB)"
else
    bad "--ohne-ext4 macht das Abbild NICHT kleiner"
fi
if [ "${gr_on:-0}" -lt "${gr_voll:-0}" ] 2>/dev/null; then
    ok "--ohne-ntfs spart $(( gr_voll - gr_on )) Oktette ($(( (gr_voll - gr_on) / 1024 )) KiB)"
else
    bad "--ohne-ntfs macht das Abbild NICHT kleiner"
fi
if [ "${gr_ob:-0}" -lt "${gr_oe:-0}" ] && [ "${gr_ob:-0}" -lt "${gr_on:-0}" ] 2>/dev/null; then
    ok "--ohne-fremdfs spart $(( gr_voll - gr_ob )) Oktette ($(( (gr_voll - gr_ob) / 1024 )) KiB), mehr als jedes einzeln"
else
    bad "--ohne-fremdfs spart nicht mehr als die Einzelschalter"
fi
printf 'voll %s\nohne-ext4 %s\nohne-ntfs %s\nohne-beide %s\n' \
    "$gr_voll" "$gr_oe" "$gr_on" "$gr_ob" > "$TMPD/groessen.txt"

# DIE ZEILE, DIE ES SAGT. Wer ein Abbild in der Hand hat, muss ihm
# ansehen koennen, was darin ist.
grep -qa 'ext4=aus, ntfs=aus' "$TMPD/v-ohne-beide.log" \
    && ok "der Bau meldet 'ext4=aus, ntfs=aus'" \
    || bad "der Bau sagt nicht, dass die zwei fehlen"
grep -qa 'ext4=an, ntfs=an' "$TMPD/v-voll.log" \
    && ok "und beim vollen Bau 'ext4=an, ntfs=an'" \
    || bad "der volle Bau sagt es nicht"

# DER LAUF OHNE BEIDE. Das System muss unveraendert hochkommen, und
# ein Einhaengeversuch muss SOFORT scheitern -- nicht haengen.
lauf_mit() { # name kernel zweite kommandozeile
    local name=$1 kern=$2 second=$3 app=$4
    cp --sparse=always "$TMPD/root.img" "$TMPD/live-$name.img"
    local drives=(-drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0")
    if [ -n "$second" ]; then
        cp --sparse=always "$second" "$TMPD/live2-$name.img"
        drives+=(-drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1")
    fi
    local acc=""
    [ "$OSUM_QEMU_ACCEL" = kvm ] && acc="-cpu host"
    timeout 300 $QEMU_X86 $acc -kernel "$kern" -m 512 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${drives[@]}" > /dev/null 2>&1
    echo $?
}

if [ "${gr_ob:-0}" -gt 1000000 ]; then
    rc=$(lauf_mit ohne-e4 "$TMPD/v-ohne-beide.mb" "$TMPD/ext4-part.img" \
        "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
    num "[ohne-beide] der Kernel beendet sich selbst statt zu haengen" "$rc" eq 21
    sagt "$TMPD/ohne-e4.txt" mount 0 \
        "[ohne-beide] ein ext4 wird ABGELEHNT (Dateisystem nicht unterstuetzt)"
    # UND ZWAR OHNE EINEN EINZIGEN VERSUCH, DIE PLATTE ZU LESEN: die
    # Leerfassung meldet gar nichts. Steht hier trotzdem eine Zeile des
    # Treibers, ist er doch mit im Abbild.
    if grep -qa '^ext4: ' "$TMPD/ohne-e4.txt"; then
        bad "[ohne-beide] der ext4-Treiber meldet sich -- er ist noch im Abbild"
    else
        ok "[ohne-beide] der ext4-Treiber meldet sich mit keiner Zeile"
    fi

    rc=$(lauf_mit ohne-nt "$TMPD/v-ohne-beide.mb" "$TMPD/ntfs-part.img" \
        "osum nokbd vfs script=fremdfs ntfs /dev/hdb1 /mnt")
    num "[ohne-beide] derselbe Lauf mit NTFS beendet sich selbst" "$rc" eq 21
    sagt "$TMPD/ohne-nt.txt" mount 0 \
        "[ohne-beide] ein NTFS wird ABGELEHNT"
    if grep -qa '^ntfs: ' "$TMPD/ohne-nt.txt"; then
        bad "[ohne-beide] der NTFS-Treiber meldet sich -- er ist noch im Abbild"
    else
        ok "[ohne-beide] der NTFS-Treiber meldet sich mit keiner Zeile"
    fi

    # DAS SYSTEM LAEUFT UNVERAENDERT. Dieselbe Arbeit auf der eigenen
    # Wurzelplatte, mit dem Abbild ohne die zwei Treiber -- sie muss
    # genauso durchgehen wie mit ihnen.
    rc=$(lauf_mit ohne-ofs "$TMPD/v-ohne-beide.mb" "" \
        "osum nokbd vfs script=ls /bin;echo fertig-ohne")
    num "[ohne-beide] das System kommt ohne die zwei Treiber hoch" "$rc" eq 21
    hat "$TMPD/ohne-ofs.txt" "fertig-ohne" \
        "[ohne-beide] und arbeitet auf der eigenen Platte unveraendert weiter"

    # EINZELN: mit --ohne-ext4 muss NTFS noch gehen.
    rc=$(lauf_mit nur-ntfs "$TMPD/v-ohne-ext4.mb" "$TMPD/ntfs-part.img" \
        "osum nokbd vfs script=fremdfs ntfs /dev/hdb1 /mnt")
    num "[ohne-ext4] der Lauf beendet sich selbst" "$rc" eq 21
    sagt "$TMPD/nur-ntfs.txt" mount 1 \
        "[ohne-ext4] NTFS geht weiterhin -- die Schalter wirken EINZELN"
    rc=$(lauf_mit nur-ext4 "$TMPD/v-ohne-ntfs.mb" "$TMPD/ext4-part.img" \
        "osum nokbd vfs script=fremdfs ext4 /dev/hdb1 /mnt")
    num "[ohne-ntfs] der Lauf beendet sich selbst" "$rc" eq 21
    sagt "$TMPD/nur-ext4.txt" mount 1 \
        "[ohne-ntfs] ext4 geht weiterhin"
fi

# Die Abbilder dieses Abschnitts sind gemessen und gelaufen; sie
# belegen zusammen gut 20 MB und werden nicht mehr gebraucht.
rm -f "$TMPD"/v-*.mb "$TMPD"/v-*.mb.elf "$TMPD"/live-ohne-*.img \
      "$TMPD"/live2-ohne-*.img "$TMPD"/live-nur-*.img \
      "$TMPD"/live2-nur-*.img 2>/dev/null

# ------------------------------------------------- 8. die Lesegeschwindigkeit

echo "== 8. wie schnell gelesen wird (gegen das eigene OFS) =="
# Dieselbe Arbeit, dieselbe Maschine: die 6-MiB-Datei einmal ganz
# lesen. Gemessen wird die Zeit des GANZEN Laufs -- das ist kein
# Mikromassstab, aber es ist eine ehrliche Zahl, und der Vergleich
# zwischen den Dateisystemen ist fair, weil alles andere gleich bleibt.
messen() { # name abbild art
    local name=$1 abbild=$2 art=$3 t0 t1
    t0=$(date +%s%N)
    lauf "$name" "$TMPD/root.img" "$abbild" \
        "osum nokbd vfs script=fremdfs $art /dev/hdb1 /mnt" >/dev/null
    t1=$(date +%s%N)
    echo $(( (t1 - t0) / 1000000 ))
}
if [ "$NUR" = beide ]; then
    ms_ext4=$(messen zeit-ext4 "$TMPD/ext4-part.img" ext4)
    ms_ntfs=$(messen zeit-ntfs "$TMPD/ntfs-part.img" ntfs)
    echo "  ext4: ${ms_ext4} ms fuer den ganzen Durchgang (6 MiB + 520 Dateien)"
    echo "  ntfs: ${ms_ntfs} ms fuer den ganzen Durchgang (6 MiB + 520 Dateien)"
    printf 'ext4 %s\nntfs %s\n' "$ms_ext4" "$ms_ntfs" > "$TMPD/zeiten.txt"
    num "ext4 liest den Baum in unter 120 Sekunden" "${ms_ext4:-999999}" lt 120000
    num "ntfs liest den Baum in unter 120 Sekunden" "${ms_ntfs:-999999}" lt 120000
fi

# ------------------------------------------------------------- das Ergebnis

echo
echo "accel: $OSUM_QEMU_ACCEL ($OSUM_ACCEL_GRUND)"
echo "FREMDFS: $pass bestanden, $fail gescheitert"
[ "$fail" -eq 0 ]
