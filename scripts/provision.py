"""Pinned Grand-local tools. Adapted from Hold Ledger; invoke through uv only."""
from __future__ import annotations

import hashlib
import argparse
import fcntl
import json
import os
import platform
import re
import shutil
import shlex
import subprocess
import sys
import tarfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"
PINS = json.loads((ROOT / "scripts/toolchains.json").read_text())


def local_env() -> dict[str, str]:
    env = os.environ.copy()
    env.update(ELAN_HOME=str(LOCAL / "elan"), ELAN_TOOLCHAIN=PINS["lean_toolchain"],
               XDG_CACHE_HOME=str(LOCAL / "cache"), npm_config_cache=str(LOCAL / "npm-cache"),
               GRAND_TLC_JAR=str(LOCAL / "tlc/tla2tools.jar"),
               GRAND_LYNX_ROOT=str(LOCAL / "src/lynx"), GRAND_VEIL_ROOT=str(LOCAL / "src/veil"),
               LEAN_NUM_THREADS=env.get("LEAN_NUM_THREADS", "4"))
    env["PATH"] = os.pathsep.join([str(LOCAL / "bin"), str(LOCAL / "elan/bin"),
                                  str(LOCAL / PINS["node"]["directory"] / "bin"), env.get("PATH", "")])
    return env


def run(argv, cwd=ROOT, *, capture=False):
    print("+ " + " ".join(map(str, argv)), flush=True)
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=local_env(),
                            check=True, text=True, capture_output=capture)
    return result.stdout.strip() if capture else ""


