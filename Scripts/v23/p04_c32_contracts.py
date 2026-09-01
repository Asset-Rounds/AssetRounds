from __future__ import annotations
import hashlib,json,os,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];CARD="V23-P04-C32";BASE="e08f2016afc775fc416354a0db0cd01b3713cb56";BTREE="0576981d6c5eb066f9b5f45f38c84bb2d86f927a";HEAD="f90855c537dccb61cf59943d48bd22117ce17e9f";CTREE="cf9584631565c1ef756458c614a012caf973161a";SEQ=525;CONTEXT="99f301ad119a2506d8c717a8e8d9c8767f3dd3358cbb69ce26f80168121ac937";FENCE="f374f1432016abf7e2123b5a7014bf974cf9efacffb3cc6b8251dc79264bae6b";ALLOCATION="5fc3408e0ec9917d4c22d2ccc77e64c70841a256e663bd5bd2fefd8f0544160b";PREREQ="b90decd22b0fd7cde25f6e3521bbb4a48769cbd6a93ca9726140d09cc0935f5d";S10="274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a";FINAL_HASHES_SEALED=False
TEST="FieldEvidenceAppTests/V9_95PartyContactSiteRoleImportTests.swift";FIXTURE="FieldEvidenceAppTests/Fixtures/V23/ImportExport/V23P04C32PartyContactSiteRoleImportCorpusV1.json";UI="FieldEvidenceAppUITests/V23_P04_C32PartyContactSiteRoleImportUITests.swift";SCHEMA="Scripts/v23/party-contact-site-role-import.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C32PartyContactSiteRoleImportContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C32PartyContactSiteRoleImportEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C32BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C32-tooling-manifest.json";SCRIPTS=("Scripts/v23/p04_c32_contracts.py","Scripts/v23/generate_p04_c32_contracts.py","Scripts/v23/verify_p04_c32_contracts.py");OWNED=set((*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST))
PATH_FENCE=("FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift","FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift","FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift","FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift","FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift","FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift","FieldEvidenceAppTests/V9_23PartyAccountabilityTests.swift","FieldEvidenceAppTests/V9_53OperationalContactTests.swift","FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift","FieldEvidenceAppTests/S6_3BackupValidationTests.swift","FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift","FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift","FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift","FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift","FieldEvidenceApp/Domain/ImportExport/PartyContactSiteRoleImportMutationV1.swift","FieldEvidenceApp/Application/ImportExport/PartyContactSiteRoleImportCoordinatorV1.swift","FieldEvidenceApp/Features/AssetImport/PartyContactSiteRoleImportView.swift",TEST,FIXTURE,UI,*SCRIPTS,SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST)
SELECTORS=("testV23P04C32G01PreviewFirstMultiFilePartyContactAndSiteRoleMigrationGolden","testV23P04C32A01ExplicitKeyBindingSharedRoleCorrectionAndReversalAlternate","testV23P04C32H01HostileIdentityUnicodeFormulaAndBudgetFailClosed","testV23P04C32I01CancellationChunkInterruptionAndRestoreNoPartialClaim","testV23P04C32R01ReceiptReplayBackupRestoreJournalReplicationAndPrivacyRecovery")
PINS={"V23-P04-C32":(7519,"f83e1d4b88b1e22a6697233a12c8e171312d05ca605b3eeef51fb9fa3efe0bfb"),"V21-P04-C32":(4168,"ba66fc4faeea2e1bc09ea5972082130f7d2d7eca1373667f04631055b181f37c"),"V23-P04-C32-register":(319,"d33f4b4c13fdb7dc95c6993e287808e385cb722864e82b4906c7393d6599a939")};FLAGS={x:False for x in("physicalDevice","native","hosted","activation","adoption","acceptance","publication","release")}
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def git(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def _coord():
 p=os.environ.get("V23_P04_C32_COORDINATION_ROOT");return None if p=="NONE" else(Path(p)if p else ROOT.parent/"AssetRounds-v23-coordination")
def pins():
 if git("rev-parse",BASE+"^{tree}")!=BTREE:raise ValueError("base tree")
 b=subprocess.run(["git","show",f"{BASE}:docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md"],cwd=ROOT,check=True,capture_output=True).stdout;f=subprocess.run(["git","show",f"{BASE}:docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md"],cwd=ROOT,check=True,capture_output=True).stdout
 def sec(n,i):
  m=re.search(rf"(?ms)^{i}### {re.escape(n)} —.*?(?=^{i}### |\Z)",b.decode());return m.group(0).encode() if m else (_ for _ in ()).throw(ValueError("source "+n))
 at=f.index(b"P04-C32");row=f[f.rfind(b"\n",0,at)+1:f.index(b"\n",at)+1];vals={"V23-P04-C32":sec("V23-P04-C32",""),"V21-P04-C32":sec("V21-P04-C32","    "),"V23-P04-C32-register":row}
 for k,v in vals.items():
  if(len(v),sha(v))!=PINS[k]:raise ValueError("pin "+k)
 return[{"anchor":k,"utf8Length":len(v),"sha256":sha(v)}for k,v in vals.items()]
def authority():
 a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"hydrationRevision":2,"fencePathCount":30,"existingPathCount":16,"newPathCount":14,"priorFenceProof":{"fenceCount":123,"priorOwnedPathCount":30,"unauthorizedOverlapCount":0,"s10ReservedOverlapCount":0},"frozenS10ReservationDigest":S10,"orderedPathFence":list(PATH_FENCE),"sourcePins":pins(),"finalHashesSealed":False}
 c=_coord()
 if c is None or not c.is_dir():
  m=json.loads((ROOT/MANIFEST).read_bytes());
  if m.get("authority")!=a:raise ValueError("portable authority")
  return a
 if (git("rev-parse","HEAD",cwd=c),git("rev-parse","HEAD^{tree}",cwd=c))!=(HEAD,CTREE):raise ValueError("coord identity")
 ctx=json.loads((c/f"contexts/{CARD}-attempt-1/BootstrapCardContextV1.json").read_bytes());f=json.loads((c/f"contexts/{CARD}-attempt-1/BootstrapPathFenceV1.json").read_bytes());proof=f["priorFenceProof"]
 if(ctx.get("contextDigest"),f.get("fenceDigest"),ctx.get("ownerAuthorizedPathAllocationDigest"),ctx.get("provisionalPrerequisiteDigest"))!=(CONTEXT,FENCE,ALLOCATION,PREREQ)or tuple(f.get("allowedCreateOrReplacePaths",()))!=PATH_FENCE or(len(f["existingPaths"]),len(f["newPaths"]),proof["fenceCount"],proof["priorOwnedPathCount"],proof["unauthorizedOverlapCount"],proof["s10ReservedOverlapCount"])!=(16,14,123,30,0,0)or f.get("frozenS10ReservationDigest")!=S10:raise ValueError("fence")
 return a
