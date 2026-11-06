> Historical validation report. Its test results remain valid; the earlier
> Partial/Draft outcome is superseded by the authoritative docset's
> handoffs/G01B-CLOSURE.md and control/WORKFLOW.md. G01B is complete for the
> local prototype; next is Grand G02A implementation. No repeat closure gate.

# G01B local validation — 2026-11-06

Delivery: `GRAND-G01A-20261106-A`; continuation: `G01B-local-20261106`.
Repository baseline: `6f2eecc534e6ff1eceff1d930dff00e18dc9b72c`.
Authoritative docset baseline: `98383e1115ad1c84f552e7992003222028ab4bb8`
(in the separate brainstorms repository).

All 24 required Mix gates passed (exit 0) on the repaired tree:
`mix deps.get --check-locked`, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test`, `mix credo --strict`,
`mix dialyzer`, from each independent project. See
`g01b-logs/final-results.json` for command, app, duration and full output path.
Core: 5 tests; BeamCompass adapter: 4; Assurance: 3; CLI: 2, including
real subprocess import → link → approve → inspect requirement/fact → export.
No Dialyzer warnings were skipped. Credo checks were not disabled.

Initial Credo failures and the intermediate repair run are retained in
`g01b-logs/`. Repairs extract parser/validator helpers, remove a tautological
float comparison and redundant CLI with clauses. Added codec regression
coverage for numbers, escapes and nested JSON. Existing tests exercise invalid
version, duplicate IDs, missing anchors, traversal, source nonexecution,
immutable conflict, wrong snapshot/kind/status and stored-envelope tampering.
CLI negative controls reject unknown versions and existing export paths.
`sh scripts/smoke.sh <fresh temporary store>` and static validation also pass;
see `g01b-logs/extra-results.json`.

Runtime: Elixir 1.20.4, OTP 29.1.2 (pinned in `.tool-versions`). All four
lockfiles pin Credo 1.7.19 and Dialyxir 1.4.8; already present on entry.

The original ZIPs were not supplied/found in the inspected locations. Original
archive byte checksums cannot be independently confirmed. The code manifest
matches 21/42 entries; changes are preserved in existing commits (packaging,
assets, docs and development dependencies). The authoritative docset manifest
matches 109/109 entries before this pass. Baseline comparisons are retained;
no tree was replaced and no history rewritten. The original manifest remains
historical; `g01b-manifest.json` inventories this continuation.

G01A and G01B remain Partial/Draft: ADR-0003/0005 require explicit user
approval. No approval was inferred from the instruction to continue.
Human actor labels remain self-attested; production authentication and durable
storage qualification are unresolved. No external proof engine or real target
program ran. G02–G07 remain Draft/Not Started; no accepted v2 export was verified.
