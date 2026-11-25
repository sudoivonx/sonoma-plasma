#!/usr/bin/env bash
# ==============================================================================
# Sonoma Plasma — macOS Sonoma Desktop Transformation for KDE Plasma 6 (Wayland)
# Repository: https://github.com/sudoivonx/sonoma-plasma
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_CONFIG_DIR="$SCRIPT_DIR/config"
REPO_LOCAL_DIR="$SCRIPT_DIR/local"
REPO_WALLPAPER="$SCRIPT_DIR/wallpapers/default.jpg"

DRY_RUN=0
SKIP_PACKAGES=0
SKIP_THEMES=0
NO_BACKUP=0
WITH_SDDM=0
ASSUME_YES=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [OPTIONS]

Options:
  --dry-run        Simulate all steps without modifying any files or installing packages
  --skip-packages  Skip distro package installation
  --skip-themes    Skip cloning/installing WhiteSur KDE, Icon, and Cursor themes
  --no-backup      Skip backing up existing KDE/GTK configuration files
  --with-sddm      Also install the bundled macOS SDDM login theme (requires sudo)
  -y, --yes        Proceed non-interactively without confirmation prompts
  -h, --help       Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)        DRY_RUN=1; shift ;;
        --skip-packages)  SKIP_PACKAGES=1; shift ;;
        --skip-themes)    SKIP_THEMES=1; shift ;;
        --no-backup)      NO_BACKUP=1; shift ;;
        --with-sddm)      WITH_SDDM=1; shift ;;
        -y|--yes)         ASSUME_YES=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)
            echo "[ERROR] Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

log()  { printf '\033[1;34m[sonoma-plasma]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[sonoma-plasma]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[sonoma-plasma]\033[0m %s\n' "$*"; }

run_cmd() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] $*"
    else
        "$@"
    fi
}

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"
TARGET_WALLPAPER="$WALLPAPER_DIR/sonoma-plasma-default.jpg"
BACKUP_ROOT="$STATE_HOME/sonoma-plasma/backups"
BACKUP_DIR="$BACKUP_ROOT/pre-sonoma-$(date -u +%Y%m%d-%H%M%SZ)"

detect_distro() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        case "${ID:-} ${ID_LIKE:-}" in
            *fedora*|*rhel*|*centos*) echo "fedora" ;;
            *arch*|*manjaro*|*cachyos*|*endeavouros*) echo "arch" ;;
            *ubuntu*|*debian*|*pop*|*mint*) echo "debian" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

install_packages() {
    local distro
    distro="$(detect_distro)"
    log "Detected distribution family: $distro"
    if [[ "$SKIP_PACKAGES" -eq 1 ]]; then
        log "Skipping system package installation (--skip-packages)."
        return 0
    fi
    case "$distro" in
        fedora)
            run_cmd sudo dnf install -y git curl rsync python3-pyside6 qt6-qtdeclarative inter-fonts jetbrains-mono-fonts darkly || warn "Some optional Fedora packages could not be installed automatically."
            ;;
        arch)
            run_cmd sudo pacman -S --needed --noconfirm git curl rsync pyside6 qt6-declarative inter-font ttf-jetbrains-mono-nerd || warn "Some optional Arch packages could not be installed automatically."
            ;;
        debian)
            run_cmd sudo apt-get update && run_cmd sudo apt-get install -y git curl rsync python3-pyside6.qtqml python3-pyside6.qtquick fonts-inter || warn "Some optional Debian/Ubuntu packages could not be installed automatically."
            ;;
        *)
            warn "Unsupported distro for automatic package install. Please install git, PySide6 (QtQuick), Inter font, and Darkly Qt6 style manually."
            ;;
    esac
}

install_whitesur_themes() {
    if [[ "$SKIP_THEMES" -eq 1 ]]; then
        log "Skipping WhiteSur theme installation (--skip-themes)."
        return 0
    fi
    local src_dir="$DATA_HOME/kde-macos/src"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Would clone & install WhiteSur-kde, WhiteSur-icon-theme, WhiteSur-cursors into $DATA_HOME"
        return 0
    fi
    mkdir -p "$src_dir" "$DATA_HOME/plasma/desktoptheme" "$DATA_HOME/aurorae/themes" "$DATA_HOME/color-schemes" "$DATA_HOME/icons"

    if [[ ! -d "$src_dir/WhiteSur-kde/.git" ]]; then
        git clone --depth=1 https://github.com/vinceliuice/WhiteSur-kde.git "$src_dir/WhiteSur-kde"
    fi
    (cd "$src_dir/WhiteSur-kde" && ./install.sh)

    # Create WhiteSurLight.colors and WhiteSur-light aliases for dark/light toggling
    if [[ -f "$DATA_HOME/color-schemes/WhiteSur.colors" && ! -f "$DATA_HOME/color-schemes/WhiteSurLight.colors" ]]; then
        sed 's/^Name=WhiteSur$/Name=WhiteSurLight/' "$DATA_HOME/color-schemes/WhiteSur.colors" > "$DATA_HOME/color-schemes/WhiteSurLight.colors"
    fi
    [[ -d "$DATA_HOME/plasma/desktoptheme/WhiteSur" ]] && ln -sfn WhiteSur "$DATA_HOME/plasma/desktoptheme/WhiteSur-light"
    [[ -d "$DATA_HOME/aurorae/themes/WhiteSur" ]] && ln -sfn WhiteSur "$DATA_HOME/aurorae/themes/WhiteSur-light"

    if [[ ! -d "$src_dir/WhiteSur-icon-theme/.git" ]]; then
        git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git "$src_dir/WhiteSur-icon-theme"
    fi
    (cd "$src_dir/WhiteSur-icon-theme" && ./install.sh -a)

    if [[ ! -d "$src_dir/WhiteSur-cursors/.git" ]]; then
        git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git "$src_dir/WhiteSur-cursors"
    fi
    (cd "$src_dir/WhiteSur-cursors" && ./install.sh)
    if [[ -d "$DATA_HOME/icons/WhiteSur-cursors" ]]; then
        printf '[Icon Theme]\nName=WhiteSur-cursors\n' > "$DATA_HOME/icons/WhiteSur-cursors/index.theme"
    fi
    ok "WhiteSur KDE, Icon, and Cursor themes installed in user space."
}

