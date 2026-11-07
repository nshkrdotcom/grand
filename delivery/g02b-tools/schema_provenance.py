import json,hashlib
from pathlib import Path
from jsonschema import Draft202012Validator
r=Path('/home/home/p/g/n/grand');d=Path('/home/home/p/g/n/brainstorms/nshkrdotcom/docs/20261106/grand/grand-docset')
count=0
for p in (d/'contracts').rglob('*.schema.json'):
 Draft202012Validator.check_schema(json.loads(p.read_text()));count+=1
p=d/'contracts/upstream/beamcompass-p02b'; prov=json.loads((p/'provenance.json').read_text());n=0
for rec in prov['files']:
 q=p/rec['path']
 if q.exists():
  raw=q.read_bytes();assert hashlib.sha256(raw).hexdigest()==rec['sha256'];assert len(raw)==rec['bytes'];n+=1
for name in ['a.json','mutated.json','exact-0.json','exact-1.json']:
 assert (p/name).read_bytes()==(r/'fixtures/upstream/beamcompass-p02b'/name).read_bytes()
for name in ['exact-0.json','exact-1.json']:
 Draft202012Validator(json.loads((p/'behavior-reference.schema.json').read_text())).validate(json.loads((p/name).read_text()))
print(f'PASS: {count} Draft 2020-12 schemas; {n} authoritative pinned file hashes; 4 code/doc fixture byte matches; 2 upstream exact references')
