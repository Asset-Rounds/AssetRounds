#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C29."""
from __future__ import annotations

import hashlib, json, re, subprocess, sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
CARD="V23-P03-C29"; TITLE="Versioned offline plans, normalized placements, deterministic rebase preview, and receipts"
REGISTER_ORDINAL=66; BASE_HEAD="8efb2cdf9241268a2035e947934ff72282d807d6"; BASE_TREE="ac757f22be8385fb1af7d74ad4f8e8d9dd640fb3"
COORDINATION_HEAD="80f5527884169c9d9409673d7412329ddaee0473"; COORDINATION_TREE="e5996208859ad13058788939c8946acd41d9bde2"; COORDINATION_CAS_SEQUENCE=282; HYDRATION_REVISION=1
PREREQUISITE_DIGEST="03c907a94c4d5749c7d066c00e19c2b1e7d1764c1a9db34c115afc9a28005227"
CONTEXT_DIGEST="b202e213e61a093d65c169453878700f110cba548cf4bbba86d760733b5f4d8d"; FENCE_DIGEST="d647bb477e65b06a780876ac60c02ed68296e7d89c2219823f19815c75c2bb53"
HYDRATION_TRANSITION_DIGEST="b20b178a9e00f7966014c0f9651ce07d339a0a0d429af715e407eb894443499d"
COORDINATION_LEDGER_DIGEST="0ccf73b5e6a62edd4f53fdc651f0900c4bee38001c83e9022adf7d17d6437970"; COORDINATION_PROJECTION_DIGEST="7d0d3e5e5f67570a21b6109a2ac7fd1cde91da1c99b6c460af1a319f67391223"
AUTHORIZED_OVERLAP_COUNT=1959; UNAUTHORIZED_OVERLAP_COUNT=0

SCHEMA_PATH="Scripts/v23/plan-rebase.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P03C29PlanRebaseContractV1.json"
EVIDENCE_PATH="docs/design/v23/tooling/V23P03C29PlanRebaseEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P03C29BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C29-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c29_contracts.py","Scripts/v23/generate_p03_c29_contracts.py","Scripts/v23/verify_p03_c29_contracts.py")
GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)

sys.path.insert(0,str(Path(__file__).resolve().parent))
import p03_c28_contracts as _c28
EXISTING_ADDITIONS=(
"FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift","FieldEvidenceApp/Domain/Models/AssetLocatorPersistenceModelsV1.swift","FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/AssetSemantics/AssetLocatorLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_41AssetLocatorTests.swift",
"FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift","FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift","FieldEvidenceApp/Domain/Packs/FieldReferencePackContractsV1.swift","FieldEvidenceApp/Domain/Models/FieldReferencePackPersistenceModelsV1.swift","FieldEvidenceApp/Application/Packs/FieldReferencePackCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/OfflineReadiness/FieldReferencePackLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_37FieldReferencePackTests.swift",
"FieldEvidenceApp/Domain/Models/Site.swift","FieldEvidenceApp/Domain/Models/LocationPersistenceModelsV1.swift","FieldEvidenceApp/Domain/Location/LocationHierarchyContractsV1.swift","FieldEvidenceApp/Domain/Location/AssetPlacementContractsV1.swift","FieldEvidenceApp/Domain/Location/AssetCompositionContractsV1.swift","FieldEvidenceApp/Domain/Location/CompletedLocationCompositionSnapshotV1.swift","FieldEvidenceApp/Application/Location/AssetPlacementChangeCoordinatorV1.swift","FieldEvidenceAppTests/V9_LocationHierarchyPlacementCompositionTests.swift","FieldEvidenceApp/Domain/Workflow/FinalizationContracts.swift","FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift")
EXISTING_PATHS=tuple(_c28.EXISTING_PATHS)+EXISTING_ADDITIONS
NEW_PATHS=("FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift","FieldEvidenceApp/Domain/Models/PlanPersistenceModelsV1.swift","FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Plans/PlanLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_43PlanRebaseTests.swift","FieldEvidenceAppTests/Fixtures/V22/Plans/V22P03C29PlanRebaseCorpusV1.json",*SCRIPT_PATHS,*GENERATED_PATHS)
PATH_FENCE=EXISTING_PATHS+NEW_PATHS; MANIFEST_INPUT_PATHS=tuple(p for p in PATH_FENCE if p!=MANIFEST_PATH)

