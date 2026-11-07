# Grand agent instructions

**Delivery authority:** Companion docset `control/WORKFLOW.md` overrides any
conflicting historical/reference delivery instructions. Use only the latest
`grand-repo.zip` and `grand-docset.zip`, extracted directly as `grand/` and
`grand-docset/`. The archive-internal roots are **not** output file paths.
Local agents write `/tmp/grand-repo.zip` and `/tmp/grand-docset.zip` on their
own host; ChatGPT agents return downloadable `grand-repo.zip` and
`grand-docset.zip` from their available artifact directory. Return a direct
link to the **only** continuation prompt at
`grand-docset/handoffs/NEXT_IMPLEMENTATION_AGENT_PROMPT.txt`, already inside
the docset ZIP. No duplicate prompt, external handoff tree, phase-prefixed ZIP
names or assumed access to the user's machine.

No Grand Git checkout, commits, archive provenance, archive hashes or
per-command audit matrices. Do not push. External tool source pins/download
checksums and Lake's Git dependency fetching are separate from Grand delivery
and remain required for reproducible tools.

Read README.md, docs/TOOLING.md and the companion docset's control/WORKFLOW.md,
control/NEXT_AGENT.md, control/state.json, foundation/current-state.md and the
active phase sections. Follow handoffs/NEXT_IMPLEMENTATION_AGENT_PROMPT.txt.

All Python commands use uv. Run scripts/bootstrap.sh for local tool setup and
scripts/local.sh for child commands. No apt, sudo, system installation or global
configuration changes. Assume Ubuntu 26.04 x86_64, uv, existing Elixir 1.20.5
built with OTP 29, OTP 29.1.2, compatible Java and documented native prerequisites.
Tools/cache directories are ignored and never included in delivery ZIPs.

User rescope: G04B closes tooling setup and existing Mix/TLC validation only.
G05A implements genuine source-linked Lynx -> Lean qualification, its safe worker,
a distinct Veil adapter/experiments, integrated CLI/contracts and original change
impact/staleness tasks. Installation smoke is not a law/model acceptance result.
The next A agent implements source/tests even if its environment lacks the tools;
local B executes actual acceptance. No review-only handoff or tool-absence loop.

Preserve four independent Mix apps; no root mix.exs. Direction: Core <- Assurance
and BeamCompass; CLI -> all. BeamCompass is JSON-only v1/v2 source evidence.
Do not alter exact G03 historical refs, approvals, journal or conditional unrun
receipt; do not execute target mix.exs/anchors during import. No auto-approval,
production identity/durability, runtime causality or unbounded correctness claims.

Run each app's deps.get --check-locked, format --check-formatted,
compile --warnings-as-errors, test, credo --strict and dialyzer when code changes
require them. Repair failures; report actual PASS/FAIL/UNRUN. Historical G03B
24 Mix gates/55 tests remain independent. Return exactly the two named,
ignore-respecting ZIPs and link the one existing prompt in the docset; follow
`control/WORKFLOW.md` for output locations and ZIP-open verification.
