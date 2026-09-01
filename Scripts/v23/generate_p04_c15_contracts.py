import argparse,os,sys,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c15_contracts as c
FAULTS=("BEFORE_ACCEPTED_ARTIFACT_WRITE","AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT","AFTER_RECEIPT_BEFORE_RETURN")
def rendered():
 d=c.documents();c.validate_documents(d);return {k:c.pretty(v)for k,v in d.items()}
def accepted(root,expected):
 manifest=root/c.MANIFEST
 if not manifest.is_file():return False
 try:
  import json;m=json.loads(manifest.read_bytes())
  return len(m.get("files",[]))==3 and m.get("sources")==c.rows()[0] and all((root/x["path"]).is_file()and c.sha((root/x["path"]).read_bytes())==x["sha256"]and (root/x["path"]).read_bytes()==expected[x["path"]] for x in m["files"])
 except Exception:return False
def apply_atomic(expected,root=c.ROOT,fault=None):
 if fault==FAULTS[0]:raise RuntimeError(fault)
 staged=[]
 try:
  for path,bytes_ in expected.items():
   target=root/path;target.parent.mkdir(parents=True,exist_ok=True);fd,tmp=tempfile.mkstemp(prefix=".c15-",dir=target.parent);os.write(fd,bytes_);os.close(fd);staged.append((target,Path(tmp)))
  for target,tmp in staged[:-1]:os.replace(tmp,target)
  if fault==FAULTS[1]:raise RuntimeError(fault)
  target,tmp=staged[-1];os.replace(tmp,target)
  if fault==FAULTS[2]:raise RuntimeError(fault)
 finally:
  for _,tmp in staged:
   if tmp.exists():tmp.unlink()
def self_test(expected):
 with tempfile.TemporaryDirectory(prefix="c15-interrupt-")as folder:
  root=Path(folder)
  for path,bytes_ in expected.items():(root/path).parent.mkdir(parents=True,exist_ok=True);(root/path).write_bytes(bytes_)
  import json;candidate=dict(expected)
  for index,path in enumerate((c.CONTRACT,c.EVIDENCE,c.BRAND),1):candidate[path]=("candidate-artifact-"+str(index)+"\n").encode()
  manifest=json.loads(expected[c.MANIFEST]);manifest["files"]=[{"path":path,"sha256":c.sha(candidate[path])}for path in(c.CONTRACT,c.EVIDENCE,c.BRAND)];candidate[c.MANIFEST]=c.pretty(manifest)
  outcomes=[]
  for fault in FAULTS:
   for path,bytes_ in expected.items():(root/path).write_bytes(bytes_)
   try:apply_atomic(candidate,root,fault)
   except RuntimeError as error:
    if str(error)!=fault:raise
   outcomes.append((fault,sum(accepted(root,set_)for set_ in(expected,candidate))))
  if outcomes!=[(FAULTS[0],1),(FAULTS[1],0),(FAULTS[2],1)]:raise ValueError("C15 interruption acceptance differs:"+repr(outcomes))
 return outcomes
p=argparse.ArgumentParser();p.add_argument("--apply",action="store_true");p.add_argument("--check",action="store_true");p.add_argument("--fault",choices=FAULTS);p.add_argument("--self-test",action="store_true");a=p.parse_args()
if not a.self_test and a.apply==a.check:p.error("choose exactly one")
try:
 o=rendered()
 if a.self_test:print("C15 interruption self-test PASS "+repr(self_test(o)))
 elif a.check:
  if not accepted(c.ROOT,o):raise ValueError("artifact drift or incomplete acceptance set")
  print("C15 generator check PASS_STATIC_PROVISIONAL")
 else:
  apply_atomic(o,fault=a.fault);print("C15 generator apply PASS_STATIC_PROVISIONAL generated=4 manifest-last")
except Exception as e:print("C15 generator FAIL_STATIC:"+str(e),file=sys.stderr);raise SystemExit(1)
