<p align="center">
  <img src="assets/grand.svg" alt="Grand" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand — versioned source evidence and bounded local queries

Grand owns **normative requirement and assurance records**. BeamCompass remains
an independent product; Grand reads only its versioned portable JSON exports.
This repository is a headless prototype. G01B passed its historical 24 local Mix gates. G02B validation and repairs are recorded in `delivery/G02B-VALIDATION.md`.

**Delivery:** The supplied `grand-repo.zip` and `grand-docset.zip` are the
sole working inputs and outputs for G04A and all later A/B phases. Unzip both,
work directly on the extracted source/doc files and return two updated ZIPs.
There is no checkout, commit, archive checksum or provenance prerequisite.
See docset `control/WORKFLOW.md` for the continuing rule. Historical G03B
runtime acceptance remains separate from the new G04A implementation.

## Repository layout

Each path has its own `mix.exs`, `.formatter.exs` and `mix.lock`. There is **no
root `mix.exs`**, no umbrella, no BeamCompass source dependency, and no BeamCompass implementation dependency. `grand_cli` is the fourth, thin orchestration app, preserving
one-way dependencies: `grand_core` <- `grand_beamcompass` and
`grand_assurance`; `grand_cli` -> all three. Development tools are locked separately in each project: Credo 1.7.19 and
Dialyxir 1.4.8 (plus ExDoc and their dependencies).

- `monorepo/grand_core`: JSON parser, deterministic codec, preserved v1 records,
  additive versioned v2 exact refs, and immutable append-only local file store.
- `monorepo/grand_beamcompass`: distinct read-only v1/v2 snapshot adapters,
  exact typed resolution and bounded Grand-local evidence queries.
- `monorepo/grand_assurance`: manually linked requirement revisions, explicit
  approval events, unformalized obligations, and **unrun** evidence bundles.
- `monorepo/grand_cli`: `mix grand` import/link/approve/inspect/query/export.
- `fixtures`: synthetic legacy inputs and portable actual BeamCompass P02B
  exported JSON copies (no payment implementation code).
- `scripts/check.sh`: per-project complete quality gates; fails if tools absent.
- `scripts/smoke.sh`: fixture demonstration (run only with Elixir installed).

## Usage (Elixir/Mix ~> 1.20.5 and OTP 29.1.2 required)

Run from `monorepo/grand_cli`. All options use long-form `--` flags:

```sh
cd monorepo/grand_cli
mix deps.get --check-locked
mix grand import ../../fixtures/beamcompass_v1.json \
  --project synthetic-ledger --store ../../grand-store
mix grand link ../../fixtures/requirement_pending.json \
  --project synthetic-ledger --snapshot synthetic-hold-snapshot-001 \
  --fact synthetic-fact-void-intent-001 --actor human:fixture-submitter \
  --store ../../grand-store
mix grand approve synthetic-REQ-void-confirmation \
  --actor human:fixture-reviewer --ack-human --store ../../grand-store
mix grand inspect requirement synthetic-REQ-void-confirmation \
  --store ../../grand-store
mix grand inspect fact synthetic-ledger synthetic-hold-snapshot-001 \
  synthetic-fact-void-intent-001 --store ../../grand-store
mix grand export synthetic-REQ-void-confirmation \
  --project synthetic-ledger --store ../../grand-store
```

To write a bundle instead of stdout, append `--out new-file.json` to `export`.
The output must not already exist. Each command emits one JSON object on stdout;
errors produce a nonzero `mix` exit status. An unchanged source snapshot can be
reimported; a conflicting object cannot overwrite the prior record. Requirement
revision 1 remains available after explicit approval creates revision 2.

### Important scope boundaries

* `--actor human:... --ack-human` is a **manual self-attestation**, not identity
  authentication. It is an authorized local prototype control; a production
  authorization design remains separate; AI-labeled actors are denied.
* Imported facts are syntactic occurrences (`source`, `proposed`, or
  `unresolved`), not observed calls or causal reachability. Capsules remain
  provisional. All object references are exact project+snapshot+fact IDs.
* A receipt contains an `UNFORMALIZED` obligation, a `verification_result`
  with `status=unrun`, and `coverage_summary.status=unassessed`. No engine or
  target software executes. The SHA-256 fingerprint is **not** a proof.
