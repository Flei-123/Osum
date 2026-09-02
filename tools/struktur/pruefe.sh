#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/struktur/pruefe.sh -- DER NACHWEIS, DASS DER UMZUG NICHTS GETAN HAT.
#
#   ./tools/struktur/pruefe.sh ALT.elf NEU.elf
#
# Ein Umzug von Dateien darf am fertigen Kern NICHTS aendern. "Der Bau
# laeuft durch" ist dafuer KEIN Nachweis -- er liefe auch durch, wenn ein
# Treiber leise aus dem Abbild gefallen waere, weil niemand ihn mehr
# importiert. Deshalb wird hier das ABBILD verglichen, nicht der Bau.
#
# Vier Proben, in dieser Reihenfolge, und die dritte ist die eigentliche:
#
#   1. DIE SYMBOLE. Jede Funktion und jede Konstante des alten Abbilds
#      muss im neuen stehen und umgekehrt. Der Uebersetzer bildet ein
#      Symbol aus DATEINAME und Funktionsname (`modules.rs`:
#      `module_name` = `file_stem`, dann `mangle` = `modul__name`) -- der
#      Pfad steht NICHT darin. Ein Umzug darf hier also null Differenz
#      machen; jede Abweichung waere ein verlorenes oder doppeltes Modul.
#
#   2. DIE GROESSE VON .text. Gleich viele Oktette Befehle heisst: kein
#      Befehl kam hinzu, keiner fiel weg.
#
#   3. JEDE ABWEICHUNG IM CODE MUSS ERKLAERT SEIN. .text ist nach dem
#      Umzug NICHT oktettgleich, und das ist richtig so -- aber "richtig
#      so" muss man BELEGEN und nicht behaupten. Darum wird hier nicht
#      wegnormalisiert, sondern KLASSIFIZIERT: jeder abweichende Befehl
#      muss in eine der drei Klassen fallen, die aus einem laengeren
#      Quellpfad folgen; die vierte Klasse ("unerklaert") muss leer sein.
#        B  Ein Immediate, das sich um 12 oder 14 unterscheidet -- die
#           LAENGE des Pfadstrings. Osums Panikaufruf bekommt Zeiger UND
#           Laenge, und die Laenge steht als Konstante im Befehl.
#           (`mov $0x52,%esi` -> `mov $0x60,%esi`: 82 -> 96 Zeichen, und
#           14 ist genau kernel/kbd.fi -> kernel/drivers/input/kbd.fi.)
#        C1 Eine Absolutadresse, die um 0x2000 groesser ist: .rodata
#           waechst um 9456 Oktette, das sind aufgerundet zwei Seiten,
#           und alles dahinter (.data, .bss, kdata) rutscht mit.
#        C2 Ein RIP-relativer Versatz auf einen Zeichenkettenanfang, der
#           sich verschoben hat.
#      Eine Handvoll Stellen im Startcode (`arch/x86_64/boot.s`) traegt
#      Daten IM .text; dort verliert objdump die Synchronisation und
#      liest dieselben Oktette einmal als `and` und einmal als `rex`.
#      Diese Stellen werden nicht geschoent, sondern eigens ausgewiesen
#      und auf ihre Zahlen geprueft (auch dort: +0x2000).
#
#   4. DER GRUND FUER DEN REST. Die Panikmeldungen des Kerns tragen den
#      QUELLPFAD ("panic: integer overflow ... at .../kernel/usb.fi:41:3").
#      Wird eine Datei tiefer gelegt, wird dieser Text laenger, .rodata
#      waechst, und alles dahinter rutscht um ein Vielfaches der
#      Seitengroesse weiter. Diese Probe rechnet das Wachstum von .rodata
#      aus den Pfadlaengen NACH und verlangt, dass der unerklaerte Rest
#      NULL ist. Erst damit ist die Groessenaenderung erklaert statt nur
#      hingenommen.
#
# EINE VORPROBE, ohne die die anderen nichts wert waeren: derselbe Baum
# zweimal gebaut ergibt oktettgleiches .text (nachgemessen, Runde
# STRUKTUR). .rodata dagegen ist NICHT reproduzierbar, weil
# `tools/build-kernel.sh` aus einem `mktemp -d`-Verzeichnis uebersetzt
# und dessen Name in jeder Panikmeldung steht. Die Namen sind gleich
# LANG, darum ist die GROESSE reproduzierbar und der Inhalt nicht.
set -uo pipefail
cd "$(dirname "$0")/../.."

