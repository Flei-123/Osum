# Busy / message / progress API (`kernel/user/busy.fi`)

One import for every "tell the user / make them wait" case, as easy as a Windows MessageBox.
It sits on the modal dialog of `fuiscene` (same theme, light/dark, scale 1/2, corner radii) and takes
its texts from the message catalog (`msg.get`, keys `dialog.ok`, `dialog.cancel`).

Texts are pointers to NUL-terminated octets that must outlive the dialog.
Everything runs on the UI thread: a worker is a step function that returns quickly.

## Message box

    import busy
    busy.alert(title, text)

## Confirm (OK / Cancel)

    if busy.confirm(title, text) {
        delete_files()
    }

## Spinner (indefinite wait, optional Cancel button)

    busy.spinner(title, text, true)
    while !busy.cancelled() && more_work() {
        do_small_piece()
        let _c: bool = busy.tick()
    }
    busy.close()

## Progress (determinate 0..100, indeterminate with `busy.PCT_INDETERMINATE`)

    var i: u64 = 0
    while i < n {
        if busy.progress(title, text, (i * 100 / n) as i64, true) {
            break
        }
        copy_one(i)
        i = i + 1
    }
    busy.close()

`progress` opens the dialog on the first call, updates text and bar on later calls, runs one UI turn
and returns true once the user pressed Cancel (button, Enter or Esc).

## Run a worker under a dialog

    fn step(ud: u64) -> u64 {
        busy.report(40)
        if finished() {
            return busy.STEP_DONE
        }
        return busy.STEP_MORE
    }
    let r: u64 = busy.run(title, text, step, 0, 30000, true)

`run` calls `step` until it returns `STEP_DONE`, pumping the UI between calls. Results:
`RUN_OK`, `RUN_CANCELLED`, `RUN_TIMEOUT` (timeout in ms, 0 = none), `RUN_NO_WINDOW`,
`RUN_ERROR` (step returned another value, `busy.last_error()`).
A step that blocks for long freezes the spinner for that long: split the work, or call `busy.tick()` inside it.

## Layers

- `fuiscene.dialog_spin / dialog_busy / dialog_progress(PCT_INDET) / dialog_cancel / dialog_cancel_asked`: the dialog state.
- The spinner (12 dots) and the indeterminate bar are drawn from the clock; `pump` repaints every 33 ms
  only while such a dialog is open, nothing is drawn or woken when it is closed.
- Gate: `tools/busy/run.sh [light|dark] [scale]` (screenshots, serial markers; program `kernel/user/busydemo.fi`).
