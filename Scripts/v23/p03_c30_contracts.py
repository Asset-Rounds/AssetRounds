#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C30."""
from __future__ import annotations
import hashlib,json,re,subprocess,sys
from pathlib import Path
from typing import Any
sys.dont_write_bytecode=True

CARD="V23-P03-C30";TITLE="Day, night, and operating-context evidence semantics with paired-comparison provenance";REGISTER_ORDINAL=68
BASE_HEAD="08841c808ab5fe263b41db530e4e733f8126adb4";BASE_TREE="19b59129672300d130b96b7115c9fce1aef1a8e5"
COORDINATION_HEAD="875eb4211ae389ebceb9333c3895d345c5be8f84";COORDINATION_TREE="d8698f66110a371993e62dd2489aee9a63057263";COORDINATION_CAS_SEQUENCE=290;HYDRATION_REVISION=1
PREREQUISITE_DIGEST="9e66962109303b6c2e236af1ba43cdf0b79746f13c6cf83e286fdb1f7d88b70a";CONTEXT_DIGEST="9689e557880781b54e2405585434d699d2b93646770f99dcd6e5f4e423622e74";FENCE_DIGEST="ce331285b7a191fb7f6dbd3756a0575224b8bbf1c1c479ae6af1409dfca54ff6";HYDRATION_TRANSITION_DIGEST="83f785413c59782f64db43e4052cafa21cf9ed673d46c7b186bfe1474b5d3323";COORDINATION_LEDGER_DIGEST="4d1bd94d68bb68c0c6873f62b0e98048fba6dada0669c004a411e7349943f367";COORDINATION_PROJECTION_DIGEST="a261af880c157f21eb0963566ace5e9f4d338e0ad461ab76cb8e32135ac78cd0"
AUTHORIZED_OVERLAP_COUNT=2343;UNAUTHORIZED_OVERLAP_COUNT=0
SCHEMA_PATH="Scripts/v23/evidence-context.schema.json";CONTRACT_PATH="docs/design/v23/tooling/V23P03C30EvidenceContextContractV1.json";EVIDENCE_PATH="docs/design/v23/tooling/V23P03C30EvidenceContextEvidenceReceiptV1.json";BRAND_PATH="docs/design/v23/tooling/V23P03C30BrandImpactManifestV1.json";MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C30-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c30_contracts.py","Scripts/v23/generate_p03_c30_contracts.py","Scripts/v23/verify_p03_c30_contracts.py");GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)
sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c37_contracts as _c37
EXISTING_PATHS=tuple(_c37.EXISTING_PATHS)+tuple(_c37.NEW_PATHS[:6])
NEW_PATHS=("FieldEvidenceApp/Domain/EvidenceContext/EvidenceContextContractsV1.swift","FieldEvidenceApp/Domain/Models/EvidenceContextPersistenceModelsV1.swift","FieldEvidenceApp/Application/EvidenceContext/EvidenceContextCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/EvidenceContext/EvidenceContextLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_45EvidenceContextTests.swift","FieldEvidenceAppTests/Fixtures/V22/EvidenceContext/V22P03C30EvidenceContextCorpusV1.json",*SCRIPT_PATHS,*GENERATED_PATHS)
PATH_FENCE=EXISTING_PATHS+NEW_PATHS;MANIFEST_INPUT_PATHS=tuple(p for p in PATH_FENCE if p!=MANIFEST_PATH)
CONTRACT_NAMES=("EvidenceLightingConditionV1","UserObservedEvidenceContextV1","SolarLocationV1","SolarPolarDispositionV1","DerivedSolarConditionV1","SolarEventInstantV1","DerivedSolarContextV1","SolarCalculationInputV1","OfflineSolarCalculatorV1","ControlExpectationV1","EvidenceContextV1","PairedObservationPurposeV1","PairedObservationReferenceV1","PairedObservationMismatchReasonV1","PairedObservationLinkV1","EvidenceContextCanonicalCodecV1","EvidenceContextWriteOperationV1","EvidenceContextWriteReceiptV1")
TEST_METHODS=("testV23P03C30G01ExplicitConditionsAndOfflineSolarDerivationAreDeterministic","testV23P03C30A01CoveredAndUnknownContextsRetainUserTruthAndStablePairing","testV23P03C30H01MissingLocationTimeConflictsAndPurposeMismatchFailClosed","testV23P03C30I01InterruptedContextAndPairWritesRecoverAsZeroOrOneCanonicalSuccess","testV23P03C30R01RestoreReplayRebuildAndHistoricContextRemainByteExact")
FLAGS={k:False for k in ("native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
PERSISTENCE_PINS_PENDING=False
PERSISTENCE:dict[str,Any]={"schemaRelease":"EVIDENCE_CONTEXT_V1","persistentSchemaVersion":30,"recordsSchemaVersion":29,"persistentKindLifecycleModelCount":104,"durableFamilyCount":2,"persistedFamilies":["EvidenceContextRow","PairedObservationLinkRow"],"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V30_WRITE"}

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
 p=root/"FieldEvidenceAppTests/V9_45EvidenceContextTests.swift"
 if not p.is_file():return ()
 return tuple(re.findall(r"\bfunc\s+(testV23P03C30(?:G|A|H|I|R)\d{2}\w*)\s*\(",p.read_text(encoding="utf-8")))
def require_source_ready(root:Path)->None:
 required=("FieldEvidenceApp/Domain/EvidenceContext/EvidenceContextContractsV1.swift","FieldEvidenceApp/Domain/Models/EvidenceContextPersistenceModelsV1.swift","FieldEvidenceApp/Application/EvidenceContext/EvidenceContextCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/EvidenceContext/EvidenceContextLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_45EvidenceContextTests.swift")
 missing=[p for p in required if not (root/p).is_file()]
 if missing:raise ValueError("C30 stable source absent:"+",".join(missing))
 selectors=observed_selectors(root)
 if len(selectors)!=5 or {s[len("testV23P03C30")] for s in selectors}!={"G","A","H","I","R"}:raise ValueError("C30 exact G/A/H/I/R selectors absent")
 if PERSISTENCE_PINS_PENDING or any(PERSISTENCE[k] is None for k in ("schemaRelease","persistentSchemaVersion","recordsSchemaVersion","persistentKindLifecycleModelCount","durableFamilyCount","persistedFamilies","downgrade")):raise ValueError("C30 persistence pins await stable canonical source")
def _tokens(root:Path,path:str,*tokens:str)->str:
 p=root/path
 if not p.is_file():raise ValueError(f"C30 source absent:{path}")
 text=p.read_text(encoding="utf-8");missing=[x for x in tokens if x not in text]
 if missing:raise ValueError(f"C30 source regression:{path}:"+",".join(missing))
 return text
def assert_source_regressions(root:Path)->None:
 require_source_ready(root)
 core=_tokens(root,"FieldEvidenceApp/Domain/EvidenceContext/EvidenceContextContractsV1.swift","enum EvidenceLightingConditionV1","struct UserObservedEvidenceContextV1","source = .userObserved","struct SolarLocationV1","enum SolarPolarDispositionV1","struct DerivedSolarContextV1","struct SolarCalculationInputV1","enum OfflineSolarCalculatorV1","static func calculate(_ input: SolarCalculationInputV1)","struct ControlExpectationV1","A policy expectation only. No field represents observed operation","compliance, approval, or inferred equipment state","struct EvidenceContextV1","let userObserved: UserObservedEvidenceContextV1","let derivedSolar: DerivedSolarContextV1?","struct PairedObservationReferenceV1","enum PairedObservationMismatchReasonV1","struct PairedObservationLinkV1","func validateCompatiblePair()","static func mismatches","enum EvidenceContextCanonicalCodecV1")
 if re.search(r"\blet\s+(?:photo|image|inferredCondition|complianceState)\b",core):raise ValueError("C30 prohibited inference field surfaced")
 models=_tokens(root,"FieldEvidenceApp/Domain/Models/EvidenceContextPersistenceModelsV1.swift","@Model final class EvidenceContextRow","@Model final class PairedObservationLinkRow","persistentSchemaVersion=30","recordsSchemaVersion=29","durableModelCount=2","totalModelCount=104")
 if len(re.findall(r"@Model\s+final\s+class",models))!=2:raise ValueError("C30 persistence must remain exactly two rows")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","enum PersistentSchemaV30","EvidenceContextRow.self","PairedObservationLinkRow.self")
 _tokens(root,"FieldEvidenceApp/Application/EvidenceContext/EvidenceContextCoordinatorV1.swift","enum EvidenceContextWriteOperationV1","case appendContext","case appendPair","struct EvidenceContextWriteReceiptV1","final class EvidenceContextCoordinatorV1","let receipt = try await authority.commit(operation)")
 _tokens(root,"FieldEvidenceApp/Infrastructure/EvidenceContext/EvidenceContextLifecycleAdapterV1.swift","protocol EvidenceContextCanonicalWorkspaceWritingV1","final class EvidenceContextLifecycleAdapterV1","let receipt = try writer.commitEvidenceContext(operation)","try receipt.validate()")
 _tokens(root,"FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift","case applyEvidenceContext(EvidenceContextWriteOperationV1)","case applyEvidenceContext=\"apply_evidence_context\"")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","case let .applyEvidenceContext(value):return try applyEvidenceContext")
 _tokens(root,"FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","let evidenceContexts: [V30BackupEvidenceContextRecordV1]","let pairedObservationLinks: [V30BackupEvidenceContextRecordV1]","case workflowRecords, evidenceContexts, pairedObservationLinks","func validateC30EvidenceContextClosure() throws","$0.workspaceID == endpoint.workspaceID","$0.evidenceSHA256 == endpoint.evidenceSHA256","$0.evidenceRevision == endpoint.evidenceRevision","$0.assetID == endpoint.assetID","$0.assetRevision == endpoint.assetRevision")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift","if records.recordsSchemaVersion >= 29","fields[\"evidenceContexts\"]","fields[\"pairedObservationLinks\"]","guard (4...29).contains(records.recordsSchemaVersion)","records.recordsSchemaVersion == 29")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift","try records.validateC30EvidenceContextClosure()")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift","enum C30EvidenceContextPackageValidationV1","try records.validateC30EvidenceContextClosure()")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","validateEvidencePairPurpose(value,existing:rows)","historical.allSatisfy({$0.purpose==candidate.purpose&&$0.purposeRevision==candidate.purposeRevision})")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift","validateEvidenceContextReferences(_ operation:EvidenceContextWriteOperationV1)","$0.purpose==candidate.purpose&&$0.purposeRevision==candidate.purposeRevision")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift","validateEvidencePairPurposeHistory","purposeByEvidence")
 _tokens(root,"FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift","contextID != SearchContractValidationV1.zeroUUID","linkID != SearchContractValidationV1.zeroUUID","PairedObservationLinkV1.mismatches(first, second) == mismatchReasons","func validate(boundTo context: EvidenceContextV1)")
 _tokens(root,"FieldEvidenceApp/Domain/EvidenceContext/EvidenceContextContractsV1.swift","static func exactInt64(_ value: Double) throws -> Int64","rounded.isFinite","rounded < Double(Int64.max)","static func utcEpochSecond(_ value: Date)","static func timeZone(_ identifier: String, matchesUTCOffset offset: Int","TimeZone(identifier: identifier)","timeZone.secondsFromGMT(for: date) == offset","static func validateTimeZoneIfDeclared(in temporal: TemporalContextV1)","validateTimeZoneIfDeclared(in: temporalContext)")
 for path in ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift","FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift","FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift","FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift","FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift"):_tokens(root,path,"C30")
 tests=_tokens(root,"FieldEvidenceAppTests/V9_45EvidenceContextTests.swift",*TEST_METHODS,"XCTAssertEqual(explicit.source, .userObserved)","XCTAssertNil(covered.derivedSolar)","PairedObservationLinkV1.mismatches","INVALID_TIME_ZONE","OFFSET_CONFLICT","EXTREME_FINITE_DATE","INT64_CONVERSION_OVERFLOW","DANGLING_PAIRED_ENDPOINT","REPORT_ZERO_UUID","REPORT_LINK_IDENTITY_MISMATCH","CONFLICTING_COMPARISON_PURPOSE","XCTAssertNil(polar.sunrise)","XCTAssertNil(polar.sunset)")
 if tests.count("XCTAssertThrowsError")<8:raise ValueError("C30 hostile coverage regressed")
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(188,14,202) or len(set(PATH_FENCE))!=202:raise ValueError("C30 fence must be unique 202=188+14")
 if any("s10" in p.lower() or "phase10" in p.lower() for p in PATH_FENCE):raise ValueError("C30 S10 overlap")
 if subprocess.run(["git","-C",str(root),"show","-s","--format=%T",BASE_HEAD],check=True,capture_output=True,text=True).stdout.strip()!=BASE_TREE:raise ValueError("C30 base tree differs")
 for p in EXISTING_PATHS:
  if not _base_exists(root,p):raise ValueError(f"existing absent at base:{p}")
 for p in NEW_PATHS:
  if _base_exists(root,p):raise ValueError(f"new existed at base:{p}")
 if AUTHORIZED_OVERLAP_COUNT!=2343 or UNAUTHORIZED_OVERLAP_COUNT!=0 or any(FLAGS.values()):raise ValueError("C30 authority proof differs")
