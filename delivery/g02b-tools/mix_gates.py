import subprocess,json,pathlib,time,datetime
root=pathlib.Path('/home/home/p/g/n/grand'); logs=root/'delivery/g02b-logs';logs.mkdir(exist_ok=True)
results=[]
for app in ['grand_core','grand_beamcompass','grand_assurance','grand_cli']:
 for gate in ['deps.get --check-locked','format --check-formatted','compile --warnings-as-errors','test','credo --strict','dialyzer']:
  name=app+'-'+gate.split()[0];p=logs/(name+'.log');start=time.time(); head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(); version=subprocess.check_output(['elixir','--version'],cwd=root,text=True).strip()
  with p.open('w') as out:r=subprocess.run(['mix']+gate.split(),cwd=root/'monorepo'/app,stdout=out,stderr=subprocess.STDOUT)
  results.append(dict(project=app,command='mix '+gate,exit_code=r.returncode,log=str(p.relative_to(root)),seconds=round(time.time()-start,2),checked_code_head=head,toolchain=version,started_utc=datetime.datetime.fromtimestamp(start,datetime.timezone.utc).isoformat(),cwd=str(root/'monorepo'/app)))
  (logs/'results.json').write_text(json.dumps(results,indent=2)+'\n');print(name,r.returncode,flush=True)
