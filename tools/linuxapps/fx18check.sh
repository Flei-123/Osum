#!/usr/bin/env bash
set -uo pipefail
SER=${1:?ser.clean of a guest-fx18-idle.sh run}
BUDGET=${FX18_BUDGET:-150}
FIRST=${FX18_FROM:-1}
awk -v budget="$BUDGET" -v first="$FIRST" '
/^FXS sample/ { s = $3; seen = 1 }
/^FXT / && seen && $3 > 8 && $6 != "awk" && $6 != "sleep" {
    k = $2
    if (s <= first) { base[k] = $4; next }
    if (!(k in base)) base[k] = 0
    use = $4 - base[k]
    if (!(k in top) || use > top[k]) { top[k] = use; name[k] = $6 " " $7 }
}
END {
    worst = 0; n = 0
    for (k in top) { n++; if (top[k] > worst) { worst = top[k]; wk = k } }
    if (n == 0) { print "red no thread samples"; exit 1 }
    if (worst > budget) { print "red", wk, name[wk], "used", worst, "ticks budget", budget; exit 1 }
    print "green worst", wk, name[wk], "used", worst, "ticks budget", budget
}' "$SER"
