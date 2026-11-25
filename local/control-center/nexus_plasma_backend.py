#!/usr/bin/env python3
"""NEXUS-Plasma Control Center Backend.

Manages macOS-styled KDE Plasma 6 settings (Appearance, Dock/Bar, Blur/Effects,
Animations/Spaces, Wallpaper/Lockscreen, Cursor/ShakeCursor, Typography,
Profiles, SHA-256 guarded Undo, Baseline Reset, and Hyprland Isolation status).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
from typing import Any


SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
CATALOG_PATH = SCRIPT_DIR / "settings_catalog.json"

SETTING_ALIASES = {
    "appearance.themeMode": "appearance.colorMode",
    "appearance.mode": "appearance.colorMode",
    "appearance.buttonsSide": "appearance.buttonLayout",
    "blur.blurEnabled": "blur_effects.blurEnabled",
    "blur.blurStrength": "blur_effects.blurStrength",
    "blur.noiseStrength": "blur_effects.noiseStrength",
    "blur.translucencyEnabled": "blur_effects.translucencyEnabled",
    "blur.cornerRadius": "blur_effects.darklyCornerRadius",
    "blur.menuOpacity": "blur_effects.darklyMenuOpacity",
    "animations.scaleEnabled": "animations.glowEnabled",
    "animations.scaleDuration": "animations.glowDuration",
    "cursor.shakecursorEnabled": "cursor.shakeCursorEnabled",
    "cursor.shakecursor": "cursor.shakeCursorEnabled",
    "wallpaper.desktop": "wallpaper_lock.desktopWallpaper",
    "wallpaper.lockscreen": "wallpaper_lock.lockscreenWallpaper",
    "lockscreen.autolock": "wallpaper_lock.autolock",
    "dock.height": "dock_bar.dockHeight",
    "dock.floating": "dock_bar.dockFloating",
    "dock.hiding": "dock_bar.dockHiding",
    "bar.height": "dock_bar.topBarHeight",
    "typography.uiFont": "typography.generalFont",
    "typography.monoFont": "typography.fixedFont",
}

PROFILE_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


class NexusPlasmaError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


class NexusPlasmaBackend:
    def __init__(
        self,
        *,
        home_dir: pathlib.Path | None = None,
        config_home: pathlib.Path | None = None,
        state_home: pathlib.Path | None = None,
        data_home: pathlib.Path | None = None,
        skip_live: bool | None = None,
    ):
        self.home_dir = pathlib.Path(home_dir or os.environ.get("HOME") or pathlib.Path.home()).expanduser()
        self.config_home = pathlib.Path(
            config_home or os.environ.get("XDG_CONFIG_HOME") or (self.home_dir / ".config")
        ).expanduser()
        self.state_home = pathlib.Path(
            state_home or os.environ.get("XDG_STATE_HOME") or (self.home_dir / ".local/state")
        ).expanduser()
        self.data_home = pathlib.Path(
            data_home or os.environ.get("XDG_DATA_HOME") or (self.home_dir / ".local/share")
        ).expanduser()

        if skip_live is None:
            env_skip = os.environ.get("KDE_MACOS_SKIP_LIVE_SERVICES", "0") == "1"
            real_home = pathlib.Path.home().resolve()
            is_sandbox = self.config_home.resolve() != (real_home / ".config").resolve()
            self.skip_live = env_skip or is_sandbox
        else:
            self.skip_live = skip_live

        self.cc_state_dir = self.state_home / "kde-macos" / "control-center"
        self.initial_state_path = self.cc_state_dir / "initial-state.json"
        self.undo_path = self.cc_state_dir / "undo" / "actions.json"
        self.profiles_dir = self.cc_state_dir / "profiles"
        self.catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
        self.settings_by_id = {s["id"]: s for s in self.catalog["settings"]}

    def _resolve_sid(self, sid: str) -> str:
        return SETTING_ALIASES.get(sid, sid)

    def _ensure_private_dir(self, path: pathlib.Path) -> None:
        path.mkdir(parents=True, exist_ok=True)
        os.chmod(path, 0o700)

    def _write_private_json(self, path: pathlib.Path, payload: Any) -> None:
        self._ensure_private_dir(path.parent)
        tmp = path.with_suffix(path.suffix + ".tmp")
        tmp.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(path)
        os.chmod(path, 0o600)

    def _env(self) -> dict[str, str]:
        env = dict(os.environ)
        env["HOME"] = str(self.home_dir)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.state_home)
        env["XDG_DATA_HOME"] = str(self.data_home)
        return env

    def _run(self, cmd: list[str], *, check: bool = False, timeout: int = 10) -> subprocess.CompletedProcess:
        return subprocess.run(cmd, env=self._env(), capture_output=True, text=True, timeout=timeout, check=check)

    def _kread(self, filename: str, groups: list[str], key: str, default: str = "") -> str:
        path = self.config_home / filename
        cmd = ["kreadconfig6", "--file", str(path)]
        for g in groups:
            cmd += ["--group", g]
        cmd += ["--key", key, "--default", default]
        r = self._run(cmd)
        return r.stdout.strip() if r.returncode == 0 else default

    def _kwrite(self, filename: str, groups: list[str], key: str, value: Any) -> pathlib.Path:
        self.config_home.mkdir(parents=True, exist_ok=True)
        path = self.config_home / filename
        cmd = ["kwriteconfig6", "--file", str(path)]
        for g in groups:
            cmd += ["--group", g]
        val_str = ("true" if value else "false") if isinstance(value, bool) else str(value)
        cmd += ["--key", key, val_str]
        r = self._run(cmd)
        if r.returncode != 0:
            raise NexusPlasmaError("kwrite_failed", r.stderr.strip() or f"Failed writing {filename}:{key}")
        return path

    def _update_gtk_ini(self, subdir: str, updates: dict[str, str]) -> None:
        ini = self.config_home / subdir / "settings.ini"
        ini.parent.mkdir(parents=True, exist_ok=True)
        lines = ini.read_text(encoding="utf-8", errors="ignore").splitlines() if ini.is_file() else ["[Settings]"]
        if not any(l.strip() == "[Settings]" for l in lines):
            lines.insert(0, "[Settings]")
        out = []
        seen = set()
        for l in lines:
            k = l.split("=", 1)[0].strip() if "=" in l else ""
            if k in updates:
                out.append(f"{k}={updates[k]}")
                seen.add(k)
            else:
                out.append(l)
        for k, v in updates.items():
            if k not in seen:
                out.append(f"{k}={v}")
        ini.write_text("\n".join(out).strip() + "\n", encoding="utf-8")

    def _update_gtk2(self, updates: dict[str, str]) -> None:
        p = self.home_dir / ".gtkrc-2.0"
        lines = p.read_text(encoding="utf-8", errors="ignore").splitlines() if p.is_file() else []
        out = []
        seen = set()
        for l in lines:
            k = l.split("=", 1)[0].strip() if "=" in l else ""
            if k in updates:
                out.append(f"{k}={updates[k]}")
                seen.add(k)
            else:
                out.append(l)
        for k, v in updates.items():
            if k not in seen:
                out.append(f"{k}={v}")
        p.write_text("\n".join(out).strip() + "\n", encoding="utf-8")

    @staticmethod
    def _file_sha256(path: pathlib.Path) -> str | None:
        if not path.is_file():
            return None
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def _read_bool(self, filename: str, groups: list[str], key: str, default: bool) -> bool:
        raw = self._kread(filename, groups, key, "true" if default else "false").lower()
        if raw in ("true", "1", "yes", "on"):
            return True
        if raw in ("false", "0", "no", "off"):
            return False
        return default

    def _read_int(self, filename: str, groups: list[str], key: str, default: int) -> int:
        raw = self._kread(filename, groups, key, str(default))
        try:
            return int(float(raw))
        except Exception:
            return default

    def _read_float(self, filename: str, groups: list[str], key: str, default: float) -> float:
        raw = self._kread(filename, groups, key, str(default))
        try:
            return round(float(raw), 3)
        except Exception:
            return default

    def _read_desktop_wallpaper(self) -> str:
        applets = self.config_home / "plasma-org.kde.plasma.desktop-appletsrc"
        if applets.is_file():
            txt = applets.read_text(errors="ignore")
            # Identify desktop containment IDs (folder or desktop, not panel)
            desktop_ids: set[str] = set()
            cur_cid: str | None = None
            for line in txt.splitlines():
                s = line.strip()
                m_top = re.match(r"^\[Containments\]\[(\d+)\]$", s)
                if m_top:
                    cur_cid = m_top.group(1)
                    continue
                if s.startswith("["):
                    cur_cid = None
                    continue
                if cur_cid and s.startswith("plugin="):
                    plug = s.split("=", 1)[1].strip()
                    if plug in ("org.kde.plasma.folder", "org.kde.plasma.desktop"):
                        desktop_ids.add(cur_cid)
            # Read Image= from a desktop containment's org.kde.image wallpaper section
            in_wp_sec = False
            for line in txt.splitlines():
                s = line.strip()
                m_wp = re.match(r"^\[Containments\]\[(\d+)\]\[Wallpaper\]\[org\.kde\.image\]\[General\]$", s)
                if m_wp:
                    in_wp_sec = (not desktop_ids) or (m_wp.group(1) in desktop_ids)
                    continue
                if s.startswith("["):
                    in_wp_sec = False
                    continue
                if in_wp_sec and s.startswith("Image="):
                    val = s.split("=", 1)[1].strip()
                    return val.replace("file://", "", 1)
            m = re.search(r"^Image=(?:file://)?(.+)$", txt, re.M)
            if m:
                return m.group(1).strip()
        return self.settings_by_id["wallpaper_lock.desktopWallpaper"]["default"]

    def _read_live_panels(self) -> dict[str, Any]:
        if self.skip_live:
            return {}
        js = (
            'var ps = panels(); var out = {}; '
            'for (var i = 0; i < ps.length; i++) { '
            '  if (ps[i].location === "top") out["dock_bar.topBarHeight"] = Math.round(ps[i].height); '
            '  if (ps[i].location === "bottom") { '
            '    out["dock_bar.dockHeight"] = Math.round(ps[i].height); '
            '    out["dock_bar.dockFloating"] = Boolean(ps[i].floating); '
            '    out["dock_bar.dockHiding"] = (ps[i].hiding === "normal" ? "none" : String(ps[i].hiding)); '
            '  } '
            '} '
            'print(JSON.stringify(out));'
        )
        r = self._run(["qdbus-qt6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js])
        if r.returncode == 0 and r.stdout.strip():
            for line in reversed(r.stdout.strip().splitlines()):
                line = line.strip()
                if line.startswith("{") and line.endswith("}"):
                    try:
                        data = json.loads(line)
                        if isinstance(data, dict):
                            return data
                    except Exception:
                        pass
        return {}

    def _read_panel_setting(self, key: str, default: Any) -> Any:
        if not self.skip_live:
            live = self._read_live_panels()
            if key in live:
                return live[key]
        pref = self.cc_state_dir / "panel-prefs.json"
        if pref.is_file():
            try:
                data = json.loads(pref.read_text(encoding="utf-8"))
                if key in data:
                    val = data[key]
                    if key == "dock_bar.dockHiding" and val == "normal":
                        return "none"
                    return val
            except Exception:
                pass
        return default

    def _save_panel_setting(self, key: str, value: Any) -> pathlib.Path:
        pref = self.cc_state_dir / "panel-prefs.json"
        data = {}
        if pref.is_file():
            try:
                data = json.loads(pref.read_text(encoding="utf-8"))
            except Exception:
                data = {}
        data[key] = value
        self._write_private_json(pref, data)
        if not self.skip_live:
            self._apply_live_panel_setting(key, value)
        return pref

    def _apply_live_panel_setting(self, key: str, value: Any) -> None:
        if key == "dock_bar.topBarHeight":
            js = f'var ps = panels(); for (var i=0;i<ps.length;i++) if (ps[i].location === "top") ps[i].height = {int(value)};'
        elif key == "dock_bar.dockHeight":
            js = f'var ps = panels(); for (var i=0;i<ps.length;i++) if (ps[i].location === "bottom") ps[i].height = {int(value)};'
        elif key == "dock_bar.dockFloating":
            js = f'var ps = panels(); for (var i=0;i<ps.length;i++) if (ps[i].location === "bottom") ps[i].floating = {"true" if value else "false"};'
        elif key == "dock_bar.dockHiding":
            h_val = "none" if str(value) == "normal" else str(value)
            js = f'var ps = panels(); for (var i=0;i<ps.length;i++) if (ps[i].location === "bottom") ps[i].hiding = "{h_val}";'
        else:
            return
        self._run(["qdbus-qt6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js])

    def get_setting(self, sid: str) -> Any:
        sid = self._resolve_sid(sid)
        if sid not in self.settings_by_id:
            raise NexusPlasmaError("unknown_setting", f"Unknown setting id: {sid}")
        defn = self.settings_by_id[sid]
        d = defn["default"]

        if sid == "appearance.colorMode":
            pt = self._kread("plasmarc", ["Theme"], "name", "WhiteSur-dark").lower()
            return "light" if ("light" in pt or pt == "whitesur") else "dark"
        if sid == "appearance.plasmaTheme":
            return self._kread("plasmarc", ["Theme"], "name", d)
        if sid == "appearance.colorScheme":
            return self._kread("kdeglobals", ["General"], "ColorScheme", d)
        if sid == "appearance.windowDecoration":
            return self._kread("kwinrc", ["org.kde.kdecoration2"], "theme", d)
        if sid == "appearance.buttonLayout":
            left = self._kread("kwinrc", ["org.kde.kdecoration2"], "ButtonsOnLeft", "XIA")
            return "macos_left" if "X" in left else "classic_right"
        if sid == "appearance.iconTheme":
            return self._kread("kdeglobals", ["Icons"], "Theme", d)
        if sid == "appearance.widgetStyle":
            return self._kread("kdeglobals", ["KDE"], "widgetStyle", d)
        if sid.startswith("dock_bar."):
            return self._read_panel_setting(sid, d)
        if sid == "blur_effects.blurEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "blurEnabled", d)
        if sid == "blur_effects.blurStrength":
            return self._read_int("kwinrc", ["Effect-blur"], "BlurStrength", d)
        if sid == "blur_effects.noiseStrength":
            return self._read_int("kwinrc", ["Effect-blur"], "NoiseStrength", d)
        if sid == "blur_effects.translucencyEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "translucencyEnabled", d)
        if sid == "blur_effects.darklyTranslucent":
            raw = self._kread("darklyrc", ["Style"], "TransparentDolphinView", "")
            if raw:
                return raw.lower() in ("true", "1", "yes", "on")
            return self._read_bool("darklyrc", ["Style"], "TranslucentWindows", d)
        if sid == "blur_effects.darklyMenuOpacity":
            return self._read_int("darklyrc", ["Style"], "MenuOpacity", d)
        if sid == "blur_effects.darklyCornerRadius":
            return self._read_int("darklyrc", ["Style"], "CornerRadius", d)
        if sid == "animations.durationFactor":
            return self._read_float("kdeglobals", ["KDE"], "AnimationDurationFactor", d)
        if sid == "animations.magicLampEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "magiclampEnabled", d)
        if sid == "animations.magicLampDuration":
            return self._read_int("kwinrc", ["Effect-magiclamp"], "AnimationDuration", d)
        if sid == "animations.glowEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "glowEnabled", d)
        if sid == "animations.glowDuration":
            return self._read_int("kwinrc", ["Effect-glow"], "Duration", d)
        if sid == "animations.slideEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "slideEnabled", d)
        if sid == "animations.virtualDesktops":
            if not self.skip_live:
                r = self._run(["qdbus-qt6", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.count"])
                if r.returncode == 0 and r.stdout.strip().isdigit():
                    return int(r.stdout.strip())
            return self._read_int("kwinrc", ["Desktops"], "Number", d)
        if sid == "wallpaper_lock.desktopWallpaper":
            return self._read_desktop_wallpaper()
        if sid == "wallpaper_lock.lockscreenWallpaper":
            raw = self._kread("kscreenlockerrc", ["Greeter", "Wallpaper", "org.kde.image", "General"], "Image", d)
            return raw.replace("file://", "", 1)
        if sid == "wallpaper_lock.autolock":
            return self._read_bool("kscreenlockerrc", ["Daemon"], "Autolock", d)
        if sid == "cursor.shakeCursorEnabled":
            return self._read_bool("kwinrc", ["Plugins"], "shakecursorEnabled", d)
        if sid == "cursor.theme":
            return self._kread("kcminputrc", ["Mouse"], "cursorTheme", d)
        if sid == "cursor.size":
            return self._read_int("kcminputrc", ["Mouse"], "cursorSize", d)
        if sid == "typography.generalFont":
            return self._kread("kdeglobals", ["General"], "font", d)
        if sid == "typography.fixedFont":
            return self._kread("kdeglobals", ["General"], "fixed", d)
        if sid == "typography.titleFont":
            return self._kread("kdeglobals", ["WM"], "activeFont", d)
        return d

    def get_all_values(self) -> dict[str, Any]:
        return {sid: self.get_setting(sid) for sid in self.settings_by_id}

    def _cursor_theme_installed(self, name: str) -> bool:
        for base in (
            self.data_home / "icons",
            self.home_dir / ".icons",
            pathlib.Path("/usr/share/icons"),
            pathlib.Path("/usr/local/share/icons"),
        ):
            if (base / name / "cursors").is_dir():
                return True
        return False

    def validate_value(self, sid: str, value: Any) -> Any:
        sid = self._resolve_sid(sid)
        if sid not in self.settings_by_id:
            raise NexusPlasmaError("unknown_setting", f"Unknown setting: {sid}")
        defn = self.settings_by_id[sid]
        t = defn["type"]

        if sid == "appearance.buttonLayout":
            if value == "left":
                value = "macos_left"
            elif value == "right":
                value = "classic_right"
        if sid == "dock_bar.dockHiding" and value == "normal":
            value = "none"

        if t == "boolean":
            if isinstance(value, bool):
                return value
            if isinstance(value, str) and value.lower() in ("true", "false", "1", "0"):
                return value.lower() in ("true", "1")
            raise NexusPlasmaError("values_invalid", f"{sid} requires a boolean")
        if t == "integer":
            try:
                v = int(value) if not isinstance(value, bool) else None
            except Exception:
                v = None
            if v is None:
                raise NexusPlasmaError("values_invalid", f"{sid} requires an integer")
            if "min" in defn and v < defn["min"]:
                raise NexusPlasmaError("values_invalid", f"{sid} must be >= {defn['min']}")
            if "max" in defn and v > defn["max"]:
                raise NexusPlasmaError("values_invalid", f"{sid} must be <= {defn['max']}")
            return v
        if t == "number":
            try:
                v = float(value) if not isinstance(value, bool) else None
            except Exception:
                v = None
            if v is None:
                raise NexusPlasmaError("values_invalid", f"{sid} requires a number")
            if "min" in defn and v < defn["min"]:
                raise NexusPlasmaError("values_invalid", f"{sid} must be >= {defn['min']}")
            if "max" in defn and v > defn["max"]:
                raise NexusPlasmaError("values_invalid", f"{sid} must be <= {defn['max']}")
            return round(v, 3)
        if t == "enum":
            sv = str(value)
            if sv not in defn["choices"]:
                raise NexusPlasmaError("values_invalid", f"{sid} must be one of {defn['choices']}")
            return sv
        if t == "filepath":
            sv = str(value).strip()
            if not sv:
                raise NexusPlasmaError("values_invalid", f"{sid} cannot be empty")
            p = pathlib.Path(sv).expanduser()
            if not p.is_file():
                raise NexusPlasmaError("values_invalid", f"File does not exist: {p}")
            return str(p)
        if t == "string":
            sv = str(value).strip()
            if not sv:
                raise NexusPlasmaError("values_invalid", f"{sid} cannot be empty")
            if sid == "cursor.theme" and not self._cursor_theme_installed(sv):
                raise NexusPlasmaError("values_invalid", f"Cursor theme not installed: {sv}")
            return sv
        return value

    def _target_files_for(self, sid: str) -> list[pathlib.Path]:
        sid = self._resolve_sid(sid)
        if sid == "appearance.colorMode":
            return [
                self.config_home / "plasmarc",
                self.config_home / "kdeglobals",
                self.config_home / "kwinrc",
                self.config_home / "gtk-3.0/settings.ini",
                self.config_home / "gtk-4.0/settings.ini",
                self.home_dir / ".gtkrc-2.0",
            ]
        if sid == "appearance.plasmaTheme":
            return [self.config_home / "plasmarc"]
        if sid == "appearance.buttonLayout":
            return [
                self.config_home / "kwinrc",
                self.config_home / "gtk-3.0/settings.ini",
                self.config_home / "gtk-4.0/settings.ini",
            ]
        if sid in ("appearance.colorScheme", "appearance.iconTheme", "appearance.widgetStyle",
                   "typography.generalFont", "typography.fixedFont", "typography.titleFont"):
            return [
                self.config_home / "kdeglobals",
                self.config_home / "gtk-3.0/settings.ini",
                self.config_home / "gtk-4.0/settings.ini",
                self.home_dir / ".gtkrc-2.0",
            ]
        if sid == "appearance.windowDecoration" or sid.startswith("blur_effects.blur") or sid in (
            "blur_effects.noiseStrength", "blur_effects.translucencyEnabled",
            "animations.magicLampEnabled", "animations.magicLampDuration",
            "animations.glowEnabled", "animations.glowDuration",
            "animations.slideEnabled", "animations.virtualDesktops",
            "cursor.shakeCursorEnabled",
        ):
            return [self.config_home / "kwinrc"]
        if sid == "animations.durationFactor":
            return [self.config_home / "kdeglobals", self.config_home / "kwinrc"]
        if sid.startswith("blur_effects.darkly"):
            return [self.config_home / "darklyrc"]
        if sid.startswith("dock_bar."):
            return [self.cc_state_dir / "panel-prefs.json"]
        if sid in ("wallpaper_lock.lockscreenWallpaper", "wallpaper_lock.autolock"):
            return [self.config_home / "kscreenlockerrc"]
        if sid == "wallpaper_lock.desktopWallpaper":
            return [self.config_home / "plasma-org.kde.plasma.desktop-appletsrc"]
        if sid in ("cursor.theme", "cursor.size"):
            return [
                self.config_home / "kcminputrc",
                self.config_home / "gtk-3.0/settings.ini",
                self.config_home / "gtk-4.0/settings.ini",
                self.home_dir / ".gtkrc-2.0",
            ]
        return []

    def ensure_baseline(self) -> dict[str, Any]:
        self._ensure_private_dir(self.cc_state_dir)
        self._ensure_private_dir(self.undo_path.parent)
        self._ensure_private_dir(self.profiles_dir)
        if self.initial_state_path.is_file():
            return json.loads(self.initial_state_path.read_text(encoding="utf-8"))
        vals = self.get_all_values()
        vals["appearance.mode"] = vals.get("appearance.colorMode", "dark")
        baseline = {
            "schema": "nexus-initial-state-v1",
            "capturedAt": int(time.time()),
            "values": vals,
        }
        self._write_private_json(self.initial_state_path, baseline)
        return baseline

    def _reconfigure_kwin(self) -> None:
        if not self.skip_live:
            self._run(["qdbus-qt6", "org.kde.KWin", "/KWin", "reconfigure"])

    def _kwin_effect_toggle(self, effect_name: str, enabled: bool) -> None:
        if not self.skip_live:
            act = "loadEffect" if enabled else "unloadEffect"
            self._run(["qdbus-qt6", "org.kde.KWin", "/Effects", f"org.kde.kwin.Effects.{act}", effect_name])

    def _kwin_effect_reconfigure(self, effect_name: str) -> None:
        if not self.skip_live:
            self._run(["qdbus-qt6", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.reconfigureEffect", effect_name])

    def _emit_darkly_reload(self) -> None:
        if not self.skip_live:
            self._run(["dbus-send", "--session", "--type=signal", "/DarklyStyle", "org.kde.Darkly.Style.configurationChanged"])

    def _emit_kglobal_change(self, change_type: int) -> None:
        if not self.skip_live:
            self._run([
                "dbus-send", "--session", "--type=signal",
                "/KGlobalSettings", "org.kde.KGlobalSettings.notifyChange",
                f"int32:{change_type}", "int32:0",
            ])

    def _emit_icon_change(self) -> None:
        if not self.skip_live:
            self._run(["dbus-send", "--session", "--type=signal", "/KIconLoader", "org.kde.KIconLoader.iconChanged", "int32:0"])
            self._emit_kglobal_change(4)

    def _reload_screenlocker(self) -> None:
        if not self.skip_live:
            self._run(["qdbus-qt6", "org.freedesktop.ScreenSaver", "/ScreenSaver", "org.kde.screensaver.configure"])

    def _gsettings_set(self, schema: str, key: str, value: str) -> None:
        if not self.skip_live:
            self._run(["gsettings", "set", schema, key, value])

    def _sync_virtual_desktops(self, target_count: int) -> None:
        if self.skip_live:
            return
        r = self._run(["qdbus-qt6", "--literal", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.desktops"])
        uuids = re.findall(r'"([0-9a-fA-F-]{36})"', r.stdout) if r.returncode == 0 else []
        cur = len(uuids)
        if cur == 0:
            rc = self._run(["qdbus-qt6", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.count"])
            cur = int(rc.stdout.strip()) if rc.returncode == 0 and rc.stdout.strip().isdigit() else 1
        while cur < target_count:
            self._run(["qdbus-qt6", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.createDesktop", str(cur), f"Desktop {cur + 1}"])
            cur += 1
        while cur > target_count and uuids:
            last_id = uuids.pop()
            self._run(["qdbus-qt6", "org.kde.KWin", "/VirtualDesktopManager", "org.kde.KWin.VirtualDesktopManager.removeDesktop", last_id])
            cur -= 1

    def _apply_single_no_undo(self, sid: str, value: Any) -> None:
        sid = self._resolve_sid(sid)
        if sid == "appearance.colorMode":
            is_dark = value == "dark"
            pt = "WhiteSur-dark" if is_dark else "WhiteSur-light"
            cs = "WhiteSurDark" if is_dark else "WhiteSurLight"
            wd = "__aurorae__svg__WhiteSur-dark" if is_dark else "__aurorae__svg__WhiteSur-light"
            ic = "WhiteSur-dark" if is_dark else "WhiteSur"
            gtk_dark = "true" if is_dark else "false"
            if not self.skip_live:
                # Run plasma-apply-* BEFORE writing config so they don't short-circuit
                self._run(["plasma-apply-desktoptheme", pt])
                self._run(["plasma-apply-colorscheme", cs])
            self._kwrite("plasmarc", ["Theme"], "name", pt)
            self._kwrite("kdeglobals", ["General"], "ColorScheme", cs)
            self._kwrite("kdeglobals", ["Icons"], "Theme", ic)
            self._kwrite("kwinrc", ["org.kde.kdecoration2"], "theme", wd)
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-application-prefer-dark-theme": gtk_dark, "gtk-icon-theme-name": ic})
            self._update_gtk2({"gtk-icon-theme-name": f'"{ic}"'})
            self._gsettings_set("org.gnome.desktop.interface", "color-scheme", "prefer-dark" if is_dark else "prefer-light")
            self._gsettings_set("org.gnome.desktop.interface", "icon-theme", ic)
            self._emit_kglobal_change(0)
            self._emit_icon_change()
            self._emit_darkly_reload()
            self._reconfigure_kwin()
            return
        if sid == "appearance.plasmaTheme":
            if not self.skip_live:
                self._run(["plasma-apply-desktoptheme", str(value)])
            self._kwrite("plasmarc", ["Theme"], "name", value)
            return
        if sid == "appearance.colorScheme":
            if not self.skip_live:
                self._run(["plasma-apply-colorscheme", str(value)])
            self._kwrite("kdeglobals", ["General"], "ColorScheme", value)
            self._emit_kglobal_change(0)
            self._emit_darkly_reload()
            return
        if sid == "appearance.windowDecoration":
            self._kwrite("kwinrc", ["org.kde.kdecoration2"], "library", "org.kde.kwin.aurorae.v2")
            self._kwrite("kwinrc", ["org.kde.kdecoration2"], "theme", value)
            self._reconfigure_kwin()
            return
        if sid == "appearance.buttonLayout":
            if value == "macos_left":
                self._kwrite("kwinrc", ["org.kde.kdecoration2"], "ButtonsOnLeft", "XIA")
                self._kwrite("kwinrc", ["org.kde.kdecoration2"], "ButtonsOnRight", "")
                gtk_lay = "close,minimize,maximize:menu"
            else:
                self._kwrite("kwinrc", ["org.kde.kdecoration2"], "ButtonsOnLeft", "MS")
                self._kwrite("kwinrc", ["org.kde.kdecoration2"], "ButtonsOnRight", "IAX")
                gtk_lay = "menu:minimize,maximize,close"
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-decoration-layout": gtk_lay})
            self._gsettings_set("org.gnome.desktop.wm.preferences", "button-layout", gtk_lay)
            self._reconfigure_kwin()
            return
        if sid == "appearance.iconTheme":
            self._kwrite("kdeglobals", ["Icons"], "Theme", value)
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-icon-theme-name": str(value)})
            self._update_gtk2({"gtk-icon-theme-name": f'"{value}"'})
            self._gsettings_set("org.gnome.desktop.interface", "icon-theme", str(value))
            self._emit_icon_change()
            return
        if sid == "appearance.widgetStyle":
            self._kwrite("kdeglobals", ["KDE"], "widgetStyle", value)
            self._emit_kglobal_change(2)
            if str(value) == "Darkly":
                self._emit_darkly_reload()
            return
        if sid.startswith("dock_bar."):
            self._save_panel_setting(sid, value)
            return
        if sid == "blur_effects.blurEnabled":
            self._kwrite("kwinrc", ["Plugins"], "blurEnabled", value)
            self._kwin_effect_toggle("blur", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "blur_effects.blurStrength":
            self._kwrite("kwinrc", ["Effect-blur"], "BlurStrength", value)
            self._kwin_effect_reconfigure("blur")
            self._reconfigure_kwin()
            return
        if sid == "blur_effects.noiseStrength":
            self._kwrite("kwinrc", ["Effect-blur"], "NoiseStrength", value)
            self._kwin_effect_reconfigure("blur")
            self._reconfigure_kwin()
            return
        if sid == "blur_effects.translucencyEnabled":
            self._kwrite("kwinrc", ["Plugins"], "translucencyEnabled", value)
            self._kwin_effect_toggle("translucency", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "blur_effects.darklyTranslucent":
            self._kwrite("darklyrc", ["Style"], "TransparentDolphinView", value)
            self._kwrite("darklyrc", ["Style"], "TranslucentWindows", value)
            self._emit_darkly_reload()
            return
        if sid == "blur_effects.darklyMenuOpacity":
            self._kwrite("darklyrc", ["Style"], "MenuOpacity", value)
            self._emit_darkly_reload()
            return
        if sid == "blur_effects.darklyCornerRadius":
            self._kwrite("darklyrc", ["Style"], "CornerRadius", value)
            self._emit_darkly_reload()
            return
        if sid == "animations.durationFactor":
            self._kwrite("kdeglobals", ["KDE"], "AnimationDurationFactor", value)
            self._kwrite("kwinrc", ["KDE"], "AnimationDurationFactor", value)
            self._emit_kglobal_change(2)
            self._reconfigure_kwin()
            return
        if sid == "animations.magicLampEnabled":
            self._kwrite("kwinrc", ["Plugins"], "magiclampEnabled", value)
            self._kwrite("kwinrc", ["Plugins"], "squashEnabled", not value)
            self._kwin_effect_toggle("squash", not bool(value))
            self._kwin_effect_toggle("magiclamp", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "animations.magicLampDuration":
            self._kwrite("kwinrc", ["Effect-magiclamp"], "AnimationDuration", value)
            self._kwin_effect_reconfigure("magiclamp")
            self._reconfigure_kwin()
            return
        if sid == "animations.glowEnabled":
            self._kwrite("kwinrc", ["Plugins"], "glowEnabled", value)
            if value:
                self._kwrite("kwinrc", ["Plugins"], "scaleEnabled", False)
                self._kwin_effect_toggle("scale", False)
            self._kwin_effect_toggle("glow", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "animations.glowDuration":
            self._kwrite("kwinrc", ["Effect-glow"], "Duration", value)
            self._kwin_effect_reconfigure("glow")
            self._reconfigure_kwin()
            return
        if sid == "animations.slideEnabled":
            self._kwrite("kwinrc", ["Plugins"], "slideEnabled", value)
            self._kwin_effect_toggle("slide", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "animations.virtualDesktops":
            self._kwrite("kwinrc", ["Desktops"], "Number", value)
            self._kwrite("kwinrc", ["Desktops"], "Rows", 1)
            self._sync_virtual_desktops(int(value))
            self._reconfigure_kwin()
            return
        if sid == "wallpaper_lock.desktopWallpaper":
            if not self.skip_live:
                self._run(["plasma-apply-wallpaperimage", str(value)])
            else:
                applets = self.config_home / "plasma-org.kde.plasma.desktop-appletsrc"
                applets.parent.mkdir(parents=True, exist_ok=True)
                applets.write_text(f"[Containments][1][Wallpaper][org.kde.image][General]\nImage=file://{value}\n", encoding="utf-8")
            return
        if sid == "wallpaper_lock.lockscreenWallpaper":
            self._kwrite("kscreenlockerrc", ["Greeter"], "WallpaperPlugin", "org.kde.image")
            self._kwrite("kscreenlockerrc", ["Greeter", "Wallpaper", "org.kde.image", "General"], "Image", f"file://{value}")
            self._reload_screenlocker()
            return
        if sid == "wallpaper_lock.autolock":
            self._kwrite("kscreenlockerrc", ["Daemon"], "Autolock", value)
            self._reload_screenlocker()
            return
        if sid == "cursor.shakeCursorEnabled":
            self._kwrite("kwinrc", ["Plugins"], "shakecursorEnabled", value)
            self._kwin_effect_toggle("shakecursor", bool(value))
            self._reconfigure_kwin()
            return
        if sid == "cursor.theme":
            cur_sz = str(self.get_setting("cursor.size"))
            if not self.skip_live:
                # Run plasma-apply-cursortheme BEFORE overwriting kcminputrc so it doesn't short-circuit
                self._run(["plasma-apply-cursortheme", str(value), "--size", cur_sz])
            self._kwrite("kcminputrc", ["Mouse"], "cursorTheme", value)
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-cursor-theme-name": str(value)})
            self._update_gtk2({"gtk-cursor-theme-name": f'"{value}"'})
            self._gsettings_set("org.gnome.desktop.interface", "cursor-theme", str(value))
            return
        if sid == "cursor.size":
            cur_th = str(self.get_setting("cursor.theme"))
            if not self.skip_live:
                self._run(["plasma-apply-cursortheme", cur_th, "--size", str(value)])
            self._kwrite("kcminputrc", ["Mouse"], "cursorSize", value)
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-cursor-theme-size": str(value)})
            self._update_gtk2({"gtk-cursor-theme-size": str(value)})
            self._gsettings_set("org.gnome.desktop.interface", "cursor-size", str(value))
            return
        if sid == "typography.generalFont":
            self._kwrite("kdeglobals", ["General"], "font", value)
            self._kwrite("kdeglobals", ["General"], "menuFont", value)
            self._kwrite("kdeglobals", ["General"], "toolBarFont", value)
            fam = str(value).split(",")[0].strip()
            sz = str(value).split(",")[1].strip() if "," in str(value) else "10"
            for gv in ("gtk-3.0", "gtk-4.0"):
                self._update_gtk_ini(gv, {"gtk-font-name": f"{fam} {sz}"})
            self._update_gtk2({"gtk-font-name": f'"{fam} {sz}"'})
            self._gsettings_set("org.gnome.desktop.interface", "font-name", f"{fam} {sz}")
            self._emit_kglobal_change(1)
            return
        if sid == "typography.fixedFont":
            self._kwrite("kdeglobals", ["General"], "fixed", value)
            self._emit_kglobal_change(1)
            return
        if sid == "typography.titleFont":
            self._kwrite("kdeglobals", ["WM"], "activeFont", value)
            self._emit_kglobal_change(1)
            self._reconfigure_kwin()
            return

    def _load_undo_stack(self) -> list[dict[str, Any]]:
        if not self.undo_path.is_file():
            return []
        try:
            data = json.loads(self.undo_path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except Exception:
            return []

    def _save_undo_stack(self, stack: list[dict[str, Any]]) -> None:
        self._write_private_json(self.undo_path, stack[-50:])

    def set_settings(self, updates: dict[str, Any], *, action_label: str = "set") -> dict[str, Any]:
        self.ensure_baseline()
        expanded: dict[str, Any] = {}
        for sid, val in updates.items():
            if sid == "wallpaper.path":
                expanded["wallpaper_lock.desktopWallpaper"] = val
                expanded["wallpaper_lock.lockscreenWallpaper"] = val
            else:
                expanded[self._resolve_sid(sid)] = val
        validated = {sid: self.validate_value(sid, val) for sid, val in expanded.items()}
        before_values = {sid: self.get_setting(sid) for sid in validated}
        changed = {sid: val for sid, val in validated.items() if before_values[sid] != val}
        if not changed:
            return {"status": "no_changes", "runtimeVerified": True, "values": before_values}

        target_files: list[pathlib.Path] = []
        seen_paths: set[str] = set()
        for sid in changed:
            for p in self._target_files_for(sid):
                if str(p) not in seen_paths:
                    seen_paths.add(str(p))
                    target_files.append(p)

        file_snapshots = []
        for p in target_files:
            file_snapshots.append({
                "path": str(p),
                "existed": p.is_file(),
                "beforeSha256": self._file_sha256(p),
                "beforeContent": p.read_text(encoding="utf-8", errors="ignore") if p.is_file() else None,
            })

        for sid, val in changed.items():
            self._apply_single_no_undo(sid, val)

        for snap in file_snapshots:
            p = pathlib.Path(snap["path"])
            snap["afterSha256"] = self._file_sha256(p)

        stack = self._load_undo_stack()
        stack.append({
            "id": f"act-{int(time.time() * 1000)}",
            "label": action_label,
            "timestamp": int(time.time()),
            "undone": False,
            "beforeValues": {sid: before_values[sid] for sid in changed},
            "afterValues": changed,
            "files": file_snapshots,
        })
        self._save_undo_stack(stack)
        if not self.skip_live:
            self.sync_plasma_shared()
        active_undo = sum(1 for a in stack if not a.get("undone"))
        return {"status": "ok", "runtimeVerified": True, "changed": changed, "undoCount": active_undo}

    def undo_last(self) -> dict[str, Any]:
        stack = self._load_undo_stack()
        target_idx = None
        for idx in range(len(stack) - 1, -1, -1):
            if not stack[idx].get("undone"):
                target_idx = idx
                break
        if target_idx is None:
            raise NexusPlasmaError("nothing_to_undo", "No recorded actions to undo.")
        last = stack[target_idx]
        for snap in last.get("files", []):
            p = pathlib.Path(snap["path"])
            cur_sha = self._file_sha256(p)
            if cur_sha != snap.get("afterSha256"):
                raise NexusPlasmaError(
                    "undo_conflict",
                    f"File was modified externally since last Control Center action: {p}",
                )
        for snap in last.get("files", []):
            p = pathlib.Path(snap["path"])
            if snap["existed"]:
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(snap["beforeContent"] or "", encoding="utf-8")
            elif p.exists():
                p.unlink()
        last["undone"] = True
        self._save_undo_stack(stack)
        if not self.skip_live:
            for sid, old_val in last.get("beforeValues", {}).items():
                try:
                    self._apply_single_no_undo(sid, old_val)
                except Exception:
                    pass
            self._reconfigure_kwin()
            self.sync_plasma_shared()
        active_undo = sum(1 for a in stack if not a.get("undone"))
        return {"status": "ok", "undoneAction": last["id"], "restoredValues": last["beforeValues"], "undoCount": active_undo}

    def reset(self, *, category: str | None = None, setting_id: str | None = None, reset_all: bool = False) -> dict[str, Any]:
        if not self.initial_state_path.is_file():
            raise NexusPlasmaError("baseline_missing", "Initial baseline has not been captured yet.")
        baseline = json.loads(self.initial_state_path.read_text(encoding="utf-8"))
        saved = baseline.get("values", {})
        if setting_id:
            sid = self._resolve_sid(setting_id)
            if sid not in saved:
                raise NexusPlasmaError("baseline_value_missing", f"No baseline value for {sid}")
            targets = {sid: saved[sid]}
        elif reset_all:
            targets = {sid: saved[sid] for sid in self.settings_by_id if sid in saved}
        elif category:
            targets = {
                sid: saved[sid]
                for sid, defn in self.settings_by_id.items()
                if defn["category"] == category and sid in saved
            }
            if not targets:
                raise NexusPlasmaError("unknown_category", f"No baseline settings for category: {category}")
        else:
            raise NexusPlasmaError("invalid_reset", "Specify setting_id, --category, or --all")
        return self.set_settings(targets, action_label=f"reset:{setting_id or category or 'all'}")

    def apply_animation_preset(self, preset: str) -> dict[str, Any]:
        presets = {
            "macos_smooth": {
                "animations.durationFactor": 1.0,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 280,
                "animations.glowEnabled": True,
                "animations.glowDuration": 750,
                "animations.slideEnabled": True,
            },
            "macos": {
                "animations.durationFactor": 1.0,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 280,
                "animations.glowEnabled": True,
                "animations.glowDuration": 750,
                "animations.slideEnabled": True,
            },
            "macOS Dengeli": {
                "animations.durationFactor": 1.0,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 280,
                "animations.glowEnabled": True,
                "animations.glowDuration": 750,
                "animations.slideEnabled": True,
            },
            "snappy": {
                "animations.durationFactor": 0.75,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 200,
                "animations.glowEnabled": True,
                "animations.glowDuration": 500,
                "animations.slideEnabled": True,
            },
            "Seri": {
                "animations.durationFactor": 0.7,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 200,
                "animations.glowEnabled": True,
                "animations.glowDuration": 500,
                "animations.slideEnabled": True,
            },
            "cinematic": {
                "animations.durationFactor": 1.25,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 360,
                "animations.glowEnabled": True,
                "animations.glowDuration": 950,
                "animations.slideEnabled": True,
            },
            "Yumuşak": {
                "animations.durationFactor": 1.35,
                "animations.magicLampEnabled": True,
                "animations.magicLampDuration": 360,
                "animations.glowEnabled": True,
                "animations.glowDuration": 950,
                "animations.slideEnabled": True,
            },
            "reduced_motion": {
                "animations.durationFactor": 0.5,
                "animations.magicLampEnabled": False,
                "animations.glowEnabled": False,
                "animations.slideEnabled": False,
            },
            "off": {
                "animations.durationFactor": 0.0,
                "animations.magicLampEnabled": False,
                "animations.glowEnabled": False,
                "animations.slideEnabled": False,
            },
            "Kapalı": {
                "animations.durationFactor": 0.0,
                "animations.magicLampEnabled": False,
                "animations.glowEnabled": False,
                "animations.slideEnabled": False,
            },
        }
        if preset not in presets:
            raise NexusPlasmaError("unknown_preset", f"Unknown animation preset: {preset}")
        return self.set_settings(presets[preset], action_label=f"preset:{preset}")

    @staticmethod
    def _validate_profile_name(name: str) -> str:
        raw = name.strip()
        if not raw or "/" in raw or "\\" in raw or ".." in raw or not PROFILE_NAME_RE.match(raw):
            raise NexusPlasmaError("profile_name_invalid", f"Invalid profile name: {name!r}")
        return raw

    def list_profiles(self) -> list[dict[str, Any]]:
        if not self.profiles_dir.is_dir():
            return []
        out = []
        for p in sorted(self.profiles_dir.glob("*.json")):
            try:
                d = json.loads(p.read_text(encoding="utf-8"))
                out.append({"name": p.stem, "savedAt": d.get("savedAt", 0), "settingCount": len(d.get("values", {}))})
            except Exception:
                continue
        return out

    def save_profile(self, name: str) -> dict[str, Any]:
        clean = self._validate_profile_name(name)
        path = self.profiles_dir / f"{clean}.json"
        payload = {"name": clean, "savedAt": int(time.time()), "values": self.get_all_values()}
        self._write_private_json(path, payload)
        return {"status": "ok", "name": clean, "path": str(path)}

    def copy_profile(self, src_name: str, dst_name: str) -> dict[str, Any]:
        src = self._validate_profile_name(src_name)
        dst = self._validate_profile_name(dst_name)
        src_path = self.profiles_dir / f"{src}.json"
        if not src_path.is_file():
            raise NexusPlasmaError("profile_not_found", f"Profile not found: {src}")
        try:
            payload = json.loads(src_path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise NexusPlasmaError("profile_invalid", f"Corrupted profile JSON: {exc}")
        payload["name"] = dst
        payload["savedAt"] = int(time.time())
        dst_path = self.profiles_dir / f"{dst}.json"
        self._write_private_json(dst_path, payload)
        return {"status": "ok", "source": src, "name": dst, "path": str(dst_path)}

    def load_profile(self, name: str) -> dict[str, Any]:
        clean = self._validate_profile_name(name)
        path = self.profiles_dir / f"{clean}.json"
        if not path.is_file():
            raise NexusPlasmaError("profile_not_found", f"Profile not found: {clean}")
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise NexusPlasmaError("profile_invalid", f"Corrupted profile JSON: {exc}")
        if not isinstance(payload, dict) or not isinstance(payload.get("values"), dict):
            raise NexusPlasmaError("profile_invalid", "Profile JSON missing 'values' object.")
        vals = {self._resolve_sid(k): v for k, v in payload["values"].items() if self._resolve_sid(k) in self.settings_by_id}
        return self.set_settings(vals, action_label=f"profile-load:{clean}")

    def delete_profile(self, name: str) -> dict[str, Any]:
        clean = self._validate_profile_name(name)
        path = self.profiles_dir / f"{clean}.json"
        if not path.is_file():
            raise NexusPlasmaError("profile_not_found", f"Profile not found: {clean}")
        path.unlink()
        return {"status": "ok", "deleted": clean}

    def check_hyprland_isolation(self) -> dict[str, Any]:
        iso_dir = self.state_home / "kde-macos" / "isolation"
        hypr_shared = iso_dir / "hyprland-shared"
        plasma_shared = iso_dir / "plasma-macos-shared"
        snapshots_ok = (hypr_shared / "kdeglobals").is_file() and (plasma_shared / "kdeglobals").is_file()

        manifest = self.state_home / "kde-macos" / "backups" / "latest" / "HYPRLAND_SHA256SUMS"
        manifest_ok = True
        detail = ""
        if manifest.is_file() and not self.skip_live:
            r = self._run(["sha256sum", "-c", "--quiet", str(manifest)], timeout=20)
            manifest_ok = r.returncode == 0
            detail = (r.stdout + r.stderr).strip()
        elif not manifest.is_file():
            manifest_ok = False
            detail = f"Missing manifest: {manifest}"

        ok = snapshots_ok and manifest_ok
        return {
            "status": "ok" if ok else "degraded",
            "verified": ok,
            "healthy": ok,
            "snapshotsOk": snapshots_ok,
            "manifest": str(manifest),
            "detail": detail,
        }

    def sync_plasma_shared(self) -> dict[str, Any]:
        plasma_snap = self.state_home / "kde-macos" / "isolation" / "plasma-macos-shared"
        plasma_snap.mkdir(parents=True, exist_ok=True)
        copied = []
        for rel in ("kdeglobals", "gtk-3.0", "gtk-4.0"):
            src = self.config_home / rel
            dst = plasma_snap / rel
            if src.exists():
                if src.is_dir():
                    if dst.exists():
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)
                copied.append(rel)
        gtk2 = self.home_dir / ".gtkrc-2.0"
        if gtk2.is_file():
            shutil.copy2(gtk2, plasma_snap / "gtkrc-2.0")
            shutil.copy2(gtk2, plasma_snap / ".gtkrc-2.0")
            copied.append(".gtkrc-2.0")
        return {"status": "ok", "synced": copied, "target": str(plasma_snap)}

    def status_summary(self) -> dict[str, Any]:
        self.ensure_baseline()
        return {
            "status": "ok",
            "schema": self.catalog["schema"],
            "catalog": self.catalog,
            "categories": self.catalog["categories"],
            "settings": self.catalog["settings"],
            "values": self.get_all_values(),
            "undoCount": sum(1 for a in self._load_undo_stack() if not a.get("undone")),
            "profiles": self.list_profiles(),
            "hyprlandIsolation": self.check_hyprland_isolation(),
        }


def _parse_cli_value(raw: str) -> Any:
    s = raw.strip()
    if s in ("true", "false"):
        return s == "true"
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("{") and s.endswith("}")) or (s.startswith("[") and s.endswith("]")):
        try:
            return json.loads(s)
        except Exception:
            return raw
    return raw


def main(argv: list[str] | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    raw_argv = [a for a in raw_argv if a != "--json"]

    parser = argparse.ArgumentParser(description="NEXUS-Plasma Control Center CLI")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("initialize")
    sub.add_parser("status")
    sub.add_parser("catalog")
    sub.add_parser("catalog-state")
    p_get = sub.add_parser("get")
    p_get.add_argument("setting_id", nargs="?")
    for alias in ("set", "setting-set"):
        p_set = sub.add_parser(alias)
        p_set.add_argument("setting_id")
        p_set.add_argument("value")
    p_cur = sub.add_parser("cursor-set")
    p_cur.add_argument("theme")
    p_cur.add_argument("size", nargs="?", default="24")
    sub.add_parser("toggle-dark-light")
    for alias in ("preset", "motion-preset"):
        p_pre = sub.add_parser(alias)
        p_pre.add_argument("name")
    sub.add_parser("undo")
    p_res = sub.add_parser("reset")
    p_res.add_argument("setting_id", nargs="?")
    p_res.add_argument("--category")
    p_res.add_argument("--all", action="store_true")
    p_rcat = sub.add_parser("reset-category")
    p_rcat.add_argument("category")
    sub.add_parser("reset-all")
    sub.add_parser("profile-list")
    p_ps = sub.add_parser("profile-save")
    p_ps.add_argument("name")
    p_pl = sub.add_parser("profile-load")
    p_pl.add_argument("name")
    p_pc = sub.add_parser("profile-copy")
    p_pc.add_argument("src")
    p_pc.add_argument("dst")
    p_pd = sub.add_parser("profile-delete")
    p_pd.add_argument("name")
    sub.add_parser("hyprland-isolation-check")
    sub.add_parser("isolation-status")
    sub.add_parser("sync-isolation")

    args = parser.parse_args(raw_argv)
    be = NexusPlasmaBackend()
    try:
        if args.cmd == "initialize":
            res = {"status": "ok", "baseline": be.ensure_baseline()}
        elif args.cmd in ("status", "catalog-state"):
            res = be.status_summary()
        elif args.cmd == "catalog":
            res = be.catalog
        elif args.cmd == "get":
            res = {"status": "ok", "values": {args.setting_id: be.get_setting(args.setting_id)}} if args.setting_id else {"status": "ok", "values": be.get_all_values()}
        elif args.cmd in ("set", "setting-set"):
            res = be.set_settings({args.setting_id: _parse_cli_value(args.value)})
        elif args.cmd == "cursor-set":
            res = be.set_settings({"cursor.theme": args.theme, "cursor.size": args.size}, action_label="cursor-set")
        elif args.cmd == "toggle-dark-light":
            cur = be.get_setting("appearance.colorMode")
            nxt = "light" if cur == "dark" else "dark"
            res = be.set_settings({"appearance.colorMode": nxt}, action_label="toggle-dark-light")
        elif args.cmd in ("preset", "motion-preset"):
            res = be.apply_animation_preset(args.name)
        elif args.cmd == "undo":
            res = be.undo_last()
        elif args.cmd == "reset":
            res = be.reset(category=args.category, setting_id=args.setting_id, reset_all=args.all)
        elif args.cmd == "reset-category":
            res = be.reset(category=args.category)
        elif args.cmd == "reset-all":
            res = be.reset(reset_all=True)
        elif args.cmd == "profile-list":
            details = be.list_profiles()
            res = {"status": "ok", "profiles": [p["name"] for p in details], "details": details}
        elif args.cmd == "profile-save":
            res = be.save_profile(args.name)
        elif args.cmd == "profile-load":
            res = be.load_profile(args.name)
        elif args.cmd == "profile-copy":
            res = be.copy_profile(args.src, args.dst)
        elif args.cmd == "profile-delete":
            res = be.delete_profile(args.name)
        elif args.cmd in ("hyprland-isolation-check", "isolation-status"):
            res = be.check_hyprland_isolation()
        elif args.cmd == "sync-isolation":
            res = be.sync_plasma_shared()
        else:
            raise NexusPlasmaError("unknown_command", f"Unsupported command: {args.cmd}")
        print(json.dumps(res, ensure_ascii=False))
        return 0
    except NexusPlasmaError as exc:
        print(json.dumps({"status": "error", "code": exc.code, "message": exc.message}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
