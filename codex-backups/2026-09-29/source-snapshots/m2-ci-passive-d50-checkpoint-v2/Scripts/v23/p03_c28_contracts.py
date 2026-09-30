#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C28."""
from __future__ import annotations

import hashlib, json, re, subprocess, sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
CARD="V23-P03-C28"; TITLE="Deterministic schedule definitions, occurrence identity, basis provenance, due-state projection, and history"
REGISTER_ORDINAL=65; BASE_HEAD="d22f3764c32136d592636478a778a5ec21cdf7d8"; BASE_TREE="2f214a9549a27c533274c9a0184868a49d61da85"
COORDINATION_HEAD="1acd0991739c42dcd955504f875fd0b7567e59bb"; COORDINATION_TREE="508c1bcc7502fbfa65f4ed99e2866f1a2299c90b"; COORDINATION_CAS_SEQUENCE=278; HYDRATION_REVISION=2
CONTEXT_DIGEST="48e0e15c7c6890d57a36909f5060428b8e2b53ac8a6a3948e453edcc176a9972"; FENCE_DIGEST="59de5cf7743a73e39d7d2bab3097f0ac71104737b2436122d17333a82bf69c15"
PREREQUISITE_DIGEST="05b66f89907d30c24b389309e9820ad34387758faacc14d19fbc2b72ae06890c"; FENCE_CORRECTION_RECEIPT_DIGEST="29a393ac76236564c5663ebd1bf5920b4dd0a8574907fbceeff4b130de873b43"; HYDRATION_TRANSITION_DIGEST="9e91fbaae5eda3dd058097e75e73765d276978f98b79df8570d7b253c05e6235"
COORDINATION_LEDGER_DIGEST="9abdd8c33c9ef0db0681c686f2431228fb9174c435d312b3258d0883986a71f7"; COORDINATION_PROJECTION_DIGEST="12de0e5d8b3e873909f9d66caa59d74fae5c0947f14e30e99bbfb85ef487c3fd"
AUTHORIZED_OVERLAP_COUNT=1761; UNAUTHORIZED_OVERLAP_COUNT=0

SCHEMA_PATH="Scripts/v23/schedule.schema.json"; CONTRACT_PATH="docs/design/v23/tooling/V23P03C28ScheduleContractV1.json"
EVIDENCE_PATH="docs/design/v23/tooling/V23P03C28ScheduleEvidenceReceiptV1.json"; BRAND_PATH="docs/design/v23/tooling/V23P03C28BrandImpactManifestV1.json"; MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C28-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c28_contracts.py","Scripts/v23/generate_p03_c28_contracts.py","Scripts/v23/verify_p03_c28_contracts.py")
GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)

sys.path.insert(0,str(Path(__file__).resolve().parent))
import p03_c27_contracts as _c27
EXISTING_ADDITIONS=(
"FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift","FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift","FieldEvidenceApp/Domain/Models/ObservationAndTimeModelsV1.swift","FieldEvidenceApp/Domain/Workflow/TimeContextRule.swift","FieldEvidenceApp/Domain/Workflow/WorkRule.swift","FieldEvidenceApp/Infrastructure/System/DeviceTimeSemanticsV1.swift","FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift","FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift","FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift","FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift","FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift","FieldEvidenceApp/Infrastructure/WorkPacket/WorkPacketManifestLifecycleAdapterV1.swift","FieldEvidenceApp/Application/WorkPacket/WorkPacketManifestCoordinatorV1.swift","FieldEvidenceApp/Domain/Models/WorkPacketManifestPersistenceModelsV1.swift","FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift","FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift","FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift","FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift","FieldEvidenceApp/Domain/Models/SurveyDefinitionPersistenceModelsV1.swift","FieldEvidenceApp/Application/Workflow/SurveySessionCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Workflow/SurveySessionLifecycleAdapterV1.swift","FieldEvidenceApp/Domain/Models/SurveySessionPersistenceModelsV1.swift","FieldEvidenceAppTests/V9_29WorkPacketManifestTests.swift","FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift","FieldEvidenceAppTests/V9_40SurveySessionTests.swift","FieldEvidenceAppTests/V9_11ObservationTemporalSemanticsTests.swift","FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests.swift","FieldEvidenceAppTests/V9_35ClientCapabilityPackageLifecycleTests.swift","FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift")
EXISTING_PATHS=tuple(_c27.EXISTING_PATHS)+EXISTING_ADDITIONS
NEW_PATHS=("FieldEvidenceApp/Domain/Workflow/ScheduleContractsV1.swift","FieldEvidenceApp/Domain/Models/SchedulePersistenceModelsV1.swift","FieldEvidenceApp/Application/Workflow/ScheduleCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Workflow/ScheduleLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_42ScheduleTests.swift","FieldEvidenceAppTests/Fixtures/V22/Schedules/V22P03C28ScheduleCorpusV1.json",*SCRIPT_PATHS,*GENERATED_PATHS)
PATH_FENCE=EXISTING_PATHS+NEW_PATHS; MANIFEST_INPUT_PATHS=tuple(p for p in PATH_FENCE if p!=MANIFEST_PATH)

