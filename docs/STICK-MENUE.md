# Das Startmenue des Sticks -- die Begruendungen

Bis zum 24.09.2026 standen diese Absaetze als `#`-Kommentare IN der
`limine.conf` auf dem Stick und erschienen im Limine-Editor (Taste E) unter
jedem Eintrag. Seitdem liefert `tools/usbimg/build.sh` die Datei ohne
Kommentare aus; die Geschichte der Eintraege steht hier. Die alten deutschen
Titel sind die, auf die sich die Absaetze beziehen -- die heutigen Titel
stehen in der Tabelle unten.

## Zu `OrientOS -- Schreibtisch`

    limine.conf -- @MARKE_PRODUKT@ auf dem Stick (Runde USBIMG)

    DIE NAMEN, UND WARUM SIE HIER AUSEINANDERGEHEN (Runde MESSTAFEL).
    docs/ROADMAP-UPDATE.md:28 sagt es seit langem: der KERN und das
    SYSTEM darum sind zwei Namen. Auf dem Schirm stand trotzdem ueberall
    der des Kerns. Justins Vergleich trifft: der Kern heisst Linux, der
    Startschirm sagt Ubuntu -- niemand nennt seine Verteilung "Linux 6.8".

    Ab hier: was der BENUTZER liest, traegt den PRODUKTnamen aus
    marke.conf. Was den KERN meint, traegt den KERNnamen -- die Datei
    /osum.mb, das Startprotokoll, die Fassungszeile, die Panikmeldungen.
    Genau wie `Linux` im dmesg steht und nicht im Startbildschirm.

    RUNDE MARKE: in dieser Datei steht deshalb KEIN Produktname mehr,
    auch nicht im Kommentar. Ein Kommentar, der den alten Namen nennt,
    ist nach der ersten Umbenennung schlicht falsch -- und er stuende
    ausgerechnet in der Datei, die der Bau fuer jede Marke neu schreibt.
    `docs/NAMING.md` steht dem nicht
    entgegen: jenes Dokument regelt DEUTSCH GEGEN ENGLISCH in Pfaden und
    Anzeigetexten, nicht den Produktnamen.
    ================== RUNDE MENUE: VIER EINTRAEGE FUER MENSCHEN, DER REST
    EINE ETAGE TIEFER.

    Hier standen zehn gleichwertige Eintraege untereinander. Das war eine
    gewachsene TESTLISTE, keine Auswahl: wer den Stick in einen fremden
    Rechner steckt, will den Schreibtisch, und musste ihn zwischen
    Vektoreinheit, USB-Diagnose und zwei Aufloesungsvarianten suchen.

    Oben stehen jetzt die vier, die ein Mensch wirklich waehlt. Alles
    uebrige liegt unter "Werkzeuge und Diagnose" -- ein Baumeintrag, den
    Limine seit Fassung 8 kann (ein Eintrag OHNE `protocol`, dessen Kinder
    einen Schraegstrich mehr haben). Nichts ist weg, nichts hat eine
    andere `cmdline`; es ist reine Ordnung.

    WARTEZEIT 20 SEKUNDEN, und danach startet der Standardeintrag von
    selbst -- ein echter Countdown, kein Warten auf eine Taste. Das ist
    genau der Fall, um den es die ganze Runde geht: auf einem Brett, auf
    dem die Tastatur nicht antwortet, MUSS das Menue von allein
    weiterlaufen, sonst kommt man nie bis zum Schreibtisch.

    `default_entry: 1` zeigt jetzt auf den Schreibtisch. Vorher war es
    ebenfalls die 1 -- nur stand dort die Hardware-Diagnose, und die
    BLEIBT ABSICHTLICH STEHEN. Der Stick lief also nach zehn Sekunden von
    selbst in einen Bericht, der nie weitergeht.
    ==================================================== RUNDE LEISTE
    `dhcp` STEHT JETZT IM HAUPTEINTRAG.

    Justin will den JARVIS-Helfer auf dem Blech. Der braucht eine Route
    ins Internet, und `nip=169.254.10.1/16` ist eine
    VERBINDUNGSLOS-Adresse: kein Tor, kein Nameserver, kein Weg hinaus.
    `dhcp` startet /bin/dhcp in Ring 3, sobald der Schreibtisch steht.

    DIE FESTE ADRESSE BLEIBT TROTZDEM STEHEN, und das ist Absicht: sie
    gilt, bis der Klient etwas Besseres bekommt. Kommt kein Angebot
    (kein Kabel, kein Server, kein Treiber fuer den Chip), bleibt der
    Rechner genau so bedienbar wie vorher -- nur eben ohne Netz. Ein
    Schreibtisch, der auf ein DHCP-Angebot WARTET, waere ein Rueckschritt.

    Was danach auf der Tafel steht, beantwortet die Frage ohne serielle
    Leitung: Zeile 22 (NETZ) zeigt Treiber, Bus, Verbindung und die
    Adresse, die der Stapel wirklich fuehrt.
    ================================================ RUNDE ECHTHARDWARE-5
    `disp` MUSSTE AUF DIESE ZEILE, SONST IST DER HELLIGKEITSREGLER TOT.

    Justins Befund E: "Helligkeit und Lautstaerke gehen nicht, die Regler
    bewirken nichts."

    GEMESSEN, nicht vermutet. Der Regler laesst sich sehr wohl ziehen --
    das Kontrollzentrum meldet bei jedem Schritt einen neuen Wert --,
    aber JEDER Aufruf kam mit demselben Fehler zurueck:

    qs: hell auf =150 rc=-19        (-19 = ENODEV)

    -19 kommt aus `sysgui.do_dispset`, erste Zeile:

    if !vmode.ready(state) { return sys.neg(errno.E_NODEV) }

    und `vmode` wird nur bereit, wenn `vmode_stage` es untersucht --
    was es ausdruecklich nur tut, wenn das Wort `disp` auf der
    Befehlszeile steht (`vmode.want(state, vmode.M_DISP)`). Es stand
    hier nicht. Der ganze Bildschirmzweig -- Helligkeit, Kontrast,
    Gamma, Aufloesungswechsel -- war auf dem Stick damit abgeschaltet,
    und das Bedienfeld hatte keine Moeglichkeit, das zu wissen.

    GEGENPROBE, mittlere Bildhelligkeit ueber den ganzen Schirm, derselbe
    Zug am selben Regler:
    ohne `disp`:  18,78 -> 18,77 -> 18,76   (nichts passiert)
    mit  `disp`:  16,83 -> 13,44 -> 28,18   (dunkler, dann heller)

    Die Helligkeit ist dabei eine LUT im Rahmenpuffer und keine
    Hintergrundbeleuchtung -- sie wirkt auf das Bild, nicht auf die
    Lampe. Das ist ehrlich und sichtbar; eine echte Backlight-Steuerung
    braucht ACPI und ist eine eigene Runde.

    UND `audio` AUS DEMSELBEN GRUND. Die serielle Leitung sagte
    `aud: aus (kein Wort)` -- der Tonstapel wird nur aufgesetzt, wenn
    das Wort dasteht (kernel/kmain.fi, `w_aud`). Ohne ihn meldet das
    Kontrollzentrum folgerichtig `qs: vol ist=0`, graut die Beschriftung
    aus (T_DIM) und nimmt keinen Zug an -- das ist richtig und war
    trotzdem nicht das, was Justin wollte. Hat das Brett keine Karte,
    bleibt die Zeile grau; hat es eine, laesst sie sich ziehen.

