"""Run tool installation smoke checks; no Grand law/model qualification."""
import json
import hashlib
import zipfile
import subprocess
import sys
from provision import LOCAL, PINS, run, prerequisites, download, digest, local_env


def inspect():
    prerequisites()
    executables = {name: LOCAL / "elan/bin" / name for name in ("elan", "lean", "lake")}
    executables.update({name: LOCAL / PINS["node"]["directory"] / "bin" / name for name in ("node", "npm")})
    versions = {name: run([path, "--version"], capture=True) for name, path in executables.items()}
    if "Lean (version 4.35.0," not in versions["lean"] or "Lean version 4.35.0" not in versions["lake"]:
        raise RuntimeError("Lean/Lake version mismatch")
    if versions["node"] != PINS["node"]["version"]:
        raise RuntimeError("Node version mismatch")
    lynx = LOCAL / "src/lynx"
    lynx_output = run(["mix", "run", "--no-compile", "-e", 'unless Code.ensure_loaded?(Lynx.Laws), do: System.halt(2); IO.puts("Lynx.Laws loaded")'], lynx, capture=True)
    versions["lynx"] = PINS["lynx"]["revision"] + " (Lynx.Laws loaded; runner built)"
    smoke = LOCAL / "smoke"
    smoke.mkdir(exist_ok=True)
    source = smoke / "VeilImport.lean"
    source.write_text("import Veil\nexample : True := by trivial\n")
    run(["lake", "env", "lean", source], LOCAL / "src/veil")
    versions["veil"] = PINS["veil"]["revision"] + " (Veil import/elaboration passed)"
    archive = download(PINS["cvc5"])
    with zipfile.ZipFile(archive) as zipped:
        for member in zipped.namelist():
            if "/lib/" in member and member.endswith(".a"):
                installed = LOCAL / "src/veil/.lake/packages/cvc5" / member
                with zipped.open(member) as handle:
                    expected = hashlib.file_digest(handle, "sha256").hexdigest()
                if not installed.is_file() or digest(installed) != expected:
                    raise RuntimeError(f"Veil cvc5 native library does not match pinned release: {member}")
    versions["cvc5"] = "1.3.2 (native libraries match pinned archive)"
    if digest(LOCAL / "tlc/tla2tools.jar") != PINS["tlc"]["sha256"]:
        raise RuntimeError("Installed TLC JAR differs from pinned artifact")
    # This TLC release exits 1 for a successful help request.
    help_result = subprocess.run(["java", "-cp", str(LOCAL / "tlc/tla2tools.jar"), "tlc2.TLC", "-help"],
                                 env=local_env(), capture_output=True, text=True)
    output = help_result.stdout + help_result.stderr
    if help_result.returncode not in (0, 1) or "Version 2.19" not in output:
        raise RuntimeError("TLC version mismatch")
    versions["tlc"] = "2.19 (official release v1.7.4; help smoke passed)"
    notes = ["Upstream Lynx emits a nonfatal Lean linter warning; no warning was suppressed."] if "warning:" in lynx_output else []
    return {"status": "PASS", "scope": "tool installation/build/import smoke only", "tools": versions, "notes": notes}


if __name__ == "__main__":
    try:
        print(json.dumps(inspect(), indent=2))
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Doctor failed: {error}. Run scripts/bootstrap.sh.", file=sys.stderr)
        sys.exit(1)
