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

## Typed P02B consumer (G02B locally verified)

`Grand.BeamCompass` dispatches only on a declared JSON `schema_version`:
separate `V1` and `V2` implementations. Version 2 requires caller-supplied
`project_id` matching the export; checks snapshot and manifest digests, source
mode, typed effect targets, evidence DAG, canonical ordering, and safe paths;
returns a versioned immutable envelope. `reference(snapshot, "entity" |
"relation" | "evidence", id)` constructs an exact Grand v2 ref and
`resolve/2` checks scope, complete evidence sets and optional status/resolution.
Old two-argument v1 references and v1 store paths are unchanged. `load/3` is
backwards compatible, `load/4` selects version explicitly. Source-only facts
are neither runtime observations nor execution/causal guarantees.

`Grand.BeamCompass.query(snapshot, focus: entity_id, budget: 1..256,
lens: "neighbors" | "connected" | "effects", preserve: [typed_refs])`
reads only a valid stored v2 envelope, returns typed objects, evidence closure
and explicit preserved/omitted/unresolved receipts. No BeamCompass P03 API is
called. `preserve` entries are maps with `object_kind` entity/relation and
`object_id`; requiring a relation also requires both known endpoints. The
budget counts entities and relations, not the separately reported evidence and
receipts. It is never a proof or semantic-completeness assertion.

G02B passed the ExUnit suite on the bundled **actual exported** P02B JSON
under `fixtures/upstream/beamcompass-p02b`. G02A authoring was runtime UNRUN;
see root `delivery/G02B-VALIDATION.md` for independent B acceptance.
