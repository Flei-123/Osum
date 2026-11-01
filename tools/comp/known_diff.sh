KNOWN_BOX_X0=423
KNOWN_BOX_Y0=55
KNOWN_BOX_X1=430
KNOWN_BOX_Y1=62
outside_known() {
    grep -a '^wmd: cycle ' "$1" | awk -v X0=$KNOWN_BOX_X0 -v Y0=$KNOWN_BOX_Y0 -v X1=$KNOWN_BOX_X1 -v Y1=$KNOWN_BOX_Y1 '{
        d = 0; bb = ""
        for (i = 1; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "differ") d = kv[2]; if (kv[1] == "bbox") bb = kv[2] }
        if (d == 0) next
        n = split(bb, b, ",")
        if (n != 4 || b[1] < X0 || b[2] < Y0 || b[3] > X1 || b[4] > Y1) out += d
    } END { print out + 0 }'
}
