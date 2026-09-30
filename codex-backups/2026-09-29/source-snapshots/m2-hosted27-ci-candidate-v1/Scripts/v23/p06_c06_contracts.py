from __future__ import annotations
import copy,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];CARD="V23-P06-C06";BASE="d14bcaedef96a8404be7011f39dc7ec825824459";TREE="104ca8da1bac691da8a38667007585d02c876d0a";COORD="980362ad542288a62824ac6ce8c18e78ad99aefa";CTREE="b594186477267346db5002e4924971a268bccd3c";SEQ=611
V5="docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json";V5SHA="33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5";V5D="57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38";RES="docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
H={"staticPreparationAnchorDigest":"6deb25429aac46a6beb9feda5c367909f048f22b719573dcc66f88db0ab603d3","executionSpecDigest":"91fb61a46174f0f77fd32d32994e3a59e2cfb3e1e8446dce3ced93db092e5671","pathFenceDigest":"f10cb04e506a49b0a7429f78c0a71d94abd900d6420707a442b48546196e170d","prerequisiteSetDigest":"a7f63ac6fd904f6d735b8b20a544407a2f59610ca64e74c39c5f945e6e042f1b","transitionDigest":"eedc9a7c6d748e6fdd4671ee3c3124a7a73872d4748be8f8b809414442f50721","ledgerDigest":"23002ccb3bac68ac1fdc3206c6a00dbcc6abe5a259a7dbfa91d79254fdbe24f4","projectionDigest":"2f67d1aa9ff626fc415f3dddbece9aa2d5a11b4306fd5e56fc13d6d715cead0e"}
S=("Scripts/v23/p06_c06_contracts.py","Scripts/v23/generate_p06_c06_contracts.py","Scripts/v23/verify_p06_c06_contracts.py");SC="Scripts/v23/managed-label-static-protocol.schema.json";CP="FieldEvidenceAppTests/Fixtures/V23/P06/ManagedLabel/V23P06C06ManagedLabelStaticCorpusV1.json";CT="docs/design/v23/tooling/V23P06C06ManagedLabelStaticPreparationContractV1.json";EV="docs/design/v23/tooling/V23P06C06ManagedLabelStaticPreparationEvidenceReceiptV1.json";BR="docs/design/v23/tooling/V23P06C06BrandImpactManifestV1.json";MF="docs/design/v23/tooling/V23-P06-C06-tooling-manifest.json";OWNED=(*S,SC,CP,CT,EV,BR,MF);FLAGS={x:False for x in("native","hosted","physical","adoption","implementation","acceptance","selector","release","phase","main","merge","publication")};IDS=tuple("V23-P06-C06-"+x for x in("G01","A01","H01-DAMAGED","H01-DUPLICATE","H01-FOREIGN","H01-REVOKED","H01-REPLACED","I01","R01"));CAPS=("QR_GENERATION","PDF_GENERATION","CSV_GENERATION","SCAN","CAMERA","PRINT","NETWORK","RESOLVER","VENDOR_SDK","SECRET","AUTOMATIC_START")
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def load(p):return json.loads((ROOT/p).read_bytes())
def git(*x):return subprocess.run(["git",*x],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
def cr():return ROOT.parent/"AssetRounds-v23-coordination"
def cg(*x):return subprocess.run(["git",*x],cwd=cr(),check=True,capture_output=True,text=True).stdout.strip()
def cbytes(v):return(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n").encode()
def seal(v,k,d):
 b=copy.deepcopy(v);a=b.pop(k,None)
 if a!=d or sha(cbytes(b))!=d:raise ValueError("digest:"+k)
def overlap():return len(set(OWNED)&set(load(RES)["reservedPaths"]))
def verify():
 if subprocess.run(["git","merge-base","--is-ancestor",BASE,"HEAD"],cwd=ROOT).returncode or git("rev-parse",f"{BASE}^{{tree}}")!=TREE:raise ValueError("base")
 if sha((ROOT/V5).read_bytes())!=V5SHA:raise ValueError("V5")
 a=load(V5);b=copy.deepcopy(a);d=b.pop("contentDigest");
 if d!=V5D or sha(json.dumps(b,sort_keys=True,separators=(",",":")).encode())!=V5D or CARD not in a["provisionalStaticPreparationPlane"]["eligibleCardsInCanonicalOrder"]:raise ValueError("authority")
 r=load(RES);seal(r,"contentDigest",a["frozenPhase10Observation"]["reservationContentDigest"])
 if len(r["reservedPaths"])!=86:raise ValueError("reservation")
 if(cg("rev-parse","HEAD"),cg("rev-parse","origin/main"),cg("rev-parse","HEAD^{tree}"))!=(COORD,COORD,CTREE):raise ValueError("coord")
 ps={"receipts/V23-P00-C03-static-preparation-anchor-v1.json":("anchorDigest",H["staticPreparationAnchorDigest"]),"contexts/V23-P06-C06-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json":("executionSpecDigest",H["executionSpecDigest"]),"contexts/V23-P06-C06-attempt-1/ProvisionalStaticPreparationPathFenceV1.json":("pathFenceDigest",H["pathFenceDigest"]),"receipts/V23-P06-C06-provisional-static-prerequisite-set-v1.json":("prerequisiteSetDigest",H["prerequisiteSetDigest"]),"transitions/000611-V23-P06-C06-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json":("transitionDigest",H["transitionDigest"]),"state/BootstrapExecutionLedgerEnvelopeV1.json":("ledgerDigest",H["ledgerDigest"]),"projections/ActiveWorkSetProjectionV1.json":("projectionDigest",H["projectionDigest"])};q={p:json.loads((cr()/p).read_bytes())for p in ps}
 for p,(k,d)in ps.items():seal(q[p],k,d)
 if tuple(q[list(ps)[2]]["allowedCreateOrReplacePaths"])!=OWNED or q[list(ps)[2]]["s10ReservedOverlapCount"]!=0:raise ValueError("fence")
 sp=q[list(ps)[1]]
 if sp.get("validationStudyAuthorized")is not False or sp.get("customerData")is not False or sp.get("externalActions")!="NONE" or sp.get("qrPDFCSVGenerationEnabled")is not False:raise ValueError("spec")
 if q[list(ps)[5]]["casSequence"]!=SEQ or q[list(ps)[6]]["ledgerDigest"]!=H["ledgerDigest"]:raise ValueError("ledger")
def protocol():return {"schema":"V23P06C06ManagedLabelStaticProtocolV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","declarativeOnly":True,"capabilityInvoked":False,"canonicalWrites":0,"prohibitedCapabilities":list(CAPS),"scope":{"sources":"SYNTHETIC_OR_REPOSITORY_ONLY","externalActions":"NONE","customerData":False},"preconditions":{"p00C03":"NOT_PREELIGIBLE_PRESERVED","p04C13":"PROVISIONAL_ONLY","p04C21":"PROVISIONAL_ONLY","realValidationStudy":False},"evidenceIDs":list(IDS),"expiry":{"maximumDays":30,"reconcileOnAcceptedS10_6":True},"flags":FLAGS}
def corpus():return {"schema":"V23P06C06ManagedLabelStaticCorpusV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","syntheticOnly":True,"cases":[{"id":IDS[0],"kind":"golden","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[1],"kind":"accessibility","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[2],"kind":"hostile","input":"damaged label","expected":"REJECT_DAMAGED"},{"id":IDS[3],"kind":"hostile","input":"duplicate label","expected":"REJECT_DUPLICATE"},{"id":IDS[4],"kind":"hostile","input":"foreign label","expected":"REJECT_FOREIGN"},{"id":IDS[5],"kind":"hostile","input":"revoked label","expected":"REJECT_REVOKED"},{"id":IDS[6],"kind":"hostile","input":"replaced label","expected":"REJECT_REPLACED"},{"id":IDS[7],"kind":"interruption","expected":"NO_RUNTIME_CLAIM"},{"id":IDS[8],"kind":"recovery","expected":"RECONCILE_OR_DISCARD"}],"realTerminalValidationResult":False}
def schema():return {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":False,"required":["schema","cardID","disposition","declarativeOnly","capabilityInvoked","canonicalWrites","prohibitedCapabilities","scope","preconditions","evidenceIDs","flags"],"properties":{"schema":{"const":"V23P06C06ManagedLabelStaticProtocolV1"},"cardID":{"const":CARD},"disposition":{"const":"PROVISIONAL_STATIC_PREPARATION_ONLY"},"declarativeOnly":{"const":True},"capabilityInvoked":{"const":False},"canonicalWrites":{"const":0}}}
def validate(v):
 if v!=protocol()or any(v["flags"].values())or tuple(v["evidenceIDs"])!=IDS:raise ValueError("protocol")
 if not v["declarativeOnly"]or v["capabilityInvoked"]or v["canonicalWrites"]or v["scope"]["customerData"]or v["scope"]["externalActions"]!="NONE"or tuple(v["prohibitedCapabilities"])!=CAPS:raise ValueError("capability")
def authority():return {"cardID":CARD,"ordinal":142,"attemptID":1,"appBaseHead":BASE,"appBaseTree":TREE,"coordinationHead":COORD,"coordinationTree":CTREE,"sequence":SEQ,"ownerOverrideV5SHA256":V5SHA,"ownerOverrideV5SemanticDigest":V5D,**H,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","fencePathCount":9,"s10ReservationOverlapCount":overlap(),"finalHashesSealed":False}
def docs():
 verify();p=protocol();c=corpus();validate(p);b={"schema":"V23P06C06StaticPreparationToolingV1","cardID":CARD,"authority":authority(),"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","flags":FLAGS,"noProductionPath":True,"noRealStudy":True};x={SC:schema(),CP:c,CT:{**b,"contract":"ManagedLabelStaticPreparationContractV1","protocol":p,"corpusPath":CP},EV:{**b,"receipt":"ManagedLabelStaticPreparationEvidenceReceiptV1","result":"PASS_STATIC_PROVISIONAL","protocolSHA256":sha(pretty(p)),"corpusSHA256":sha(pretty(c))},BR:{**b,"manifest":"ManagedLabelBrandImpactManifestV1","impact":"NONE_SHIPPING"}};x[MF]={**b,"manifest":"V23P06C06ToolingManifestV1","pathFence":list(OWNED),"generatedFiles":[{"path":k,"sha256":sha(pretty(v))}for k,v in x.items()]};return x
def changed():
 s={x.replace("\\","/")for x in git("diff","--name-only",BASE,"HEAD").splitlines()if x}
 for r in subprocess.run(["git","status","--porcelain=v1"],cwd=ROOT,check=True,capture_output=True,text=True).stdout.splitlines():
  p=r[3:].replace("\\","/");t=ROOT/p
  if t.is_dir():s.update(x.relative_to(ROOT).as_posix()for x in t.rglob("*")if x.is_file())
  elif p:s.add(p)
 return s
def counts():
 s=changed();return {"changedPathCount":len(s&set(OWNED)),"missingOwnedPathCount":sum(not(ROOT/x).is_file()for x in OWNED),"unownedChangedPathCount":len(s-set(OWNED)),"s10ReservationOverlapCount":overlap(),"fencePathCount":9}
def self_test():
 out=[]
 for n,f in(("invoke",lambda x:x.__setitem__("capabilityInvoked",True)),("write",lambda x:x.__setitem__("canonicalWrites",1)),("secret",lambda x:x["prohibitedCapabilities"].pop()),("data",lambda x:x["scope"].__setitem__("customerData",True))):
  x=copy.deepcopy(protocol());f(x)
  try:validate(x)
  except ValueError:out.append(n)
 if len(out)!=4:raise ValueError("self test")
 return {"result":"PASS_STATIC_PROVISIONAL","rejected":out}
