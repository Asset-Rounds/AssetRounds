from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";ROOT=Path(__file__).resolve().parents[2];COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C18";BASE="19ecc7ff4e91a488ac64fa4e075baa216417b006";HEAD="42f244e435b0eab376208afb26ab055fe2ba751d";CTREE="bab52121302fd40051fe21a750cefd5069074ac4";CONTEXT="4bb7885f6309b76bbc187ba4c4b6aba65d6776064dda5ce5ad646f676354a722";FENCE="19be0c8fd3afeba2fbf0c5090ff71bcda220e134b0c7292aad00eadb9f2e9c08";SEQ=460;FINAL_HASHES_SEALED=True
SCHEMA="Scripts/v23/lighting-night-workflow.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C18LightingNightWorkflowContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C18LightingNightWorkflowEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C18BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C18-tooling-manifest.json";SCRIPTS=("Scripts/v23/p04_c18_contracts.py","Scripts/v23/generate_p04_c18_contracts.py","Scripts/v23/verify_p04_c18_contracts.py");GENERATED=(SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST);OWNED=set(SCRIPTS+GENERATED)
SELECTORS=("testV23P04C18G01DayNightDeltaPreservesExpectedObservedAndExactFrontiers","testV23P04C18A01FreshNightSafetyAndIssueSpecificClosureFailClosed","testV23P04C18H01FortyFiveHostileMeasurementGroupingAndClaimCasesFailClosed","testV23P04C18I01CanonicalWriterInterruptionRecoveryIsIdempotent","testV23P04C18R01BackupClonePatrolSearchAndReportRemainExactAndDerived");FLAGS={x:False for x in("activation","native","hosted","adoption","acceptance","release","publish","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def run(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def authority():
 c=json.loads((COORD/"contexts/V23-P04-C18-attempt-1/BootstrapCardContextV1.json").read_bytes());f=json.loads((COORD/"contexts/V23-P04-C18-attempt-1/BootstrapPathFenceV1.json").read_bytes());p=f["priorFenceProof"]
 if(run("rev-parse","HEAD",cwd=COORD),run("rev-parse","HEAD^{tree}",cwd=COORD))!=(HEAD,CTREE):raise ValueError("C18 coordination differs")
 if c.get("contextDigest")!=CONTEXT or f.get("fenceDigest")!=FENCE or (len(c["existingPaths"]),len(c["newPaths"]),len(f["allowedCreateOrReplacePaths"]),p["unauthorizedOverlapCount"],p["s10ReservedOverlapCount"])!=(49,15,64,0,0):raise ValueError("C18 authority/fence differs")
 return c,f
def source_paths():_,f=authority();return tuple(x for x in f["allowedCreateOrReplacePaths"]if x not in OWNED)
def rows():
 r=[]
 for p in source_paths():
  b=(ROOT/p).read_bytes()if(ROOT/p).is_file()else b"";r.append({"path":p,"status":"SOURCE_PRESENT"if b else"SOURCE_MISSING","sha256":sha(b)if b else None})
 return r,all(x["status"]=="SOURCE_PRESENT"for x in r)
def counts():
 _,f=authority();own=set(f["allowedCreateOrReplacePaths"]);g=lambda *a:{x.replace("\\","/")for x in run(*a).splitlines()if x};x=g("diff","--name-only",BASE,"HEAD")|g("diff","--name-only","HEAD")|g("ls-files","--others","--exclude-standard")|OWNED;return{"changedPathCount":len(x&own),"missingPathCount":sum(not(ROOT/p).is_file()for p in own-OWNED),"unownedChangedPathCount":len(x-own),"s10ReservationOverlapCount":len(own&set(f["activeS10ReservedPaths"]))}
def semantics(ready):
 if not ready:return
 by={p:(ROOT/p).read_text(encoding="utf-8",errors="replace")for p in source_paths()};t="\n".join(by.values());need=("LightingNightWorkflowV1","LightingNightWorkflowRowV1","PersistentSchemaV53.models.count == 168","MutationJournalStoreV1","MutationReceiptRecoveryServiceV1","unrounded","uncertainty","inconclusive","9c6bb0a73e59bcd49485940ffd33ad489d96514761a39e4706872f0fa306df0a","kindIDs.count == 453","V53BackupLightingNightWorkflowRecordV1","lightingNightWorkflows","LightingNightWorkflowBackupEnrollmentV1.recordsSchemaVersion == 52","XCTSkip")
 m=[x for x in need if x not in t]
 if m:raise ValueError("C18 source semantics missing:"+",".join(m))
 test=by.get("FieldEvidenceAppTests/V9_81LightingNightWorkflowTests.swift","");ui=by.get("FieldEvidenceAppUITests/V23_P04_C18LightingNightWorkflowUITests.swift","");night=by.get("FieldEvidenceApp/Domain/Lighting/LightingNightWorkflowContractsV1.swift","")
 for selector in SELECTORS:
  if selector not in test:raise ValueError("C18 selector missing:"+selector)
 if "EXACT_ROUND_SESSION_ITEM_COMPLETION_REFERENCE" not in test or "RoundSessionReferenceV1" not in test or "LightingPatrolReferenceV1" not in test or "itemID:" not in test or "completion:" not in test:raise ValueError("C18 patrol closure is not exact RoundSession item/completion provenance")
 if "patrolSHA256" in test or "patrolSHA256" in night:raise ValueError("C18 patrol must not use opaque patrol SHA")
 reopen=("result == .resolvedForRecordedScope","Set(reopenedRecheckIDs).count == reopenedRecheckIDs.count","predecessor.rechecks.first(where:","$0.eventID == reopen.supersededRecheckEventID","$0.eventSHA256 == reopen.supersededRecheckSHA256","matches.count == 1")
 missing_reopen=[token for token in reopen if token not in night]
 if missing_reopen:raise ValueError("C18 reopen integrity missing:"+",".join(missing_reopen))
 mutation=by.get("FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift","");backup=by.get("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","")
 if night.count("workflowSHA256 = try LightingCanonicalCodecV1.sha256(Basis(")!=1:raise ValueError("C18 workflow SHA must have one canonical assignment")
 reversal=("policies.count == 61","policies.count == WorkspaceCommandKindV1.allCases.count","Set(policies.map(\\.commandKind)).count == policies.count",".applyLightingNightWorkflow")
 missing_reversal=[token for token in reversal if token not in mutation]
 if missing_reversal:raise ValueError("C18 reversal registry is not exact 61/61:"+",".join(missing_reversal))
 if "Set(keys).count == keys.count" not in backup or "lightingDayInventoryWorkflows" not in backup or "lightingNightWorkflows" not in backup:raise ValueError("C18 backup unique IDs or C17/C18 families missing")
 starts=[index for index in range(len(backup)) if backup.startswith("func replacing",index)]
 helpers=[backup[start:(starts[position+1] if position+1<len(starts) else len(backup))] for position,start in enumerate(starts)]
 if not helpers or any("lightingDayInventoryWorkflows:" not in helper or "lightingNightWorkflows:" not in helper for helper in helpers):raise ValueError("C18 replacement backup helper dropped C17/C18 workflow family")
 if ui.count("XCTSkip")!=5 or "accepted S10.6 reconciliation" not in ui:raise ValueError("C18 UI skip/reconciliation evidence missing")
 if any(x in t.lower()for x in("photometry adequate","diagnosis claim","lighting adequacy")):raise ValueError("C18 prohibited claim")
def documents():
 c,f=authority();r,ready=rows();n=counts();a={"cardID":CARD,"appBaseHead":BASE,"coordinationHead":HEAD,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"finalHashesSealed":FINAL_HASHES_SEALED,"fencePathCount":64,"existingPathCount":49,"newPathCount":15,"s10OverlapCount":0};s={"sourceReady":ready,"sourceRows":r,"counts":n,"selectors":list(SELECTORS)};scope={"persistentSchema":"V53","activeModelCount":168,"durableRecordFamilyCount":1,"recordsSchemaVersion":52,"separateBackupFamily":"V53BackupLightingNightWorkflowRecordV1","persistentKindUniverse":{"count":453,"sha256":"9c6bb0a73e59bcd49485940ffd33ad489d96514761a39e4706872f0fa306df0a","priorCount":451},"patrolProvenance":"EXACT_ROUND_SESSION_ITEM_COMPLETION_REFERENCE","statusFlags":FLAGS};co={"schema":"V23P04C18LightingNightWorkflowContractV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"testSelectors":list(SELECTORS),"statusFlags":FLAGS};ev={"schema":"V23P04C18LightingNightWorkflowEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"sourceProjection":s,"contractDigest":sha(pretty(co)),"statusFlags":FLAGS};br={"schema":"V23P04C18BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS};m={"schema":"V23P04C18ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":a,"pathFence":f["allowedCreateOrReplacePaths"],"files":[{"path":p,"sha256":sha(pretty(v))}for p,v in((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],"sources":r,"counts":n,"toolingPaths":[*SCRIPTS,*GENERATED],"statusFlags":FLAGS};return{CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
