# SPDX-License-Identifier: GPL-2.0-only
# Sourced by run.sh and herkunft.sh.

BUILD_SCRIPT=${BUILD_SCRIPT:-tools/usbimg/build.sh}

unguarded_musl_lines() {
    awk '
        /^[[:space:]]*#/ { next }
        /^BBLIBC=/ || /^\[ -r "\$BBLIBC" \]/ { next }
        /^if \[ "\$BBSH" = 1 \]; then/ { guarded = 1; next }
        /^fi/ { guarded = 0; next }
        /ld-musl/ && !guarded { print NR ": " $0 }
    ' "$BUILD_SCRIPT"
}

default_is_opt_in() {
    grep -q '^BBSH=${BBSH:-auto}' "$BUILD_SCRIPT" &&
        grep -q '^    BBSH=0$' "$BUILD_SCRIPT" &&
        grep -q '\[ "\$IMAGE_PROFILE" = personal \] && \[ -r "\$BBDYN" \]' "$BUILD_SCRIPT"
}

base_image_has_musl() {
    [ -n "$(unguarded_musl_lines)" ] || ! default_is_opt_in
}
