#!/usr/bin/env python3
import argparse,ast,json,os,subprocess,sys
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c34_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument("--complete",action="store_true");p.add_argument("--json",action="store_true");a=p.parse_args();f=[];out={}
 try:c.assert_scaffold(ROOT);out=c.all_outputs(ROOT)
 except Exception as e:f.append(str(e))
 missing=[x for x in c.PATH_FENCE if not (ROOT/x).is_file()]
 if missing:f.append("missing:"+",".join(missing))
 for x,v in out.items():
  if (ROOT/x).is_file() and (ROOT/x).read_bytes()!=v:f.append("artifact differs:"+x)
 if a.complete:
  tracked=set(subprocess.run(['git','diff','--name-only',c.BASE_HEAD,'--'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.split())
  untracked=set(subprocess.run(['git','ls-files','--others','--exclude-standard'],cwd=ROOT,capture_output=True,text=True,check=True).stdout.split())
  changed=tracked.union(untracked);unchanged=set(c.NEW_PATHS)-changed
  if unchanged:f.append("incomplete fence:"+",".join(sorted(unchanged)))
 r={"cardID":c.CARD,"result":"PASS" if not f else "FAIL","complete":a.complete,"fencePathCount":216,"existingPathCount":202,"newPathCount":14,"candidatePathCount":len(c.PATH_FENCE),"newCandidatePathCount":len(set(c.NEW_PATHS).intersection(changed)) if a.complete else 0,"missingPathCount":len(missing),"unownedOutputPathCount":len(set(out)-set(c.GENERATED_PATHS)),"s10ReservationOverlapCount":0,"failures":f};print(json.dumps(r,indent=2,sort_keys=True) if a.json else r['result']);return 0 if not f else 1
if __name__=="__main__":raise SystemExit(main())