def digest(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def download(pin):
    name = pin.get("archive", pin["url"].rsplit("/", 1)[-1])
    dest = LOCAL / "downloads" / name
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        if digest(dest) != pin["sha256"]:
            raise RuntimeError(f"Corrupt cached download: {dest}. Remove that file and retry bootstrap.")
        print(f"Reuse checked download: {name}", flush=True)
        return dest
    part = dest.with_suffix(dest.suffix + ".partial")
    for attempt in range(3):
        try:
            print(f"Download {pin['url']}", flush=True)
            with urllib.request.urlopen(pin["url"], timeout=60) as src, part.open("wb") as out:
                shutil.copyfileobj(src, out, 1024 * 1024)
            if digest(part) != pin["sha256"]:
                raise RuntimeError(f"Download checksum mismatch: {part}; refusing extraction")
            part.replace(dest)
            return dest
        except (OSError, TimeoutError):
            if attempt == 2:
                raise
            time.sleep(attempt + 1)
    raise RuntimeError("Download failed")


def extract(pin, destination, *, strip_root=False):
    marker = destination / ".grand-tool.json"
    expected = {k: pin[k] for k in ("url", "sha256")}
    if marker.exists():
        if json.loads(marker.read_text()) != expected:
            raise RuntimeError(f"Tool pin changed at {destination}; remove only this generated directory and rerun.")
        print(f"Reuse installed source/tool: {destination.name}", flush=True)
        return
    archive = download(pin)
    temporary = destination.with_name(destination.name + ".partial")
    # Only an interrupted extraction directory is replaced; published installations survive failure.
    if temporary.exists():
        shutil.rmtree(temporary)
    temporary.mkdir(parents=True)
    try:
        if archive.name.endswith(".zst"):
            import zstandard
            with archive.open("rb") as src, zstandard.ZstdDecompressor().stream_reader(src) as stream:
                with tarfile.open(fileobj=stream, mode="r|") as tar:
                    tar.extractall(temporary, filter="data")
        else:
            with tarfile.open(archive) as tar:
                tar.extractall(temporary, filter="data")
        content = list(temporary.iterdir())
        actual = content[0] if strip_root and len(content) == 1 and content[0].is_dir() else temporary
        if destination.exists():
            raise RuntimeError(f"Unrecognized installation at {destination}; inspect it before removing it.")
        actual.rename(destination)
        marker.write_text(json.dumps(expected) + "\n")
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def prerequisites():
    release = platform.freedesktop_os_release()
    if release.get("ID") != "ubuntu" or release.get("VERSION_ID") != "26.04" or platform.machine() != "x86_64":
        raise RuntimeError("Supported starting environment: Ubuntu 26.04 x86_64.")
    needed = {
        "uv": "Install uv and rerun scripts/bootstrap.sh.",
        "java": "Install a compatible JDK (Java 21–25; qualified here: OpenJDK 25) and expose java on PATH.",
        "elixir": "Expose Elixir 1.20.5 compiled with OTP 29 on PATH.",
        "mix": "Expose Mix from that Elixir installation on PATH.",
        "git": "Expose Git for Lake's pinned upstream dependencies; Grand itself needs no Git checkout.",
        "clang": "Expose Clang for Veil native builds.",
        "clang++": "Expose Clang C++ for the local libc++ build.",
        "cmake": "Expose CMake for the local libc++ build.",
        "ninja": "Expose Ninja for the local libc++ build.",
        "unzip": "Expose unzip for Veil's pinned cvc5 binary archive.",
        "curl": "Expose curl for Lake's upstream downloads.",
        "make": "Expose make for native dependency builds.",
    }
    for name, hint in needed.items():
        if shutil.which(name) is None:
            raise RuntimeError(f"Missing prerequisite {name}. {hint} Bootstrap never uses apt/sudo.")
    version = run(["elixir", "--version"], capture=True)
    if not re.search(r"Elixir 1\.20\.5 \(compiled with Erlang/OTP 29\)", version):
        raise RuntimeError("Select existing Elixir 1.20.5 built with OTP 29; bootstrap does not replace BEAM.")
    otp = run(["elixir", "-e", 'IO.write(File.read!(Path.join([to_string(:code.root_dir()), "releases", "29", "OTP_VERSION"])))'], capture=True)
    if otp != "29.1.2":
        raise RuntimeError(f"Expected OTP 29.1.2; observed {otp}.")
    java = subprocess.run(["java", "--version"], capture_output=True, text=True)
    match = re.search(r"(?:openjdk|java) (\d+)", java.stdout + java.stderr)
    if java.returncode or not match or not 21 <= int(match[1]) <= 25:
        raise RuntimeError("Expose Java 21–25 on PATH (qualified here: OpenJDK 25); bootstrap never installs system packages.")
    LOCAL.mkdir(exist_ok=True)
    if (ROOT / "lean-toolchain").read_text().strip() != PINS["lean_toolchain"]:
        raise RuntimeError("lean-toolchain disagrees with scripts/toolchains.json")


def provision_native():
    source = LOCAL / "src/llvm-runtime-source"
    prefix = LOCAL / "native"
    extract(PINS["libcxx"], source, strip_root=True)
    if not (prefix / ".grand-native-complete").exists():
        build = LOCAL / "build/libcxx"
        run(["cmake", "-G", "Ninja", "-S", source / "runtimes", "-B", build,
             "-DLLVM_ENABLE_RUNTIMES=libunwind;libcxx;libcxxabi", "-DCMAKE_BUILD_TYPE=Release",
             "-DCMAKE_INSTALL_PREFIX=" + str(prefix),
             "-DCMAKE_C_COMPILER=/usr/bin/clang", "-DCMAKE_CXX_COMPILER=/usr/bin/clang++",
             "-DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF", "-DLIBCXX_INCLUDE_TESTS=OFF",
             "-DLIBCXXABI_INCLUDE_TESTS=OFF", "-DLIBCXX_INCLUDE_BENCHMARKS=OFF", "-DLIBUNWIND_INCLUDE_TESTS=OFF"])
        run(["cmake", "--build", build, "--parallel", "4"])
        run(["cmake", "--install", build])
    # Generated wrappers give only these child processes the local C++ headers/libraries.
    wrappers = LOCAL / "bin"
    wrappers.mkdir(exist_ok=True)
    for tool in ("clang", "clang++"):
        host = Path("/usr/bin") / tool
        flags = [str(host), "-isystem", str(prefix / "include/c++/v1"),
                 "-L" + str(prefix / "lib"), "-Wl,-rpath," + str(prefix / "lib"),
                 "-Wno-unused-command-line-argument"]
        wrapper = wrappers / tool
        wrapper.write_text("#!/bin/sh\nexec " + shlex.join(flags) + ' "$@"\n')
        wrapper.chmod(0o755)
    probe = LOCAL / "native-probe"
    try:
        subprocess.run([str(wrappers / "clang++"), "-std=c++17", "-stdlib=libc++", "-x", "c++", "-", "-o", str(probe)],
                       input="#include <vector>\nint main(){std::vector<int> v; return v.size();}\n", text=True, check=True)
        run([probe])
        (prefix / ".grand-native-complete").write_text(PINS["libcxx"]["sha256"] + "\n")
    finally:
        probe.unlink(missing_ok=True)


def provision():
    prerequisites()
    elan = LOCAL / "elan/bin/elan"
    if not elan.exists():
        installer = LOCAL / "elan-installer"
        extract(PINS["elan"], installer)
        run([installer / "elan-init", "-y", "--no-modify-path", "--default-toolchain", "none"])
    if not run([elan, "--version"], capture=True).startswith("elan " + PINS["elan"]["version"] + " "):
        raise RuntimeError("Installed local Elan version differs from its pin.")
    lean = LOCAL / PINS["lean"]["directory"]
    extract(PINS["lean"], lean, strip_root=True)
    installed = run([elan, "toolchain", "list"], capture=True)
    if PINS["lean_toolchain"] not in [line.split()[0] for line in installed.splitlines() if line.split()]:
        run([elan, "toolchain", "link", PINS["lean_toolchain"], lean])
    selected = Path(run([elan, "which", "lean"], capture=True)).resolve()
    if selected != (lean / "bin/lean").resolve():
        raise RuntimeError("Local Elan toolchain points outside Grand's local Lean installation.")
    extract(PINS["node"], LOCAL / PINS["node"]["directory"], strip_root=True)
    jar = download(PINS["tlc"])
    target = LOCAL / "tlc/tla2tools.jar"
    target.parent.mkdir(exist_ok=True)
    if not target.exists():
        shutil.copyfile(jar, target)
    elif digest(target) != PINS["tlc"]["sha256"]:
        raise RuntimeError("Installed TLC JAR differs from its pin. Remove .local/tlc and rerun.")
    for name in ("lynx", "veil"):
        extract(PINS[name], LOCAL / "src" / name, strip_root=True)
    provision_native()
    run(["mix", "compile", "--warnings-as-errors"], LOCAL / "src/lynx")
    run(["lake", "build", "Veil"], LOCAL / "src/veil")
    from doctor import inspect
    report = inspect()
    (LOCAL / "bootstrap-result.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PASS: Grand local tooling ready. Use scripts/local.sh; no global environment was changed.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check installed tools without installing/building")
    args = parser.parse_args()
    try:
        LOCAL.mkdir(exist_ok=True)
        with (LOCAL / "bootstrap.lock").open("w") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError("Another bootstrap is running in this tree; wait for it to finish.") from None
            if args.check:
                from doctor import inspect
                print(json.dumps(inspect(), indent=2))
            else:
                provision()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Bootstrap failed: {error}\nCorrect the reported prerequisite/build error and rerun scripts/bootstrap.sh.", file=sys.stderr)
        sys.exit(1)
