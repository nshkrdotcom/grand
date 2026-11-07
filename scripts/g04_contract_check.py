#!/usr/bin/env python3
"""G04 portable fixture and input/result schema checks, not checker acceptance.

No model, law, or target source is executed by this Python script.
"""
import argparse
import copy
import json
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'fixtures'


def read(path):
    return json.loads(path.read_text())


def must(value, message):
    if not value:
        raise AssertionError(message)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--docset', type=Path, required=True)
    ns = ap.parse_args()
    schemas = ns.docset / 'contracts/schemas'
    input_schema = read(schemas / 'g04-manifest.schema.json')
    result_schema = read(schemas / 'verification-result-v3.schema.json')
    Draft202012Validator.check_schema(input_schema)
    Draft202012Validator.check_schema(result_schema)
    check_input = Draft202012Validator(input_schema)
    check_result = Draft202012Validator(result_schema)
    obligation = read(FIXTURES / 'g03_obligation_input.json')
    for name in ('lean', 'tlc', 'tlc-bad'):
        value = read(FIXTURES / 'g04' / f'{name}-manifest.json')
        check_input.validate(value)
        for field in ('requirement', 'assumptions', 'scope', 'source_refs'):
            must(value[field] == obligation[field], 'G03 binding mismatch: ' + field)
        must(value['obligation_id'] == obligation['id'], 'obligation ID mismatch')
        if name == 'lean':
            law = (FIXTURES / 'g04' / value['law']['file']).read_text()
            must('theorem grand_demo_reflexivity' in law and '#print axioms grand_demo_reflexivity' in law,
                 'positive Lean fixture not source-linked to named law')
            bad_law = (FIXTURES / 'g04/InvalidLaw.lean').read_text()
            must('0 = 1' in bad_law and 'rfl' in bad_law, 'invalid Lean law mutation missing')
        else:
            model = (FIXTURES / 'g04' / value['model']['file']).read_text()
            cfg = (FIXTURES / 'g04' / value['model']['config_file']).read_text()
            must('---- MODULE Model ----' in model and 'Spec ==' in model, 'not a model module')
            must('SPECIFICATION Spec' in cfg and 'CONSTANT Limit = 2' in cfg and
                 'INVARIANT Safe' in cfg, 'model config missing bounds or invariant')
            must(('Safe == count <= Limit' in model) == (name == 'tlc'), 'safe/bad model mismatch')
        forged = copy.deepcopy(value)
        forged['adapter'] = 'attacker-shell'
        must(not check_input.is_valid(forged), 'unknown executable accepted')
        forged = copy.deepcopy(value)
        forged['requirement']['revision'] = 'forged'
        must(not check_input.is_valid(forged), 'invalid revision accepted')
        forged = copy.deepcopy(value)
        forged['model' if name == 'lean' else 'law'] = {}
        must(not check_input.is_valid(forged), 'mixed law/model accepted')

    example = read(ns.docset / 'contracts/examples/verification_result_v3.json')
    check_result.validate(example)
    changed = copy.deepcopy(example)
    changed['status'] = 'verified'
    must(not check_result.is_valid(changed), 'binary verified status accepted')
    changed = copy.deepcopy(example)
    changed['runner']['execution_requested'] = 'yes'
    must(not check_result.is_valid(changed), 'nonboolean policy accepted')
    print('PASS: 3 G04 source-linked synthetic fixtures, real G03 obligation bindings,')
    print('      Draft 2020-12 input/result schemas, forbidden adapter/payload/status negatives')
    print('NOTE: no Elixir, Lean or TLC runtime checking is implied')


if __name__ == '__main__':
    main()
