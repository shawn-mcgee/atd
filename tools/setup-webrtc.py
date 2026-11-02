"""Install a pinned official extension into ignored v2/addons/webrtc_native/."""
import argparse
import hashlib
from io import BytesIO
from pathlib import Path
import urllib.request
import subprocess
import tempfile
import sys
import zipfile

URL = "https://github.com/godotengine/webrtc-native/releases/download/1.2.2-stable/godot-extension-webrtc_native.zip"
SHA256 = "98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, help="Use an already downloaded archive (checksum still verified)")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent / "v2"
    if args.archive:
        payload = args.archive.read_bytes()
    elif sys.platform == "win32":
        # Windows curl uses the system certificate store, including enterprise CAs.
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "webrtc.zip"
            subprocess.run(["curl.exe", "--fail", "--location", "--silent", "--show-error", "--output", str(archive_path), URL], check=True)
            payload = archive_path.read_bytes()
    else:
        payload = urllib.request.urlopen(URL, timeout=120).read()
    if hashlib.sha256(payload).hexdigest() != SHA256:
        raise SystemExit("WebRTC extension checksum mismatch")
    with zipfile.ZipFile(BytesIO(payload)) as archive:
        for entry in archive.infolist():
            target = (root / entry.filename).resolve()
            if not target.is_relative_to(root.resolve()):
                raise SystemExit("Unsafe archive member")
            if entry.filename not in ("addons/", "addons/webrtc_native/") and not entry.filename.startswith("addons/webrtc_native/"):
                raise SystemExit("Unexpected archive member")
        archive.extractall(root)
    print("Installed official webrtc-native 1.2.2. Restart Godot after installation.")


if __name__ == "__main__":
    main()
