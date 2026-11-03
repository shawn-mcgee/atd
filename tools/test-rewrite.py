"""Import and validate the v2 rewrite. Use --network for the live coordinator smoke test."""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--network", action="store_true")
    parser.add_argument("--require-native", action="store_true", help="Fail unless the compiled movement kernel is loaded")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    logs = root / "v2/test-results"
    logs.mkdir(exist_ok=True)
    # Import does not need native extensions. Recovery mode avoids the editor's
    # shared ~DLL copy colliding with an already open Windows Godot editor.
    commands = [("import", ["--editor", "--recovery-mode", "--import", "--quit"]),
                ("foundation", ["--script", "res://tests/test_foundation.gd"]),
                ("view", ["--script", "res://tests/test_view.gd"]),
                ("protocol", ["--script", "res://tests/test_protocol.gd"])]
    if args.network:
        commands.append(("network", ["--script", "res://tests/test_network.gd"]))
    for name, options in commands:
        if name == "foundation" and args.require_native:
            options = [*options, "--", "--require-native"]
        log = logs / (name + ".log")
        try:
            with log.open("w", encoding="utf-8") as sink:
                result = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(root / "v2"), *options],
                                        cwd=root, stdout=sink, stderr=subprocess.STDOUT, text=True, timeout=120)
        except subprocess.TimeoutExpired:
            print(f"FAIL {name} (timeout): partial output saved to {log}")
            return 1
        output = log.read_text(encoding="utf-8", errors="replace")
        errors = [line for line in output.splitlines() if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
        if result.returncode or errors:
            print(f"FAIL {name} (exit {result.returncode}): see {logs / (name + '.log')}")
            print("\n".join(errors[:8]))
            return 1
        print(f"PASS {name}")
        for line in output.splitlines():
            if line.startswith("ATD_"): print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
