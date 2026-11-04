# BEFUND: der Name eines Plugins ist fuenfzehn Oktette lang, immer

Gemessen im Modul `verwaltung` der Runde WMPLUGIN, an einem wirklich
gebooteten Kern (`gfx wm wmplug wmshell ...`, Exitcode 21, Protokoll
`/tmp/verw/ser2.txt`). Der Befund gehoert nicht mir allein, deshalb
steht er hier und nicht nur in meinem Commit.

## Was passiert ist

`WM_PLUG_REG` (2117) holt sich den Namen mit fester Laenge:

```
kernel/sysgui.fi:1910   if name != 0 && !sys.copy_in(state, me, puffer, name, 15)
```

`kernel/user/pluguhr.fi` legt den Namen in ein `[u8; 4] = "uhr\0"`. Der
Kern liest also elf Oktette weiter -- und was dort stand, war das
naechste Stueck Ring-3-Stapel. Auf der seriellen Leitung:

```
osum$ pluguhr runden=30 takt=300 still &
wmplug: reg uhr rund platz=0 rechte=0x1f
```

Das Plugin heisst im Kern `uhr\0rund…`. Zwei Folgen, beide gemessen:

1. **`wmplug enable uhr` traf ins Leere.** `wmplug.grant_lookup`
   vergleicht `NAME_LEN` Oktette; der saubere Name aus `/etc/wmplug.conf`
   ist nicht derselbe wie der verschmutzte aus der Anmeldung. Die Rechte
   blieben bei `0x1F`, obwohl `WM_PLUG_GRANT` 0 zurueckgab.
2. **`wmplug info uhr` fand nichts**, weil `PL_NAME` (acht rohe Oktette)
   nicht zum getippten Namen passte.

## Was ich in meinem Modul getan habe

`/bin/wmplug` vergleicht Namen jetzt **bis zum ersten Null-Oktett** und
nicht ueber acht rohe Oktette (`namen_gleich`, kernel/user/wmplug.fi).
`list` und `info` finden ein so angemeldetes Plugin damit wieder.
Ausserdem fuellt `wmplug` seinen eigenen Namenspuffer vor
`WM_PLUG_GRANT` ausdruecklich mit Nullen.

## Was das NICHT repariert

Die Gewaehrung im Kern (`wmplug.grant_lookup`, 15-Oktett-Vergleich)
bleibt betroffen: solange ein Plugin einen verschmutzten Namen anmeldet,
kann `enable` seine Rechte nicht treffen. Zwei Wege, beide ausserhalb
meiner Dateien:

* **Plugin-Seite** (Module `widget`, `regel`, `gegenprobe`): den Namen in
  einem Puffer von 16 Oktetten fuehren und mit Nullen fuellen. Das ist
  die ABI, so wie sie im PLAN steht (`name*15`).
* **Kernseite** (Modul `kern`): in `reg`/`grant` nach dem ersten
  Null-Oktett den Rest des Puffers nullen. Eine Schleife ueber 15
  Oktette, keine Rekursion -- und danach kann kein Plugin mehr einen
  Namen anmelden, den niemand tippen kann.

Der Beleg dafuer, dass `enable`/`disable` mit einem SAUBEREN Namen
durchgaengig wirken, steht in meinem Commit: mit einem Stummel, der 16
Nullen vorlegt, zeigt `wmplug list` `0x01F` vor `enable`, `0x807`
danach, `0x000` nach `disable` -- und das laufende Plugin sieht denselben
Wechsel in seinem eigenen `PL_RIGHTS`.
