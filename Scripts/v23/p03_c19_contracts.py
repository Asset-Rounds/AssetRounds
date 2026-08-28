#!/usr/bin/env python3
"""Deterministic static contract corpus and evidence builders for V23-P03-C19."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

import p03_c18_contracts as c18


CARD = "V23-P03-C19"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 56
TITLE = "InstrumentReferenceV1, calibration-status snapshot, measurement provenance, and deterministic quality review"
BASE_HEAD = "83053def0ab93fd24b1d42fffc21480e5f1c3ba1"
BASE_TREE = "3d785ae416444c9c737f0d0644a40666591b7a39"
COORDINATION_HEAD = "50c56dfb1d7801e2a90be87548c8d9a6ed5378e5"
COORDINATION_TREE = "c7d033931da2ced5dcf3b47eda5558b5cc40a636"
COORDINATION_LEDGER_DIGEST = "5ad7da908a28efe233577243845b00be6f23d08002e040a390dba1c592933250"
COORDINATION_PROJECTION_DIGEST = "a4123fc0bcea3619148cd64a7781fd73a0c4300de56533d30e22846b6fc5ae0c"
COORDINATION_CAS_SEQUENCE = 238
HYDRATION_TRANSITION_SEQUENCE = 238
# The hydration receipt is sealed by the coordination checkpoint and is bound
# here so generated evidence cannot silently drift from the ordered handoff.
HYDRATION_TRANSITION_DIGEST: str | None = "545e0d1232a133276259d9927f35408436f89257d24faa545a91470c8d4c204b"
CONTEXT_DIGEST = "dd92f4d303488dd670da5c48a0753227a7c5a905a7733e40e2928ee139e4108f"
FENCE_DIGEST = "4b39fc01e6f5a3a5c05ff754192369243c5ece0d021421adfc21dd93b0cdc4b1"
PREREQUISITE_DIGEST = "d0a0c4d3cacbdd952fb870420a579dbde68598bf862da8794d6d48302aae004b"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

REGISTER_SECTION_SHA256 = "f8485d18df7f4055bed6d929813694aca368fcb68e54a11cf8b8ba71176402c1"
REGISTER_SECTION_UTF8_LENGTH = 320
REGISTER_ROW_SHA256 = REGISTER_SECTION_SHA256
REGISTER_ROW_UTF8_LENGTH = REGISTER_SECTION_UTF8_LENGTH
DOSSIER_SHA256 = "eec4207cd7a37ef62a7934c6a0f8cbcf0deee593b0a627440282cf15b3e1137c"
DOSSIER_UTF8_LENGTH = 7289
INHERITED_V21_BLOCK_SHA256 = "1c29515e1e98f05eb334dfe9b86b01f4199ab8855fb9e6622ad9beeb3d580490"
INHERITED_V21_BLOCK_UTF8_LENGTH = 11076

SCHEMA_PATH = "Scripts/v23/measurement-integrity.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C19MeasurementIntegrityContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C19MeasurementIntegrityEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C19BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C19-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c19_contracts.py",
    "Scripts/v23/generate_p03_c19_contracts.py",
    "Scripts/v23/verify_p03_c19_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# This ordering is the sealed BootstrapPathFenceV1 order from coordination.
# Keep the authority order intact: generated path-fence digests bind both the
# set and its sequence, so a convenient alphabetical rewrite is not equivalent.
EXISTING_PATHS = (
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ExactMeasurementSemanticsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationEngineV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/AuthorityCriterionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/ObservationAndTimeModelsV1.swift",
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceAppTests/V9_11ObservationTemporalSemanticsTests.swift",
    "FieldEvidenceAppTests/V9_13TypedResponseTests.swift",
    "FieldEvidenceAppTests/V9_25AuthorityCriterionDerivationTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V9_31IntegrationEventProjectionTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/InspectionKernel/MeasurementIntegrityContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/MeasurementIntegrityPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Measurement/MeasurementIntegrityCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Measurement/MeasurementIntegrityLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_33MeasurementIntegrityTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Measurement/V21P03C19MeasurementIntegrityCorpusV1.json",
    *SCRIPT_PATHS,
    SCHEMA_PATH,
    CONTRACT_PATH,
    EVIDENCE_PATH,
    BRAND_PATH,
    MANIFEST_PATH,
)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
FULL_FENCE_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_REFERENCE_PATHS = EXISTING_PATHS
AUTHORITY_REFERENCE_PATHS = (
    "docs/design/v23/EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v23/EXPANSION_V23_FOUNDATION_PLAN.md",
)

_OVERLAP_COUNTS = dict(c18._OVERLAP_COUNTS)
# C18 was the immediately preceding card and is therefore not present in the
# sealed C18 predecessor's historical overlap map.  Its reproof contribution
# is supplied by the C19 hydration authority.
_OVERLAP_COUNTS["V23-P03-C18"] = _OVERLAP_COUNTS.get("V23-P03-C18", 0) + 166
PRIOR_FENCE_OVERLAPS = tuple(
    {"cardID": card, "fenceDigest": "BOUND_TO_C19_PRIOR_FENCE_PROOF", "disposition": "REPROOF_REQUIRED", "overlapCount": count}
    for card, count in _OVERLAP_COUNTS.items()
)
PRIOR_FENCE_PROOF = {
    "fenceCount": len(PRIOR_FENCE_OVERLAPS),
    "priorOwnedPathCount": 1150,
    "overlapCount": 956,
    "authorizedOverlapCount": 956,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "InstrumentReferenceV1",
    "CalibrationStatusSnapshotV1",
    "MeasurementCaptureV1",
    "MeasurementSeriesV1",
    "MeasurementQualityAssessmentV1",
)
INSTRUMENT_TYPES = ("ILLUMINANCE_METER", "MULTIMETER", "THERMOMETER", "OTHER_TYPED_LOCAL_INSTRUMENT")
INSTRUMENT_LIFECYCLE_STATES = ("ACTIVE", "RETIRED", "OUT_OF_SERVICE")
CALIBRATION_STATES = ("NOT_REQUIRED", "CURRENT", "EXPIRED", "UNKNOWN", "OUT_OF_SERVICE")
MEASUREMENT_SOURCE_MODES = ("MANUAL_ENTRY", "LOCAL_OBSERVATION")
MEASUREMENT_UNITS = ("LUX", "FOOT_CANDLE", "CELSIUS", "FAHRENHEIT", "VOLT", "AMPERE", "OHM")
OBSERVATION_BASES = ("DIRECT_OBSERVATION", "RECHECK_OBSERVATION", "COMPARATIVE_OBSERVATION")
AGGREGATION_POLICIES = ("NONE", "MEAN", "MEDIAN", "MINIMUM", "MAXIMUM")
QUALITY_DISPOSITIONS = ("CLEAR", "REVIEW_REQUIRED", "OVERRIDDEN")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C19G01InstrumentCalibrationCaptureAndQualityReviewAreDeterministic",
    "testV23P03C19A01OptionalPlanReferencesRemainIndependentAndTyped",
    "testV23P03C19H01UnknownCalibrationAndInvalidProvenanceFailClosed",
    "testV23P03C19I01InterruptedMeasurementLifecycleRetainsExactSnapshot",
    "testV23P03C19R01RecoveryReplayBackupDeleteAndReportRemainExact",
)
SOURCE_CONTRACT_TOKENS = (
    CARD,
    "V21-P03-C19",
    *CONTRACT_NAMES,
    "fixed-point value",
    "deterministic quality review",
)
REQUIRED_BEHAVIORS = (
    {"id": "INSTRUMENT_REFERENCE", "contract": "InstrumentReferenceV1", "requirement": "Stable local instrument identity, type, label, owner-permitted opaque serial, manufacturer, model, unit capabilities, and lifecycle state are typed without external keys, providers, or accounts.", "evidence": "C19-S01"},
    {"id": "CALIBRATION_SNAPSHOT", "contract": "CalibrationStatusSnapshotV1", "requirement": "Capture-time calibration status freezes NOT_REQUIRED, CURRENT, EXPIRED, UNKNOWN, or OUT_OF_SERVICE with basis, effective/expiry, source, capturedAt, and revision.", "evidence": "C19-S02"},
    {"id": "MEASUREMENT_PROVENANCE", "contract": "MeasurementCaptureV1", "requirement": "Fixed-point value and typed unit bind source mode, instrument and calibration snapshots, observation basis, uncertainty, operator provenance, mutation/revision IDs, and the exact response.", "evidence": "C19-S03"},
    {"id": "MEASUREMENT_SERIES", "contract": "MeasurementSeriesV1", "requirement": "Repeatable series and sample identity, ordering, expected/observed count, aggregation policy, and immutable finalized snapshot are deterministic.", "evidence": "C19-S04"},
    {"id": "QUALITY_REVIEW", "contract": "MeasurementQualityAssessmentV1", "requirement": "Quality review returns CLEAR, REVIEW_REQUIRED, or OVERRIDDEN with closed reasons, evidence, policy version, reviewer, and rationale; it never diagnoses or auto-passes compliance.", "evidence": "C19-S05"},
    {"id": "V18_LIFECYCLE", "contract": "PERSISTENT_SCHEMA_V18", "requirement": "Schema V18 and records 17 migration, backup/restore, import/export, report, search/rebuild, replay, delete/Erase, compatibility, interruption, and forward-fix mappings are explicit.", "evidence": "C19-S06"},
    {"id": "OPTIONAL_PLAN_REFERENCES", "contract": "InstallationPlanReferenceV1+PunchPlanReferenceV1", "requirement": "Optional plan references are emitted only for compatible plans and never create a dependency between installation and punch workflows.", "evidence": "C19-S07"},
    {"id": "STATIC_BOUNDARY", "contract": CARD, "requirement": "This lane is PASS_STATIC_PROVISIONAL and native, hosted, adoption, acceptance, and release flags remain false.", "evidence": "C19-B01"},
)
EVIDENCE_CASES = (
    {"id": "C19-S01", "kind": "INSTRUMENT_REFERENCE", "assertion": "Golden local instrument references retain stable identity and typed capabilities without hardware or provider state."},
    {"id": "C19-S02", "kind": "CALIBRATION", "assertion": "Calibration status is an immutable capture-time snapshot and later instrument edits do not rewrite history."},
    {"id": "C19-S03", "kind": "PROVENANCE", "assertion": "Measurement captures preserve fixed-point values, typed units, source, uncertainty, operator, basis, mutation, revision, and instrument snapshots."},
    {"id": "C19-S04", "kind": "SERIES", "assertion": "Alternate repeated samples aggregate deterministically and finalized series snapshots remain immutable."},
    {"id": "C19-S05", "kind": "QUALITY_REVIEW", "assertion": "Quality review is explainable, policy-versioned, and human-reviewed without diagnosis, compliance judgment, or automatic pass."},
    {"id": "C19-S06", "kind": "V18_LIFECYCLE", "assertion": "Migration, backup, restore, export, report, search, replay, delete, Erase, interruption, and recovery preserve exact history and identity."},
    {"id": "C19-S07", "kind": "OPTIONAL_PLAN_REFERENCES", "assertion": "Installation and punch plan references are independently optional and typed when compatible plans exist."},
    {"id": "C19-H01", "kind": "HOSTILE", "assertion": "Unknown calibration, expired or out-of-service instruments, invalid units, duplicate series samples, stale revisions, forged provenance, and external-provider requests fail closed."},
    {"id": "C19-I01", "kind": "INTERRUPTION", "assertion": "Interruption before and after capture, series finalization, review, migration, backup, restore, delete, Erase, and replay never yields partial canonical success."},
    {"id": "C19-R01", "kind": "RECOVERY", "assertion": "Recovery and replay reproduce exact old-or-new snapshots and never rewrite immutable measurement history."},
    {"id": "C19-F01", "kind": "PATH_FENCE", "assertion": "The hydrated fence is exactly 112 paths: 98 existing and 14 new, with zero overlap against the frozen S10 reservation."},
    {"id": "C19-B01", "kind": "STATIC_BOUNDARY", "assertion": "Activation, native, hosted, adoption, acceptance, and release claims remain false pending later evidence and reconciliation."},
)
SOURCE_PROJECTION = {
    "registerRows": ['| 56 | <a id="v23-p03-c19-register"></a>[`V23-P03-C19`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c19) | InstrumentReferenceV1, calibration-status snapshot, measurement provenance, and deterministic quality review | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C10`, `V23-P03-C17` | `EXACT_WITH_GENERATION_REBIND` |'],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 1,
    "canonicalRecordWriterOwnershipRowCount": 4,
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C19).CONTRACTS", "InstallationPlanReferenceV1", "PunchPlanReferenceV1", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C21", "V23-P03-C53", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
}
DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 2,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [
        {"cardID": "V23-P03-C10", "attemptID": 1, "candidateHead": "3777bfc1b7800f808871337ddec533f171a6dc39", "candidateTree": "d3b22a2116f16c693c57d590ed9361dc93fe5e78", "checkpointDigest": "bc90541801925613b7ce7442169933c09aabb9308a3308396808f83e6be349d1", "verificationReceiptDigest": "861e16483da58262c6cf451cbe1f3ad9520af42c5128e281dc4fca54127d0762", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C10_HEAD"},
        {"cardID": "V23-P03-C17", "attemptID": 1, "candidateHead": "38b5bd807bb7e1096e015077f72a9e25b8b06b6a", "candidateTree": "8d36b480b0103993ad0c5dab6df055bf63b2da8d", "checkpointDigest": "3511f3a7fad741bf639dbfae0a22e0cddc1e8a0185ddfb8b4360262306d43b7f", "verificationReceiptDigest": "1ddff8c2eee58e3b7984bb8986356015fc84886135fe6dcc7a72b857cc32072a", "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C17_HEAD"},
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}
SEMANTIC_SCOPE = {
    "durableOwner": list(CONTRACT_NAMES),
    "atomicAuthorityPolicy": "FIXED_POINT_CAPTURE_CALIBRATION_SNAPSHOT_SERIES_FINALIZATION_AND_QUALITY_REVIEW_USE_THE_SOLE_CANONICAL_WRITER_WITH_EXPECTED_REVISION_MUTATION_ID_AND_DURABLE_RECEIPT",
    "instrumentPolicy": "LOCAL_TYPED_INSTRUMENT_REFERENCE_WITH_NO_EXTERNAL_KEY_PROVIDER_ACCOUNT_HARDWARE_OR_IMPORT_SOURCE",
    "calibrationPolicy": "CAPTURE_TIME_IMMUTABLE_STATUS_BASIS_EFFECTIVE_EXPIRY_SOURCE_CAPTURED_AT_AND_REVISION_WITH_UNKNOWN_EXPIRED_AND_OUT_OF_SERVICE_VISIBLE",
    "provenancePolicy": "FIXED_POINT_VALUE_TYPED_UNIT_SOURCE_MODE_INSTRUMENT_CALIBRATION_OBSERVATION_BASIS_UNCERTAINTY_OPERATOR_MUTATION_REVISION_AND_RESPONSE",
    "seriesPolicy": "REPEATABLE_SERIES_SAMPLE_ID_ORDER_EXPECTED_OBSERVED_COUNT_AGGREGATION_AND_IMMUTABLE_FINALIZED_SNAPSHOT",
    "qualityPolicy": "CLEAR_REVIEW_REQUIRED_OR_OVERRIDDEN_WITH_CLOSED_REASONS_EVIDENCE_POLICY_VERSION_REVIEWER_AND_RATIONALE_NEVER_DIAGNOSIS_OR_AUTO_COMPLIANCE",
    "lifecyclePolicy": "V18_RECORDS17_MIGRATION_BACKUP_RESTORE_EXPORT_REPORT_SEARCH_REBUILD_REPLAY_DELETE_ERASE_INTERRUPTION_RECOVERY_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "optionalPlanPolicy": "INSTALLATION_AND_PUNCH_PLAN_REFERENCES_ARE_OPTIONAL_COMPATIBILITY_BOUND_AND_INDEPENDENT",
    "forbiddenPolicy": "NO_BLUETOOTH_IOT_VENDOR_SDK_REMOTE_CALIBRATION_PROVIDER_ENDPOINT_CREDENTIAL_DEVICE_CONTROL_IMPORT_AUTOMATIC_COMPLIANCE_PREDICTIVE_MAINTENANCE_AI_DIAGNOSIS_FLOAT_CANONICAL_VALUE_LOCALIZED_UNIT_IDENTITY_MUTABLE_FINAL_MEASUREMENT_ACCOUNT_CLOUD_TELEMETRY_OR_LEGAL_CLAIM",
    "s10Policy": "EXACT_FROZEN_S10_RESERVATION_WITH_ZERO_OVERLAP_AND_NO_NEW_UI",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

REQUIRED_BEHAVIORS = tuple(REQUIRED_BEHAVIORS)
CORPUS: dict[str, Any] = {
    "schema": "V21P03C19MeasurementIntegrityCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": 18,
    "recordsSchemaVersion": 17,
    "persistentMeasurementIntegrityKindCount": 5,
    "migrationInventedMeasurementIntegrityCount": 0,
    "requiredContractNames": list(CONTRACT_NAMES),
    "instrumentTypes": list(INSTRUMENT_TYPES),
    "instrumentLifecycleStates": list(INSTRUMENT_LIFECYCLE_STATES),
    "calibrationStates": list(CALIBRATION_STATES),
    "measurementSourceModes": list(MEASUREMENT_SOURCE_MODES),
    "measurementUnits": list(MEASUREMENT_UNITS),
    "observationBases": list(OBSERVATION_BASES),
    "aggregationPolicies": list(AGGREGATION_POLICIES),
    "qualityDispositions": list(QUALITY_DISPOSITIONS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
    "forbiddenClaims": ["HARDWARE_INTEGRATION", "REMOTE_CALIBRATION", "AUTOMATIC_COMPLIANCE", "PREDICTIVE_MAINTENANCE", "AI_DIAGNOSIS", "FLOATING_POINT_CANONICAL_VALUE", "MUTABLE_FINAL_MEASUREMENT", "CLOUD_OR_ACCOUNT_STATE", "NATIVE_IPAD_SURFACE", "SIGNING_TESTFLIGHT_APP_STORE_OR_DEPLOYMENT"],
    "persistence": {
        "schemaRelease": "MEASUREMENT_INTEGRITY_V1",
        "schemaVersion": 18,
        "recordsSchemaVersion": 17,
        "mode": "NEW_SCHEMA_VERSION",
        "migrationRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportReportRequired": True,
        "searchRebuildRequired": True,
        "replayRequired": True,
        "canonicalWriter": "V23-P02-C01",
        "canonicalSourceOfTruth": list(CONTRACT_NAMES),
        "persistedFamilies": list(CONTRACT_NAMES),
        "nonPersistentFamilies": [],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
        "forwardFix": "IMMUTABLE_CAPTURE_AND_REVIEW_HISTORY_WITH_OLD_OR_NEW_REPLAY_NEVER_HYBRID",
    },
    "measurementCases": [
        {"id": "golden-single-capture", "calibration": "CURRENT", "quality": "CLEAR", "finalized": True},
        {"id": "alternate-repeat-series", "calibration": "CURRENT", "quality": "REVIEW_REQUIRED", "finalized": True},
        {"id": "unknown-calibration", "calibration": "UNKNOWN", "quality": "REVIEW_REQUIRED", "finalized": False},
        {"id": "expired-calibration", "calibration": "EXPIRED", "quality": "REVIEW_REQUIRED", "finalized": False},
        {"id": "out-of-service-instrument", "calibration": "OUT_OF_SERVICE", "quality": "REVIEW_REQUIRED", "finalized": False},
    ],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED_NO_PARTIAL_CANONICAL_SUCCESS"} for case_id in ("unknown-instrument", "duplicate-instrument-identity", "invalid-unit", "localized-unit-identity", "floating-point-value", "stale-revision", "duplicate-sample-order", "changed-calibration-after-capture", "forged-provenance", "auto-compliance-request", "hardware-provider-request", "remote-calibration-request", "cross-workspace-reference", "partial-series-finalization")],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_MEASUREMENT"} for case_id in ("capture-before-receipt", "capture-after-receipt", "series-finalization", "quality-review", "migration", "backup", "restore", "delete-erase", "replay")],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "EXACT_OLD_OR_NEW_SNAPSHOT_REPLAY_NO_REWRITE"} for case_id in ("restore-calibration-snapshot", "rebuild-series", "replay-capture", "replay-quality-review", "clone-fork", "import-export", "search-rebuild", "erase-recovery")],
    "claims": {claim: False for claim in ("native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit", "hardwareIntegration", "automaticCompliance", "predictiveMaintenance", "aiDiagnosis", "remoteCalibration", "cloudState")},
}


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _git_blob(root: Path, relative: str) -> bytes:
    return subprocess.run(["git", "-C", str(root), "show", f"{BASE_HEAD}:{relative}"], check=True, capture_output=True).stdout


def source_artifacts(root: Path) -> list[dict[str, Any]]:
    return [{"path": path, "source": "BASE_HEAD_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)} for path in SOURCE_REFERENCE_PATHS]


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    return [{"path": path, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)} for path in AUTHORITY_REFERENCE_PATHS]


def _schema_for_value(value: Any) -> dict[str, Any]:
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer"}
    if isinstance(value, float):
        return {"type": "number"}
    if isinstance(value, str):
        return {"type": "string"}
    if isinstance(value, list):
        result: dict[str, Any] = {"type": "array", "minItems": len(value), "maxItems": len(value)}
        if value:
            shapes = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
            result["items"] = next(iter(shapes.values())) if len(shapes) == 1 else {"anyOf": [shapes[key] for key in sorted(shapes)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/measurement-integrity.schema.json", "title": "V23 P03 C19 Measurement Integrity Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION", "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST, "fullFencePaths": list(PATH_FENCE),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST, "directPrerequisiteCards": ["V23-P03-C10", "V23-P03-C17"], "nextCard": "V23-P03-C20",
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "MEASUREMENT_INTEGRITY_V1", "recordSchemaVersion": 17,
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True,
        "deleteBehaviorDelta": True, "exportBehaviorDelta": True, "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True,
        "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True, "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
        "uiSurfaceDelta": False, "brandSurfaceDelta": False, "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True, "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": []}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "EXACT_WITH_GENERATION_REBIND", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def _required_semantics() -> dict[str, Any]:
    return {"contractNames": list(CONTRACT_NAMES), "instrumentTypes": list(INSTRUMENT_TYPES), "instrumentLifecycleStates": list(INSTRUMENT_LIFECYCLE_STATES), "calibrationStates": list(CALIBRATION_STATES), "measurementSourceModes": list(MEASUREMENT_SOURCE_MODES), "measurementUnits": list(MEASUREMENT_UNITS), "observationBases": list(OBSERVATION_BASES), "aggregationPolicies": list(AGGREGATION_POLICIES), "qualityDispositions": list(QUALITY_DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": CORPUS["forbiddenClaims"]}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({"schema": "V23P03C19MeasurementIntegrityContractV1", "artifact": "V23P03C19MeasurementIntegrityContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows), "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": _required_semantics(), "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(CONTRACT_NAMES), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "successor": {"cardID": "V23-P03-C20", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = _required_semantics()
    return _sealed({"schema": "V23P03C19MeasurementIntegrityEvidenceReceiptV1", "artifact": "V23P03C19MeasurementIntegrityEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows), "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics), "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C19BrandImpactManifestV1", "artifact": "V23P03C19BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "NO_NEW_UI_BRAND_SURFACE_MEASUREMENT_FOUNDATION_ONLY", "affectedSurfacePaths": [], "semanticStates": ["CURRENT", "EXPIRED", "UNKNOWN", "OUT_OF_SERVICE", "CLEAR", "REVIEW_REQUIRED", "OVERRIDDEN"], "contractArtifact": contract_row, "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    if relative in rendered:
        raw = rendered[relative]
        return {"path": relative, "state": "GENERATED", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    path = root / relative
    if path.is_file():
        raw = path.read_bytes()
        return {"path": relative, "state": "WORKTREE", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if relative in EXISTING_PATHS:
        raw = _git_blob(root, relative)
        return {"path": relative, "state": "BASE_HEAD", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    return {"path": relative, "state": "MISSING_NEW_PATH", "bytes": 0, "sha256": sha256_bytes(b"")}


def all_outputs(root: Path) -> dict[str, bytes]:
    if len(EXISTING_PATHS) != 98 or len(NEW_PATHS) != 14 or len(PATH_FENCE) != 112:
        raise ValueError("C19 path fence constants differ")
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = json.loads(contract_raw.decode("utf-8"))
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    brand_raw = pretty(brand_document(contract_row))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C19ToolingManifestV1", "artifact": "V23P03C19ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows, "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered
