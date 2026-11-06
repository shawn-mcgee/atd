"""Export the preserved v1 game separately; never overwrite the current export.

Uses the same pinned editor and cached web templates as v3. Installing those
templates in Godot's normal user directory lets the original v1 preset remain
unchanged. Run from v3 after tools/setup-engine.py.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / ".godot-version").read_text().strip()


def main():
    suffix = "win64_console.exe" if sys.platform == "win32" else "linux.x86_64"
    editor = os.environ.get("GODOT_BIN", str(ROOT / ".tools" / "godot" / f"Godot_v{VERSION}-stable_{suffix}"))
    if sys.platform == "win32":
        user_data = Path(os.environ["APPDATA"]) / "Godot"
    elif sys.platform == "darwin":
        user_data = Path.home() / "Library/Application Support/Godot"
    else:
        user_data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local/share"))) / "godot"
    templates = user_data / "export_templates" / f"{VERSION}.stable"
    templates.mkdir(parents=True, exist_ok=True)
    for name in ("web_nothreads_release.zip", "web_nothreads_debug.zip"):
        shutil.copy2(ROOT / ".tools/godot/templates" / name, templates / name)
    (templates / "version.txt").write_text(f"{VERSION}.stable\n")
    legacy = ROOT.parent / "v1"
    output = ROOT / "build/legacy-web"
    output.mkdir(parents=True, exist_ok=True)
    for options in (("--editor", "--import", "--quit"), ("--export-release", "Web", str(output / "index.html"))):
        result = subprocess.run([editor, "--headless", "--path", str(legacy), *options],
                                capture_output=True, text=True, encoding="utf-8", errors="replace")
        log = result.stdout + result.stderr
        phase = "import" if "--import" in options else "export"
        (output / f"{phase}.log").write_text(log, encoding="utf-8")
        if result.returncode or re.search(r"SCRIPT ERROR:|^ERROR:", log, re.MULTILINE):
            print(log[-6000:])
            raise SystemExit(f"Legacy {phase} failed; see {output / (phase + '.log')}")
    print(f"Legacy v1 export ready: {output}")


if __name__ == "__main__":
    main()
