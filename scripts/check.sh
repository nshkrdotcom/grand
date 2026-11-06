#!/bin/sh
# Run from any directory. Execute each independent Mix app without a root umbrella.
# This script stops at the first failing gate and never reports absent tools as PASS.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for app in grand_core grand_beamcompass grand_assurance grand_cli; do
  printf '\n== %s ==\n' "$app"
  cd "$repo/monorepo/$app"
  mix deps.get --check-locked
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix test
  mix credo --strict
  mix dialyzer
done
