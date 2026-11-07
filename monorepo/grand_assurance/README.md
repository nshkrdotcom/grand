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
