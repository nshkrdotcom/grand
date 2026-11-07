# G04B tooling closeout — user-amended scope

**Complete:** reproducible local tooling and installation smoke. **Next: G05A
implementation.** By explicit user direction, genuine Lynx source-law integration,
positive/negative law qualification, the distinct Veil adapter/experiments and
new-worker acceptance are transferred to G05A/G05B. They are not claimed passed.
Historical runtime_verified_through remains G03B.

Installed in Grand's own ignored .local/ on Ubuntu 26.04.1 x86_64:
Elan 4.2.4; Lean 4.35.0/Lake 5.0.0-src+eb6cafb; Lynx revision
81c9f7ffa69a6b56bf5c831cd41559afd54abff2; Veil revision
57447722e7f25f06c75cff8735d10d41697afc14; Node v24.22.2/npm 11.19.1;
TLC 2.19 from official TLA+ v1.7.4; cvc5 1.3.2 native libraries;
locally built LLVM 21.1.8 libc++/libc++abi/libunwind.

PASS: installation from initially empty Grand tool directories, using pinned
artifacts (Lean/Elan download cache seeded from Hold Ledger, rechecked before
extraction; no installed sibling tool dependency). Lynx library/runner build and
Lynx.Laws load; Veil library build/import and trivial declaration elaboration;
version checks; native C++ compile/link probe; cvc5 library integrity checks.
PASS: unchanged bootstrap rerun, with UV_OFFLINE=1; reused installed tools and
incremental builds. This establishes reuse, not a universal offline-install claim.
PASS: bootstrap --check and 6 offline failure/recovery tests. Corrupt cached
downloads and archive traversal fail closed; interrupted extraction retries;
missing Java produces installation guidance; parent environment stays unchanged.
Concurrent bootstrap is rejected with a friendly message.

The first attempts exposed missing libc++ headers (resolved by adding a local
runtime build), a required libunwind build setting (fixed), and TLC's normal
help exit 1 (doctor now checks its expected help/version behavior). No apt,
sudo, system installation or global profile/config changes were performed.
Lynx's upstream build emits a nonfatal Lean unused-simp-argument linter warning;
it is retained, not suppressed. This is tool build smoke, not law acceptance.

All Python commands use uv. Root bootstrap.sh/local.sh and docs/TOOLING.md are
the maintained entry points. Tool inputs/checksums, lean-toolchain, Python/uv
locks are delivered; .local/, .venv/, deps/_build, caches and generated outputs
are excluded. New environments need the documented existing BEAM/Java/native
prerequisites, not this machine or ../hold_ledger. Four Grand Mix apps remain.

Earlier source validation remains separate: 24 Mix gates/70 tests and actual
finite TLC pass/counterexample were recorded before this tooling-only pass.
No Mix app source changed in this pass. G03B's 24 gates/55 tests remain historical.
No approval, exact G03 refs/journal or conditional unrun receipt changed.

G05A implements G05-T01..T09, including original change impact/staleness and the
transferred integrations. The ChatGPT A environment may lack installed tools;
it must still author actual workers/fixtures/tests and report available checks.
B bootstraps and executes real backend acceptance. Use only the latest two ZIPs
and the ONE prompt at handoffs/NEXT_IMPLEMENTATION_AGENT_PROMPT.txt.
