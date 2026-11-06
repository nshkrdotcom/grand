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

Requires Elixir >= 1.15. From this application's directory:

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
