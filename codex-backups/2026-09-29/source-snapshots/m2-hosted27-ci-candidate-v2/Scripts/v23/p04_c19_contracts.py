from __future__ import annotations
import hashlib,json,os,subprocess
from pathlib import Path
os.environ["PYTHONDONTWRITEBYTECODE"]="1";ROOT=Path(__file__).resolve().parents[2];COORD=Path(r"C:\AssetRounds-v23-coordination")
CARD="V23-P04-C19";BASE="e22788314918ff294bf5b36cd851c7451a0286d7";BTREE="df4cb890392f8e1b990bcbc8bfb66e59e9179958";HEAD="1e24865f21476cb7cec0cc1e6d59a6240d96ab34";CTREE="16dc58b2dad13bdb6f843f2a3295c088d8584744";CONTEXT="e58e8f9ee9b6a428a2b33e5d4a207d7a0438eee5588a88f3244dd56b39a8e23a";FENCE="1104061fdd8d36142f3c658336b19b6eff6ea973c60dae33dc86ffda246bd038";ALLOCATION="8d5b867def83ef995184aa4792fe06f7992e77110b5c14edcca29e16db94154e";PREREQ="18741e6f8e2d63fde37fa106491ef69c2fbedd1a7e3f5d563c0f1ed5f6b9004d";TRANSITION="b8282cdccac21c3dd0665cbfe17fcfe0caad27520b409e3694387ebda5a93976";LEDGER="eb8b99796d669a0506a37aaab93a229dda4a11fdf9ca7019a21cae4c7eb58d96";PROJECTION="8b46411ead75754d52f71a6737e3466d31dbd62dac936c5f989c75718b0d92db";SEQ=464;FINAL_HASHES_SEALED=True
SCHEMA="Scripts/v23/offline-plan-rebase-activation.schema.json";CONTRACT="docs/design/v23/tooling/V23P04C19OfflinePlanRebaseActivationContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P04C19OfflinePlanRebaseActivationEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P04C19BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P04-C19-tooling-manifest.json";SCRIPTS=("Scripts/v23/p04_c19_contracts.py","Scripts/v23/generate_p04_c19_contracts.py","Scripts/v23/verify_p04_c19_contracts.py");GENERATED=(SCHEMA,CONTRACT,EVIDENCE,BRAND,MANIFEST);OWNED=set(SCRIPTS+GENERATED)
SELECTORS=("testV23P04C19G01ColdLaunchPreparedPacketProvesExactOfflineReadiness","testV23P04C19A01PlacementCreateMoveResumeAndAccessiblePoseParity","testV23P04C19H01MissingCorruptWithdrawnEncryptedAndUnsupportedReferencesFailClosed","testV23P04C19I01RebaseApproveRejectAndInterruptedActivationAreIdempotent","testV23P04C19R01RestoreRebuildAndHistoricReportRetainOriginalPlanRevision");FLAGS={x:False for x in("activation","native","hosted","adoption","acceptance","release","publish","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")}
SOURCE_PINS=(("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md","V23-P04-C19",7303,"5a3e97e6933edfbc75d47f32f05880105a662c4c1be4f6ea8a33feaaec399094"),("docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md","V21-P04-C19",5837,"45c3b2b94968db2ace6a1208b3169f339a2251337f42d00e76f501b6c4bfb263"),("docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md","V23-P04-C19-register",314,"835cdf48ede8154b1f3357788c7c2cbc65a94d242cec2bd5394bf9eadd322b39"))
def pretty(v):return(json.dumps(v,sort_keys=True,indent=2)+"\n").encode()
def sha(v):return hashlib.sha256(v).hexdigest()
def run(*a,cwd=ROOT):return subprocess.run(["git",*a],cwd=cwd,check=True,capture_output=True,text=True).stdout.strip()
def authority():
 c=json.loads((COORD/"contexts/V23-P04-C19-attempt-1/BootstrapCardContextV1.json").read_bytes());f=json.loads((COORD/"contexts/V23-P04-C19-attempt-1/BootstrapPathFenceV1.json").read_bytes());p=f["priorFenceProof"]
 if(run("rev-parse","HEAD",cwd=COORD),run("rev-parse","HEAD^{tree}",cwd=COORD))!=(HEAD,CTREE):raise ValueError("C19 coordination differs")
 if c.get("contextDigest")!=CONTEXT or f.get("fenceDigest")!=FENCE or c.get("ownerAuthorizedPathAllocationDigest")!=ALLOCATION or c.get("provisionalPrerequisiteDigest")!=PREREQ:raise ValueError("C19 context authority differs")
 if (len(c["existingPaths"]),len(c["newPaths"]),len(f["allowedCreateOrReplacePaths"]),p["authorizedOverlapCount"],p["unauthorizedOverlapCount"],p["s10ReservedOverlapCount"])!=(17,14,31,38,0,0):raise ValueError("C19 fence proof differs")
 if c["repository"]!={"appBaseHead":BASE,"appBaseTree":BTREE}:raise ValueError("C19 app base differs")
 return c,f
