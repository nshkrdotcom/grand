"""Execute argv with Grand-local tools. Invoke via scripts/local.sh or uv."""
import argparse
import subprocess
import sys
from provision import ROOT, LOCAL, local_env

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cwd", default=str(ROOT))
parser.add_argument("--tool", choices=("lynx", "veil"))
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
if not args.command:
    parser.error("a command is required")
cwd = LOCAL / "src" / args.tool if args.tool else ROOT / args.cwd
try:
    result = subprocess.run(args.command, cwd=cwd, env=local_env())
except FileNotFoundError as error:
    print(f"Missing command/workspace: {error}. Run scripts/bootstrap.sh.", file=sys.stderr)
    sys.exit(1)
sys.exit(result.returncode)
