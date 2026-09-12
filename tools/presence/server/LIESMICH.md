# Die Serverseite von RUNDE PRÄSENZ

Diese zwei Dateien **laufen hier nicht** — sie liegen im JARVIS-Server:

```
/root/jarvis/lib/praesenzd.js          der Dienst
/root/jarvis/test/praesenzd.test.mjs   sein Prüfstand
```

Hier steht eine **Kopie zum Nachlesen**, damit die Runde vollständig in
einem Baum steht und ein Mensch, der `docs/PRAESENZ.md` liest, den Code
dazu findet, ohne das andere Repo zu kennen.

**Die Kopie ist nicht die Quelle.** Wer etwas ändert, ändert es in
`/root/jarvis` und kopiert danach hierher; andersherum wird nichts
eingespielt. Ein Verzeichnis, aus dem irgendwann jemand
zurückkopiert, ist ein zweiter Ursprung, und zwei Ursprünge laufen
auseinander.

Gefahren wird der Prüfstand mit:

```
node /root/jarvis/test/praesenzd.test.mjs
```

`tools/presence/run.sh` ruft genau diesen Pfad auf (Abschnitt 5..7) und
sagt es, wenn `node` fehlt, statt still grün zu sein.
