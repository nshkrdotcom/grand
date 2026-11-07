#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
exec uv run --project "$root" --locked python "$root/scripts/local_run.py" "$@"
