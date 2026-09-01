#!/usr/bin/env python3
"""Fail-closed provisional static contracts for V23-P04-C16."""
from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1"
ROOT=Path(__file__).resolve().parents[2];COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C16";BASE="eadd255b885523ae38d139073f515e301f044a35";TREE="368d53a50f0c457002bc72d9b7da434298bcc173";HEAD="c9dfba19cd369a2df5b589d5c32dcc632e8e524d";CTREE="d763514d0eb511e351bbf1b794968bbb7a2bf311";CONTEXT="ca644de68e6b8dfb66418b0c0deb497a501230a252c4803f4f35bcba1e3a4b69";FENCE="e57f96435bb30dd026eb793af5ac86b18938322b2c9d59c376e9e418570bb55e";SEQ=452;FINAL_HASHES_SEALED=True
SCHEMA="Scripts/v23/task-first-shell.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C16TaskFirstShellContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C16TaskFirstShellEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C16BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C16-tooling-manifest.json";SCRIPTS=("Scripts/v23/p04_c16_contracts.py","Scripts/v23/generate_p04_c16_contracts.py","Scripts/v23/verify_p04_c16_contracts.py");GENERATED=(SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=("testV23P04C16G01TypedSettingsAndTaskFirstShell","testV23P04C16A01PracticeWorkspaceIsolationAndReset","testV23P04C16H01AccessGatePrecedesEveryContentRead","testV23P04C16I01InterruptedInstallResumeIsIdempotent","testV23P04C16R01BackupRestoreCloneAndReportRebuildPracticeState");FLAGS={x:False for x in("activation","native","hosted","adoption","acceptance","release","publish","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")};OWNED=set(SCRIPTS+GENERATED)
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def run(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def load(p):return json.loads((COORD/p).read_bytes())
def authority():
 c=load("contexts/V23-P04-C16-attempt-1/BootstrapCardContextV1.json");f=load("contexts/V23-P04-C16-attempt-1/BootstrapPathFenceV1.json");proof=f["priorFenceProof"]
 if (run("rev-parse","HEAD",cwd=COORD),run("rev-parse","HEAD^{tree}",cwd=COORD))!=(HEAD,CTREE):raise ValueError("C16 coordination authority differs")
 if c.get("contextDigest")!=CONTEXT or f.get("fenceDigest")!=FENCE or c.get("executionPredecessor",{}).get("acceptedCandidateHead")!=BASE or c.get("executionPredecessor",{}).get("acceptedCandidateTree")!=TREE:raise ValueError("C16 authority pin differs")
 if len(c["existingPaths"])!=53 or len(c["newPaths"])!=19 or len(f["allowedCreateOrReplacePaths"])!=72 or proof["authorizedOverlapCount"]!=46 or proof["unauthorizedOverlapCount"]!=0 or proof["s10ReservedOverlapCount"]!=0:raise ValueError("C16 fence proof differs")
 return c,f
def source_paths():
 _,f=authority();return tuple(p for p in f["allowedCreateOrReplacePaths"] if p not in OWNED)
def rows():
 r=[]
 for p in source_paths():
  b=(ROOT/p).read_bytes()if(ROOT/p).is_file()else b"";r.append({"path":p,"status":"SOURCE_PRESENT"if b else"SOURCE_MISSING","sha256":sha(b)if b else None})
 return r,all(x["status"]=="SOURCE_PRESENT"for x in r)
def counts():
 _,f=authority();own=set(f["allowedCreateOrReplacePaths"]);clean=lambda *a:{x.replace("\\","/")for x in run(*a).splitlines()if x};changed=clean("diff","--name-only",BASE,"HEAD")|clean("diff","--name-only","HEAD")|clean("ls-files","--others","--exclude-standard")|OWNED
 return {"changedPathCount":len(changed&own),"missingPathCount":sum(not(ROOT/p).is_file()for p in own-OWNED),"unownedChangedPathCount":len(changed-own),"s10ReservationOverlapCount":len(own&set(f["activeS10ReservedPaths"]))}
def _contains(by,path,*tokens):
 missing=[x for x in tokens if x not in by[path]]
 if missing:raise ValueError("C16 scoped semantics missing "+path+":"+",".join(missing))
def semantics(ready):
 if not ready:return
 by={p:(ROOT/p).read_text(encoding="utf-8",errors="replace")for p in source_paths()}
 _contains(by,"FieldEvidenceApp/Application/Ports/AppAccessPortsV1.swift","protocol AppAccessGatePortV1","requireContentAccess","AppAccessContentPermitV1")
 _contains(by,"FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift","makePreAuthenticationIngressStore","OwnedStorageLedgerProtectedIngressEffectV1","c16AccessGateProductionAdoptionComplete = false","requireContentAccess")
 _contains(by,"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","PersistentSchemaV51","PracticeWorkspaceProvenanceRowV1","models.count == 166","PersistentSchemaV50.models.count + 1")
 _contains(by,"FieldEvidenceApp/Domain/Models/WorkspaceExperiencePersistenceModelsV1.swift","PracticeWorkspaceProvenanceRowV1","totalModelCount = 166","cloneAndForkOmitPracticeProvenance = true")
 _contains(by,"FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift","WorkspaceWriterV1","MutationJournalStoreV1","effectBeforeReceiptRecoveryQueriesExistingMutationID")
 _contains(by,"FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift","MutationJournalStoreV1","recover")
 _contains(by,"FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift","recover","validateRecovered")
 _contains(by,"FieldEvidenceApp/Infrastructure/WorkspaceExperience/WorkspaceExperienceLifecycleAdapterV1.swift","WorkspaceWriterV1","commitWorkspaceExperience","replaceRestorePreservesExactProvenance = true","practiceResetUsesWholeWorkspaceDeletion = true","practiceResetAutomaticallyReinstalls = false","searchProjectionIsRebuildable = true")
 _contains(by,"FieldEvidenceApp/Domain/WorkspaceExperience/WorkspaceExperienceContractsV1.swift","canonicalShellOrder","canonicalOrder","PracticeWorkspaceResetPlanV1","ConfigurationClonePlanV1","PracticeShareConfirmationV1","PRACTICE — NOT FOR FIELD USE")
 _contains(by,"FieldEvidenceApp/Domain/Security/AppAccessContractsV1.swift","WorkspaceExperienceAppAccessAdoptionBoundaryV1","productionCallerAdoptionComplete = false")
 _contains(by,"FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","cloneAndForkOmitProvenance = true","resetRequiresWholeWorkspaceDeletion = true","resetAutomaticallyReinstalls = false")
 _contains(by,"FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift","replaceExisting","case .clone, .fork","reconcileRestoreAndPrivateSystemDiscoveryAtStartup")
 _contains(by,"FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift","PracticeShareConfirmationV1","mandatoryWatermark","historicDisplayIsFrozen","requireContentAccess(for: .render)","permit.surface == .render")
 _contains(by,"FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift","performBlindStartupHygieneEffect","ProtectedIngressStartupHygieneReceiptV1","afterPrepare","afterEffect","afterReceipt","interruptIfTriggered")
 _contains(by,"FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift","shell.practice")
 _contains(by,"FieldEvidenceAppUITests/V23_P04_C16ShellAccessibilityLocalizationUITests.swift","XCTSkip","accepted S10.6")
 tests=by["FieldEvidenceAppTests/V9_79WorkspaceExperienceTests.swift"]
 if any(x not in tests for x in SELECTORS)or tests.count("testV23P04C16")!=5:raise ValueError("C16 exact five selector tests differ")
 if any(x not in tests for x in("ingressHygieneFailureInjection: boundary",".afterPrepare, .afterEffect, .afterReceipt","performBlindStartupHygieneEffect","readBlindStartupHygieneReceiptEffect","reconcileProtectedIngressHygiene","renderer.renderPendingReport")):raise ValueError("C16 selector production seam/fault coverage differs")
 fixture=json.loads(by["FieldEvidenceAppTests/Fixtures/V21/WorkspaceExperience/V21P04C16WorkspaceExperienceCorpusV1.json"])
 if any(not isinstance(fixture.get(k),list)or not fixture[k] for k in("golden","alternate","hostile","interruption","recovery")):raise ValueError("C16 fixture G/A/H/I/R matrix differs")
def validate_generated(v):
 common={"schema","schemaVersion","cardID","provisional","authority","statusFlags"}; schema=v.get("schema")
 allowed={"V23P04C16TaskFirstShellContractV1":common|{"semantics","sourceProjection","testSelectors"},"V23P04C16TaskFirstShellEvidenceReceiptV1":common|{"sourceProjection","contractDigest"},"V23P04C16BrandImpactManifestV1":common|{"semantics","sourceProjection","uiAdoptionSkipped","uiAcceptanceCredit"},"V23P04C16ToolingManifestV1":common|{"finalHashesSealed","pathFence","files","sources","counts","toolingPaths"}}
 if schema not in allowed or set(v)!=allowed[schema] or v.get("schemaVersion")!=1 or v.get("cardID")!=CARD or v.get("provisional")is not True or v.get("statusFlags")!=FLAGS:raise ValueError("C16 generated root closure differs")
 if set(v["authority"])!={"cardID","appBaseHead","appBaseTree","coordinationHead","sequence","contextDigest","pathFenceDigest","finalHashesSealed","fencePathCount","existingPathCount","newPathCount","priorFenceCount","priorOwnedPathCount","authorizedOverlapCount","unauthorizedOverlapCount","s10OverlapCount"}:raise ValueError("C16 generated authority closure differs")
 if "sourceProjection" in v and (set(v["sourceProjection"])!={"sourceReady","sourceRows","counts","selectors"} or len(v["sourceProjection"]["sourceRows"])!=64):raise ValueError("C16 generated source projection closure differs")
def documents():
 c,f=authority();r,ready=rows();n=counts();a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":TREE,"coordinationHead":HEAD,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"finalHashesSealed":FINAL_HASHES_SEALED,"fencePathCount":72,"existingPathCount":53,"newPathCount":19,"priorFenceCount":3,"priorOwnedPathCount":273,"authorizedOverlapCount":46,"unauthorizedOverlapCount":0,"s10OverlapCount":0};s={"sourceReady":ready,"sourceRows":r,"counts":n,"selectors":list(SELECTORS)};scope={"persistentSchema":"V51","activeModelCount":166,"durableRecordFamilyCount":1,"fourRootsOnly":True,"searchScopes":["settings","taskFirstShell","practiceWorkspace","resume","report"],"statusFlags":FLAGS};co={"schema":"V23P04C16TaskFirstShellContractV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"testSelectors":list(SELECTORS),"statusFlags":FLAGS};ev={"schema":"V23P04C16TaskFirstShellEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"sourceProjection":s,"contractDigest":sha(pretty(co)),"statusFlags":FLAGS};br={"schema":"V23P04C16BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS};m={"schema":"V23P04C16ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":a,"pathFence":f["allowedCreateOrReplacePaths"],"files":[{"path":p,"sha256":sha(pretty(v))}for p,v in((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],"sources":r,"counts":n,"toolingPaths":[*SCRIPTS,*GENERATED],"statusFlags":FLAGS}
 for x in(co,ev,br,m):validate_generated(x)
 return{CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