## Zu `OrientOS -- Schreibtisch (Rahmenpuffer uncached, Test)`

    ================== RUNDE MESSTAFEL: DERSELBE EINTRAG AUF ENGLISCH

    Beide Textkataloge liegen im Abbild (`/usr/share/locale/de/messages`
    und `.../en/messages`, beide in der PFLICHT-Liste weiter oben). Was
    fehlte, war der Schalter: die Sprache stand fest in
    /users/root/config/locale, und das Einstellungsprogramm, das sie
    umstellen kann, braucht Maus oder Tastatur -- also genau das, was bei
    Justin klemmt. `lang=en` setzt die Datei VOR dem ersten
    Ring-3-Programm; sonst aendert sich an diesem Eintrag nichts.

    INTEGRATIONSRUNDE 19.09.2026: DIESER EINTRAG IST JETZT DER AUSWEG UND
    NICHT MEHR DIE AUSNAHME. Seit die Vorgabe wieder `de` ist (oben bei
    `locale-de`), faehrt der Schreibtisch-Eintrag ohne `lang=` deutsch --
    er nimmt, was in den beiden Dateien steht. DIESER Eintrag behaelt sein
    `lang=en` und ist damit der Weg zurueck zum Englischen, ohne Maus und
    ohne Einstellungsprogramm. Er wurde absichtlich NICHT angefasst.
    ================== RUNDE ZWISCHENSPEICHER: DER EINE EINTRAG, DER DIE
    FRAGE MIT EINEM FOTO ENTSCHEIDET

    Justins Rechner hat KEINE eingebaute Grafik: der Rahmenpuffer ist ein
    PCIe-Fenster der RTX 3060. Er war bis zu dieser Runde WRITE-BACK
    abgebildet -- kleine Aenderungen (Taskleiste, Messtafel, ein Fenster)
    bleiben dann in der Zwischenspeicherhierarchie der CPU liegen und
    gehen nie ueber PCIe zur Karte. Nur das erste Vollbild (19,8 MB, mehr
    als jeder L3) verdraengt sich selbst und wird sichtbar. Genau das
    zeigt sein Foto: blauer Grund und Zeiger, sonst nichts.

    Der Kern bildet den Puffer seit dieser Runde write-combining ab. DIESER
    Eintrag ist die GEGENPROBE mit dem groebsten Mittel: `fbuc` schaltet
    den Zwischenspeicher fuer das Fenster ganz ab (PCD|PWT). Das ist
    langsam -- jeder Bildpunkt geht einzeln auf den Bus --, aber es kann
    per Bauart nichts liegenbleiben.

    ERSCHEINEN HIER TASKLEISTE, TERMINALFENSTER UND MESSTAFEL, waehrend
    sie im ersten Eintrag fehlen, dann ist die Ursache bewiesen und es
    war die Abbildungsart. Erscheinen sie auch hier nicht, ist sie
    widerlegt und der Fehler liegt woanders.

