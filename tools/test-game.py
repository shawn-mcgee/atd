"""Run Godot integration tests from the repository root; retain diagnostic logs."""
import argparse
import concurrent.futures
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", action="append", help="Test suffix, e.g. mission-upgrade; repeat to select multiple tests")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    engines = sorted(root.glob("Godot*.exe"))
    godot = args.godot or (engines[0] if engines else None)
    if godot is None:
        parser.error("Provide --godot or place the Godot executable at the repository root")
    tests = sorted((root / "project/tools").glob("test-*.gd"))
    if args.name:
        wanted = {"test-" + name.removeprefix("test-").removesuffix(".gd") for name in args.name}
        missing = wanted - {test.stem for test in tests}
        if missing:
            parser.error("Unknown headless tests: " + ", ".join(sorted(missing)))
        tests = [test for test in tests if test.stem in wanted]
    logs = root / "project/art_source/.build/test-results"
    logs.mkdir(parents=True, exist_ok=True)
    imported = subprocess.run(
        [str(godot.resolve()), "--headless", "--editor", "--path", str(root / "project"), "--import", "--quit"],
        cwd=root, capture_output=True, text=True, timeout=args.timeout,
    )
    import_output = imported.stdout + imported.stderr
    (logs / "import.log").write_text(import_output, encoding="utf-8")
    if imported.returncode or any("SCRIPT ERROR:" in line or line.startswith("ERROR:") for line in import_output.splitlines()):
        print(f"Project import failed. See {logs / 'import.log'}", flush=True)
        return 1

    def run(test):
        command = [str(godot.resolve()), "--headless", "--path", str(root / "project"), "--script", "res://tools/" + test.name]
        try:
            result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=args.timeout)
            output = result.stdout + result.stderr
            errors = [line.strip() for line in output.splitlines() if "SCRIPT ERROR:" in line or line.startswith("ERROR:")]
            passed = result.returncode == 0 and not errors
        except subprocess.TimeoutExpired as error:
            output = (error.stdout or b"").decode(errors="replace") if isinstance(error.stdout, bytes) else error.stdout or ""
            output += "\nTest exceeded its timeout."
            passed = False
            errors = ["timeout"]
        (logs / (test.stem + ".log")).write_text(output, encoding="utf-8")
        return test.stem, passed, errors

    failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        for future in concurrent.futures.as_completed([pool.submit(run, test) for test in tests]):
            name, passed, errors = future.result()
            failed += not passed
            print(("PASS " if passed else "FAIL ") + name, flush=True)
            for error in errors[:5]:
                print("  " + error, flush=True)
    print(f"{len(tests) - failed}/{len(tests)} passed. Logs: {logs}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
