# `firnc1` bricht still ab — Ursache gefunden, und es ist keine Größengrenze

**Runde MERGE-10, 09.09.2026.** Betrifft `OFFEN.md` **D-019**.

## Was bisher im Befund stand

> **`firnc1` bricht still ab, wenn `wlib.fi` zu groß wird** — RC=1, keine
> Zeile stdout/stderr, 4 MB resident (also keine Wirtsknappheit, sondern
> eine feste Tabelle in firnc1). Trifft `netmon`, `freunde`, `powermon`.
> `firnc0` übersetzt dasselbe klaglos → fällt **nur** in K16 auf.

Daraus folgte die Sorge, hier liege eine Zeitbombe: jede Runde, die
`wlib.fi` wachsen lässt, könnte den selbstgehosteten Übersetzer kippen.
Runde ECHTHARDWARE-2 hat die Infoblase deshalb aus `wlib.fi` nach
`taskbar.fi` verschoben — eine Umgehung, keine Behebung.

## Was wirklich der Fall ist

**Es ist keine Größengrenze. Es ist eine fehlende Nachbardatei, und die
Meldung darüber fehlt.**

`wlib.fi` ist in dieser Runde von 212 048 auf 239 464 Oktett gewachsen
(der Merge von `explorer2` hat 734 Zeilen hinzugefügt). Es übersetzt sich
mit `firnc1` **fehlerfrei** — solange es an seinem Platz liegt:

```
$ cd /root/osum-merge9 && export FIRNLIB="$PWD/lib"
$ vendor/firn/bin/firnc1 -c -o /tmp/wlibtest.o kernel/user/wlib.fi
  RC=0, 1 063 392 Oktett Objektdatei
```

Dieselbe Datei, Oktett für Oktett dieselbe (`md5sum` stimmt überein),
aus einem anderen Ordner übersetzt:

```
$ cp kernel/user/wlib.fi /tmp/wlib.copy.fi
$ vendor/firn/bin/firnc1 -c -o /tmp/x.o /tmp/wlib.copy.fi
  RC=2, stdout 0 Oktett, stderr 0 Oktett
```

Die Größe ist in beiden Fällen gleich. Der Unterschied ist der **Ordner**.

### Der Beweis, was fehlt

`wlib.fi` hat in Zeile 57 ein `import ulib`, und die Suche danach läuft
zuerst **relativ zur importierenden Datei**. Legt man die Nachbarn dazu,
kippt der Fehler genau bei einer Datei um:

```
/tmp/mt3/  nur wlib.fi                   firnc1 RC=2
        +  wlibc.fi                      firnc1 RC=2
        +  msg.fi                        firnc1 RC=2
        +  ulib.fi                       firnc1 RC=0   <- hier
```

### Warum es niemandem auffiel: `firnc0` sagt es, `firnc1` schweigt

Derselbe Fehler, beide Übersetzer, dieselbe Quelle:

| Übersetzer | RC | stdout | stderr |
|---|---|---|---|
| `firnc0` (festgenagelt, auf dem Wirt) | 1 | 0 B | **volle Meldung** |
| `firnc1` (selbstgehostet) | 2 | 0 B | **0 B** |

`firnc0` schreibt:

```
error: cannot read '/tmp/mt4/ulib.fi': No such file or directory (os error 2)
   --> /tmp/mt4/wlib.fi:57:1
    |
 57 | import ulib
    | ^^^^^^ here
    = note: the search runs relative to the importing file, relative to
      '/tmp/mt4', in the sources of the project, in its dependencies,
      then in $FIRNLIB and in <directory of the compiler binary>/../lib
```

`firnc1` schreibt **nichts** und geht mit 2.

Dieselbe Messung für die drei Programme aus dem alten Befund — `netmon`,
`freunde`, `powermon` — ergibt Zeile für Zeile dasselbe Bild: `firnc1`
RC=2 ohne ein Oktett Ausgabe, `firnc0` RC=1 mit der genauen Zeile und dem
Namen der fehlenden Datei (`ulib.fi`).

## Was daraus folgt

1. **Die Zeitbombe gibt es nicht.** `wlib.fi` darf weiter wachsen; 239 KB
   übersetzen sich klaglos. Die Umgehung aus ECHTHARDWARE-2 (Infoblase
   nach `taskbar.fi`) war gegen die falsche Ursache gerichtet — sie
   schadet nicht, war aber nicht nötig.

2. **Der echte Mangel ist die fehlende Meldung.** Ein Übersetzer, der
   eine fehlende Datei mit RC=2 und null Oktett Ausgabe quittiert, kostet
   jeden, der darauf stößt, einen halben Tag — dieser Befund ist der
   zweite Anlauf auf dieselbe Stelle.

3. **`RC=1` im alten Befund war `firnc0`, nicht `firnc1`.** `firnc1` gibt
   2 zurück. Die beiden Läufe sind damals vermischt worden, und das ist
   der Grund, warum aus „Datei fehlt" eine „feste Tabelle" wurde.

## Was zu tun ist (nicht in dieser Runde)

Der Fehler liegt in `vendor/firn` und damit **nicht in diesem Baum** —
`vendor/firn/COMMIT` ist festgenagelt. Zu tun ist dort:

* `bin/firnc1.fi`: der Zweig, der eine nicht lesbare Importdatei
  behandelt, muss dieselbe Meldung schreiben wie `firnc0`. `firnc0` kann
  es, der Text steht in seiner Quelle — es ist kein neuer Text nötig,
  sondern derselbe an einer zweiten Stelle.
* Bis dahin gilt die Regel, die dieser Befund liefert und die in
  `tools/k16/run.sh` gehört: **`firnc1` mit RC=2 und leerer Ausgabe heißt
  „eine importierte Datei war nicht lesbar"** — und die Gegenprobe ist,
  dieselbe Quelle durch `firnc0` zu schicken, der den Namen nennt.

## Wie man es nachstellt

```bash
cd /root/osum-merge9
export FIRNLIB="$PWD/lib"

# geht:
vendor/firn/bin/firnc1 -c -o /tmp/a.o kernel/user/wlib.fi ; echo "RC=$?"

# geht nicht, dieselbe Datei, ohne ein Wort Erklaerung:
mkdir -p /tmp/q && cp kernel/user/wlib.fi /tmp/q/
vendor/firn/bin/firnc1 -c -o /tmp/b.o /tmp/q/wlib.fi ; echo "RC=$?"

# und so sagt es der andere Uebersetzer:
vendor/firn/bin/firnc  -c -o /tmp/c.o /tmp/q/wlib.fi ; echo "RC=$?"
```
