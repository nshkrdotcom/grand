# Local verification tools

Starting environment: **Ubuntu 26.04 x86_64**, **uv** on PATH, existing
**Elixir 1.20.5 built with OTP 29 / OTP 29.1.2**, and **Java 21–25**
(qualified here: OpenJDK 25). Existing native prerequisites: `/usr/bin/clang`
and `clang++`, CMake, Ninja, make, curl, unzip and Git. Git is used by Lake
for external dependencies. Bootstrap diagnoses
missing prerequisites. It never invokes apt, sudo or a system installer.

From any directory:

```sh
/path/to/grand/scripts/bootstrap.sh
/path/to/grand/scripts/bootstrap.sh --check
```

The first run uses `uv sync --locked`, installs pinned tools locally and builds
Lynx and Veil. Reruns reuse checked artifacts and incremental builds. Allow
several GB of disk and network access to GitHub, Node and Python package hosts.
Interrupted downloads/extractions can be retried. A corrupt cached artifact or
conflicting published installation fails with its path; remove only that named
generated artifact and rerun. Run one bootstrap at a time per extracted tree.

Tools: Elan 4.2.4, Lean 4.35.0 with Lake, pinned Lynx and Veil source revisions,
TLC 2.19 from TLA+ release v1.7.4, pinned Node 24/npm, and locally built LLVM
C++ runtime libraries for Veil's cvc5 binding. Exact sources/checksums are in
`scripts/toolchains.json`; Veil's Lake manifest pins its Lean dependencies and
npm lockfiles pin its widget dependencies. `lean-toolchain`, `.python-version`
and `uv.lock` are included. Download checksums concern tool installation, not
Grand ZIP provenance. No global shell profile or tool configuration is changed.

Use the wrapper; it sets local Elan/Node/compiler/cache paths and
`GRAND_TLC_JAR`, `GRAND_LYNX_ROOT`, `GRAND_VEIL_ROOT` for that child process:

```sh
./scripts/local.sh lean --version
./scripts/local.sh --tool lynx mix compile --warnings-as-errors
./scripts/local.sh --tool veil lake build Veil
./scripts/local.sh --cwd monorepo/grand_assurance mix test
uv run --locked python scripts/doctor.py
```

All Python commands use **uv**. Run repo checks with `uv run --locked python
scripts/static_validate.py` (and the G02/G03/G04 scripts). Docset has its own
locked uv environment: from its root use `uv run --locked python
tools/docsetctl.py check` and `uv run --locked python -m unittest discover -s
tools -p 'test_*.py' -v`.

`.local/` contains installed tools, upstream source, downloads, caches, smoke
files and `bootstrap-result.json`; `.venv/` contains Python dependencies.
Both, `tmp/`, Mix `deps/`/`_build/`, and Python caches are ignored and excluded
from delivery ZIPs. They can be regenerated. No installed tool is shipped in
the ZIPs. No sibling Hold Ledger directory is required on a new machine.
