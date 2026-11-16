"""Read the display name and safe native filenames from the Godot project."""
import re
from pathlib import Path


def read_branding(project: Path) -> dict[str, str]:
    config = project.read_text(encoding="utf-8")
    name = re.search(r'^config/name="([^"]+)"', config, re.MULTILINE).group(1)
    version = re.search(r'^config/version="([^"]+)"', config, re.MULTILINE).group(1)
    # ASCII executable/PCK names avoid Unicode normalization changing a signed
    # bundle when Finder copies it from a ZIP or an HFS+ disk image.
    filename = re.sub(r"[^A-Za-z0-9_-]", "", name) or "Drive"
    return {"display_name": name, "file_name": filename, "version": version}
