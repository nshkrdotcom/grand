#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if ! command -v uv >/dev/null 2>&1; then
  echo 'Missing uv. Install uv, expose it on PATH, and rerun scripts/bootstrap.sh. No system installer is run.' >&2
  exit 1
fi
cd "$root"
uv sync --locked
exec uv run --locked python scripts/provision.py "$@"