ALT=${1:-}
NEU=${2:-}
if [[ -z $ALT || -z $NEU ]]; then
    sed -n '4,6p' "$0"; exit 1
fi
for f in "$ALT" "$NEU"; do
    [[ -f $f ]] || { echo "gibt es nicht: $f" >&2; exit 1; }
done

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FEHLER %s\n' "$1"; }

echo "STRUKTUR-PRUEFUNG"
echo "  alt: $ALT"
echo "  neu: $NEU"

# ------------------------------------------------------------ 1. Symbole
nm "$ALT" 2>/dev/null | awk '{print $3}' | sort > /tmp/.st-sym-alt
nm "$NEU" 2>/dev/null | awk '{print $3}' | sort > /tmp/.st-sym-neu
na=$(wc -l < /tmp/.st-sym-alt); nn=$(wc -l < /tmp/.st-sym-neu)
nur_alt=$(comm -23 /tmp/.st-sym-alt /tmp/.st-sym-neu | grep -c . || true)
nur_neu=$(comm -13 /tmp/.st-sym-alt /tmp/.st-sym-neu | grep -c . || true)
if [[ $na -eq $nn && $nur_alt -eq 0 && $nur_neu -eq 0 ]]; then
    ok "die Symbole sind dieselben ($na), keins hinzu, keins weg"
else
    bad "Symbole: alt $na, neu $nn, nur alt $nur_alt, nur neu $nur_neu"
    comm -23 /tmp/.st-sym-alt /tmp/.st-sym-neu | head -10 | sed 's/^/        nur alt: /'
    comm -13 /tmp/.st-sym-alt /tmp/.st-sym-neu | head -10 | sed 's/^/        nur neu: /'
fi

# ------------------------------------------------------- 2. Groesse .text
ta=$(size -A "$ALT" | awk '$1==".text"{print $2}')
tn=$(size -A "$NEU" | awk '$1==".text"{print $2}')
if [[ $ta == "$tn" ]]; then
    ok ".text ist gleich gross ($ta Oktette) -- kein Befehl kam hinzu oder fiel weg"
else
    bad ".text alt $ta, neu $tn Oktette"
fi

# ---------------------------------------------------- 3./4. die Befehlsfolge
python3 - "$ALT" "$NEU" <<'ENDEPY3'
import re,subprocess,sys,collections
alt,neu=sys.argv[1],sys.argv[2]

def befehle(f):
    out=subprocess.run(['objdump','-d','--no-show-raw-insn','-j','.text',f],
                       capture_output=True,text=True).stdout
    r=[]
    for ln in out.splitlines():
        m=re.match(r'\s+([0-9a-f]+):\s+(\S+)\s*([^#]*)',ln)
        if m: r.append((int(m.group(1),16),m.group(2),m.group(3).strip()))
    return r

a,b=befehle(alt),befehle(neu)
print("  ....  %d Befehle alt, %d neu" % (len(a),len(b)))
if len(a)!=len(b):
    print("  FEHLER verschieden viele Befehle"); sys.exit(1)

# Die Pfadverlaengerungen dieser Runde: 12 Zeichen (kernel/X.fi ->
# kernel/drivers/KL3/X.fi) und 14 (Klasse `input`, zwei Zeichen mehr).
PFAD={12,14}