* Local storage hard-links an fsynced temporary file to an immutable path; the
  operator chooses the store root. Source paths from v1 anchors are checked as
  relative strings and are **never opened**.
* The legacy v1 Hold Ledger-inspired fixture is synthetic. Separate pinned
  actual P02B v2 JSON exports are bundled for G02 tests; they do not prove a
  target Hold Ledger implementation, observation or causal effect.
* Do not use this as an authorization service or proof service. Do not export
  sensitive source content or grant untrusted principals write access to store.

## G03B local acceptance

G03B passed all 24 ordered Mix gates on Elixir 1.20.5-otp-29 / OTP 29.1.2.
ExUnit: Core 15, adapter 16, Assurance 16, CLI 8: **55 passed, zero failures**.
All six stable G03 acceptance IDs, legacy v1/G02 regressions, isolated smoke,
Python contract/schema checks and 25 supplemental real CLI subprocesses passed.
Exact commands, timestamps, versions, lock hashes, statuses, exit codes and
stdout/stderr are under `delivery/g03b-logs/`, with `acceptance-matrix.json`. Earlier
failed attempts are retained separately. The accompanying docset ZIP retains G03B records independently, plus the
G04A source handoff and one G04B continuation prompt.
No target/checker execution, authenticated identity, causality, proof or production
durability is claimed; G03 receipts remain conditional unrun/unassessed records.
The G03A authoring section below retains its original historical UNRUN scope.

## Quality/validation status

The receiving local agent should run, from each of the four project directories:

```sh
mix deps.get --check-locked
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
```

A repository-wide convenience command is `./scripts/check.sh`. The local G01B
run uses Elixir 1.20.4 / OTP 29.1.2 historically. G02B uses Elixir 1.20.5 / OTP 29.1.2, pinned in `.tool-versions`. Exact command
outputs and exit codes are under `delivery/g01b-logs/`; see
`delivery/G01B-VALIDATION.md` for results and limitations. G01B is complete for its bounded local prototype. G02A source was authored
without Mix runtime validation; G02B independently verifies the user-committed
A trees and records repairs and exact results in `delivery/g02b-logs/`. See the authoritative docset `control/WORKFLOW.md` and
`control/NEXT_AGENT.md`.
Versioned references and immutable JSON storage are authorized for this scope;
production authentication/durability and stable external API release remain separate.

## Documentation and licensing

