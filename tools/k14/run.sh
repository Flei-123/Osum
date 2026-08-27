#!/usr/bin/env bash
# tools/k14/run.sh -- DIE VFS-SCHICHT UND DIE FREMDEN DATEISYSTEME.
#
# Bis zu dieser Runde kannte Osum genau EIN Dateisystem: sein eigenes.
# `mount` gab es, aber ohne Ziel -- es hiess "die eine Platte ist da".
# Folge: kein /proc, kein /dev als Verzeichnis, und jede Platte, die
# Linux oder Windows beschrieben hatte, war unlesbar.
#
# WAS HIER GEMESSEN WIRD, und alles davon IM LAUFENDEN KERNEL:
#
#   1. DIE NUMMERN. mount ist 165, umount2 ist 166, rename ist 82 --
#      Linux' Nummern, weil Linux die Aufrufe hat. Die eigene Nummer
#      dieser Runde liegt im zugeteilten Block 1700..1799. Und die
#      Karte von `kdata`: die drei Seiten dieser Runde liegen in
#      0x43000..0x46000 und ueberschneiden sich mit nichts.
#   2. DASS DIE OPS-TAFEL ECHTE ZEIGER SIND. Die uebersetzte
#      Objektdatei wird ZERLEGT und die `call *`-Befehle werden
#      gezaehlt. Eine Weiche aus `if`s hat keinen einzigen davon. Dazu
#      der Zaehlerbeweis im Lauf: `VFS_OPS` zaehlt die Schicht, wenn
#      sie eine Verrichtung ANSTOESST, `VFS_INDIRECT` zaehlt der
#      TREIBER, wenn sie bei ihm ANKOMMT -- zwei Zaehler an zwei
#      Stellen, und ihre Gleichheit ist eine Aussage.
#   3. FAT32 GEGEN DIE ECHTEN LINUX-WERKZEUGE. Das Abbild kommt von
#      `mkfs.vfat`, die Dateien von `mcopy`, die Partitionstafel von
#      `sfdisk` und `sgdisk`. Osum liest sie und der Inhalt wird OKTETT
#      FUER OKTETT verglichen. Umgekehrt: was Osum schreibt, holt
#      `mcopy` wieder heraus und `cmp` vergleicht es -- und `fsck.fat`
#      sagt, ob das Dateisystem danach noch eines ist.
#   4. MBR UND GPT. Beide Tafeln, beide von fremden Werkzeugen
#      geschrieben. Bei GPT werden BEIDE Pruefsummen gerechnet; ein
#      umgedrehtes Bit im Kopf MUSS dazu fuehren, dass Osum die Platte
#      nicht mehr liest.
#   5. /proc UND /dev als echte Dateisysteme, gemessen ueber ein
#      Programm in Ring 3 (`/bin/k14`), das jede Antwort als Zahl
#      meldet -- und `ps` (ueber SYS_OSUM_PSTAT) gegen
#      `cat /proc/<pid>/stat` (ueber das Dateisystem), Zahl fuer Zahl.
#   6. DIE GEGENPROBEN, ohne die in diesem Projekt nichts zaehlt:
#      `novfs` (nur die Wurzel -- alles andere MUSS verschwinden),
#      `noprocfs`, `nodevfs`, `nofat`, `nopart` (das Dateisystem wird
#      bei Block 0 gesucht, wo die TAFEL steht -- die Messung MUSS
#      zusammenbrechen), `fatro` (jeder Schreibversuch -EROFS), ein
#      Lauf ohne zweite Platte, und ein Abbild mit einem kaputten
#      GPT-Kopf.
#   7. OFS VERLIERT NICHTS. Derselbe Kernel, dieselbe Arbeit, einmal
#      auf dem geraden Weg von Runde 62 und einmal mit `vfsall` durch
#      die Ops-Tafel -- die Ausgaben werden OKTETT FUER OKTETT
#      verglichen. Das ist der Beweis, dass OFS ein NUTZER dieser
#      Schicht ist und kein Sonderfall daneben.
#
# Gemessen wie in den Runden 59 bis K12: QEMU je Fall, mit Zeitlimit,
# serielle Ausgabe gegen Erwartungen, Beendigungscode aus
# `isa-debug-exit` (21 = der Kernel hat sich selbst beendet, 63 = eine
# Ausnahme).
#
# Aufruf:  bash tools/k14/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
ULD=kernel/user/user.ld
BLOCKS=4096
PROGS="sh cat echo ls cp rm mkdir wc grep head true false ps mount umount k14"

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
        printf '        soll: %s\n' "$(printf '%s' "$2" | head -c 300)"
        printf '        ist : %s\n' "$(printf '%s' "$3" | head -c 300)"
    fi
}
dateien_gleich() { # name sollDatei istDatei
    if cmp -s "$2" "$3"; then ok "$1"
    else
        bad "$1"
        diff <(od -c "$2" | head -12) <(od -c "$3" | head -12) | head -10 | sed 's/^/        /'
    fi
}
hat() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hat_nicht() { grep -qaF "$2" "$1" && bad "$3 -- '$2' steht da und sollte nicht" || ok "$3"; }

