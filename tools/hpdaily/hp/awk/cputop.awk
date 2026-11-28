FNR == NR { ticks1[$1] = $3; next }
{
    delta = $3 - ticks1[$1]
    if (delta > 0) printf "%d %s %s %s\n", delta, $1, $5, $6
}