# WIEVIEL alles hinter .rodata weiterrutscht, wird GEMESSEN und nicht
# angenommen: es ist die Differenz der .data-Adressen. Beim GUI-losen
# Abbild sind das zwei Seiten (0x2000), beim vollen fuenf (0x5000) --
# eine feste Zahl im Skript waere genau hier falsch gewesen und hat es
# beim zweiten Abbild auch prompt gemeldet.
def datenadresse(f):
    out=subprocess.run(['readelf','-S',f],capture_output=True,text=True).stdout
    for ln in out.splitlines():
        m=re.search(r'\.data\s+PROGBITS\s+([0-9a-f]+)',ln)
        if m: return int(m.group(1),16)
    return 0
SEITEN=datenadresse(neu)-datenadresse(alt)

# Und WIE WEIT ein einzelner Zeichenkettenanfang innerhalb von .rodata
# wandern kann, ist ebenfalls keine Schaetzung: hoechstens um das
# gesamte Wachstum von .rodata. Eine geratene Schranke (0x4000) hat
# genau hier danebengelegen -- der groesste echte Versatz war 0x4004.
def rodatagroesse(f):
    out=subprocess.run(['size','-A',f],capture_output=True,text=True).stdout
    return int(out.split('.rodata')[1].split()[0])
WACHSTUM=rodatagroesse(neu)-rodatagroesse(alt)
GRENZE=max(SEITEN,WACHSTUM)
print("  ....  hinter .rodata rutscht alles um 0x%x; .rodata waechst um %d Oktette"
      % (SEITEN,WACHSTUM))
print("  ....  ein Zeichenkettenversatz darf sich also um hoechstens %d unterscheiden" % GRENZE)

def zahlen(t):
    # auch 64-bit-Brocken, die objdump an Datenstellen zusammenzieht,
    # werden in 32-bit-Haelften zerlegt -- sonst faellt eine Adresse,
    # die zweimal +0x2000 enthaelt, durch das Raster.
    out=[]
    for h in re.findall(r'0x([0-9a-f]+)',t):
        v=int(h,16)
        if len(h)>8: out += [v>>32, v & 0xFFFFFFFF]
        else: out.append(v)
    return out

kl=collections.Counter(); unerklaert=[]
for i in range(len(a)):
    if a[i][1:]==b[i][1:]: continue
    _,oa,ga=a[i]; _,ob,gb=b[i]
    na,nb=zahlen(ga),zahlen(gb)
    if len(na)!=len(nb) or not na:
        kl['A  Desync im Startcode (Daten im .text)']+=1
        unerklaert.append((i,oa,ga,ob,gb)); continue
    d=[y-x for x,y in zip(na,nb) if x!=y]
    if not d:
        unerklaert.append((i,oa,ga,ob,gb)); kl['D  unerklaert']+=1
    elif all(x in PFAD for x in d):
        kl['B  Stringlaenge als Immediate (+12/+14)']+=1
    elif all(x==SEITEN for x in d):
        kl['C1 Absolutadresse +0x%x' % SEITEN]+=1
    elif all(0 < x <= GRENZE for x in d):
        kl['C2 RIP-Versatz auf verschobenen String']+=1
    else:
        unerklaert.append((i,oa,ga,ob,gb)); kl['D  unerklaert']+=1

n=sum(kl.values())
print("  ....  %d Befehle weichen ab, nach Klasse:" % n)
for k,v in sorted(kl.items()): print("        %-42s %5d" % (k,v))

