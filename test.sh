#!/usr/bin/env bash
#
set -uo pipefail

cd "$(dirname "$0")"
ROOT=$(pwd)
WORK="${OSUM_WORK:-$ROOT/.test-work}"
mkdir -p "$WORK"

export FIRNLIB="$ROOT/lib"

# ======================================================================
# RUNDE TESTFAST -- DIE ABSCHNITTE LAUFEN GLEICHZEITIG.
#

JOBS=${OSUM_JOBS:-$(( $(nproc 2>/dev/null || echo 2) / 2 ))}
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1
ZEIT=${OSUM_ZEIT:-1}

NUR=${OSUM_NUR:-}

SERIELL_RE='^tools/(net|netmon|netview|tunnel|hwnet|rtl)/'
NETZSPERRE=${OSUM_NETZSPERRE:-/tmp/osum-netz.lock}
: > "$NETZSPERRE" 2>/dev/null || NETZSPERRE="$WORK/.netz.lock"
: > "$NETZSPERRE"

PASS=0
FAIL=0
FAILED=""
ZUSAGEN=0
UEBERSPRUNGEN=0

A_TITEL=(); A_SKRIPT=(); A_NAME=(); A_MUSTER=()

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  $1"; echo "  FEHLER  $1"; }

zusagen() {
    local log=$1
    local n
    n=$(grep -aoE '^[A-Z][A-Z0-9]*: [0-9]+ (passed|proofs|bestanden|Zusagen)' "$log" | tail -1 | grep -oE '[0-9]+' | tail -1)
    [ -n "${n:-}" ] && ZUSAGEN=$((ZUSAGEN + n))
}

abschnitt_ausfuehren() { # index
    local i=$1
    local skript=${A_SKRIPT[$i]} name=${A_NAME[$i]}
    local rc=0 s e
    rm -f "$WORK/.netto.$i"
    s=$(date +%s%N)
    if [[ "$skript" =~ $SERIELL_RE ]]; then
        flock "$NETZSPERRE" bash -c '
            ns=$(date +%s%N)
            bash "$1" > "$2" 2>&1; r=$?
            ne=$(date +%s%N)
            printf "%s\n" "$(( (ne - ns) / 1000000 ))" > "$3"
            exit $r' _ "$skript" "$WORK/$name.log" "$WORK/.netto.$i" || rc=$?
    else
        bash "$skript" > "$WORK/$name.log" 2>&1 || rc=$?
    fi
    e=$(date +%s%N)
    printf '%s\n' "$rc"                > "$WORK/.rc.$i"
    printf '%s\n' "$(( (e - s) / 1000000 ))" > "$WORK/.ms.$i"
    : > "$WORK/.done.$i"
}

abschnitt_ausgeben() { # index
    local i=$1
    local titel=${A_TITEL[$i]} skript=${A_SKRIPT[$i]}
    local name=${A_NAME[$i]} muster=${A_MUSTER[$i]}
    local rc ms
    rc=$(cat "$WORK/.rc.$i" 2>/dev/null || echo 1)
    ms=$(cat "$WORK/.ms.$i" 2>/dev/null || echo 0)
    [ "${2:-}" = "kopf_schon_da" ] || echo "== $titel =="
    grep -aE "$muster" "$WORK/$name.log" | sed 's/^ */   /'
    zusagen "$WORK/$name.log"
    if [ "$rc" -eq 0 ]; then
        ok
    else
        bad "$skript ist fehlgeschlagen (siehe .test-work/$name.log)"
        grep -aE '^  FAIL' "$WORK/$name.log" | head -12 | sed 's/^/     /'
    fi
    if [ "$ZEIT" = "1" ]; then
        local netto="" nms
        if [ -f "$WORK/.netto.$i" ]; then
            nms=$(cat "$WORK/.netto.$i")
            if [ $((ms - nms)) -gt 1000 ]; then
                netto=$(printf '  (davon %d,%03d s Warten auf die Netzsperre)' \
                        "$(( (ms - nms) / 1000 ))" "$(( (ms - nms) % 1000 ))")
            fi
        fi
        printf '   [%s  %d,%03d s  %s]%s\n' \
            "$(grep -am1 '^accel: ' "$WORK/$name.log" | sed 's/^accel: //;s/ (.*//' || true)" \
            "$(( ms / 1000 ))" "$(( ms % 1000 ))" "$name" "$netto"
    fi
}