## Zu `OrientOS -- Schreibtisch (Cache leeren je Bild, Test)`

    ============ RUNDE BLECHEINGABE: DER ZWEITE, UNABHAENGIGE BEWEIS

    `fbuc` bildet den Rahmenpuffer ohne Zwischenspeicher ab -- eine andere
    ABBILDUNG. `fbflush` laesst die Abbildung, wie sie ist (write-combining
    seit der Vorrunde), und raeumt nach jedem Blit den ganzen
    Zwischenspeicher mit `wbinvd` hinaus. Zwei verschiedene Mittel gegen
    DIESELBE Ursache: hilft eines von beiden und das erste nicht, lag es am
    Zwischenspeicher. Hilft keines, lag es woanders -- und dann sagen die
    zwei Herzschlagfelder am rechten Bildrand, wo.

## Zu `OrientOS -- Schreibtisch (Rahmenpuffer write-back, Test)`

    ============ RUNDE BLECHZWEI: DER DRITTE VERGLEICHSFALL

    GEMESSEN, Vollbild-Blit in QEMU, alle drei Betriebsarten mit
    demselben Kern und derselben Aufloesung:

    write-combining (Vorgabe)   1 751 us   PDE 10E3
    write-back      (`fbwb`)    3 402 us   PDE 00E3
    uncached        (`fbuc`)  396 531 us   PDE 00FB

    UC ist 226-mal langsamer als WC. Der Eintrag ist deshalb AUSDRUECKLICH
    ein Messeintrag und kein Betriebsmodus -- er macht das Bild sichtbar,
    aber der Rechner verbringt seine Zeit im Bildspeicher. `fbwb` ist die
    dritte Ecke des Dreiecks: schnell, aber es kann liegenbleiben.

## Zu `OrientOS -- Schreibtisch (Diagnose: Lampe und Blinkfelder)`

    ============================================ RUNDE BLECHFUENF
    DER DIAGNOSE-EINTRAG, UND WARUM ER EIN EIGENER IST.

    Justin hat gemeldet, dass an seiner Tastatur die Lampen DAUERND
    blinken und Nummernfeststell sich nicht mehr schalten laesst. Das war
    der LED-Herzschlag aus der Runde BLECHVIER: er legt zweimal je Sekunde
    die Rollen-Lampe ueber den Tastenzustand. Als Messgeraet hat er seine
    Frage beantwortet (der Zeitgeber laeuft, HZ 99); als Dauerzustand
    macht er die Feststelltasten unbrauchbar. Dasselbe gilt fuer die zwei
    blinkenden Kaestchen am rechten Bildrand, die er fuer einen
    Zeichenfehler gehalten hat.

    Beides haengt jetzt an `pulsled` und ist in den Schreibtisch-
    Eintraegen AUS. Hier ist es an -- fuer den Fall, dass wieder einmal
    ohne Bild und ohne serielle Leitung entschieden werden muss, ob
    ueberhaupt noch etwas laeuft.