# DIE DESYNC-STELLEN: nicht mehr ueber den Disassembler, sondern ueber
# die ROHEN OKTETTE. Der Startcode aus `arch/x86_64/boot.s` laeuft im
# 32-Bit-Modus, objdump liest ihn als 64-Bit und zieht darum Oktette zu
# Befehlen zusammen, die es nicht gibt (`a3 00 10 4a 00 ...` wird ein
# `movabs` mit 8-Oktett-Operand). Ob sich dort etwas GEAENDERT hat,
# entscheidet deshalb nicht die Befehlszeile, sondern das Oktett:
# um jede unerklaerte Stelle wird ein Fenster gelegt, und JEDES
# abweichende Oktett darin muss Teil eines 32-Bit-Wortes sein, das um
# genau +0x2000 groesser geworden ist -- eine Adresse der Seitentafeln,
# die mit .data weitergerutscht ist.
import struct,tempfile,os
def rohtext(f):
    t=tempfile.mktemp()
    subprocess.run(['objcopy','-O','binary','--only-section=.text',f,t],check=True)
    d=open(t,'rb').read(); os.unlink(t); return d
ra,rb=rohtext(alt),rohtext(neu)
TEXTBASIS=0x100000
schlimm=[]
for i,oa,ga,ob,gb in unerklaert:
    adr=a[i][0]-TEXTBASIS
    lo,hi=max(0,adr-8),min(len(ra),adr+12)
    stellen=[k for k in range(lo,hi) if ra[k]!=rb[k]]
    offen=[]
    for k in stellen:
        gut=False
        for w in range(max(0,k-3),k+1):
            if w+4<=len(ra):
                va=struct.unpack('<I',ra[w:w+4])[0]; vb=struct.unpack('<I',rb[w:w+4])[0]
                if vb-va==SEITEN: gut=True; break
        if not gut: offen.append(k)
    if offen: schlimm.append((i,oa,ga,ob,gb))
    else:
        print("        Desync bei 0x%x ('%s' | '%s'): %d abweichende Oktette," %
              (a[i][0],oa,ob,len(stellen)))
        print("           alle Teil einer Adresse +0x2000 (Seitentafeln aus boot.s)")

if schlimm:
    print("  FEHLER %d Befehle bleiben unerklaert:" % len(schlimm))
    for i,oa,ga,ob,gb in schlimm[:10]:
        print("        alt: %s %s" % (oa,ga)); print("        neu: %s %s" % (ob,gb))
    sys.exit(1)
print("  ok    alle %d Abweichungen folgen aus laengeren Quellpfaden -- kein geaenderter Code" % n)
ENDEPY3
[[ $? -eq 0 ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

# ------------------------------------- 4. das Wachstum von .rodata erklaeren
python3 - "$ALT" "$NEU" <<'PY'
import re,sys,subprocess,collections
alt,neu=sys.argv[1],sys.argv[2]
def rodata(f):
    return int(subprocess.run(['size','-A',f],capture_output=True,text=True)
               .stdout.split('.rodata')[1].split()[0])
def pfade(f):
    d=open(f,'rb').read()
    return collections.Counter(re.findall(rb'/kernel/([A-Za-z0-9_/.-]+\.fi):',d))
wachstum=rodata(neu)-rodata(alt)
ca,cb=pfade(alt),pfade(neu)
erklaert=0
zeilen=[]
for p,n in sorted(ca.items()):
    base=p.split(b'/')[-1]
    cand=[q for q in cb if q.split(b'/')[-1]==base]
    if not cand or cand[0]==p: continue
    q=cand[0]; d=(len(q)-len(p))*n
    erklaert+=d
    zeilen.append("        %-24s -> %-30s %4d Stellen x %2d = %5d" %
                  (p.decode(),q.decode(),n,len(q)-len(p),d))
print("  ....  .rodata waechst um %d Oktette" % wachstum)
for z in zeilen: print(z)
rest=wachstum-erklaert
if rest==0:
    print("  ok    restlos erklaert: %d Oktett laengere Quellpfade in Panikmeldungen" % erklaert)
else:
    print("  FEHLER %d Oktett unerklaert (erklaert: %d)" % (rest,erklaert))
    sys.exit(1)
PY
[[ $? -eq 0 ]] && PASS=$((PASS+1)) || FAIL=$((FAIL+1))

echo "STRUKTUR: $PASS bestanden, $FAIL gefallen"
[[ $FAIL -eq 0 ]]