backup_existing() {
    if [[ "$NO_BACKUP" -eq 1 ]]; then
        log "Skipping backup (--no-backup)."
        return 0
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Would back up existing KDE/GTK configs into $BACKUP_DIR"
        return 0
    fi
    mkdir -p "$BACKUP_DIR/config"
    for f in darklyrc kcminputrc kded6rc kdeglobals kglobalshortcutsrc krunnerrc kscreenlockerrc kwinrc kwinrulesrc plasma-org.kde.plasma.desktop-appletsrc plasmanotifyrc plasmarc plasmashellrc; do
        [[ -f "$CONFIG_HOME/$f" ]] && cp -a "$CONFIG_HOME/$f" "$BACKUP_DIR/config/$f"
    done
    [[ -d "$CONFIG_HOME/gtk-3.0" ]] && cp -a "$CONFIG_HOME/gtk-3.0" "$BACKUP_DIR/config/gtk-3.0"
    [[ -d "$CONFIG_HOME/gtk-4.0" ]] && cp -a "$CONFIG_HOME/gtk-4.0" "$BACKUP_DIR/config/gtk-4.0"
    [[ -f "$HOME/.gtkrc-2.0" ]] && cp -a "$HOME/.gtkrc-2.0" "$BACKUP_DIR/gtkrc-2.0"
    ln -sfn "$BACKUP_DIR" "$BACKUP_ROOT/latest"
    ok "Backed up existing configuration to $BACKUP_DIR"
}

deploy_with_home_sub() {
    local src="$1"
    local dst="$2"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Deploy $src -> $dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    if file -b --mime-encoding "$src" 2>/dev/null | grep -qv binary; then
        sed "s|__HOME__|$HOME|g" "$src" > "$dst"
        chmod --reference="$src" "$dst" 2>/dev/null || true
    else
        cp -a "$src" "$dst"
    fi
}

