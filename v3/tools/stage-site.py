"""Stage the current export at / and /v3/, optionally adding a legacy /v1/.

Run after export:web. The legacy input must be a separately exported v1 build;
the active game is never replaced by that input. Paths inside Godot's HTML stay
relative, so each copy loads its own JavaScript, WASM, pack, and bridge.
"""
import argparse
from pathlib import Path
import shutil
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ("index.html", "index.js", "index.wasm", "index.pck")


def copy_export(source, destination, active=False):
    required = REQUIRED + (("bridge.js", "THIRD-PARTY-NOTICES.txt") if active else ())
    for name in required:
        if not (source / name).is_file():
            raise SystemExit(f"Missing export file: {source / name}")
    destination.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        if file.is_file() and not file.name.endswith(".import"):
            shutil.copy2(file, destination / file.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--v1-web", type=Path, help="Optional already-exported legacy v1 directory")
    args = parser.parse_args()
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    site = build / "site"
    with TemporaryDirectory(prefix="site-", dir=build) as temporary:
        staged = Path(temporary) / "site"
        copy_export(build / "web", staged, active=True)
        copy_export(build / "web", staged / "v3", active=True)
        if args.v1_web:
            copy_export(args.v1_web.resolve(), staged / "v1")
        (staged / ".nojekyll").touch()
        # Only replace this helper's generated output, never a project directory.
        if site.is_symlink() or site.resolve().parent != build.resolve():
            raise SystemExit(f"Unsafe staging destination: {site}")
        if site.exists():
            shutil.rmtree(site)
        shutil.move(str(staged), site)
    print(f"Pages ready: {site} (root and /v3/ serve the current game)")


if __name__ == "__main__":
    main()
