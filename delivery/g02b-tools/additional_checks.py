import subprocess,json,pathlib,tempfile
r=pathlib.Path('/home/home/p/g/n/grand');d=pathlib.Path('/home/home/p/g/n/brainstorms/nshkrdotcom/docs/20261106/grand/grand-docset');logs=r/'delivery/g02b-logs'
commands=[(r,['python3','scripts/static_validate.py'],'static'),(r,['python3','scripts/g02_contract_check.py'],'contract'),(r,['bash','scripts/smoke.sh',tempfile.mkdtemp(prefix='grand-g02b-smoke-')],'smoke'),(d,['python3','tools/docsetctl.py','check'],'docset'),(d,['python3','-m','unittest','discover','-s','tools','-p','test_*.py','-v'],'docset-tests'),(r,['elixir','--version'],'elixir-version'),(r,['mix','--version'],'mix-version'),(r,['python3','--version'],'python-version')]
results=[]
for cwd,cmd,name in commands:
 with (logs/(name+'.log')).open('w') as out:p=subprocess.run(cmd,cwd=cwd,stdout=out,stderr=subprocess.STDOUT)
 results.append(dict(cwd=str(cwd),command=cmd,exit_code=p.returncode,log='delivery/g02b-logs/'+name+'.log'));print(name,p.returncode,flush=True)
(logs/'extra-results.json').write_text(json.dumps(results,indent=2)+'\n')
