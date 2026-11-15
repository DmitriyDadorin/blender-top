"""Package an existing Drive.app as a drag-to-Applications disk image on macOS."""
import argparse
import hashlib
import json
import platform
import plistlib
import subprocess
import tempfile
from pathlib import Path

try:
    import dmgbuild
except ImportError:
    raise SystemExit("Install tools/requirements-macos.txt in a Python virtual environment first.")

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=ROOT / "build" / "macos-arm64")
args = parser.parse_args()
if platform.system() != "Darwin":
    raise SystemExit("Run this script on macOS.")

output = args.output.resolve()
app = output / "Drive" / "Drive.app"
with (app / "Contents" / "Info.plist").open("rb") as file:
    info = plistlib.load(file)
version = info["CFBundleShortVersionString"]
executable = app / "Contents" / "MacOS" / info["CFBundleExecutable"]
architectures = subprocess.check_output(["lipo", "-archs", executable], text=True).strip()
if architectures != "arm64":
    raise SystemExit("Expected a native arm64 application, got " + architectures)
subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)

installer = output / f"Drive-macOS-arm64-{version}.dmg"
with tempfile.TemporaryDirectory(prefix="drive-dmg-") as temporary:
    staging = Path(temporary)
    background = staging / "background.png"
    subprocess.run(["swift", Path(__file__).with_name("dmg_background.swift"), background], check=True)
    instructions = staging / "Установка.txt"
    instructions.write_text("""DRIVE — установка для Mac

Требования: Apple Silicon (M1 и новее), macOS 13+.

1. Перетащите Drive в папку Applications («Программы») справа.
2. Дождитесь окончания копирования и извлеките образ Drive.
3. Откройте Drive из папки «Программы».
Godot и Blender для запуска не требуются.

ЕСЛИ macOS НЕ ОТКРЫВАЕТ DRIVE

Эта сборка имеет локальную ad-hoc подпись, но не нотарифицирована Apple.
Формат DMG сам по себе не отменяет проверку разработчика в macOS.
Для этой известной вам сборки можно разрешить запуск отдельно:

1. Попробуйте открыть Drive в «Программах» и закройте предупреждение.
2. Откройте «Системные настройки» → «Конфиденциальность и безопасность».
3. В разделе «Безопасность» найдите блокировку Drive и нажмите
   «Открыть всё равно», затем подтвердите открытие.

Официальная инструкция Apple: https://support.apple.com/102445

УПРАВЛЕНИЕ
WASD / стрелки — движение; пробел — ручник; Enter — старт;
Esc — пауза и гараж; R — возврат на дорогу; H — сигнал; M — звук.
В гараже: Q — пустыня, E — город, N — ночной город, P — Palm Bay.

Авторы звуков и лицензии: Drive.app → «Показать содержимое пакета» →
Contents/Resources/Audio-CREDITS.md и THIRD_PARTY_NOTICES.txt.
""", encoding="utf-8")
    dmgbuild.build_dmg(str(installer), "Drive", settings={
        "format": "UDZO",
        "compression_level": 9,
        "files": [str(app), str(instructions)],
        "symlinks": {"Applications": "/Applications"},
        "icon": str(app / "Contents" / "Resources" / "icon.icns"),
        "background": str(background),
        "window_rect": ((160, 120), (700, 500)),
        "icon_locations": {"Drive.app": (180, 225), "Applications": (520, 225), "Установка.txt": (350, 405)},
        "icon_size": 96,
        "text_size": 15,
        "show_status_bar": False,
        "show_tab_view": False,
        "show_toolbar": False,
        "show_pathbar": False,
        "arrange_by": None,
        "hide_extensions": ["Drive.app"],
    })
subprocess.run(["hdiutil", "verify", installer], check=True)
digest = hashlib.sha256(installer.read_bytes()).hexdigest()
(output / (installer.name + ".sha256")).write_text(digest + "  " + installer.name + "\n")
manifest = {
    "version": version, "architecture": architectures,
    "minimum_macos": "13.0", "bundle_identifier": info["CFBundleIdentifier"],
    "signing": "ad-hoc", "notarized": False,
    "installer": installer.name, "sha256": digest,
}
(output / "dmg-build-info.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print("MACOS_DMG", installer)
print("SHA256", digest)
