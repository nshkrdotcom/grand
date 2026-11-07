import json,subprocess,tempfile,pathlib
r=pathlib.Path('/home/home/p/g/n/grand');logs=r/'delivery/g02b-logs';results=[]
with tempfile.TemporaryDirectory(prefix='grand-g02b-') as temp:
 t=pathlib.Path(temp)
 def run(args,ok=True):
  p=subprocess.run(['mix','grand']+args,cwd=r/'monorepo/grand_cli',capture_output=True,text=True)
  n=len(results)+1;name=f'cli-{n:02}.log';(logs/name).write_text(p.stdout+p.stderr)
  results.append(dict(command=['mix','grand']+args,exit_code=p.returncode,expected='success' if ok else 'rejection',log='delivery/g02b-logs/'+name))
  assert (p.returncode==0)==ok,(args,p.stdout,p.stderr)
  if ok:return json.loads(p.stdout.strip().splitlines()[-1])
 for name in ['a.json','mutated.json']:
  source=r/'fixtures/upstream/beamcompass-p02b'/name;s=json.loads(source.read_text());sid=s['snapshot_id'];store=str(t/name);common=['--store',store,'--schema','2'];project='fixture:ledger'
  run(['import',str(source),'--project',project]+common)
  run(['inspect','snapshot',project,sid]+common)
  for kind,collection in [('entity','entities'),('relation','relations'),('evidence','evidence')]:run(['inspect',kind,project,sid,s[collection][0]['id']]+common)
  rel=next(x for x in s['relations'] if x['resolution']=='resolved');args=['query',project,sid,'--focus',rel['source_id'],'--preserve','relation='+rel['id']]+common
  q=run(args+['--budget','3']);assert q['receipt']['preserved'] and q['receipt']['omitted'] and q['receipt']['unresolved']
  run(args+['--budget','1'],False)
  out=str(t/(name+'-portable.json'));run(['export','snapshot',project,sid,'--out',out]+common)
  run(['import',out,'--project',project,'--schema','2','--store',store+'-roundtrip'])
  run(['export','snapshot',project,sid,'--out',out]+common,False)
  run(['import',str(source),'--project','foreign']+common,False)
  run(['import',str(source),'--project',project,'--schema','1','--store',store],False)
  run(['import',str(source),'--project',project,'--no-such-flag','yes']+common,False)
(logs/'cli-results.json').write_text(json.dumps(results,indent=2)+'\n');print('PASS:',len(results),'real mix grand subprocesses')
