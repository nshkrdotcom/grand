# Grand G05 portable source-only verification fixtures (MIT original work)

All fixtures ship inside `grand/`. The source-linked `lynx/` package includes
selected `Portable`, `Support` and law modules plus `SourcePremature.ex` for
the deliberately invalid release-on-request case. This is a genuinely
source-translated Lynx law, not a handwritten toy reflexivity theorem. Origin,
license, positive/negative semantics and admitted abstraction appear under
`lynx/README.md`. Only pinned tool-driven translation/Lean checking can yield
named theorem evidence; B must validate and repair the actual proof script.

`veil/` contains independent `Safe.lean`, `Bad.lean`, and TLA+ `Model.tla`,
`BadModel.tla`, `Model.cfg`. Each expresses a small no-premature-release
finite Boolean safety property; no fairness, runtime correspondence or
translation equivalence is proved. Veil uses its actual pinned Lean DSL and
`#model_check` command, not a fabricated standalone executable. B must
capture real checker results, not just elaboration. `impact/` contains v1/v2
BeamCompass source-only snapshots and explicit reverse links to an approved
historical G03 fixture; they are test evidence for staleness only, not proof.

The four G05 v2 JSON manifests and two G04 TLC v1 manifests repeat exactly the
existing synthetic-retry G03 approved obligation pins **only as authorization
scope**. The differently stated Hold Ledger void safety property does **not**
automatically discharge that G03 obligation or rewrite its conditional unrun
receipt. All A engine cases were UNRUN; G05B must run them.
