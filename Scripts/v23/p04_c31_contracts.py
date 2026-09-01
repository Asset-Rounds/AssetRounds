from __future__ import annotations
import hashlib,json,os,re,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]; CARD="V23-P04-C31"; BASE="a7fefa4c09db2dccf65ee3d78ee551fb5752776f"; BTREE="e734020edc94c00b8f495c0bbae47ea639f056bb"; HEAD="82b8ba252a9529e3c1f58f625b60da268d1c2897"; CTREE="b1c7dba25c76da3382072dbdfa8c40cfbb7ee0be"; SEQ=518
CONTEXT="ceca32f9a59e22078ae414230ac2705c3ff8fd61aa43cd98b448ae85afd72d34"; FENCE="43a83321c1eaa33dc862f1f66123ab2b10840936f3e964c785db4b26ac38c480"; ALLOCATION="30b81d3bfece6ef7d6739f12df5d643b6304458a4b6b963e1d5894d48515adea"; PREREQ="a23e3d656ba6260fb6e08d4d92431b4fef551798a5f7f6a0d1b551b49e659798"; S10="274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"; FINAL_HASHES_SEALED=False
TEST="FieldEvidenceAppTests/V9_94OperationalHandoffExperienceTests.swift"; FIXTURE="FieldEvidenceAppTests/Fixtures/V23/Contacts/V23P04C31OperationalHandoffExperienceCorpusV1.json"; UI="FieldEvidenceAppUITests/V23_P04_C31OperationalHandoffExperienceUITests.swift"; SCHEMA="Scripts/v23/operational-handoff-experience.schema.json"; CONTRACT="docs/design/v23/tooling/V23P04C31OperationalHandoffExperienceContractV1.json"; EVIDENCE="docs/design/v23/tooling/V23P04C31OperationalHandoffExperienceEvidenceReceiptV1.json"; BRAND="docs/design/v23/tooling/V23P04C31BrandImpactManifestV1.json"; MANIFEST="docs/design/v23/tooling/V23-P04-C31-tooling-manifest.json"; SCRIPTS=("Scripts/v23/p04_c31_contracts.py","Scripts/v23/generate_p04_c31_contracts.py","Scripts/v23/verify_p04_c31_contracts.py"); OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST))
PATH_FENCE=("FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift","FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift","FieldEvidenceApp/Domain/Models/OperationalContactPersistenceModelsV1.swift","FieldEvidenceApp/Infrastructure/Platform/SystemHandoffAdapterV1.swift","FieldEvidenceApp/Application/Contacts/OperationalContactHandoffSessionV1.swift","FieldEvidenceApp/Features/Contacts/OperationalContactHandoffView.swift",TEST,FIXTURE,UI,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=("testDirectionsAndPartyChannelChooserUseExactCurrentTargetsWithoutPersistence", "testSystemAcceptanceIsTruthfullyBoundedAndCopyFallbackIsEphemeral", "testHostileTargetsAndStaleDeletedSourcesFailClosed", "testCancellationAndSystemRefusalRestoreRouteSelectionScrollAndFocus", "testProductionCompositionRequiresAccessAndUsesInjectableNativeBoundary")
PINS={"V23-P04-C31":(7452,"3ddd089a9704a2f806965e9cf50b5ff63b305acc47d3103feacebeaf8e54c77e"),"V21-P04-C31":(3907,"07d4ababb82c0e3be93da907ee9664769b3755e2adc656e268b5617676ca9a8a"),"V23-P04-C31-register":(310,"b53fcab7bb306d1fe6f3eeb99848700734905bc7260168c23f6d4eee9f990461")}; FLAGS={x:False for x in ("physicalDevice","native","hosted","activation","adoption","acceptance","publication","release")}
def pretty(v):return (json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def git(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def coord():
 p=os.environ.get("V23_P04_C31_COORDINATION_ROOT"); return None if p=="NONE" else Path(p) if p else ROOT.parent/"AssetRounds-v23-coordination"
def pins():
 if git("rev-parse",BASE+"^{tree}")!=BTREE:raise ValueError("base tree")
 b=subprocess.run(["git","show",f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"],cwd=ROOT,check=True,capture_output=True).stdout;f=subprocess.run(["git","show",f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"],cwd=ROOT,check=True,capture_output=True).stdout
 def section(n,i):
  m=re.search(rf"(?ms)^{i}### {re.escape(n)} —.*?(?=^{i}### |\Z)",b.decode());return m.group(0).encode() if m else (_ for _ in ()).throw(ValueError("missing "+n))
 at=f.index(b"P04-C31");row=f[f.rfind(b"\n",0,at)+1:f.index(b"\n",at)+1];vals={"V23-P04-C31":section("V23-P04-C31",""),"V21-P04-C31":section("V21-P04-C31","    "),"V23-P04-C31-register":row}
 for k,v in vals.items():
  if (len(v),sha(v))!=PINS[k]:raise ValueError("pin "+k)
 return [{"anchor":k,"utf8Length":len(v),"sha256":sha(v)} for k,v in vals.items()]
def authority():
 a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"coordinationTree":CTREE,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"fencePathCount":17,"existingPathCount":4,"newPathCount":13,"priorFenceProof":{"fenceCount":121,"priorOwnedPathCount":4,"authorizedOverlapEdgeCount":35,"unauthorizedOverlapCount":0,"s10ReservedOverlapCount":0},"s10OverlapCount":0,"frozenS10ReservationDigest":S10,"orderedPathFence":list(PATH_FENCE),"sourcePins":pins(),"finalHashesSealed":False}
 c=coord()
 if not c or not c.is_dir():
  m=json.loads((ROOT/MANIFEST).read_bytes())
  if m.get("authority")!=a:raise ValueError("portable authority")
  return a
 if (git("rev-parse","HEAD",cwd=c),git("rev-parse","HEAD^{tree}",cwd=c))!=(HEAD,CTREE):raise ValueError("coord identity")
 ctx=json.loads((c/f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json").read_bytes());f=json.loads((c/f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json").read_bytes());proof=f["priorFenceProof"]
 if (ctx.get("contextDigest"),f.get("fenceDigest"),ctx.get("ownerAuthorizedPathAllocationDigest"),ctx.get("provisionalPrerequisiteDigest"))!=(CONTEXT,FENCE,ALLOCATION,PREREQ) or tuple(f.get("allowedCreateOrReplacePaths",()))!=PATH_FENCE or (len(f["existingPaths"]),len(f["newPaths"]),proof["fenceCount"],proof["authorizedOverlapEdgeCount"],proof["unauthorizedOverlapCount"],proof["s10ReservedOverlapCount"])!=(4,13,121,35,0,0) or f.get("frozenS10ReservationDigest")!=S10:raise ValueError("fence authority")
 return a
def rows():
 r=[]
 for p in PATH_FENCE:
  if p not in OWNED:
   q=ROOT/p;r.append({"path":p,"status":"SOURCE_PRESENT" if q.is_file() else "SOURCE_MISSING","sha256":sha(q.read_bytes()) if q.is_file() else None})
 return r,all(x["status"]=="SOURCE_PRESENT" for x in r)
def counts():
 def names(*args): return {x.replace("\\","/") for x in git(*args).splitlines() if x}
 changed=names("diff","--name-only",BASE,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--cached","--name-only")|names("ls-files","--others","--exclude-standard")|OWNED
 allowed=set(PATH_FENCE)
 return {"changedPathCount":len(changed&allowed),"missingPathCount":sum(not(ROOT/p).is_file() for p in allowed-OWNED),"unownedChangedPathCount":len(changed-allowed),"s10ReservationOverlapCount":0}
def documents():
 a=authority();r,ready=rows();base={"schema":"V23P04C31OperationalHandoffExperienceToolingV1","cardID":CARD,"authority":a,"sourceRows":r,"sourceReady":ready,"finalHashesSealed":False,"flags":FLAGS,"selectors":list(SELECTORS),"lifecycle":{"persistentSchema":"V53","activeModelCount":168,"newDurableFamilyCount":0,"newWriterCount":0,"newMigrationCount":0,"sessionPersistence":"NONPERSISTENT"}}
 contract={**base,"contract":"OperationalHandoffExperienceContractV1","requirements":{"sitePartyChooserEphemeral":True,"actions":["DIRECTIONS","CALL","TEXT","EMAIL"],"safeCopyFallbackOnly":True,"noGeocoderTrackingHistory":True,"truthfulSystemAcceptance":True}}
 evidence={**base,"receipt":"OperationalHandoffExperienceEvidenceReceiptV1"};brand={"schema":"BrandImpactManifestV1","cardID":CARD,"flags":FLAGS,"finalHashesSealed":False,"requiresAcceptedS10_6Reconciliation":True};files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))};manifest={"schema":"V23P04C31ToolingManifestV1","cardID":CARD,"authority":a,"pathFence":list(PATH_FENCE),"files":[{"path":p,"sha256":h} for p,h in files.items()],"sourceRows":r,"flags":FLAGS,"finalHashesSealed":False};return {CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:manifest}
def semantics(ready):
 if not ready:return
 t="\n".join((ROOT/p).read_text(encoding="utf-8",errors="ignore") for p in PATH_FENCE if p.endswith(".swift") or p.endswith(".json"))
 for x in ("OperationalContact","SystemHandoff","MKMapItem","DIRECTIONS","CALL","TEXT","EMAIL","NONPERSISTENT"):
  if x not in t:raise ValueError("semantic "+x)
 for p in (TEST,UI):
  for s in SELECTORS:
   if s not in (ROOT/p).read_text(encoding="utf-8"):raise ValueError("selector "+s)
