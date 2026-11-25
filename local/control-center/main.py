#!/usr/bin/env python3
"""NEXUS-Plasma Control Center GUI (PySide6 + QtQuick/QML)."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

from PySide6.QtCore import QObject, Property, Signal, Slot, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from nexus_plasma_backend import NexusPlasmaBackend, NexusPlasmaError


class NexusPlasmaBridge(QObject):
    stateChanged = Signal()
    statusMessageChanged = Signal(str)

    def __init__(self, backend: NexusPlasmaBackend, parent: QObject | None = None):
        super().__init__(parent)
        self._backend = backend
        self._state = backend.status_summary()
        self._status_message = "Hazır — tüm değişiklikler geri alınabilir (Undo)."

    def _reload(self, msg: str | None = None) -> None:
        self._state = self._backend.status_summary()
        if msg is not None:
            self._status_message = msg
            self.statusMessageChanged.emit(msg)
        self.stateChanged.emit()

    @Property(str, notify=stateChanged)
    def stateJson(self) -> str:
        return json.dumps(self._state, ensure_ascii=False)

    @Property(str, notify=statusMessageChanged)
    def statusMessage(self) -> str:
        return self._status_message

    @Slot(str, "QVariant", result=bool)
    def setSetting(self, setting_id: str, value) -> bool:
        try:
            res = self._backend.set_settings({setting_id: value})
            if res.get("status") == "no_changes":
                return True
            self._reload(f"Uygulandı: {setting_id}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Hata ({exc.code}): {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(result=bool)
    def toggleDarkLight(self) -> bool:
        try:
            cur = self._backend.get_setting("appearance.colorMode")
            nxt = "light" if cur == "dark" else "dark"
            self._backend.set_settings({"appearance.colorMode": nxt}, action_label="toggle-dark-light")
            self._reload(f"Tema kipi değiştirildi: {'Açık (WhiteSur)' if nxt == 'light' else 'Koyu (WhiteSur-dark)'}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Hata: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(str, result=bool)
    def applyPreset(self, preset_name: str) -> bool:
        try:
            self._backend.apply_animation_preset(preset_name)
            self._reload(f"Animasyon profili uygulandı: {preset_name}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Hata: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(result=bool)
    def undoLast(self) -> bool:
        try:
            res = self._backend.undo_last()
            self._reload(f"Geri alındı: {res.get('undoneAction')}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Geri alma hatası ({exc.code}): {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(str, result=bool)
    def resetCategory(self, category: str) -> bool:
        try:
            self._backend.reset(category=category)
            self._reload(f"Kategori varsayılanlara döndürüldü: {category}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Sıfırlama hatası: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(result=bool)
    def resetAll(self) -> bool:
        try:
            self._backend.reset(reset_all=True)
            self._reload("Tüm ayarlar başlangıç durumuna döndürüldü.")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Sıfırlama hatası: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(str, result=bool)
    def saveProfile(self, name: str) -> bool:
        try:
            res = self._backend.save_profile(name)
            self._reload(f"Profil kaydedildi: {res['name']}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Profil hatası: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(str, result=bool)
    def loadProfile(self, name: str) -> bool:
        try:
            self._backend.load_profile(name)
            self._reload(f"Profil yüklendi: {name}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Profil yükleme hatası: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot(str, result=bool)
    def deleteProfile(self, name: str) -> bool:
        try:
            self._backend.delete_profile(name)
            self._reload(f"Profil silindi: {name}")
            return True
        except NexusPlasmaError as exc:
            self._status_message = f"Profil silme hatası: {exc.message}"
            self.statusMessageChanged.emit(self._status_message)
            return False

    @Slot()
    def refresh(self) -> None:
        self._reload("Durum yenilendi.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="macOS Control Center — Plasma Settings")
    parser.add_argument("--smoke-test", "--check", dest="smoke_test", action="store_true", help="Load QML offscreen and exit cleanly after verification")
    args = parser.parse_args(argv)

    app = QGuiApplication(sys.argv[:1])
    app.setApplicationName("macOS Control Center")
    app.setOrganizationName("macos-control-center")

    backend = NexusPlasmaBackend()
    bridge = NexusPlasmaBridge(backend)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("nexusBridge", bridge)
    qml_path = SCRIPT_DIR / "ui" / "MainWindow.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path)))

    if not engine.rootObjects():
        print("ERROR: Failed to load MainWindow.qml", file=sys.stderr)
        return 1

    if args.smoke_test:
        root_obj = engine.rootObjects()[0]
        state = json.loads(bridge.stateJson)
        print(
            f"SMOKE_OK categories={len(state['categories'])} settings={len(state['settings'])} "
            f"title={root_obj.property('title')!r}"
        )
        QTimer.singleShot(150, app.quit)

    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
