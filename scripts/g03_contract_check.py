#!/usr/bin/env python3
"""G03 portable JSON/contract negatives; never substitutes for Elixir runtime.

Accepts --docset to validate new Draft 2020-12 schemas against full examples.
Never reads, compiles or executes imported source anchor files or target Mix.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from g02_contract_check import validate as validate_v2

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'fixtures'

def canonical(data):
    return json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(',', ':')).encode()

def expect(value, reason):
    if not value:
        raise AssertionError(reason)

def load(path):
    return json.loads(path.read_bytes())

def refs(snapshot, value):
    for ref in value:
        expect(ref['schema_version'] == 2 and ref['upstream_schema_version'] == 2, 'v2-only synthetic fixture')
        expect(ref['provider'] == 'beamcompass' and ref['project_id'] == snapshot['project_id'] and
               ref['snapshot_id'] == snapshot['snapshot_id'], 'exact snapshot scope mismatch')
        kind = ref['object_kind']
        expect(kind in ('entity', 'relation', 'evidence'), 'typed ref kind')
        collection = {'entity':'entities','relation':'relations','evidence':'evidence'}[kind]
        obj = next((o for o in snapshot[collection] if o['id'] == ref['object_id']), None)
        expect(obj is not None, 'dangling source ref')
        expect(ref['evidence_ids'] == ([obj['id']] if kind == 'evidence' else obj['evidence_ids']),
               'mismatched exact evidence set')
        if kind == 'relation':
            expect(ref.get('resolution') == obj['resolution'], 'mismatched exact resolution')
        if kind != 'evidence':
            expect(ref.get('epistemic_status') == obj['epistemic_status'], 'mismatched epistemic scope')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--docset', type=Path)
    args = parser.parse_args()
    snapshot = load(FIXTURES / 'g03_synthetic_retry_v2.json')
    schema = load(FIXTURES / 'upstream/beamcompass-p02b/snapshot-v2.schema.json')
    validate_v2(snapshot, schema)
    expect(snapshot['project_id'] == 'fixture:synthetic-retry', 'synthetic project identity')
    expect(any('SYNTHETIC' in limit for limit in snapshot['limitations']), 'synthetic provenance explicit')
    source = next((entity for entity in snapshot['entities']
                   if entity['kind'] == 'function' and 'retry' in entity['label'].lower()), None)
    expect(source is not None, 'positive retry label')
    expect(any(r['kind'] == 'performs_effect' and r['source_id'] == source['id'] and
               r['resolution'] == 'resolved' and
               any(e['id'] == r['target_id'] and e['kind'] == 'effect' for e in snapshot['entities'])
               for r in snapshot['relations']), 'typed effect relationship')
    source_negative = load(FIXTURES / 'upstream/beamcompass-p02b/a.json')
    expect(not any('retry' in e['label'].lower() and e['kind'] == 'function' for e in source_negative['entities']),
           'pinned actual export is not falsely motif-positive')
    for kind in ('candidate','requirement','assumption','obligation'):
        value = load(FIXTURES / f'g03_{kind}_input.json')
        expect(value['scope'] == {'project_id':snapshot['project_id'],
               'snapshot_id':snapshot['snapshot_id'], 'upstream_schema_version':2}, 'input scope')
        for field in ('source_refs','behavior_refs'):
            if field in value: refs(snapshot, value[field])
        if kind == 'assumption':
            for ev in value['evidence']: refs(snapshot, ev['source_refs'])
        if kind == 'obligation':
            refs(snapshot, value['witness']['source_refs'])
            expect(value['requirement'] == {'id':'g03-confirm-once','revision':3}, 'pinned approved revision')
            expect(value['witness']['status'] == 'missing' and
                   {'witness_missing','contradiction','vacuity'} <=
                   {c['kind'] for c in value['precondition_challenges']}, 'explicit witness challenge')
    bad = copy.deepcopy(snapshot)
    bad['entities'][0]['label'] = 'unproven changed source'
    expect(hashlib.sha256(canonical({k:v for k,v in bad.items() if k!='snapshot_id'})).hexdigest()
           != bad['snapshot_id'], 'modified source without changed digest must be rejected')
    if args.docset:
        schema_dir = args.docset / 'contracts/schemas'
        registry = Registry().with_resources((schema['$id'], Resource.from_contents(schema))
            for f in schema_dir.glob('*.schema.json')
            for schema in [load(f)])
        cases = {'candidate':'candidate-v2','requirement':'requirement-v2',
                 'assumption':'assumption-v2','obligation':'obligation-v2'}
        for kind,name in cases.items():
            sample = load(args.docset / 'contracts/examples' / f'g03-{kind}-v2.json')
            schema = load(schema_dir/(name+'.schema.json'))
            validator = Draft202012Validator(schema, registry=registry)
            validator.validate(sample)
            faulty = {**sample, 'status':'proved'}
            expect(not validator.is_valid(faulty), 'illegal status must fail: '+kind)
        print('PASS: 4 G03 Draft 2020-12 schemas + invalid statuses')
    print('PASS: synthetic v2 graph/source-only digest, typed retry/effect link, exact fixture refs,')
    print('      pinned upstream negative, witness challenges, untrusted-label provenance and rehash control')
    print('NOTE: NOT an Elixir compile, source runtime, model checker or proof')

if __name__ == '__main__': main()
