#!/usr/bin/env bash
set -euo pipefail

ROOT_PREFIX="${SDDM_ROOT:-}"
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --root-prefix)
            ROOT_PREFIX="${2:?missing root prefix}"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

THEMES_DIR="${SDDM_THEMES_DIR:-${ROOT_PREFIX}/usr/share/sddm/themes}"
ETC_DIR="${SDDM_ETC_DIR:-${ROOT_PREFIX}/etc/sddm.conf.d}"

is_system_target() {
    case "$1" in
        /etc|/etc/*|/usr|/usr/*) return 0 ;;
        *) return 1 ;;
    esac
}

if (is_system_target "$THEMES_DIR" || is_system_target "$ETC_DIR") && [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Run with sudo: sudo $0 (or set SDDM_ETC_DIR and SDDM_THEMES_DIR / --root-prefix <dir> for sandbox)" >&2
    exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[DRY-RUN] Would remove ${ETC_DIR}/10-macos-theme.conf and ${THEMES_DIR}/WhiteSur"
    exit 0
fi

rm -f "${ETC_DIR}/10-macos-theme.conf"
rm -rf "${THEMES_DIR}/WhiteSur"
echo "SDDM macOS theme rolled back to Fedora/KDE Breeze default"