def authority()->dict[str,Any]:return {"cardID":CARD,"attemptID":1,"registerOrdinal":REGISTER_ORDINAL,"title":TITLE,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":COORDINATION_CAS_SEQUENCE,"hydrationRevision":HYDRATION_REVISION,"prerequisiteDigest":PREREQUISITE_DIGEST,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"coordinationLedgerDigest":COORDINATION_LEDGER_DIGEST,"coordinationProjectionDigest":COORDINATION_PROJECTION_DIGEST,"allowedPathCount":202,"existingPathCount":188,"newPathCount":14,"authorizedOverlapCount":2343,"unauthorizedOverlapCount":0,"directPrerequisiteCards":["V23-P03-C37"],"nextCard":"V23-P03-C31","digestPinsPending":PERSISTENCE_PINS_PENDING}
def _sealed(v:dict[str,Any])->dict[str,Any]:return {**v,"artifactDigest":sha256_bytes(pretty(v))}
def schema_document()->dict[str,Any]:return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/evidence-context.schema.json","title":"V23 P03 C30 Evidence Context Corpus","type":"object","additionalProperties":False,"properties":{"schema":{"const":"V22P03C30EvidenceContextCorpusV1"},"schemaVersion":{"const":1},"cardID":{"const":CARD},"persistentSchemaVersion":{"const":PERSISTENCE["persistentSchemaVersion"]},"recordsSchemaVersion":{"const":PERSISTENCE["recordsSchemaVersion"]},"durableFamilies":{"const":PERSISTENCE["persistedFamilies"]},"requiredContractNames":{"const":list(CONTRACT_NAMES)},"statusFlags":{"type":"object","additionalProperties":{"const":False}}},"required":["schema","schemaVersion","cardID","persistentSchemaVersion","recordsSchemaVersion","durableFamilies","requiredContractNames","statusFlags"]}
def contract_document(root:Path)->dict[str,Any]:
 assert_source_regressions(root);semantics={"contractNames":list(CONTRACT_NAMES),"fiveSelectors":list(observed_selectors(root)),"observedAndDerivedRemainDistinct":True,"offlineVersionedSolarDSTAndPolarNull":True,"explicitComparisonMismatchReasons":True,"timestampDoesNotInferContext":True,"photoDoesNotInferContext":True,"controlDoesNotInferCompliance":True,"canonicalV4RecordsSchema29EncoderDecoderWiring":True,"pairedEndpointGraphClosure":True,"deterministicNonzeroReportBinding":True,"onePhotoOnePurposeWriterJournalRecoveryAdmission":True,"timeZoneValidityAndExactOffsetConsistency":True,"guardedDateDoubleToInt64Conversion":True,"oneWorkspaceWriterAndReceipt":True,"backupDeleteSearchReportLocalizationAccessibilityClosure":True}
 return _sealed({"schema":"V23P03C30EvidenceContextContractV1","schemaVersion":1,"authority":authority(),"persistence":PERSISTENCE,"requiredSemantics":semantics})
def evidence_document(root:Path)->dict[str,Any]:
 contract=contract_document(root);return _sealed({"schema":"V23P03C30EvidenceContextEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"evidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],"testSelectors":list(observed_selectors(root)),"requiredSemanticsDigest":sha256_value(contract["requiredSemantics"]),"statusFlags":FLAGS})
def brand_document()->dict[str,Any]:return _sealed({"schema":"V23P03C30BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":False,"brandSurfaceDelta":True,"nativeIPadSurface":False,"telemetry":False,"statusFlags":FLAGS})
def _row(root:Path,p:str,r:dict[str,bytes])->dict[str,Any]:
 raw=r[p] if p in r else (root/p).read_bytes();return {"path":p,"sha256":sha256_bytes(raw),"byteCount":len(raw)}
def all_outputs(root:Path)->dict[str,bytes]:
 assert_source_regressions(root);r={SCHEMA_PATH:pretty(schema_document()),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,r) for p in MANIFEST_INPUT_PATHS];r[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C30ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":202,"existingPathCount":188,"newPathCount":14,"authorizedOverlapCount":2343,"unauthorizedOverlapCount":0,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"statusFlags":FLAGS}));return r
