#!/usr/bin/env python3
"""Fail-closed C53 asset-service reliability tooling."""
from __future__ import annotations
import hashlib,json,os,re,sys
from pathlib import Path
from typing import Any
os.environ["PYTHONDONTWRITEBYTECODE"]="1";sys.dont_write_bytecode=True
CARD="V23-P03-C53";ORDINAL=84;BASE_HEAD="0ecc7daf4b329b3aeb90a8e457e2700bf9d4fcbd";BASE_TREE="d063df00d73dc432be3c0d506dcf1baea7a28a88"
COORDINATION_HEAD="4941f4f636c5103948487ce3b0cf889aa5d26999";COORDINATION_TREE="8cb83a946372b82a2fd7786e23682f223a563197";CAS_SEQUENCE=355
CONTEXT_DIGEST="e2cdd39366c42ceda098600bd0f5bf4f03dd7a6dc5fbe487ad7bb9e4da29e021";FENCE_DIGEST="1a2efea842b850f3b8a0a773b4ff904f43d763d7b087bdf4a53e3cc621618892";PREREQUISITE_DIGEST="d2dce0eafd998405c462de14bfdf85648a354c37ae7dab8852d099b6679d09e8";PRIOR_C19_FENCE="4b39fc01e6f5a3a5c05ff754192369243c5ece0d021421adfc21dd93b0cdc4b1"
HYDRATION=Path(r"C:\AssetRounds-v23-coordination\contexts\V23-P03-C53-attempt-1\BootstrapPathFenceV1.json")
SCHEMA="Scripts/v23/asset-service-reliability.schema.json";CONTRACT="docs/design/v23/tooling/V23P03C53AssetServiceReliabilityContractV1.json";EVIDENCE="docs/design/v23/tooling/V23P03C53AssetServiceReliabilityEvidenceReceiptV1.json";BRAND="docs/design/v23/tooling/V23P03C53BrandImpactManifestV1.json";MANIFEST="docs/design/v23/tooling/V23-P03-C53-tooling-manifest.json"
SCRIPTS=("Scripts/v23/p03_c53_contracts.py","Scripts/v23/generate_p03_c53_contracts.py","Scripts/v23/verify_p03_c53_contracts.py")
IMPLEMENTATION=("FieldEvidenceApp/Domain/ServiceReliability/AssetServiceReliabilityContractsV1.swift","FieldEvidenceApp/Domain/Models/AssetServiceReliabilityPersistenceModelsV1.swift","FieldEvidenceApp/Application/ServiceReliability/AssetServiceReliabilityCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/ServiceReliability/AssetServiceReliabilityLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_61AssetServiceReliabilityTests.swift","FieldEvidenceAppTests/Fixtures/V22/ServiceReliability/V22P03C53AssetServiceReliabilityCorpusV1.json")
GENERATED=(CONTRACT,EVIDENCE,BRAND,MANIFEST);FLAGS={k:False for k in("activation","native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","physicalEvidence","phase10PollingDuringParallelExecution")};EVIDENCE_IDS=tuple(f"{CARD}-{x}" for x in("G01","A01","H01","I01","R01"))
BACKUP_PATHS=("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift","FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift","FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift","FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift")
JOURNAL_PATH="FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift";SEARCH_PATHS=("FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift","FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift","FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift")
def pretty(v:Any)->bytes:return (json.dumps(v,sort_keys=True,indent=2,ensure_ascii=False)+"\n").encode()
def _text(root:Path,path:str)->str:
 p=root/path
 if not p.is_file():raise ValueError("C53 source absent:"+path)
 return p.read_text(encoding="utf-8")
def _tokens(text:str,tokens:tuple[str,...],label:str)->None:
 missing=[token for token in tokens if token not in text]
 if missing:raise ValueError(label+" missing:"+",".join(missing))
def _hydration()->dict[str,Any]:
 if not HYDRATION.is_file():raise ValueError("C53 hydration absent")
 data=json.loads(HYDRATION.read_text(encoding="utf-8"))
 if data.get("cardID")!=CARD or data.get("fenceDigest")!=FENCE_DIGEST:raise ValueError("C53 hydration authority differs")
 return data
