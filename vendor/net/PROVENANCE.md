# Woher der TCP/IP-Stack kommt

Osum schreibt den Stack aus Runde K3 **nicht ab**. Er benutzt ihn als
Abhaengigkeit, und zwar ueber genau den Mechanismus, mit dem auch der
Uebersetzer festgenagelt ist: `vendor/firn/COMMIT`.

## Der Weg, in einem Satz

`vendor/firn/fetch-firnc.sh` packt den Firn-Commit aus `COMMIT` aus und
kopiert **die ganze Firn-Bibliothek** dieses Commits nach
`vendor/firn/lib/`. Darin liegt `lib/net/`. Beide Uebersetzerstufen
suchen ein `import` zuletzt in `<Verzeichnis der Uebersetzerdatei>/../lib`
— also in `vendor/firn/lib/`. Damit findet

```firn
import net.wire
import net.tcp
import net.stack
```

im Kernel **den Stand aus `vendor/firn/COMMIT`** und sonst keinen. Es gibt
keine zweite Kopie im Repo, die auseinanderdriften koennte, und es gibt
keinen Pfad, ueber den versehentlich ein *neuerer* Firn-Stand
hereinkaeme: `$FIRNLIB` zeigt auf `<repo>/lib` (die libc dieses Repos),
und `<repo>/lib/net/` existiert absichtlich nicht.

## Der Stand, festgenagelt

| | |
|---|---|
| Firn-Commit | `c66c6bcd5f30d632d74e20facb6a5757c6043379` (`vendor/firn/COMMIT`) |
| `lib/net/wire.fi` | blob `0dd4c71cfd88424f0d1149f41342458468cd53bd`, 492 Zeilen |
| `lib/net/tcp.fi` | blob `201b5a3972d0e05bb5d6b74c4298e42f1732685d`, 1 555 Zeilen |
| `lib/net/stack.fi` | blob `136851a057d18cad35aeba10c59f9e6b83ba9426`, 599 Zeilen |
| entstanden in | Firn-Runde K3b, gemergt als `c8ce865` in Osums Historie |
| gemessen gegen | den Linux-Kernel ueber `veth` + `AF_PACKET`, `tools/k3net/run.sh` im Firn-Repo, 20 Zusagen |

Die drei Blob-Hashes stehen in `vendor/net/BLOBS` und werden in
Abschnitt 1 von `./test.sh` gegen die Dateien geprueft, die
`fetch-firnc.sh` wirklich ausgepackt hat — `git hash-object` rechnet
denselben Wert aus, den Firn im Baum stehen hat. Zieht jemand `COMMIT`
nach und der Stack hat sich dabei geaendert, faellt das dort auf und
nicht erst in einer Messung.

## Warum nicht kopieren

Zwei auseinanderdriftende Kopien desselben Codes sind in diesem Projekt
heute schon dreimal teuer geworden. Eine Kopie unter `lib/net/` waere
genau das gewesen: sie haette sich beim naechsten Fehler im Stack von der
Firn-Fassung entfernt, und danach waere bei jedem Unterschied unklar,
welche der beiden gemeint ist.

## Was Osum dazu selbst baut

Der Stack hat zwei Tueren nach unten (`net_input`, `net_output`) und
nichts darunter. Runde K8 baut das Darunter:

* `kernel/virtio.fi` — der virtio-net-Treiber (PCI, Merkmale, virtqueues,
  Unterbrechungen).
* `kernel/inet.fi` — die Naht: der Speicher fuer `stack.Stack`, die
  Pumpe zwischen Treiber und Stack, die Steckdosentabelle.
* `kernel/sys.fi` — die Systemaufrufe fuer Ring 3, mit den Nummern von
  Linux x86-64.
