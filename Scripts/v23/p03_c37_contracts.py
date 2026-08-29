#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C37."""
from __future__ import annotations
import hashlib,json,re,subprocess,sys
from pathlib import Path
from typing import Any
sys.dont_write_bytecode=True

CARD="V23-P03-C37";TITLE="Reference-framed point anchors and asset pose/facing, immutable observation history, and plan-safe rebase semantics";REGISTER_ORDINAL=67
BASE_HEAD="4511b4ae963e80fb764393cf0d3561191baf1fea";BASE_TREE="c3ae71f1e8e5808d666cd4e7b6de83f6cd72b4ea"
COORDINATION_HEAD="317df73786d4028a960633dfc1c593023e8e3d84";COORDINATION_TREE="5ce2865cb727080e154ce0bce49349f4b5fe5745";COORDINATION_CAS_SEQUENCE=286;HYDRATION_REVISION=1
PREREQUISITE_DIGEST="f61e9ba5c3e66eb1c434389c8b67160dbfe69975f1940b5275650281ea1cd5ef";CONTEXT_DIGEST="cacb2aeb4e857ef445a4432ed71c33b499e92de72d9bcf6cbc638a95f27d75bc";FENCE_DIGEST="59b198fde5e300119e100f68870480334b704adc64e303de40db3b23979a4e59";HYDRATION_TRANSITION_DIGEST="dfefcdc0f7cc33c6894d58321f2c394dee18842fa421e698c38f027e327862a0";COORDINATION_LEDGER_DIGEST="bc58704f7e6c52a8465817bb19318bce4cfdb1dc3dee35306fe89f93de6cc41a";COORDINATION_PROJECTION_DIGEST="9dfbc96dfa19d1d4a7f9716fe5fc2fa9bd82635368a37a90445d19405d1a76ae"
AUTHORIZED_OVERLAP_COUNT=2155;UNAUTHORIZED_OVERLAP_COUNT=0
SCHEMA_PATH="Scripts/v23/placement-pose.schema.json";CONTRACT_PATH="docs/design/v23/tooling/V23P03C37PlacementPoseContractV1.json";EVIDENCE_PATH="docs/design/v23/tooling/V23P03C37PlacementPoseEvidenceReceiptV1.json";BRAND_PATH="docs/design/v23/tooling/V23P03C37BrandImpactManifestV1.json";MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C37-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c37_contracts.py","Scripts/v23/generate_p03_c37_contracts.py","Scripts/v23/verify_p03_c37_contracts.py");GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)
sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c29_contracts as _c29
EXISTING_ADDITIONS=("FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift","FieldEvidenceApp/Domain/Models/PlanPersistenceModelsV1.swift","FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Plans/PlanLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_43PlanRebaseTests.swift","FieldEvidenceAppTests/Fixtures/V22/Plans/V22P03C29PlanRebaseCorpusV1.json","FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift","FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift","FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift","FieldEvidenceApp/Infrastructure/Drafts/DraftCommitSagaRecoveryV1.swift","FieldEvidenceApp/Infrastructure/Drafts/DraftAutosaveSchedulerV1.swift","FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift","FieldEvidenceAppTests/Fixtures/V21/Drafts/V21P03C36FieldDraftResilienceCorpusV1.json")
EXISTING_PATHS=tuple(_c29.EXISTING_PATHS)+EXISTING_ADDITIONS
NEW_PATHS=("FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift","FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift","FieldEvidenceApp/Application/Pose/PlacementPoseCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Pose/PlacementPoseLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_44PlacementPoseTests.swift","FieldEvidenceAppTests/Fixtures/V22/Pose/V22P03C37PlacementPoseCorpusV1.json",*SCRIPT_PATHS,*GENERATED_PATHS)
PATH_FENCE=EXISTING_PATHS+NEW_PATHS;MANIFEST_INPUT_PATHS=tuple(p for p in PATH_FENCE if p!=MANIFEST_PATH)
CONTRACT_NAMES=("PoseAxisID","PoseAxisDescriptorV1","PoseAxisSemanticRoleV1","PoseAxisRegistryPolicyV1","PoseRequiredComponentsV1","PoseObservationRequirementV1","PoseAngleMilliDegreesV1","PoseObservationDispositionV1","PoseNotObservedReasonV1","PoseReferenceFrameV1","PlacementPoseV1","PoseCaptureSourceV1","DeviceHeadingProposalV1","AssetPoseEventV1","SpatialAnchorObservationV1","CurrentPoseProjectionV1","PoseAxisRegistryReleaseV1","PlacementPoseAdmissionClosureV1","PosePlacementDispositionComponentV1","PoseFrameRebaseComponentV1","PoseFrameRebasePolicyV1","PlacementPoseEditorContractV1","PlacementPoseEditorStateV1","PlacementPoseEditorCommandV1","CompletedPlacementPoseSnapshotV1")
POSE_OUTCOMES=("OBSERVED","NOT_OBSERVED","REOBSERVE","CARRY_FORWARD_SAME_PHYSICAL_INSTALLATION","MARK_NOT_OBSERVED","TRANSFORMED","UNCHANGED","REVIEW_REQUIRED")
TEST_METHODS=("testV23P03C37G01ReferenceFramedPoseHistoryAndQualifiedSnapshotAreDeterministic","testV23P03C37A01ManualNotObservedAndNoPlanFallbackRemainComplete","testV23P03C37H01InvalidFramesAnglesTransformsForksAndClaimsFailClosed","testV23P03C37I01InterruptedMoveRebaseAndPromotionExposeOldOrOneSealedSuccessor","testV23P03C37R01RestoreReplayRebuildAndHistoricArtifactsPreserveExactPoseTruth")
FLAGS={k:False for k in ("native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
PERSISTENCE_PINS_PENDING=False
PERSISTENCE:dict[str,Any]={"schemaRelease":"PLACEMENT_POSE_V1","persistentSchemaVersion":29,"recordsSchemaVersion":28,"persistentKindLifecycleModelCount":102,"durableFamilyCount":2,"persistedFamilies":["AssetPoseEventRow","SpatialAnchorObservationRow"],"embeddedFamilies":["PoseAxisDescriptorV1","PlacementPoseV1"],"nonPersistentFamilies":["DeviceHeadingProposalV1","PoseAxisDescriptorRegistryV1","AssetPoseHistoryV1","AssetPoseCurrentTipV1","CurrentPoseProjectionV1","PosePlacementDispositionComponentV1","PoseFrameRebaseComponentV1","PlacementPoseEditorContractV1","PlacementPoseEditorStateV1","PlacementPoseEditorCommandV1","CompletedPlacementPoseSnapshotV1"],"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V29_WRITE"}

def canonical(v:Any)->bytes:return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def pretty(v:Any)->bytes:return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha256_bytes(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def sha256_value(v:Any)->str:return sha256_bytes(canonical(v))
def _git_paths(root:Path,*args:str)->set[str]:
 out=subprocess.run(["git","-C",str(root),*args],check=True,capture_output=True,text=True).stdout
 return {p.replace("\\","/") for p in out.splitlines() if p}
def observed_changed_paths(root:Path)->set[str]:
 changed=_git_paths(root,"diff","--name-only",f"{BASE_HEAD}..HEAD","--");changed|=_git_paths(root,"diff","--name-only","--");changed|=_git_paths(root,"diff","--cached","--name-only","--");changed|=_git_paths(root,"ls-files","--others","--exclude-standard");return changed
def _base_exists(root:Path,p:str)->bool:return subprocess.run(["git","-C",str(root),"cat-file","-e",f"{BASE_HEAD}:{p}"],capture_output=True).returncode==0
def observed_selectors(root:Path)->tuple[str,...]:
 p=root/"FieldEvidenceAppTests/V9_44PlacementPoseTests.swift"
 if not p.is_file():return ()
 return tuple(re.findall(r"\bfunc\s+(testV23P03C37(?:G|A|H|I|R)\d{2}\w*)\s*\(",p.read_text(encoding="utf-8")))
def require_source_ready(root:Path)->None:
 required=("FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift","FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift","FieldEvidenceApp/Application/Pose/PlacementPoseCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Pose/PlacementPoseLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_44PlacementPoseTests.swift")
 missing=[p for p in required if not (root/p).is_file()]
 if missing:raise ValueError("C37 stable source absent:"+",".join(missing))
 selectors=observed_selectors(root)
 if len(selectors)!=5 or {s[len("testV23P03C37")] for s in selectors}!={"G","A","H","I","R"}:raise ValueError("C37 exact G/A/H/I/R selectors absent")
 if PERSISTENCE_PINS_PENDING or any(PERSISTENCE[k] is None for k in ("schemaRelease","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","durableFamilyCount","persistedFamilies","downgrade")):raise ValueError("C37 persistence pins await stable canonical source")
def _tokens(root:Path,path:str,*tokens:str)->str:
 p=root/path
 if not p.is_file():raise ValueError(f"C37 source absent:{path}")
 text=p.read_text(encoding="utf-8");missing=[x for x in tokens if x not in text]
 if missing:raise ValueError(f"C37 source regression:{path}:"+",".join(missing))
 return text
def assert_source_regressions(root:Path)->None:
 require_source_ready(root)
 core=_tokens(root,"FieldEvidenceApp/Domain/Pose/PlacementPoseContractsV1.swift","struct PoseAxisDescriptorV1","enum PoseRequiredComponentsV1","enum PoseObservationRequirementV1","struct PoseAngleMilliDegreesV1","struct AssetPoseEventV1","struct SpatialAnchorObservationV1","struct PoseAxisRegistryReleaseV1","struct PlacementPoseAdmissionClosureV1","let packageRelease: InspectionPackageReleaseV1","let axisRegistryRelease: PoseAxisRegistryReleaseV1","let planRevisions: [PlanRevisionV1]","let placementEvents: [AssetPlacementEventV1]","usedPlacementIDs == Set(placementEvents.map(\\.id))","usedPlanReferences == suppliedPlanReferences","final class PosePlacementDispositionComponentV1","struct PoseFrameRebasePolicyV1","struct PoseFrameRebaseComponentV1","struct PlacementPoseEditorContractV1","struct CompletedPlacementPoseSnapshotV1","360_000","90_000","180_000","rounded(.toNearestOrEven)")
 for token in ("minimumSingularValueScaled","maximumSingularValueRatioScaled","maximumSimilarityResidualScaled"):
  if token not in core:raise ValueError(f"C37 transform policy regression:{token}")
 models=_tokens(root,"FieldEvidenceApp/Domain/Models/PlacementPosePersistenceModelsV1.swift","@Model final class AssetPoseEventRow","@Model final class SpatialAnchorObservationRow","durableModelCount=2","persistentSchemaVersion=29","recordsSchemaVersion=28")
 if len(re.findall(r"@Model\s+final\s+class",models))!=2:raise ValueError("C37 persistence must remain exactly two rows")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","enum PersistentSchemaV29","PersistentSchemaV28.models+[AssetPoseEventRow.self,SpatialAnchorObservationRow.self]")
 _tokens(root,"FieldEvidenceApp/Domain/Packs/FieldReferencePackContractsV1.swift","FieldReferenceReleaseV1")
 _tokens(root,"FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift","canonicalPoseEffectsSHA256","PlacementPoseMutationV1")
 _tokens(root,"FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift","struct PlacementPoseMutationV1","let admissionClosure:PlacementPoseAdmissionClosureV1","admissionClosure:PlacementPoseAdmissionClosureV1)throws","try admissionClosure.validate(events:events,observations:observations)")
 _tokens(root,"FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift","poseEffects:","writer.commitPlan(mutation, validatedAgainst: preview)")
 _tokens(root,"FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift","poseAdmissionClosure: PlacementPoseAdmissionClosureV1?","posePostImageSHA256","admissionClosure: poseAdmissionClosure","try poseAdmissionClosure?.validate(events: poseEvents, observations: [])","struct AssetPlacementChangeReceiptV1","let posePostImageSHA256: String?; let commandBodySHA256: String","WorkspaceCommandV1.applyAssetPlacementChange(plan))","mutationReceipt.commandBodySHA256 == commandBodySHA256","posePostImageSHA256 = plan.posePostImageSHA256")
 _tokens(root,"FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift","poseAdmissionClosure: PlacementPoseAdmissionClosureV1?","posePostImageBuilder","poseAdmissionClosure: poseAdmissionClosure","writer.execute(request)","durableReceipt(mutationID:")
 _tokens(root,"FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift","AssetPoseEventReferenceV1")
 _tokens(root,"FieldEvidenceApp/Application/Pose/PlacementPoseCoordinatorV1.swift","appendPoseEvent","PlacementPoseAppendReceiptV1","admissionClosure: PlacementPoseAdmissionClosureV1","try admissionClosure.validate(events: [event], observations: [])","try admissionClosure.validate(events: [], observations: [observation])")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Pose/PlacementPoseLifecycleAdapterV1.swift","admissionClosure: PlacementPoseAdmissionClosureV1","try admissionClosure.validate(events: [event], observations: [])","try admissionClosure.validate(events: [], observations: [observation])")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","validatePlacementPoseAdmissionClosure(mutation.admissionClosure)","closure.packageRelease","closure.planRevisions","closure.placementEvents")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift","validatePlacementPoseReferences(_ mutation:PlacementPoseMutationV1)","validatePlacementPoseAdmissionClosure(mutation.admissionClosure,pendingPlacementIDs:[])","validateAssetPlacementPoseReferences")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift","let closure=mutation.admissionClosure","closure.packageRelease","closure.planRevisions","closure.placementEvents")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift","validatePlacementPoses","V29PlacementPoseImportBoundaryV1.validate(persistent: 29, records: 28)")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift","PlacementPoseKernelDeletionEnrollmentV1","PlacementPoseRestoreIdentityPolicyV1.durableFamilyCount == 2")
 _tokens(root,"FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","struct C37PoseSearchRecordV1","C37PoseSearchProjectionPolicyV1")
 _tokens(root,"FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift","C37PlacementPoseReportProjectionV1")
 _tokens(root,"FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift","C37PoseLocalizationKeyV1")
 _tokens(root,"FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift","C37PlacementPoseAccessibilityIDV1")
 hostile=_tokens(root,"FieldEvidenceAppTests/V9_44PlacementPoseTests.swift","let missingAuthorities = try PlacementPoseAdmissionClosureV1","let forgedDescriptorClosure = try PlacementPoseAdmissionClosureV1","let bypassClosure = try PlacementPoseAdmissionClosureV1","XCTAssertThrowsError(try PlacementPoseMutationV1(","admissionClosure: bypassClosure","func testV23P03C37AssetPlacementChangeReceiptV1RejectsMismatchedPoseCommandBodySHA256()","XCTAssertEqual(firstPlan.planSHA256, secondPlan.planSHA256)","XCTAssertNotEqual(firstPlan.posePostImageSHA256, secondPlan.posePostImageSHA256)","XCTAssertNotEqual(firstCommandBodySHA256, secondCommandBodySHA256)")
 if hostile.count("XCTAssertThrowsError(try") < 20:raise ValueError("C37 hostile admission coverage regressed")
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(182,14,196) or len(set(PATH_FENCE))!=196:raise ValueError("C37 fence must be unique 196=182+14")
 if any("s10" in p.lower() or "phase10" in p.lower() for p in PATH_FENCE):raise ValueError("C37 S10 overlap")
 if subprocess.run(["git","-C",str(root),"show","-s","--format=%T",BASE_HEAD],check=True,capture_output=True,text=True).stdout.strip()!=BASE_TREE:raise ValueError("C37 base tree differs")
 for p in EXISTING_PATHS:
  if not _base_exists(root,p):raise ValueError(f"existing absent at base:{p}")
 for p in NEW_PATHS:
  if _base_exists(root,p):raise ValueError(f"new existed at base:{p}")
 if AUTHORIZED_OVERLAP_COUNT!=2155 or UNAUTHORIZED_OVERLAP_COUNT!=0 or any(FLAGS.values()):raise ValueError("C37 authority proof differs")
