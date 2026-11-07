<p align="center">
  <img src="assets/grand_cli.svg" alt="Grand CLI" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand CLI

Orchestration and Mix tasks for Grand normative requirements and assurance pipelines.

## Contents

- [Overview](#overview)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Documentation](#documentation)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)

## Overview

Part of [Grand](https://github.com/nshkrdotcom/grand), providing the operator interface and `mix grand` task suite:

- `mix grand import`: Ingest BeamCompass snapshot JSON.
- `mix grand link`: Link requirement JSON to snapshot fact references.
- `mix grand approve`: Explicitly approve requirements with human attestation.
- `mix grand inspect`: Query requirements or facts from the immutable store.
- `mix grand export`: Export unrun evidence bundles to stdout or output files.

## Getting started

Requires Elixir 1.20.5 / OTP 29.1.2. From this application's directory:

```sh
mix deps.get
mix compile
mix test
```

## Usage

```sh
mix grand import ../../fixtures/beamcompass_v1.json \
  --project synthetic-ledger --store ../../grand-store

mix grand link ../../fixtures/requirement_pending.json \
  --project synthetic-ledger --snapshot synthetic-hold-snapshot-001 \
  --fact synthetic-fact-void-intent-001 --actor human:submitter \
  --store ../../grand-store

mix grand approve synthetic-REQ-void-confirmation \
  --actor human:reviewer --ack-human --store ../../grand-store

mix grand inspect requirement synthetic-REQ-void-confirmation \
  --store ../../grand-store

mix grand export synthetic-REQ-void-confirmation \
  --project synthetic-ledger --store ../../grand-store --out bundle.json
```

## Documentation

```sh
mix docs
```

The documentation menu includes this guide, API modules, Mix tasks, the [changelog](CHANGELOG.md), and the [MIT license](LICENSE).

## Packaging

Build the Hex archive with:

```sh
MIX_ENV=prod mix hex.build
```

Development uses sibling poncho dependencies. Standalone installs resolve dependencies from Hex.

## License

MIT — Copyright (c) 2026 nshkrdotcom. See [LICENSE](LICENSE).

### Versioned v2 CLI (G02B locally verified)

`mix grand import SNAPSHOT --project ID --schema 2 --store DIR` accepts the
pinned source-only v2 JSON. `inspect snapshot` supports `--schema 2`;
`inspect entity|relation|evidence PROJECT SNAPSHOT OBJECT_ID --schema 2`
returns a full exact ref and object. `query PROJECT SNAPSHOT --focus ENTITY_ID
--lens neighbors|connected|effects --budget N [--preserve entity=ID]
[--preserve relation=ID] --store DIR [--out NEW_FILE]` returns a local bounded
slice and preserved/omitted/unresolved receipt; it does not call an upstream
projection. `export snapshot PROJECT SNAPSHOT --schema 2 --store DIR --out
NEW_FILE` writes a validated portable upstream snapshot without overwriting.
Legacy v1 commands (`link`, `approve`, `export REQUIREMENT_ID`) remain unchanged
and do not accept a forged v2 fact. G02B independently passed the actual-export subprocess regressions.

## G03A additive implementation (runtime UNRUN)

Explicit `mix grand g03` JSON-only lifecycle/motif subcommands and a real Mix subprocess end-to-end test; legacy CLI preserved.

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
bounded local process boundary, not a hardened sandbox. The authoring host had
no Elixir/Mix/Lean/TLC JAR; ExUnit and actual engines remain unrun until G04B.
