# w-ux-taskbar76
- Neighbour hover: tbhover.hover_brand skipped minimised window buttons (kver != 0) -> hover target 0, old card lingered, no card for the new app. Condition removed; gate step d (minimised terminal button shows card).
- Neighbour switch: taskview.preview_swap re-lays the card in place (no hide/show flash); tbpreview.keep_open uses it.
- Jump list: launch row of a running app reads "New window".
- Peek (hover thumbnail highlights real window): prototype taskpeek.fi works up to window creation, but the bar cannot open a 12th scene window (apphost.MAXWN 11, plus unknown shared-buffer/handle limit; bumping MAXWN/WN_LEN/DR_LEN/MAXWIN to 12 still gave "no peek window"). Removed from the branch. WM_THUMB is capped 480x320, so a real full-size peek needs a kernel change (wmthumb.THUMB_MAX_*, blockb row buffer) or a compositor-side peek.
