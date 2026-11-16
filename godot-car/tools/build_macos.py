"""Build, ad-hoc sign and package a native Apple Silicon application on macOS."""
import argparse
import hashlib
import json
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from macos_branding import read_branding

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "godot-car"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--godot", default=shutil.which("godot") or "/Applications/Godot.app/Contents/MacOS/Godot")
parser.add_argument("--output", type=Path, default=ROOT / "build" / "macos-arm64")
parser.add_argument("--dmg", action="store_true", help="Also create a drag-to-Applications DMG (requires tools/requirements-macos.txt).")
args = parser.parse_args()
if platform.system() != "Darwin":raise SystemExit("Run this packaging script on macOS with Command Line Tools installed.")

def run(*command):
    subprocess.run([str(value) for value in command], check=True)

def prepare_arm64_templates():
    engine_version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    template_version = ".".join(engine_version.split(".")[:4])
    archive = Path.home() / "Library" / "Application Support" / "Godot" / "export_templates" / template_version / "macos.zip"
    if not archive.exists():raise SystemExit("Install the matching Godot export templates first: " + str(archive))
    additions = []
    # Official macOS templates contain Universal binaries. The exporter expects
    # explicitly named arm64 slices for an arm64-only preset.
    with zipfile.ZipFile(archive) as source, tempfile.TemporaryDirectory(prefix="drive-arm64-template-") as temporary:
        for flavor in ["debug", "release"]:
            universal = "macos_template.app/Contents/MacOS/godot_macos_" + flavor + ".universal"
            native = universal.replace(".universal", ".arm64")
            if native in source.namelist():continue
            original = Path(temporary) / (flavor + ".universal")
            result = Path(temporary) / (flavor + ".arm64")
            original.write_bytes(source.read(universal))
            run("lipo", original, "-thin", "arm64", "-output", result)
            entry = zipfile.ZipInfo(native)
            entry.external_attr = 0o100755 << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            additions.append((entry, result.read_bytes()))
    if additions:
        backup = archive.with_name("macos-universal-original.zip")
        if not backup.exists():shutil.copy2(archive, backup)
        with zipfile.ZipFile(archive, "a", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as destination:
            for entry, content in additions:destination.writestr(entry, content)
        print("Prepared native arm64 export template slices")

branding = read_branding(PROJECT / "project.godot")
version = branding["version"]
app_name = branding["file_name"]
display_name = branding["display_name"]
output = args.output.resolve()
payload = output / app_name
payload.mkdir(parents=True, exist_ok=True)
app = payload / (app_name + ".app")
prepare_arm64_templates()
run(args.godot, "--headless", "--path", PROJECT, "--editor", "--import", "--quit")
run(args.godot, "--headless", "--path", PROJECT, "--export-release", "macOS Apple Silicon", app)

plist_path = app / "Contents" / "Info.plist"
with plist_path.open("rb") as file:info = plistlib.load(file)
old_executable = app / "Contents" / "MacOS" / info["CFBundleExecutable"]
native_executable = old_executable.with_name(app_name)
if old_executable != native_executable:old_executable.rename(native_executable)
old_pack = app / "Contents" / "Resources" / (info["CFBundleExecutable"] + ".pck")
if old_pack.exists():old_pack.rename(old_pack.with_name(app_name + ".pck"))
info["CFBundleExecutable"] = app_name
info["CFBundleName"] = display_name
info["CFBundleDisplayName"] = display_name
with plist_path.open("wb") as file:plistlib.dump(info, file, sort_keys=False)
executable = app / "Contents" / "MacOS" / info["CFBundleExecutable"]
architectures = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip()
if architectures != "arm64":raise RuntimeError("Expected arm64-only runtime, got: " + architectures)

notices = app / "Contents" / "Resources" / "THIRD_PARTY_NOTICES.txt"
run(args.godot, "--headless", "--path", PROJECT, "--script", "res://tools/export_runtime_notices.gd", "--", notices)
credits = PROJECT / "audio" / "CREDITS.md"
shutil.copy2(credits, app / "Contents" / "Resources" / "Audio-CREDITS.md")
shutil.copy2(credits, payload / "Audio-CREDITS.md")
shutil.copy2(notices, payload / "THIRD_PARTY_NOTICES.txt")
(payload / "README.txt").write_text(f"""{display_name.upper()} — macOS / Apple Silicon

Требования: Mac с процессором Apple Silicon, macOS 13 или новее.
Распакуйте архив, перенесите {app_name}.app в «Программы» и откройте приложение.
Godot и Blender для запуска не требуются.

Управление:
WASD / стрелки — газ, тормоз, поворот; пробел — ручник; R — возврат на дорогу.
Enter — старт; Esc — пауза и выход в гараж; H — сигнал; M — звук.
В гараже: Q — пустыня, E — город, N — ночной город, P — Palm Bay.

В сборке все четыре карты и обе машины. Рекорды и громкость сохраняются
в пользовательском профиле игры; приложение не записывает данные внутрь .app.

Сборка имеет локальную ad-hoc подпись и не нотарифицирована Apple.
При блокировке скачанной копии используйте «Открыть всё равно» для {display_name}
в системных настройках конфиденциальности и безопасности macOS.
Для публичного выпуска с нотарификацией нужны Developer ID и учётная запись Apple Developer.

Лицензии движка и сторонних компонентов: THIRD_PARTY_NOTICES.txt.
Авторы и лицензии звуков: Audio-CREDITS.md.
""", encoding="utf-8")
# Resource notices and bundle display name are part of the final signed bundle.
run("codesign", "--force", "--sign", "-", "--options", "runtime", app)
run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
with tempfile.TemporaryDirectory(prefix="drive-export-check-") as empty_directory:
    report = output / "verification-headless.json"
    subprocess.run([str(executable), "--headless", "--log-file", str(output / "verification-headless.log"), "--", "--verify-export", "--verify-report=" + str(report)], cwd=empty_directory, check=True, timeout=120)
    if not report.exists() or not json.loads(report.read_text())["ok"]:raise RuntimeError("Packaged application verification failed")
archive = output / (app_name + "-macOS-arm64-" + version + ".zip")
run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", payload, archive)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(output / (archive.name + ".sha256")).write_text(digest + "  " + archive.name + "\n")
manifest = {"version": version, "architecture": architectures, "minimum_macos": "13.0", "bundle_identifier": info["CFBundleIdentifier"], "signing": "ad-hoc", "notarized": False, "archive": archive.name, "sha256": digest}
(output / "build-info.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print("MACOS_APP", app)
print("MACOS_ARCHIVE", archive)
print("SHA256", digest)
if args.dmg:
    run(sys.executable, Path(__file__).with_name("package_macos_dmg.py"), "--output", output)