_H=_hydration();EXISTING=tuple(_H["existingPaths"]);NEW=tuple(_H["newPaths"]);FENCE=EXISTING+NEW
def _subsystems(root:Path)->None:
 backup=tuple(_text(root,path) for path in BACKUP_PATHS);journal=_text(root,JOURNAL_PATH);search=tuple(_text(root,path) for path in SEARCH_PATHS)
 _tokens(backup[0],("C53ServiceReliabilityBackupEnrollmentV1","V39BackupServiceReliabilityRecordV1","V39BackupServiceReliabilityReceiptRecordV1"),"C53 backup contracts")
 _tokens(backup[1],("validC53ServiceReliability","C53ServiceReliabilityBackupEncodingBoundaryV1"),"C53 backup encoding")
 _tokens(backup[2],("validateC53ServiceReliability","C53ServiceReliabilityBackupDecodingBoundaryV1"),"C53 backup decoding")
 _tokens(backup[3],("C53ServiceReliabilityBackupExportBoundaryV1","serviceReliabilityReceipts"),"C53 backup export")
 _tokens(backup[4],("C53ServiceReliabilityBackupImportServiceBoundaryV1","C53ServiceReliabilityBackupEnrollmentV1.validate"),"C53 backup import")
 _tokens(journal,("case let .applyServiceReliability","ServiceReliabilityMutationReceiptV1","C53AssetServiceReliabilityJournalBoundaryV1"),"C53 journal")
 _tokens(search[0],("C53ServiceReliabilitySearchProjectionV1","C53ServiceReliabilitySearchProjectionBoundaryV1"),"C53 search contract")
 _tokens(search[1],("C53ServiceReliabilitySearchPersistenceEnvelopeV1","C53ServiceReliabilitySearchPersistenceBoundaryV1"),"C53 search persistence")
 _tokens(search[2],("C53ServiceReliabilityLocalSearchIndexBoundaryV1","rawServiceReliabilityEventBytesAreNotIndexed = true"),"C53 search index")
 _tokens(search[3],("C53ServiceReliabilitySearchRebuildBoundaryV1","C53ServiceReliabilitySearchProjectionBoundaryV1.projection"),"C53 search rebuild")
def _sources(root:Path)->None:
 contracts,models,coordinator,lifecycle,tests,fixture=(_text(root,p) for p in IMPLEMENTATION)
 writer=_text(root,"FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift")
 _tokens(contracts,("AssetServiceIncidentV1","ServiceImpactSegmentV1","QualifiedServiceExposureV1","ReliabilityMetricInputProjectionV1","FULL_INTERRUPTION","DEGRADED","INTERMITTENT","UNKNOWN","PLANNED","UNPLANNED","exposure","unplannedFullDowntimeMilliseconds","operatingExposure","qualifyingFailureStartEventIDs","UNAVAILABLE_ZERO_QUALIFIED_EXPOSURE","maximal","ServiceReliabilityIntervalAlgebraV1.union","ServiceReliabilityIntervalAlgebraV1.subtract","expectedOperating","operatingExposure==expectedOperating"),"C53 E/D/O interval algebra")
 if re.search(r"\b(?:Double|Float)\b",contracts):raise ValueError("C53 exact interval contracts admit floating point")
 _tokens(models,("AssetServiceIncident","ServiceImpactSegment","QualifiedServiceExposure","Persistent","canonical"),"C53 persistence")
 _tokens(coordinator,("WorkspaceWriterV1","ServiceReliabilityAtomicBundleV1","ServiceReliabilityMutationReceiptV1","AssetServiceReliabilityCommitPlanV1","WorkspaceExpectedRevisionV1","writer.commitServiceReliability","try Self.validate(receipt, for: plan.bundle)","mutationReceipt.validate()"),"C53 sole-writer plan and receipt validation")
 _tokens(contracts,("ServiceReliabilityWriterReceiptV1","ServiceReliabilityAtomicBundleV1","ServiceReliabilityCanonicalValidatingV1","func validate()throws","canonicalMutationReceiptSHA256"),"C53 writer receipt contract")
 _tokens(writer,("extension WorkspaceWriterV1","commitServiceReliability","durableServiceReliabilityReceipt","ServiceReliabilityMutationReceiptV1","validateForCanonicalWriter"),"C53 sole workspace writer")
 _tokens(lifecycle,("AssetServiceReliabilityLifecycleAdapterV1","importAccepted","restoreAccepted","replayAccepted","rebuildDerivedProjection","erase(workspaceID:","createsSecondWriter = false","createsSecondMutableStore = false"),"C53 lifecycle composition")
 _tokens(tests,("testV23P03C53G01","testV23P03C53A01","testV23P03C53H01","testV23P03C53I01","testV23P03C53R01"),"C53 G/A/H/I/R")
 _tokens(fixture,(CARD,"G01","A01","H01","I01","R01"),"C53 corpus")
 _subsystems(root)
 executable="\n".join(line for line in "\n".join((contracts,models,coordinator,lifecycle)).splitlines() if not line.lstrip().startswith("//"))
 for forbidden in (r"\b(?:URLSession|WebSocket)\b",r"\b(?:telemetry|analytics|IoT|predictive|OEE|SLA|warranty|release.to.service|automatic.release)\b[^\n]*(?:=|:)\s*true\b"):
  if re.search(forbidden,executable,re.I):raise ValueError("C53 forbidden claim:"+forbidden)
