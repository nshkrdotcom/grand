# Veil finite-state Hold void model (original Grand fixture, MIT)

These models use **actual pinned Veil 2.0 DSL**, `public import Veil`,
`veil module`, `individual`, `action`, `safety`, `#gen_spec` and
`#model_check interpreted {} {} (sequential := true)`. There is no fabricated
`veil` executable. Source reference: pinned `Examples/Tutorial/Ring.lean` and
`docs/ModelChecker-Guide.md` in verse-lab/veil, Apache-2.0 (external library
not redistributed). Mode: interpreted explicit-state, no SMT solver or SMT
axiom from that mode, finite two-Boolean-state variables, no depth bound,
no fairness, termination/liveness unspecified.

`Safe.lean` preserves `released -> confirmed` for `request_void`, and
`Bad.lean` violates it on that action. Both must be checked by *actual* Veil
before reported as model acceptance. Batch results may be InfoView-only;
absence of recognized checker output must be **inconclusive**, never
`bounded_pass`. This model is **not** target Elixir semantics and does not
establish an unbounded implementation invariant. `Model.tla`/`BadModel.tla`
are independent TLC translations with matching named intended property.
