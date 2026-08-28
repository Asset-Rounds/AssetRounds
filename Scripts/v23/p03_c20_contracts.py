#!/usr/bin/env python3
"""Deterministic static contract corpus and evidence builders for V23-P03-C20."""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C20"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 57
TITLE = "PrivacyTransformManifestV1, manual redaction review, immutable-original protection, and audience-safe derivative projection"
BASE_HEAD = "af134ec68a2708bda01b5680c535651952993055"
BASE_TREE = "12bb97d262c282b0f01c41193e61361b81556e9e"
COORDINATION_HEAD = "445f7ec70c01087532b25ab7d162e8a9e1ca90db"
COORDINATION_TREE = "78db67b0377d63fb849c063436615d9c4edc8239"
COORDINATION_LEDGER_DIGEST = "7a4e2eddbec685d6732c48fb9cea0bec2f6be597f0eedfc43b5f1a592ec4cd92"
COORDINATION_PROJECTION_DIGEST = "5014fda09437b1c4d728a418ea032d23c0c9e81c5b3df829580c790deea05948"
COORDINATION_CAS_SEQUENCE = 242
HYDRATION_TRANSITION_SEQUENCE = 242
HYDRATION_TRANSITION_DIGEST = "b6119fa2df58faaca002a67948de5071118dabb877996c78205913cb80efedd5"
CONTEXT_DIGEST = "00862b45e494d0a5b99160156e117661b354a27cfbf91d38d7b4c62c00b35226"
FENCE_DIGEST = "f03324cba026c1532c7de1f616525a2354251ede2f7e6ff7bc24a51b53405228"
PREREQUISITE_DIGEST = "74967f57da320d404336b02f022050b8e2a979a3a7e2964feb56bdd0041cd69d"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "cb7c7b2c8c4bc9b276f41645d6242f95bcf00687d1bf9e1ce7782648ad9afff9"
REGISTER_ROW_UTF8_LENGTH = 312
DOSSIER_SHA256 = "da7016fa69be19df2487a6932f425b91be14dbeff3de88c60b2e46656a3f7fc4"
DOSSIER_UTF8_LENGTH = 7217
INHERITED_V21_BLOCK_SHA256 = "9db1d347531f203e9105296e1f3f15c258074c8841117e095351a2d15e2f87ff"
INHERITED_V21_BLOCK_UTF8_LENGTH = 11594

SCHEMA_PATH = "Scripts/v23/privacy-transform.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C20PrivacyTransformContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C20PrivacyTransformEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C20PrivacyTransformBrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C20-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c20_contracts.py",
    "Scripts/v23/generate_p03_c20_contracts.py",
    "Scripts/v23/verify_p03_c20_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# Exact order sealed by the C20 BootstrapPathFenceV1.  The six C05
# content/media declaration owners are carried forward because C20's
# original/derivative lifecycle depends on those canonical contracts.
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
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Content/PrivacyTransformContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/PrivacyTransformPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Content/PrivacyTransformCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/PrivacyTransformLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_34PrivacyTransformTests.swift",
    "FieldEvidenceAppUITests/V23_P03_C20PrivacyTransformUITests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/PrivacyTransform/V21P03C20PrivacyTransformCorpusV1.json",
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