lauf() { # titel skript logname muster
    if [ "${ABGEARBEITET:-0}" = "1" ]; then
        echo "FEHLER: '$3' wird NACH abschnitte_abarbeiten angemeldet und" >&2
        echo "        wuerde damit nie laufen. Den lauf-Aufruf VOR die" >&2
        echo "        Zeile 'abschnitte_abarbeiten' stellen." >&2
        exit 2
    fi
    if [ -n "$NUR" ] && ! printf '%s' "$3" | grep -qE "$NUR"; then
        UEBERSPRUNGEN=$((UEBERSPRUNGEN + 1))
        return 0
    fi
    local i=${#A_SKRIPT[@]}
    A_TITEL+=("$1"); A_SKRIPT+=("$2"); A_NAME+=("$3"); A_MUSTER+=("$4")
    if [ "$JOBS" -le 1 ]; then
        echo "== $1 =="
        abschnitt_ausfuehren "$i"
        abschnitt_ausgeben "$i" kopf_schon_da
    fi
}

abschnitte_abarbeiten() {
    local n=${#A_SKRIPT[@]} i
    [ "$JOBS" -le 1 ] && return 0
    [ "$n" -gt 0 ] || return 0

    echo "-- $n Abschnitte, $JOBS gleichzeitig" \
         "(OSUM_JOBS=1 fuer den alten seriellen Lauf) --"
    echo

    rm -f "$WORK"/.done.* "$WORK"/.rc.* "$WORK"/.ms.* "$WORK"/.netto.*

    (
        for ((i = 0; i < n; i++)); do
            while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
                wait -n 2>/dev/null || break
            done
            abschnitt_ausfuehren "$i" &
        done
        wait
    ) &
    local verteiler=$!

    for ((i = 0; i < n; i++)); do
        while [ ! -f "$WORK/.done.$i" ]; do
            if ! kill -0 "$verteiler" 2>/dev/null; then
                sleep 0.3
                [ -f "$WORK/.done.$i" ] || break
            fi
            sleep 0.2
        done
        abschnitt_ausgeben "$i"
    done
    wait "$verteiler" 2>/dev/null || true

    if [ "$ZEIT" = "1" ]; then
        echo
        echo "-- Zeit je Abschnitt, laengster zuerst --"
        for ((i = 0; i < n; i++)); do
            printf '%8d %s %s\n' "$(cat "$WORK/.ms.$i" 2>/dev/null || echo 0)" \
                "$(grep -am1 '^accel: ' "$WORK/${A_NAME[$i]}.log" 2>/dev/null | sed 's/^accel: //;s/ (.*//' || echo '?')" \
                "${A_NAME[$i]}"
        done | sort -rn | awk '{printf "   %6d,%03d s  %-5s %s\n", $1/1000, $1%1000, $2, $3}'
    fi
}

echo "== 1. der festgenagelte Uebersetzer (vendor/firn/COMMIT) =="
COMMIT=$(cat vendor/firn/COMMIT)
S1=""
bash vendor/firn/fetch-firnc.sh > "$WORK/vendor.log" 2>&1 || \
    S1="$S1 fetch-firnc.sh fehlgeschlagen (siehe .test-work/vendor.log);"
[ -x vendor/firn/bin/firnc ]  || S1="$S1 vendor/firn/bin/firnc fehlt;"
[ -x vendor/firn/bin/firnc1 ] || S1="$S1 vendor/firn/bin/firnc1 fehlt;"
[ -d vendor/firn/lib/std ]    || S1="$S1 vendor/firn/lib/std fehlt;"
#
#     a751b3db...  b229d84c0efbe8b6
#     ^ Commit     ^ sha256 der Flicken in vendor/firn/patches/
#
GEB_C=$(cut -d' ' -f1 vendor/firn/.gebaut 2>/dev/null)
GEB_P=$(cut -d' ' -f2 vendor/firn/.gebaut 2>/dev/null)
PSUM_SOLL=$( { cat vendor/firn/patches/*.patch 2>/dev/null || true; } \
             | sha256sum | cut -c1-16)
[ -f vendor/firn/.gebaut ] || S1="$S1 vendor/firn/.gebaut fehlt;"
[ "$GEB_C" = "$COMMIT" ] || \
    S1="$S1 vendor/firn/.gebaut: Commit $GEB_C statt $COMMIT;"
[ "$GEB_P" = "$PSUM_SOLL" ] || \
    S1="$S1 vendor/firn/.gebaut: Flicken $GEB_P statt $PSUM_SOLL;"
while read -r want name; do
    case "$want" in \#*|"") continue;; esac
    roh="vendor/firn/lib/.roh/$name"
    [ -f "$roh" ] || roh="vendor/firn/lib/$name"
    got=$(git hash-object "$roh" 2>/dev/null)
    [ "$got" = "$want" ] || S1="$S1 $roh: $got statt $want;"
done < vendor/net/BLOBS
[ -d lib/net ] && S1="$S1 im Repo liegt eine Kopie des Stacks unter lib/net;"
{ [ -e compiler ] || [ -e bin/firnc1.fi ]; } && \
    S1="$S1 im Repo liegt ein Uebersetzer -- er gehoert nach vendor/;"
ZUSAGEN=$((ZUSAGEN + 9))
if [ -z "$S1" ]; then
    echo "   Firn ${COMMIT:0:8}, firnc0 + firnc1 gebaut, lib/std daneben,"
    echo "   lib/net/ mit den drei Blob-Hashes aus vendor/net/BLOBS (9 Zusagen)"
    ok
else
    bad "der festgenagelte Uebersetzer:$S1"
    tail -5 "$WORK/vendor.log" | sed 's/^/     /'
fi

lauf "2. freistehend uebersetzen: profile kernel, Inline-Assembler, MMIO, iretq (tools/freestanding/run.sh)" \
     tools/freestanding/run.sh freestanding '^FREESTANDING: '

lauf "3. std.core im Kernel: die Bibliothek ohne Allokator (tools/core/run.sh, Runde 73)" \
     tools/core/run.sh core '^CORE: '

lauf "4. der Kern laeuft: Aufgaben, Adressraeume, Systemaufrufe, Dateien (tools/kernel/run.sh, Runden 59/62)" \
     tools/kernel/run.sh kernel '^KERNEL: '

lauf "5. ein Programm von der Platte: ELF-Lader, exec, /bin/sh (tools/osum/run.sh, Runde K1)" \
     tools/osum/run.sh osum '^OSUM:|deepest|biggest program|refusals in one run'

lauf "6. der Kernel liest seine Maschine: PCI, APIC, NVMe ueber DMA (tools/pci/run.sh, Runde K2)" \
     tools/pci/run.sh pci '^PCI: |^        bench: '

lauf "7. die POSIX-Schicht und die libc (tools/posix/run.sh, Runde K4)" \
     tools/posix/run.sh posix '^POSIX:|^   -- '

lauf "8. vier Prozessoren, und die Sperre, die einen Kernel daraus macht (tools/smp/run.sh, Runde K5)" \
     tools/smp/run.sh smp '^SMP: |^        (one core|four cores|speed-up|one host thread|with the lock)'

lauf "9. ein Userland: eine Shell, 25 Werkzeuge, Roehren und Umlenkung (tools/userland/run.sh, Runde K6)" \
     tools/userland/run.sh userland '^USERLAND:|the whole userland in octets|the biggest program|programs loaded off the disk'

lauf "10. Handles statt Umgebungsautoritaet: die Capability-Schicht aus Osum (tools/caps/run.sh)" \
     tools/caps/run.sh caps '^CAPS: |^        \(\.utext'

lauf "10b. die Lebensdauer vor der Asynchronitaet: Handles mit Verweiszaehler, Generation und Abbruch-Token (tools/handle/run.sh, Runde HANDLE)" \
     tools/handle/run.sh handle '^HANDLE: |^  ZAHL '

lauf "10c. die asynchrone Auftragsschicht: ein Auftrag lebt laenger als sein Systemaufruf (tools/async/run.sh, Runde ASYNC)" \
     tools/async/run.sh async '^ASYNC: |^        (TSC |  synchron|  asynchron|  nur die Abgabe|  Speicher je Auftrag)'

lauf "11. der Multiboot-Kopf verlangt einen Bildschirm -- der UEFI-Pfad (tools/boot/run.sh)" \
     tools/boot/run.sh boot '^BOOT: '

lauf "12. der Bildschirm: Rahmenpuffer, Textkonsole, /dev/fb (tools/gfx/run.sh, Runde K7)" \
     tools/gfx/run.sh gfx '^GFX: |^   fbbench: '

lauf "13. was jedes Unix-Programm voraussetzt: Signale, Terminal, Uhr, Zufall (tools/unix/run.sh, Runde K9)" \
     tools/unix/run.sh unix '^UNIX: |^   -- '

lauf "14. das Netz: virtio-net, der Stack aus K3, Steckdosen -- gegen den Linux-Kern (tools/net/run.sh)" \
     tools/net/run.sh net '^NET:|^  OK    (throughput|round trip|what came back|and on three)'

lauf "15. die Schutzbits und das Boot-Modul: SMEP, SMAP, CRC32 (tools/guard/run.sh, Runde K10)" \
     tools/guard/run.sh guard '^GUARD: |^  OK    (das SMAP-Fenster|und alle drei weiteren|nach einem Lauf)'

# ABSCHNITT 15b -- RUNDE AVX, ANGEMELDET VON RUNDE MERGE-5.
#
lauf "15b. die Vektoreinheit fuer Ring 3: XSAVE im Kontextwechsel (tools/avx/run.sh, Runde AVX)" \
     tools/avx/run.sh avx '^AVX: |^  OK    (Vektoranweisungen|CR4 traegt|der Kern nimmt|XCR0|der Sicherungsbereich|mit nofpu|Abweichungen|kein Prozess|gemessene Breite|Prozesse mit|fork erbt|der Wechsel|GEGENPROBE|Kerne, die|sechs Kernaufgaben|und die gemessene|diese Maschine|die Maschine bietet)'

lauf "16. man kann darauf arbeiten: ein Editor, zwanzig Werkzeuge, eine Shell mit Sprache (tools/k11/run.sh, Runde K11)" \
     tools/k11/run.sh k11 '^K11: |^  OK    (DIE GESICHERTE|EINE DATEI|AUF DEM BILDSCHIRM|GNU )'

lauf "17. die Oberflaeche: Maus, Fensterserver, TrueType (tools/wm/run.sh, Runde K10)" \
     tools/wm/run.sh wm '^WM: |^   wmbench: |^        im Regellauf|^        ohne Bereichsverfolgung'

lauf "18. ein Wirt fuer fremde Prozessoren: AMD-V, verschachtelte Seitentabellen, Gaeste (tools/hv/run.sh, Runde K12)" \
     tools/hv/run.sh hv '^HV:|^        (bench|exits|cpu):'

lauf "19. Benutzer, Rechte und der erste Prozess: uid/gid, chmod/chown, login, init (tools/k13/run.sh, Runde K13)" \
     tools/k13/run.sh k13 '^K13: |^  OK    (DIE (KENNUNG|WAISE)|GEGENPROBE|PYTHON|das Passwort steht NICHT|die Maschine (schaltet|faehrt)|DER NOTWEG)'
lauf "20. die VFS-Schicht und die fremden Dateisysteme: /proc, /dev, FAT32, MBR und GPT (tools/k14/run.sh, Runde K14)" \
     tools/k14/run.sh k14 '^K14: |^  OK    (vier Dateisysteme|blob.bin|kopie.bin|fsck.fat|dieselbe Arbeit|GEGENPROBE novfs: nur|GEGENPROBE nopart)'

lauf "21. der Uebersetzer laeuft auf dem System selbst, und eine Datei weiss, womit man sie oeffnet (tools/k16/run.sh, Runde K16)" \
     tools/k16/run.sh k16 '^K16: |^  OK    (ZEICHENGLEICH|DAS AUF OSUM|DER DOPPELKLICK|DER AUSLEGER|DER INHALT GEHT VOR|fas uebersetzt|16 von 16)'
lauf "22. Widgets und der Dateimanager: eine Bibliothek in Ring 3 (tools/k15/run.sh, Runde K15)" \
     tools/k15/run.sh k15 '^K15: |^        -> |^  OK    (die Anordnung|ein Klick auf das Kaestchen|mit Bereichsverfolgung|und /data/neu|der Verweis spart|getippt |OHNE (die Schluesselwoerter|das Journal|den Namensindex)|[0-9]\. (DER AUFBAU|DIE SUCHE|DIE GEGENPROBE|der Index)|und DIESELBEN NAMEN|nach dem (Anlegen|Umbenennen)|das Symbol des Dateimanagers)'
lauf "25. der Fensterbaum: Kacheln, Reiter, Drehen -- und die Invariante nach jeder Operation (tools/tiling/run.sh, Runde TILING)" \
     tools/tiling/run.sh tiling '^TILING: |^  OK    (die Zusagen des Fensterbaums|und KEINE davon|Verletzungen der Invariante|und nach JEDER Operation|GEGENPROBE|Fenster [0-9] |und im Bild|vier Reiter|nach der Drehung|der Aufwand waechst|und das spart|Kern und Ring 3)'
lauf "24. Energie und Leistung: drei Profile, Ruhezustand, Waerme, Akku (tools/k18/run.sh, Runde K18)" \
     tools/k18/run.sh k18 '^K18: |^  OK    (dieselbe Stelle|IA32_PERF_CTL bekommt|Turbo ist bei|SpeedStep ist bei|jeder Durchlauf ging|schlafend |aber es wird kein|zwei Tabellen|GEGENPROBE|GEDROSSELT|im BILD|dasselbe Pruefbild|und einen Bildpunkt DANEBEN|keine AUFRUFNUMMER)'
lauf "25. die zweite Maschine: AArch64 auf qemu -M virt (tools/arm/run.sh, Runde ARM)" \
     tools/arm/run.sh arm '^ARM: |^  OK    (der erste|the first|100 virtual|arch_switch|nomm:|noaf:|notimer:|noeoi:|32 virtio|with a disk|a page mapped|the same octet|SCTLR|CNTFRQ)|^   (first octet|to the last line)'

lauf "23. USB: xHCI, Aufzaehlung, Tastatur, Maus und ein Stick (tools/k17/run.sh, Runde K17)" \
     tools/k17/run.sh k17 '^K17: |^  OK    (DIESELBEN ZEICHEN|DIESELBE SHELL|WAS OSUM SCHRIEB|die Tastatur, an Klasse|die Maus, an Klasse|der Stick, an Klasse|der Zeiger steht|GEGENPROBE usbnoirq|lesen auf dem OFFENEN)'

lauf "26. Der Bildschirm, zum zweiten Mal: Modusliste, Wechsel im Betrieb, EDID, Gamma (tools/display/run.sh, Runde DISPLAY)" \
     tools/display/run.sh display '^DISPLAY: |^  OK    (gefragt |die native |der rohe Block|er hat [0-9]+ Mikro|gemessen: |je Bildpunkt|NACHHER|VORHER|ZURUECK|Feld 1 ist rot|das Foto ist 800x600 -- der Bildmodus|und der Kernel hat von SELBST|die Aufrufnummern dieser Runde|ein Programm in Ring 3 hat)'

lauf "28. Eigene Aufloesungen: drei Schranken mit ihrer Zahl, eine Frist ohne Zutun, ein Modus ueber den Neustart (tools/customres/run.sh, Runde CUSTOMRES)" \
     tools/customres/run.sh customres '^CUSTOMRES: |^  OK    (1400x1050 steht in KEINER|das Foto ist 1400x1050|die genannte Zahl ist GENAU|und es steht da, was die Karte|und JETZT ist der Bildspeicher|eine Begruendung, die sich|nach 22 Sekunden Schlaf|der Kernel hat von SELBST|der Kernel findet den Modus|jetzt sind die drei Versuche|die Tafel steht auf dem SICHEREN|3840x2160 scheitert jetzt|mit 16 MiB war es noch|die Belegung der acht|zehn Zusagen ueber die|und die neun eigenen)'

lauf "27. Marken statt Farben: hell, dunkel, automatisch, und der Kontrast nachgerechnet (tests/theme/run.sh, Runde THEME)" \
     tests/theme/run.sh theme '^THEME: |^  OK    (rohe Farbwerte|derselbe Pruefer|alle 256|groesster Abstand|[a-z]+/(light|dark): (41|23|21|jede)|#[0-9a-f]+ hell|die Farbe bleibt|GEGENPROBE|aufloesen |nachsehen |vollstaendig |erkennen, |neu malen, |das Umschalten|[a-z]+: die (haeufigste|aufgeloeste)|[a-z]+: surface [(]#[0-9a-f]+[)] traegt|[a-z]+: surface #[0-9a-f]+ und surface-sunken|[a-z]+: surface und surface-sunken sind beide|ohne /etc/theme.conf|und die eingebaute|aus der kaputten|und 4 werden|was die Datei)'

lauf "25. das Symbolsystem: eine Schrift fuer die Oberflaeche, Bitmaps fuer die Anwendungen (tools/icons/run.sh, Runde ICONS)" \
     tools/icons/run.sh icons '^icons: |^  OK    (assets/osum-icons.ttf|lib/icons.fi|raw code points|counterproof|the kernel loaded|the kernel says|and Ring 3 sees|assertions|an icon in memory|screenshot)|^        (per mixed pixel|one icon cold|in memory:|both mix)'
lauf "26. die Mischung, die Kante, der Schatten und das Symbol -- jedes mit seinem Preis (tools/paint/run.sh, Runde PAINT)" \
     tools/paint/run.sh paint '^PAINT: |^ *OK    (abschneiden|\(num|Kern und Wirt|a=0 laesst|alle 5 Fundstellen|[0-9]+x[0-9]+: |dieselbe Rechnung nativ|fb\.selftest3|und der Zaehler|jedes Zeichen|jede Kante|dasselbe Zeichen wie FreeType|4x4 liegt|keine zwei Skalare|Aufrufnummer|und 2116|kernel/.* numeriert|der Satz von WM_LIST|und der Buendelname|shape=|[0-9]+ Bildpunkte sind dunkler|der Unterschied faellt|er endet nach|die runde Ecke|GEGENPROBE|[0-9]+ Symbole|die Taskleiste hat)'

lauf "25. eine Netzsicht je Prozess: real, filtered, faked, none (tools/netview/run.sh, Runde NETVIEW)" \
     tools/netview/run.sh netview '^NETVIEW: |^  OK    (OCTETS THAT LEFT|faked: (connect|reading|the WHOLE|the BODY|a name resolved|and the reachability)|none: (connect|and it said)|real: connect took|and the python server|(nocarrier|noip|noroute|online): the icon|(dark|light): (button|and the REAL)|kernel/netmark|8[a-f]:|faking:)'

# =====================================================================
lauf "26. wer wieviel verbraucht, und die Verbindung weiterreichen (tools/netmon/run.sh, Runde NETMON)" \
     tools/netmon/run.sh netmon '^NETMON: |^  OK    (what the KERNEL counted|the counting is|one frame, cache hit|wget/ping ratio|and the SECOND roll|addresses in the history|the client got an OFFER|echo replies from|files fetched over HTTP|NAT records made)'

lauf "25. der Tunnel: WireGuard, AmneziaWG, SOCKS5 und Tor (tools/tunnel/run.sh, Runde TUNNEL)" \
     tools/tunnel/run.sh tunnel '^  OK    ([0-9]+ vectors|all [0-9]+|X25519 in the kernel|the Linux kernel completed|Linux pinged|KILL SWITCH|counter-check)|^     .*(all passed|ok   [0-9]+ of|rtt )'

lauf "26. der Tunnel als PAKET: was er kostet, wenn keiner laeuft (tools/tunnel/kosten.sh, Nachtrag TUNNEL)" \
     tools/tunnel/kosten.sh tunnelkosten '^  OK    (der Tunnel kostet|ein EINGERICHTETER|der Haken)'
lauf "27. installieren, benutzen, entfernen -- und nichts bleibt (tools/tunnel/pakete.sh, Nachtrag TUNNEL)" \
     tools/tunnel/pakete.sh tunnelpakete '^  OK    (SPURLOS|zweimal gebaut|GEGENPROBE|das Paket .bleibt.|mit --behalte-daten)'
lauf "25. Diebstahl: Geraeteidentitaet, Sicherung, Schluesselverwaltung (tools/vault/run.sh, Runde TRESOR)" \
     tools/vault/run.sh tresor '^TRESOR: |^  OK    (SMBIOS |SHA-256 |PBKDF2|DER ZWEITE LAUF|der wiederhergestellte Baum|ACHT OKTETTE|im beschaedigten|GEGENPROBE|eine (NEUE PLATTE|ANDERE Maschine)|der Fingerabdruck ist|die Seriennummer des Laufwerks|crypto erase|open mit dem richtigen|1000 Oktette|bei 0xF1031|und seine Pruefsumme|PREIS DER AUSNAHME|MIT Liste sichert|DAS WIEDERHERGESTELLTE PAKET|das verwaiste Paket ist OKTETT|ZWEITER LAUF SCHREIBT NULL|GESCHRIEBEN nur|FAKTOR der kleinen|kein halbes Backup)'
lauf "28. dieselbe Abnahme auf zwei Chips: virtio-net und e1000 (tools/hwnet/run.sh, Runde HWNET)" \
     tools/hwnet/run.sh hwnet '^HWNET: |^   [a-z0-9-]+ +[0-9]+|^  OK    (firnc[01]|k.o:|e1000.fi|tools/net/bridge.c|virtio-net-pci|e1000|the unknown card|and the kernel says|no driver claimed)'
lauf "29. HTTPS aus Ring 3, und die Verweigerungen (tools/hwnet/tls.sh, Runde HWNET)" \
     tools/hwnet/tls.sh hwnettls '^HWNETTLS: |^   SKIPPED|^  OK    (firnc --profile=app|not one undefined|ld with|the program on the disk|  \(that is|the test certificates|good/ca|expired/ca|wrong/ca|rogue/ca|good/empty|the trust store|[a-z0-9.]+: (the chain|certificates in|octets of|THE SAME OCTETS))'

lauf "25. Akkuanalyse je Programm: die gemessene Gesamtleistung, anteilig zugeordnet (tools/powermon/run.sh, Runde POWERMON)" \
     tools/powermon/run.sh powermon '^POWERMON: |^        |^  OK    (another table|GEGENPROBE|the two displays|the same energy|the sum of the program|and the kernel.s own rows|the shares add up|the ageing|runtime left|one sample costs|counted and uncounted|at 10 samples|the file stays|AND THE SENTENCE|ON THIS HOST|wigapp= really|the window server counts|distinct colours)'
lauf "29. auf zwei Dinge gleichzeitig warten: poll (tools/poll/run.sh, Runde POLL)" \
     tools/poll/run.sh poll '^POLL: |^  OK    (poll meldet GENAU|und es ist POLL|Verhaeltnis Warteschleife|Systemaufrufe im ganzen|dieselben 1,2 s|poll\(|die Antwort des Helfers|Durchlaeufe der einen|beide Quellen)|^        (poll: |um den es geht|Laufzeit dieses)'

lauf "28. derselbe Kernel auf der ECHTEN CPU: /dev/kvm statt Emulation (tools/kvm/run.sh, Runde KVMFIX)" tools/kvm/run.sh kvm '^KVM: |^  OK    (der Kernel ist gebaut|1\.|3\.|4\.)|^  --    (CPU|3\.|4\.)|^KVM: uebersprungen'
lauf "29. die Platte, die ein echter PC hat: AHCI/SATA ueber DMA (tools/ahci/run.sh, Runde AHCI)" \
     tools/ahci/run.sh ahci '^AHCI: |^  --    Beschleuniger|^  OK    (die Speicherkarte|1\.[2-7]|2\.|3\.|4\.|5\.[2-4]|6\.[2-3]|7\.[2-9]|7\.10|8\.[2-5])'

lauf "30. Osum als Server: ohne Grafik gebaut, auf der seriellen Leitung bedient (tools/server/run.sh, Runde SERVERBUILD)" \
     tools/server/run.sh server '^SERVER: |^        (gui=|Symbole der|srvbench: )|^  OK    (das Serverabbild|im Serverabbild|die Naht selbst|kein Modul|die Shell antwortet|Rueckschritt und|GEGENPROBE|und der Zaehler|im Regellauf|empfangene|kein Oktett|STRG-U)'

lauf "31. die Sprache der Firmware: ein AML-Interpreter, _PRT statt Register 0x3C (tools/aml/run.sh, Runde AML)" \
     tools/aml/run.sh aml '^AML: |^    (DSDT parsen|_PRT auswerten|Namensraum|Arena benutzt|Kernstapel|Verschachtelung|Zeilen Quelltext|Bootzeit|Abdeckung|in der Tabelle|davon unterstuetzt)|^  OK    (MIT der Leitung|mit der FALSCHEN|die NAMEN stimmen|_PRT und das Register|00:03.0 Stift A|der Rueckfall|die Schrittgrenze|die Tiefengrenze|nach dem Verwerfen|die Abdeckung)'

lauf "29. Mehrbenutzerbetrieb: Pfadrechte, Zusatzgruppen, Kostenfaktor, Anmeldung (tools/multiuser/run.sh, Runde MULTIUSER)" \
     tools/multiuser/run.sh multiuser '^MULTIUSER: |^  --    (gemessen|daraus|/dev/kvm|kein /dev/kvm)|^  OK    (JUSTIN|GEGENPROBE|EINE Pruefung|viermal|und braucht dort|setuid\(0\)|setgroups als|der Kern hat|und [0-9]+ davon|[0-9]+ Zugriffe|[0-9]+ Rechtefragen|nach dem (ersten|zweiten|dritten)|und die Uhr|mit verzoegerung|und der Lauf ist|keine Zwischendatei|der neue Eintrag|das Passwort steht NICHT|PYTHON rechnet|justin liest sie NICHT|und die EINE Ebene|MIT den Zusatzgruppen|id nennt sie)'
lauf "29. der erste Prozess, servertauglich: /bin/init, die Grenze fuer abstuerzende Dienste, Ziele, shutdown und ein ECHTER Neustart (tools/init/run.sh, Runde INIT)" \
     tools/init/run.sh init '^INIT: |^  OK    (Beschleunigung|init schaltet|er wurde GENAU|und fuenf Rueckfaelle|der Dienst .sauber|.sauber. wurde NICHT|der Kernel kam|und der Kern hat wirklich|GEGENPROBE|DER NOTWEG|DIE WAISE|ein Dienst mit respawn|svc list|svc start|JETZT laeuft|die Zeile des Dienstes|der Dienst mit .netz|eine Zeile .name|init liest|und am Ende steht)'

ABGEARBEITET=0
#
lauf "29. der Stromausfall: das Journal von OFS, /bin/fsck und die Grenzen (tools/fsrobust/run.sh, Runde FSROBUST)" \
     tools/fsrobust/run.sh fsrobust '^FSROBUST: |^  OK    (BESCHAEDIGTE FAELLE|ohne Journal treten|groesste Datei|EIN Block weiter|kaputte Abbilder|Laeufe, die danach|die Bestaetigung ist|fsck -r hat|nach der Reparatur|alle Eintraege|und der LETZTE Name|zweimal gebaut|eine Platte OHNE Journal|der Journalbereich liegt)'
lauf "30. Auto-Update: Ed25519, Signaturpflicht, A/B-Boot (tools/update/run.sh, Runde UPDATE)" \
     tools/update/run.sh update '^UPDATE: |^        [a-z0-9]|^  OK    (all [0-9]+ checks|tools/update/oracle.fi|das signierte Paket|und installiert|die Liste nennt|GEGENPROBE|die SIGNATUR schlaegt|DER PUNKT DER RUNDE|und die alte, laufende|Start [123]|Ausgangslage|das kaputte Update|Generation 1 steht|beim naechsten Start|es wird nie|holen ->|Neustart ->|-> Erfolgsvermerk)'

lauf "31. der Chip, den ein echtes Brett hat: Realtek 8168/8169 und der PCH-Zweig fuer I219 (tools/rtl/run.sh, Runde RTL)" \
     tools/rtl/run.sh rtl '^RTL: |^   [a-z0-9-]+ +[0-9]+|^  OK    (firnc[01]|k.o:|r8169.fi|tools/net/bridge.c|10EC|8086|1AF4|14E4|GEGENPROBE|eine Nummer|und fuer die|die PCI-Durchmusterung|netdev waehlt|die Ethernet-Adresse|die unbekannte Karte|und der Kern sagt|kein Treiber hat|rtl8139:|RINGUEBERLAUF|GROESSER ALS MTU|der C\+-Modus|der Empfangsfilter|der Chip wurde|der Empfangs- und|die Selbstpruefung|und danach redet|vorher:|Kabel|und der Treiber meldet|virtio-net-pci:|e1000:)'

lauf "30. der Fernzugang: SSH-2 gegen den echten OpenSSH-Klienten (tools/sshd/run.sh, Runde SSHD)" \
     tools/sshd/run.sh sshd '^SSHD: |^  OK    (tools/sshd/oracle|[0-9]+ Vergleiche|der Dienst lauscht|es gab noch keinen|sshd nennt|ssh-keyscan|ssh-keygen|und der Schluesseltyp|ssh mit (Schluessel|Passwort)|die Ausgabe|\.\.\.Zeile|und der Server hat es|der Klient sagt|strict kex|auch root|ssh gibt den|der SHA-256|die Shell|es war wirklich|die Sitzung am|die Zeilenenden|und die Rohr-Sitzung|die (erste|zweite) Sitzung|und beide haben|ein (FREMDER|falsches|unbekannter|Klient)|und der Befehl ist nicht|ein Name, den|.svc shutdown.|kein einziger|derselbe (Fingerabdruck|Schluessel)|und hat KEINEN|das Passwort geht|die Uebertragung|Zahl der Starts|angenommene Verbindungen|die groesste Zahl)|^        (SHA-256:|HMAC|mpint|Base64|Ableitung|chacha20|Gegenprobe|Auffuellung|Klartext|name-list|eine LEERE|[0-9]+ Oktette in|[0-9]+ ms fuer|langsamster|sshd running|/sbin/sshd:)'

lauf "31. ein Abbild fuer echtes Blech: BIOS und UEFI, Diagnose, deutscher Schreibtisch (tools/usbimg/run.sh, Runde USBIMG)" \
     tools/usbimg/run.sh usbimg '^USBIMG: |^ +(kern|programme|symbole|wurzel|geprueft|umlaute) +[0-9]'

lauf "29. echte Umlaute ueberall, wo Text auf dem Schirm steht (tools/umlaut/run.sh, Runde UMLAUT2)" \
     tools/umlaut/run.sh umlaut '^UMLAUT2: |^     (translit|quellen|marken|spalten|puffer|schriftprobe|Beschleuniger)|^  OK    (SICHTBARE|Umschrift in|GEGENPROBE|GEGEN-GEGENPROBE|keys=|der Pruefer findet|Marken mit|Beschriftungen|Zeichenketten passen|verschiedene Zeichen|passwd zaehlt|die Einstellungen zaehlen|die Zeile steht|starter:|einstellungen:|speicher:|der Speicher-Dialog|die Spalte|\[)'

lauf "32. der Vorlagenladen: zehn Erscheinungen, gemessen statt angeschaut (tools/themestore/run.sh, Runde THEMESTORE)" \
     tools/themestore/run.sh themestore '^THEMESTORE: |^  OK    (alle zehn|die zehn Vorlagen|dieselben Kontraste|keine Vorlage|der Kontrast|anwenden|die ausgegebene Datei|sie traegt|und die Kante|das Konto|die Seite|ein Bild je|und in keiner)'

lauf "33. die weiche Oberflaeche: Schatten, Knoepfe, Fokus, Kontrast (tools/softui/run.sh, Runde SOFTUI)" \
     tools/softui/run.sh softui '^SOFTUI: |^   (OK|--) +(classic|Marken|ctrl_h|Formwoerter|und die Datei|der Schatten|Maske|Ringe|ohne Schatten|die drei|der rote|hover|Fokus|Kontrast|kein Bild|Abschnitt A|[0-9]+ Beanstandungen)'

# ABSCHNITT 34 -- RUNDE OTA, ANGEMELDET VON RUNDE MERGE-5.
#
lauf "34. das Update ueber das Netz: signiertes VERZEICHNIS, Rueckschritt, Wiederaufnahme (tools/ota/run.sh, Runde OTA)" \
     tools/ota/run.sh ota '^OTA: |^  OK    (der festgenagelte|kernel/(user|app)/|zwei signierte|Fassung 3|die Zertifikate|jede Signatur|ein VERZEICHNIS|die Gegenstelle|/bin/fetch|das Geraet|die Fassung|Wiederaufnahme|abgelehnt|[0-9]+ von 30|[0-9]+ von 7)'

lauf "35. Osum auf fremdem Blech: Wurzelsuche, RAID-Meldung, EHCI, NVMe-Namensraeume (tools/metal/run.sh, Runde BLECH)" \
     tools/metal/run.sh blech '^BLECH: |^  --    (QEMU|Beschleuniger)|^  OK    (der Kern|die Speicherkarte|ein OFS|DER ALTE|DER NEUE|und haengt|und /bin|und die Shell|die LEERE|und die AHCI|eingehaengt|kein einziger|und die Wurzel|ein Controller|und mit SEINEN|und es steht|der SD|und die Reihenfolge|die Firmware|an Anschluss|READ CAPACITY|keine Uebertragung|Block |die Tastatur|sechs Tasten|und es sind|der Endpunkt|Geraet 0|Geraet 1|beide sind|und Block |alle drei|auch der mit|Namensraum |GEGENPROBE|und kein Geraet|derselbe Treiber|q35|die nackte|ein EHCI|ein OHCI|ein UHCI|und bei OHCI)'

lauf "36. HID: Berichtsbeschreibungen, ein Eingabeweg, Touchpad, I2C-HID (tools/hid/run.sh, Runde HID)" \
     tools/hid/run.sh hid '^  ok    |^ +(ps2|usb-boot|usb-gen|i2c-soft|touchpad|n=) '

lauf "37. ein Treiber, der nicht im Kern steht: laden, benutzen, entladen (tools/module/run.sh, Runde MODUL)" \
     tools/module/run.sh modul '^MODUL: |^  OK    (zwei Kernabbilder|die Ausfuhrtafel|dasselbe wie nm|ohne Modul|mit Modul|und es bewegt|und es laesst|die Signatur|ein fremdes|der Kern laedt|danach|vorher|eine Platte|der Lauf endet|die Sperrliste)'

lauf "38. der JARVIS-Helfer und seine Rechteliste (tools/bridge/run.sh, Runde BRIDGE)" \
     tools/bridge/run.sh bridge '^BRIDGE: |^  OK    (firnc|kein undefinierter|die Namenskollision|bridge/build|jarvisd auf der Platte|jsig auf der Platte|der GUI-lose|die Testzertifikate|die Rechteliste wird|GEGENPROBE|die Verbindung steht|die Ed25519|der Server hat|und Osum hat|der Helfer meldet|die Laenge|system|schreib|lies|liste|befehl|foto|genau eine|sieben|der Start steht|die Anmeldung steht|ein (erledigter|abgelehnter)|acht Ablehnungen|und NICHTS ist passiert|(expired|wrong|rogue):|leerer Speicher|ohne Bestaetigung|der Code wird|und die Ablehnung|sie steht auch|jarvisctl|beim zweiten Anlauf|und sie steht|die Gegenstelle hat|der Helfer stirbt|er zaehlt|und er versucht|er endet|ohne Netz|er sagt|und er wartet|keine einzige|Systemaufrufe je|pub |die Schluesseldatei|und sie laesst|nach chmod|python-cryptography|der beschnittene|und der KERN|lesen geht weiter|die Rechte des|ohne Schein|mit Schein|DER SCHEIN GILT|und das zweite|das Foto steht|drei Auftraege|Antworten, die|Quelltext)|^        (Quelltext:|/bin/jarvisd:|/bin/jsig:|Wartelast:|gewartet:|QEMU auf dem Wirt|Rechtebitfeld|Groesse des Bildschirmfotos|KEIN BILD GEMESSEN|vom QEMU-Start)|^BRIDGE: uebersprungen'

# ABSCHNITT 39 -- RUNDE STICK.
#
lauf "39. was man mit dem Stick TUN kann: dhcp, host, fetch, ota und die Bruecke, vom Abbild (tools/stick/run.sh, Runde STICK)" \
     tools/stick/run.sh stick '^STICK: |^  ok   |^       (SHA-256|/bin traegt|kern|programme|apps|wurzeln|ota.conf|schluessel)'

lauf "40. Ring 3 auf ALLEN Kernen, und der Riegel davor -- der Fehler der Runde BLECHKERN, auf Bestellung (tools/multicore/run.sh, Runde VIELKERN)" \
     tools/multicore/run.sh vielkern '^VIELKERN: |^  OK   |^  FAIL |^        (r3:|tafel:|absturz:)'

lauf "41. der Aufgabenverwalter und das Kontrollzentrum (tools/toolbench/run.sh, Runde WERKZEUGE)" \
     tools/toolbench/run.sh werkzeug '^WERKZEUGE: |^  OK    |^        '

lauf "42. der Zeichenweg auf mehreren Kernen: eine Buehne je Kern (tools/glyph/run.sh, Runde GLYPHE)" \
     tools/glyph/run.sh glyphe '^GLYPHE: |^  OK    |^  FAIL |^  ZAHL  |^        '
#  43. DER SYSTEMBUS (tools/systembus/run.sh, Runde SYSTEMBUS)
#
lauf "43. der Systembus: Dienste, Rechte, Zwischenablage, Segmente (tools/systembus/run.sh, Runde SYSTEMBUS)" \
     tools/systembus/run.sh systembus '^SYSTEMBUS: |^  OK   |^  FAIL |^        (busa|busb|busd|buss|byt=|vor=|mit nobus|bild)'
lauf "44. das Kernprotokoll, die Absturzberichte und der Panik-Bildschirm (tools/protocol/run.sh, Runde PROTOKOLL)" \
     tools/protocol/run.sh protokoll '^PROTOKOLL: |^  OK    |^        '

lauf "45. Freunde, Praesenz und ein Chat ohne Mitleser (tools/presence/run.sh, Runde PRAESENZ)" \
     tools/presence/run.sh praesenz '^PRAESENZ: |^  OK    |^  FAIL  |^        (/bin/presence|104 Bereiche)'
# ================================================== RUNDE TON-2
#
lauf "46. der Mischer von Ring 3 aus: zwei Programme, Lautstaerke je Strom, Saettigung, Systemklang (tools/audio/mischer.sh, Runde TON-2)" \
     tools/audio/mischer.sh ton2 '^== |^  OK   |^  FEHL |^    \(|^ERGEBNIS'

lauf "48. die Bildgrenze und die Fensterbewegung (tools/vsync/run.sh, Runde VSYNC)" \
     tools/vsync/run.sh vsync '^VSYNC: |^    ok  |^    NICHT |^        '

lauf "49. der Puffer, der bei knappem Speicher schweigt -- und der Aufrufer, der darueber hinausschreibt (tools/hardening/run.sh, Runde HAERTUNG-2)" \
     tools/hardening/run.sh haertung '^HAERTUNG: |^  OK    |^  FEHL  |^     fall='
#
lauf "47. WLAN ohne eine einzige Karte: 802.11, WPA2/WPA3 und CCMP gegen die Normen und gegen eine echte Aufzeichnung (tools/wlan/run.sh, Runde WLAN)" \
     tools/wlan/run.sh wlan '^WLAN: |^WLAN-FUZZ: |^== |^  OK    (QEMU |tools/wlan/orakel|das Orakel lehnt|die Aufzeichnung liegt|SHA-1 gegen|HMAC-SHA1 gegen|PRF-SHA1, IEEE|PBKDF2-SHA1, RFC|PMK aus|AES gegen OpenSSL|AES-CMAC, RFC|Key Wrap, RFC|AES-CCM|IEEE Std 802\.11|Beacon 1|die Ketten|EAPOL-Rahmen|PTK aus dem echten|Pruefwert von Nachricht|Gruppenschluessel aus|DIE GANZE KETTE|mit einem TK|ueber ALLE|die richtige Folge|und hat den Schluessel|alle [0-9]+ Verstuemmelungen|Nachricht 3 zweimal|ERSCHOEPFEND|der Fehlerzustand|alle [0-9]+ Abschnitte|ein RSN-Element|EAPOL: alle|[0-9]+ verstuemmelte Rahmen|jede der [0-9]+|von den [0-9]+|valgrind ueber|keine WLAN-PCI|SAE ist NICHT|TKIP und WEP|die Runde in Zeilen|PTK mit KDF-SHA256|beide Seiten)'
#
lauf "50. WLAN gegen ein ZWEITES Programm: 4-Wege-Handschlag gegen einen unabhaengigen Authenticator, die Naht zum Blech, der USB-Stick beim Namen (tools/wlan/run2.sh, Runde WLAN-2)" \
     tools/wlan/run2.sh wlan2 '^WLAN2: |^== |^  OK    (tools/wlan/orakel|die Gegenstelle|PMK aus|Pruefwert von|Schluesseldaten von|[0-9]+ vollstaendige|in jedem Lauf|Nachricht 3 mit|Schluesseldaten OHNE|Automat: |die Naht|ein Geraet OHNE|alle [0-9]+ USB|kernel/usb\.fi|SAE ist NICHT|kein USB-WLAN|die neuen Dateien)'

lauf "51. der echte Standby: S3 schlafen und aufwachen, Geraete und Speicher danach (tools/s3/run.sh, K-004)" \
     tools/s3/run.sh s3 '^S3: |^== |^  OK    (QEMU meldet|zurueck|APIC|PCI|ACPI-Modus|Arbeitsspeicher|Pruefsumme|zwei verschiedene|Zeitgeber|und kommt NICHT|Ladesegmente|Grafikmodus|die Rueckstellung|Gegenprobe s3nobild|8042|das Programm bittet|INNERHALB des Systemaufrufs|kehrt nach dem Wecken|die Shell fuehrt)'

lauf "52. der Anmeldeschirm, wie Justin ihn bedient: eine Taste ein Zeichen, Tab-Kette, blinkende Marke, das Auge, Maus auf USB und PS/2 (tools/loginui/run.sh, Runde LOGIN-2)" \
     tools/loginui/run.sh loginui '^LOGINUI: |^== |^  OK    (xhci\.fi|XUSB2PR|kbd\.irq|the icon font|glogin\.fi|lock\.fi|the login screen|the USB mouse|one password|visible fields|the focus starts|caret phase|and it alternates|Tab chain|Tab: button|the password field has|a MOUSE click|a second click|BILD|the name field|name typed|GEGENPROBE|four PS/2|clock, network|a click on the|a second click closes)'

# 53. THE ACTION BUS (docs/ACTION-BUS.md): apps declare actions in a
# manifest, one broker (/bin/orientbus) checks types and rights for every
# caller alike, critical actions always need the user, changes are
# logged before they happen and can be undone -- and Jarvis reaches it
# only through the bridge and the same client (/bin/act).
lauf "53. the action bus: manifests, one broker for every caller, rights, dry run, undo, audit, Jarvis through the bridge (tools/actionbus/run.sh, round ACTION-BUS)" \
     tools/actionbus/run.sh actionbus '^ACTIONBUS: |^ACTIONBUS-LATENCY |^== |^  OK    |^  FAIL  '

# 54. AB-016: the action bus in the SHIPPED image -- the stick is built,
# booted like the Dell (UEFI, USB, default entry), and the session starts
# the broker and the settings provider before the sign-in.
lauf "54. the action bus in the real image: broker + settingsd started by the session, before the sign-in (tools/actionbus/image.sh, AB-016)" \
     tools/actionbus/image.sh actbusimage '^ACTBUS-IMAGE: |^== |^  OK    |^  FAIL  '

# 55. THE SOCIAL LAYER (FirnChat docs/SOCIAL.md, docs/ACTION-BUS.md § 8):
# the service /bin/social on the action bus, providers as programs behind
# one interface (Fleitec over the network with a device access token, the
# device's own contacts), the friends bar reading it -- friends on the
# host's fleikontakte see what was set on OrientOS.
lauf "55. the social layer: social.* actions on orient-bus, providers behind one interface, presence/activity/privacy, the friends bar (tools/social/run.sh, round SOCIAL)" \
     tools/social/run.sh social '^SOCIAL: |^== |^  OK    |^  FAIL  '

# 55b. THE MELDER ON ORIENTOS (r135, FirnChat docs/MELDER-INTERFACE.md):
# /bin/melder is the OrientOS backend of the Melder interface v1 and a small
# core -- a running game becomes social.activity.set on the bus, the privacy
# switch is social.privacy.set; no token, no HTTP.
lauf "55b. the Melder on the OS: backend v1 (hello/detect/games/privacy/autostart/report) and core, reporting as bus actions (tools/melder/run.sh, r135)" \
     tools/melder/run.sh melder '^MELDER: |^== |^  OK    |^  FAIL  '

# 55c. RIGHTS PER APP AND PRIVACY OF THE SOCIAL SERVICE (r30): scopes
# (contacts.read, activity.write, messages.send, invites.send), user_only,
# the never-show list, who may invite -- one local provider, no network.
lauf "55c. social rights per app and privacy switches: scopes, user_only, never show, who may invite (tools/social/perms.sh, r30)" \
     tools/social/perms.sh socperms '^SOCIAL-PERMS: |^== |^  OK    |^  FAIL  '

# 55d. THE SOCIAL SDK (r29): setActivity with a party, invite, join -- the C
# header and the JS shim against a fake act, the Firn module against the real
# broker + service, social.party.take once, the scopes.
lauf "55d. social SDK for apps and games: Firn module, C header, JS shim, party/join, social.party.take (tools/social/sdk.sh, r29)" \
     tools/social/sdk.sh socsdk '^SOCIAL-SDK: |^== |^  OK    |^  FAIL  '

# 55e. THE SETTINGS PAGES OF THE SOCIAL PACKAGE ON THE REAL IMAGE (r348): a click on the
# switch and on the text fields asks, the system dialog answers, nothing says "Failed.".
lauf "55e. settings window, package pages of the social layer: ask, trusted dialog yes (tools/usbimg/settingsprobe.sh, r348)" \
     tools/setprobe/run.sh setprobe '^SETTINGSPROBE: |^== |^  OK    |^  FAIL  '

# 55f. THE FRIENDS BAR JOIN PATHS ON THE REAL IMAGE (r349): friend -> chat -> Join and
# invitation -> Accept both end in partyrun starting the game.
lauf "55f. friends bar: Join and Accept start the game through partyrun (tools/usbimg/joinprobe.sh, r349)" \
     tools/joinprobe/run.sh joinprobe '^JOINPROBE: |^== |^  OK    |^  FAIL  '

# 56. ROUND ACTION-BUS-3 ON A SCREEN: the foreign-window layer (a Linux
# Wayland program on wayd steered through its window -- keys, typed text,
# a click, the close box; the settings window is NOT steerable) and the
# settings window as a client of the bus (pages System and App rights,
# a critical change only after the yes, brightness into the kernel).
lauf "56. the action bus on a screen: foreign windows (keys/ui adapters, wayd input) and the settings window as a bus client (tools/actionbus/gui.sh, round ACTION-BUS-3)" \
     tools/actionbus/gui.sh actbusgui '^ACTBUS-GUI: |^== |^  OK    |^  FAIL  '

# DAILY-DRIVER: the clock -- summer time by rule, setting it (clock_settime),
# the network clock /bin/sntp against a fake NTP server, faulty answers.
lauf "57. the clock: summer time by rule (tzrule=eu), clock_settime, /bin/sntp, faulty NTP answers (tools/time/run.sh, round DAILY-DRIVER)" \
     tools/time/run.sh time '^TIME: |^== |^  OK    |^  FAIL  '
lauf "57b. the clock right after the boot, before any sntp: hardware clock on local time / UTC / no zone yet, summer and winter (tools/time/boot.sh, r544)" \
     tools/time/boot.sh timeboot '^TIME-BOOT: |^== |^  OK    |^  FAIL  '

# 58. THE ENGLISH GUARD (Justin, 07.10.2026): code is English -- identifiers, file names, program names,
# comments, log and error texts; German lives in the catalogs only. The counter must count (counter-proof),
# no file may get MORE German than tools/english/baseline.json says, and the lines added since main are English.
lauf "58. the English guard: German in code only goes down, new lines are English (tools/english/run.sh)" \
     tools/english/run.sh english '^ENGLISH: |^== |^  OK    |^  FAIL  '

# 59. THE DISK MANAGER, READING ONLY (docs/DISKS.md stages D-0 / D-1): the partition table reader on image files (a GPT with
# primary and backup, an MBR, two tables with one flipped byte -- they must read as none), /bin/diskctl in the VM on a
# second disk, and the window /bin/disks.
lauf "59. the disk manager, read side: MBR / GPT with checksums, diskctl list, the window (tools/disks/run.sh)" \
     tools/disks/run.sh disks '^DISKS: |^== |^  OK    |^  FAIL  '

# 60. THE CENTRE LINE (r441): icon, text and row on ONE line -- the file manager's rows, the command bar, the title bar,
# the tabs, a menu, the task bar (tools/midline/run.sh).
lauf "60. the centre line: rows, icons, tabs, menu rows, title bar, task bar (tools/midline/run.sh)" \
     tools/midline/run.sh midline '^MIDLINE: |^  OK    |^  FAIL  '

# 61. THE DAMAGE REGION (docs/COMPOSITOR.md S2): the same picture as with the single box (kernel word `norgn`), and a real saving.
lauf "61. the damage region: same picture as the single box, fewer pixels painted (tools/region/run.sh)" \
     tools/region/run.sh region '^REGION: |^== |^  OK    |^  FAIL  '

# 62. RING-3 COMPOSITING (docs/COMPOSITOR.md section 5): the window server's primitives and a process wake-up, measured in a user program.
lauf "62. ring-3 compositing: row copy, blend, blur, pipe round trip against the 16 ms budget (tools/comp/run.sh)" \
     tools/comp/run.sh comp '^COMP: |^== |^  OK    |^  FAIL  '

# 63. THE TERMINAL WINDOW EXECUTES THE CONTROL SEQUENCES OF FULL-SCREEN PROGRAMS (docs/TERMINAL.md): the editor in a terminal window, its
# cells read back, the tty size answered from the window's grid.
lauf "63. the terminal window: the editor's control sequences are executed, the screen fits the window (tools/term/run.sh)" \
     tools/term/run.sh term '^TERM: |^== |^  OK    |^  FAIL  '

# 58b. retired (ENG-1, 22.10.2026): tools/english/count.py is the one German-in-code metric and guard (section 58).
# 64. ROUND WAYLAND-INPUT: a real libwayland client on wayd gets the keyboard (keymap memfd, focus, serials, modifiers), the pointer
# (enter/motion/button/frame/leave) and the clipboard (wl_data_device, client to client and to/from the OrientOS clipboard), with
# counter-proofs (no focus, wrong serial, dead owner, locked screen); keysyms checked with libxkbcommon on the host.
lauf "64. Wayland input and clipboard: keymap, focus, keys, pointer, wl_data_device, bridge to the system clipboard (tools/wayland/input.sh, round WAYLAND-INPUT)" \
     tools/wayland/input.sh wlinput '^WL-INPUT: |^== |^  OK    |^  FAIL  '

# 65. R-015: touch screen, touch pad and pen as layers: HID contacts, tracker with quirks, event ring (/proc/touchev), gesture machines
# (lib/touchgest), the app API (lib/touchev) and a Surface Laptop 4 capture replayed through the kernel parser; counter-proofs in each lib gate.
lauf "65. Input stack: contacts, tracker, quirks, ring, gestures, app API, HOLO-LAPTOP-3 corpus (tools/input/run.sh, R-015)" \
     tools/input/run.sh input '^  OK    |^  FAIL  |^input: '

abschnitte_abarbeiten
ABGEARBEITET=1

echo
echo "=================================================================="
echo "gelaufen mit OSUM_JOBS=$JOBS, accel=${OSUM_ACCEL:-auto}"
if [ "$UEBERSPRUNGEN" -gt 0 ]; then
    echo "ACHTUNG: DIESER LAUF IST UNVOLLSTAENDIG -- OSUM_NUR='$NUR' hat"
    echo "         $UEBERSPRUNGEN Abschnitte gar nicht erst angemeldet. Die Zahlen"
    echo "         unten gelten NICHT als Abnahme."
fi
if [ "$FAIL" -eq 0 ]; then
    echo "ALLE $PASS ABSCHNITTE BESTANDEN, $ZUSAGEN Zusagen, 0 Fehler"
    exit 0
else
    echo "$PASS Abschnitte bestanden, $FAIL FEHLGESCHLAGEN ($ZUSAGEN Zusagen)"
    printf '%b\n' "$FAILED"
    exit 1
fi
