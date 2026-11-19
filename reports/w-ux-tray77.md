# w-ux-tray77 (interim)

- Clock, bell and Win+N now open ONE flyout (`kernel/user/calpop.fi`): notifications on top (cards, per-row dismiss, row actions, "Clear all", do-not-disturb switch), month calendar below (today marked, month switch, events, contacts).
- `kernel/user/notify/notifc.fi` lost its own window: it is now the list model (`load/rows/click/clear_all/report*`) used by calpop; the bell, Win+N and clock all call `tbpaint.flyout_toggle`.
- `qs.toggle_dnd` exported (one switch for the quick-settings tile and the flyout).
- Merged main ee48face4. Gates: features 17/0, hotnote 15/0, notecard 4/0 (x2 scales), calpop 24/0, english 5/0.
