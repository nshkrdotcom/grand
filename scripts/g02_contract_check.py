#!/usr/bin/env python3
"""Independent offline P02B fixture/contract checks; NOT Grand Elixir runtime tests.

No BeamCompass code or target source is read or executed. jsonschema is a
local-development validation dependency, not a Grand Mix dependency.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

ROOT = Path(__file__).resolve().parents[1]
PINNED = ROOT / "fixtures/upstream/beamcompass-p02b"


def canonical(obj: dict) -> bytes:
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def load(name: str) -> dict:
    return json.loads((PINNED / name).read_bytes())


def expect(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def sorted_unique(values: list) -> bool:
    return values == sorted(values) and len(values) == len(set(values))


def acyclic(edges: dict[str, list[str]]) -> bool:
    done = set()

    def visit(n, path):
        if n in path:
            return False
        if n in done:
            return True
        if not all(visit(v, path | {n}) for v in edges[n]):
            return False
        done.add(n)
        return True

    return all(visit(n, set()) for n in edges)


def validate(snapshot: dict, schema: dict) -> None:
    Draft202012Validator(schema).validate(snapshot)
    expect(snapshot["snapshot_id"] == digest(canonical({k: v for k, v in snapshot.items() if k != "snapshot_id"})), "bad snapshot digest")
    for collection in ("entities", "relations", "evidence"):
        expect(sorted_unique([e["id"] for e in snapshot[collection]]), "unordered or duplicate " + collection)
    expect(sorted_unique([p["id"] for p in snapshot["manifest"]["providers"]]), "provider order")
    expect(sorted_unique(snapshot["limitations"]), "limitation order")
    expect(snapshot["issues"] == sorted(snapshot["issues"], key=lambda x: (x["code"], x["message"], x["evidence_ids"])), "issue order")
    providers = {p["id"] for p in snapshot["manifest"]["providers"]}
    evidence = {e["id"]: e for e in snapshot["evidence"]}
    entities = {e["id"]: e for e in snapshot["entities"]}
    expect(all(p["mode"] == "source" for p in snapshot["manifest"]["providers"]), "unsupported provider mode")
    expect(acyclic({e["id"]: e["input_evidence_ids"] for e in snapshot["evidence"]}), "evidence cycle")
    for e in snapshot["evidence"]:
        expect(e["mode"] == "source" and e["provider_id"] in providers, "evidence provider/mode")
        expect(set(e["input_evidence_ids"]) <= evidence.keys(), "dangling derivation")
        a = e["anchor"]
        path = a["path"]
        expect(not path.startswith("/") and "\\" not in path and "\x00" not in path and not (len(path) > 1 and path[1] == ":") and all(p not in ("", ".", "..") for p in path.split("/")), "unsafe path")
        start = (a["start_line"], a["start_column"])
        end = (a["end_line"], a["end_column"])
        expect(end == (None, None) or (None not in end and end >= start), "bad range")
        expect(sorted_unique(e["input_evidence_ids"]), "duplicate derivation")
    for obj in snapshot["entities"] + snapshot["relations"]:
        expect(sorted_unique(obj["evidence_ids"]) and bool(obj["evidence_ids"]), "object evidence ordering")
        expect(set(obj["evidence_ids"]) <= evidence.keys(), "missing evidence")
        expect(obj["epistemic_status"] in ("sourced", "derived", "proposed", "unresolved"), "observed assertion")
    for entity in snapshot["entities"]:
        expect(sorted_unique(entity["limitations"]), "entity limitations")
    for relation in snapshot["relations"]:
        source, target = entities.get(relation["source_id"]), entities.get(relation["target_id"])
        expect(source is not None, "missing relation source")
        if relation["resolution"] == "resolved":
            expect(target is not None, "missing resolved target")
        if relation["resolution"] == "possible" and relation["target_id"] is not None:
            expect(target is not None, "missing possible candidate")
        if relation["resolution"] == "unresolved":
            expect(relation["target_id"] is None and relation["epistemic_status"] == "unresolved", "false certainty")
        if relation["kind"] in ("performs_effect", "describes_effect"):
            expect(source["kind"] in ("function", "actor", "behavior", "transition"), "wrong performer source type")
            expected = "effect" if relation["kind"] == "performs_effect" else "effect_intent"
            expect(target is None or target["kind"] == expected, "wrong effect endpoint type")
    for issue in snapshot["issues"]:
        expect(set(issue["evidence_ids"]) <= evidence.keys(), "dangling issue evidence")


def main() -> None:
    provenance = load("provenance.json")
    for record in provenance["files"]:
        if (PINNED / record["path"]).exists():
            data = (PINNED / record["path"]).read_bytes()
            expect(digest(data) == record["sha256"] and len(data) == record["bytes"], "fixture hash " + record["path"])
    schema = load("snapshot-v2.schema.json")
    Draft202012Validator.check_schema(schema)
    real = [load(name) for name in ("a.json", "mutated.json")]
    for snapshot in real:
        validate(snapshot, schema)
    refs = [load(name) for name in ("exact-0.json", "exact-1.json")]
    objects = {e["id"]: e for e in real[0]["entities"]}
    for ref in refs:
        expect(ref["snapshot_id"] == real[0]["snapshot_id"] and ref["project_id"] == real[0]["project_id"], "exact ref scope")
        expect(ref["evidence_ids"] == objects[ref["object_id"]]["evidence_ids"], "exact ref evidence")
    a = real[0]
    attacks = []
    import copy
    x = copy.deepcopy(a)
    x["manifest"]["providers"][0]["mode"] = "compiled"
    attacks.append(x)
    x = copy.deepcopy(a)
    x["evidence"][0]["input_evidence_ids"] = [x["evidence"][0]["id"]]
    attacks.append(x)
    x = copy.deepcopy(a)
    x["evidence"][0]["anchor"]["path"] = "../secret"
    attacks.append(x)
    x = copy.deepcopy(a)
    x["entities"][0]["evidence_ids"] = ["missing"]
    attacks.append(x)
    x = copy.deepcopy(a)
    effect_intent = next(e for e in x["entities"] if e["kind"] == "effect_intent")
    effect_rel = next(r for r in x["relations"] if r["kind"] == "performs_effect" and r["resolution"] == "resolved")
    effect_rel["target_id"] = effect_intent["id"]
    attacks.append(x)
    x = copy.deepcopy(a)
    x["entities"].reverse()
    attacks.append(x)
    for attack in attacks:
        attack["snapshot_id"] = digest(canonical({k: v for k, v in attack.items() if k != "snapshot_id"}))
        try:
            validate(attack, schema)
        except (AssertionError, ValidationError):
            pass
        else:
            raise AssertionError("hostile rehashed fixture was accepted")
    print("PASS: pinned P02B byte hashes, two actual v2 exports, exact refs, 6 rehashed hostile controls")
    print("SCOPE: independent Python contract only; Grand Mix runtime UNRUN")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("FAIL:", exc, file=sys.stderr)
        sys.exit(1)