## Zu `OrientOS -- Hardware-Diagnose (bleibt stehen)`

    ============ RUNDE BLECH-HID: DER NETZ-SELBSTLAUF, OHNE EINE TASTE

    Der Eintrag, den Justin am 03.09.2026 gebraucht haette und nicht
    hatte. Der Stick startete, zeigte ein Bild -- und nahm keine Eingabe
    an; damit war jeder der 52 Befehle auf dem Abbild unerreichbar.

    `netlauf` gibt der Shell `/etc/netlauf.sh` als Argument mit
    (`kernel/kmain.fi`, Abschnitt `osum`), sie faehrt es von oben nach
    unten -- `dhcp`, `resolv.conf`, `host store.fleitec.com`,
    `fetch https://store.fleitec.com/index.json`, `ota suchen` -- und
    danach BLEIBT DER BILDSCHIRM STEHEN (`hwdiag.park_after_shell`). Ein
    Foto davon ist die erste Messung des Netzwegs auf echtem Blech.

    `usb hidgen` steht mit drin, obwohl niemand tippen muss: findet der
    Baum Tastatur und Maus, sagt der Bericht das mit -- und dann weiss
    Justin im selben Foto, ob die Uebernahme dieser Runde greift.

## Zu `Werkzeuge und Diagnose`

    ================== RUNDE BLECH-HID: DIE USB-DIAGNOSE, DIE ANFASST

    Eintrag 1 darueber bleibt Oktett fuer Oktett, wie er war -- er haelt
    VOR jedem Treiber an und ist damit der Eintrag, der auf JEDER Maschine
    bis zum Bericht kommt. Er hat seit dieser Runde eine LESENDE
    USB-Uebersicht am Ende (`usb: regler=`, je Regler eine Zeile mit
    `besitz=BIOS|OS|frei`, `strom=`, `verbunden=`).

    DIESER Eintrag hier geht weiter: er nimmt der Firmware die Regler ab
    (`usb`), zaehlt auf, prueft die Uebernahme an einer gebauten
    Faehigkeitsliste (`usbleg`) und haelt danach an (`usbstop`). Was dabei
    gedruckt wird, ist der volle Bericht -- je Regler die
    Halbleiter-Semaphore vor und nach der Uebernahme, HCRST, und dann
    jeder Anschluss einzeln mit PP, CCS, PED, PR und Tempo.

    WARUM ZWEI EINTRAEGE UND NICHT EINER: der erste fasst nichts an und
    kann deshalb nicht haengen. Wenn dieser hier auf einem fremden Brett
    stehenbleibt, ist der andere immer noch da.
    ------------------------------------------------------------------
    DER BAUMEINTRAG. Er hat selbst KEIN `protocol` -- genau daran
    erkennt Limine ein Untermenue statt eines Starteintrags.

    ZU DEN ZWEI AUFLOESUNGSEINTRAEGEN, und warum sie NICHT verschwinden:
    Justins Vorschlag war, die Aufloesung einfach von der Firmware
    uebernehmen zu lassen. Das tut der Lader bereits -- alle Eintraege
    ohne `resolution:` bekommen, was die Firmware anbietet, und auf
    Justins 3440x1440 ist das richtig. Es ist nur NICHT verlaesslich:
    gemessen (docs/SCHIRM.md, "Unter dem Lader") gibt derselbe Lader auf
    einem 3840x2160-Schirm von sich aus 1280x800. Nach
    ExitBootServices gibt es kein GOP mehr, der Kern kann das also nicht
    nachbessern. Wer auf so einem Schirm ein scharfes Bild will, muss den
    LADER waehlen lassen -- deshalb bleiben die zwei Eintraege. Sie
    gehoeren nur nicht ins Hauptmenue.

## Zu `OrientOS -- USB-Diagnose: Regler und jeder Anschluss`

    RUNDE STICK: DIESER EINTRAG HAT JETZT AUCH EINE NETZKARTE. Ohne
    `nic` blieb der Schreibtisch fuer immer bei "kein Netz", und das
    Terminal darin konnte `dhcp` nicht fahren -- der Stapel stand gar
    nicht. Die Adresse ist dieselbe verbindungslokale Platzhalteradresse
    wie im Kommandozeilen-Eintrag; `dhcp` ersetzt sie.

