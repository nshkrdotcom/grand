#!/usr/bin/env python3
"""G05 source-only/Lynx/Veil portable contracts. Static checks, NOT engine proof."""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'fixtures'


def read(path: Path):
    return json.loads(path.read_text())


def need(ok, why):
    if not ok:
        raise AssertionError(why)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--docset', type=Path, required=True)
    args = parser.parse_args()
    contracts = args.docset / 'contracts'
    schemas = contracts / 'schemas'
    validator = {}
    for key, filename in {
        'manifest': 'g05-manifest.schema.json',
        'result': 'verification-result-v4.schema.json',
        'impact': 'impact-report-v2.schema.json',
        'tlc': 'g04-manifest.schema.json',
    }.items():
        schema = read(schemas / filename)
        Draft202012Validator.check_schema(schema)
        validator[key] = Draft202012Validator(schema)
    obligation = read(FIXTURES / 'g03_obligation_input.json')
    for kind in ('lynx-good', 'lynx-bad', 'veil-safe', 'veil-bad'):
        manifest = read(FIXTURES / 'g05' / f'{kind}-manifest.json')
        validator['manifest'].validate(manifest)
        need(manifest['schema_version'] == 2, f'{kind}: manifest v2')
        for field in ('scope', 'source_refs', 'assumptions', 'requirement'):
            need(manifest[field] == obligation[field], f'{kind}: G03 {field} mismatch')
        need(manifest['obligation_id'] == obligation['id'], f'{kind}: G03 obligation mismatch')
        changed = copy.deepcopy(manifest)
        changed['adapter'] = 'sh'
        need(not validator['manifest'].is_valid(changed), 'unallowlisted adapter schema accepted')
        changed = copy.deepcopy(manifest)
        changed['allow_law_code'] = True
        need(not validator['manifest'].is_valid(changed), 'authorization embedded in manifest')
        changed = copy.deepcopy(manifest)
        changed['assumptions'][0]['revision'] = 'latest'
        need(not validator['manifest'].is_valid(changed), 'invalid assumption revision accepted')
        changed = copy.deepcopy(manifest)
        changed['model' if kind.startswith('lynx') else 'law'] = {}
        need(not validator['manifest'].is_valid(changed), 'mixed law/model adapter accepted')

    for kind in ('tlc-safe', 'tlc-bad'):
        manifest = read(FIXTURES / 'g05' / f'{kind}-manifest.json')
        validator['tlc'].validate(manifest)
        need(manifest['source_refs'] == obligation['source_refs'], f'{kind} G03 source')
        tla = (FIXTURES / 'g05' / manifest['model']['file']).read_text()
        need('---- MODULE Model ----' in tla and 'NoPrematureRelease ==' in tla,
             'TLC translation property missing')
    safe = (FIXTURES / 'g05/veil/Safe.lean').read_text()
    bad = (FIXTURES / 'g05/veil/Bad.lean').read_text()
    for source in (safe, bad):
        for term in ('public import Veil', 'veil module HoldVoid',
                     'safety [no_premature_release]', '#gen_spec',
                     '#model_check interpreted {} {} (sequential := true)'):
            need(term in source, f'Veil model missing pinned DSL command {term}')
    need('released := false' in safe.split('action request_void', 1)[1],
         'safe action does not preserve held capacity')
    need('released := true' in bad.split('action request_void', 1)[1],
         'negative model does not release prematurely')
    source = (FIXTURES / 'g05/lynx/Source.ex').read_text()
    mutant = (FIXTURES / 'g05/lynx/SourcePremature.ex').read_text()
    support = (FIXTURES / 'g05/lynx/Support.ex').read_text()
    law = (FIXTURES / 'g05/lynx/Law.ex').read_text()
    need('Support.hold_pending(free)' in source and 'Support.hold_pending(free) + 1' in mutant,
         'source-linked Hold Ledger positive and negative dependency mismatch')
    need('def hold_pending(free)' in support and 'use Lynx.Laws' in law and
         'law capacity_held_before_confirmation(free)' in law and
         'Elixir.Grand.HoldLedger.Support' in law and '~LEAN' in law,
         'no genuine translated-source Lynx law package')
    need('theorem grand_demo_reflexivity' not in law, 'old synthetic proof leaked')
    for kind in ('before', 'premature', 'line-shift', 'effect-omitted',
                 'v2-before', 'v2-line-shift'):
        data = read(FIXTURES / 'g05/impact' / f'{kind}.json')
        need(data['schema_version'] in (1, 2), 'unsupported source version fixture')
    links = read(FIXTURES / 'g05/impact/links.json')
    need(len(links['links']) > 0, 'impact has no reverse dependency paths')
    for name, schema in [('verification_result_v4', 'result'), ('impact_report_v2', 'impact')]:
        instance = read(contracts / 'examples' / f'{name}.json')
        validator[schema].validate(instance)
        changed = copy.deepcopy(instance)
        changed['status' if schema == 'result' else 'evidence_status'] = 'verified'
        need(not validator[schema].is_valid(changed), 'verified boolean-style verdict accepted')
        changed = copy.deepcopy(instance)
        changed['schema_version'] = 3
        need(not validator[schema].is_valid(changed), 'wrong result/report version accepted')

    print('PASS: G05 six backend fixtures (static), translated-source law package,')
    print('      original exact G03 bindings, source-only v1/v2 impact fixtures,')
    print('      versioned manifest/result/impact Draft 2020-12 schemas and negatives')
    print('NOTE: no Lynx/Lean/Veil/TLC runtime acceptance or proof is implied')


if __name__ == '__main__':
    main()
