# RUNDE KLEINKRAM2 -- K-022 und O-009

Zweig `kleinkram2`, Basis `main` (1f1be8a). Zwei kleine offene Punkte,
beide gemessen, beide mit einer Gegenprobe, die fehlschlagen MUSS.

---

## K-022 -- der XTS-Schluesselspeicher hielt genau EINEN Schluessel

### VORHER

`lib/crypto/xts.fi` hielt seit Runde AESNI die fertigen
AES-NI-Schluesselplaene des **zuletzt benutzten** Schluessels in vier
Statiken (`c_key`, `c_enc`, `c_dec`, `c_tk2`, `c_voll`). Das war noetig:
ohne den Speicher rief `sector_encrypt` `aes.key_set` zweimal je Sektor,
und `key_set` kostet 6218 ns -- 12,4 us je Sektor allein fuer den Plan,
bei 1,9 us echter Rechnung.

Der Speicher trug, solange es **einen** verschluesselten Traeger gab.
Bei **zwei** nebeneinander fiel er bei jedem Wechsel um.

### NACHHER

Eine Tafel mit vier Plaetzen (`SLOTS = 4`), jeder mit eigenem Schluessel
und eigenen Plaenen, Verdraengung reihum. Kein LRU-Zaehler -- der waere
ein Seitenkanal ueber die Zugriffsfolge und traegt bei vier Plaetzen
nichts ein.

Die Tafel liegt in `lib/`, **nicht** in `kdata`: es wurde weder eine
Seite noch ein Modusindex gebraucht. Die Zuteilung 0x138000..0x13A000 /
1085..1087 ist **unangetastet**, `MODE_WORDS` bleibt 17.

### GEMESSEN

`tools/xtstafel/run.sh` -- **XTSTAFEL: 6 bestanden, 0 gescheitert**

| Messung | vorher (SLOTS=1) | nachher (SLOTS=4) |
|---|---|---|
| 200 Sektoren, zwei Traeger abwechselnd | **200 Neufuellungen** | **0** |
| Aufwaermen (beide Traeger einmal) | 2 | 2 |
| nach `forget()`: Oktette ungleich null in der Tafel | -- | **0 von 3360** |

Beide Traeger gehen Oktett fuer Oktett hin und zurueck, und zwei
Schluessel liefern zwei verschiedene Geheimtexte. Fuenf Schluessel auf
vier Plaetzen (die Verdraengung greift) rechnen weiter richtig.

### DIE BEIDEN DINGE, DIE NICHT VERLOREN GEHEN DURFTEN

1. **`forget()` loescht ALLE Eintraege.** `krypto.lock_down` ruft es;
   bliebe ein Plan stehen, laege nach dem Zusperren noch ein Schluessel
   im Speicher, waehrend `CRY_KEY` schon genullt ist. Die Schleife geht
   ueber alle Plaetze und nullt Schluessel UND Plaene UND `nr`/`ok`.
2. **Der Vergleich laeuft ohne fruehen Abbruch** -- ueber alle 64
   Oktette, und zusaetzlich ueber **alle** Plaetze: `cache_hit` springt
   beim Treffer NICHT heraus, sondern merkt ihn sich und sieht sich
   jeden Platz an. Ein fruehes `return` waere ein Zeitkanal geworden,
   den es vorher (bei einem Platz) noch nicht geben konnte.

### DIE OFFENE FRAGE AUS RUNDE AESNI -- JETZT BEANTWORTET

Der Bericht der Runde AESNI liess ausdruecklich ungeprueft, ob der Plan
nach `forget()` wirklich nirgends mehr steht. `tools/xtstafel/loeschen.fi`
sieht **im echten Speicher der Tafel** nach (`xts.tafel_von()`/`tafel_len()`,
die Laenge aus dem Abstand zweier Plaetze, nicht geraten):

* waehrend der Traeger offen ist, ist der Schluessel dort zu finden --
  sonst suchte die Probe an der falschen Stelle und alles Weitere waere
  wertlos;
