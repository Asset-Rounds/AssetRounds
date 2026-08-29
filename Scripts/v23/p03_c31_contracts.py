#!/usr/bin/env python3
"""Deterministic provisional tooling model for V23-P03-C31."""
from __future__ import annotations
import hashlib,json,re,subprocess,sys
from pathlib import Path
from typing import Any
sys.dont_write_bytecode=True

CARD="V23-P03-C31";TITLE="Exterior and parking-lighting package, shared topology, observational claims, and measurement boundary";REGISTER_ORDINAL=69
BASE_HEAD="81fb371d7774684ebcee94a8a15c675a966848d1";BASE_TREE="5db17061ee362c64b9c9dde3753108e50d365609"
COORDINATION_HEAD="162218beead4494ea3a3ed48c79273825f7e6394";COORDINATION_TREE="95931020af8e24f4162eec3d313b63ec9ce2f7be";COORDINATION_CAS_SEQUENCE=294;HYDRATION_REVISION=1
PREREQUISITE_DIGEST="15a24d69743b332cf32cbb06c7d59fe29b27d9b56b11a6fd5796206e22c435b7";CONTEXT_DIGEST="df713e7fb33855d75ab8eb01e95c24dbd4271aaaf9530d8fc0199725cf55cd26";FENCE_DIGEST="ea730d30ec67055fcb981fa085653e9e5171e1fbb94e8f7780bfaa3c937b964a";HYDRATION_TRANSITION_DIGEST="3453ce470e7f6e24887162c0aa2027ba9aaf35c4697221f1d3fc8a8ddd56d6ff";COORDINATION_LEDGER_DIGEST="f90518605a1fdf504733edd243475df4a2673edeee731d3c4005bea63cb360ff";COORDINATION_PROJECTION_DIGEST="75d6335c6a5a911a666a8ebfeb0152317b4b6a62f329c29b8b40de6ea1e82c0d"
AUTHORIZED_OVERLAP_COUNT=2537;UNAUTHORIZED_OVERLAP_COUNT=0
SCHEMA_PATH="Scripts/v23/lighting-package.schema.json";CONTRACT_PATH="docs/design/v23/tooling/V23P03C31LightingPackageContractV1.json";EVIDENCE_PATH="docs/design/v23/tooling/V23P03C31LightingPackageEvidenceReceiptV1.json";BRAND_PATH="docs/design/v23/tooling/V23P03C31BrandImpactManifestV1.json";MANIFEST_PATH="docs/design/v23/tooling/V23-P03-C31-tooling-manifest.json"
SCRIPT_PATHS=("Scripts/v23/p03_c31_contracts.py","Scripts/v23/generate_p03_c31_contracts.py","Scripts/v23/verify_p03_c31_contracts.py");GENERATED_PATHS=(SCHEMA_PATH,CONTRACT_PATH,EVIDENCE_PATH,BRAND_PATH,MANIFEST_PATH)
sys.path.insert(0,str(Path(__file__).resolve().parent));import p03_c30_contracts as _c30
EXISTING_PATHS=tuple(_c30.EXISTING_PATHS)+tuple(_c30.NEW_PATHS[:6])
NEW_PATHS=("FieldEvidenceApp/Domain/Lighting/LightingContractsV1.swift","FieldEvidenceApp/Domain/Models/LightingPersistenceModelsV1.swift","FieldEvidenceApp/Application/Lighting/LightingCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Lighting/LightingLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_46LightingPackageTests.swift","FieldEvidenceAppTests/Fixtures/V22/Lighting/V22P03C31LightingPackageCorpusV1.json",*SCRIPT_PATHS,*GENERATED_PATHS)
PATH_FENCE=EXISTING_PATHS+NEW_PATHS;MANIFEST_INPUT_PATHS=tuple(p for p in PATH_FENCE if p!=MANIFEST_PATH)
CONTRACT_NAMES=("LightingSystemV1","LightingZoneV1","ControlGroupV1","LuminaireAssetV1","LightingObservationV1","LightingIssueV1","MeasurementPlanV1","CriterionReferenceV1","LightingClaimStateV1")
TEST_METHODS=("testV23P03C31G01LightingTopologyObservationAndMeasurementBoundariesAreExact","testV23P03C31A01SharedSupportsMultiHeadAndMultiAreaTopologyWithoutClones","testV23P03C31H01ForbiddenClaimsInvalidMeasurementsAndUnsafeWorkFailClosed","testV23P03C31I01InterruptedLightingMutationRecoversAsZeroOrOneCanonicalSuccess","testV23P03C31R01RestoreReplayAndHistoricLightingReportsRemainExact")
FLAGS={k:False for k in ("native","hosted","adoption","acceptance","release","nativeAcceptance","hostedAcceptance","adoptionEvidence","acceptanceCredit","releaseReadiness","phase10PollingDuringParallelExecution")}
PERSISTENCE_PINS_PENDING=False
PERSISTENCE:dict[str,Any]={"schemaRelease":"LIGHTING_PACKAGE_V1","persistentSchemaVersion":31,"recordsSchemaVersion":30,"persistentKindLifecycleModelCount":109,"durableFamilyCount":5,"persistedFamilies":["LightingSystemRow","LightingObservationRow","LightingIssueRow","MeasurementPlanRow","LightingClaimStateRow"],"mode":"NEW_SCHEMA_VERSION","migrationRequired":True,"backupRestoreRequired":True,"cloneForkRequired":True,"deleteEraseRequired":True,"exportReportRequired":True,"searchRebuildRequired":True,"replayRequired":True,"interruptionRecoveryRequired":True,"downgrade":"PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V31_WRITE"}

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
 p=root/"FieldEvidenceAppTests/V9_46LightingPackageTests.swift"
 if not p.is_file():return ()
 return tuple(re.findall(r"\bfunc\s+(testV23P03C31(?:G|A|H|I|R)\d{2}\w*)\s*\(",p.read_text(encoding="utf-8")))
