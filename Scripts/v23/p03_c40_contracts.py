"""Deterministic static corpus and evidence builders for V23-P03-C40.

Card 48 owns the portable authority-source, applicability, criterion, severity,
measurement, and derivation contract lane.  The module deliberately emits
static provisional evidence only: it never evaluates customer data, fetches a
source, executes a package script, or claims native, hosted, adoption,
acceptance, or release evidence.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C40"
SCHEMA_VERSION = 1
BASE_HEAD = "f34461d0d1da63a4d923a8983ce193124668088b"
BASE_TREE = "5fc7cc703e1e7ab8b58342b5cd105fc76335540f"
CONTEXT_DIGEST = "fafbec0ccdb5cd65f331caca8fa74373104f31f38b1be9abd97345410bd82c9e"
FENCE_DIGEST = "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397"
PREREQUISITE_DIGEST = "9060cc74a70134676a8b7dfd39e062256807756486c10636ffb1edd244d5f5bb"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "50ba1905d45cb8269ef0696352e51f1bcf6b375b"
COORDINATION_TREE = "f8f5a220e7ebf7664c6193806696c6112d3eef26"
COORDINATION_LEDGER_DIGEST = "a5a8f10341a9785836313f59a5b000772696469e46a67a3031f4e4d0b2ee1e26"
COORDINATION_CAS_SEQUENCE = 204
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "4850fabd9be952d41a0087deb6f0d497f866d0ea08ac4bd92075e6d454e1c86b"
DOSSIER_SHA256 = "b0d32c5a01af5027ffdc49f33683d98c149131ddba61dbbbb5b5a2c8f5a08c2a"
DOSSIER_UTF8_LENGTH = 7170
INHERITED_V21_BLOCK_SHA256 = "9215b3fbe9f1eb380a89b6d96d81a5a7932bb33bcb303157247a40f99ecbdf25"
INHERITED_V21_BLOCK_UTF8_LENGTH = 7424

SCHEMA_PATH = "Scripts/v23/authority-criterion.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C40AuthorityCriterionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C40AuthorityCriterionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C40BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C40-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/AuthorityCriterion/V21P03C40AuthorityCriterionCorpusV1.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c40_contracts.py",
    "Scripts/v23/generate_p03_c40_contracts.py",
    "Scripts/v23/verify_p03_c40_contracts.py",
)
GENERATED_PATHS = (FIXTURE_PATH, SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)

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
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/ExactMeasurementSemanticsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/FindingContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/RequirementEvaluationEngineV1.swift",
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift",
    "FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift",
    "FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift",
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
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/InspectionKernel/AuthorityCriterionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AuthorityCriterionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Authority/AuthorityCriterionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Authority/AuthorityCriterionLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_25AuthorityCriterionDerivationTests.swift",
    "FieldEvidenceAppUITests/V23_P03_C40AuthorityCriterionUITests.swift",
    FIXTURE_PATH,
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

# The bootstrap fence records 382 authorized edges over the prior 48 fences.
# This compact projection preserves every prior fence identity and count while
# keeping path ownership itself exclusively bound to the immutable fence hash.
PRIOR_FENCE_OVERLAPS = (
    {"cardID": "V23-P01-C01", "fenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", "disposition": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C02", "fenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", "disposition": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P01-C03", "fenceDigest": "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", "disposition": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P01-C04", "fenceDigest": "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", "disposition": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P01-C05", "fenceDigest": "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", "disposition": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED", "overlapCount": 10},
    {"cardID": "V23-P01-C06", "fenceDigest": "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", "disposition": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 17},
    {"cardID": "V23-P01-C07", "fenceDigest": "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", "disposition": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P02-C01", "fenceDigest": "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", "disposition": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P02-C02", "fenceDigest": "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", "disposition": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED", "overlapCount": 25},
    {"cardID": "V23-P02-C03", "fenceDigest": "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", "disposition": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED", "overlapCount": 17},
    {"cardID": "V23-P02-C04", "fenceDigest": "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", "disposition": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P02-C05", "fenceDigest": "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", "disposition": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 7},
    {"cardID": "V23-P02-C06", "fenceDigest": "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", "disposition": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P02-C07", "fenceDigest": "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", "disposition": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED", "overlapCount": 25},
    {"cardID": "V23-P02-C08", "fenceDigest": "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", "disposition": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P02-C09", "fenceDigest": "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", "disposition": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C01", "fenceDigest": "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3", "disposition": "PACKAGE_REGISTRY_AND_CAPABILITY_REPROOF_REQUIRED", "overlapCount": 3},
    {"cardID": "V23-P03-C02", "fenceDigest": "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba", "disposition": "PACKAGE_RELEASE_BINDING_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C03", "fenceDigest": "8e424c0e0718d8df4127a2034744f1a347f14c3aed23f684cc0c0c4f6b525bf6", "disposition": "EXACT_MEASUREMENT_UNIT_AND_ROUNDING_OWNER_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P03-C04", "fenceDigest": "cafb01052cd0eb74fb7a90f0815439d3e3b29811c3a8b920fbae4d948d5c166c", "disposition": "FINDING_SEVERITY_AND_OPERATIONAL_DISPOSITION_BOUNDARY_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P03-C05", "fenceDigest": "f6ef2e304901fc4ccc103c5c210eee65b26faefb6b96a2cd8ae3a171debab614", "disposition": "CONTENT_REFERENCE_AND_LOCATOR_OWNER_REPROOF_REQUIRED", "overlapCount": 2},
    {"cardID": "V23-P03-C06", "fenceDigest": "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", "disposition": "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C08", "fenceDigest": "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", "disposition": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED", "overlapCount": 8},
    {"cardID": "V23-P03-C09", "fenceDigest": "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", "disposition": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 36},
    {"cardID": "V23-P03-C10", "fenceDigest": "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", "disposition": "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED", "overlapCount": 1},
    {"cardID": "V23-P03-C11", "fenceDigest": "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", "disposition": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED", "overlapCount": 5},
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 31},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 36},
    {"cardID": "V23-P03-C38", "fenceDigest": "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", "disposition": "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED", "overlapCount": 49},
    {"cardID": "V23-P03-C39", "fenceDigest": "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", "disposition": "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED", "overlapCount": 52},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 48,
    "priorOwnedPathCount": 806,
    "overlapCount": 382,
    "authorizedOverlapCount": 382,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "AuthoritySourceReleaseV1",
    "LicenseStorageDispositionV1",
    "RequirementBasisBindingV1",
    "ApplicabilityContextSnapshotV1",
    "ApplicabilityDispositionV1",
    "AssessmentScopeSnapshotV1",
    "SeverityScaleReleaseV1",
    "FindingClassificationBindingV1",
    "MeasurementProtocolReleaseV1",
    "DerivedFactEvaluatorDescriptorV1",
    "DerivedFactProvenanceV1",
)
SOURCE_TYPES = ("GUIDANCE", "VOLUNTARY_STANDARD", "ADOPTED_RULE", "MANUFACTURER_INSTRUCTION", "CONTRACT_OR_INSURER", "OWNER_POLICY")
LICENSE_STORAGE_DISPOSITIONS = ("METADATA_ONLY", "LAWFUL_C23_REFERENCE", "RIGHTS_UNRESOLVED")
APPLICABILITY_DISPOSITIONS = ("APPLICABLE", "NOT_APPLICABLE_WITH_REASON", "UNKNOWN", "CONFLICT_REVIEW_REQUIRED", "UNSUPPORTED")
CRITERION_RESULTS = ("MEETS_SCREENING_CRITERION", "DOES_NOT_MEET", "INCONCLUSIVE", "NOT_EVALUATED")
SEVERITY_SCALE_STATES = ("RELEASED", "RETIRED")
MEASUREMENT_DISPOSITIONS = ("VALID", "MISSING", "OUTLIER", "DUPLICATE", "UNCERTAINTY_INVALID", "INSUFFICIENT_SAMPLES", "DIMENSION_MISMATCH")
DERIVATION_DISPOSITIONS = ("DERIVED", "INCONCLUSIVE", "NOT_EVALUATED", "INVALID_INPUT")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V11_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY",
    "MIGRATION_AND_RECOVERY",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "PRIVACY_PROGRESSIVE_DISCLOSURE",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
)
FORBIDDEN_CLAIMS = (
    "LEGAL_RESEARCH_ENGINE",
    "GPS_DERIVED_JURISDICTION",
    "AUTOMATIC_LEGAL_PRECEDENCE_OR_AHJ_SELECTION",
    "AUTOMATIC_COMPLIANCE_OR_SAFETY_SCORE",
    "LICENSED_SOURCE_TEXT",
    "WEB_UPDATED_STANDARDS",
    "USER_AUTHORED_EVALUATOR_OR_SCRIPT",
    "FULL_UCUM_OR_SECOND_UNIT_SYSTEM",
    "SECOND_REFERENCE_STORE",
    "PACKAGE_SPECIFIC_TABLE_OR_WRITER",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV9_AuthorityCriterionG01SourceApplicabilityCriterionAndSeverityMatrix",
    "testV9_AuthorityCriterionA01MeasurementUnitsAndDeterministicDerivation",
    "testV9_AuthorityCriterionH01RightsJurisdictionEvaluatorAndClaimBoundariesFailClosed",
    "testV9_AuthorityCriterionI01InterruptedAdmissionBindingDerivationAndReplayRecover",
    "testV9_AuthorityCriterionR01BackupRestoreSearchReportImportAndErasePinHistory",
)
SOURCE_CONTRACT_TOKENS = (CARD, *CONTRACT_NAMES, "PersistentSchemaReleaseRegistryV1")

SEMANTIC_SCOPE = {
    "durableOwner": ["AuthoritySourceReleaseV1", "RequirementBasisBindingV1", "ApplicabilityContextSnapshotV1", "AssessmentScopeSnapshotV1", "SeverityScaleReleaseV1", "FindingClassificationBindingV1", "MeasurementProtocolReleaseV1", "DerivedFactEvaluatorDescriptorV1", "DerivedFactProvenanceV1", "PersistentSchemaV11"],
    "sourcePolicy": "IMMUTABLE_AUTHORITY_SOURCE_RELEASES_STORE_METADATA_LOCATORS_RIGHTS_DISPOSITION_AND_LAWFUL_C23_REFERENCES_ONLY_NEVER_LICENSED_BYTES_OR_COPIED_SOURCE_TEXT",
    "applicabilityPolicy": "PERSON_SELECTED_CONTEXT_BINDS_EXACT_SITE_ACTIVITY_C39_SUBJECT_PACKAGE_C38_ACTOR_QUALIFICATION_EFFECTIVE_DATE_BASIS_AND_SOURCE_RELEASES_WITH_APPLICABLE_NOT_APPLICABLE_WITH_REASON_UNKNOWN_CONFLICT_REVIEW_REQUIRED_OR_UNSUPPORTED",
    "jurisdictionPolicy": "NO_GPS_DERIVED_JURISDICTION_LEGAL_PRECEDENCE_NEWEST_OR_STRICTEST_SOURCE_SELECTION_OR_AUTOMATIC_ADOPTION_INFERENCE",
    "criterionPolicy": "SCREENING_RESULTS_ARE_ONLY_MEETS_SCREENING_CRITERION_DOES_NOT_MEET_INCONCLUSIVE_OR_NOT_EVALUATED_AND_REPORTS_SAY_ASSESSED_AGAINST_WITHOUT_SAFE_COMPLIANT_CERTIFIED_LEGAL_AHJ_OR_PROFESSIONAL_CLAIMS",
    "severityPolicy": "SEVERITY_LEVEL_IDS_ARE_MEANINGFUL_ONLY_INSIDE_ONE_IMMUTABLE_SCALE_RELEASE_AND_CROSS_SCALE_ORDER_REQUIRES_AN_EXACT_MAPPING_RELEASE_NEVER_NUMERIC_ORDER_ALONE",
    "measurementPolicy": "PROTOCOL_RELEASES_FREEZE_NORMATIVE_UNIT_SAMPLING_MISSING_OUTLIER_DUPLICATE_UNCERTAINTY_AND_ROUNDING_POLICY_AND_CONSUME_C03_EXACT_UNIT_DIMENSION_CONVERSION_AUTHORITY",
    "derivationPolicy": "APP_BUNDLED_PURE_VERSION_AND_DIGEST_BOUND_EVALUATORS_PRESERVE_RAW_INPUTS_CONVERSION_ROUNDING_RESULT_UNCERTAINTY_DISPOSITION_AND_PREDECESSOR_AND_FAIL_CLOSED_ON_ZERO_DIVISION_OVERFLOW_DIMENSION_DUPLICATES_INSUFFICIENT_SAMPLES_OR_UNKNOWN_RELEASE",
    "packagePolicy": "PACKAGES_REFERENCE_DECLARED_PROTOCOLS_AND_EVALUATORS_BUT NEVER_SUPPLY_EXECUTABLE_FORMULAS_SCRIPTS_OR_FLOATING_POINT_CANONICAL_THRESHOLDS",
    "migrationPolicy": "V10_TO_V11_COPY_ON_WRITE_PRESERVES_ALL_RELEASED_VALUES_AND_CREATES_ZERO_AUTHORITY_APPLICABILITY_SEVERITY_PROTOCOL_EVALUATOR_OR_DERIVED_FACT_ROWS",
    "writerPolicy": "P02_C01_SOLE_WORKSPACE_WRITER_COMMITS_EXPECTED_REVISION_MUTATION_ID_ATOMIC_POST_IMAGE_DURABLE_RECEIPT_JOURNAL_AND_EFFECT_BEFORE_RECEIPT_RECOVERY",
    "fullLifecyclePolicy": "SCHEMA_MIGRATION_COMPATIBILITY_BACKUP_RESTORE_CLONE_FORK_ARCHIVE_OPEN_JSON_SEARCH_REBUILD_JOURNAL_REPLAY_CHECKPOINT_REPORT_DELETE_ERASE_PRIVACY_INTERRUPTION_AND_DOWNGRADE_ENROLL_ALL_NINE_PERSISTENT_FAMILIES_BEFORE_FIRST_WRITE",
    "historyPolicy": "ACCEPTED_SOURCE_PROTOCOL_EVALUATOR_SCALE_BINDING_CONTEXT_SCOPE_CLASSIFICATION_AND_DERIVATION_HISTORY_IS_APPEND_ONLY_SUPERSEDED_NEVER_EDITED_AND_COMPLETED_WORK_REMAINS_PINNED",
    "forbiddenPolicy": "NO_LEGAL_RESEARCH_ENGINE_JURISDICTION_OR_AHJ_AUTO_SELECTION_COMPLIANCE_OR_SAFETY_SCORE_LICENSED_TEXT_WEB_UPDATES_USER_SCRIPTS_FULL_UCUM_SECOND_REFERENCE_STORE_UNIT_SYSTEM_WRITER_RENDERER_OR_PACKAGE_SPECIFIC_TABLE",
    "localizationAccessibilityPolicy": "UNKNOWN_CONFLICT_INCONCLUSIVE_UNSUPPORTED_AND_NOT_EVALUATED_USE_TYPED_EN_ONLY_KEYS_TEXT_ICON_ACTIONABLE_NEXT_STEP_DYNAMIC_TYPE_VOICEOVER_RTL_AND_NONCOLOR_SEMANTICS",
    "privacyPolicy": "CUSTOMER_SAFE_SEARCH_REPORT_AND_OPEN_JSON_EXCLUDE_LICENSED_TEXT_RAW_SAMPLES_PRIVATE_LOCATORS_QUALIFICATION_DETAIL_AND_ANY_UNSUPPORTED_CLAIM",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_IS_FROZEN_AND_CARD_PATH_FENCE_HAS_ZERO_S10_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_NONRESERVED_SCHEMA_CONTRACT_LIFECYCLE_FIXTURE_AND_TEST_IMPLEMENTATION_ONLY_NATIVE_HOSTED_RESERVED_UI_ACCEPTANCE_RELEASE_AND_PHASE10_POLLING_DEFERRED_PENDING_ACCEPTED_S10_6_RECONCILIATION",
}

REQUIRED_BEHAVIORS = (
    {"id": "SOURCE_RELEASES", "contract": "AuthoritySourceReleaseV1", "requirement": "Immutable authority releases store issuer, designation, edition, dates, locator, digest when available, source type, and rights disposition without licensed bytes or copied source text.", "evidence": "C40-S01"},
    {"id": "SOURCE_RIGHTS", "contract": "LicenseStorageDispositionV1", "requirement": "Metadata-only and lawful C23 reference modes are explicit; unresolved rights fail closed and never activate a source.", "evidence": "C40-S02"},
    {"id": "APPLICABILITY_CONTEXT", "contract": "ApplicabilityContextSnapshotV1", "requirement": "Person-selected Site, activity, C39 subject, package, C38 actor and qualification, effective date, basis, and source releases remain frozen in an append-only snapshot.", "evidence": "C40-S03"},
    {"id": "APPLICABILITY_DISPOSITION", "contract": "ApplicabilityDispositionV1", "requirement": "Applicable, not-applicable-with-reason, unknown, conflict-review-required, and unsupported are closed outcomes; GPS and newest/strictest inference are forbidden.", "evidence": "C40-S04"},
    {"id": "ASSESSMENT_SCOPE", "contract": "AssessmentScopeSnapshotV1", "requirement": "Assessment scope binds the exact frozen subject, activity, package, source, actor, qualification, and effective-date basis used by a criterion result.", "evidence": "C40-S05"},
    {"id": "SEVERITY_AND_CRITERION", "contract": "SeverityScaleReleaseV1", "requirement": "Immutable scale releases own meaningful level IDs and exact cross-scale mappings; criterion results remain screening-only and use assessed-against language.", "evidence": "C40-S06"},
    {"id": "MEASUREMENT_PROTOCOL", "contract": "MeasurementProtocolReleaseV1", "requirement": "Protocol releases freeze normative units, sampling, missing/outlier/duplicate/uncertainty/rounding behavior and consume C03 conversion authority.", "evidence": "C40-S07"},
    {"id": "PURE_DERIVATION", "contract": "DerivedFactEvaluatorDescriptorV1", "requirement": "App-bundled pure digest-bound evaluators preserve raw inputs, conversion, rounding, result, uncertainty, disposition, and predecessor and fail closed on invalid inputs.", "evidence": "C40-S08"},
    {"id": "SCHEMA_V11_PERSISTENCE", "contract": "PersistentSchemaV11", "requirement": "Schema-v11 migration, writer, backup/restore, clone/fork, import preview, journal/replay, search, report/open JSON, delete/Erase, privacy, interruption, and forward-fix behavior enroll every C40 family before first write.", "evidence": "C40-L01"},
    {"id": "STATIC_BOUNDARY", "contract": CARD, "requirement": "This lane is PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, acceptance credit, and release credit remain false.", "evidence": "C40-B01"},
)
EVIDENCE_CASES = (
    {"id": "C40-S01", "kind": "SOURCE_PROJECTION", "assertion": "Register, dossier, inherited V21 boundary, policy, contract, aggregate, and invalidation source projection values are pinned to their exact recorded hashes and lengths."},
    {"id": "C40-S02", "kind": "RIGHTS_SAFE_SOURCE", "assertion": "Synthetic source records contain metadata and locators only; licensed bytes and copied source text are absent and unresolved rights remain non-admissible."},
    {"id": "C40-S03", "kind": "APPLICABILITY_MATRIX", "assertion": "The fixture covers person-selected context, simultaneous sources, adopted versus published edition, mid-session package update, source retirement, and every applicability disposition."},
    {"id": "C40-S04", "kind": "CRITERION_SEVERITY", "assertion": "All four screening results are represented, severity is scale-qualified, and cross-scale ordering requires an exact mapping release."},
    {"id": "C40-S05", "kind": "MEASUREMENT_DERIVATION", "assertion": "Exact inch/mm, psi/kPa, affine, rounding, duplicate, uncertainty, denominator, overflow, dimension, and evaluator-version cases remain deterministic and fail closed when invalid."},
    {"id": "C40-S06", "kind": "HISTORY_PINNING", "assertion": "Completed scope and criterion results preserve their authority, protocol, evaluator, source, and predecessor history through updates and recovery."},
    {"id": "C40-F01", "kind": "PATH_DIGEST_FENCE", "assertion": "Exactly the 86-path C40 fence is accounted for (71 existing and 15 new), with exact manifest byte/digest rows, no unowned path, and zero S10 overlap."},
    {"id": "C40-B01", "kind": "STATIC_BOUNDARY", "assertion": "The result is PASS_STATIC_PROVISIONAL and all native, hosted, adoption, acceptance, and release flags and credits are false."},
)

_SOURCE_PROJECTION = {
    "registerRows": ["| 48 | <a id=\"v23-p03-c40-register\"></a>[`V23-P03-C40`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c40) | Authority sources, applicability, criterion and severity bindings, measurement protocols, and deterministic derivation | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C39` | `EXACT_WITH_GENERATION_REBIND` |"],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 0,
    "canonicalRecordWriterOwnershipRowCount": 9,
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001", "V23-POL-HIG-001", "V23-POL-A11Y-001", "V23-POL-L10N-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C40).CONTRACTS", *CONTRACT_NAMES, "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C13", "V23-P03-C41", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
    "canonicalRegisterDigest": "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd",
    "directGraphDigest": "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae",
    "selectorManifestDigest": "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2",
    "relationManifestDigest": "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4",
    "dependencyDispositionDigest": "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c",
    "impactManifestDigest": "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b",
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 1,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [{
        "cardID": "V23-P03-C39",
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "checkpointDigest": "0bb45f959929ebbab657448b8e02edac094c67be7fe8a53dbd6dcfdea7110c9b",
        "contextDigest": "c17b4ad987ed57fb4a44ba6adaa53b19d9ea0e2d6de33b79736fd66063301329",
        "pathFenceDigest": "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2",
        "verificationReceiptDigest": "e3fb3ae902e943f6fe0421ed6b15406797d0c36a307d7538915ef0491348ca87",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AND_ORDERING_AUTHORITY_AT_EXACT_APP_HEAD",
    }],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
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
            schemas = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
            result["items"] = next(iter(schemas.values())) if len(schemas) == 1 else {"anyOf": [schemas[key] for key in sorted(schemas)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/authority-criterion.schema.json", "title": "V23 P03 C40 Authority Criterion Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": 48, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C39"], "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V11_AUTHORITY_CRITERION_DERIVATION",
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V11_WRITE", "uiSurfaceDelta": True, "brandSurfaceDelta": True,
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True, "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": []}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": _SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "EXACT_WITH_GENERATION_REBIND", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({
        "schema": "V23P03C40AuthorityCriterionContractV1", "artifact": "V23P03C40AuthorityCriterionContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": _SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows),
        "semanticScope": SEMANTIC_SCOPE,
        "requiredSemantics": {"contractNames": list(CONTRACT_NAMES), "sourceTypes": list(SOURCE_TYPES), "licenseStorageDispositions": list(LICENSE_STORAGE_DISPOSITIONS), "applicabilityDispositions": list(APPLICABILITY_DISPOSITIONS), "criterionResults": list(CRITERION_RESULTS), "severityScaleStates": list(SEVERITY_SCALE_STATES), "measurementDispositions": list(MEASUREMENT_DISPOSITIONS), "derivationDispositions": list(DERIVATION_DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)},
        "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C41", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "sourceTypes": list(SOURCE_TYPES), "licenseStorageDispositions": list(LICENSE_STORAGE_DISPOSITIONS), "applicabilityDispositions": list(APPLICABILITY_DISPOSITIONS), "criterionResults": list(CRITERION_RESULTS), "severityScaleStates": list(SEVERITY_SCALE_STATES), "measurementDispositions": list(MEASUREMENT_DISPOSITIONS), "derivationDispositions": list(DERIVATION_DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({
        "schema": "V23P03C40AuthorityCriterionEvidenceReceiptV1", "artifact": "V23P03C40AuthorityCriterionEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": _SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics),
        "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C40BrandImpactManifestV1", "artifact": "V23P03C40BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
        "affectedSurfacePaths": [], "semanticStates": ["UNKNOWN", "CONFLICT_REVIEW_REQUIRED", "INCONCLUSIVE", "UNSUPPORTED", "NOT_EVALUATED"], "contractArtifact": contract_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


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
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    fixture_raw = pretty(CORPUS)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    brand_raw = pretty(brand_document(contract_row))
    rendered: dict[str, bytes] = {FIXTURE_PATH: fixture_raw, SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C40ToolingManifestV1", "artifact": "V23P03C40ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows,
        "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": _SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


CORPUS: dict[str, Any] = {
    "schema": "V21P03C40AuthorityCriterionCorpusV1", "schemaVersion": SCHEMA_VERSION, "cardID": CARD,
    "requiredContractNames": list(CONTRACT_NAMES), "sourceTypes": list(SOURCE_TYPES), "licenseStorageDispositions": list(LICENSE_STORAGE_DISPOSITIONS),
    "applicabilityDispositions": list(APPLICABILITY_DISPOSITIONS), "criterionResults": list(CRITERION_RESULTS), "severityScaleStates": list(SEVERITY_SCALE_STATES),
    "measurementDispositions": list(MEASUREMENT_DISPOSITIONS), "derivationDispositions": list(DERIVATION_DISPOSITIONS), "lifecycleDimensions": list(LIFECYCLE_DIMENSIONS),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "evidenceCases": list(EVIDENCE_CASES),
    "persistence": {"schemaRelease": "PERSISTENT_SCHEMA_V11_AUTHORITY_CRITERION_DERIVATION", "predecessorSchemaVersion": 10, "migration": "EXACT_V10_TO_V11_COPY_ON_WRITE", "canonicalWriter": "V23-P02-C01", "firstWriteEnrolled": True, "compatibilityRequired": True, "backupRestoreRequired": True, "deleteEraseRequired": True, "exportImportPreviewRequired": True, "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V11_WRITE"},
    "authoritySourceReleases": [
        {"id": "synthetic-guidance-v1", "issuer": "Synthetic Publisher", "publisher": "Synthetic Publisher", "title": "Synthetic authority metadata", "designation": "SYN-G-001", "edition": "1", "addendaOrCorrigenda": [], "sourceType": "GUIDANCE", "publicationDate": "2024-01-01", "effectiveDate": "2024-01-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-guidance-v1", "retrievalTime": "2024-01-02", "retrievedAt": "2024-01-02", "sourceDigest": None, "licenseStorageDisposition": "METADATA_ONLY", "licensedBytesStored": False, "copiedSourceTextStored": False},
        {"id": "synthetic-adopted-v1", "issuer": "Synthetic Authority", "publisher": "Synthetic Authority", "title": "Synthetic adopted metadata", "designation": "SYN-A-001", "edition": "1", "addendaOrCorrigenda": ["none"], "sourceType": "ADOPTED_RULE", "publicationDate": "2024-02-01", "effectiveDate": "2024-03-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-adopted-v1", "retrievalTime": "2024-03-02", "retrievedAt": "2024-03-02", "sourceDigest": "0" * 64, "licenseStorageDisposition": "LAWFUL_C23_REFERENCE", "lawfulC23ReferenceReleaseID": "c23-release-synthetic-v1", "licensedBytesStored": False, "copiedSourceTextStored": False},
        {"id": "synthetic-standard-v1", "issuer": "Synthetic Standards Body", "publisher": "Synthetic Standards Body", "title": "Synthetic voluntary metadata", "designation": "SYN-V-001", "edition": "1", "addendaOrCorrigenda": [], "sourceType": "VOLUNTARY_STANDARD", "publicationDate": "2024-04-01", "effectiveDate": "2024-04-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-standard-v1", "retrievalTime": "2024-04-02", "retrievedAt": "2024-04-02", "sourceDigest": None, "licenseStorageDisposition": "METADATA_ONLY", "licensedBytesStored": False, "copiedSourceTextStored": False},
        {"id": "synthetic-manufacturer-v1", "issuer": "Synthetic Manufacturer", "publisher": "Synthetic Manufacturer", "title": "Synthetic manufacturer metadata", "designation": "SYN-M-001", "edition": "1", "addendaOrCorrigenda": [], "sourceType": "MANUFACTURER_INSTRUCTION", "publicationDate": "2024-05-01", "effectiveDate": "2024-05-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-manufacturer-v1", "retrievalTime": "2024-05-02", "retrievedAt": "2024-05-02", "sourceDigest": None, "licenseStorageDisposition": "METADATA_ONLY", "licensedBytesStored": False, "copiedSourceTextStored": False},
        {"id": "synthetic-contract-v1", "issuer": "Synthetic Contract Party", "publisher": "Synthetic Contract Party", "title": "Synthetic contract metadata", "designation": "SYN-C-001", "edition": "1", "addendaOrCorrigenda": [], "sourceType": "CONTRACT_OR_INSURER", "publicationDate": "2024-06-01", "effectiveDate": "2024-06-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-contract-v1", "retrievalTime": "2024-06-02", "retrievedAt": "2024-06-02", "sourceDigest": None, "licenseStorageDisposition": "METADATA_ONLY", "licensedBytesStored": False, "copiedSourceTextStored": False},
        {"id": "synthetic-owner-v1", "issuer": "Synthetic Owner", "publisher": "Synthetic Owner", "title": "Synthetic owner policy metadata", "designation": "SYN-O-001", "edition": "1", "addendaOrCorrigenda": [], "sourceType": "OWNER_POLICY", "publicationDate": "2024-07-01", "effectiveDate": "2024-07-01", "retiredDate": None, "url": None, "locator": "c23://reference/synthetic-owner-v1", "retrievalTime": "2024-07-02", "retrievedAt": "2024-07-02", "sourceDigest": None, "licenseStorageDisposition": "METADATA_ONLY", "licensedBytesStored": False, "copiedSourceTextStored": False},
    ],
    "licenseStorageDispositionRecords": [
        {"id": "metadata-only", "mode": "METADATA_ONLY", "sourceTextStored": False, "licensedBytesStored": False, "lawfulReferenceReleaseID": None},
        {"id": "lawful-c23-reference", "mode": "LAWFUL_C23_REFERENCE", "sourceTextStored": False, "licensedBytesStored": False, "lawfulReferenceReleaseID": "c23-release-synthetic-v1"},
        {"id": "rights-unresolved", "mode": "RIGHTS_UNRESOLVED", "sourceTextStored": False, "licensedBytesStored": False, "lawfulReferenceReleaseID": None},
    ],
    "basisBindings": [
        {"id": "basis-owner-policy", "basisKind": "OWNER_POLICY", "sourceReleaseIDs": ["synthetic-guidance-v1"], "personSelected": True, "adoptionInferred": False, "jurisdictionInferred": False},
        {"id": "basis-conflict", "basisKind": "ADOPTION", "sourceReleaseIDs": ["synthetic-adopted-v1", "synthetic-guidance-v1"], "personSelected": True, "adoptionInferred": False, "jurisdictionInferred": False},
    ],
    "applicabilityContexts": [
        {"id": "context-applicable", "siteID": "site-synthetic-1", "activityID": "activity-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "packageReleaseID": "package-c40-v1", "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": "qualification-c38-1", "effectiveDate": "2024-03-10", "basisBindingID": "basis-owner-policy", "sourceReleaseIDs": ["synthetic-guidance-v1"], "disposition": "APPLICABLE", "personSelected": True},
        {"id": "context-not-applicable", "siteID": "site-synthetic-1", "activityID": "activity-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "packageReleaseID": "package-c40-v1", "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": None, "effectiveDate": "2024-03-10", "basisBindingID": "basis-owner-policy", "sourceReleaseIDs": ["synthetic-guidance-v1"], "disposition": "NOT_APPLICABLE_WITH_REASON", "reason": "scope-excluded-by-person", "personSelected": True},
        {"id": "context-unknown", "siteID": "site-synthetic-1", "activityID": "activity-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "packageReleaseID": "package-c40-v1", "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": "qualification-c38-1", "effectiveDate": "2024-03-10", "basisBindingID": "basis-owner-policy", "sourceReleaseIDs": [], "disposition": "UNKNOWN", "personSelected": True},
        {"id": "context-conflict", "siteID": "site-synthetic-1", "activityID": "activity-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "packageReleaseID": "package-c40-v1", "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": "qualification-c38-1", "effectiveDate": "2024-03-10", "basisBindingID": "basis-conflict", "sourceReleaseIDs": ["synthetic-adopted-v1", "synthetic-guidance-v1"], "disposition": "CONFLICT_REVIEW_REQUIRED", "personSelected": True},
        {"id": "context-unsupported", "siteID": "site-synthetic-1", "activityID": "activity-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "packageReleaseID": "package-c40-v1", "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": "qualification-c38-1", "effectiveDate": "2024-03-10", "basisBindingID": "basis-owner-policy", "sourceReleaseIDs": ["synthetic-guidance-v1"], "disposition": "UNSUPPORTED", "personSelected": True},
    ],
    "assessmentScopes": [{"id": "scope-synthetic-1", "subjectSnapshotID": "subject-synthetic-1", "contextSnapshotID": "context-applicable", "packageReleaseID": "package-c40-v1", "sourceReleaseIDs": ["synthetic-guidance-v1"], "actorSnapshotID": "actor-c38-1", "qualificationSnapshotID": "qualification-c38-1", "effectiveDate": "2024-03-10", "frozen": True}],
    "severityScaleReleases": [
        {"id": "scale-synthetic-v1", "version": 1, "state": "RELEASED", "levels": [{"id": "LOW", "localizedKey": "criterion.severity.low"}, {"id": "HIGH", "localizedKey": "criterion.severity.high"}], "crossScaleMappingReleaseID": "mapping-synthetic-v1"},
        {"id": "scale-synthetic-v0", "version": 0, "state": "RETIRED", "levels": [{"id": "LEGACY", "localizedKey": "criterion.severity.legacy"}], "crossScaleMappingReleaseID": None},
    ],
    "crossScaleMappingReleases": [{"id": "mapping-synthetic-v1", "fromScaleID": "scale-synthetic-v0", "toScaleID": "scale-synthetic-v1", "mapping": [{"fromLevelID": "LEGACY", "toLevelID": "LOW"}], "exact": True}],
    "classificationBindings": [{"id": f"classification-{result.lower()}", "scopeSnapshotID": "scope-synthetic-1", "criterionResult": result, "severityScaleReleaseID": "scale-synthetic-v1", "severityLevelID": "LOW" if result == "MEETS_SCREENING_CRITERION" else None, "language": "assessed against", "safeClaim": False} for result in CRITERION_RESULTS],
    "measurementProtocols": [{"id": "protocol-synthetic-v1", "version": 1, "normativeUnit": "mm", "samplingPolicy": "DECLARED_SAMPLE_SET", "missingPolicy": "FAIL_CLOSED", "outlierPolicy": "PRESERVE_AND_MARK", "duplicatePolicy": "FAIL_CLOSED", "uncertaintyPolicy": "EXPLICIT_INTERVAL", "roundingPolicy": "DISPLAY_ONLY_AFTER_CANONICAL_RESULT", "unitAuthority": "V23-P03-C03", "released": True}],
    "evaluatorDescriptors": [{"id": "evaluator-synthetic-v1", "version": 1, "implementationKind": "APP_BUNDLED_PURE", "implementationDigest": "1" * 64, "protocolReleaseID": "protocol-synthetic-v1", "formulaReference": "NONE", "packageSupplied": False, "floatingPointCanonicalThresholds": False}],
    "derivedFacts": [{"id": "derived-synthetic-valid", "rawInputDigest": "2" * 64, "evaluatorDescriptorID": "evaluator-synthetic-v1", "inputUnit": "mm", "conversionPolicy": "C03_EXACT", "roundingPolicy": "DISPLAY_ONLY", "result": "MEETS_SCREENING_CRITERION", "uncertainty": "EXPLICIT_INTERVAL", "disposition": "DERIVED", "predecessorID": None}, {"id": "derived-synthetic-inconclusive", "rawInputDigest": "3" * 64, "evaluatorDescriptorID": "evaluator-synthetic-v1", "inputUnit": "mm", "conversionPolicy": "C03_EXACT", "roundingPolicy": "DISPLAY_ONLY", "result": "INCONCLUSIVE", "uncertainty": "UNKNOWN", "disposition": "INCONCLUSIVE", "predecessorID": "derived-synthetic-valid"}],
    "derivedFactProvenance": [{"derivedFactID": "derived-synthetic-valid", "rawInputPreserved": True, "conversionPreserved": True, "roundingPreserved": True, "resultPreserved": True, "uncertaintyPreserved": True, "dispositionPreserved": True, "predecessorPreserved": True}],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED"} for case_id in ("missing-adoption-basis", "contradictory-source-basis", "gps-derived-jurisdiction", "copyrighted-bytes", "source-digest-mismatch", "expired-qualification", "duplicate-samples", "zero-denominator", "overflow", "dimension-mismatch", "display-rounding-boundary", "unknown-evaluator", "unknown-unit-version", "floating-point-threshold", "package-script", "safe-compliant-certified-copy-leak")],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_ACTIVATION"} for case_id in ("release-admission-boundary", "binding-boundary", "derivation-boundary", "report-boundary", "archive-boundary", "restore-boundary", "replay-boundary")],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "RECOVER_EFFECT_RECEIPT_AND_HISTORY"} for case_id in ("backup-clone-fork", "journal-replay-checkpoint", "compatibility-forward-fix", "search-report", "delete-erase", "released-v1")],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
}
