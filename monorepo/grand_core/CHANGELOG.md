# Changelog

## 0.1.0 — 2026-11-06 (Delivery GRAND-G01A-20261106-A)

- Initial release of Grand Core foundational primitives and storage engine.
- Pure-Elixir deterministic JSON encoder and strict parser (no atoms, strict depth/node bounds).
- Deterministic schema validation for canonical record types: `behavior_ref`, `requirement`, `approval_event`, `obligation`, `assumption`, `verification_result`, and `evidence_bundle`.
- Append-only immutable file store (`Grand.Core.Store`) with atomic fsync-and-hard-link persistence and duplicate conflict rejection.