def source_paths():_,f=authority();return tuple(x for x in f["allowedCreateOrReplacePaths"] if x not in OWNED)
def rows():
 r=[]
 for p in source_paths():
  b=(ROOT/p).read_bytes() if (ROOT/p).is_file() else b"";r.append({"path":p,"status":"SOURCE_PRESENT" if b else "SOURCE_MISSING","sha256":sha(b) if b else None})
 return r,all(x["status"]=="SOURCE_PRESENT" for x in r)
def counts():
 _,f=authority();own=set(f["allowedCreateOrReplacePaths"]);g=lambda *a:{x.replace("\\","/") for x in run(*a).splitlines() if x};x=g("diff","--name-only",BASE,"HEAD")|g("diff","--name-only","HEAD")|g("diff","--cached","--name-only")|g("ls-files","--others","--exclude-standard")|OWNED
 return {"changedPathCount":len(x&own),"missingPathCount":sum(not(ROOT/p).is_file() for p in own-OWNED),"unownedChangedPathCount":len(x-own),"s10ReservationOverlapCount":len(own&set(f["activeS10ReservedPaths"]))}
def source_pins():
 for path,anchor,length,digest in SOURCE_PINS:
  data=(ROOT/path).read_bytes()
  if anchor=="V23-P04-C19":start=data.index(b"### V23-P04-C19 ");end=data.find(b"\n### V23-",start+1);part=data[start:] if end<0 else data[start:end+1]
  elif anchor=="V21-P04-C19":start=data.index(b"    ### V21-P04-C19 ");end=data.find(b"\n    ### V21-P",start+1);part=data[start:] if end<0 else data[start:end+1]
  else:
   start=data.index(b"| 107 | <a id=\"v23-p04-c19-register\"");end=data.index(b"\n",start)+1;part=data[start:end]
  if len(part)!=length or sha(part)!=digest:raise ValueError("C19 source pin differs:"+anchor)
def semantics(ready):
 if not ready:return
 by={p:(ROOT/p).read_text(encoding="utf-8",errors="replace") for p in source_paths()};schema_text=(ROOT/"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift").read_text(encoding="utf-8",errors="replace");t="\n".join((*by.values(),schema_text));need=("PlanOfflineWorkCoordinatorV1","PlanOfflineWorkLifecycleAdapterV1","OfflineWorkPacketReadinessV1","PlanWorkSurfaceStateV1","RebaseReviewStateV1","DERIVED_ONLY","DERIVED_DEVICE_LOCAL_PRESENTATION","PersistentSchemaV53","PersistentSchemaV53.models.count == 168","XCTSkip")
 missing=[x for x in need if x not in t]
 if missing:raise ValueError("C19 source semantics missing:"+",".join(missing))
 test=by.get("FieldEvidenceAppTests/V9_82PlanOfflineWorkTests.swift","");ui=by.get("FieldEvidenceAppUITests/V23_P04_C19PlanOfflineWorkRebaseUITests.swift","");core=by.get("FieldEvidenceApp/Domain/Plans/PlanOfflineWorkContractsV1.swift","")
 if any(s not in test for s in SELECTORS):raise ValueError("C19 exact unit selector missing")
 if "45" not in test or "45" not in by.get("FieldEvidenceAppTests/Fixtures/V23/Plans/V23P04C19PlanOfflineWorkCorpusV1.json",""):raise ValueError("C19 hostile corpus must be exactly 45")
 if ui.count("XCTSkip")!=5:raise ValueError("C19 UI skip count differs")
 lifecycle=by.get("FieldEvidenceApp/Infrastructure/Plans/PlanOfflineWorkLifecycleAdapterV1.swift","")
 coordinator=by.get("FieldEvidenceApp/Application/Plans/PlanOfflineWorkCoordinatorV1.swift","");search=by.get("FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","");report=by.get("FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift","")
 exact=("expectedByteLength == contentBinding.byteLength","expectedSHA256 == contentBinding.contentSHA256","state != .openable || exactBytes","current == requestedRevision ? .current : .historic","never substituted for the requested value","disposition != .approvedActivated || receipt?.decision == .approved","(disposition == .pending) == (receipt == nil)")
 missing_exact=[token for token in exact if token not in core and token not in lifecycle]
 if missing_exact:raise ValueError("C19 proof/rebase integrity missing:"+",".join(missing_exact))
 if any(x in core for x in("offlineReady: Bool","isOffline: Bool","offline: Bool")) or any(x in t for x in("latestHistoricFallback","latest historic fallback","OfflinePlanReceiptRow")):raise ValueError("C19 derived-only/storage prohibition violated")
 absent=("applicability != .notApplicable || exactPlanRevision == nil","applicability != .notApplicable || !hasPlan","PlanRevisionReferenceV1?","PlanContentBindingV1?","PlanOfflineFieldReferenceProofV1?","PlanDocumentOpenabilityObservationV1?")
 if any(token not in core for token in absent):raise ValueError("C19 absent-plan all-absent parity missing")
 surface=("guard source.applicability != .notApplicable","let planRevisionValue = source.planRevision","let fieldReference = source.fieldReference","let openability = source.openability")
 if any(token not in core for token in surface):raise ValueError("C19 work surface must reject absent/not-applicable plan")
 pose=("event.assetID == placement.subjectID","placementEventID = value.placementEventID","physicalEpisodeID = value.placementEpisodeID","PlanPlacementPoseBindingV1","planRevision: revision")
 if any(token not in core for token in pose) or "physical.physicalEpisodeID == event.placementEpisodeID" not in lifecycle:raise ValueError("C19 pose snapshot provenance binding missing")
 resume=("source.revisionDisposition == .current","source.fieldReference?.availability == .readyOffline","source.openability?.state == .openable","source.access.protectedDataAvailable")
 if any(token not in coordinator for token in resume) or "try Self.validateResumeEligibility" not in coordinator:raise ValueError("C19 coordinator resume guard missing")
 if "absentPlanAndNotApplicableItemsAreExcluded = true" not in search or "guard value.applicability != .notApplicable" not in search or "guard value.applicability != .notApplicable" not in report:raise ValueError("C19 search/report must exclude absent plan safely")