def assert_scaffold(root:Path)->None:
 if (len(EXISTING),len(NEW),len(FENCE))!=(104,14,118):raise ValueError("C53 fence cardinality")
 if NEW!=(*IMPLEMENTATION,*SCRIPTS,SCHEMA,*GENERATED):raise ValueError("C53 hydration new paths differ")
 if len(set(FENCE))!=118 or any(FLAGS.values()):raise ValueError("C53 fence or flags")
 _tokens(_text(root,SCHEMA),(CARD,"V23P03C53AssetServiceReliabilityContractV1"),"C53 schema")
def authority()->dict[str,Any]:return {"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":CAS_SEQUENCE,"contextDigest":CONTEXT_DIGEST,"pathFenceDigest":FENCE_DIGEST,"provisionalPrerequisiteDigest":PREREQUISITE_DIGEST,"registerOrdinal":ORDINAL,"directPrerequisiteFences":{"V23-P03-C19":PRIOR_C19_FENCE},"inheritedV21PayloadPresent":False}
def all_outputs(root:Path)->dict[str,bytes]:
 assert_scaffold(root);_sources(root);common={"cardID":CARD,"authority":authority(),"evidenceIDs":list(EVIDENCE_IDS),"statusFlags":FLAGS,"priorPrerequisiteProof":{"cards":["V23-P03-C19"],"fences":{"V23-P03-C19":PRIOR_C19_FENCE},"liveResealRequired":False},"s10ReservationOverlapCount":0,"s10ReservedPathCount":86}
 out={CONTRACT:pretty({"schema":"V23P03C53AssetServiceReliabilityContractV1","schemaVersion":1,**common,"semantics":{"exactIntegerIntervals":True,"expectedExposureMinusUnplannedFullDowntime":"O=E\\D","maximalDowntimeQualifiedStartsOnly":True,"degradedIntermittentUnweighted":True,"unavailableZeroQualifiedExposure":"UNAVAILABLE_ZERO_QUALIFIED_EXPOSURE","noInfinity":True}}),EVIDENCE:pretty({"schema":"V23P03C53AssetServiceReliabilityEvidenceReceiptV1","schemaVersion":1,**common,"journey":"FJ09","cases":list(EVIDENCE_IDS),"nativeCompileRan":False,"hostedDispatchEnabled":False,"physicalLockedState":"REQUIRED_PENDING_OWNER"}),BRAND:pretty({"schema":"V23P03C53BrandImpactManifestV1","schemaVersion":1,**common,"uiSurfaceDelta":True,"brandSurfaceDelta":True,"telemetryOrPredictiveMaintenance":False,"automaticReleaseToService":False})}
 files=[]
 for path in FENCE:
  if path==MANIFEST:continue
  data=out[path] if path in out else (root/path).read_bytes();files.append({"path":path,"byteCount":len(data),"sha256":hashlib.sha256(data).hexdigest()})
 out[MANIFEST]=pretty({"schema":"V23P03C53ToolingManifestV1","schemaVersion":1,**common,"existingPathCount":104,"newPathCount":14,"fencePathCount":118,"files":files});return out