- [Grand Core](monorepo/grand_core/README.md) · [Core changelog](monorepo/grand_core/CHANGELOG.md)
- [Grand BeamCompass](monorepo/grand_beamcompass/README.md) · [BeamCompass adapter changelog](monorepo/grand_beamcompass/CHANGELOG.md)
- [Grand Assurance](monorepo/grand_assurance/README.md) · [Assurance changelog](monorepo/grand_assurance/CHANGELOG.md)
- [Grand CLI](monorepo/grand_cli/README.md) · [CLI changelog](monorepo/grand_cli/CHANGELOG.md)
- [MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom


## Versioned v2 import and local queries

The pinned, **actual** BeamCompass P02B source-only snapshots and exact refs are
bundled under `fixtures/upstream/beamcompass-p02b/` with upstream provenance
SHA-256 records. Grand does not depend on BeamCompass source or BeamCompass P03.
The `Grand.BeamCompass.V1` adapter retains v1 import/reference/store semantics;
`Grand.BeamCompass.V2` independently validates v2 canonical snapshot digests,
all typed collections, sorted IDs and evidence sets, source-only provider modes,
evidence derivation DAG, relation endpoints, effect/effect-intent type boundaries,
anchor safety and exact project/snapshot/evidence references. The v2 import lives
in a **separate immutable store collection** from v1; no silent v1 upgrades.
Unknown effect performers and ambiguous targets remain unresolved, not false.

The new `Grand.Core.validate("behavior_ref_v2", reference)` contract is an
exact pointer to **entity, relation or evidence**; legacy v1 `behavior_ref`
records and the v1 manual assurance pipeline retain their original schema.
This stage does not silently migrate v1 normative requirements to v2 references.

From `monorepo/grand_cli` with the pinned toolchain:

```sh
# Substitute ABS for the full path to this Grand checkout.
cd ABS/monorepo/grand_cli
mix grand import ABS/fixtures/upstream/beamcompass-p02b/a.json \
  --project fixture:ledger --schema 2 --store /tmp/grand-g02-demo
# Use the returned snapshot_id and a source entity ID from the JSON fixture.
mix grand inspect entity fixture:ledger SNAPSHOT_ID ENTITY_ID \
  --schema 2 --store /tmp/grand-g02-demo
mix grand query fixture:ledger SNAPSHOT_ID --focus ENTITY_ID --lens neighbors \
  --budget 8 --store /tmp/grand-g02-demo --out /tmp/grand-g02-query.json
mix grand export snapshot fixture:ledger SNAPSHOT_ID --schema 2 \
  --store /tmp/grand-g02-demo --out /tmp/grand-g02-export.json
```

`--preserve entity=ID` and `--preserve relation=ID` may repeat. Required
preserved relations include source and non-null target endpoints; insufficient
`--budget` returns an explicit error, never a silent dropped safety frontier.
`--budget` 1–256 bounds selected **entities + relations**; referenced evidence
and dependency ancestors are included separately. Every query returns complete
`receipt.preserved`, `receipt.omitted`, and `receipt.unresolved` lists and
counts for the *imported snapshot*, with `retained` flags on unresolved links.
`neighbors` is one hop; `connected` traverses retained adjacent records within
budget; `effects` is one-hop for `sends`, `may_deliver_to`,
`describes_effect`, `performs_effect`. Local query completeness and semantics are
never claimed, even when a subset happens to have no omissions. Query `--out`
and snapshot export refuse to overwrite an existing file. All imports only
read provided JSON, never anchor paths or target configuration.

ExUnit cases `G02-TEST-01`–`05`, rehashed hostile inputs and real Mix
subprocess CLI regressions exercise both pinned actual P02B exports. See
`delivery/G02B-VALIDATION.md` and `delivery/g02b-logs/` for independent B
results, including failures and repairs. Python contract checks supplement
Elixir execution. They do not establish runtime target behavior. G01B's
historical verification remains unchanged. The authoritative docset owns the
phase ledger and canonical next-A implementation prompt.

## G03A — additive v2 specification/assumption lifecycle (authored; runtime UNRUN here)

**Independent G03A portable delivery**, not a new runtime-verified baseline. G02B's 24-gate acceptance remains historical. Code, tests and docs are authored against Elixir **1.20.5-otp-29** and OTP **29.1.2** (`.tool-versions`; all four apps require `~> 1.20.5`); no Elixir/Mix was available in the G03A environment. Run each app's six gates at G03B; do not treat the Python checks as ExUnit passes.

`Grand.Core.G03` defines additive strict `candidate_v2`, `requirement_v2`, `assumption_v2`, `obligation_v2` records without mutating v1. `Grand.Core.LifecycleStore` publishes canonical SHA-256 linked immutable commits via a single local writer lock and atomic HEAD rename, replaying and validating full contiguous histories; tests inject precommit/pre-HEAD failures, tampering and stale HEAD conflicts. Single-directory 512-commit and 4MB bounds; this does **not** guarantee durability against power-loss, hostile full-store rewrites, distributed writers or authenticated history.

`Grand.Assurance.G03` supports candidate propose/reject/supersede, human-labelled requirement draft/submit/approve/reject/supersede, assumption register/revise (`external|compiler|model|runtime`, open gaps, no external attestation as proof), and obligation creation over **exact approved historical requirement revision, exact source refs, exact assumption revisions**, explicit witness/preconditions and typed vacuity/contradiction challenges. Receipts carry the pinned and latest assumption records and unresolved gaps; their verification is permanently `unrun` and coverage `unassessed` at G03. `human:` with `--ack-human` is a self-attestation string, **not authenticated identity or production authorization**; no agent approval or candidate auto-promotion.

`Grand.BeamCompass.Motif.retry_external_effect/1` takes only validated imported v2 source-only JSON. It asks a reviewable question when a retry-labelled function is a typed resolved `performs_effect` source of an `effect` record; the preserved, omitted and unresolved *bounded* query receipt, exact refs, alternative explanation and limitations follow the question. This does **not** establish retries, external calls, bug, causality, equivalence or unknown performers. The included `fixtures/g03_synthetic_retry_v2.json` is **synthetic positive**, correctly rehashed, NOT an actual upstream export or proof. Original pinned P02B `a.json` is a required negative. Do not change BeamCompass source, wait for P03 or execute any target `mix.exs` or source anchors.

From `monorepo/grand_cli` after importing the synthetic fixture (or other validated exact source), an illustrative lifecycle is:

```sh
mix grand import ../../fixtures/g03_synthetic_retry_v2.json --project fixture:synthetic-retry --schema 2 --store /tmp/grand-g03-demo
mix grand g03 propose ../../fixtures/g03_candidate_input.json --actor agent:motif --store /tmp/grand-g03-demo
mix grand g03 assumption register ../../fixtures/g03_assumption_input.json --actor human:reviewer --ack-human --store /tmp/grand-g03-demo
mix grand g03 requirement draft ../../fixtures/g03_requirement_input.json --actor human:reviewer --ack-human --store /tmp/grand-g03-demo
mix grand g03 requirement submit g03-confirm-once --actor human:reviewer --ack-human --store /tmp/grand-g03-demo
mix grand g03 requirement approve g03-confirm-once --actor human:reviewer --ack-human --store /tmp/grand-g03-demo
mix grand g03 obligation create ../../fixtures/g03_obligation_input.json --actor human:reviewer --ack-human --store /tmp/grand-g03-demo
mix grand g03 receipt g03-obligation-once --store /tmp/grand-g03-demo --out /tmp/grand-g03-conditional.json
mix grand g03 history requirement g03-confirm-once --store /tmp/grand-g03-demo
```

The imported snapshot ID is the digest reported by import; all fixture exact refs point to this particular synthetic digest. You can also `mix grand g03 motif propose fixture:synthetic-retry SNAPSHOT_ID --actor agent:motif --store /tmp/grand-g03-demo`, then explicitly reject the candidate as a human. Full CLI command/field details are in `Grand.CLI` help and the authoritative docset `contracts/interfaces.md`. G03A ExUnit cases in all four projects, including a real `System.cmd("mix", ["grand", ...])` subprocess lifecycle, are authored **UNRUN here**. Static checks: `python3 scripts/static_validate.py`, `python3 scripts/g02_contract_check.py`, `python3 scripts/g03_contract_check.py --docset PATH`. Existing G01/G02 source fixture and query receipts are unchanged.

## G04A — explicit Lean and finite TLC verification (authored, not runtime accepted)

From `monorepo/grand_cli`, use an existing G03 store with an approved exact
G03 requirement and registered obligation (the synthetic CLI integration test
creates such a store). Example manifests are in `../../fixtures/g04/`:

```sh
mix grand g04 inspect ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store
mix grand g04 run ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store --execute --tlc-jar /path/to/tla2tools.jar
mix grand g04 run ../../fixtures/g04/lean-manifest.json --store /path/to/g03-store --execute --allow-law-code
mix grand g04 applicability result.json ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store
```

`inspect` never launches a checker. `run` defaults to `unrun`; `--execute` is
required, and Lean source needs the extra `--allow-law-code` opt-in. No imported
BeamCompass anchor or target Mix project is executed. Only trusted local law or
model files should be passed; the disposable workspace is **not** an OS or
network sandbox. Arguments are allowlisted and output/time bounds enforced.

A result lists its exact G03 scope, named law or finite model, bound, fairness,
hypotheses, assumption revisions, open witness gaps, engine version, separate
stdout/stderr, and distinct `proved` / `bounded_pass` / `counterexample` /
`inconclusive` / `unsupported` / `error` / `unrun` statuses. `applicability`
returns `current` or `stale` for source/assumption changes. It is not a verdict
about runtime conformance or unbounded behavior. Nothing approves a requirement.

G04A adds `Grand.Assurance.G04` and an adapter behaviour, Lean/TLC drivers,
`Grand.CLI.G04`, positive/negative toy fixtures, API/CLI security ExUnit tests
and a v3 result schema in the separate docset. It also adds
`scripts/g04_contract_check.py`. Python-only checks passed; Elixir/Mix, Lean
and a real TLC JAR are absent in this authoring environment, so all actual
Mix/checker acceptance is **UNRUN**. G04B must run and repair those tests
when the toolchain is available. Synthetic fixtures are not Hold Ledger laws.
