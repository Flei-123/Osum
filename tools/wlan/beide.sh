#!/usr/bin/env bash
# Hilfsskript der Runde WLAN-2: beide WLAN-Abschnitte hintereinander,
# im Hintergrund, mit Ergebnisdatei. Nur zum Messen waehrend der Runde.
cd "$(dirname "$0")/../.."
{
  echo "=== 42 (geerbt, Runde WLAN) ==="
  bash tools/wlan/run.sh 2>&1 | tail -4
  echo "=== 43 (neu, Runde WLAN-2) ==="
  bash tools/wlan/run2.sh 2>&1 | tail -4
  echo "=== FERTIG ==="
} > /tmp/wlan-beide.log 2>&1
