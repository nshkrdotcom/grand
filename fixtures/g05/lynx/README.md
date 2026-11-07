# Portable Hold Ledger law package (original Grand fixture, MIT)

`Source.ex` defines a **pure** capacity-release seam: a void *request* leaves
released capacity unchanged; trusted terminal void confirmation may free one
unit. `SourcePremature.ex` is the intentional mutant releasing at request time.
`Law.ex` provides a Lynx **Elixir** `law` with a Lean proof over the translated
called function, **not** a standalone, manually written Lean reflexivity lemma.
`Support.ex` is an explicit local support dependency. These three selected
files are compiled in the private worker, not the target application, with
`Lynx.Laws.verify/2` and its Lean runner. It is deliberately a tiny abstraction
of Hold Ledger semantics, **not** the actual payment app or the historical
G03 property (G03's approved obligation is a synthetic retry/remote-effect
property). Linking it to that G03 scope is a constrained experiment, not proof
of the G03 obligation. External confirmation truth, identity fences, remote
processor deduplication and durable commit order are outside this law.

Origin: Grand G05 original fixture authored for this phase, derived in concept
from evaluation/hold-ledger.md, without copying the separate Hold Ledger app.
License: MIT, Grand LICENSE. Upstream translator: josevalim/lynx pinned in
scripts/toolchains.json (Apache-2.0); external library is NOT redistributed.

B must check the good and mutant using real Lynx/Lean, inspect translated
modules and kernel/axiom evidence, and repair proof script against the pinned
translator as needed. Neither a parser fixture nor `lean Law.lean` qualifies.
