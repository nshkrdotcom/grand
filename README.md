<p align="center">
  <img src="assets/grand.svg" alt="Grand" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand — G02A v2 evidence import authored (local G02B pending)

Grand owns **normative requirement and assurance records**. BeamCompass remains
an independent product; Grand reads only its versioned portable JSON exports.
This repository is a headless prototype. G01B passed its 24 local Mix gates; the new G02A source and tests are **authored but not yet Mix-verified**.

**Baseline delivery:** `GRAND-G01A-20261106-A` (see `delivery/manifest.json`).
**Authoritative docset on the user's machine:**
`~/p/g/n/brainstorms/nshkrdotcom/docs/20261106/grand/grand-docset`.
Its canonical continuation entry is `control/NEXT_AGENT.md`. No docset files
are vendored into the Grand code repository.

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

## Usage (Elixir/Mix >= 1.15 required)

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
run uses Elixir 1.20.4 / OTP 29.1.2, pinned in `.tool-versions`. Exact command
outputs and exit codes are under `delivery/g01b-logs/`; see
`delivery/G01B-VALIDATION.md` for results and limitations. G01B is complete for its bounded local prototype. G02A source was authored
without Mix runtime validation; next is local G02B verification on the user-
committed A changes. See the authoritative docset `control/WORKFLOW.md` and
`control/NEXT_AGENT.md`.
Versioned references and immutable JSON storage are authorized for this scope;
production authentication/durability and stable external API release remain separate.

## Documentation and licensing

- [Grand Core](monorepo/grand_core/README.md) · [Core changelog](monorepo/grand_core/CHANGELOG.md)
- [Grand BeamCompass](monorepo/grand_beamcompass/README.md) · [BeamCompass adapter changelog](monorepo/grand_beamcompass/CHANGELOG.md)
- [Grand Assurance](monorepo/grand_assurance/README.md) · [Assurance changelog](monorepo/grand_assurance/CHANGELOG.md)
- [Grand CLI](monorepo/grand_cli/README.md) · [CLI changelog](monorepo/grand_cli/CHANGELOG.md)
- [MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom


## G02A source-authored v2 import and local queries (awaits G02B Mix verification)

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

From `monorepo/grand_cli` after a local G02B toolchain check:

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

G02A has authored ExUnit cases `G02-TEST-01`–`05`, hostile rehashed/typed
inputs and real Mix subprocess CLI regressions. In this authoring sandbox,
**Mix/Elixir were unavailable and these are UNRUN**, not passed. The independent
`python3 scripts/g02_contract_check.py` checks pinned hashes, actual snapshots,
exact refs and rehashed negative controls, but is not a substitute for the six
Mix gates in each project. See the authoritative docset
`handoffs/G02A-HANDOFF.md` and canonical standalone G02B prompt for the local
verification and repairs. G01B's earlier verification remains unchanged.
