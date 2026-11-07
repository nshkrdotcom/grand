#!/usr/bin/env python3
"""Capture actual ordered gates without stopping at the first failure."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'delivery/g03b-logs'
COMMANDS = ['mix deps.get --check-locked', 'mix format --check-formatted',
            'mix compile --warnings-as-errors', 'mix test', 'mix credo --strict',
            'mix dialyzer']


def capture(command, cwd=ROOT):
    return subprocess.check_output(command, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else 'final'
    if not re.fullmatch(r'[a-z0-9-]+', label):
        raise SystemExit('invalid run label')
    OUT.mkdir(exist_ok=True)
    if (OUT / f'{label}-matrix.json').exists():
        raise SystemExit('refusing to overwrite recorded matrix')
    elixir = capture(['elixir', '--version'])
    mix = capture(['mix', '--version'])
    otp = capture(['erl', '-noshell', '-eval',
                   'io:format("~s", [element(2, file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])))]), halt().'])
    if 'Elixir 1.20.5 ' not in elixir or otp != '29.1.2':
        raise SystemExit('pinned toolchain unavailable; do not run as passing acceptance')
    head = capture(['git', 'rev-parse', 'HEAD'])
    status = capture(['git', 'status', '--short'])
    results = []
    for app in ['grand_core', 'grand_beamcompass', 'grand_assurance', 'grand_cli']:
        cwd = ROOT / 'monorepo' / app
        for index, command in enumerate(COMMANDS, 1):
            at = datetime.datetime.now(datetime.timezone.utc).isoformat()
            log = OUT / f'{label}-{app}-{index}.log'
            process = subprocess.run(command.split(), cwd=cwd, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT)
            log.write_bytes(process.stdout)
            output = process.stdout.decode(errors='replace')
            passed = re.search(r'Result: (\d+) passed', output)
            partial = re.search(r'Result: (\d+)/(\d+) passed', output)
            failed = re.search(r'Failed: (\d+) tests?', output)
            tests = (int(partial[2]) if partial else int(passed[1]) if passed else None)
            failures = int(failed[1]) if failed else 0 if tests is not None else None
            results.append(dict(cwd=str(cwd), command=command, timestamp=at,
                                completed_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                elixir_version=elixir, otp_version=otp, mix_version=mix,
                                checked_code_head=head, checked_code_status=status,
                                lock_sha256=hashlib.sha256((cwd / 'mix.lock').read_bytes()).hexdigest(),
                                exit_code=process.returncode, log_path=str(log.relative_to(ROOT)),
                                tests=tests, failures=failures,
                                outcome='PASS' if process.returncode == 0 else 'FAIL'))
            (OUT / f'{label}-matrix.json').write_text(json.dumps(results, indent=2) + '\n')
            print(app, command, process.returncode, tests, failures, flush=True)
    return int(any(r['exit_code'] for r in results))


if __name__ == '__main__':
    sys.exit(main())