_OVERLAP_COUNTS = {
    "V23-P00-C10": 2, "V23-P00-C11": 1,
    "V23-P01-C01": 3, "V23-P01-C02": 7, "V23-P01-C03": 6,
    "V23-P01-C04": 3, "V23-P01-C05": 12, "V23-P01-C06": 23,
    "V23-P01-C07": 7, "V23-P02-C01": 7, "V23-P02-C02": 29,
    "V23-P02-C03": 22, "V23-P02-C04": 6, "V23-P02-C05": 10,
    "V23-P02-C06": 2, "V23-P02-C07": 29, "V23-P02-C08": 6,
    "V23-P02-C09": 5, "V23-P03-C01": 2, "V23-P03-C02": 3,
    "V23-P03-C03": 4, "V23-P03-C04": 1, "V23-P03-C05": 6,
    "V23-P03-C06": 7, "V23-P03-C07": 3, "V23-P03-C08": 12,
    "V23-P03-C09": 39, "V23-P03-C10": 2, "V23-P03-C11": 5,
    "V23-P03-C12": 35, "V23-P03-C13": 73, "V23-P03-C14": 76,
    "V23-P03-C15": 71, "V23-P03-C16": 5, "V23-P03-C17": 30,
    "V23-P03-C18": 74, "V23-P03-C19": 98, "V23-P03-C35": 37,
    "V23-P03-C36": 61, "V23-P03-C38": 49, "V23-P03-C39": 51,
    "V23-P03-C40": 71, "V23-P03-C41": 70,
}
PRIOR_FENCE_OVERLAPS = tuple(
    {
        "cardID": card,
        "fenceDigest": "BOUND_TO_C20_HYDRATION_PRIOR_FENCE_PROOF",
        "disposition": "REPROOF_REQUIRED",
        "overlapCount": count,
    }
    for card, count in _OVERLAP_COUNTS.items()
)
PRIOR_FENCE_PROOF = {
    "fenceCount": len(PRIOR_FENCE_OVERLAPS),
    "priorOwnedPathCount": 1300,
    "overlapCount": 1065,
    "authorizedOverlapCount": 1065,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "PrivacyTransformPolicyV1",
    "PrivacyRegionV1",
    "PrivacyTransformManifestV1",
    "PrivacyReviewReceiptV1",
)
PERSISTENT_SCHEMA_VERSION = 19
RECORDS_SCHEMA_VERSION = 18
PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT = 77
DURABLE_FAMILY_COUNT = 4
TRANSFORM_KINDS = ("SOLID_FILL", "BLUR", "PIXELATE")
AUDIENCES = ("INTERNAL_REVIEW", "CUSTOMER_REPORT", "EXTERNAL_COLLABORATOR")
COORDINATE_SPACES = ("NORMALIZED_IMAGE_V1", "PIXEL_IMAGE_V1")
COORDINATE_API_TYPES = (
    "PrivacyCoordinateSpaceV1",
    "PrivacyImageOrientationV1",
    "PrivacyCoordinateScaleV1",
    "PrivacyCoordinateProjectionV1",
)
ORIENTATIONS = (
    "UP",
    "UP_MIRRORED",
    "DOWN",
    "DOWN_MIRRORED",
    "LEFT",
    "LEFT_MIRRORED",
    "RIGHT",
    "RIGHT_MIRRORED",
)
COORDINATE_SCALE_RATIOS = ("1/1", "3/2")
NORMALIZED_COORDINATE_SCALE = 1_000_000
SOURCE_BOUNDS_FIELDS = ("x", "y", "width", "height")
REVIEW_DECISIONS = ("APPROVED", "REJECTED")
SANITATION_DISPOSITIONS = ("SANITIZED", "REJECTED_PROHIBITED_METADATA")
PROJECTION_DISPOSITIONS = (
    "APPROVED_NONSTALE_DERIVATIVE",
    "DENY_MISSING_REVIEW",
    "DENY_REJECTED_REVIEW",
    "DENY_STALE_SOURCE",
    "DENY_WRONG_AUDIENCE",
    "DENY_WRONG_POLICY",
    "DENY_DIGEST_DIVERGENCE",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C20G01PrivacyRegionsAreCanonicalNormalizedAndImmutable",
    "testV23P03C20A01ApprovedProjectionRequiresSanitizedDerivativeAndExactAudience",
    "testV23P03C20H01MissingRejectedStaleWrongPolicyAndDigestInputsFailClosed",
    "testV23P03C20I01PublicationRowsAndRecoveryAreAtomicAndIdempotent",
    "testV23P03C20R01V19BackupRestoreDeleteEraseAndProjectionConsumersRemainDeniedByDefault",
)
SOURCE_CONTRACT_TOKENS = (
    CARD, "V21-P03-C20", *CONTRACT_NAMES, "immutable original",
    *COORDINATE_API_TYPES, *COORDINATE_SPACES, *ORIENTATIONS,
    "separate derivative", "manual", "metadata sanitation",
    "deny-by-default", "audience", "source bounds", "coordinate scale",
)

