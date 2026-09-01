from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
ROOT=Path(__file__).resolve().parents[2]; COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C20"; BASE="1867095815c1b8b5f9fd2be0df884303fa5447e3"; BTREE="ed68387293bd76ac892cd27c6c25a4f58ebdd050"; HEAD="4d8c5b95986f8e9220db3a8ca77d4873b7ad31e3"; CTREE="3608c8e1e6fe33db7253bb485e47c11bb3da05bf"; CONTEXT="a6a8a7f3a2c206605526b475199bedb5bc9cafc13fc8b90c97b096eb8e91744e"; FENCE="07541220f2c3ba690b954234b14073f15277775e1944e2ddc9c763541cb81636"; ALLOCATION="ce937444460ff08c13fc6000c20ece559cf6795903a225617532f37f28fec8f0"; PREREQ="8b6af1031df3fe4c859a19a3027c73c48a4046198b73b5c991b647a9a18ce867"; TRANSITION="075b5c78c24fac90f2747bd42ad31ef89972d9463f5b7deb44dcb0e304bea2f5"; LEDGER="2ab7e90162c84e64038fa4cefaba5cbb6f1a6f88e8d5d30b52030d9367bea971"; PROJECTION="7e07e153b2d11dd0060ababb4b7c93c341a17b5a9e2c613df1d14fe7ed4f492e"; SEQ=467; FINAL_HASHES_SEALED=True
SCHEMA="Scripts/v23/guided-survey-workflow.schema.json"; CONTRACT="docs/design/v23/tooling/V23P04C20GuidedSurveyWorkflowContractV1.json"; EVIDENCE="docs/design/v23/tooling/V23P04C20GuidedSurveyWorkflowEvidenceReceiptV1.json"; BRAND="docs/design/v23/tooling/V23P04C20BrandImpactManifestV1.json"; MANIFEST="docs/design/v23/tooling/V23-P04-C20-tooling-manifest.json"; SCRIPTS=("Scripts/v23/p04_c20_contracts.py","Scripts/v23/generate_p04_c20_contracts.py","Scripts/v23/verify_p04_c20_contracts.py"); GENERATED=(SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST); OWNED=set(SCRIPTS+GENERATED)
SELECTORS=("testV23P04C20G01TwoReleasesAuthorRunReviewPublishAndOfflineReport","testV23P04C20A01AllClosedFieldsConditionalRepeatUnknownAndPoseParity","testV23P04C20H01HostileDefinitionsImportsConflictsAndPrivacyFailClosed","testV23P04C20I01PauseKillResumeAndPublishRecoveryRemainIdempotent","testV23P04C20R01RestoreSearchReportAndPromotionPreserveFrozenPublication")
FLAGS={x:False for x in("activation","native","hosted","adoption","acceptance","release","publish","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}
PINS=(("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md","V23-P04-C20",7333,"dff1da05b257e4233ebaa4d0bf4c92957a63008fda3cc99744b1f1c831845201"),("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md","V21-P04-C20",5862,"04e6423fccad7e14ee10306aa9e852ef26be46a2e41ace73d2ff5034b43545ff"),("docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md","V23-P04-C20-register",342,"a2358435b6bb48cb5f21dab8020c49e4696900a6be82e74d0e2bffc77182bc6e"))
def pretty(v): return (json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v): return hashlib.sha256(v).hexdigest()
def git(*a,cwd=ROOT): return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def authority():
 c=json.loads((COORD/"contexts/V23-P04-C20-attempt-1/BootstrapCardContextV1.json").read_bytes());f=json.loads((COORD/"contexts/V23-P04-C20-attempt-1/BootstrapPathFenceV1.json").read_bytes());p=f["priorFenceProof"]
 if (git("rev-parse","HEAD",cwd=COORD),git("rev-parse","HEAD^{tree}",cwd=COORD))!=(HEAD,CTREE): raise ValueError("C20 coordination differs")
 if (c["contextDigest"],f["fenceDigest"],c["ownerAuthorizedPathAllocationDigest"],c["provisionalPrerequisiteDigest"])!=(CONTEXT,FENCE,ALLOCATION,PREREQ): raise ValueError("C20 authority digest differs")
 if (len(c["existingPaths"]),len(c["newPaths"]),len(f["allowedCreateOrReplacePaths"]),p["authorizedOverlapCount"],p["unauthorizedOverlapCount"],p["s10ReservedOverlapCount"])!=(15,14,29,57,0,0): raise ValueError("C20 fence proof differs")
 if c["repository"]!={"appBaseHead":BASE,"appBaseTree":BTREE}: raise ValueError("C20 app base differs")
 return c,f
def source_paths(): _,f=authority(); return tuple(x for x in f["allowedCreateOrReplacePaths"] if x not in OWNED)
def rows():
 r=[]
 for p in source_paths():
  b=(ROOT/p).read_bytes() if (ROOT/p).is_file() else b""; r.append({"path":p,"status":"SOURCE_PRESENT" if b else "SOURCE_MISSING","sha256":sha(b) if b else None})
 return r,all(x["status"]=="SOURCE_PRESENT" for x in r)
def counts():
 _,f=authority(); own=set(f["allowedCreateOrReplacePaths"]); parse=lambda s:{x.replace("\\","/") for x in s.splitlines() if x}; x=parse(git("diff","--name-only",BASE,"HEAD"))|parse(git("diff","--name-only","HEAD"))|parse(git("diff","--cached","--name-only"))|parse(git("ls-files","--others","--exclude-standard"))|OWNED
 return {"changedPathCount":len(x&own),"missingPathCount":sum(not(ROOT/p).is_file() for p in own-OWNED),"unownedChangedPathCount":len(x-own),"s10ReservationOverlapCount":len(own&set(f["activeS10ReservedPaths"]))}
def source_pins():
 for path,anchor,length,digest in PINS:
  # Hydration pins are defined over the accepted app-base blob, not the
  # potentially CRLF-normalized shared working tree.
  data=subprocess.run(["git","show",f"{BASE}:{path}"],cwd=ROOT,check=True,capture_output=True).stdout
  if anchor=="V23-P04-C20": start=data.index(b"### V23-P04-C20 "); end=data.find(b"\n### V23-",start+1)
  elif anchor=="V21-P04-C20": start=data.index(b"    ### V21-P04-C20 "); end=data.find(b"\n    ### V21-P",start+1)
  else: start=data.index(b'| 108 | <a id="v23-p04-c20-register"'); end=data.index(b"\n",start)
  part=data[start:] if end<0 else data[start:end+1]
  if len(part)!=length or sha(part)!=digest: raise ValueError("C20 source pin differs:"+anchor)
def semantics(ready):
 if not ready:return
 by={p:(ROOT/p).read_text(encoding="utf-8",errors="replace") for p in source_paths()}; schema=(ROOT/"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift").read_text(encoding="utf-8",errors="replace"); t="\n".join((*by.values(),schema)); test=by.get("FieldEvidenceAppTests/V9_83GuidedSurveyFlowTests.swift",""); ui=by.get("FieldEvidenceAppUITests/V23_P04_C20GuidedSurveyFlowUITests.swift","")
 need=("GuidedSurveyFlowV1","GuidedSurveyFlowCoordinatorV1","GuidedSurveyFlowLifecycleAdapterV1","SurveyDefinitionCoordinatorV1","SurveySessionCoordinatorV1","SurveyFieldKindV1","SurveyFactPayloadV1","PersistentSchemaV53","XCTSkip")
 miss=[x for x in need if x not in t]
 if miss: raise ValueError("C20 source semantics missing:"+','.join(miss))
 if any(s not in test for s in SELECTORS): raise ValueError("C20 exact selector missing")
 if "45" not in test or "45" not in by.get("FieldEvidenceAppTests/Fixtures/V23/Surveys/V23P04C20GuidedSurveyFlowCorpusV1.json",""): raise ValueError("C20 hostile corpus must be exactly 45")
 if ui.count("XCTSkip")!=5: raise ValueError("C20 UI skip count differs")
 required=("QUARANTINE","FRESH_DRAFT","StreamingArchive","favorite","recent","publish","retire","duplicate","import","resume","promotion","report","search","backup","restore","clone","fork","delete","erase","replay")
 miss=[x for x in required if x not in t]
 if miss: raise ValueError("C20 lifecycle semantics missing:"+','.join(miss))
 policy=by.get("FieldEvidenceApp/Domain/Workflow/GuidedSurveyFlowContractsV1.swift","")
 if not all(x in policy for x in ("allowsGenericEAV = false","allowsScripting = false","allowsPassFail = false","!allowsGenericEAV, !allowsScripting, !allowsPassFail")): raise ValueError("C20 closed-field policy violated")
 if any(x in policy for x in ("[String: Any]","scriptExecution")) or any(x in t for x in ("new PersistentModel","SurveyWorkflowReceiptRow")): raise ValueError("C20 storage/claim prohibition violated")
def documents():
 c,f=authority(); r,ready=rows(); n=counts(); a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"coordinationTree":CTREE,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"transitionDigest":TRANSITION,"ledgerDigest":LEDGER,"projectionDigest":PROJECTION,"finalHashesSealed":FINAL_HASHES_SEALED,"fencePathCount":29,"existingPathCount":15,"newPathCount":14,"authorizedOverlapCount":57,"s10OverlapCount":0}; sem={"persistentSchema":"V53","activeModelCount":168,"newDurableRecordCount":0,"newDurableFamilies":[],"derivedStates":["GuidedSurveyFlowV1","SurveyAuthoringPolicyV1","SurveyReviewStateV1"],"closedFieldSet":"SurveyFieldKindV1/SurveyFactPayloadV1","deviceLocalOnly":["favorites","recents"],"importMode":"QUARANTINE_THEN_FRESH_DRAFT","export":"StreamingArchive","statusFlags":FLAGS}; proj={"sourceReady":ready,"sourceRows":r,"counts":n,"selectors":list(SELECTORS),"sourcePins":[{"path":p,"anchor":a,"utf8Length":l,"sha256":d} for p,a,l,d in PINS]}; co={"schema":"V23P04C20GuidedSurveyWorkflowContractV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":sem,"sourceProjection":proj,"testSelectors":list(SELECTORS),"statusFlags":FLAGS}; ev={"schema":"V23P04C20GuidedSurveyWorkflowEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"sourceProjection":proj,"contractDigest":sha(pretty(co)),"statusFlags":FLAGS}; br={"schema":"V23P04C20BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":sem,"sourceProjection":proj,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS}; m={"schema":"V23P04C20ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":a,"pathFence":f["allowedCreateOrReplacePaths"],"files":[{"path":p,"sha256":sha(pretty(v))} for p,v in ((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],"sources":r,"counts":n,"toolingPaths":[*SCRIPTS,*GENERATED],"statusFlags":FLAGS}; return {CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