def rows():
 r=[]
 for p in PATH_FENCE:
  if p not in OWNED:
   q=ROOT/p;r.append({"path":p,"status":"SOURCE_PRESENT"if q.is_file()else"SOURCE_MISSING","sha256":sha(q.read_bytes())if q.is_file()else None})
 return r,all(x["status"]=="SOURCE_PRESENT"for x in r)
def counts():
 def names(*a):return{x.replace("\\","/")for x in git(*a).splitlines()if x}
 ch=names("diff","--name-only",BASE,"HEAD")|names("diff","--name-only","HEAD")|names("diff","--cached","--name-only")|names("ls-files","--others","--exclude-standard")|OWNED;allow=set(PATH_FENCE);return{"changedPathCount":len(ch&allow),"missingPathCount":sum(not(ROOT/p).is_file()for p in allow-OWNED),"unownedChangedPathCount":len(ch-allow),"s10ReservationOverlapCount":0}
def semantics(ready):
 if not ready:return
 text="\n".join((ROOT/p).read_text(encoding="utf-8",errors="ignore")for p in PATH_FENCE if p.endswith(".swift")or p.endswith(".json"))
 for x in("applyPartyContactSiteRoleImport","atomicWorkspaceBundle","WorkspaceWriterV1","MutationReceipt","preview","reversal","replay","CSV"):
  if x not in text:raise ValueError("semantic "+x)
 if SELECTORS:
  for s in SELECTORS:
   if s not in(ROOT/TEST).read_text(encoding="utf-8"):raise ValueError("selector "+s)
  ui=(ROOT/UI).read_text(encoding="utf-8")
  if "testV23P04C32PartyContactSiteRoleImportUIIsDeferredPendingS106" not in ui or "XCTSkip" not in ui:raise ValueError("UI skip")
def documents():
 a=authority();r,ready=rows();base={"schema":"V23P04C32PartyContactSiteRoleImportToolingV1","cardID":CARD,"authority":a,"sourceRows":r,"sourceReady":ready,"finalHashesSealed":False,"flags":FLAGS,"selectors":list(SELECTORS),"lifecycle":{"persistentSchema":"V53","activeModelCount":168,"newDurableFamilyCount":0,"newWriterCount":0,"newMigrationCount":0,"previewWrites":0,"atomicRootCount":1,"receiptCount":1}}
 contract={**base,"contract":"PartyContactSiteRoleImportContractV1","requirements":{"sourceSchemaOrder":["PARTY","OPERATIONAL_CONTACT","SITE_ROLE"],"exactKeyOnly":True,"fuzzyMatching":False,"previewZeroWrite":True,"compoundCommand":"applyPartyContactSiteRoleImport","allOrNothing":True,"safeDefaultExport":True}}
 evidence={**base,"receipt":"PartyContactSiteRoleImportEvidenceReceiptV1"};brand={"schema":"BrandImpactManifestV1","cardID":CARD,"flags":FLAGS,"finalHashesSealed":False,"requiresAcceptedS10_6Reconciliation":True};files={CONTRACT:sha(pretty(contract)),EVIDENCE:sha(pretty(evidence)),BRAND:sha(pretty(brand))};m={"schema":"V23P04C32ToolingManifestV1","cardID":CARD,"authority":a,"pathFence":list(PATH_FENCE),"files":[{"path":p,"sha256":h}for p,h in files.items()],"sourceRows":r,"flags":FLAGS,"finalHashesSealed":False};return{CONTRACT:contract,EVIDENCE:evidence,BRAND:brand,MANIFEST:m}