## Zu `OrientOS -- Vektoreinheit pruefen (bleibt stehen)`

    RUNDE SCHIRM: ZWEI EINTRAEGE FUER GROSSE SCHIRME.

    GEMESSEN: auf einem 3840x2160-Schirm gibt der Lader dem Kern von sich
    aus 1280x800 (docs/SCHIRM.md, Abschnitt "Unter dem Lader"). Der Kern
    kann das NICHT nachbessern -- nach ExitBootServices gibt es kein GOP
    mehr, und der Bochs-Weg, ueber den er ohne Lader den Modus setzt, ist
    auf echter Hardware nicht da. Wer den Modus will, muss ihn den LADER
    waehlen lassen, und genau das tun diese zwei Eintraege.

    Passt die Aufloesung dem Bildschirm nicht, faellt Limine auf seine
    Vorgabe zurueck; es bleibt also immer ein Bild.

## Zu `OrientOS -- Grafik erheben (bleibt stehen)`

    =============== RUNDE MERGE-11: DIE GRAFIK-ERHEBUNG ALS MENUEEINTRAG

    JUSTIN SOLL NICHTS TIPPEN MUESSEN. Die Erhebung aus GRAFIK-1 Etappe A
    beantwortet eine Frage, die seit Tagen offen ist: auf echtem Blech
    sieht er eckige Fenster, groben Bildbrei und einen klotzigen Zeiger,
    waehrend der Pruefstand in QEMU saubere runde Ecken MISST (VEKTORs
    Eckenmesswerkzeug: 0 Fuellpixel ausserhalb des Radius). Beides kann
    nicht gleichzeitig stimmen -- es sei denn, zwischen dem gezeichneten
    Bild und der Tafel liegt noch eine Streckung.

    Genau die zeigt die Zeile `weg`:

    grafik: weg tafel=AxB bild=CxD gezogen=JA/NEIN pitch=../..

    `gezogen=JA` heisst: es wird ein KLEINERER Puffer gerendert und vom
    Anzeige-Controller mit naechstem Nachbarn hochgestreckt. Dann sind
    alle drei Beschwerden EINE Ursache, und eine Rundung von drei
    Bildpunkten ueberlebt so eine Streckung nicht. `gezogen=NEIN`
    schliesst den Verdaechtigen aus, und wir suchen woanders -- auch das
    ist ein Ergebnis, und es kostet Justin einen Tastendruck statt einer
    weiteren Woche.

    `hwdiagstop` haelt das Bild an, damit er es abfotografieren kann;
    `nokbd`/`noring3` halten alles heraus, was das Bild ueberschreiben
    koennte. Die Erhebung FASST NICHTS AN: kein Register wird
    geschrieben, kein Modus gesetzt (kernel/grafik.fi, `bericht`).

