# ECHTHARDWARE-5 -- Arbeitsstand

## FERTIG UND BELEGT
- B TERMINAL LEER: Ursache = `prompt()` lief NACH `get_line()`; eine Shell,
  auf die niemand tippt, haengt fuer immer im Lesen -> nie eine
  Eingabeaufforderung. Gemessen mit neuen Zaehlern TO/TP (Tafel Zeile 0):
  vorher TO16 TP16 (nur "sh: ready, osum\n"), nachher TO86 TP86.
  Tinte im Fenster 0.5% -> 2.21% (Prompt) -> 3.43% (nach `ls`).
  Fix in kernel/user/sh.fi.
- D GROESSE NUR RECHTS: Ursache zweiteilig. (1) `on_mouse` nahm nur
  `am_rechts || am_unten` an. (2) Die Titelleistenpruefung `lokal_y < 0`
  stand VOR der Kantenpruefung und fing die obere Kante immer ab.
  (3) `resize_win` rechnet aus der linken oberen Ecke -- links/oben ging
  damit prinzipiell nicht. Neu: Bitmaske S_SZEDGE + Anker S_SZAX/S_SZAY,
  Kantenpruefung VOR der Titelleiste, Klemmung am Schirmrand.
  BELEGT: k=1,2,4,8 und Ecken k=5 (links+oben), k=10 (rechts+unten).
- J THEMA WIRKT NICHT AUF OFFENES: `qs.fi` hat eine EIGENE Schleife und
  ruft `wlib.step()` nie -- also auch `theme_watch()` nie. Die Leiste
  pollte das Thema bereits, behielt es aber fuer sich. Neu:
  `qs.thema_neu()`, gerufen aus dem theme_poll-Zweig der Leiste.

## URSACHE BELEGT, FIX OFFEN
- F TASKMGR/EINSTELLUNGEN GEHEN NICHT AUF: `/bin/taskmgr` ist im
  AUSGELIEFERTEN ABBILD NICHT VORHANDEN. Nachgewiesen mit
  `python3 tools/osum/mkfs.py list` auf der Wurzelpartition von
  orientos-usb-20260910-44a5af3.img: 177 Inoden, kein /bin/taskmgr.
  `qs.fi:1316` startet genau diesen Pfad. Fix = PROGS in
  tools/usbimg/build.sh ergaenzen.

## NOCH ZU TUN
- A Suchfenster dunkel/tot (im Nachbau NICHT reproduziert: tippen geht,
  Farben sind dunkel -- Unterschied zur echten Maschine suchen)
- C Zeichenartefakte beim Verschieben
- E Helligkeit/Lautstaerke
- G Ringpuffer VERL/KOAL
- H zwei rote Zeilen erklaeren
- I DNS/HTTPS pruefen
