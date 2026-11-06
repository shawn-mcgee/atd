"""Package the already-verified web export with index.html at archive root."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import json

root = Path(__file__).resolve().parents[1]
web = root / "build" / "web"
version = json.loads((root / "package.json").read_text())["version"]
required = ["index.html", "index.js", "index.wasm", "index.pck", "bridge.js", "THIRD-PARTY-NOTICES.txt"]
for name in required:
    if not (web / name).is_file():
        raise SystemExit(f"Missing browser export: {name}")
output = root / "build" / f"atd-{version}-web.zip"
with ZipFile(output, "w", ZIP_DEFLATED) as archive:
    for file in sorted(web.iterdir()):
        if file.is_file() and not file.name.endswith(".import") and (file.name.startswith("index.") or file.name in ["bridge.js", "THIRD-PARTY-NOTICES.txt"]):
            archive.write(file, file.name)
with ZipFile(output) as archive:
    assert set(required) <= set(archive.namelist())
    assert archive.testzip() is None
print(output)
