# G02B local acceptance — 2026-11-06

G02B passed on Elixir 1.20.5-otp-29 / OTP 29.1.2. Checked source HEAD:
7ac8ca3e8962c8e786e945232d65931f5a8b1421. Both initial trees were clean; user-committed A code was
604d771087eb80070db40c49ab775dc9debb5862 and parent documentation was
5e087ec66eb0ad9253d347601eb7ecfad82527d5. No A import/duplicate commit or push.

All 24 Mix gates passed in the required order in each independent project.
ExUnit: Core 7, adapter 12, Assurance 3, CLI 5 — 27 passed, zero failures.
All five stable G02-TEST IDs executed. All six gate commands, actual cwd,
checked HEAD, toolchain, timestamps, exit codes and combined stdout/stderr
paths are in g02b-runtime-evidence.json and g02b-logs/results.json.

The initial pass exposed three format failures, adapter/CLI Credo failures
and adapter/CLI Dialyzer failures. Logs under g02b-logs/initial and
intermediate retain those attempts; they are not passes. Repairs extracted
small validation/output helpers and replaced recursive MapSet visited sets with
plain maps to avoid opaque set inference. No checks were disabled. Mix projects
require Elixir ~> 1.20.5 and .tool-versions pins OTP 29.1.2 / Elixir 1.20.5.

Both actual P02B exports import and roundtrip; exact-0/1 refs resolve. Typed
source provenance, DAG, uncertainty, exact refs, immutable conflict/tamper and
hostile rehashed mode/type/path/graph/digest inputs execute in adapter tests.
JSON duplicate keys, excess size/depth and a decoy target mix.exs are rejected
or remain unexecuted. Source inspection confirms only input JSON/store files
are opened, never imported anchor paths. Legacy v1 tests and a real subprocess
import/link/approve/inspect/export pipeline retain unrun/unassessed output and
self_attested_not_authenticated identity. Manual approval is not authentication.

26 additional real mix grand subprocesses have full stdout/stderr transcripts
and exact actual fixture-derived IDs in g02b-logs/cli-results.json and cli-*.log.
They cover both exports, all inspect kinds, successful tight-budget preservation,
explicit insufficient-budget rejection, preserved/omitted/unresolved receipts,
portable export/re-import, overwrite, schema/project mismatch and invalid options.
The independent Python contract/static checks, smoke, authoritative docset
structural check and eight Python tests (no skips) pass. Thirteen Draft 2020-12
schemas, ten authoritative pinned hashes, four code/doc fixture byte matches
and two upstream exact refs pass. Final docset checks are rerun after reconciliation.

The independent receiving cold read is recorded separately. G01B's 24 gates /
14 tests remain historical. No BeamCompass source was changed. No target code,
upstream runtime, proof/checker, causal claim, semantic equivalence, human identity
or production durability is established. G02 local acceptance is bounded to
these inputs and prototype controls.

G02 aggregate and G02B are Complete; runtime_verified_through=G02B; next G03A.
The sole canonical next implementation prompt is
handoffs/NEXT_IMPLEMENTATION_AGENT_PROMPT.txt in the authoritative docset.
The final delivery commit IDs and ZIP hashes are recorded in the external
G02B delivery receipt, avoiding self-referential commit/archive hashes.
