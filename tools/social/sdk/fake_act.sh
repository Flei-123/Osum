#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_ACT_LOG"
[ -z "${FAKE_ACT_FAIL:-}" ] || exit 1
case "$2" in
social.party.take)
    if [ -n "${FAKE_ACT_EMPTY:-}" ]; then
        printf 'ok\nfound=false\n'
    else
        printf 'ok\nfound=true\ntarget=game://lobby/7\nname=Chess\nkind=invite\nfrom=local:peter\n'
    fi
    ;;
*) printf 'ok\n' ;;
esac