def require_source_ready(root:Path)->None:
 required=("FieldEvidenceApp/Domain/Lighting/LightingContractsV1.swift","FieldEvidenceApp/Domain/Models/LightingPersistenceModelsV1.swift","FieldEvidenceApp/Application/Lighting/LightingCoordinatorV1.swift","FieldEvidenceApp/Infrastructure/Lighting/LightingLifecycleAdapterV1.swift","FieldEvidenceAppTests/V9_46LightingPackageTests.swift")
 missing=[p for p in required if not (root/p).is_file()]
 if missing:raise ValueError("C31 stable source absent:"+",".join(missing))
 selectors=observed_selectors(root)
 if len(selectors)!=5 or {s[len("testV23P03C31")] for s in selectors}!={"G","A","H","I","R"}:raise ValueError("C31 exact G/A/H/I/R selectors absent")
 if PERSISTENCE_PINS_PENDING or PERSISTENCE["persistedFamilies"] != ["LightingSystemRow","LightingObservationRow","LightingIssueRow","MeasurementPlanRow","LightingClaimStateRow"]:raise ValueError("C31 exact five persisted family names differ")
def _tokens(root:Path,path:str,*tokens:str)->str:
 p=root/path
 if not p.is_file():raise ValueError(f"C31 source absent:{path}")
 text=p.read_text(encoding="utf-8");missing=[x for x in tokens if x not in text]
 if missing:raise ValueError(f"C31 source regression:{path}:"+",".join(missing))
 return text
