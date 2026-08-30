# /bin/update -- RUNDE UPDATE: der Ablauf am Stueck.
#
#     update <name> <quelle>
#
# <quelle> ist ein Verzeichnis, in dem INDEX, INDEX.sig und die
# .opk-Dateien liegen -- entweder eingehaengt, oder von `/bin/fetch`
# ueber HTTPS dorthin geholt (siehe unten).
#
# WAS HIER PASSIERT, UND IN GENAU DIESER REIHENFOLGE:
#
#   1. NACHSEHEN, WAS LAEUFT.       opk liste
#   2. HOLEN UND PRUEFEN.           opk aktualisieren <name> --quelle <q>
#      Darin steckt die ganze Kette: die Ed25519-Signatur ueber den
#      INDEX, der Streuwert aus dem INDEX gegen die Oktette des Pakets,
#      und die Ed25519-Signatur ueber das Paket selbst. Faellt eines
#      davon durch, passiert NICHTS -- kein Store-Eintrag, keine
#      Generation, kein Umschalten.
#   3. DIE NEUE GENERATION steht danach in Erprobung; `opk` hat
#      `/system/ERPROBUNG` geschrieben.
#   4. NEU STARTEN. Der Kern zaehlt den Versuch hoch (`kernel/ab.fi`).
#   5. BEIM NAECHSTEN START: laeuft es, wird bestaetigt
#      (`opk erprobung ok`); laeuft es nicht, faellt der Kern nach drei
#      Versuchen von selbst auf die vorige Generation zurueck.
#
# DIE HTTPS-SEITE. `/bin/fetch` (Runde HWNET) holt eine Datei ueber TLS
# 1.3 mit Kettenpruefung. Der Aufruf sieht so aus und steht hier als
# Kommentar, weil dieses Skript die Quelle als Verzeichnis bekommt und
# nicht als URL -- was fehlt, ist die Namensaufloesung, und das steht in
# docs/UPDATE.md unter "was noch fehlt":
#
#     fetch -n pkg.example.org -o /tmp/q/INDEX     https://<ip>/INDEX
#     fetch -n pkg.example.org -o /tmp/q/INDEX.sig https://<ip>/INDEX.sig
#     fetch -n pkg.example.org -o /tmp/q/x.opk     https://<ip>/x.opk
#     fetch -n pkg.example.org -o /tmp/q/x.opk.sig https://<ip>/x.opk.sig
#     update x /tmp/q
opk liste
opk aktualisieren $1 --quelle $2
opk erprobung