CONTRACT_NAMES=("ScheduleDefinitionReleaseV1","OccurrenceIDV1","OccurrenceStateV1","ScheduleExceptionV1","DueQueueProjectionV1","ReminderProjectionV1")
PERSISTED_FAMILIES=("ScheduleDefinitionReleaseV1","OccurrenceHistoryEventV1"); NONPERSISTENT_FAMILIES=("DueQueueProjectionV1","ReminderProjectionV1","ScheduleGenerationPlanV1")
OCCURRENCE_STATES=("UPCOMING","READY","DUE","OVERDUE","DEFERRED","MISSED","SKIPPED","CANCELLED","STARTED","COMPLETED")
SCHEDULE_ACTIONS=("CREATE","EDIT_SUCCESSOR","PAUSE","RESUME","END","RETIRE")
TEST_METHODS=("testV23P03C28G01DeterministicScheduleAndOccurrenceIdentitySurviveDSTAndTravel","testV23P03C28A01FixedAndCompletionRelativePoliciesRemainDistinct","testV23P03C28H01AmbiguousNonexistentRollbackDuplicateAndLateCompletionFailClosed","testV23P03C28I01BoundedGenerationAndOccurrenceHistoryRetryIdempotently","testV23P03C28R01RestoreRebuildsDueQueueAndReminderProjectionWithoutNotificationTruth")
EVIDENCE_IDS=tuple(f"{CARD}-{s}" for s in ("G01","A01","H01","I01","R01"))
FLAGS={k:False for k in ("native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
PERSISTENCE={"schemaRelease":"SCHEDULE_V1","persistentSchemaVersion":27,"recordsSchemaVersion":26,"persistentKindLifecycleModelCount":96,"durableFamilyCount":2,"persistedFamilies":list(PERSISTED_FAMILIES),"nonPersistentFamilies":list(NONPERSISTENT_FAMILIES),"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V27_WRITE"}
DIRECT_PREREQUISITE_EVIDENCE={"schema":"ProvisionalExecutionPrerequisiteSetReceiptV1","schemaVersion":1,"successorCardID":CARD,"successorAttemptID":1,"ordinaryDirectEdgeCount":1,"predecessors":[{"cardID":"V23-P03-C25","attemptID":1,"disposition":"CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C25_HEAD"}],"canonicalRelationPreserved":True,"nonreleaseSpecialEdgeApplied":False,"disposition":"PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY","nativeCompileRan":False,"physicalLockedState":"REQUIRED_PENDING_OWNER","acceptanceCredit":False,"releaseCredit":False,"prerequisiteDigest":PREREQUISITE_DIGEST}

def canonical(v:Any)->bytes:return json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
def pretty(v:Any)->bytes:return (json.dumps(v,ensure_ascii=False,sort_keys=True,indent=2,allow_nan=False)+"\n").encode()
def sha256_bytes(v:bytes)->str:return hashlib.sha256(v).hexdigest()
def sha256_value(v:Any)->str:return sha256_bytes(canonical(v))
def _base_path_exists(root:Path,p:str)->bool:return subprocess.run(["git","-C",str(root),"cat-file","-e",f"{BASE_HEAD}:{p}"],capture_output=True).returncode==0
def _observed_selectors(root:Path)->tuple[str,...]:
 p=root/"FieldEvidenceAppTests/V9_42ScheduleTests.swift"
 if not p.is_file():return TEST_METHODS
 return tuple(re.findall(r"\bfunc\s+(testV23P03C28(?:G|A|H|I|R)\w*)\s*\(",p.read_text(encoding="utf-8")))
def authority()->dict[str,Any]:return {"cardID":CARD,"attemptID":1,"registerOrdinal":REGISTER_ORDINAL,"title":TITLE,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":COORDINATION_CAS_SEQUENCE,"hydrationRevision":HYDRATION_REVISION,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"fenceCorrectionReceiptDigest":FENCE_CORRECTION_RECEIPT_DIGEST,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"coordinationLedgerDigest":COORDINATION_LEDGER_DIGEST,"coordinationProjectionDigest":COORDINATION_PROJECTION_DIGEST,"allowedPathCount":len(PATH_FENCE),"existingPathCount":len(EXISTING_PATHS),"newPathCount":len(NEW_PATHS),"directPrerequisiteCards":["V23-P03-C25"],"nextCard":"V23-P03-C29","digestPinsPending":False}
def _sealed(v:dict[str,Any])->dict[str,Any]:return {**v,"artifactDigest":sha256_bytes(pretty(v))}
def schema_document()->dict[str,Any]:return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/schedule.schema.json","title":"V23 P03 C28 Schedule Corpus","type":"object","additionalProperties":False,"properties":{"schema":{"const":"V22P03C28ScheduleCorpusV1"},"schemaVersion":{"const":1},"cardID":{"const":CARD},"persistentSchemaVersion":{"const":27},"recordsSchemaVersion":{"const":26},"persistentKindLifecycleModelCount":{"const":96},"durableFamilyCount":{"const":2},"durableFamilies":{"type":"array","const":list(PERSISTED_FAMILIES)},"occurrenceStates":{"type":"array","const":list(OCCURRENCE_STATES)},"requiredContractNames":{"type":"array","const":list(CONTRACT_NAMES)},"statusFlags":{"type":"object","additionalProperties":{"const":False}}},"required":["schema","schemaVersion","cardID","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","durableFamilyCount","durableFamilies","occurrenceStates","requiredContractNames","statusFlags"]}
def contract_document(root:Path)->dict[str,Any]:
 required={"contractNames":list(CONTRACT_NAMES),"occurrenceStates":list(OCCURRENCE_STATES),"scheduleActions":list(SCHEDULE_ACTIONS),"persistentFamilies":list(PERSISTED_FAMILIES),"nonPersistentFamilies":list(NONPERSISTENT_FAMILIES),"fiveSelectors":list(_observed_selectors(root)),"fixedAndCompletionRelativeDistinct":True,"frozenTimeZoneAndDSTBasis":True,"deterministicBoundedGeneration":True,"notificationDeliveryIsTruth":False,"deviceCurrentTimeZoneReinterpretation":False,"unboundedGeneration":False,"historyRewritten":False}
 return _sealed({"schema":"V23P03C28ScheduleContractV1","schemaVersion":1,"authority":authority(),"persistence":PERSISTENCE,"directPrerequisiteEvidence":DIRECT_PREREQUISITE_EVIDENCE,"requiredSemantics":required})
def evidence_document(root:Path)->dict[str,Any]:
 required=contract_document(root)["requiredSemantics"];return _sealed({"schema":"V23P03C28ScheduleEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"evidenceIDs":list(EVIDENCE_IDS),"testSelectors":list(_observed_selectors(root)),"requiredSemanticsDigest":sha256_value(required),"statusFlags":FLAGS})
def brand_document()->dict[str,Any]:return _sealed({"schema":"V23P03C28BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":False,"brandSurfaceDelta":True,"changedStates":list(OCCURRENCE_STATES),"nativeIPadSurface":False,"telemetry":False,"statusFlags":FLAGS})
def _row(root:Path,p:str,r:dict[str,bytes])->dict[str,Any]:
 raw=r[p] if p in r else (root/p).read_bytes();return {"path":p,"sha256":sha256_bytes(raw),"byteCount":len(raw)}
def all_outputs(root:Path)->dict[str,bytes]:
 r={SCHEMA_PATH:pretty(schema_document()),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,r) for p in MANIFEST_INPUT_PATHS];r[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C28ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":len(PATH_FENCE),"existingPathCount":len(EXISTING_PATHS),"newPathCount":len(NEW_PATHS),"authorizedOverlapCount":AUTHORIZED_OVERLAP_COUNT,"unauthorizedOverlapCount":UNAUTHORIZED_OVERLAP_COUNT,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"statusFlags":FLAGS}));return r
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(146,14,160) or len(set(PATH_FENCE))!=160:raise ValueError("C28 corrected fence must be unique 160=146+14")
 if any("s10" in p.lower() or "phase10" in p.lower() for p in PATH_FENCE):raise ValueError("C28 S10 overlap")
 for p in EXISTING_PATHS:
  if not _base_path_exists(root,p):raise ValueError(f"existing absent at base:{p}")
 for p in NEW_PATHS:
  if _base_path_exists(root,p):raise ValueError(f"new existed at base:{p}")
