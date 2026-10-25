# Screen reader (P-016, round SR-1)

`/bin/screenreader serve [ticks] [silent]` (root) reads the a11y tree (docs/A11Y.md) and speaks the focused control:
`<name>, <role>, <state>`; a new window is announced first (`Notes, window. Save, button`). `screenreader say <text>` speaks a text.

Layers: `lib/fui/speaktext.fi` (node -> text) · `lib/audio/speechphon.fi` (letters -> phonemes) · `lib/audio/speech.fi` + `speechdsp.fi`
(integer formant synthesizer, 16 kHz S16LE stereo, rough English-like voice, digits are spoken) · `kernel/user/screenreader.fi` (events -> mixer).

Security: grants itself `P_READ` only (never `P_ACT`), right falls at exec; only role, state and NAME are spoken, never a node value; password
fields say name + "protected"; value events of entries/passwords/sliders/scroll bars are dropped (no typing echo); locked screen = kernel drops events.

Gate: `bash tools/screenreader/run.sh` (host, seconds): 33 checks (texts, canary, phoneme rules, pitch, formants, hiss, capacity) + 3 counter-proofs.
Open: guest gate with QEMU HDA wav capture; German voice; reading by caret/word; terminal is not in the tree; Braille.
