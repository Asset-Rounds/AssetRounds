from __future__ import annotations
import copy,hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; CARD="V23-P06-C03"; ORDINAL=139
BASE,TREE="fdfa30aaf2c19201e88b4536ff0c587a36c9207c","6b1941d42498f8127f8bd0ecb11d071096f6f642"
COORD,CTREE,SEQ="4a06a207563687f435b0e816aa846b923714aca9","8a41b45757bdd5a468d729d991a36eda131b1cfd",603
V5="docs/design/v23/authority/OwnerParallelImplementationOverrideV5.json"; V5SHA="33ca39e0996baf62069f60d68b96181844160dfdcc97a2ba05e8ba045dfc46b5"; V5DIGEST="57255dfd005eedb7971f1dffb42257d06d44f4dd929788b125be1abb6fdf1e38"; RES="docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
HYD={"staticPreparationAnchorDigest":"6deb25429aac46a6beb9feda5c367909f048f22b719573dcc66f88db0ab603d3","executionSpecDigest":"6a84f507e2e1335558f936ac42f755b5d2e97a4e6a17051891c4c32e4578f0cc","pathFenceDigest":"3ee692da8b53f7c9b9aed45b1e5baa9e9f1060a3dd4b171147a6d6ee888effd7","prerequisiteSetDigest":"bacd1ff29a8c67f6220803f9f78eaeb887adbb71481833deb5781776bdea64ff","transitionDigest":"94bccb4edf96c0a18a4526e7866b6222c596b90503024f7cefd869c9f1266965","ledgerDigest":"aa07c87964e32513dbbeb28635b0d4b0534d4a668a68ef6e1b2cca429b8e8c19","projectionDigest":"d73a3ccde578d57bdc27bc2fade6e56df3fc0e0fc5f577fa59ca4acfc637d88c"}
P04=(("V23-P04-C07","03f9bb99f26b227995a24dd939c8489948e64331a175051dc7fb55d2d03dc927","f0b52c6c7c45f22b19756cd2c4ed655139f24fe04d5351bc07a00215c6625fa0","8925c84d79f703482525a0dc0876bfb6a1e5b7c1","68a59bca98a5aa2a191c138db6418492203b0586"),("V23-P04-C20","b1576eff29ca2edb5094a1f88d392b5dc3b4c9d5802c3d3001baca25444dd000","b3a0c7c41dc0f84685b678d2b7cbcab00124ef5f1bbd36ba08572db9476dc44b","e82534cd6894138bf15085e2dc08e736aefb2531","a2265654e81a74be07557546c8edfdddb437e6f3"))
SCRIPTS=("Scripts/v23/p06_c03_contracts.py","Scripts/v23/generate_p06_c03_contracts.py","Scripts/v23/verify_p06_c03_contracts.py"); SCHEMA="Scripts/v23/advanced-survey-static-protocol.schema.json"; CORPUS="FieldEvidenceAppTests/Fixtures/V23/P06/AdvancedSurvey/V23P06C03AdvancedSurveyStaticCorpusV1.json"; CONTRACT="docs/design/v23/tooling/V23P06C03AdvancedSurveyStaticPreparationContractV1.json"; EVIDENCE="docs/design/v23/tooling/V23P06C03AdvancedSurveyStaticPreparationEvidenceReceiptV1.json"; BRAND="docs/design/v23/tooling/V23P06C03BrandImpactManifestV1.json"; MANIFEST="docs/design/v23/tooling/V23-P06-C03-tooling-manifest.json"; OWNED=(*SCRIPTS,SCHEMA,CORPUS,CONTRACT,EVIDENCE,BRAND,MANIFEST)
FLAGS={x:False for x in ("native","hosted","physical","adoption","implementation","acceptance","selector","release","phase","main","merge","publication")}; IDS=tuple("V23-P06-C03-"+x for x in ("G01","A01","H01-MALFORMED","H01-EAV","H01-EXCHANGE","I01","R01")); FORBIDDEN=("VALIDATED_PASS","VALIDATED_FAIL","ACCEPTED","READY","RELEASED","PHASE_INTEGRATED")
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def canon(v):return(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",": "))+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def load(p):return json.loads((ROOT/p).read_bytes())
def git(*x):return subprocess.run(["git",*x],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
def cr():return ROOT.parent/"AssetRounds-v23-coordination"
def cg(*x):return subprocess.run(["git",*x],cwd=cr(),check=True,capture_output=True,text=True).stdout.strip()
def cl(p):return json.loads(p.read_bytes())
def checkseal(v,k,d,spaced=True):
 b=copy.deepcopy(v);a=b.pop(k,None)
 raw=canon(b) if spaced else (json.dumps(b,sort_keys=True,separators=(",",":"))+"\n").encode()
 if a!=d or sha(raw)!=d:raise ValueError("self digest differs:"+k)
def overlap():return len(set(OWNED)&set(load(RES).get("reservedPaths",())))
def v5():
 if sha((ROOT/V5).read_bytes())!=V5SHA:raise ValueError("V5 byte digest differs")
 a=load(V5);b=copy.deepcopy(a);d=b.pop("contentDigest",None)
 if d!=V5DIGEST or sha(json.dumps(b,sort_keys=True,separators=(",",":")).encode())!=V5DIGEST:raise ValueError("V5 semantic digest differs")
 if CARD not in a.get("provisionalStaticPreparationPlane",{}).get("eligibleCardsInCanonicalOrder",()):raise ValueError("V5 eligibility differs")
 if not all(a.get("noCredit",{}).get(x) is True for x in ("implementationCreditProhibited","acceptanceCreditProhibited","selectorCreditProhibited","releaseCreditProhibited","phaseCreditProhibited","mainCreditProhibited","mergeCreditProhibited")):raise ValueError("V5 no credit differs")
 r=load(RES);checkseal(r,"contentDigest",a["frozenPhase10Observation"]["reservationContentDigest"],False)
 if r.get("reservedPathCount")!=86 or len(r.get("reservedPaths",()))!=86:raise ValueError("reservation differs")
def coord():
 if not cr().is_dir() or (cg("rev-parse","HEAD"),cg("rev-parse","origin/main"),cg("rev-parse","HEAD^{tree}"))!=(COORD,COORD,CTREE):raise ValueError("coord identity differs")
 ps={"receipts/V23-P00-C03-static-preparation-anchor-v1.json":("anchorDigest",HYD["staticPreparationAnchorDigest"]),"contexts/V23-P06-C03-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json":("executionSpecDigest",HYD["executionSpecDigest"]),"contexts/V23-P06-C03-attempt-1/ProvisionalStaticPreparationPathFenceV1.json":("pathFenceDigest",HYD["pathFenceDigest"]),"receipts/V23-P06-C03-provisional-static-prerequisite-set-v1.json":("prerequisiteSetDigest",HYD["prerequisiteSetDigest"]),"transitions/000603-V23-P06-C03-attempt-1-NOT_STARTED-to-HYDRATING-static-preparation.json":("transitionDigest",HYD["transitionDigest"]),"state/BootstrapExecutionLedgerEnvelopeV1.json":("ledgerDigest",HYD["ledgerDigest"]),"projections/ActiveWorkSetProjectionV1.json":("projectionDigest",HYD["projectionDigest"])};ds={p:cl(cr()/p)for p in ps}
 for p,(k,d)in ps.items():checkseal(ds[p],k,d,k!="anchorDigest")
 spec=ds["contexts/V23-P06-C03-attempt-1/ProvisionalStaticPreparationExecutionSpecV1.json"];fence=ds["contexts/V23-P06-C03-attempt-1/ProvisionalStaticPreparationPathFenceV1.json"];pre=ds["receipts/V23-P06-C03-provisional-static-prerequisite-set-v1.json"]
 if tuple(fence.get("allowedCreateOrReplacePaths",()))!=OWNED or fence.get("s10ReservedOverlapCount")!=0:raise ValueError("fence differs")
 if spec.get("validationStudyAuthorized") is not False or spec.get("customerData") is not False or spec.get("externalActions")!="NONE":raise ValueError("spec differs")
 if tuple((x.get("cardID"),x.get("checkpointDigest"),x.get("verificationReceiptDigest"),x.get("candidateHead"),x.get("candidateTree"))for x in pre.get("sources",())[1:])!=P04:raise ValueError("P04 pins differ")
 if ds["state/BootstrapExecutionLedgerEnvelopeV1.json"].get("casSequence")!=SEQ or ds["projections/ActiveWorkSetProjectionV1.json"].get("ledgerDigest")!=HYD["ledgerDigest"]:raise ValueError("ledger projection differs")
def verify():
 if subprocess.run(["git","merge-base","--is-ancestor",BASE,"HEAD"],cwd=ROOT).returncode or git("rev-parse",f"{BASE}^{{tree}}")!=TREE:raise ValueError("base identity differs")
 v5();coord()
def protocol():return {"schema":"V23P06C03AdvancedSurveyStaticProtocolV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","purpose":"Declarative advanced survey-pack, field-type, and exchange validation protocol only; not a validation study.","eav":False,"newStore":False,"newWriter":False,"newRenderer":False,"importInvoked":False,"exportInvoked":False,"backend":False,"network":False,"customerPayload":False,"publicClaim":False,"scope":{"sources":"SYNTHETIC_OR_REPOSITORY_ONLY","externalActions":"NONE","customerData":False,"manualOfflineFallback":True},"hypothesis":"Existing local survey-pack and exchange contracts can document advanced field-type refinement without backend, second writer/store/kernel, or real validation studies.","disconfirmers":["EAV","new store","new writer","new renderer","import invocation","export invocation","backend","network","customer payload","public claim","loss of manual offline fallback"],"preconditions":{"p00C03":"NOT_PREELIGIBLE_PRESERVED","p04C07":"PROVISIONAL_ONLY","p04C20":"PROVISIONAL_ONLY","realValidationStudy":False},"evidenceIDs":list(IDS),"expiry":{"maximumDays":30,"reconcileOnAcceptedS10_6":True,"invalidateOn":["authority-change","register-change","graph-change","reservation-change","origin-main-change","predecessor-checkpoint-change","revocation"]},"flags":FLAGS,"forbiddenResults":list(FORBIDDEN)}
def corpus():return {"schema":"V23P06C03AdvancedSurveyStaticCorpusV1","cardID":CARD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","syntheticOnly":True,"realTerminalValidationResult":False,"cases":[{"id":IDS[0],"kind":"golden","input":"synthetic advanced survey grammar","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[1],"kind":"accessibility","input":"synthetic field label and RTL review","expected":"STATIC_PROTOCOL_ONLY"},{"id":IDS[2],"kind":"hostile","input":"malformed field type","expected":"REJECT_NO_STUDY"},{"id":IDS[3],"kind":"hostile","input":"EAV or new writer/store/renderer request","expected":"REJECT_OUT_OF_SCOPE"},{"id":IDS[4],"kind":"hostile","input":"import export backend network customer payload or public claim","expected":"REJECT_OUT_OF_SCOPE"},{"id":IDS[5],"kind":"interruption","input":"synthetic static review interruption","expected":"NO_RUNTIME_CLAIM"},{"id":IDS[6],"kind":"recovery","input":"expired or revoked protocol","expected":"RECONCILE_OR_DISCARD"}],"forbiddenResults":list(FORBIDDEN)}
def schema():return {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":False,"required":["schema","cardID","disposition","eav","newStore","newWriter","newRenderer","importInvoked","exportInvoked","backend","network","customerPayload","publicClaim","scope","hypothesis","disconfirmers","preconditions","evidenceIDs","expiry","flags","forbiddenResults"],"properties":{"schema":{"const":"V23P06C03AdvancedSurveyStaticProtocolV1"},"cardID":{"const":CARD},"disposition":{"const":"PROVISIONAL_STATIC_PREPARATION_ONLY"},"eav":{"const":False},"newStore":{"const":False},"newWriter":{"const":False},"newRenderer":{"const":False},"importInvoked":{"const":False},"exportInvoked":{"const":False},"backend":{"const":False},"network":{"const":False},"customerPayload":{"const":False},"publicClaim":{"const":False}}}
def validate(v):
 if v!=protocol() or any(v["flags"].values())or tuple(v["evidenceIDs"])!=IDS:raise ValueError("protocol drift")
 if any(v[x]for x in ("eav","newStore","newWriter","newRenderer","importInvoked","exportInvoked","backend","network","customerPayload","publicClaim"))or v["scope"]["customerData"]or v["scope"]["externalActions"]!="NONE"or not v["scope"]["manualOfflineFallback"]:raise ValueError("advanced survey scope drift")
def authority():return {"cardID":CARD,"ordinal":ORDINAL,"attemptID":1,"appBaseHead":BASE,"appBaseTree":TREE,"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","coordinationHead":COORD,"coordinationTree":CTREE,"sequence":SEQ,"ownerOverrideV5SHA256":V5SHA,"ownerOverrideV5SemanticDigest":V5DIGEST,**HYD,"disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","fencePathCount":9,"existingPathCount":0,"newPathCount":9,"s10ReservationOverlapCount":overlap(),"finalHashesSealed":False}
def docs():
 verify();p=protocol();c=corpus();validate(p);b={"schema":"V23P06C03StaticPreparationToolingV1","cardID":CARD,"authority":authority(),"appBaseIdentity":{"head":BASE,"tree":TREE},"observedCandidateIdentityPolicy":"RUNTIME_OBSERVATION_NOT_GENERATED_SELF_PIN","disposition":"PROVISIONAL_STATIC_PREPARATION_ONLY","flags":FLAGS,"noProductionPath":True,"noRealStudy":True,"noAcceptanceCredit":True};x={SCHEMA:schema(),CORPUS:c,CONTRACT:{**b,"contract":"AdvancedSurveyStaticPreparationContractV1","protocol":p,"corpusPath":CORPUS},EVIDENCE:{**b,"receipt":"AdvancedSurveyStaticPreparationEvidenceReceiptV1","protocolSHA256":sha(pretty(p)),"corpusSHA256":sha(pretty(c)),"result":"PASS_STATIC_PROVISIONAL","terminalValidationResult":None},BRAND:{**b,"manifest":"AdvancedSurveyBrandImpactManifestV1","impact":"NONE_SHIPPING","requiresMergeTimeS10_6Reconciliation":True}};x[MANIFEST]={**b,"manifest":"V23P06C03ToolingManifestV1","pathFence":list(OWNED),"generatedFiles":[{"path":k,"sha256":sha(pretty(v))}for k,v in x.items()],"canonicalGeneration":"MANIFEST_LAST_ATOMIC_REPLACE"};return x
def changed():
 if subprocess.run(["git","merge-base","--is-ancestor",BASE,"HEAD"],cwd=ROOT).returncode:raise ValueError("non-descendant")
 s={x.replace("\\","/")for x in git("diff","--name-only",BASE,"HEAD").splitlines()if x}
 for r in subprocess.run(["git","status","--porcelain=v1"],cwd=ROOT,check=True,capture_output=True,text=True).stdout.splitlines():
  p=r[3:].replace("\\","/");t=ROOT/p
  if t.is_dir():s.update(x.relative_to(ROOT).as_posix()for x in t.rglob("*")if x.is_file())
  elif p:s.add(p)
 return s
def counts():
 s=changed();return {"changedPathCount":len(s&set(OWNED)),"missingOwnedPathCount":sum(not(ROOT/x).is_file()for x in OWNED),"unownedChangedPathCount":len(s-set(OWNED)),"s10ReservationOverlapCount":overlap(),"fencePathCount":9}
def self_test():
 bad=[]
 for n,f in (("eav",lambda x:x.__setitem__("eav",True)),("writer",lambda x:x.__setitem__("newWriter",True)),("network",lambda x:x.__setitem__("network",True)),("payload",lambda x:x.__setitem__("customerPayload",True))):
  x=copy.deepcopy(protocol());f(x)
  try:validate(x)
  except ValueError:bad.append(n)
 if len(bad)!=4:raise ValueError("hostile mutation accepted")
 return {"result":"PASS_STATIC_PROVISIONAL","rejected":bad}
