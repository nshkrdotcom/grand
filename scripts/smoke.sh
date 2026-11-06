#!/bin/sh
# Operators: explicitly self-attested fixture approval only, not authenticated.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
store=${1:-"$repo/grand-store"}
cd "$repo/monorepo/grand_cli"
mix grand import "$repo/fixtures/beamcompass_v1.json" --project synthetic-ledger --store "$store"
mix grand link "$repo/fixtures/requirement_pending.json" --project synthetic-ledger \
  --snapshot synthetic-hold-snapshot-001 --fact synthetic-fact-void-intent-001 \
  --actor human:fixture-submitter --store "$store"
mix grand approve synthetic-REQ-void-confirmation --actor human:fixture-reviewer \
  --ack-human --store "$store"
mix grand inspect requirement synthetic-REQ-void-confirmation --store "$store"
mix grand export synthetic-REQ-void-confirmation --project synthetic-ledger --store "$store"