# Ein Wert aus der Ausgabe von /bin/k14 ("k14: name = zahl").
wert() { # datei name
    grep -a -m1 "^k14: $2 = " "$1" 2>/dev/null | sed 's/.* = //' | tr -d '\r\000'
}
sagt() { # datei name soll beschreibung
    local got
    got=$(wert "$1" "$2")
    if [ -z "$got" ]; then bad "$4 -- keine Zeile 'k14: $2 ='"; return; fi
    if [ "$got" = "$3" ]; then ok "$4 ($2 = $got)"
    else bad "$4 -- $2 = $got, erwartet $3"; fi
}
number_in() { # datei name
    grep -aE "^const $2: u64 = [0-9]+" "$1" | head -1 \
        | sed -E 's/^const [A-Za-z0-9_]+: u64 = ([0-9]+).*/\1/'
}

bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "vendor/firn/fetch-firnc.sh fehlgeschlagen"; exit 1; }
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "K14: uebersprungen, qemu-system-x86_64 fehlt"
    exit 0
fi
for w in mkfs.vfat mcopy mdir mmd mtype sfdisk; do
    command -v "$w" >/dev/null 2>&1 || {
        echo "K14: uebersprungen, $w fehlt (dosfstools/mtools/util-linux)"
        exit 0
    }
done

# ---------------------------------------------------------- 1. die Nummern

echo "== 1. die Nummern, die Karte von kdata und die Zahlenvorraete =="
check() { # name soll grund
    local got
    got=$(number_in kernel/sys.fi "SYS_$1")
    if [ "$got" = "$2" ]; then ok "SYS_$1 = $2 ($3)"
    else bad "SYS_$1 = ${got:-fehlt}, erwartet $2"; fi
}
check MOUNT 165 "Linux' Nummer"
check UMOUNT2 166 "Linux' Nummer"
check RENAME 82 "Linux' Nummer"
check OSUM_MNTSTAT 1700 "der Block dieser Runde"

# Die eigene Nummer dieser Runde liegt im ZUGETEILTEN Bereich und
# nirgends sonst. Drei Runden arbeiten gleichzeitig an diesem Baum; das
# ist genau die Lage, aus der die vier kdata-Kollisionen entstanden sind.
mnt_nr=$(number_in kernel/sys.fi "SYS_OSUM_MNTSTAT")
if [ "${mnt_nr:-0}" -ge 1700 ] && [ "${mnt_nr:-0}" -le 1799 ]; then
    ok "die eigene Aufrufnummer liegt im Vorrat 1700..1799: $mnt_nr"
else
    bad "die eigene Aufrufnummer $mnt_nr liegt AUSSERHALB von 1700..1799"
fi
kfile=$(number_in kernel/file.fi "K_VFILE")
kdir=$(number_in kernel/file.fi "K_VDIR")
gleich "die Deskriptorarten dieser Runde sind 12 und 13" "12 13" "$kfile $kdir"

# Die kdata-Karte. `memmap.py` rechnet jede Ueberschneidung nach -- diese
# Stelle hat dem Projekt viermal denselben Fehler beschert.
if python3 tools/kernel/memmap.py kernel > "$TMPD/karte.txt" 2>&1; then
    ok "die Speicherkarte von kdata: $(tail -1 "$TMPD/karte.txt")"
else
    bad "tools/kernel/memmap.py meldet Kollisionen"
    sed 's/^/        /' "$TMPD/karte.txt" | head -8
fi
hat "$TMPD/karte.txt" "0 Kollisionen" "keine zwei Bereiche ueberschneiden sich"
for r in K14_OFF FAT_OFF PROCFS_OFF; do
    v=$(grep -aE "^const $r: u64 = 0x[0-9A-Fa-f]+" kernel/kstate.fi | head -1 | grep -oE '0x[0-9A-Fa-f]+')
    d=$((v))
    if [ "$d" -ge $((0x43000)) ] && [ "$d" -lt $((0x46000)) ]; then
        ok "$r = $v liegt im zugeteilten Bereich 0x43000..0x46000"
    else
        bad "$r = ${v:-fehlt} liegt AUSSERHALB von 0x43000..0x46000"
    fi
