# Grand — first-pass G01A implementation

Grand owns **normative requirement and assurance records**. BeamCompass remains
an independent product; Grand reads only its versioned portable JSON exports.
This repository is a headless G01A prototype, **not** a verified Grand system.

**Baseline delivery:** `GRAND-G01A-20261106-A` (see `delivery/manifest.json`).
**Authoritative docset on the user's machine:**
`~/p/g/n/brainstorms/nshkrdotcom/docs/20261106/grand/grand-docset`.
Its canonical continuation entry is `control/NEXT_AGENT.md`. No docset files
are vendored into the Grand code repository.

## Repository layout

Each path has its own `mix.exs`, `.formatter.exs` and `mix.lock`. There is **no
root `mix.exs`**, no umbrella, no BeamCompass source dependency, and no external
Hex dependencies. `grand_cli` is the fourth, thin orchestration app, preserving
one-way dependencies: `grand_core` <- `grand_beamcompass` and
`grand_assurance`; `grand_cli` -> all three. Empty `%{}` lockfiles explicitly
represent no external dependency locks for this first pass.

- `monorepo/grand_core`: JSON parser, deterministic codec, v1 record validation,
  and immutable append-only local file store.
- `monorepo/grand_beamcompass`: bounded, read-only v1 snapshot import/resolve.
- `monorepo/grand_assurance`: manually linked requirement revisions, explicit
  approval events, unformalized obligations, and **unrun** evidence bundles.
- `monorepo/grand_cli`: real `mix grand` import/link/approve/inspect/export.
- `fixtures`: synthetic Hold Ledger-inspired JSON inputs (no payment code).
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
  authentication. It is a prototype-only approval control pending user review
  of ADR-0003 and an actual authorization solution; AI-labeled actors are denied.
* Imported facts are syntactic occurrences (`source`, `proposed`, or
  `unresolved`), not observed calls or causal reachability. Capsules remain
  provisional. All object references are exact project+snapshot+fact IDs.
* A receipt contains an `UNFORMALIZED` obligation, a `verification_result`
  with `status=unrun`, and `coverage_summary.status=unassessed`. No engine or
  target software executes. The SHA-256 fingerprint is **not** a proof.
* Local storage hard-links an fsynced temporary file to an immutable path; the
  operator chooses the store root. Source paths from v1 anchors are checked as
  relative strings and are **never opened**.
* The fixture is synthetic, not a checked Hold Ledger test or a BeamCompass
  accepted P02 v2 export. No real v2 adapter is implemented.
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

A repository-wide convenience command is `./scripts/check.sh`. Credo and
Dialyzer are **not bundled**; installing/pinning them is a separate G01B choice.
The ChatGPT first-pass environment lacked Mix/Elixir, so **none** of these
runtime checks was run. Written ExUnit tests are not a claim of passing tests.
See `delivery/manifest.json` and the docset G01A handoff for static evidence.
