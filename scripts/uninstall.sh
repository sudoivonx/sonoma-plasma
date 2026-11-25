#!/usr/bin/env bash
# ==============================================================================
# Sonoma Plasma — Clean Rollback / Uninstaller
# ==============================================================================
set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
BACKUP_DIR="$STATE_HOME/sonoma-plasma/backups/latest"

log() { printf '\033[1;34m[sonoma-plasma-uninstall]\033[0m %s\n' "$*"; }

if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "[ERROR] No backup found at $BACKUP_DIR" >&2
    exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[DRY-RUN] Would restore configs from $(readlink -f "$BACKUP_DIR") into $CONFIG_HOME"
    log "[DRY-RUN] Would remove custom plasmoids (com.nexus.*) and glow effect from $DATA_HOME"
    exit 0
fi

for f in darklyrc kcminputrc kded6rc kdeglobals kglobalshortcutsrc krunnerrc kscreenlockerrc kwinrc kwinrulesrc plasma-org.kde.plasma.desktop-appletsrc plasmanotifyrc plasmarc plasmashellrc; do
    if [[ -f "$BACKUP_DIR/config/$f" ]]; then
        cp -a "$BACKUP_DIR/config/$f" "$CONFIG_HOME/$f"
    fi
done
[[ -d "$BACKUP_DIR/config/gtk-3.0" ]] && rm -rf "$CONFIG_HOME/gtk-3.0" && cp -a "$BACKUP_DIR/config/gtk-3.0" "$CONFIG_HOME/gtk-3.0"
[[ -d "$BACKUP_DIR/config/gtk-4.0" ]] && rm -rf "$CONFIG_HOME/gtk-4.0" && cp -a "$BACKUP_DIR/config/gtk-4.0" "$CONFIG_HOME/gtk-4.0"
[[ -f "$BACKUP_DIR/gtkrc-2.0" ]] && cp -a "$BACKUP_DIR/gtkrc-2.0" "$HOME/.gtkrc-2.0"

rm -rf "$DATA_HOME/kwin/effects/glow"
rm -rf "$DATA_HOME/plasma/plasmoids/com.nexus.macosdock" \
       "$DATA_HOME/plasma/plasmoids/com.nexus.macosmenubar" \
       "$DATA_HOME/plasma/plasmoids/com.nexus.macoscontrolcenter" \
       "$DATA_HOME/plasma/plasmoids/com.nexus.macosnotifications"
rm -f "$DATA_HOME/applications/nexus-plasma-settings.desktop"

if command -v qdbus-qt6 >/dev/null 2>&1; then
    qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
fi
systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || true
log "Restored previous KDE Plasma configuration successfully."
