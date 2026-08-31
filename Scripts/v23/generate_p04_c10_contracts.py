#!/usr/bin/env python3
import argparse
import os
import sys
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
from p04_c10_contracts import ROOT, documents, pretty, FINAL_HASHES_SEALED, validate_generated_documents
parser=argparse.ArgumentParser()
parser.add_argument("--apply",action="store_true")
parser.add_argument("--check",action="store_true")
args=parser.parse_args()
if args.apply == args.check: parser.error("choose exactly one of --apply or --check")
try:
    rendered={path:pretty(value) for path,value in documents().items()}
    validate_generated_documents({path: __import__("json").loads(data) for path,data in rendered.items()})
    stale=[path for path,data in rendered.items() if not (ROOT/path).is_file() or (ROOT/path).read_bytes()!=data]
    if args.check:
        if stale:
            print("C10 generator check FAIL_STATIC_STALE\nstale="+",".join(stale)); raise SystemExit(1)
        print("C10 generator check "+("PASS_STATIC_SEALED" if FINAL_HASHES_SEALED else "PASS_STATIC_PROVISIONAL"))
    else:
        for path,data in rendered.items():
            target=ROOT/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
        print("C10 generator apply PASS_STATIC_"+("SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL")+" generated="+str(len(rendered)))
except Exception as error:
    print("C10 generator FAIL_STATIC:"+str(error),file=sys.stderr); raise SystemExit(1)
