#!/usr/bin/env bash
# Startet echtserver.sh im Hintergrund und raeumt vorher auf.
# (Nur ein Starthelfer -- die Messung steht in echtserver.sh.)
cd "$(dirname "$0")/../.."
pkill -f 'tools/bridge/echtserver.sh' 2>/dev/null
pkill -f 'JARVIS_OSUM_PROBE' 2>/dev/null
sleep 2
rm -f /tmp/echt.log
rm -f /tmp/bridge2-echt/seriell.txt /tmp/bridge2-echt/server.log
setsid bash tools/bridge/echtserver.sh > /tmp/echt.log 2>&1 < /dev/null &
echo "gestartet: $!"
