#!/usr/bin/env bash
# gate wrapper: OHCI tablet on the real desktop (see tools/usbhid/desktop.sh)
exec bash "$(dirname "$0")/../usbhid/desktop.sh" "$@"
