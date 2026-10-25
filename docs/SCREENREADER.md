# Screen reader (P-016, round SR-1)

`/bin/screenreader serve [ticks] [silent]` (root) reads the a11y tree (docs/A11Y.md) and speaks the focused control:
`<name>, <role>, <state>`; a new window is announced first (`Notes, window. Save, button`). `screenreader say <text>` speaks a text.

Layers: `lib/fui/speaktext.fi` (node -> text) · `lib/audio/speechlang.fi` (language registry en/de) · `lib/audio/speechphon.fi` / `speechphon_de.fi` (letters -> phonemes, `phonbuf.fi` = inventory) · `lib/fui/speakwords.fi` (role/state words per language) · `lib/audio/speech.fi` + `speechdsp.fi`
(integer formant synthesizer, 16 kHz S16LE stereo, rough English-like voice, digits are spoken) · `kernel/user/screenreader.fi` (events -> mixer).

Security: grants itself `P_READ` only (never `P_ACT`), right falls at exec; only role, state and NAME are spoken, never a node value; password
fields say name + "protected"; value events of entries/passwords/sliders/scroll bars are dropped (no typing echo); locked screen = kernel drops events.

Gate: `bash tools/screenreader/run.sh` (host, seconds): 33 checks (texts, canary, phoneme rules, pitch, formants, hiss, capacity) + 3 counter-proofs.
Guest gate: `bash tools/srguest/run.sh` (QEMU intel-hda + audiodev wav, a11ydemo, sendkey tab): announcements on serial, password rule, WAV not silent, counter-proofs `serve silent` and no sound device.
German: rule based (umlauts, ß, ich/ach-Laut, sch, st/sp, ei/eu/au, vowel length, final devoicing, numbers 0-9999); language = `msg.read_lang` (user locale, then /etc/locale.conf, else en). Heuristic: compounds and loanwords are wrong, intelligibility only measured, not heard.
Switch (r1990): `/etc/screenreader.conf` holds `enabled=0|1` (live) and `autostart=0|1` (at server start `enabled` is set to it; no `autostart` key = legacy, starts on).
Settings > Display rows "Screen reader" / "Screen reader at start" write it at once (module `srconf`); `screenreader toggle` flips `enabled`; the server polls the file every 0.3 s and announces `Screen reader on|off` (off = no tree read, no speech).
Hotkey Ctrl+Alt+N -> hotkeyd -> bus action `screenreader.toggle` (provider `a.screenreader` in the serve process, `etc/actions.d/screenreader.actions`, right `hotkey` in apprights.conf). Ctrl+Alt+R/F/J/L/S are taken. usbimg starts `screenreader serve` through `/etc/wmplug.autostart`.
Open: reading by caret/word; terminal is not in the tree; Braille.
