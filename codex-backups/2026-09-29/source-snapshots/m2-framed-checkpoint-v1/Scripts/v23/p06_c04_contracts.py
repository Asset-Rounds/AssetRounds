from __future__ import annotations
import copy,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];CARD="V23-P06-C04";BASE="4f5cac63c9631f0b51956734d603ef505148b39b";TREE="e74a5a35415896b6e63cd824d90765e0bb77a45f";COORD="ff1319d3df1a330bcfcd2381744e368960c0ef77";CTREE="59afc9c02b3d1de04e00109d08de58f3c0d27987";SEQ=607
V5="docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json";V5SHA="33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5";V5D="57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38";RES="docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
H={"staticPreparationAnchorDigest":"6deb25429aac46a6beb9feda5c367909f048f22b719573dcc66f88db0ab603d3","executionSpecDigest":"a6b0eaa00490dc10d423b719ed7120fdea467ed1ca66c761f854da9682f4aba9","pathFenceDigest":"4cc6d567d4f665e602e3c101c65edd10d5d2f10818d0a3436c701f5d09cf46a7","prerequisiteSetDigest":"504d5261e6c4adc075b8e1798659907e3e5d888dbcd23be5f1975c00e98e0adc","transitionDigest":"0f8fb57691b0b6e986801948c7adc72bb26f5c175bbe591e1026294ba7009388","ledgerDigest":"e29721087d9f9fcd1abf0f6121361b6bd3f060a010a12d69367ee8fe4491616e","projectionDigest":"4f4890271d169f80e42652ae575e62cd69f177c383caaa427f8f9e63a36648ab"}
P18=("V23-P04-C18","034ee940cbe19998ea461502a599f0fcc0c74c6c5c1cf36822e9a2d153c641d0","a70ba5b0dc5aef54033d6296668b537f81b0343b80062412666ba52d0dd314e8","e22788314918ff294bf5b36cd851c7451a0286d7","df4cb890392f8e1b990bcbc8bfb66e59e9179958")
S=("Scripts/v23/p06_c04_contracts.py","Scripts/v23/generate_p06_c04_contracts.py","Scripts/v23/verify_p06_c04_contracts.py");SC="Scripts/v23/photometric-screening-static-protocol.schema.json";CP="FieldEvidenceAppTests/Fixtures/V23/P06/PhotometricScreening/V23P06C04PhotometricScreeningStaticCorpusV1.json";CT="docs/design/v23/tooling/V23P06C04PhotometricScreeningStaticPreparationContractV1.json";EV="docs/design/v23/tooling/V23P06C04PhotometricScreeningStaticPreparationEvidenceReceiptV1.json";BR="docs/design/v23/tooling/V23P06C04BrandImpactManifestV1.json";MF="docs/design/v23/tooling/V23-P06-C04-tooling-manifest.json";OWNED=(*S,SC,CP,CT,EV,BR,MF)
FLAGS={x:False for x in("native","hosted","physical","adoption","implementation","acceptance","selector","release","phase","main","merge","publication")};IDS=tuple("V23-P06-C04-"+x for x in("G01","A01","H01-MALFORMED","H01-DEVICE","H01-CLAIM","I01","R01"));FORBID=("VALIDATED_PASS","VALIDATED_FAIL","ACCEPTED","READY","RELEASED","PHASE_INTEGRATED")
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def can(v):return(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",": "))+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def load(p):return json.loads((ROOT/p).read_bytes())
def git(*x):return subprocess.run(["git",*x],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
def cr():return ROOT.parent/"AssetRounds-v23-coordination"
def cg(*x):return subprocess.run(["git",*x],cwd=cr(),check=True,capture_output=True,text=True).stdout.strip()
def seal(v,k,d,space=True):
 b=copy.deepcopy(v);a=b.pop(k,None);raw=can(b)if space else(json.dumps(b,sort_keys=True,separators=(",",":"))+"\n").encode()
 if a!=d or sha(raw)!=d:raise ValueError("digest differs:"+k)
def overlap():return len(set(OWNED)&set(load(RES).get("reservedPaths",())))
def authority_check():
 if sha((ROOT/V5).read_bytes())!=V5SHA:raise ValueError("V5 bytes")
 a=load(V5);b=copy.deepcopy(a);d=b.pop("contentDigest",None)
 if d!=V5D or sha(json.dumps(b,sort_keys=True,separators=(",",":")).encode())!=V5D:raise ValueError("V5 semantic")
 if CARD not in a["provisionalStaticPreparationPlane"]["eligibleCardsInCanonicalOrder"]:raise ValueError("V5 eligibility")
 if not all(a["noCredit"].get(x)is True for x in("implementationCreditProhibited","acceptanceCreditProhibited","selectorCreditProhibited","releaseCreditProhibited","phaseCreditProhibited","mainCreditProhibited","mergeCreditProhibited")):raise ValueError("V5 credit")
 r=load(RES);seal(r,"contentDigest",a["frozenPhase10Observation"]["reservationContentDigest"],False)
 if len(r["reservedPaths"])!=86:raise ValueError("reservation")
def verify():
 if subprocess.run(["git","merge-base","--is-ancestor",BASE,"HEAD"],cwd=ROOT).returncode or git("rev-parse",f"{BASE}^{{tree}}")!=TREE:raise ValueError("base")
 authority_check()
 if(cg("rev-parse","HEAD"),cg("rev-parse","origin/main"),cg("rev-parse","HEAD^{tree}"))!=(COORD,COORD,CTREE):raise ValueError("coord")
 ps={"receipts/V23-P00-C03-static-preparation-anchor-v1.json":("anchorDigest",H["staticPreparationAnchorDigest"],False),"contexts/V23-P06-C04-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json":("executionSpecDigest",H["executionSpecDigest"],True),"contexts/V23-P06-C04-attempt-1/ProvisionalStaticPreparationPathFenceV1.json":("pathFenceDigest",H["pathFenceDigest"],True),"receipts/V23-P06-C04-provisional-static-prerequisite-set-v1.json":("prerequisiteSetDigest",H["prerequisiteSetDigest"],True),"transitions/000607-V23-P06-C04-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json":("transitionDigest",H["transitionDigest"],True),"state/BootstrapExecutionLedgerEnvelopeV1.json":("ledgerDigest",H["ledgerDigest"],True),"projections/ActiveWorkSetProjectionV1.json":("projectionDigest",H["projectionDigest"],True)};d={p:json.loads((cr()/p).read_bytes())for p in ps}
 for p,(k,x,z)in ps.items():seal(d[p],k,x,False)
 sp=d[list(ps)[1]];fe=d[list(ps)[2]];pr=d[list(ps)[3]]
 if tuple(fe["allowedCreateOrReplacePaths"])!=OWNED or fe["s10ReservedOverlapCount"]!=0:raise ValueError("fence")
 if any(sp.get(k) is not False for k in("validationStudyAuthorized","customerData","meterDeviceBLECameraLicenseEnabled"))or sp.get("externalActions")!="NONE":raise ValueError("spec")
 x=pr["sources"][1];pin=tuple(x.get(k)for k in("cardID","checkpointDigest","verificationReceiptDigest","candidateHead","candidateTree"))
 if pin!=P18:raise ValueError("P18")
 if d[list(ps)[5]]["casSequence"]!=SEQ or d[list(ps)[6]]["ledgerDigest"]!=H["ledgerDigest"]:raise ValueError("ledger")
def protocol():return {"schema":"V23P06C04PhotometricScreeningStaticProtocolV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","purpose":"Declarative synthetic photometric screening protocol only; not a validation study.","meterAdapterInvoked":False,"deviceMeasurement":False,"ble":False,"camera":False,"network":False,"licenseContent":False,"complianceClaim":False,"accuracyClaim":False,"attestationClaim":False,"scope":{"sources":"SYNTHETIC_OR_REPOSITORY_ONLY","externalActions":"NONE","customerData":False,"manualOfflineFallback":True},"hypothesis":"Synthetic photometric screening protocol can be represented as offline static validation material without meter adapters, device/BLE/camera access, licenses, jurisdiction claims, backend, or second writer/store/kernel.","preconditions":{"p00C03":"NOT_PREELIGIBLE_PRESERVED","p04C18":"PROVISIONAL_ONLY","realValidationStudy":False},"evidenceIDs":list(IDS),"expiry":{"maximumDays":30,"reconcileOnAcceptedS10_6":True},"flags":FLAGS,"forbiddenResults":list(FORBID)}
def corpus():return {"schema":"V23P06C04PhotometricScreeningStaticCorpusV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","syntheticOnly":True,"realTerminalValidationResult":False,"cases":[{"id":IDS[0],"kind":"golden","input":"synthetic threshold descriptors","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[1],"kind":"accessibility","input":"synthetic text alternatives","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[2],"kind":"hostile","input":"malformed threshold descriptor","expected":"REJECT_NO_STUDY"},{"id":IDS[3],"kind":"hostile","input":"meter device BLE camera or network request","expected":"REJECT_DEVICE_INVOCATION"},{"id":IDS[4],"kind":"hostile","input":"license compliance accuracy or attestation claim","expected":"REJECT_CLAIM"},{"id":IDS[5],"kind":"interruption","input":"synthetic static interruption","expected":"NO_RUNTIME_CLAIM"},{"id":IDS[6],"kind":"recovery","input":"expired protocol","expected":"RECONCILE_OR_DISCARD"}],"forbiddenResults":list(FORBID)}
def schema():return {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":False,"required":["schema","cardID","disposition","meterAdapterInvoked","deviceMeasurement","ble","camera","network","licenseContent","complianceClaim","accuracyClaim","attestationClaim","scope","preconditions","evidenceIDs","flags","forbiddenResults"],"properties":{"schema":{"const":"V23P06C04PhotometricScreeningStaticProtocolV1"},"cardID":{"const":CARD},"disposition":{"const":"PROVISIONAL_STATIC_PREPARATION_ONLY"},"meterAdapterInvoked":{"const":False},"deviceMeasurement":{"const":False},"ble":{"const":False},"camera":{"const":False},"network":{"const":False}}}
def validate(v):
 if v!=protocol()or any(v["flags"].values())or tuple(v["evidenceIDs"])!=IDS:raise ValueError("protocol")
 if any(v[k]for k in("meterAdapterInvoked","deviceMeasurement","ble","camera","network","licenseContent","complianceClaim","accuracyClaim","attestationClaim"))or v["scope"]["customerData"]or v["scope"]["externalActions"]!="NONE":raise ValueError("photometric scope")
def authority():return {"cardID":CARD,"ordinal":140,"attemptID":1,"appBaseHead":BASE,"appBaseTree":TREE,"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","coordinationHead":COORD,"coordinationTree":CTREE,"sequence":SEQ,"ownerOverrideV5SHA256":V5SHA,"ownerOverrideV5SemanticDigest":V5D,**H,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","fencePathCount":9,"existingPathCount":0,"newPathCount":9,"s10ReservationOverlapCount":overlap(),"finalHashesSealed":False}
def docs():
 verify();p=protocol();c=corpus();validate(p);b={"schema":"V23P06C04StaticPreparationToolingV1","cardID":CARD,"authority":authority(),"appBaseIdentity":{"head":BASE,"tree":TREE},"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","flags":FLAGS,"noProductionPath":True,"noRealStudy":True,"noAcceptanceCredit":True};d={SC:schema(),CP:c,CT:{**b,"contract":"PhotometricScreeningStaticPreparationContractV1","protocol":p,"corpusPath":CP},EV:{**b,"receipt":"PhotometricScreeningStaticPreparationEvidenceReceiptV1","protocolSHA256":sha(pretty(p)),"corpusSHA256":sha(pretty(c)),"result":"PASS_STATIC_PROVISIONAL","terminalValidationResult":None},BR:{**b,"manifest":"PhotometricScreeningBrandImpactManifestV1","impact":"NONE_SHIPPING","requiresMergeTimeS10_6Reconciliation":True}};d[MF]={**b,"manifest":"V23P06C04ToolingManifestV1","pathFence":list(OWNED),"generatedFiles":[{"path":k,"sha256":sha(pretty(v))}for k,v in d.items()]};return d
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
 for n,f in(("meter",lambda x:x.__setitem__("meterAdapterInvoked",True)),("device",lambda x:x.__setitem__("deviceMeasurement",True)),("network",lambda x:x.__setitem__("network",True)),("claim",lambda x:x.__setitem__("complianceClaim",True))):
  x=copy.deepcopy(protocol());f(x)
  try:validate(x)
  except ValueError:out.append(n)
 if len(out)!=4:raise ValueError("self test")
 return {"result":"PASS_STATIC_PROVISIONAL","rejected":out}