def documents():
 c,f=authority();r,ready=rows();n=counts();a={"cardID":CARD,"appBaseHead":BASE,"appBaseTree":BTREE,"coordinationHead":HEAD,"coordinationTree":CTREE,"sequence":SEQ,"contextDigest":CONTEXT,"pathFenceDigest":FENCE,"allocationDigest":ALLOCATION,"prerequisiteDigest":PREREQ,"transitionDigest":TRANSITION,"ledgerDigest":LEDGER,"projectionDigest":PROJECTION,"finalHashesSealed":FINAL_HASHES_SEALED,"fencePathCount":31,"existingPathCount":17,"newPathCount":14,"authorizedOverlapCount":38,"s10OverlapCount":0};s={"sourceReady":ready,"sourceRows":r,"counts":n,"selectors":list(SELECTORS),"sourcePins":[{"path":p,"anchor":a,"utf8Length":l,"sha256":d} for p,a,l,d in SOURCE_PINS]};scope={"persistentSchema":"V53","activeModelCount":168,"newDurableRecordCount":0,"newDurableFamilies":[],"derivedStates":["OfflineWorkPacketReadinessV1","PlanWorkSurfaceStateV1","RebaseReviewStateV1"],"statusFlags":FLAGS};co={"schema":"V23P04C19OfflinePlanRebaseActivationContractV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"testSelectors":list(SELECTORS),"statusFlags":FLAGS};ev={"schema":"V23P04C19OfflinePlanRebaseActivationEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"sourceProjection":s,"contractDigest":sha(pretty(co)),"statusFlags":FLAGS};br={"schema":"V23P04C19BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"authority":a,"semantics":scope,"sourceProjection":s,"uiAdoptionSkipped":True,"uiAcceptanceCredit":False,"statusFlags":FLAGS};m={"schema":"V23P04C19ToolingManifestV1","schemaVersion":1,"cardID":CARD,"provisional":True,"finalHashesSealed":FINAL_HASHES_SEALED,"authority":a,"pathFence":f["allowedCreateOrReplacePaths"],"files":[{"path":p,"sha256":sha(pretty(v))} for p,v in ((CONTRACT,co),(EVIDENCE,ev),(BRAND,br))],"sources":r,"counts":n,"toolingPaths":[*SCRIPTS,*GENERATED],"statusFlags":FLAGS};return {CONTRACT:co,EVIDENCE:ev,BRAND:br,MANIFEST:m}
