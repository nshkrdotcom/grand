# Grand code-agent entry

1. Read `README.md`, `delivery/manifest.json`, and the **authoritative** docset
   at `~/p/g/n/brainstorms/nshkrdotcom/docs/20261106/grand/grand-docset`:
   `control/NEXT_AGENT.md`, `foundation/current-state.md`, then G01A/G01B
   manifests and bounded required reading. The docset is outside this repo.
2. If those paths are absent in your environment, locate the existing Grand
   repository from the current working directory; obtain the actual docset path
   before modifying its state. Never treat an uploaded Repomix dump as a
   guaranteed current in-place docset.
3. Verify matching delivery ID `GRAND-G01A-20261106-A` and hashes. Perform
   independent cold-read; keep phase readiness Draft until all gates and
   approval-sensitive ADR decisions are resolved.
4. Run local Mix gates per project. Fix errors, add tests and pin/check Credo
   and Dialyzer as warranted. Never claim an unrun check passed.
5. The projects are separate (`monorepo/*/mix.exs`); there is no root Mix file.
   BeamCompass remains an independent project with JSON-only integration.
6. Reconcile docset current-state, phase manifests, traceability, decisions,
   risks, quality-gates, NEXT_AGENT and handoff with observed results. Do not
   mark other phases Ready or Complete without dependency evidence.
7. Commit completed code and docset changes independently if they have
   separate Git histories. Do not push unless requested. For a continuing
   cycle, return both ZIPs with matching manifests, a commit-message proposal
   and a short next-agent prompt.