def assert_source_regressions(root:Path)->None:
 require_source_ready(root)
 core=_tokens(root,"FieldEvidenceApp/Domain/Lighting/LightingContractsV1.swift",*CONTRACT_NAMES,"OBSERVED","MEASURED","DERIVED","SCREENED","ATTESTED","LightingTopologyAdmissionClosureV1","current.eventID == eventID","current.action != .ended","LightingIssueAdmissionClosureV1","workspaceID==source.workspaceID","subjectAssetID==source.assetID","LightingClaimAdmissionClosureV1","validateMeasurementBasis","protocolRelease.recordedAt<=capture.capturedAt","calibration.effectiveAt.map{$0<=capture.capturedAt}==true","calibration.expiresAt.map{capture.capturedAt<=$0}==true","LightingSafetyGateV1","trafficControlAuthorized","energizedWorkAuthorized")
 if re.search(r"\blet\s+(?:inferredLux|inferredFootcandles|photoLux|exifLux|complianceState)\b",core,re.I):raise ValueError("C31 photo/EXIF inference field surfaced")
 models=_tokens(root,"FieldEvidenceApp/Domain/Models/LightingPersistenceModelsV1.swift","@Model final class LightingSystemRow","@Model final class LightingObservationRow","@Model final class LightingIssueRow","@Model final class MeasurementPlanRow","@Model final class LightingClaimStateRow","persistentSchemaVersion=31","recordsSchemaVersion=30","durableModelCount=5","totalModelCount=109")
 if len(re.findall(r"@Model\s+final\s+class",models))!=5:raise ValueError("C31 persistence must remain exactly five rows")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift","enum PersistentSchemaV31","LightingSystemRow.self","LightingObservationRow.self","LightingIssueRow.self","MeasurementPlanRow.self","LightingClaimStateRow.self")
 _tokens(root,"FieldEvidenceApp/Domain/InspectionKernel/ExactMeasurementSemanticsV1.swift",'unit("[fc_i]", .illuminance, "lx", rational(1_076_391, 100_000), 5)','unit("lx", .illuminance, "lx", rational(1), 5)')
 _tokens(root,"FieldEvidenceApp/Application/Lighting/LightingCoordinatorV1.swift","enum LightingWriteOperationV1","var mutationID: MutationIDV1","func validate() throws","let predecessor = try await query.latest","let receipt = try await authority.commit(operation)")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Lighting/LightingLifecycleAdapterV1.swift","protocol LightingCanonicalWorkspaceWritingV1","private let writer","writer.commitLighting(operation)","try receipt.validate()")
 _tokens(root,"FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift","enum LightingPersistedAdmissionV1","case .appendSystem(let system,_,let admission)","try exact(value,descriptors)","try exact(value,events)","requiredEventIDs.isSubset","case .appendIssue(_,_,let admission): try observation(admission.observation)","case .appendClaim(let value,_,let admission): try claim(admission,value:value)","DerivedFactProvenanceRow","FindingClassificationBindingRow","AuthoritySourceReleaseRow","RequirementBasisBindingRow","ApplicabilityContextSnapshotRow","AssessmentScopeSnapshotRow","AttestationRow")
 backup=_tokens(root,"FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift","func validateC31LightingClosure() throws","recordsSchemaVersion == 30","let decodedLighting = try LightingBackupRecordSetV1.decode(lighting)","C31LightingClaimEvidenceClosureV1.validate","measurementIntegrity: measurementIntegrity","authorityCriterion: authorityCriterion","guard systemByReference.updateValue(value, forKey: reference) == nil","guard observationByReference.updateValue(value, forKey: reference) == nil","guard planByReference.updateValue(value, forKey: reference) == nil","enum C31LightingClaimEvidenceClosureV1","instruments.updateValue(value, forKey: value.referenceID) == nil","captures.updateValue(value, forKey: value.captureID) == nil","authorities.updateValue(value, forKey: value.releaseID) == nil","classifications.updateValue(value, forKey: value.bindingID) == nil","provenances.updateValue(value, forKey: value.provenanceID) == nil")
 if "let systemByReference = Dictionary(uniqueKeysWithValues:" in backup or "let observationByReference = Dictionary(uniqueKeysWithValues:" in backup or "let planByReference = Dictionary(uniqueKeysWithValues:" in backup:raise ValueError("C31 backup semantic-key index can trap on duplicate")
 for path in ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift","FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift","FieldEvidenceApp/Domain/Search/SearchContractsV1.swift","FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift","FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift","FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift"):_tokens(root,path,"C31")
 tests=_tokens(root,"FieldEvidenceAppTests/V9_46LightingPackageTests.swift",*TEST_METHODS,"ExactDecimalV1(mantissa: 1_076_391, scale: 5)","XCTAssertThrowsError","LightingIssueAdmissionClosureV1(observation: foreignObservation)","LightingIssueAdmissionClosureV1(observation: subjectObservation)","LightingIssueAdmissionClosureV1(observation: contentObservation)","calibrationExpiry.addingTimeInterval(1)","wrongProtocol","C31_PHOTO_OR_EXIF_IS_NOT_A_METER","MISSING_C19_CAPTURE","MISMATCHED_C19_PROTOCOL","MISSING_C40_PROVENANCE","MISMATCHED_C40_PROVENANCE","DUPLICATE_SEMANTIC_KEY_ARCHIVE","duplicateSemanticKeyRows","LightingBackupRecordSetV1.decode(duplicateSemanticKeyRows)")
 for token in ("multi","duplicate","certificate","NaN","negative","criterion","jurisdiction","camera","control","safety","traffic","electrical"):
  if token.lower() not in tests.lower():raise ValueError("C31 hostile coverage regressed:"+token)
 corpus=json.loads((root/"FieldEvidenceAppTests/Fixtures/V22/Lighting/V22P03C31LightingPackageCorpusV1.json").read_text(encoding="utf-8"))
 expected_backup_vectors=["MISSING_C19_CAPTURE","MISMATCHED_C19_CAPTURE","MISSING_C19_PROTOCOL","MISMATCHED_C19_PROTOCOL","MISSING_C19_INSTRUMENT","MISMATCHED_C19_INSTRUMENT","MISSING_C19_CALIBRATION","MISMATCHED_C19_CALIBRATION","MISSING_C19_QUALITY","MISMATCHED_C19_QUALITY","MISSING_C40_PROVENANCE","MISMATCHED_C40_PROVENANCE","DUPLICATE_SEMANTIC_KEY_ARCHIVE"]
 if len(corpus.get("hostileCases",[]))!=45 or corpus.get("durableFamilies")!=["LightingSystemV1","LightingObservationV1","LightingIssueV1","MeasurementPlanV1","LightingClaimStateV1"] or corpus.get("backupClosureVectors")!=expected_backup_vectors:raise ValueError("C31 exact 45-case/five-family/archive-closure corpus differs")
