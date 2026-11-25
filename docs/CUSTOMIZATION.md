# Customization Guide

Sonoma Plasma is designed to be tuned live without breaking Plasma or KWin.

## 1. Using macOS Control Center (`Meta + I`)
Open **macOS Control Center** via `Meta + I`, the top-bar two-pill Control Center icon, or the dock icon:
- **Appearance (`Görünüm & Tema`):** Toggle Dark/Light mode in one click (syncs Plasma desktop theme, KDE color scheme, Aurorae window decoration, icon theme, GTK 2/3/4, and `gsettings`), or change window button layout (`macos_left` vs `classic_right`).
- **Dock & Bar (`Dock & Üst Menü`):** Adjust live top bar height (`24–40px`), dock height (`44–88px`), floating state, and hiding mode (`dodgewindows`, `autohide`, `none`).
- **Blur & Glass (`Bulanıklık & Cam`):** Adjust KWin Blur strength (`1–15`), noise (`0–10`), Darkly `TransparentDolphinView`, menu opacity (`50–100%`), and corner radius (`0–24px`).
- **Animations & Spaces (`Animasyonlar & Spaces`):** Toggle **Burn My Windows Aura Glow**, set Glow duration (`150–2000ms`), configure **Magic Lamp** (`120–600ms`), switch animation speed presets, and live-manage virtual desktops (`1–8`).
- **Profiles & Undo (`Profiller & Kurtarma`):** Save/load named profiles, undo changes with SHA-256 conflict protection, or reset any category back to your captured baseline.

## 2. Fine-Tuning Dock Magnification
Right-click the dock (or edit `~/.config/plasma-org.kde.plasma.desktop-appletsrc` under `com.nexus.macosdock`):
- `iconSize`: Resting icon size in pixels (default `44`).
- `magnificationScale`: Peak zoom multiplier on hover (default `1.45` → `~64px`).
- `magnificationRadius`: Cosine wave influence radius in pixels (default `145`).
- `iconSpacing`: Gap between dock icons (default `6`).

## 3. Fine-Tuning Burn My Windows Aura Glow
Edit `~/.config/kwinrc` under `[Effect-glow]` (or via System Settings → Window Management → Desktop Effects → Aura Glow):
- `Duration`: Animation length in ms (default `750`).
- `RandomColor`: Set `true` for rainbow hue variation per window (default `false`).
- `StartHue`, `Speed`, `Saturation`, `EdgeSize`, `EdgeHardness`, `BlurAmount`: Standard Burn My Windows Aura Glow shader parameters.

Reload live with:
```bash
qdbus-qt6 org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect glow
```

## 4. Customizing Selective Vibrancy Glass
Edit `~/.config/kwinrulesrc` to add or remove applications from macOS Vibrancy translucency, then apply live:
```bash
qdbus-qt6 org.kde.KWin /KWin reconfigure
```
