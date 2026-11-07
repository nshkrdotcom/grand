> Historical partial validation. The user subsequently moved real law/Veil integration to G05A and assigned G04B tooling setup; see BOOTSTRAP.md.

# G04B validation and repairs — acceptance incomplete

All six requested Mix gates PASS in each of the four independent apps on
Elixir 1.20.5-otp-29 / OTP 29.1.2. ExUnit: Core 15, BeamCompass 16,
Assurance 27, CLI 12: **70 passed, zero failures**. Assurance and CLI tests ran
with GRAND_TLC_JAR pointing at the official release v1.7.4 JAR. No mock result
is counted as engine qualification. Static/G02/G03/G04 Python checks PASS;
legacy smoke PASS in an isolated fresh store; docsetctl and 13 Python tests PASS.

Real TLC 2.19 (08 August 2024, rev 5a47802): finite Model/Model.cfg Limit=2,
fairness none, Safe=count<=Limit returns bounded_pass, 3 distinct states;
BadModel Safe=count<Limit returns counterexample, exit 12, trace count=0,1,2.
Real CLI result JSON is in source delivery/g04b-results/{tlc,tlc-bad}-result.json.
Those results retain exact G03 bindings, assumptions, hypotheses, open witness
gaps, output and qualifications. Their temporary G03 store no longer exists;
they record these runs, not reusable proof against a new store.

UNRUN: actual Lean named theorem/axiom-free checking, invalid-law engine
execution, and a genuine trusted source-linked Hold Ledger/Lynx law package.
Lean is absent from PATH and no genuine law bundle is supplied in the ZIPs.
The synthetic reflexivity fixture is not a real Hold Ledger law. Thus G04 and
G04B remain In Progress; runtime_verified_through stays G03B. G03B historical
24-gate/55-test acceptance remains independent and unchanged.

Repairs: formatted new source/tests; created the cancellation fixture directory;
refactored Credo complexity/nesting without disabling checks; guarded malformed
CLI law/model path types; rejected contradictory TLC success/violation reports;
made workspaces random and mode 0700; added process-group termination and file
size limits. Added descendant-kill, stream separation, workspace cleanup, malformed
JSON and actual TLC CLI/applicability tests. Scripts are executable. No Core or
BeamCompass source changes, target Mix execution, approval or G03 journal rewrite.

Earlier attempts failed format, one fixture test, Credo, and CLI Dialyzer's stale
PLT missing new Assurance modules. Repairs resolved the source/test issues;
`mix dialyzer --force-check` added 7 modules and passed, followed by ordinary
`mix dialyzer` passing. No warning suppression or failure waiver was introduced.

Reproduce from each independent app: mix deps.get --check-locked;
mix format --check-formatted; mix compile --warnings-as-errors; mix test;
mix credo --strict; mix dialyzer. For the actual TLC tests export GRAND_TLC_JAR
with the path to the separately installed official v1.7.4 tla2tools.jar.
Use sh scripts/smoke.sh /a/fresh/temp/store for the legacy smoke.

Limits: Linux sh/setsid/kill are required for opted-in execution. Stream returns
are each capped; file caps round upward to 512-byte blocks on the tested host.
Polling can overshoot the requested aggregate byte budget within those caps.
This runner is not an OS sandbox and deliberately escaping trusted code is outside
its containment. Trust the engine/JAR and explicitly opted-in law code. Output
signatures are parser checks, not authenticated proof certificates. No target
translation/runtime correspondence, unbounded correctness, production identity
or durability is established. G03 conditional receipts remain unrun/unassessed.

Continue implementation and repair using the single prompt at
handoffs/NEXT_IMPLEMENTATION_AGENT_PROMPT.txt in the docset. Do not start G05A
until genuine remaining G04 acceptance passes. Continue using only the two ZIPs.