CONTRACT_NAMES=("PlanDocumentV1","PlanRevisionV1","SpatialReferenceFrameV1","PlanPlacementV1","PlanRebaseComponentV1","PlanRebaseComponentRegistryV1","PlanRebaseCoordinatorV1","RebasePreviewV1","RebaseReceiptV1")
PERSISTED_FAMILIES=("PlanDocumentV1","PlanRevisionV1","PlanPlacementV1","RebaseReceiptV1")
EMBEDDED_FAMILIES=("SpatialReferenceFrameV1",)
NONPERSISTENT_FAMILIES=("RebasePreviewV1","PlanRebaseMutationIntentV1","PlanRebaseComponentRegistryV1")
REBASE_OUTCOMES=("UNCHANGED","TRANSFORMED","OUT_OF_BOUNDS","ORPHANED","RESIDUAL_WARNING","REVIEW_REQUIRED","APPROVED","REJECTED")
TEST_METHODS=("testV23P03C29G01ImmutableRevisionAndNormalizedPlacementProduceOneDeterministicRebaseReceipt","testV23P03C29A01MissingUnsupportedOrInaccessiblePlanPreservesCompleteManualFallback","testV23P03C29H01CorruptHugeInvalidBoundsAndRegistryForksFailClosedWithoutPartialActivation","testV23P03C29I01InterruptedApprovalExposesOldSetOrOneSealedNewSet","testV23P03C29R01RestorePreservesOriginalRevisionHistoricReportAndOfflineReadiness")
EVIDENCE_IDS=tuple(f"{CARD}-{s}" for s in ("G01","A01","H01","I01","R01"))
FLAGS={k:False for k in ("native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
PERSISTENCE_PINS_PENDING=False
PERSISTENCE:dict[str,Any]={"schemaRelease":"PLAN_REBASE_V1","persistentSchemaVersion":28,"recordsSchemaVersion":27,"persistentKindLifecycleModelCount":100,"durableFamilyCount":len(PERSISTED_FAMILIES),"persistedFamilies":list(PERSISTED_FAMILIES),"embeddedFamilies":list(EMBEDDED_FAMILIES),"nonPersistentFamilies":list(NONPERSISTENT_FAMILIES),"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V28_WRITE"}
DIRECT_PREREQUISITE_EVIDENCE={"schema":"ProvisionalExecutionPrerequisiteSetReceiptV1","schemaVersion":1,"successorCardID":CARD,"successorAttemptID":1,"ordinaryDirectEdgeCount":2,"predecessors":[{"cardID":"V23-P03-C23","attemptID":1,"disposition":"CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C23_HEAD"},{"cardID":"V23-P03-C27","attemptID":1,"disposition":"CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C27_HEAD_WITH_APPEND_ONLY_CORRECTIONS"}],"canonicalRelationPreserved":True,"nonreleaseSpecialEdgeApplied":False,"disposition":"PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY","nativeCompileRan":False,"physicalLockedState":"REQUIRED_PENDING_OWNER","acceptanceCredit":False,"releaseCredit":False,"prerequisiteDigest":PREREQUISITE_DIGEST}

def canonical(v:Any)->bytes:return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def pretty(v:Any)->bytes:return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha256_bytes(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def sha256_value(v:Any)->str:return sha256_bytes(canonical(v))
def _base_path_exists(root:Path,p:str)->bool:return subprocess.run(["git","-C",str(root),"cat-file","-e",f"{BASE_HEAD}:{p}"],capture_output=True).returncode==0
def _git_paths(root:Path,*args:str)->set[str]:
 out=subprocess.run(["git","-C",str(root),*args],check=True,capture_output=True,text=True).stdout
 return {p.replace("\\","/") for p in out.splitlines() if p}
def observed_changed_paths(root:Path)->set[str]:
 # Commit ancestry and all three dirty-index/worktree/untracked dimensions are independent inputs.
 changed=_git_paths(root,"diff","--name-only",f"{BASE_HEAD}..HEAD","--")
 changed|=_git_paths(root,"diff","--name-only","--")
 changed|=_git_paths(root,"diff","--cached","--name-only","--")
 changed|=_git_paths(root,"ls-files","--others","--exclude-standard")
 return changed
def _observed_selectors(root:Path)->tuple[str,...]:
 p=root/"FieldEvidenceAppTests/V9_43PlanRebaseTests.swift"
 if not p.is_file():return TEST_METHODS
 return tuple(re.findall(r"\bfunc\s+(testV23P03C29(?:G|A|H|I|R)\w*)\s*\(",p.read_text(encoding="utf-8")))
def authority()->dict[str,Any]:return {"cardID":CARD,"attemptID":1,"registerOrdinal":REGISTER_ORDINAL,"title":TITLE,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":COORDINATION_CAS_SEQUENCE,"hydrationRevision":HYDRATION_REVISION,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"coordinationLedgerDigest":COORDINATION_LEDGER_DIGEST,"coordinationProjectionDigest":COORDINATION_PROJECTION_DIGEST,"allowedPathCount":len(PATH_FENCE),"existingPathCount":len(EXISTING_PATHS),"newPathCount":len(NEW_PATHS),"directPrerequisiteCards":["V23-P03-C23","V23-P03-C27"],"nextCard":"V23-P03-C37","digestPinsPending":PERSISTENCE_PINS_PENDING}
def _sealed(v:dict[str,Any])->dict[str,Any]:return {**v,"artifactDigest":sha256_bytes(pretty(v))}
def _require_source_pins()->None:
 if PERSISTENCE_PINS_PENDING or any(PERSISTENCE[k] is None for k in ("schemaRelease","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","downgrade")):raise ValueError("C29 persistence pins await stable canonical source")
def _source_text(root:Path,path:str)->str:
 p=root/path
 if not p.is_file():raise ValueError(f"C29 required source absent:{path}")
 return p.read_text(encoding="utf-8")
def _require_tokens(root:Path,path:str,*tokens:str)->str:
 text=_source_text(root,path)
 missing=[token for token in tokens if token not in text]
 if missing:raise ValueError(f"C29 source regression:{path}:missing:{','.join(missing)}")
 return text
def assert_source_regressions(root:Path)->None:
 """Fail closed if the sealed C29 implementation stops proving its lifecycle contract."""
 core=_require_tokens(root,"FieldEvidenceApp/Domain/Plans/PlanContractsV1.swift",
  "struct PlanDocumentV1","struct PlanRevisionV1","struct SpatialReferenceFrameV1",
  "struct PlanPlacementV1","struct PlanRebaseComponentRegistryV1","struct RebasePreviewV1",
  "struct RebaseReceiptV1","struct PlanLifecycleClosureV1","PlanLimitsV1.normalizedScale",
  "canonicalPlanMutationSHA256","resultingPlacementsSHA256")
 if "let spatialFrames: [SpatialReferenceFrameV1]" not in core:
  raise ValueError("C29 spatial frames must remain embedded in PlanRevisionV1")
 models=_require_tokens(root,"FieldEvidenceApp/Domain/Models/PlanPersistenceModelsV1.swift",
  "PlanDocumentRow","PlanRevisionRow","PlanPlacementRow","RebaseReceiptRow",
  "durableModelCount=4","persistentSchemaVersion=28","recordsSchemaVersion=27",
  "derivedTypes:[Any.Type]=[RebasePreviewV1.self]")
 if "SpatialReferenceFrameRow" in models or len(re.findall(r"@Model\s+final\s+class\s+\w+",models))!=4:
  raise ValueError("C29 persistence must be exactly four rows with embedded spatial frames")
 coordinator=_require_tokens(root,"FieldEvidenceApp/Application/Plans/PlanRebaseCoordinatorV1.swift",
  "func preview(","func approve(","PlanRebaseCommandBasisV1","canonicalPlanMutationSHA256:",
  "writer.commitPlan(mutation, validatedAgainst: preview)")
 preview=coordinator[coordinator.index("func preview("):coordinator.index("func approve(")]
 if "writer." in preview or "commitPlan(" in preview:
  raise ValueError("C29 preview must remain zero-write")
 approve=coordinator[coordinator.index("func approve("):]
 if approve.count("writer.commitPlan(mutation, validatedAgainst: preview)")!=2:
  raise ValueError("C29 approve/reject must each use the sole atomic writer/receipt seam")
 _require_tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
  "validatePlans","PlanBackupRecordSetV1.decode(records.plans)")
 _require_tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
  "func validatePlans(","PlanBackupRecordSetV1.decode(records.plans)")
 _require_tokens(root,"FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
  "PlanStreamingArchivePolicyV1.recordsSchemaVersion == 27",
  "PlanStreamingArchivePolicyV1.persistentSchemaVersion == 28",
  "PlanRestoreIdentityPolicyV1.durableFamilyCount == 4")
 _require_tokens(root,"FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
  "struct PlanPlacementSearchRecordV1","PlanReportProjectionV1")
 _require_tokens(root,"FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
  "struct PlanReportProjectionV1","PlanLimitsV1.normalizedScale")
 _require_tokens(root,"FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift","enum PlanLocalizationKeyV1")
 _require_tokens(root,"FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
  "enum PlanAccessibilityIDV1","PlanLocalizationKeyV1")
def schema_document()->dict[str,Any]:
 _require_source_pins();return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/plan-rebase.schema.json","title":"V23 P03 C29 Plan Rebase Corpus","type":"object","additionalProperties":False,"properties":{"schema":{"const":"V22P03C29PlanRebaseCorpusV1"},"schemaVersion":{"const":1},"cardID":{"const":CARD},"persistentSchemaVersion":{"const":PERSISTENCE["persistentSchemaVersion"]},"recordsSchemaVersion":{"const":PERSISTENCE["recordsSchemaVersion"]},"persistentKindLifecycleModelCount":{"const":PERSISTENCE["persistentKindLifecycleModelCount"]},"durableFamilyCount":{"const":len(PERSISTED_FAMILIES)},"durableFamilies":{"type":"array","const":list(PERSISTED_FAMILIES)},"rebaseOutcomes":{"type":"array","const":list(REBASE_OUTCOMES)},"requiredContractNames":{"type":"array","const":list(CONTRACT_NAMES)},"statusFlags":{"type":"object","additionalProperties":{"const":False}}},"required":["schema","schemaVersion","cardID","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","durableFamilyCount","durableFamilies","rebaseOutcomes","requiredContractNames","statusFlags"]}
def contract_document(root:Path)->dict[str,Any]:
 _require_source_pins();assert_source_regressions(root);required={"contractNames":list(CONTRACT_NAMES),"rebaseOutcomes":list(REBASE_OUTCOMES),"persistentFamilies":list(PERSISTED_FAMILIES),"embeddedFamilies":list(EMBEDDED_FAMILIES),"nonPersistentFamilies":list(NONPERSISTENT_FAMILIES),"fiveSelectors":list(_observed_selectors(root)),"directPrerequisiteClosure":True,"immutableRevisionHistory":True,"normalizedPlacementSeparateFromPixels":True,"closedStablePureComponentRegistry":True,"previewIsDerivedAndZeroWrite":True,"oneCombinedPreviewWriterMutationAndReceipt":True,"cycleFreeCanonicalCommandDigest":True,"backupDeleteSearchReportLocalizationAccessibilityClosure":True,"historicReportRewritten":False,"secondByteStore":False,"surveyGradeClaim":False,"silentPinRecalculation":False}
 return _sealed({"schema":"V23P03C29PlanRebaseContractV1","schemaVersion":1,"authority":authority(),"persistence":PERSISTENCE,"directPrerequisiteEvidence":DIRECT_PREREQUISITE_EVIDENCE,"requiredSemantics":required})
def evidence_document(root:Path)->dict[str,Any]:
 required=contract_document(root)["requiredSemantics"];return _sealed({"schema":"V23P03C29PlanRebaseEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"evidenceIDs":list(EVIDENCE_IDS),"testSelectors":list(_observed_selectors(root)),"requiredSemanticsDigest":sha256_value(required),"statusFlags":FLAGS})
def brand_document()->dict[str,Any]:return _sealed({"schema":"V23P03C29BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":False,"brandSurfaceDelta":True,"changedStates":list(REBASE_OUTCOMES),"nativeIPadSurface":False,"telemetry":False,"statusFlags":FLAGS})
def _row(root:Path,p:str,r:dict[str,bytes])->dict[str,Any]:
 raw=r[p] if p in r else (root/p).read_bytes();return {"path":p,"sha256":sha256_bytes(raw),"byteCount":len(raw)}
def all_outputs(root:Path)->dict[str,bytes]:
 _require_source_pins();assert_source_regressions(root);r={SCHEMA_PATH:pretty(schema_document()),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,r) for p in MANIFEST_INPUT_PATHS];r[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C29ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":len(PATH_FENCE),"existingPathCount":len(EXISTING_PATHS),"newPathCount":len(NEW_PATHS),"authorizedOverlapCount":AUTHORIZED_OVERLAP_COUNT,"unauthorizedOverlapCount":UNAUTHORIZED_OVERLAP_COUNT,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"statusFlags":FLAGS}));return r
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(168,14,182) or len(set(PATH_FENCE))!=182:raise ValueError("C29 fence must be unique 182=168+14")
 if any("s10" in p.lower() or "phase10" in p.lower() for p in PATH_FENCE):raise ValueError("C29 S10 overlap")
 if subprocess.run(["git","-C",str(root),"show","-s","--format=%T",BASE_HEAD],check=True,capture_output=True,text=True).stdout.strip()!=BASE_TREE:raise ValueError("C29 base tree differs")
 for p in EXISTING_PATHS:
  if not _base_path_exists(root,p):raise ValueError(f"existing absent at base:{p}")
 for p in NEW_PATHS:
  if _base_path_exists(root,p):raise ValueError(f"new existed at base:{p}")
 if AUTHORIZED_OVERLAP_COUNT!=1959 or UNAUTHORIZED_OVERLAP_COUNT!=0:raise ValueError("C29 overlap proof differs")
 if len(REBASE_OUTCOMES)!=8 or len(TEST_METHODS)!=5:raise ValueError("C29 outcomes/selectors differ")
 if any(FLAGS.values()):raise ValueError("C29 provisional flags must all remain false")
