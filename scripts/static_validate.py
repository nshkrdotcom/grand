#!/usr/bin/env python3
"""G01A static-only checks (not a substitute for Elixir/Mix execution)."""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APPS = ["grand_core", "grand_beamcompass", "grand_assurance", "grand_cli"]


def check() -> list[str]:
    errors: list[str] = []
    if (ROOT / "mix.exs").exists():
        errors.append("unexpected root mix.exs")
    if (ROOT / "monorepo" / "beamcompass").exists():
        errors.append("unexpected imported BeamCompass implementation")
    for app in APPS:
        path = ROOT / "monorepo" / app
        for required in ("mix.exs", "mix.lock", ".formatter.exs", "test/test_helper.exs"):
            if not (path / required).is_file():
                errors.append(f"missing {app}/{required}")
        source = (path / "mix.exs").read_text()
        if "apps_path:" in source:
            errors.append(f"umbrella apps_path in {app}")
        if re.search(r"\{\s*:beamcompass\b", source):
            errors.append(f"BeamCompass implementation dependency in {app}")
    core = ROOT / "monorepo/grand_core/lib"
    forbidden = ("Code.eval_", "binary_to_term(", "String.to_atom(", "Mix.Project.in_project(")
    for path in core.rglob("*.ex"):
        source = path.read_text()
        for token in forbidden:
            if token in source:
                errors.append(f"forbidden core token {token} in {path.name}")
    for filename in ("beamcompass_v1", "requirement_pending", "invalid_version",
                     "duplicate_fact", "missing_anchor", "path_traversal"):
        path = ROOT / "fixtures" / f"{filename}.json"
        try:
            json.loads(path.read_text())
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid fixture {path}: {exc}")
    if len(list(ROOT.glob("monorepo/*/mix.exs"))) != len(APPS):
        errors.append("unexpected Mix application count")
    if not (ROOT / "monorepo/grand_cli/test/cli_integration_test.exs").is_file():
        errors.append("missing CLI subprocess integration test")
    return errors


if __name__ == "__main__":
    issues = check()
    if issues:
        for issue in issues:
            print("FAIL:", issue)
        sys.exit(1)
    print("PASS: G01A static layout, forbidden-token and JSON fixture checks")
    print("NOTE: Elixir parsing/compile/tests/Credo/Dialyzer were NOT executed")