def authority()->dict[str,Any]:return {"cardID":CARD,"attemptID":1,"registerOrdinal":REGISTER_ORDINAL,"title":TITLE,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":COORDINATION_CAS_SEQUENCE,"hydrationRevision":HYDRATION_REVISION,"prerequisiteDigest":PREREQUISITE_DIGEST,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"coordinationLedgerDigest":COORDINATION_LEDGER_DIGEST,"coordinationProjectionDigest":COORDINATION_PROJECTION_DIGEST,"allowedPathCount":196,"existingPathCount":182,"newPathCount":14,"authorizedOverlapCount":2155,"unauthorizedOverlapCount":0,"directPrerequisiteCards":["V23-P03-C24","V23-P03-C29"],"nextCard":"V23-P03-C30","digestPinsPending":PERSISTENCE_PINS_PENDING}
def _sealed(v:dict[str,Any])->dict[str,Any]:return {**v,"artifactDigest":sha256_bytes(pretty(v))}
def schema_document()->dict[str,Any]:return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/placement-pose.schema.json","title":"V23 P03 C37 Placement Pose Corpus","type":"object","additionalProperties":False,"properties":{"schema":{"const":"V22P03C37PlacementPoseCorpusV1"},"schemaVersion":{"const":1},"cardID":{"const":CARD},"persistentSchemaVersion":{"const":29},"recordsSchemaVersion":{"const":28},"persistentKindLifecycleModelCount":{"const":102},"durableFamilyCount":{"const":2},"durableFamilies":{"const":["AssetPoseEventRow","SpatialAnchorObservationRow"]},"poseOutcomes":{"const":list(POSE_OUTCOMES)},"requiredContractNames":{"const":list(CONTRACT_NAMES)},"statusFlags":{"type":"object","additionalProperties":{"const":False}}},"required":["schema","schemaVersion","cardID","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","durableFamilyCount","durableFamilies","poseOutcomes","requiredContractNames","statusFlags"]}
def contract_document(root:Path)->dict[str,Any]:
 assert_source_regressions(root);semantics={"contractNames":list(CONTRACT_NAMES),"poseOutcomes":list(POSE_OUTCOMES),"fiveSelectors":list(observed_selectors(root)),"fixedPointBoundsAndClosedDescriptorMatrices":True,"c23C29C35C36ReferenceClosure":True,"exactPackageAxisRegistryDescriptorWorkspacePlanPageFramePlacementEpisodePathAuthority":True,"requiredAdmissionClosureHasNoDefault":True,"coordinatorLifecycleWriterJournalRecoveryAdmissionValidation":True,"c29AndC35SingleAggregateReceiptWithPoseDigest":True,"c35ReceiptBindsPoseDigestAndExactCanonicalCommandBody":True,"c35ReceiptRejectsMutationReceiptCommandBodyMismatch":True,"standalonePoseWriterReceipt":True,"hostileAdmissionCoverage":True,"finiteOrientationPreservingTransformPolicy":True,"twoDurableFamiliesOnly":True,"derivedHistoriesTipsRegistriesComponentsEditorAndSnapshots":True,"backupDeleteSearchReportLocalizationAccessibilityClosure":True,"secondWriterOrReceipt":False,"continuousSensorStream":False,"surveyGradeClaim":False}
 return _sealed({"schema":"V23P03C37PlacementPoseContractV1","schemaVersion":1,"authority":authority(),"persistence":PERSISTENCE,"requiredSemantics":semantics})
def evidence_document(root:Path)->dict[str,Any]:
 contract=contract_document(root);return _sealed({"schema":"V23P03C37PlacementPoseEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"evidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],"testSelectors":list(observed_selectors(root)),"requiredSemanticsDigest":sha256_value(contract["requiredSemantics"]),"statusFlags":FLAGS})
def brand_document()->dict[str,Any]:return _sealed({"schema":"V23P03C37BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":False,"brandSurfaceDelta":True,"changedStates":list(POSE_OUTCOMES),"nativeIPadSurface":False,"telemetry":False,"statusFlags":FLAGS})
def _row(root:Path,p:str,r:dict[str,bytes])->dict[str,Any]:
 raw=r[p] if p in r else (root/p).read_bytes();return {"path":p,"sha256":sha256_bytes(raw),"byteCount":len(raw)}
def all_outputs(root:Path)->dict[str,bytes]:
 assert_source_regressions(root);r={SCHEMA_PATH:pretty(schema_document()),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,r) for p in MANIFEST_INPUT_PATHS];r[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C37ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":196,"existingPathCount":182,"newPathCount":14,"authorizedOverlapCount":2155,"unauthorizedOverlapCount":0,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"statusFlags":FLAGS}));return r
