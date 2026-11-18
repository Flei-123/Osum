PKGDEV_SHOTS=${PKGDEV_SHOTS:-/root/jarvis/data/projects_kb/orientos/shots}
PKGDEV_CACHE=${PKGDEV_CACHE:-/root/abbilder/pkgdev-cache}
PKGDEV_BOOT_SECONDS=${PKGDEV_BOOT_SECONDS:-150}
PKGDEV_PAGE_SECONDS=${PKGDEV_PAGE_SECONDS:-30}
HEAVY=${HEAVY_BIN:-/root/jarvis/bin/heavy}

pkg_manifest() {
    local file="tools/pkgdev/pkgs/$1.pkg"
    [ -f "$file" ] || { echo "pkgdev: unknown package '$1' (have: $(pkg_list))" >&2; return 1; }
    echo "$file"
}

pkg_get() {
    sed -n "s/^$2=//p" "$(pkg_manifest "$1")" | head -1
}

pkg_list() {
    ls tools/pkgdev/pkgs/*.pkg 2>/dev/null | sed 's#.*/##; s#\.pkg$##' | tr '\n' ' '
}

pkg_sources_ok() {
    local path missing=0
    for path in $(pkg_get "$1" sources); do
        [ -e "$path" ] || { echo "pkgdev: source $path missing" >&2; missing=1; }
    done
    return $missing
}

stamp() {
    printf 'pkgdev: %-8s %5.1f s\n' "$1" "$(awk -v a="$EPOCHREALTIME" -v b="$2" 'BEGIN{print a-b}')"
}