done
# GEGENPROBE ZUR KARTE: eine Seite dieser Runde auf eine fremde Adresse
# gelegt MUSS anschlagen. Ohne diese Zeile prueft die Karte nur das,
# woran jemand gedacht hat.
mkdir -p "$TMPD/kollision"
cp kernel/*.fi "$TMPD/kollision/"
sed -i 's/^const PROCFS_OFF: u64 = 0x45000$/const PROCFS_OFF: u64 = 0x3C000/' "$TMPD/kollision/kstate.fi"
if python3 tools/kernel/memmap.py "$TMPD/kollision" > "$TMPD/karte2.txt" 2>&1; then
    bad "GEGENPROBE: PROCFS_OFF auf 0x3C000 (= FB_OFF) und der Pruefer schweigt"
else
    ok "GEGENPROBE: PROCFS_OFF auf FB_OFF gelegt -- der Kartenpruefer schlaegt an"
fi

# --------------------------------------------------------------- 2. bauen

echo "== 2. bauen: der Kern und der Werkzeugkasten, aus beiden Uebersetzern =="
as --64 -o "$TMPD/crt.o" kernel/user/crt.s 2>/dev/null || bad "crt.s laesst sich nicht assemblieren"

baue_stufe() { # 0 | 1
    local s=$1 cc p rc=0
    if [ "$s" = 0 ]; then cc="$FIRNC"; else cc="$FC1"; fi
    bash tools/build-kernel.sh "$TMPD/k$s.mb" --stufe "$s" > "$TMPD/k$s.log" 2>&1 || {
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
            -o "$TMPD/$p$s.elf" "$TMPD/crt.o" "$TMPD/$p$s.o" 2>"$TMPD/ld.err" || {
            bad "firnc$s: ld scheitert an $p"; rc=1; continue; }
        strip --strip-all "$TMPD/$p$s.elf"
    done
    return $rc
}
baue_stufe 0 || { echo "K14: $pass passed, $((fail+1)) failed"; exit 1; }
ok "firnc0: der Kern und $(echo $PROGS | wc -w) Programme sind gebaut"
if baue_stufe 1; then
    ok "firnc1: dasselbe aus dem Uebersetzer, der in Firn geschrieben ist"
else
    bad "firnc1 baut diese Runde nicht"
fi

# ------------------------------- 3. die Ops-Tafel sind ECHTE Zeiger

echo "== 3. die Tafel der Verrichtungen ist eine Tafel von ZEIGERN =="
# Firn Stufe 0 kann einen Funktionszeiger weder in eine Zahl wandeln
# noch aus einer Tafel heraus aufrufen ("only direct function names can
# be called"). Ein FELD EINER STRUKTUR aufzurufen kann es -- und das
# ergibt `call *rax`. Eine Weiche aus `if`s ergaebe keinen einzigen.
indirekt0=$(objdump -d "$TMPD/k0.mb.elf" 2>/dev/null | grep -cE 'call.*\*')
num "indirekte Aufrufe im Kern (firnc0)" "$indirekt0" ge 9
if [ -f "$TMPD/k1.mb.elf" ]; then
    indirekt1=$(objdump -d "$TMPD/k1.mb.elf" 2>/dev/null | grep -cE 'call.*\*')
    num "indirekte Aufrufe im Kern (firnc1)" "$indirekt1" ge 9
fi
# Sie stehen in `vfs.fi`: jede der neun Verrichtungen genau einmal.
for f in node_for v_readdir v_attr v_read v_write v_create v_unlink v_rename v_trunc; do
    n=$(objdump -d "$TMPD/k0.mb.elf" --disassemble="_F0.vfs__$f" 2>/dev/null \
        | grep -cE 'call.*\*')
    if [ "${n:-0}" -ge 1 ]; then ok "vfs.$f ruft ueber einen Zeiger ($n)"
    else bad "vfs.$f enthaelt keinen indirekten Aufruf"; fi
done
# Und: `vfs.fi` kennt OFS nicht beim Namen. `fs.` kommt dort nicht vor
# -- das ist der Unterschied zwischen einer Schicht und einer Weiche.
aussen=$(grep -acE '(^|[^a-z_])fs\.[a-z_]+\(' kernel/vfs.fi)
num "Aufrufe von fs.* (OFS) in kernel/vfs.fi" "$aussen" eq 0
neun=$(grep -acE '^    (lookup|readdir|attr|read|write|create|unlink|rename|trunc): fn' kernel/vfsops.fi)
num "Verrichtungen in der Tafel von vfsops.fi" "$neun" eq 9

# ------------------------------------------- 4. die Abbilder, von aussen

echo "== 4. die Abbilder: FAT32 von mkfs.vfat, Partitionen von sfdisk/sgdisk =="
FAT="$TMPD/fat.img"
dd if=/dev/zero of="$FAT" bs=1M count=64 status=none
mkfs.vfat -F 32 -s 1 -n OSUMTEST "$FAT" >/dev/null 2>"$TMPD/mkfs.err" \
    && ok "mkfs.vfat hat ein FAT32 angelegt (64 MiB, 1 Sektor je Verband)" \
    || bad "mkfs.vfat scheitert: $(head -2 "$TMPD/mkfs.err")"

printf 'hallo aus linux\n' > "$TMPD/hello.txt"
head -c 5000 /dev/urandom > "$TMPD/blob.bin"
# Eine Datei, die NICHT in 8+3 passt: nur ueber einen LANGEN NAMEN
# lesbar. Ein Treiber ohne VFAT-Lesung sieht hier "EINSEH~1.TXT".
printf 'langer name\n' > "$TMPD/lang.txt"
mcopy -i "$FAT" "$TMPD/hello.txt" ::hello.txt
mcopy -i "$FAT" "$TMPD/blob.bin" ::blob.bin
mcopy -i "$FAT" "$TMPD/lang.txt" ::einsehrlangername.txt
mmd -i "$FAT" ::unter
mcopy -i "$FAT" "$TMPD/hello.txt" ::unter/tief.txt
mdir -i "$FAT" :: > "$TMPD/mdir0.txt" 2>&1 \
    && ok "mcopy/mmd haben vier Dateien und ein Verzeichnis hineingelegt" \
    || bad "mcopy scheitert"

# Die MBR-Platte.
MBR="$TMPD/mbr.img"
dd if=/dev/zero of="$MBR" bs=1M count=80 status=none
printf 'label: dos\nstart=2048, type=c\n' | sfdisk "$MBR" >/dev/null 2>&1 \
    && ok "sfdisk hat eine MBR-Tafel geschrieben (Typ 0x0C, FAT32 LBA)" \
    || bad "sfdisk scheitert"
dd if="$FAT" of="$MBR" bs=512 seek=2048 conv=notrunc status=none

# Die GPT-Platte.
GPT="$TMPD/gpt.img"
if command -v sgdisk >/dev/null 2>&1; then
    dd if=/dev/zero of="$GPT" bs=1M count=80 status=none
    sgdisk -o -n 1:2048:+70M -t 1:0700 -c 1:OSUMFAT "$GPT" >/dev/null 2>&1 \
        && ok "sgdisk hat eine GPT geschrieben (Microsoft basic data)" \
        || bad "sgdisk scheitert"
    dd if="$FAT" of="$GPT" bs=512 seek=2048 conv=notrunc status=none
else
    GPT=""
    echo "  (sgdisk fehlt -- der GPT-Teil wird uebersprungen)"
fi

# Die Wurzelplatte von Osum. /proc, /dev und /mnt sind VERZEICHNISSE
# darin -- ohne sie wird nichts eingehaengt, und genau deshalb aendert
# diese Runde an den Abbildern der Runden 59 bis K12 nichts.
MKARGS=""
for p in $PROGS; do MKARGS="$MKARGS /bin/$p=$TMPD/${p}0.elf"; done
python3 tools/osum/mkfs.py build "$TMPD/root.img" "$BLOCKS" \
    /bin/ /proc/ /dev/ /mnt/ $MKARGS > "$TMPD/mkfs.log" 2>&1 \
    && ok "die Wurzelplatte steht: $(tail -1 "$TMPD/mkfs.log")" \
    || { bad "mkfs.py scheitert"; sed 's/^/        /' "$TMPD/mkfs.log" | head -5; }

# ------------------------------------------------------------ der Lauf

lauf() { # name kernel wurzel zweite kommandozeile [zeitlimit]
    local name=$1 img=$2 root=$3 second=$4 app=$5 t=${6:-200}
    cp "$root" "$TMPD/live-$name.img"
    local drives=(-drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0")
    if [ -n "$second" ]; then
        cp "$second" "$TMPD/live2-$name.img"
        drives+=(-drive "file=$TMPD/live2-$name.img,format=raw,if=ide,index=1")
    fi
    timeout "$t" qemu-system-x86_64 -kernel "$img" -m 256 -append "$app" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        "${drives[@]}" > /dev/null 2>&1
    echo $?
}

# ------------------------------------- 5. der Regellauf, MBR

echo "== 5. der Regellauf: vier Dateisysteme nebeneinander (MBR) =="
rc=$(lauf haupt "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" "osum nokbd vfs script=k14")
num "der Kernel beendet sich selbst (21)" "$rc" eq 21
H="$TMPD/haupt.txt"
hat "$H" "k14: root=1" "die Wurzel ist ein Eintrag der Einhaengetafel"
hat "$H" "part: mbr=1" "die MBR-Tafel wurde gelesen"
hat "$H" "fat: spc=1" "der FAT32-Kopf wurde angenommen"

sagt "$H" mount_count 4 "vier Dateisysteme sind eingehaengt"
sagt "$H" root_type 1 "auf / liegt OFS"
sagt "$H" proc_type 2 "auf /proc liegt procfs"
sagt "$H" dev_type 3 "auf /dev liegt devfs"
sagt "$H" fat_type 4 "auf /mnt liegt FAT32"
sagt "$H" fat_dev 3 "und zwar auf der ZWEITEN Platte (DEV_ATA1)"
sagt "$H" st_dev_different 1 "zwei Dateisysteme haben zwei st_dev"
sagt "$H" mnttest_is_err 2 "/mnttest ist NICHT /mnt (Namensgrenze)"
sagt "$H" deep_fat_size 16 "eine Datei zwei Ebenen tief im FAT32"
sagt "$H" fat_dir_mode 1 "ein FAT32-Verzeichnis meldet sich als Verzeichnis"
sagt "$H" opens_before 0 "vor dem Oeffnen: null Deskriptoren auf /mnt"
sagt "$H" opens_open 1 "nach dem Oeffnen: einer"
sagt "$H" umount_busy 16 "umount mit offenem Deskriptor: -EBUSY"
sagt "$H" opens_after 0 "nach dem Schliessen: wieder null"
sagt "$H" opens_dup 1 "zwei Deskriptoren, eine offene Datei: die Einhaengung ist EINMAL offen"
sagt "$H" opens_dup1 1 "der erste von beiden geschlossen: immer noch einmal"
sagt "$H" opens_dup0 0 "der zweite auch: jetzt null"
sagt "$H" umount_ok 0 "dann geht umount"
sagt "$H" gone_is_err 2 "und danach ist die Datei wirklich weg"
sagt "$H" mount_ok 0 "mount /dev/hdb1 /mnt vfat bringt sie zurueck"
sagt "$H" back_is_err 0 "und sie ist wieder da"
sagt "$H" status_lines 10 "/proc/<pid>/status hat zehn Zeilen"
sagt "$H" mounts_lines 4 "/proc/mounts hat eine Zeile je Einhaengung"
sagt "$H" maps_grew 1 "/proc/<pid>/maps waechst mit einer neuen Abbildung"
sagt "$H" cmdline_len 4 "/proc/<pid>/cmdline ist 'k14' plus Null"
sagt "$H" null_read 0 "/dev/null liest null Oktette"
sagt "$H" null_write 64 "/dev/null schluckt alles"
sagt "$H" zero_all_zero 1 "/dev/zero liefert Nullen"
sagt "$H" hdb_boot_ok 1 "/dev/hdb liefert den Bootsatz mit 0x55 0xAA"
sagt "$H" hdb_size 83886080 "/dev/hdb ist 80 MiB gross (lseek SEEK_END)"
sagt "$H" hdb_mode 1 "/dev/hdb meldet sich als BLOCKgeraet"
sagt "$H" null_mode 1 "/dev/null meldet sich als ZEICHENgeraet"
sagt "$H" proc_write_err 1 "in /proc schreiben: -EPERM"
sagt "$H" proc_mkdir_err 1 "in /proc anlegen: -EPERM"
sagt "$H" proc_unlink_err 1 "in /proc loeschen: -EPERM"
sagt "$H" dev_create_err 1 "in /dev anlegen: -EPERM"
sagt "$H" xdev_rename 18 "umbenennen ueber eine Einhaengegrenze: -EXDEV"
sagt "$H" fat_renam 0 "umbenennen INNERHALB von FAT32 geht"
sagt "$H" fat_renam_ok 0 "und der neue Name ist da"
sagt "$H" fat_write_back 0 "und wieder zurueck"
sagt "$H" done 1 "das Messprogramm ist bis zum Ende gekommen"

r=$(wert "$H" rand_varies)
num "/dev/urandom: zwei Puffer unterscheiden sich in n Oktetten" "${r:-0}" ge 40
p=$(wert "$H" status_pid)
num "/proc/<pid>/status nennt die eigene Pid" "${p:-0}" ge 2
mem=$(wert "$H" meminfo_total)
num "/proc/meminfo nennt den Speicher in kB" "${mem:-0}" ge 100000
fdn=$(wert "$H" fd_count)
num "/proc/<pid>/fd zaehlt die eigenen Deskriptoren" "${fdn:-0}" ge 3
upb=$(wert "$H" uptime_bytes)
num "/proc/uptime ist eine Zeile mit zwei Zahlen" "${upb:-0}" ge 6

# Die Zaehler der Schicht. VFS_OPS zaehlt die Schicht beim ANSTOSSEN,
# VFS_INDIRECT der TREIBER beim ANKOMMEN -- zwei Stellen, eine Zahl.
line=$(grep -a -m1 '^k14: mounts=' "$H" | tr -d '\000\r')
ops=$(echo "$line" | grep -oE 'ops=[0-9]+' | grep -oE '[0-9]+')
ind=$(echo "$line" | grep -oE 'indirect=[0-9]+' | grep -oE '[0-9]+')
cross=$(echo "$line" | grep -oE 'crossings=[0-9]+' | grep -oE '[0-9]+')
num "Verrichtungen ueber die Ops-Tafel" "${ops:-0}" ge 40
gleich "jede angestossene Verrichtung kam beim Treiber an ($ops)" "$ops" "$ind"
num "ueberquerte Einhaengegrenzen" "${cross:-0}" ge 10

# ---------------------------------- 6. FAT32 gegen die echten Werkzeuge

echo "== 6. FAT32 gegen mkfs.vfat, mcopy, mdir und fsck.fat =="
# 6a: LESEN. Osum kopiert die Dateien der fremden Platte auf SEINE
# eigene, und der Wirt holt sie dort heraus und vergleicht sie Oktett
# fuer Oktett mit dem, was `mcopy` hineingelegt hat.
rc=$(lauf lesen "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs script=cp /mnt/hello.txt /a.txt;cp /mnt/blob.bin /b.bin;cp /mnt/unter/tief.txt /c.txt;cp /mnt/einsehrlangername.txt /d.txt;ls /mnt")
num "der Lesefall beendet sich selbst" "$rc" eq 21
python3 tools/osum/mkfs.py cat "$TMPD/live-lesen.img" /a.txt > "$TMPD/got_a" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/live-lesen.img" /b.bin > "$TMPD/got_b" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/live-lesen.img" /c.txt > "$TMPD/got_c" 2>/dev/null
python3 tools/osum/mkfs.py cat "$TMPD/live-lesen.img" /d.txt > "$TMPD/got_d" 2>/dev/null
dateien_gleich "hello.txt: was mcopy hineinlegte, kam heraus" "$TMPD/hello.txt" "$TMPD/got_a"
dateien_gleich "blob.bin: 5000 Oktette Zufall, Oktett fuer Oktett" "$TMPD/blob.bin" "$TMPD/got_b"
dateien_gleich "unter/tief.txt: zwei Ebenen tief" "$TMPD/hello.txt" "$TMPD/got_c"
dateien_gleich "einsehrlangername.txt: nur ueber den LANGEN Namen" "$TMPD/lang.txt" "$TMPD/got_d"
hat "$TMPD/lesen.txt" "einsehrlangername.txt" "der lange Name steht in der Auflistung"
hat_nicht "$TMPD/lesen.txt" "EINSEH~1" "und NICHT die 8+3-Kruecke"

# 6b: SCHREIBEN. Was Osum schreibt, holt `mcopy` wieder heraus.
rc=$(lauf schreiben "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs script=echo osum-war-hier > /mnt/neu.txt;cp /mnt/blob.bin /mnt/kopie.bin;mkdir /mnt/neuverz;echo tief > /mnt/neuverz/x.txt;rm /mnt/hello.txt;umount /mnt;mount")
num "der Schreibfall beendet sich selbst" "$rc" eq 21
Z="$TMPD/live2-schreiben.img"
mdir -i "$Z@@1048576" :: > "$TMPD/mdir1.txt" 2>&1
hat "$TMPD/mdir1.txt" "neu.txt" "mdir sieht die von Osum angelegte Datei"
hat "$TMPD/mdir1.txt" "kopie.bin" "mdir sieht die 5000 Oktette, die Osum kopiert hat"
hat "$TMPD/mdir1.txt" "neuverz" "mdir sieht das von Osum angelegte Verzeichnis"
hat_nicht "$TMPD/mdir1.txt" "hello    txt" "die von Osum geloeschte Datei ist weg"
mcopy -i "$Z@@1048576" ::kopie.bin "$TMPD/back.bin" 2>/dev/null
dateien_gleich "kopie.bin: was Osum schrieb, liest mcopy Oktett fuer Oktett" \
    "$TMPD/blob.bin" "$TMPD/back.bin"
mtype -i "$Z@@1048576" ::neu.txt > "$TMPD/neu.txt" 2>/dev/null
gleich "der Inhalt der neuen Datei" "osum-war-hier" "$(tr -d '\r\n' < "$TMPD/neu.txt")"
mdir -i "$Z@@1048576" ::/neuverz > "$TMPD/mdir2.txt" 2>&1
hat "$TMPD/mdir2.txt" "x.txt" "im neuen Verzeichnis liegt die neue Datei"
hat "$TMPD/mdir2.txt" "<DIR>" "das neue Verzeichnis hat . und .."
# Das Datum: ein FAT-Eintrag ohne Datum traegt Monat 0 und Tag 0, und
# die gibt es nicht. `mdir` schreibt dann "1980-00-00".
hat_nicht "$TMPD/mdir1.txt" "1980-00-00" "die neuen Eintraege tragen ein gueltiges Datum"

# 6c: fsck.fat -- das Urteil eines fremden Pruefers.
if command -v fsck.fat >/dev/null 2>&1; then
    dd if="$Z" of="$TMPD/teil.img" bs=512 skip=2048 status=none
    fsck.fat -n "$TMPD/teil.img" > "$TMPD/fsck.txt" 2>&1
    frc=$?
    num "fsck.fat auf dem von Osum beschriebenen Dateisystem (0 = sauber)" "$frc" eq 0
    sed 's/^/        /' "$TMPD/fsck.txt" | head -6
    # GEGENPROBE: OHNE `umount` bleibt die Zahl der freien Verbaende
    # "unbekannt" -- fsck sagt es dann, und genau daran sieht man, dass
    # `umount` wirklich etwas tut.
    rc=$(lauf ohnesync "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
        "osum nokbd vfs script=echo x > /mnt/ohnesync.txt")
    dd if="$TMPD/live2-ohnesync.img" of="$TMPD/teil2.img" bs=512 skip=2048 status=none
    fsck.fat -n "$TMPD/teil2.img" > "$TMPD/fsck2.txt" 2>&1
    hat "$TMPD/fsck2.txt" "Free cluster summary" \
        "GEGENPROBE: ohne umount meldet fsck die nicht nachgefuehrte Zahl"
else
    echo "  (fsck.fat fehlt -- das Urteil des fremden Pruefers entfaellt)"
fi

# ------------------------------------------------- 7. MBR, GPT und Bruch

echo "== 7. die Partitionstafel: MBR, GPT und ein umgedrehtes Bit =="
if [ -n "$GPT" ]; then
    rc=$(lauf gpt "$TMPD/k0.mb" "$TMPD/root.img" "$GPT" \
        "osum nokbd vfs script=cat /mnt/hello.txt")
    num "der GPT-Fall beendet sich selbst" "$rc" eq 21
    hat "$TMPD/gpt.txt" "part: mbr=2  gpt=1" "der Schutz-MBR wurde als GPT erkannt"
    hat "$TMPD/gpt.txt" "parts=1" "die GPT nennt eine Partition"
    hat "$TMPD/gpt.txt" "hallo aus linux" "und die Datei darin ist lesbar"
    hat_nicht "$TMPD/gpt.txt" "gpt crc mismatch" "beide Pruefsummen stimmen"

    # GEGENPROBE: EIN OKTETT IM GPT-KOPF UMGEDREHT. Die Pruefsumme des
    # Kopfes MUSS anschlagen, und die Platte darf danach NICHT mehr
    # eingehaengt werden. Ohne diese Zeile ist "die Pruefsumme wird
    # gerechnet" eine Behauptung.
    cp "$GPT" "$TMPD/gptbad.img"
    python3 - "$TMPD/gptbad.img" <<'PY'
import sys
f = open(sys.argv[1], "r+b")
f.seek(512 + 40)          # first_usable_lba im GPT-Kopf
b = f.read(1)
f.seek(512 + 40)
f.write(bytes([b[0] ^ 0x01]))
f.close()
PY
    rc=$(lauf gptbad "$TMPD/k0.mb" "$TMPD/root.img" "$TMPD/gptbad.img" \
        "osum nokbd vfs script=cat /mnt/hello.txt")
    hat "$TMPD/gptbad.txt" "part: gpt crc mismatch" \
        "GEGENPROBE: ein umgedrehtes Bit im GPT-Kopf faellt auf"
    hat_nicht "$TMPD/gptbad.txt" "hallo aus linux" \
        "GEGENPROBE: und die Platte wird danach NICHT gelesen"
fi

# GEGENPROBE: OHNE die Partitionstafel wird das Dateisystem bei Block 0
# gesucht -- dort steht die TAFEL. Es MUSS fehlschlagen.
rc=$(lauf nopart "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs nopart script=mount")
hat "$TMPD/nopart.txt" "k14: mounts=3" "GEGENPROBE nopart: nur drei Einhaengungen"
hat_nicht "$TMPD/nopart.txt" "on /mnt type vfat" \
    "GEGENPROBE nopart: ohne Partitionstafel wird kein FAT32 gefunden"

# EIN PROZESS, DER EINE DATEI AUF /mnt OEFFNET UND ENDET, MUSS DIE
# EINHAENGUNG WIEDER FREIGEBEN. Der Zaehler haengt an `open_unref`, und
# ein sterbender Prozess geht durch `file.close_all` -- also an
# `sys.unref_of` VORBEI. Die erste Fassung dieser Runde zaehlte dort,
# und `umount /mnt` sagte danach fuer immer -EBUSY.
rc=$(lauf freigabe "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs script=cat /mnt/hello.txt;mount;umount /mnt;mount")
num "der Freigabelauf beendet sich selbst" "$rc" eq 21
n=$(grep -ac 'on /mnt type vfat' "$TMPD/freigabe.txt")
num "/mnt steht vor dem Aushaengen genau einmal in der Tafel" "$n" eq 1
hat "$TMPD/freigabe.txt" "hallo aus linux" "und der Prozess hat davon wirklich gelesen"

# GEGENPROBE: KEINE ZWEITE PLATTE. Der Kernel muss das sagen und
# weiterlaufen -- eine Maschine ohne zweites Laufwerk ist keine kaputte.
rc=$(lauf keineplatte "$TMPD/k0.mb" "$TMPD/root.img" "" \
    "osum nokbd vfs script=mount")
num "ohne zweite Platte laeuft der Kernel weiter (21)" "$rc" eq 21
hat "$TMPD/keineplatte.txt" "k14: mounts=3" "ohne zweite Platte: drei Einhaengungen"

# ------------------------------------------------ 8. die Gegenproben

echo "== 8. die Gegenproben: ohne die Schicht bricht jede Zusage weg =="
rc=$(lauf novfs "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs novfs script=k14")
num "der novfs-Lauf beendet sich selbst" "$rc" eq 21
hat "$TMPD/novfs.txt" "k14: novfs" "GEGENPROBE novfs: die Schicht meldet sich ab"
hat "$TMPD/novfs.txt" "k14: mounts=1" "GEGENPROBE novfs: nur die Wurzel steht"
sagt "$TMPD/novfs.txt" mount_count 1 "GEGENPROBE novfs: eine Einhaengung"
sagt "$TMPD/novfs.txt" fat_type 0 "GEGENPROBE novfs: kein FAT32"
sagt "$TMPD/novfs.txt" proc_type 0 "GEGENPROBE novfs: kein /proc"
sagt "$TMPD/novfs.txt" dev_type 0 "GEGENPROBE novfs: kein /dev"
sagt "$TMPD/novfs.txt" st_dev_different 0 "GEGENPROBE novfs: keine zweite Platte im Namensraum"
sagt "$TMPD/novfs.txt" hdb_boot_ok 0 "GEGENPROBE novfs: /dev/hdb gibt es nicht"
sagt "$TMPD/novfs.txt" done 1 "und das Messprogramm laeuft trotzdem durch"
# UND OFS FUNKTIONIERT WEITER. Das ist die Zusage "nichts loeschen,
# bevor der Ersatz laeuft".
hat "$TMPD/novfs.txt" "osum: bin" "GEGENPROBE novfs: OFS traegt weiter das Userland"

for w in noprocfs nodevfs nofat; do
    rc=$(lauf "$w" "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
        "osum nokbd vfs $w script=mount")
    hat "$TMPD/$w.txt" "k14: mounts=3" "GEGENPROBE $w: eine Einhaengung weniger"
done
hat_nicht "$TMPD/noprocfs.txt" "on /proc type proc" "GEGENPROBE noprocfs: kein /proc"
hat_nicht "$TMPD/nodevfs.txt" "on /dev type devfs" "GEGENPROBE nodevfs: kein /dev"
hat_nicht "$TMPD/nofat.txt" "on /mnt type vfat" "GEGENPROBE nofat: kein FAT32"

# GEGENPROBE: NUR LESEND EINGEHAENGT. Jeder Schreibversuch -EROFS, und
# die Platte danach unveraendert -- Oktett fuer Oktett.
rc=$(lauf fatro "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs fatro script=mount;echo x > /mnt/darfnicht.txt;mkdir /mnt/auchnicht;rm /mnt/hello.txt;ls /mnt")
hat "$TMPD/fatro.txt" "type vfat (ro)" "GEGENPROBE fatro: nur lesend eingehaengt"
# Nicht im Mitschnitt suchen -- die Shell schreibt den Befehl selbst
# noch einmal hin, und "darfnicht.txt" stuende dort in JEDEM Fall. Die
# Wahrheit steht auf der PLATTE, und `mdir` liest sie.
mdir -i "$TMPD/live2-fatro.img@@1048576" :: > "$TMPD/mdirro.txt" 2>&1
hat_nicht "$TMPD/mdirro.txt" "darfnicht" "GEGENPROBE fatro: die Datei entsteht NICHT"
hat_nicht "$TMPD/mdirro.txt" "auchnicht" "GEGENPROBE fatro: das Verzeichnis entsteht NICHT"
hat "$TMPD/mdirro.txt" "hello" "GEGENPROBE fatro: und die alte Datei ist noch da"
if cmp -s "$MBR" "$TMPD/live2-fatro.img"; then
    ok "GEGENPROBE fatro: die Platte ist Oktett fuer Oktett unveraendert"
else
    bad "GEGENPROBE fatro: die Platte hat sich geaendert"
fi

# ------------------------------ 9. OFS verliert nichts: der zweite Weg

echo "== 9. OFS ist ein NUTZER der Schicht, kein Sonderfall daneben =="
# Dieselbe Arbeit, zweimal: einmal auf dem geraden Weg von Runde 62,
# einmal mit `vfsall` durch die Ops-Tafel. Die Ausgaben muessen OKTETT
# FUER OKTETT gleich sein -- sonst ersetzt der eine Weg den anderen nicht.
ARBEIT="script=ls /bin;mkdir /neu;echo eins > /neu/a.txt;cat /neu/a.txt;cp /neu/a.txt /neu/b.txt;cat /neu/b.txt;ls /neu;rm /neu/a.txt;ls /neu;wc /neu/b.txt;grep eins /neu/b.txt"
rc=$(lauf ofsdirekt "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" "osum nokbd vfs $ARBEIT")
num "der gerade Weg beendet sich selbst" "$rc" eq 21
rc=$(lauf ofsvfs "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" "osum nokbd vfs vfsall $ARBEIT")
num "der Weg ueber die Ops-Tafel beendet sich selbst" "$rc" eq 21
# Nur die Zeilen der SHELL vergleichen: die Zeilen des Laders nennen
# Rahmenadressen, und die duerfen sich unterscheiden.
schnitt() { sed -n '/sh: ready/,/sh: bye/p' "$1" | grep -av '^elf:' | tr -d '\000'; }
schnitt "$TMPD/ofsdirekt.txt" > "$TMPD/a.out"
schnitt "$TMPD/ofsvfs.txt" > "$TMPD/b.out"
dateien_gleich "dieselbe Arbeit auf OFS, beide Wege, Oktett fuer Oktett" \
    "$TMPD/a.out" "$TMPD/b.out"
n=$(wc -l < "$TMPD/a.out")
num "und es war wirklich Arbeit (Zeilen im Vergleich)" "$n" ge 10
# Und die Platten danach: dieselben Oktette auf beiden Wegen.
dateien_gleich "und die Wurzelplatte danach, Oktett fuer Oktett" \
    "$TMPD/live-ofsdirekt.img" "$TMPD/live-ofsvfs.img"
# Der Beweis, dass der zweite Weg wirklich ein anderer war.
o1=$(grep -a -m1 '^k14: mounts=' "$TMPD/ofsdirekt.txt" | grep -oE 'ops=[0-9]+' | grep -oE '[0-9]+')
o2=$(grep -a -m1 '^k14: mounts=' "$TMPD/ofsvfs.txt" | grep -oE 'ops=[0-9]+' | grep -oE '[0-9]+')
if [ "${o2:-0}" -gt "${o1:-0}" ]; then
    ok "mit vfsall gehen mehr Verrichtungen ueber die Tafel ($o1 -> $o2)"
else
    bad "vfsall aendert nichts an der Zahl der Verrichtungen ($o1 -> $o2)"
fi

# ------------------------ 10. /proc gegen den Sonderaufruf von Runde K6

echo "== 10. /proc gegen SYS_OSUM_PSTAT: zwei Wege, dieselben Zahlen =="
# `ps` liest die Aufgabentafel ueber SYS_OSUM_PSTAT (Runde K6, Nummer
# 1003). `cat /proc/<pid>/stat` liest sie ueber das Dateisystem. Die
# beiden MUESSEN dieselben Zahlen sagen -- und solange das nicht
# gemessen ist, wird der Sonderaufruf nicht entfernt.
rc=$(lauf pstat "$TMPD/k0.mb" "$TMPD/root.img" "$MBR" \
    "osum nokbd vfs script=ps;cat /proc/1/stat;cat /proc/2/stat")
num "der Vergleichslauf beendet sich selbst" "$rc" eq 21
P="$TMPD/pstat.txt"
sed -n '/sh: ready/,$p' "$P" | tr -d '\000\r' > "$TMPD/pstat.clean"
for pid in 1 2; do
    psline=$(grep -aE "^ +$pid +[0-9]+ " "$TMPD/pstat.clean" | head -1)
    procline=$(grep -aE "^$pid \(" "$TMPD/pstat.clean" | head -1)
    if [ -n "$psline" ] && [ -n "$procline" ]; then
        ps_pid=$(echo "$psline" | awk '{print $1}')
        ps_ppid=$(echo "$psline" | awk '{print $2}')
        pr_pid=$(echo "$procline" | awk '{print $1}')
        pr_ppid=$(echo "$procline" | awk '{print $4}')
        gleich "Aufgabe $pid: dieselbe Pid in ps und in /proc/$pid/stat" \
            "$ps_pid" "$pr_pid"
        gleich "Aufgabe $pid: dieselbe Eltern-Pid in beiden" "$ps_ppid" "$pr_ppid"
    else
        bad "der Vergleich ps <-> /proc/$pid/stat: eine der beiden Zeilen fehlt"
    fi
done
hat "$TMPD/pstat.clean" "boot" "/proc/1/stat nennt die Art der Aufgabe"

# ------------------------------------------------------------ das Ergebnis

echo
if [ "$fail" -eq 0 ]; then
    echo "K14: $pass passed, 0 failed"
    exit 0
else
    echo "K14: $pass passed, $fail failed"
    exit 1
fi
