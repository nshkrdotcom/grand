<p align="center">
  <img src="assets/grand_beamcompass.svg" alt="Grand BeamCompass" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand BeamCompass

Bounded, read-only BeamCompass v1/v2 export adapter and BehaviorRef resolution for Grand.

## Contents

- [Overview](#overview)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Documentation](#documentation)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)

## Overview

Part of [Grand](https://github.com/nshkrdotcom/grand), consuming versioned portable JSON exports produced by [BeamCompass](https://github.com/nshkrdotcom/beamcompass).

- Imports v1 snapshot exports and persists them immutably.
- Resolves exact `BehaviorRef` objects to syntactic facts, candidate effects, and source anchors (`start_line`, `start_col`).
- Enforces strict safety boundaries: target code and AST paths are read as untrusted data and never executed.

## Getting started

Requires Elixir >= 1.15. From this application's directory:

```sh
mix deps.get
mix compile
mix test
```

## Usage

```elixir
alias Grand.BeamCompass

store_root = "/path/to/grand-store"

# Ingest a BeamCompass snapshot JSON
{:ok, snapshot} = BeamCompass.import_file(store_root, "my_project", "path/to/beamcompass_v1.json")

# Resolve a BehaviorRef
ref = %{
  "provider" => "beamcompass",
  "project_id" => "my_project",
  "snapshot_id" => snapshot["snapshot_id"],
  "fact_id" => "fact-001"
}

{:ok, fact} = BeamCompass.resolve(snapshot, ref)
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
