#!/usr/bin/env bash
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
[ -f /tmp/echt.pid ] && osum_kill_tree "$(cat /tmp/echt.pid)"
sleep 2
rm -f /tmp/echt.log
rm -f /tmp/bridge2-echt/seriell.txt /tmp/bridge2-echt/server.log
setsid bash tools/bridge/echtserver.sh > /tmp/echt.log 2>&1 < /dev/null &
echo $! > /tmp/echt.pid
echo "gestartet: $!"