* nach `forget()`: **0 Treffer, 0 von 3360 Oktetten ungleich null.**

Was das NICHT behauptet: dass nirgendwo sonst eine Kopie liegt. Der
Uebersetzer darf Zwischenwerte auf dem Stapel lassen, und `krypto.fi`
haelt den Hauptschluessel ohnehin in `kstate`, solange die Platte offen
ist. Geprueft ist die Tafel.

### GEGENPROBEN (beide laufen in `run.sh` mit und MUESSEN durchfallen)

* `SLOTS = 1` -- der Zustand vor dieser Runde: **200 Fuellungen** statt 0.
* `forget()` raeumt nur Platz 0: der Schluessel ist danach noch zu
  finden, **2366 Oktette** bleiben stehen, der Loeschtest schlaegt an.

Die zweite Gegenprobe hat waehrend der Runde einen echten Fehler in der
**Abnahme** gefunden: die erste Fassung von `loeschen.fi` benutzte einen
einzigen Schluessel, damit war nur Platz 0 belegt, und ein halbes
`forget()` kam durch. Die Probe belegt jetzt erst alle vier Plaetze.
Ebenso war die Tafellaenge zuerst mit 784 Oktetten je Platz fest
hingeschrieben -- der Uebersetzer legt sie auf **840**, und 224 Oktette
je Platz waeren ungeprueft geblieben.

### ZUSTAND

**Erledigt und gemessen.** `tools/krypto/run.sh` 61/0, `tools/aesni/run.sh`
31/0, `tools/argon/run.sh` 35/0 -- alle drei mit der Tafel im Baum.

---

## O-009 -- der Geraeteschluessel ueberlebte den Neustart nicht

### VORHER

`jarvisd` weist das Geraet mit einem Ed25519-Paar aus; der private Teil
liegt in `/etc/jarvis/geraet.key`. Das USB-Abbild legt `/etc/jarvis/` an
und bringt `rechte.conf` mit, aber **keinen** Schluessel -- der entsteht
erst beim Koppeln, und zwar in der **RAM-Wurzel**. Nach jedem Neustart
musste neu gekoppelt werden. In `OFFEN.md` steht dazu "haengt an P-001".

### DIE TRENNUNG, AUF DIE ES ANKAM

"Haengt an P-001" vermischt zwei Fragen:

* **P-001** fragt: kann ein Mensch OrientOS ueber die Oberflaeche auf
  eine Platte installieren?
* **O-009** fragt: wenn die Wurzel auf einem schreibbaren Traeger liegt
  -- bleibt der Geraeteschluessel dann derselbe?

