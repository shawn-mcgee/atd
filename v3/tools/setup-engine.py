"""Install the pinned portable editor and only the required web templates locally."""
import io
import json
import sys
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = (ROOT / ".godot-version").read_text().strip()
DEST = ROOT / ".tools" / "godot"
BASE = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/"


class RemoteArchive(io.RawIOBase):
    def __init__(self, url, size):
        self.url, self.size, self.position = url, size, 0

    def seek(self, offset, whence=0):
        self.position = offset if whence == 0 else self.position + offset if whence == 1 else self.size + offset
        return self.position

    def tell(self):
        return self.position

    def seekable(self):
        return True

    def read(self, size=-1):
        size = self.size - self.position if size < 0 else min(size, self.size - self.position)
        if size <= 0:
            return b""
        # A unique query avoids intermediary caches reusing a different byte range.
        url = f"{self.url}?atd_range={self.position}-{self.position + size - 1}"
        request = urllib.request.Request(url, headers={"Range": f"bytes={self.position}-{self.position + size - 1}", "User-Agent": "atd-dev-setup"})
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 206:
                raise RuntimeError("Template server did not support partial downloads; refusing a full 1.3 GB download")
            data = response.read()
        if len(data) != size:
            raise RuntimeError(f"Incomplete template range: {len(data)} != {size}")
        self.position += size
        return data


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    windows = sys.platform == "win32"
    binary_suffix = "win64_console.exe" if windows else "linux.x86_64"
    archive_suffix = "win64.exe.zip" if windows else "linux.x86_64.zip"
    exe = DEST / f"Godot_v{VERSION}-stable_{binary_suffix}"
    if not exe.exists():
        archive = DEST / "editor.zip"
        print("Downloading portable Godot editor...", flush=True)
        urllib.request.urlretrieve(BASE + f"Godot_v{VERSION}-stable_{archive_suffix}", archive)
        with zipfile.ZipFile(archive) as source:
            source.extractall(DEST)
        archive.unlink()
        if not windows:
            exe.chmod(0o755)
    templates = DEST / "templates"
    templates.mkdir(exist_ok=True)
    needed = ["web_nothreads_release.zip", "web_nothreads_debug.zip"]
    if not all((templates / name).exists() for name in needed):
        api = f"https://api.github.com/repos/godotengine/godot-builds/releases/tags/{VERSION}-stable"
        with urllib.request.urlopen(api) as response:
            release = json.load(response)
        asset = next(x for x in release["assets"] if x["name"] == f"Godot_v{VERSION}-stable_export_templates.tpz")
        with zipfile.ZipFile(RemoteArchive(asset["browser_download_url"], asset["size"])) as source:
            for name in needed:
                print(f"Downloading {name} from export archive...", flush=True)
                entry = next(n for n in source.namelist() if n.endswith("/" + name))
                (templates / name).write_bytes(source.read(entry))
    print(f"Godot ready: {exe}", flush=True)


if __name__ == "__main__":
    main()
