#!/usr/bin/env python3
"""Unit and offscreen QtQuick smoke tests for NEXUS-Plasma Control Center."""

from __future__ import annotations

import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

CC_DIR = pathlib.Path(__file__).resolve().parents[1]
if str(CC_DIR) not in sys.path:
    sys.path.insert(0, str(CC_DIR))

from nexus_plasma_backend import NexusPlasmaBackend, NexusPlasmaError


class NexusPlasmaBackendTests(unittest.TestCase):
    def _make_backend(self, td: str) -> NexusPlasmaBackend:
        root = pathlib.Path(td)
        (root / ".local/share/icons/WhiteSur-cursors/cursors").mkdir(parents=True, exist_ok=True)
        wp = root / "Pictures/Wallpapers/sonoma-plasma-default.jpg"
        wp.parent.mkdir(parents=True, exist_ok=True)
        wp.write_bytes(b"\xff\xd8\xff\xd9")
        old_home = os.environ.get("HOME", "")
        os.environ["HOME"] = str(root)
        self.addCleanup(lambda: os.environ.__setitem__("HOME", old_home))
        return NexusPlasmaBackend(
            home_dir=root,
            config_home=root / ".config",
            state_home=root / ".local/state",
            data_home=root / ".local/share",
            skip_live=True,
        )

    def test_set_read_undo_and_conflict_detection(self):
        with tempfile.TemporaryDirectory(prefix="nexus_plasma_test_") as td:
            be = self._make_backend(td)
            self.assertEqual(be.get_setting("blur_effects.blurStrength"), 11)

            res = be.set_settings({"blur_effects.blurStrength": 14, "cursor.shakeCursorEnabled": False})
            self.assertEqual(res["status"], "ok")
            self.assertEqual(be.get_setting("blur_effects.blurStrength"), 14)
            self.assertFalse(be.get_setting("cursor.shakeCursorEnabled"))

            # Undo restores previous value cleanly
            u = be.undo_last()
            self.assertEqual(u["status"], "ok")
            self.assertEqual(be.get_setting("blur_effects.blurStrength"), 11)

            # External modification triggers undo_conflict without clobbering
            be.set_settings({"blur_effects.blurStrength": 12})
            kwinrc = be.config_home / "kwinrc"
            kwinrc.write_text(kwinrc.read_text() + "\n# external edit\n", encoding="utf-8")
            with self.assertRaises(NexusPlasmaError) as ctx:
                be.undo_last()
            self.assertEqual(ctx.exception.code, "undo_conflict")

    def test_glow_darkly_dock_and_ui_branding_clean(self):
        with tempfile.TemporaryDirectory(prefix="nexus_plasma_glow_") as td:
            be = self._make_backend(td)
            be.set_settings({"animations.glowEnabled": False})
            be.set_settings({"animations.glowEnabled": True, "animations.glowDuration": 850})
            self.assertTrue(be.get_setting("animations.glowEnabled"))
            self.assertEqual(be.get_setting("animations.glowDuration"), 850)
            self.assertEqual(be._kread("kwinrc", ["Plugins"], "scaleEnabled", ""), "false")

            be.apply_animation_preset("snappy")
            self.assertTrue(be.get_setting("animations.glowEnabled"))
            self.assertEqual(be.get_setting("animations.glowDuration"), 500)
            self.assertEqual(be._kread("kwinrc", ["Plugins"], "scaleEnabled", ""), "false")

            be.set_settings({"blur_effects.darklyTranslucent": False})
            self.assertFalse(be.get_setting("blur_effects.darklyTranslucent"))
            self.assertEqual(be._kread("darklyrc", ["Style"], "TransparentDolphinView", ""), "false")

            be.set_settings({"dock_bar.dockHiding": "normal"})
            self.assertEqual(be.get_setting("dock_bar.dockHiding"), "none")

        qml_txt = (CC_DIR / "ui" / "MainWindow.qml").read_text(encoding="utf-8")
        self.assertNotIn("NEXUS", qml_txt)
        self.assertNotIn("Hyprland İzolasyonu", qml_txt)
        self.assertNotIn("Hyprland İzo", qml_txt)
        cat_txt = (CC_DIR / "settings_catalog.json").read_text(encoding="utf-8")
        self.assertNotIn("Hyprland", cat_txt)
        self.assertNotIn("NEXUS", cat_txt)

    def test_dark_light_toggle_and_validation_bounds(self):
        with tempfile.TemporaryDirectory(prefix="nexus_plasma_dl_") as td:
            be = self._make_backend(td)
            be.set_settings({"appearance.colorMode": "light"})
            self.assertEqual(be.get_setting("appearance.colorMode"), "light")
            self.assertEqual(be.get_setting("appearance.plasmaTheme"), "WhiteSur-light")
            self.assertEqual(be.get_setting("appearance.colorScheme"), "WhiteSurLight")

            be.set_settings({"appearance.colorMode": "dark"})
            self.assertEqual(be.get_setting("appearance.colorMode"), "dark")
            self.assertEqual(be.get_setting("appearance.plasmaTheme"), "WhiteSur-dark")

            with self.assertRaises(NexusPlasmaError) as ctx:
                be.set_settings({"cursor.size": 999})
            self.assertEqual(ctx.exception.code, "values_invalid")

            with self.assertRaises(NexusPlasmaError) as ctx2:
                be.set_settings({"dock_bar.dockHiding": "invalid_mode"})
            self.assertEqual(ctx2.exception.code, "values_invalid")

    def test_profiles_presets_and_baseline_reset(self):
        with tempfile.TemporaryDirectory(prefix="nexus_plasma_prof_") as td:
            be = self._make_backend(td)
            be.ensure_baseline()
            be.apply_animation_preset("snappy")
            self.assertEqual(be.get_setting("animations.magicLampDuration"), 200)
            self.assertEqual(be.get_setting("animations.durationFactor"), 0.75)

            be.save_profile("fast-work")
            profs = be.list_profiles()
            self.assertEqual([p["name"] for p in profs], ["fast-work"])

            be.reset(category="animations")
            self.assertEqual(be.get_setting("animations.magicLampDuration"), 280)

            be.load_profile("fast-work")
            self.assertEqual(be.get_setting("animations.magicLampDuration"), 200)

            be.delete_profile("fast-work")
            self.assertEqual(be.list_profiles(), [])

    def test_qmllint_and_offscreen_smoke_launch(self):
        qml_path = CC_DIR / "ui" / "MainWindow.qml"
        r_lint = subprocess.run(["qmllint-qt6", "--bare", str(qml_path)], capture_output=True, text=True)
        self.assertEqual(r_lint.returncode, 0, r_lint.stdout + r_lint.stderr)

        with tempfile.TemporaryDirectory(prefix="nexus_plasma_ui_") as td:
            env = dict(os.environ)
            env["QT_QPA_PLATFORM"] = "offscreen"
            env["KDE_MACOS_SKIP_LIVE_SERVICES"] = "1"
            env["HOME"] = td
            env["XDG_CONFIG_HOME"] = f"{td}/.config"
            env["XDG_STATE_HOME"] = f"{td}/.local/state"
            env["XDG_DATA_HOME"] = f"{td}/.local/share"
            r_ui = subprocess.run(
                ["python3", str(CC_DIR / "main.py"), "--smoke-test"],
                env=env,
                capture_output=True,
                text=True,
                timeout=20,
            )
            out = r_ui.stdout + "\n" + r_ui.stderr
            self.assertEqual(r_ui.returncode, 0, out)
            self.assertIn("SMOKE_OK categories=8 settings=34", out)
            self.assertIn("macOS Control Center — Plasma Settings", out)
            self.assertNotIn("NEXUS", out)


if __name__ == "__main__":
    unittest.main()
