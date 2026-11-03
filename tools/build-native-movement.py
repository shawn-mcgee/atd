"""Build the optional v2 integer movement accelerator; all output stays ignored."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "v2/native"
BUILD = SOURCE / ".build"
BIN = SOURCE / "bin"
SDK_VERSION = "4.0.20"
ZIG_VERSION = "0.14.1"


def run(command, **kwargs):
    subprocess.run([str(part) for part in command], cwd=ROOT, check=True, **kwargs)


def web_compiler(sdk):
    manager = sdk / "emsdk.py"
    if not manager.exists():
        run(["git", "clone", "--depth", "1", "--branch", SDK_VERSION, "https://github.com/emscripten-core/emsdk.git", sdk])
    env = os.environ.copy()
    env.update(EMSDK=str(sdk), EM_CONFIG=str(sdk / ".emscripten"), EMSDK_PYTHON=sys.executable)
    compiler = [sys.executable, sdk / "upstream/emscripten/em++.py"]
    version = subprocess.run([str(item) for item in [*compiler, "--version"]], cwd=ROOT, env=env,
                             capture_output=True, text=True) if compiler[1].exists() else None
    if not version or version.returncode or not re.search(r"\b" + re.escape(SDK_VERSION) + r"\b", version.stdout):
        run([sys.executable, manager, "install", SDK_VERSION])
        run([sys.executable, manager, "activate", SDK_VERSION], stdout=subprocess.DEVNULL)
    return compiler, env


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=ROOT / "Godot_v4.7.2-stable_win64.exe")
    parser.add_argument("--web", action="store_true", help="Also build the single-threaded Web extension")
    parser.add_argument("--zig", type=Path)
    parser.add_argument("--emsdk", type=Path, default=Path(tempfile.gettempdir()) / "atd-emsdk")
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    BIN.mkdir(exist_ok=True)
    staging = BUILD / "staging"
    staging.mkdir(exist_ok=True)
    api = BUILD / "api"
    api.mkdir(exist_ok=True)
    run([args.godot.resolve(), "--headless", "--path", api, "--dump-gdextension-interface", "--dump-extension-api", "--quit"],
        stdout=subprocess.DEVNULL)
    header = api / "gdextension_interface.h"
    definitions = json.loads((api / "extension_api.json").read_text(encoding="utf-8"))
    object_class = next(item for item in definitions["classes"] if item["name"] == "Object")
    notification = next(item for item in object_class["methods"] if item["name"] == "notification")
    byte_array = next(item for item in definitions["builtin_classes"] if item["name"] == "PackedByteArray")
    resize = next(item for item in byte_array["methods"] if item["name"] == "resize")
    int_array = next(item for item in definitions["builtin_classes"] if item["name"] == "PackedInt64Array")
    int_resize = next(item for item in int_array["methods"] if item["name"] == "resize")
    array = next(item for item in definitions["builtin_classes"] if item["name"] == "Array")
    array_resize = next(item for item in array["methods"] if item["name"] == "resize")
    dictionary = next(item for item in definitions["builtin_classes"] if item["name"] == "Dictionary")
    has_all = next(item for item in dictionary["methods"] if item["name"] == "has_all")
    used = {"Variant", "String", "StringName", "PackedInt64Array", "PackedByteArray", "Array", "Dictionary"}
    for config in definitions["builtin_class_sizes"]:
        if any(item["size"] > 64 for item in config["sizes"] if item["name"] in used):
            raise RuntimeError("Godot builtin storage exceeds the movement adapter ABI")
    generated = api / "native_api.hpp"
    hashes = {"ATD_NOTIFICATION_HASH": notification["hash"], "ATD_BYTE_RESIZE_HASH": resize["hash"],
              "ATD_INT_RESIZE_HASH": int_resize["hash"], "ATD_ARRAY_RESIZE_HASH": array_resize["hash"],
              "ATD_HAS_ALL_HASH": has_all["hash"]}
    generated.write_text("".join(f"#define {name} {value}ULL\n" for name, value in hashes.items()))
    digest = hashlib.sha256()
    digest.update(Path(__file__).read_bytes())
    for path in [*sorted(SOURCE.glob("*.hpp")), SOURCE / "extension.cpp", header, generated]:
        digest.update(path.read_bytes())
    tag = digest.hexdigest()[:16]
    common = ["-std=c++17", "-O3", "-fno-exceptions", "-fno-rtti", "-I", api, SOURCE / "extension.cpp"]
    arch = "arm64" if platform.machine().lower() in ("arm64", "aarch64") else "x86_64"
    if sys.platform == "win32":
        zig = args.zig or Path(tempfile.gettempdir()) / "atd-native-tools/ziglang/zig.exe"
        if not zig.exists():
            run([sys.executable, "-m", "pip", "install", "--target", zig.parent.parent, "--no-compile", f"ziglang=={ZIG_VERSION}"])
        compiler = [zig, "c++", "-target", "x86_64-windows-gnu", "-shared", "-s"]
        key, suffix = "windows.x86_64", "dll"
    else:
        cxx = shutil.which("c++") or shutil.which("clang++")
        if not cxx:
            raise RuntimeError("Install a C++17 compiler to build movement acceleration")
        compiler = [cxx, "-shared", "-fPIC"]
        key, suffix = (f"macos.{arch}", "dylib") if sys.platform == "darwin" else (f"linux.{arch}", "so")
    host = BIN / f"movement.{tag}.{key}.{suffix}"
    if not host.exists():
        pending = staging / host.name
        run([*compiler, *common, "-o", pending])
        pending.replace(host)
    web = BIN / f"movement.{tag}.web.wasm"
    if args.web and not web.exists():
        compiler, env = web_compiler(args.emsdk.resolve())
        pending = staging / web.name
        run([*compiler, *common, "-sSIDE_MODULE=2", "-sWASM_BIGINT=1", "-Wl,--export=atd_movement_init", "-o", pending], env=env)
        pending.replace(web)
    lines = ["[configuration]", 'entry_symbol = "atd_movement_init"', 'compatibility_minimum = "4.7.2"',
             "reloadable = false", "", "[libraries]", f'{key} = "res://native/bin/{host.name}"']
    if web.exists():
        lines.append(f'web = "res://native/bin/{web.name}"')
    # Content-addressed libraries avoid overwriting a DLL held by an open editor.
    descriptor = staging / "runtime.gdextension"
    descriptor.write_text("\n".join(lines) + "\n", encoding="utf-8")
    descriptor.replace(SOURCE / "runtime.gdextension")
    print(f"ATD_NATIVE_BUILT {tag} ({key}" + (", web)" if web.exists() else ")"))


if __name__ == "__main__":
    main()
