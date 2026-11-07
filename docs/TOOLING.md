# Local verification tools

Starting environment: **Ubuntu 26.04 x86_64**, **uv** on PATH, existing
**Elixir 1.20.5 built with OTP 29 / OTP 29.1.2**, and **Java 21–25**
(qualified here: OpenJDK 25). Existing native prerequisites: `/usr/bin/clang`
and `clang++`, CMake, Ninja, make, curl, unzip and Git. Git is used by Lake
for external dependencies; Grand needs no Git checkout. Bootstrap diagnoses
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

Installation checks build Lynx's runner, load `Lynx.Laws`, build/import Veil,
elaborate a trivial Lean declaration and check TLC's version/help. They do
**not** establish a genuine Grand-linked law proof or a Veil model result.
G05A implements those integrations and tests. Grand retains four independent
Mix apps; `.local/src/lynx` is an external tool source, not a fifth Grand app.

## G05B mandatory real-engine and CLI qualification

G05A contains authored fixtures in `fixtures/g05/`: `lynx-good` (source,
support, law), `lynx-bad` (premature release), `veil-safe`, `veil-bad`,
`tlc-safe`, `tlc-bad`, versioned impact snapshots and G03 links. `scripts/
g05_contract_check.py --docset ../grand-docset` statically verifies versions
and fixture contracts but **cannot** certify a theorem or model. The external
pinned Lynx/Veil trees reside in ignored `.local/` and are not Grand Mix apps.

From `grand/`, after bootstrap and `--check`, provision an isolated G03 fixture
store using the source tests/CLI harness. These commands exercise the actual
new worker tests and real `mix grand` subprocesses:

```sh
GRAND_RUN_G05_ENGINES=1 ./scripts/local.sh --cwd monorepo/grand_assurance mix test test/g05_verification_test.exs
GRAND_RUN_G05_ENGINES=1 ./scripts/local.sh --cwd monorepo/grand_cli mix test test/g05_cli_integration_test.exs
./scripts/local.sh --cwd monorepo/grand_assurance mix test
./scripts/local.sh --cwd monorepo/grand_cli mix test
uv run --locked python scripts/g05_contract_check.py --docset ../grand-docset
```

Execute safe/bad TLC counterpart manifests through the **existing** G04 worker
with `GRAND_TLC_JAR` set by `scripts/local.sh`; the G05 positive/negative Veil
cases use Lean DSL `#model_check interpreted`. They compare the *finite Boolean
property* that releasing held capacity before terminal confirmation is forbidden.
Models are independent translations, not checker equivalence; no fairness or
unbounded system correctness is inferred. Run the rest of each app's six Mix
gates (`scripts/check.sh` via the wrapper, or individually) and both docset uv
checks. Never promote results from Lean elaboration, parsed fake output, stale
source/tool fingerprints or installed engine version smoke.

**Known A-to-B qualification risks:** the fixture's concrete `simp` proof must
compile and prove under the pinned Lynx translator; support/library closure and
independent export check must be witnessed. Veil's `#model_check` may produce
InfoView messages not printed in batch `lake env lean` stdout/stderr. The adapter
returns `inconclusive` rather than assuming success; B must inspect pinned
upstream APIs and implement a real result-emission path if necessary. Document
named laws/dependencies, axiom visibility/trust, explicit finite bounds and
actual counterexample witness. Repair and rerun before aggregate acceptance.