def assert_scaffold(root:Path)->None:
 if (len(EXISTING_PATHS),len(NEW_PATHS),len(PATH_FENCE))!=(194,14,208) or len(set(PATH_FENCE))!=208:raise ValueError("C31 fence must be unique 208=194+14")
 if any("s10" in p.lower() or "phase10" in p.lower() for p in PATH_FENCE):raise ValueError("C31 S10 overlap")
 if subprocess.run(["git","-C",str(root),"show","-s","--format=%T",BASE_HEAD],check=True,capture_output=True,text=True).stdout.strip()!=BASE_TREE:raise ValueError("C31 base tree differs")
 for p in EXISTING_PATHS:
  if not _base_exists(root,p):raise ValueError(f"existing absent at base:{p}")
 for p in NEW_PATHS:
  if _base_exists(root,p):raise ValueError(f"new existed at base:{p}")
 if AUTHORIZED_OVERLAP_COUNT!=2537 or UNAUTHORIZED_OVERLAP_COUNT!=0 or any(FLAGS.values()):raise ValueError("C31 authority proof differs")
def authority()->dict[str,Any]:return {"cardID":CARD,"attemptID":1,"registerOrdinal":REGISTER_ORDINAL,"title":TITLE,"appBaseHead":BASE_HEAD,"appBaseTree":BASE_TREE,"coordinationHead":COORDINATION_HEAD,"coordinationTree":COORDINATION_TREE,"coordinationCASSequence":COORDINATION_CAS_SEQUENCE,"hydrationRevision":HYDRATION_REVISION,"prerequisiteDigest":PREREQUISITE_DIGEST,"contextDigest":CONTEXT_DIGEST,"fenceDigest":FENCE_DIGEST,"hydrationTransitionDigest":HYDRATION_TRANSITION_DIGEST,"coordinationLedgerDigest":COORDINATION_LEDGER_DIGEST,"coordinationProjectionDigest":COORDINATION_PROJECTION_DIGEST,"allowedPathCount":208,"existingPathCount":194,"newPathCount":14,"authorizedOverlapCount":2537,"unauthorizedOverlapCount":0,"directPrerequisiteCards":["V23-P03-C28","V23-P03-C30"],"nextCard":"V23-P03-C42","digestPinsPending":PERSISTENCE_PINS_PENDING}
def _sealed(v:dict[str,Any])->dict[str,Any]:return {**v,"artifactDigest":sha256_bytes(pretty(v))}
def schema_document()->dict[str,Any]:return {"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"https://assetrounds.invalid/v23/lighting-package.schema.json","title":"V23 P03 C31 Lighting Package Corpus","type":"object","additionalProperties":False,"properties":{"schema":{"const":"V22P03C31LightingPackageCorpusV1"},"schemaVersion":{"const":1},"cardID":{"const":CARD},"persistentSchemaVersion":{"const":31},"recordsSchemaVersion":{"const":30},"durableFamilies":{"const":PERSISTENCE["persistedFamilies"]},"requiredContractNames":{"const":list(CONTRACT_NAMES)},"statusFlags":{"type":"object","additionalProperties":{"const":False}}},"required":["schema","schemaVersion","cardID","persistentSchemaVersion","recordsSchemaVersion","durableFamilies","requiredContractNames","statusFlags"]}
def contract_document(root:Path)->dict[str,Any]:
 assert_source_regressions(root);semantics={"contractNames":list(CONTRACT_NAMES),"fiveSelectors":list(observed_selectors(root)),"sharedTopologyWithoutClones":True,"claimTierBoundary":True,"photoExifNeverMeasurementOrCompliance":True,"exactFootcandleLuxConversionAndProvenance":True,"criterionIdentityAndInconclusiveBoundary":True,"electricalAndTrafficSafetyStops":True,"singleWriterReceiptLifecycleClosure":True,"archiveWideC19C40ClaimProvenanceJoin":True,"duplicateSemanticKeyArchivesRejectWithoutTrap":True,"hostileMatrixClosure":True}
 return _sealed({"schema":"V23P03C31LightingPackageContractV1","schemaVersion":1,"authority":authority(),"persistence":PERSISTENCE,"requiredSemantics":semantics})
def evidence_document(root:Path)->dict[str,Any]:
 c=contract_document(root);return _sealed({"schema":"V23P03C31LightingPackageEvidenceReceiptV1","schemaVersion":1,"cardID":CARD,"evidenceIDs":[f"{CARD}-{x}" for x in ("G01","A01","H01","I01","R01")],"testSelectors":list(observed_selectors(root)),"requiredSemanticsDigest":sha256_value(c["requiredSemantics"]),"statusFlags":FLAGS})
def brand_document()->dict[str,Any]:return _sealed({"schema":"V23P03C31BrandImpactManifestV1","schemaVersion":1,"cardID":CARD,"uiSurfaceDelta":False,"brandSurfaceDelta":True,"nativeIPadSurface":False,"telemetry":False,"statusFlags":FLAGS})
def _row(root:Path,p:str,r:dict[str,bytes])->dict[str,Any]:
 raw=r[p] if p in r else (root/p).read_bytes();return {"path":p,"sha256":sha256_bytes(raw),"byteCount":len(raw)}
def all_outputs(root:Path)->dict[str,bytes]:
 assert_source_regressions(root);r={SCHEMA_PATH:pretty(schema_document()),CONTRACT_PATH:pretty(contract_document(root)),EVIDENCE_PATH:pretty(evidence_document(root)),BRAND_PATH:pretty(brand_document())};rows=[_row(root,p,r) for p in MANIFEST_INPUT_PATHS];r[MANIFEST_PATH]=pretty(_sealed({"schema":"V23P03C31ToolingManifestV1","schemaVersion":1,"authority":authority(),"pathFence":list(PATH_FENCE),"pathFenceCount":208,"existingPathCount":194,"newPathCount":14,"authorizedOverlapCount":2537,"unauthorizedOverlapCount":0,"artifacts":rows,"artifactSetDigest":sha256_value(rows),"statusFlags":FLAGS}));return r