## Zu `OrientOS -- Schreibtisch, Ring 3 nur Kern 0 (Rueckfall)`

    ================= RUNDE VIELKERN 3: DER EINTRAG FUER DAS BLECH

    Bis zur Runde BLECHKERN lief die ganze Oberflaeche auf EINEM Kern --
    nicht aus Bequemlichkeit, sondern weil `syscall_entry` den Kernstapel
    aus einem Wort fuer die ganze Maschine holte. Justins Foto vom 05.09.
    (`VEK 6 #UD RIP 0x80`, Kern 2) ist genau das gewesen.

    Der Unterbau dafuer steht seit VIELKERN 1 (Kernstapel je Kern ueber
    die GS-Basis), und seit VIELKERN 3 kommt auch der volle Schreibtisch
    damit hoch -- die zweite Ursache war ein Inodepuffer fuer die ganze
    Maschine (`fs.inode_get`), der nur solange hielt, wie nie zwei Kerne
    gleichzeitig hinsahen.

    GEMESSEN IST DAS BISHER NUR IN QEMU (-smp 1, 4 und 8). DIESER EINTRAG
    IST DIE MESSUNG AUF BLECH, und er ist deshalb ein EIGENER Eintrag und
    keine Aenderung am Schreibtisch darueber: geht etwas schief, nimmt
    man den anderen.

    WAS AUF DEM SCHREIBTISCH-EINTRAG ZU FOTOGRAFIEREN IST -- Tafelzeile 23,
    unten rechts:

    23 SAFETY WA 0 KS <n> R3W 0 R3K <n> LG 0

    R3K   auf WIE VIELEN Kernen Ring 3 wirklich gelaufen ist. Auf
    Justins Brett muss dort etwas GROESSER ALS 1 stehen; steht
    dort 1, hat kein Anwendungskern einen Prozess bekommen.
    R3W   Kerne, deren GS-Basis NICHT auf ihren eigenen Satz zeigt.
    MUSS 0 sein. Steht dort etwas anderes, hat der Riegel in
    `sched.darf_ring3` gegriffen und Ring 3 auf Kern 0 gehalten
    -- die Maschine lebt dann, aber die Runde ist nicht erfuellt.
    WA    Ueberlauf einer Kernstapel-Waechterseite. MUSS 0 sein.

    Und Zeile 7 (LEISTE) sagt, ob der Schreibtisch dabei wirklich malt.
    DER SCHREIBTISCH-EINTRAG GANZ OBEN BRAUCHT DAFUER KEIN WORT MEHR:
    seit VIELKERN 3 ist Ring 3 auf allen Kernen die VORGABE. Was hier
    steht, sind die beiden Eintraege, mit denen sich das ueberpruefen und
    zurueckdrehen laesst.

    DIE RUECKFALLEBENE. `r3eins` haelt Ring 3 auf Kern 0 -- Oktett fuer
    Oktett das Verhalten der Runde BLECHKERN. Wenn der Schreibtisch mit
    allen Kernen auf diesem Brett nicht so laeuft wie mit einem, ist das
    der Eintrag, der es beweist: derselbe Kern, dieselbe Wurzel, ein Wort
    Unterschied.

## Zu `OrientOS -- Gegenprobe: falsche GS-Basis (Riegel haelt?)`

    Und die GEGENPROBE dazu, auf demselben Stick: `gsluege` gibt jedem
    Anwendungskern eine FALSCHE GS-Basis. Der Riegel MUSS das sehen und
    Ring 3 auf Kern 0 halten -- auf der Tafel steht dann `R3W` groesser
    null und `R3K 1`, UND DIE MASCHINE LAEUFT WEITER. Das ist derselbe
    Nachweis, den tools/multicore/run.sh in QEMU fuehrt, nur auf Blech.
    (`r3blind` gibt es auf dem Stick absichtlich NICHT: das ist der
    Eintrag, der die Maschine mit Absicht umbringt, und der gehoert in
    den Pruefstand und nicht in die Hand eines Menschen vor einem
    echten Rechner.)

## Zu `OrientOS -- Schreibtisch auf einem WQHD-Schirm (2560x1440)`

    RUNDE STICK: DIE KOMMANDOZEILE MIT NETZ.

    Bis hierher konnte man auf dem Stick nur ZUSEHEN: Diagnose oder
    Schreibtisch. Es gab keinen Eintrag, in dem ein Mensch `dhcp`,
    `host`, `fetch`, `ota` oder `jarvisd` tippen kann -- und das waren
    genau die Programme, die auch nicht drauf waren.

    `nic` schaltet die Karte ein. WARUM DA TROTZDEM EINE ADRESSE STEHT,
    obwohl `dhcp` sie holen soll: `netsvc` startet den Stapel nur, wenn
    `nip=` etwas nennt -- ohne sagt der Kern "kein Netz im Kernel" und
    `/bin/dhcp` hat nichts, worauf es einen Socket aufmachen koennte
    (gemessen, 03.09.2026). 169.254.10.1/16 ist eine
    VERBINDUNGSLOKALE Adresse (RFC 3927): sie kollidiert per Definition
    mit keinem Heim- oder Firmennetz, und der erste `dhcp` ersetzt sie.
    `console=ttyS0` macht COM1 zu einem richtigen Terminal (Runde
    SERVERBUILD, kernel/sercon.fi): auf einem Server ohne Tastatur ist das
    der einzige Weg herein, und das Warten auf eine Zeile wird damit
    unbegrenzt statt vier Sekunden. Die PS/2- und USB-Tastatur laufen
    daneben weiter.

    osum$ dhcp
    osum$ host store.fleitec.com
    osum$ fetch https://store.fleitec.com/index.json
    osum$ ota suchen
    osum$ jarvisd -n

