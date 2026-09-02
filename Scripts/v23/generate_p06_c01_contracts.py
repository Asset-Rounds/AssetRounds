import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import p06_c01_contracts as c

p=argparse.ArgumentParser(); p.add_argument("--apply",action="store_true"); p.add_argument("--check",action="store_true"); p.add_argument("--self-test",action="store_true"); p.add_argument("--json",action="store_true"); a=p.parse_args()
if a.self_test:
    result=c.self_test(); print(__import__('json').dumps(result,sort_keys=True) if a.json else result['result']); raise SystemExit(0)
if a.apply == a.check: p.error("choose exactly one of --apply or --check")
try:
    docs={path:c.pretty(value) for path,value in c.documents().items()}
    drift=[path for path,data in docs.items() if not (c.ROOT/path).is_file() or (c.ROOT/path).read_bytes()!=data]
    if a.check:
        if drift: raise ValueError("artifact drift:"+",".join(drift))
        print("P06-C01 generator check PASS_STATIC_PROVISIONAL")
    else:
        for path,data in docs.items():
            target=c.ROOT/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
        print("P06-C01 generator apply PASS_STATIC_PROVISIONAL generated="+str(len(docs)))
except Exception as exc:
    print("P06-C01 generator FAIL_STATIC:"+str(exc),file=sys.stderr); raise SystemExit(1)