Die zweite laesst sich messen, **ohne** die erste zu loesen: eine Wurzel
auf einer IDE-Platte, die ueber zwei Starts dieselbe bleibt. Genau so
misst `tools/bridge2/kette.sh` schon heute (Zeile 265-278: *"ein Rechner,
der beim Neustart seine Identitaet verliert, DARF nicht mehr
hereinkommen"*) -- nur fuer den Schluessel war es nie nachgeholt worden.

### NACHHER

`tools/geraetekey/run.sh`, neu. Kein Installer, keine Oberflaeche,
**dieselbe Platte ueber vier Starts**:

    Lauf 1   jsig aus                        -> das Paar, `pub`
             jsig unterschreibe 4f2d303039   -> `sig` ("O-009")
    NEUSTART
    Lauf 2   jsig aus                        -> darf KEINEN neuen anlegen
             jsig pruefe <pub1> <msg> <sig1> -> die ALTE Unterschrift
    Lauf 3   rm geraet.key; jsig aus         -> Zuruecksetzen
    Lauf 4   jsig pruefe <pub3> <msg> <sig1> -> darf NICHT mehr passen

### GEMESSEN

`tools/geraetekey/run.sh` -- **GERAETEKEY: 12 bestanden, 0 gescheitert**

* Nach dem Neustart **derselbe** oeffentliche Teil -- kein zweites Koppeln.
* Eine Unterschrift **von vor dem Neustart** verifiziert weiterhin.
* **`python-cryptography` rechnet sie nach** -- fremdes Werkzeug, damit
  ein Fehler, der in `jsig aus` und `jsig pruefe` gleich steckt,
  auffliegt. Ueber eine andere Nachricht faellt sie durch.
* Nach dem Zuruecksetzen entsteht ein **anderer** Schluessel, und die
  alte Unterschrift passt nicht mehr zu ihm.

### GEGENPROBE (laeuft in `run.sh` mit)

Abschnitt 5 ruft den Laeufer noch einmal mit `GK_WEGWERF=1` auf: die
Platte wird vor **jedem** Start frisch ueberschrieben -- genau das
Verhalten der RAM-Wurzel. Dann faellt Abschnitt 2 durch ("der Schluessel
hat den Neustart nicht ueberlebt"), und das wird als OK gewertet. Ohne
sie wuerde die Abnahme nur `jsig` mit sich selbst vergleichen.

### WAS OFFEN BLEIBT, UND WARUM

`tools/install/abnahme.sh` Abschnitt 7b misst dieselbe Frage auf dem
**echten** Weg (installierte Platte). Der Abschnitt ist in dieser Runde
von einem Platzhalter (64 von Hand hingeschriebene Hexziffern, die nur
den PFAD belegen) auf den vollen Ed25519-Lebenslauf umgestellt worden --
**er laeuft aber nicht durch**, weil P-001 auf diesem Wirt haengt: der
Installer bekommt sein Fenster nicht auf.

    mb: ... wigapp=/bin/installer,sofort
    init: ziel=grafik
    init: herunterfahren        <- statt den Installer zu starten

Gemessen, und zwar **auch auf dem unveraenderten Baum** (Commit d1d6767,
`git status` sauber): Glied 1-3 meldet "kein Foto vom Fenster", "0
Bedienelemente", danach faellt alles Weitere nach. Das ist **P-001 und
nicht O-009** -- diese Runde hat es nicht verursacht und raeumt es nicht
ab. Sobald P-001 traegt, misst 7b dasselbe noch einmal auf dem echten
Weg; der Code dafuer steht.

### ZUSTAND

**Die Sache selbst ist erledigt und gemessen** (12/0): der Schluessel
ueberlebt, sobald die Wurzel ueberlebt, und `jsig` wuerfelt ihn nicht
bei jedem Start neu. **Offen bleibt der Weg dorthin fuer den Stick** --
also P-001, die Installation auf Platte. `O-009` kann in `OFFEN.md` von
"haengt an P-001" auf "gemessen, wartet auf P-001 fuer den echten Weg"
gehen.

---

## SPEICHER

**Kein kdata gebraucht, kein Modusindex gebraucht.** Die Tafel liegt in
`lib/crypto/xts.fi` als Statik, nicht im Kernzustand. Die Zuteilung
0x138000..0x13A000 / Modus 1085..1087 ist unberuehrt, `MODE_WORDS`
bleibt 17.

    python3 tools/kernel/memmap.py
    129 Bereiche in 0x140000 Oktetten kdata, 12 Vektoren,
    245 Modusnamen in 17 Woertern, 0 Kollisionen

## ABNAHMEN

| Laeufer | Ergebnis |
|---|---|
| `tools/xtstafel/run.sh` (neu, K-022) | 6 / 0 |
| `tools/geraetekey/run.sh` (neu, O-009) | 12 / 0 |
| `tools/krypto/run.sh` | 61 / 0 |
| `tools/aesni/run.sh` | 31 / 0 |
| `tools/argon/run.sh` | 35 / 0 |
| `tools/check-ui.sh` | PASSED |
| `tools/build-kernel.sh` | baut (6076908 Oktette) |
| `tools/usbimg/build.sh` | erzeugt das Abbild |
| `python3 tools/kernel/memmap.py` | 0 Kollisionen |
