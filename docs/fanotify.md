# fanotify

- `fs/fanotify.fi`: groups (4 KiB frame: 8 marks, 24-event queue), registry, tracked opens, `live()` guard (one counter read when no group exists).
- `sys/sysfanotify.fi`: fanotify_init (300, root only), fanotify_mark (301: ADD/REMOVE/FLUSH, MOUNT/FILESYSTEM as path-prefix marks, dirfd via at_enter1).
- Events: OPEN (do_open_mode), MODIFY (do_write, writev), CLOSE_WRITE/CLOSE_NOWRITE (file teardown), CREATE/DELETE/MOVED (inotify hook points in sysfile.fi). Read in sysfd.fi `fan_read` (24-byte metadata v3, event fd opened at read time, FAN_NOFD for entry events), poll/epoll in sysevent.fi.

## Limits
- No FID report modes, no permission events, no ignore masks, class NOTIF only. Mark and event paths are limited to 79 / 111 bytes.
- CLOSE events only for files opened while a matching mark existed (64 tracked opens).