REQUIRED_BEHAVIORS = (
    {
        "id": "MANUAL_POLICY",
        "contract": "PrivacyTransformPolicyV1",
        "requirement": "A closed policy names purpose, audience, allowed manual transform kinds, metadata sanitation, review requirement, expiration, and stale-state behavior without automatic recognition or background scanning.",
        "evidence": "C20-S01",
    },
    {
        "id": "BOUNDED_REGIONS",
        "contract": "PrivacyRegionV1",
        "requirement": "Normalized bounded manual regions retain transform kind, reason, author, source digest, coordinate-space version, orientation, source bounds, scale, and deterministic ordering.",
        "evidence": "C20-S02",
    },
    {
        "id": "IMMUTABLE_ORIGINAL_SEPARATE_DERIVATIVE",
        "contract": "PrivacyTransformManifestV1",
        "requirement": "The manifest binds immutable original bytes and provenance to a separate derivative, policy, ordered regions, renderer, sanitation result, source digest, derivative digest, and stale state.",
        "evidence": "C20-S03",
    },
    {
        "id": "METADATA_SANITATION",
        "contract": "PrivacyTransformManifestV1",
        "requirement": "Derivative metadata sanitation is explicit and evidence-bearing; prohibited retained metadata rejects the derivative and never rewrites the original.",
        "evidence": "C20-S04",
    },
    {
        "id": "AUDIENCE_SAFE_PROJECTION",
        "contract": "PrivacyReviewReceiptV1",
        "requirement": "Report, open JSON, share/export, search thumbnail, and evidence visibility project only an APPROVED non-stale digest-matching derivative for the declared audience; missing, rejected, stale, wrong-audience, wrong-policy, or divergent input denies by default.",
        "evidence": "C20-S05",
    },
    {
        "id": "V19_LIFECYCLE",
        "contract": "PERSISTENT_SCHEMA_V19",
        "requirement": "V19 and records18 close migration, backup/restore, delete/Erase, export/report, search/rebuild, replay, sync classification, interruption, recovery, and forward-fix behavior for all four durable families.",
        "evidence": "C20-S06",
    },
    {
        "id": "CANONICAL_REVIEW_RECEIPT",
        "contract": "PrivacyReviewReceiptV1",
        "requirement": "Review decisions bind exact derivative, policy, audience, source revision, rationale, reviewer, and immutable receipt digest through the sole canonical writer.",
        "evidence": "C20-S07",
    },
    {
        "id": "STATIC_BOUNDARY",
        "contract": CARD,
        "requirement": "This lane is PASS_STATIC_PROVISIONAL and native, hosted, adoption, acceptance, release, and Phase 10 claims remain false.",
        "evidence": "C20-B01",
    },
)
EVIDENCE_CASES = (
    {"id": "C20-S01", "kind": "GOLDEN", "assertion": "A manually authored policy and bounded regions produce one deterministic derivative while preserving the original byte and digest."},
    {"id": "C20-S02", "kind": "ALTERNATE", "assertion": "Offline, empty, all eight orientations, normalized/pixel spaces, 1/1 and 3/2 scales, source bounds, and audience-specific alternate inputs retain canonical meaning and deterministic region ordering."},
    {"id": "C20-S03", "kind": "IMMUTABLE_ORIGINAL", "assertion": "Original and derivative content references are separate and backup/restore/delete/Erase never mutate original authority."},
    {"id": "C20-S04", "kind": "METADATA", "assertion": "Sanitized derivative metadata is explicit; prohibited retained fields reject projection without a source rewrite."},
    {"id": "C20-S05", "kind": "AUDIENCE_PROJECTION", "assertion": "Only an approved non-stale derivative with matching audience, policy, source revision, and digest can reach report/open JSON/share/search visibility."},
    {"id": "C20-S06", "kind": "LIFECYCLE", "assertion": "V19/records18 migration, backup/restore, import/export, report, search/rebuild, replay, classification, delete, Erase, interruption, recovery, and forward fix close all four durable families."},
    {"id": "C20-S07", "kind": "REVIEW", "assertion": "APPROVED and REJECTED review receipts are exact, immutable, and purpose/audience bound."},
    {"id": "C20-H01", "kind": "HOSTILE", "assertion": "Original mutation, automatic recognition, cloud/provider processing, prohibited metadata, unknown transform, stale source, wrong audience/policy, and digest divergence fail closed with no partial canonical success."},
    {"id": "C20-I01", "kind": "INTERRUPTION", "assertion": "Render/export interruption leaves original authority intact and either no derivative or one digest-valid unapproved derivative that cannot project."},
    {"id": "C20-R01", "kind": "RECOVERY", "assertion": "Recovery and replay resume from an immutable boundary without duplicate rows or receipts and preserve exact old-or-new privacy artifacts."},
    {"id": "C20-F01", "kind": "PATH_FENCE", "assertion": "The hydrated fence is exactly 119 paths: 104 existing and 15 new, with zero S10 overlap and 1,065 authorized prior-fence edges."},
    {"id": "C20-B01", "kind": "STATIC_BOUNDARY", "assertion": "Activation, native, hosted, adoption, acceptance, release, and acceptance-credit claims remain false pending later evidence and S10.6 reconciliation."},
)

