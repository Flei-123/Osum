#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/wasm2firn/wasi_ziehen.py -- RUNDE SCHLEUSE-2
#
# Zieht die WASI-Schicht AUS dem Deuter (kernel/app/wasm.fi) heraus und
# macht daraus das gemeinsame Modul, das Deuter UND AOT-Erzeugnis
# benutzen -- Auftrag Punkt 1, letzter Halbsatz.
#
# WARUM MECHANISCH UND NICHT VON HAND ABGESCHRIEBEN. Die 21 Funktionen
# sind in SCHLEUSE gegen SQLite erprobt worden, mit allen Fallstricken,
# die in STATUS-SCHLEUSE Abschnitt 6 stehen (der acht Oktett grosse
# iovec, EEXIST gegen den Rest, das Verzeichnis als SQLite-Sperre). Wer
# sie abschreibt, schreibt einen dieser Fallstricke wieder hinein.
# Deshalb: derselbe Text, nur die Anbindung an den Zustand getauscht.
#
# DER EINZIGE UNTERSCHIED zwischen beiden Welten ist, WO der lineare
# Speicher und die Argumente liegen:
#
#   im Deuter:  (*v).argc, (*(*v).m).mem   -- Felder einer VM-Struktur
#   im AOT:     wasi_argc, mem_p           -- Globale des Programms
#
# Genau diese Stellen werden ersetzt, sonst nichts.

import re
import sys

ERSATZ = [
    # Speicherzugriffe des Gastes: im AOT heissen sie mem_*, und sie
    # brauchen kein VM-Argument mehr.
    (r'\(\*\(\*v\)\.m\)\.mem', 'mem_p'),
    (r'mem_bound\(v, ([^,]+), ([^)]+)\)', r'mem_ok(\1, \2)'),
    (r'g_ld32\(v, ', 'mem_ld32('),
    (r'g_ld8\(v, ', 'mem_ld8('),
    (r'g_ld64\(v, ', 'mem_ld64('),
    (r'g_st32\(v, ', 'mem_st32('),
    (r'g_st8\(v, ', 'mem_st8('),
    (r'g_st64\(v, ', 'mem_st64('),
    (r'g_st16\(v, ', 'mem_st16('),
    # Argumente
    (r'\(\*v\)\.argv_von', 'wasi_argv_von'),
    (r'\(\*v\)\.argc', 'wasi_argc'),
    (r'\(\*v\)\.start', 'wasi_start'),
    (r'\(\*v\)\.spur', 'wasi_spur'),
    # iov-Hilfen ohne VM
    (r'iov_ptr\(v, ', 'iov_ptr('),
    (r'iov_len\(v, ', 'iov_len('),
    # Signaturen: das VM-Argument faellt weg
    # Signaturen JEDER Hilfsfunktion dieser Schicht, nicht nur der w_*
    (r'fn ([a-z_0-9]+)\(v: \*mut VM, ', r'fn \1('),
    (r'fn ([a-z_0-9]+)\(v: \*mut VM\)', r'fn \1()'),
    # und die Rufe darauf.
    #
    # NICHT MEHR EIN NAME JE HILFSFUNKTION. Hier stand
    # `pfad_holen\(v, ` -- ein getippter Name. Die Runde ENGLISCH hat
    # die Funktion in `path_get` umbenannt, diese Zeile blieb stehen,
    # und damit verlor die SIGNATUR ihr `v` (die Regel darueber greift
    # ueber den Namen hinweg), die RUFE aber nicht:
    #     error: function 'path_get' expects 3 argument(s), found 4
    # Die Pruefung stand danach auf 0 bestanden / 10 fehlgeschlagen.
    # Deshalb steht hier jetzt die BAUART und kein Name: jeder Ruf
    # `name(v, ` dieser Schicht verliert sein erstes Argument, genau
    # wie jede Signatur `fn name(v: *mut VM, `.
    (r'(?<![\w.])([a-z_][a-z_0-9]*)\(v, ', r'\1('),
]


def ziehen(quelle):
    lines = open(quelle).read().split('\n')
    start = next(i for i, l in enumerate(lines) if l.startswith('const E_OK'))
    end = next(i for i, l in enumerate(lines) if l.startswith('fn wasi_rufen'))
    txt = '\n'.join(lines[start:end])
    for pat, rep in ERSATZ:
        txt = re.sub(pat, rep, txt)
    if '(*v)' in txt or '*mut VM' in txt:
        rest = [l for l in txt.split('\n') if '(*v)' in l or '*mut VM' in l]
        raise SystemExit('nicht ersetzte VM-Zugriffe:\n  ' + '\n  '.join(rest))
    # DER WAECHTER, DER GEFEHLT HAT. Oben wurde nur nach `(*v)` und
    # `*mut VM` gesehen -- ein uebrig gebliebener RUF `name(v, ...)`
    # enthaelt beides nicht und kam still durch. Er faellt dann erst
    # dem Uebersetzer auf, und zwar in einer erzeugten Datei unter
    # /tmp, wo niemand die Ursache sucht. Also hier.
    uebrig = sorted(set(re.findall(r'(?<![\w.])([a-z_][a-z_0-9]*)\(v[,)]', txt)))
    if uebrig:
        raise SystemExit('Rufe mit VM-Argument nicht ersetzt: '
                         + ', '.join(uebrig))
    return txt


if __name__ == '__main__':
    sys.stdout.write(ziehen(sys.argv[1]))
