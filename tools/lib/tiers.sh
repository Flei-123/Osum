#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
DRIVER_TIERS=${DRIVER_TIERS:-native}
COMPAT_PACKAGES=${COMPAT_PACKAGES:-}

tiers_validate() {
    case "$DRIVER_TIERS" in
        native|native+compat) return 0 ;;
    esac
    echo "tiers: DRIVER_TIERS must be native or native+compat, got '$DRIVER_TIERS'" >&2
    return 2
}

tiers_allows_compat() {
    [ "$DRIVER_TIERS" = native+compat ]
}

tiers_conf_text() {
    printf 'tiers=%s\n' "$DRIVER_TIERS"
}

tiers_stage_args() {
    local out=$1 pkg name f
    tiers_validate || return 2
    case " ${USBIMG_EXTRA:-} " in
        *"/etc/drvstore.conf="*) ;;
        *)
            tiers_conf_text > "$out/drvstore.conf"
            echo "/etc/drvstore.conf=$out/drvstore.conf@0644"
            ;;
    esac
    tiers_allows_compat || return 0
    [ -n "$COMPAT_PACKAGES" ] && [ -d "$COMPAT_PACKAGES" ] || return 0
    echo /lib/drivers/
    for pkg in "$COMPAT_PACKAGES"/*/; do
        [ -f "$pkg/driver.inf" ] || continue
        name=$(basename "$pkg")
        echo "/lib/drivers/$name/"
        for f in "$pkg"/*; do
            [ -f "$f" ] && echo "/lib/drivers/$name/$(basename "$f")=$f"
        done
    done
}