SOURCE_PROJECTION = {
    "registerRows": [
        "| 57 | <a id=\u0060v23-p03-c20-register\u0060></a>[\u0060V23-P03-C20\u0060](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c20) | PrivacyTransformManifestV1, manual redaction review, immutable-original protection, and audience-safe derivative projection | \u0060IMPLEMENT_NOW\u0060 | \u0060NOT_STARTED\u0060 | \u0060V23-P03-C17\u0060 | \u0060REFINED_WITHOUT_LOSS\u0060 |",
    ],
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
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C20).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C21", "V23-P03-C44", "V23-P03-C46", "V23-P03-C50", "V23-P04-C14", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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
    "predecessors": [
        {
            "cardID": "V23-P03-C17",
            "attemptID": 1,
            "candidateHead": "38b5bd807bb7e1096e015077f72a9e25b8b06b6a",
            "candidateTree": "8d36b480b0103993ad0c5dab6df055bf63b2da8d",
            "checkpointDigest": "3511f3a7fad741bf639dbfae0a22e0cddc1e8a0185ddfb8b4360262306d43b7f",
            "verificationReceiptDigest": "1ddff8c2eee58e3b7984bb8986356015fc84886135fe6dcc7a72b857cc32072a",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C17_HEAD",
        }
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "durableOwner": ["PrivacyTransformPolicyV1", "PrivacyRegionV1", "PrivacyTransformManifestV1", "PrivacyReviewReceiptV1", "PersistentSchemaV19"],
    "atomicAuthorityPolicy": "IMMUTABLE_ORIGINAL_SEPARATE_DERIVATIVE_MANIFEST_REGIONS_AND_REVIEW_RECEIPT_EFFECT_COMMIT_IN_ONE_SWIFTDATA_TRANSACTION_USING_THE_SOLE_CANONICAL_WRITER",
    "transformPolicy": "MANUAL_BOUNDED_DETERMINISTIC_REGION_TRANSFORMS_WITH_EXPLICIT_POLICY_AUDIENCE_REASON_COORDINATE_SPACE_AND_RENDERER_VERSION_NO_AUTOMATIC_RECOGNITION_OR_BACKGROUND_SCAN",
    "derivativePolicy": "IMMUTABLE_ORIGINAL_BYTES_DIGEST_AND_PROVENANCE_REMAIN_UNCHANGED_DERIVATIVE_BINDS_EXACT_SOURCE_POLICY_AUDIENCE_AND_SANITIZED_METADATA",
    "projectionPolicy": "REPORT_OPEN_JSON_SHARE_EXPORT_AND_SEARCH_USE_ONLY_APPROVED_NONSTALE_DIGEST_MATCHING_DERIVATIVE_AND_DENY_MISSING_REJECTED_WRONG_AUDIENCE_OR_WRONG_POLICY",
    "lifecyclePolicy": "V19_RECORDS18_ZERO_INVENTION_FROM_V18_BACKUP_RESTORE_CLONE_FORK_IMPORT_EXPORT_JOURNAL_REPLAY_SEARCH_REBUILD_DELETE_ERASE_RETENTION_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "privacyPolicy": "NO_PROHIBITED_SOURCE_METADATA_IN_DERIVATIVE_NO_ORIGINAL_REWRITE_NO_LEGAL_COMPLIANCE_OR_GUARANTEED_ANONYMIZATION_CLAIM_AND_NO_CUSTOMER_DATA_IN_TELEMETRY",
    "forbiddenPolicy": "NO_FACE_OR_IDENTITY_OR_LICENSE_PLATE_RECOGNITION_CLOUD_VISION_REMOTE_PROCESSOR_BIOMETRIC_TEMPLATE_VIDEO_AUDIO_REDACTION_PROVIDER_UPLOAD_ACCOUNT_CLOUD_OR_SECOND_STORE",
    "s10Policy": "EXACT_ONE_HUNDRED_NINETEEN_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP_AND_NAMED_C20_UI_TEST_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

CORPUS: dict[str, Any] = {
    "schema": "V21P03C20PrivacyTransformCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION,
    "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
    "persistentPrivacyTransformKindCount": DURABLE_FAMILY_COUNT,
    "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT,
    "durableFamilyCount": DURABLE_FAMILY_COUNT,
    "migrationInventedPrivacyTransformCount": 0,
    "requiredContractNames": list(CONTRACT_NAMES),
    "coordinateAPITypes": list(COORDINATE_API_TYPES),
    "transformKinds": list(TRANSFORM_KINDS),
    "audiences": list(AUDIENCES),
    "coordinateSpaces": list(COORDINATE_SPACES),
    "orientations": list(ORIENTATIONS),
    "normalizedCoordinateScale": NORMALIZED_COORDINATE_SCALE,
    "coordinateScaleRatios": list(COORDINATE_SCALE_RATIOS),
    "sourceBoundsFields": list(SOURCE_BOUNDS_FIELDS),
    "reviewDecisions": list(REVIEW_DECISIONS),
    "sanitationDispositions": list(SANITATION_DISPOSITIONS),
    "projectionDispositions": list(PROJECTION_DISPOSITIONS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
    "forbiddenClaims": [
        "FACE_RECOGNITION", "IDENTITY_RECOGNITION", "LICENSE_PLATE_RECOGNITION",
        "AUTOMATIC_DETECTION", "CLOUD_VISION", "REMOTE_PROCESSOR",
        "BIOMETRIC_TEMPLATE", "VIDEO_AUDIO_REDACTION", "ORIGINAL_MUTATION",
        "GUARANTEED_ANONYMIZATION", "LEGAL_COMPLIANCE", "PROVIDER_UPLOAD",
        "ACCOUNT_OR_CLOUD_STATE", "SECOND_STORE_OR_WRITER",
    ],
    "persistence": {
        "schemaRelease": "PRIVACY_TRANSFORM_V1",
        "schemaVersion": PERSISTENT_SCHEMA_VERSION,
        "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
        "mode": "NEW_SCHEMA_VERSION",
        "migrationRequired": True,
        "backupRestoreRequired": True,
        "deleteEraseRequired": True,
        "exportReportRequired": True,
        "searchRebuildRequired": True,
        "replayRequired": True,
        "classificationRequired": True,
        "interruptionRecoveryRequired": True,
        "canonicalWriter": "V23-P02-C01",
        "canonicalSourceOfTruth": list(CONTRACT_NAMES),
        "persistedFamilies": list(CONTRACT_NAMES),
        "nonPersistentFamilies": [],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V19_WRITE",
        "forwardFix": "RETAIN_IMMUTABLE_ORIGINAL_AND_RECEIPTS_DENY_UNSAFE_PROJECTION_AND_APPEND_VERSIONED_TRANSFORM_REVIEW_OR_AMENDMENT_NEVER_REWRITE_HISTORY",
    },
    "goldenCases": [
        {"id": "manual-approved", "transform": "SOLID_FILL", "audience": "CUSTOMER_REPORT", "review": "APPROVED", "sanitation": "SANITIZED", "originalImmutable": True, "separateDerivative": True},
    ],
    "alternateCases": [
        {"id": "offline-empty-regions", "transform": "BLUR", "audience": "INTERNAL_REVIEW", "review": "APPROVED", "sanitation": "SANITIZED", "regionCount": 0},
        {"id": "scale-orientation-rebound", "transform": "PIXELATE", "audience": "EXTERNAL_COLLABORATOR", "review": "REJECTED", "sanitation": "SANITIZED", "regionCount": 2},
    ],
    "hostileCases": [
        {"id": case_id, "expectedDisposition": "FAIL_CLOSED_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "mutate-original", "automatic-recognition-request", "cloud-vision-request",
            "provider-upload-request", "video-audio-redaction-request", "unknown-transform",
            "invalid-coordinate-space", "out-of-bounds-region", "nondeterministic-overlapping-regions",
            "prohibited-retained-metadata", "missing-review", "rejected-review", "stale-source-revision",
            "wrong-audience", "wrong-policy", "digest-divergence", "forged-review-receipt",
            "cross-workspace-reference", "second-store-or-writer",
        )
    ],
    "interruptionCases": [
        {"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "crash-before-region-commit", "crash-after-derivative-before-manifest",
            "crash-after-manifest-before-review", "render-interruption", "export-interruption",
            "backup-interruption", "restore-interruption", "delete-erase-interruption", "replay-interruption",
        )
    ],
    "recoveryCases": [
        {"id": case_id, "expectedDisposition": "EXACT_OLD_OR_NEW_PRIVACY_ARTIFACTS_NO_DUPLICATE_OR_REWRITE"}
        for case_id in (
            "discard-unreviewed-derivative", "rebuild-derivative", "restore-original-and-derivative",
            "replay-review-receipt", "clone-fork", "import-export-roundtrip", "search-rebuild",
            "journal-replay-from-zero", "forward-fix-after-activation",
        )
    ],
    "claims": {
        claim: False
        for claim in (
            "native", "hosted", "adoption", "acceptance", "release",
            "acceptanceCredit", "releaseCredit", "faceRecognition",
            "identityRecognition", "licensePlateRecognition", "automaticDetection",
            "cloudVision", "remoteProcessor", "biometricTemplate", "originalMutation",
            "guaranteedAnonymization", "legalCompliance", "providerUpload",
            "accountOrCloudState", "secondStore",
        )
    },
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
    return [
        {"path": path, "source": "BASE_HEAD_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)}
        for path in SOURCE_REFERENCE_PATHS
    ]


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    return [
        {"path": path, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw := _git_blob(root, path)), "sha256": sha256_bytes(raw)}
        for path in AUTHORITY_REFERENCE_PATHS
    ]


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
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/privacy-transform.schema.json", "title": "V23 P03 C20 Privacy Transform Corpus"})
    return document


def _flags() -> dict[str, bool]:
    return {"native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False, "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False, "acceptanceCredit": False, "releaseReadiness": False}


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE, "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(PATH_FENCE), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE, "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C17"], "nextCard": "V23-P03-C21",
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V19_PRIVACY_TRANSFORM",
        "recordSchemaVersion": RECORDS_SCHEMA_VERSION, "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT,
        "durableFamilyCount": DURABLE_FAMILY_COUNT, "schemaBehaviorDelta": True, "migrationBehaviorDelta": True,
        "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True,
        "exportCompatibilityRequired": True, "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V19_WRITE",
        "uiSurfaceDelta": True, "brandSurfaceDelta": True, "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False, "physicalLockedState": "REQUIRED_PENDING_OWNER", "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True,
        "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "pathFenceDigest": FENCE_DIGEST, "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "s10FenceOverlapPaths": []}


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "REFINED_WITHOUT_LOSS", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def _required_semantics() -> dict[str, Any]:
    return {"contractNames": list(CONTRACT_NAMES), "coordinateAPITypes": list(COORDINATE_API_TYPES), "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION, "recordsSchemaVersion": RECORDS_SCHEMA_VERSION, "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT, "durableFamilyCount": DURABLE_FAMILY_COUNT, "transformKinds": list(TRANSFORM_KINDS), "audiences": list(AUDIENCES), "coordinateSpaces": list(COORDINATE_SPACES), "orientations": list(ORIENTATIONS), "normalizedCoordinateScale": NORMALIZED_COORDINATE_SCALE, "coordinateScaleRatios": list(COORDINATE_SCALE_RATIOS), "sourceBoundsFields": list(SOURCE_BOUNDS_FIELDS), "reviewDecisions": list(REVIEW_DECISIONS), "sanitationDispositions": list(SANITATION_DISPOSITIONS), "projectionDispositions": list(PROJECTION_DISPOSITIONS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": CORPUS["forbiddenClaims"]}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({"schema": "V23P03C20PrivacyTransformContractV1", "artifact": "V23P03C20PrivacyTransformContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "schemaArtifact": schema_row, "sourceContract": _source_contract(source_rows, authority_rows), "semanticScope": SEMANTIC_SCOPE, "requiredSemantics": _required_semantics(), "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(CONTRACT_NAMES), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "successor": {"cardID": "V23-P03-C21", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = _required_semantics()
    return _sealed({"schema": "V23P03C20PrivacyTransformEvidenceReceiptV1", "artifact": "V23P03C20PrivacyTransformEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows), "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics), "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({"schema": "V23P03C20PrivacyTransformBrandImpactManifestV1", "artifact": "V23P03C20PrivacyTransformBrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "MANUAL_PRIVACY_SELECTION_REVIEW_STATES_ONLY_NO_NEW_BRAND_SURFACE", "affectedSurfacePaths": [], "semanticStates": ["MANUAL_SELECTION", "PREVIEW", "SANITIZED", "APPROVED", "REJECTED", "STALE", "ERROR", "RECOVERY"], "contractArtifact": contract_row, "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})


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


def _assert_constants() -> None:
    if len(EXISTING_PATHS) != 104 or len(NEW_PATHS) != 15 or len(PATH_FENCE) != 119:
        raise ValueError("C20 path fence constants differ")
    if len(set(PATH_FENCE)) != len(PATH_FENCE):
        raise ValueError("C20 path fence contains duplicates")
    if set(PATH_FENCE) & {".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml"}:
        raise ValueError("C20 path fence overlaps S10 workflow")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ValueError("C20 path fence contains S10 path")
    if sum(row["overlapCount"] for row in PRIOR_FENCE_OVERLAPS) != 1065:
        raise ValueError("C20 prior overlap total differs")
    if not all(value is False for value in _flags().values()):
        raise ValueError("C20 activation flag overclaim")
    if CORPUS["persistentSchemaVersion"] != 19 or CORPUS["recordsSchemaVersion"] != 18:
        raise ValueError("C20 schema version differs")
    if CORPUS["persistentKindLifecycleModelCount"] != 77 or CORPUS["durableFamilyCount"] != 4:
        raise ValueError("C20 lifecycle inventory differs")
    if CORPUS["coordinateAPITypes"] != list(COORDINATE_API_TYPES):
        raise ValueError("C20 coordinate API types differ")
    if CORPUS["coordinateSpaces"] != list(COORDINATE_SPACES) or CORPUS["coordinateSpaces"] != ["NORMALIZED_IMAGE_V1", "PIXEL_IMAGE_V1"]:
        raise ValueError("C20 coordinate spaces differ")
    if len(CORPUS["orientations"]) != 8 or CORPUS["orientations"] != list(ORIENTATIONS):
        raise ValueError("C20 orientation set differs")
    if CORPUS["normalizedCoordinateScale"] != 1_000_000 or CORPUS["coordinateScaleRatios"] != ["1/1", "3/2"]:
        raise ValueError("C20 coordinate scale differs")
    if CORPUS["sourceBoundsFields"] != ["x", "y", "width", "height"]:
        raise ValueError("C20 source bounds differ")
    if CORPUS["persistence"]["persistedFamilies"] != list(CONTRACT_NAMES):
        raise ValueError("C20 persistent family ownership differs")
    if CORPUS["persistence"]["secondStore"] or CORPUS["persistence"]["secondWriter"]:
        raise ValueError("C20 second store/writer is prohibited")


def all_outputs(root: Path) -> dict[str, bytes]:
    _assert_constants()
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = json.loads(contract_raw.decode("utf-8"))
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    brand_raw = pretty(brand_document(contract_row))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({"schema": "V23P03C20ToolingManifestV1", "artifact": "V23P03C20ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows, "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True})
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered
