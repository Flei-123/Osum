#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
LABEL="${1:?usage: ab.sh <label> <gateway> <download-url>}"
GW="${2:?usage: ab.sh <label> <gateway> <download-url>}"
URL="${3:?usage: ab.sh <label> <gateway> <download-url>}"
OUT="/tmp/ab-$LABEL.txt"
up() { cut -d' ' -f1 /proc/uptime; }
{
	echo "label=$LABEL"
	echo "start_uptime=$(up)"
	cat /proc/cmdline
	cat /proc/drivers
	n=0
	while [ $n -lt 120 ]; do
		grep -q 'auto=up' /proc/wlan && break
		sleep 1; n=$((n + 1))
	done
	echo "link_up_uptime=$(up) waited_s=$n"
	cat /proc/wlan
	ping -c 20 "$GW"
	t0=$(up)
	wget -O /dev/null "$URL"
	echo "download_rc=$? t0=$t0 t1=$(up)"
	cat /proc/wlan
	echo "end_uptime=$(up)"
} > "$OUT" 2>&1
echo "$OUT"
