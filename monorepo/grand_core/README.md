<p align="center">

  <img src="assets/grand_core.svg" alt="Grand Core" width="200" />
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/grand"><img src="https://img.shields.io/badge/GitHub-grand-181717?logo=github" alt="GitHub repository" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
</p>

# Grand Core

Deterministic JSON codec, immutable content-addressed storage, and foundational records for Grand.

## Contents

- [Overview](#overview)
- [Getting started](#getting-started)
- [Usage](#usage)
- [Documentation](#documentation)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)

## Overview

Part of [Grand](https://github.com/nshkrdotcom/grand), the normative requirement and assurance platform for Elixir/OTP systems. `grand_core` provides:

- Pure-Elixir deterministic JSON encoding and strict validation parsing without atom creation.
- Canonical schema validation for `behavior_ref`, `requirement`, `approval_event`, `obligation`, `assumption`, `verification_result`, and `evidence_bundle`.
- Immutable append-only disk storage (`Grand.Core.Store`) using fsync and atomic hard-links.

## Getting started

Requires Elixir 1.20.5 / OTP 29.1.2. From this application's directory:

```sh
mix deps.get
mix compile
mix test
```

## Usage

```elixir
alias Grand.Core
alias Grand.Core.Store

# Validate and encode canonical JSON
{:ok, json} = Core.encode(%{"schema_version" => "1", "status" => "draft"})
{:ok, doc} = Core.decode(json, "requirement")

# Atomic, immutable persistence
store_root = "/path/to/grand-store"
{:ok, path} = Store.put(store_root, "requirements", "REQ-001", doc)
{:ok, stored} = Store.get(store_root, "requirements", "REQ-001")
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

## License

MIT — Copyright (c) 2026 nshkrdotcom. See [LICENSE](LICENSE).
