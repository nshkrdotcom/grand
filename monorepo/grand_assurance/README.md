<p align="center">
  <img src="assets/grand_assurance.svg" alt="Grand Assurance" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand Assurance

Normative requirement linking, explicit human audit approvals, and unrun evidence receipts for Grand.

## Contents

- [Overview](#overview)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Documentation](#documentation)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)

## Overview

Part of [Grand](https://github.com/nshkrdotcom/grand), managing normative requirement lifecycles and verification obligations.

- Links requirements to validated `BehaviorRef` targets with deterministic revision advancement.
- Records explicit human self-attested approval events (`ack_human: true`), enforcing human accountability.
- Generates unrun evidence bundles and unassessed coverage summaries with deterministic hashing.

## Getting started

Requires Elixir >= 1.15. From this application's directory:

```sh
mix deps.get
mix compile
mix test
```

## Usage

```elixir
alias Grand.Assurance

store_root = "/path/to/grand-store"

# Link requirement to a behavior reference
{:ok, linked} = Assurance.link_requirement(req, behavior_ref, actor: "human:reviewer")
{:ok, path} = Assurance.save_requirement(store_root, linked)

# Approve requirement
{:ok, approved} = Assurance.approve(linked, actor: "human:reviewer", ack_human: true)
{:ok, path2} = Assurance.save_requirement(store_root, approved)
```

## Documentation

```sh
mix docs
```

The documentation menu includes this guide, API modules, the [changelog](CHANGELOG.md), and the [MIT license](LICENSE).

## Packaging

Build the Hex archive with:

```sh
MIX_ENV=prod mix hex.build
```

Development uses the sibling core application when available. Standalone installs resolve `grand_core` from Hex; publish `grand_core` before publishing this package.

## License

MIT — Copyright (c) 2026 nshkrdotcom. See [LICENSE](LICENSE).

## G03A additive implementation (runtime UNRUN)

`Grand.Assurance.G03` candidate, human-labelled requirement and assumption transitions, exact obligation and conditional unrun/unassessed receipt; v1 untouched.

See root README and authoritative docset G03 design/verification. Toolchain Elixir 1.20.5-otp-29 / OTP 29.1.2 is not present in G03A, so G03B must independently execute six required Mix gates here.

## G04A scoped verification (source authored; engine acceptance pending)

`Grand.Assurance.G04.run/3` checks a source-only JSON manifest against the
existing G03 approved obligation. `Grand.Assurance.G04.applicability/3` reports
`current` or `stale` after relevant source or assumption changes; it does not
rewrite G03. Independent `G04.Lean` and `G04.TLC` adapters share an explicitly
opted-in subprocess runner, never an implicit import or target-code executor.

From `monorepo/grand_cli`:

```sh
mix grand g04 inspect ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store
mix grand g04 run ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store --execute --tlc-jar /path/to/tla2tools.jar
mix grand g04 run ../../fixtures/g04/lean-manifest.json --store /path/to/g03-store --execute --allow-law-code
mix grand g04 applicability result.json ../../fixtures/g04/tlc-manifest.json --store /path/to/g03-store
```

Finite TLC results do not prove unlimited correctness. The named Lean toy law
is not a Hold Ledger source law. Unavailable checker/JAR is `unsupported`,
nonexecution is `unrun`, timeout/cancel is `inconclusive`, malformed output is
`error`, and G03's original unrun receipt remains unmodified. The runner is a
bounded local process boundary, not a hardened sandbox. The A authoring host lacked these tools. Subsequent B results and the
user-amended tooling/integration scope are recorded below and in the docset.

## G04B tooling scope / G05A implementation

Root `scripts/bootstrap.sh` installs the pinned local tools; use
`scripts/local.sh` to expose them to a child command. All Python runs through uv.
See root `docs/TOOLING.md`. Lynx law integration and the distinct Veil adapter
are G05A implementation work; the existing direct Lean adapter does not fulfill
source translation. Tool installation smoke is separate from law/model acceptance.

## G05A — source-linked Lynx/Veil verification and source-only change impact

`Grand.Assurance.G05.run/3` binds the exact approved G03 obligation, requirement
revision, source refs and assumptions and invokes independently implemented
`G05.Lynx` or `G05.Veil` only with explicit `execute: true,
allow_law_code: true`. Lynx stages selected BEAM source/support/law modules,
translates via `Lynx.Laws.verify/2` and requests Lean check; Veil uses the
actual pinned Lean DSL finite model checker. The G04 runner enforces private
staging, command allowlists, bounded separate streams, timeout/cancel cleanup.
This is a local process boundary, not a complete sandbox or verified identity.

`G05.Impact` reads existing BeamCompass source-only JSON v1/v2, preserves
unresolved cross-revision identity, and produces reverse source/model/
assumption/requirement/obligation/result links without importing or executing
target code. `G05.applicability/4` compares source/support/law/model content,
manifest, requirement/assumption revisions and installed tool fingerprint;
it does not rewrite original G03 records. Versioned manifest v2, scoped result
v4 and impact report v2 are in the paired docset.

G05A authored the implementation/ExUnit tests, **not** real engine acceptance.
The portable property differs from historical synthetic-retry G03 obligation,
and Lynx axiom audit and Veil InfoView outcome capture remain B qualification
gaps. G05B must run actual backend positive/negative and CLI suites using the
pinned local toolchain before reporting a checker result accepted.