deploy_files() {
    log "Deploying Sonoma Plasma configs, Burn My Windows Aura Glow, macOS Plasmoids, and Control Center..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Would copy wallpaper -> $TARGET_WALLPAPER"
        log "[DRY-RUN] Would deploy config/* -> $CONFIG_HOME/"
        log "[DRY-RUN] Would deploy local/kwin/effects/glow -> $DATA_HOME/kwin/effects/glow"
        log "[DRY_RUN] Would deploy local/plasma/plasmoids/* -> $DATA_HOME/plasma/plasmoids/"
        log "[DRY-RUN] Would deploy local/control-center -> $DATA_HOME/kde-macos/control-center"
        log "[DRY-RUN] Would deploy local/applications/nexus-plasma-settings.desktop -> $DATA_HOME/applications/"
        log "[DRY-RUN] Would deploy local/sddm -> $DATA_HOME/kde-macos/sddm"
        return 0
    fi

    # 1. Wallpaper
    mkdir -p "$WALLPAPER_DIR"
    cp -f "$REPO_WALLPAPER" "$TARGET_WALLPAPER"

    # 2. KDE & GTK Configs
    for f in darklyrc kcminputrc kded6rc kdeglobals kglobalshortcutsrc krunnerrc kscreenlockerrc kwinrc kwinrulesrc plasma-org.kde.plasma.desktop-appletsrc plasmanotifyrc plasmarc plasmashellrc; do
        [[ -f "$REPO_CONFIG_DIR/$f" ]] && deploy_with_home_sub "$REPO_CONFIG_DIR/$f" "$CONFIG_HOME/$f"
    done
    deploy_with_home_sub "$REPO_CONFIG_DIR/gtk-3.0/settings.ini" "$CONFIG_HOME/gtk-3.0/settings.ini"
    deploy_with_home_sub "$REPO_CONFIG_DIR/gtk-4.0/settings.ini" "$CONFIG_HOME/gtk-4.0/settings.ini"
    deploy_with_home_sub "$REPO_CONFIG_DIR/gtkrc-2.0" "$HOME/.gtkrc-2.0"

    # 3. KWin 6 Burn My Windows Aura Glow effect
    rm -rf "$DATA_HOME/kwin/effects/glow"
    mkdir -p "$DATA_HOME/kwin/effects"
    cp -a "$REPO_LOCAL_DIR/kwin/effects/glow" "$DATA_HOME/kwin/effects/glow"

    # 4. Plasma 6 macOS Plasmoids
    mkdir -p "$DATA_HOME/plasma/plasmoids"
    for p in com.nexus.macosdock com.nexus.macosmenubar com.nexus.macoscontrolcenter com.nexus.macosnotifications; do
        rm -rf "$DATA_HOME/plasma/plasmoids/$p"
        while IFS= read -r -d '' f; do
            rel="${f#"$REPO_LOCAL_DIR/plasma/plasmoids/$p/"}"
            deploy_with_home_sub "$f" "$DATA_HOME/plasma/plasmoids/$p/$rel"
        done < <(find "$REPO_LOCAL_DIR/plasma/plasmoids/$p" -type f -print0)
    done

    # 5. macOS Control Center
    rm -rf "$DATA_HOME/kde-macos/control-center"
    while IFS= read -r -d '' f; do
        rel="${f#"$REPO_LOCAL_DIR/control-center/"}"
        deploy_with_home_sub "$f" "$DATA_HOME/kde-macos/control-center/$rel"
    done < <(find "$REPO_LOCAL_DIR/control-center" -type f -print0)
    chmod +x "$DATA_HOME/kde-macos/control-center/main.py" "$DATA_HOME/kde-macos/control-center/nexus_plasma_backend.py"

    # 6. Desktop entry
    deploy_with_home_sub "$REPO_LOCAL_DIR/applications/nexus-plasma-settings.desktop" "$DATA_HOME/applications/nexus-plasma-settings.desktop"

    # 7. Optional SDDM staging
    mkdir -p "$DATA_HOME/kde-macos/sddm"
    cp -a "$REPO_LOCAL_DIR/sddm/"* "$DATA_HOME/kde-macos/sddm/"
    chmod +x "$DATA_HOME/kde-macos/sddm/apply-sddm-macos.sh" "$DATA_HOME/kde-macos/sddm/rollback-sddm-macos.sh"

    ok "All Sonoma Plasma files deployed cleanly."
}

apply_live_session() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] Would apply Plasma theme, color scheme, cursor, wallpaper, KWin effects, and restart plasmashell."
        return 0
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
        warn "Not currently inside a live KDE Plasma session; settings will activate on next KDE Plasma login."
        return 0
    fi

    log "Applying live KDE Plasma 6 session updates..."
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    command -v plasma-apply-desktoptheme >/dev/null 2>&1 && plasma-apply-desktoptheme WhiteSur-dark >/dev/null 2>&1 || true
    command -v plasma-apply-colorscheme >/dev/null 2>&1 && plasma-apply-colorscheme WhiteSurDark >/dev/null 2>&1 || true
    command -v plasma-apply-cursortheme >/dev/null 2>&1 && plasma-apply-cursortheme WhiteSur-cursors --size 24 >/dev/null 2>&1 || true
    command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && plasma-apply-wallpaperimage "$TARGET_WALLPAPER" >/dev/null 2>&1 || true

    if command -v qdbus-qt6 >/dev/null 2>&1; then
        qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect shakecursor >/dev/null 2>&1 || true
        qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect scale >/dev/null 2>&1 || true
        qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glow >/dev/null 2>&1 || true
        qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect magiclamp >/dev/null 2>&1 || true
        qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect blur >/dev/null 2>&1 || true
        qdbus-qt6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
        qdbus-qt6 org.freedesktop.ScreenSaver /ScreenSaver org.kde.screensaver.configure >/dev/null 2>&1 || true
    fi
    command -v dbus-send >/dev/null 2>&1 && dbus-send --session --type=signal /DarklyStyle org.kde.Darkly.Style.configurationChanged >/dev/null 2>&1 || true
    systemctl --user restart plasma-plasmashell.service >/dev/null 2>&1 || true
    python3 "$DATA_HOME/kde-macos/control-center/nexus_plasma_backend.py" initialize >/dev/null 2>&1 || true
    ok "Live KDE Plasma 6 session updated!"
}

main() {
    log "Starting Sonoma Plasma installer..."
    if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
        read -r -p "This will back up and transform your KDE Plasma 6 desktop into Sonoma Plasma. Continue? [y/N] " ans
        case "$ans" in
            y|Y|yes|YES) ;;
            *) log "Aborted by user."; exit 0 ;;
        esac
    fi

    install_packages
    install_whitesur_themes
    backup_existing
    deploy_files
    apply_live_session

    if [[ "$WITH_SDDM" -eq 1 ]]; then
        run_cmd sudo "$DATA_HOME/kde-macos/sddm/apply-sddm-macos.sh"
    fi

    ok "Sonoma Plasma installation complete! Press Meta+I to open macOS Control Center."
}

main
