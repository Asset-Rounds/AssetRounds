#!/usr/bin/env python3
"""Deterministic static contract, corpus, and evidence builders for V23-P03-C21.

This module is intentionally static.  It records the sealed coordination facts
for the client-capability/package-lifecycle card and never enables a native,
hosted, adoption, acceptance, release, network, or Phase 10 claim.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C21"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 58
TITLE = "Portable client capability admission and package lifecycle disposition"
BASE_HEAD = "25d0c788f4faa82fca3a88518fbccb45508a0428"
BASE_TREE = "06844bf5e7096d3e4198355c5b8c10a133d5d88f"
COORDINATION_HEAD = "054f8059128789a00d040e333a767d6b218eb2ad"
COORDINATION_TREE = "1d3dafe36c024d00cb01f7d081b3f8ef3f01f861"
COORDINATION_LEDGER_DIGEST = "16ca4a8977d05a34d3b96010eb1ead5c3c61bb7fa2d43c769be6eba05c007f78"
COORDINATION_PROJECTION_DIGEST = "e61951ce7c6575b2270a78f4535a39da4a97bd8ac09c3480bf6956f5b3f4da29"
COORDINATION_CAS_SEQUENCE = 246
HYDRATION_TRANSITION_SEQUENCE = 246
HYDRATION_TRANSITION_DIGEST = "f2a53472bc48df63852b9a20d232d718ff26a3437ea1553fd5f86b2a6d4b358a"
CONTEXT_DIGEST = "033924c121880600a986352b8da1360c058a1e546c4efd987c0aaf85b0123a89"
FENCE_DIGEST = "a961c346c2aa4a68fb18ed9af92497ded130e37e22bded16a99bf2bedf5e8a73"
PREREQUISITE_DIGEST = "9081bc282becb7e77f9e275cbca23310fa1a1fff5273ed42670378365d6908ec"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "4718623f17feac92109ba8127697a24dc7f063b1b4de310a927390777acfdb20"
REGISTER_ROW_UTF8_LENGTH = 297
DOSSIER_SHA256 = "02ff7e18dfbc253de218e7f6163537fe730514e9024adc0a8a96836acd1f9209"
DOSSIER_UTF8_LENGTH = 7129
INHERITED_V21_BLOCK_SHA256 = "92409ffc674dd98ef38be7c4f992a4d8b24173af1ba140086653fc35dc4d39fe"
INHERITED_V21_BLOCK_UTF8_LENGTH = 8576

SCHEMA_PATH = "Scripts/v23/client-capability-package-lifecycle.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C21ClientCapabilityPackageLifecycleContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C21ClientCapabilityPackageLifecycleEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C21ClientCapabilityPackageLifecycleBrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C21-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c21_contracts.py",
    "Scripts/v23/generate_p03_c21_contracts.py",
    "Scripts/v23/verify_p03_c21_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS


def _paths(text: str) -> tuple[str, ...]:
    return tuple(line.strip() for line in text.splitlines() if line.strip())


# Exact order sealed by the C21 BootstrapPathFenceV1.  These are concrete
# repository paths, never directory roots or glob expressions.
EXISTING_PATHS = _paths(
    """
FieldEvidenceApp/Resources/Localizable.xcstrings
FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift
FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift
FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift
FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift
FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift
FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift
FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift
FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift
FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift
FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift
FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift
FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift
FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift
FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift
FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift
FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift
FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift
FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift
FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift
FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift
FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift
FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift
FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift
FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift
FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift
FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift
FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift
FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift
FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift
FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift
FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift
FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift
FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift
FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift
FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift
FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift
FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift
FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift
FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift
FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift
FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift
FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift
FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift
FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift
FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift
FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift
FieldEvidenceApp/Domain/Search/SearchContractsV1.swift
FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift
FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift
FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift
FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift
FieldEvidenceApp/Domain/Packs/InspectionPackageContractsV2.swift
FieldEvidenceApp/Domain/Packs/InspectionPackageRegistryV2.swift
FieldEvidenceApp/Infrastructure/Packs/BundledInspectionPackageRegistryV2.swift
FieldEvidenceApp/Domain/InspectionKernel/InspectionPackageReleaseV1.swift
FieldEvidenceApp/Domain/InspectionKernel/PackageReleaseBindingV1.swift
FieldEvidenceApp/Domain/Models/WorkflowModels.swift
FieldEvidenceApp/Domain/Drafts/FieldDraftContractsV1.swift
FieldEvidenceApp/Domain/Models/FieldDraftPersistenceModelsV1.swift
FieldEvidenceApp/Application/Drafts/FieldDraftCoordinatorV1.swift
FieldEvidenceApp/Infrastructure/Drafts/FieldDraftLifecycleAdapterV1.swift
FieldEvidenceApp/Domain/Packs/PackageEvolutionContractsV1.swift
FieldEvidenceApp/Domain/Models/PackageEvolutionPersistenceModelsV1.swift
FieldEvidenceApp/Application/Packs/PackageEvolutionCoordinatorV1.swift
FieldEvidenceApp/Infrastructure/Packs/PackageEvolutionLifecycleAdapterV1.swift
FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift
FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift
FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift
FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift
FieldEvidenceAppTests/V9_06DeletionRightsTests.swift
FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift
FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift
FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift
FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift
FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift
FieldEvidenceAppTests/V9_19LocalSearchTests.swift
FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift
FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift
FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift
FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift
FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift
FieldEvidenceAppTests/S6_2BackupExportTests.swift
FieldEvidenceAppTests/S6_3BackupValidationTests.swift
FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift
FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift
FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift
FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift
FieldEvidenceAppTests/V9_11ObservationTemporalSemanticsTests.swift
FieldEvidenceAppTests/V9_13TypedResponseTests.swift
FieldEvidenceAppTests/V9_20KernelConformanceTests.swift
FieldEvidenceAppTests/V9_31IntegrationEventProjectionTests.swift
FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift
FieldEvidenceAppTests/S1PackTokenTests.swift
FieldEvidenceAppTests/S3_1DraftSchemaTests.swift
FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift
FieldEvidenceAppTests/S6_1DeletionGraphTests.swift
FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift
FieldEvidenceAppTests/S8_1SecondPackZeroForkTests.swift
FieldEvidenceAppTests/V9_11PackRegistryTests.swift
FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift
FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift
FieldEvidenceAppTests/V9_32PackageEvolutionTests.swift
FieldEvidenceAppTests/Fixtures/V21/PackageEvolution/V21P03C18PackageEvolutionCorpusV1.json
""")
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Packs/ClientCapabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/ClientCapabilityPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Packs/ClientCapabilityCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/ClientCapabilityLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_35ClientCapabilityPackageLifecycleTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/PackageLifecycle/V21P03C21ClientCapabilityPackageLifecycleCorpusV1.json",
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

PRIOR_FENCE_OVERLAP_COUNT = 1135
PRIOR_FENCE_PROOF = {
    "fenceCount": 0,
    "priorOwnedPathCount": 0,
    "overlapCount": PRIOR_FENCE_OVERLAP_COUNT,
    "authorizedOverlapCount": PRIOR_FENCE_OVERLAP_COUNT,
    "unauthorizedOverlapCount": 0,
    "overlapRowsAreAggregate": True,
}
PRIOR_FENCE_OVERLAPS: tuple[dict[str, Any], ...] = ()

CONTRACT_NAMES = (
    "ClientCapabilityProfileV1",
    "ClientCapabilityAdmissionDecisionV1",
    "PackageLifecyclePolicyV1",
    "PackageLifecycleDispositionV1",
)
PERSISTENT_SCHEMA_VERSION = 20
RECORDS_SCHEMA_VERSION = 19
PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT = 81
DURABLE_FAMILY_COUNT = 4
CAPABILITY_RANGES = ("SCHEMAS", "CONTRACTS", "PACKAGES", "MEDIA", "CANONICALIZATION", "DIGESTS")
ADMISSIONS = ("READ_WRITE", "READ_ONLY", "MIGRATION_REQUIRED", "QUARANTINE", "REJECT")
OPERATIONS = ("START", "RESUME", "FINALIZE", "AMEND", "VIEW", "EXPORT", "RESTORE", "REPLAY", "UPGRADE_DRAFT")
LIFECYCLE_STATES = ("ACTIVE", "DEPRECATED", "WITHDRAWN", "QUARANTINED", "SUPERSEDED")
DISPOSITIONS = ("ALLOWED", "BLOCKED", "MIGRATION_REQUIRED", "QUARANTINED", "REJECTED")
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C21G01CapabilityAdmissionAndImmutableReleaseLifecycle",
    "testV23P03C21A01ClosedAdmissionAndOperationMatrixIsDeterministic",
    "testV23P03C21H01UnknownCapabilityAndForbiddenRemoteStateFailClosed",
    "testV23P03C21I01CapabilityAdmissionAndPackageMutationIsAtomicAndRecoverable",
    "testV23P03C21R01V20BackupRestoreDeleteEraseReplayAndWithdrawalPreserveHistory",
)
FORBIDDEN_CLAIMS = (
    "REMOTE_CLIENT_REGISTRY", "ACCOUNT_USER_TENANT_ENDPOINT", "PROVIDER_CREDENTIAL",
    "HEARTBEAT_UPLOAD_ACKNOWLEDGEMENT", "UNKNOWN_CLIENT_OPTIMISTIC_WRITE", "MUTABLE_RELEASE",
    "ANDROID_WEB_BACKEND_SAAS_CLOUD", "SECOND_STORE_OR_WRITER", "NETWORK_OR_PROVIDER_STATE",
)

SOURCE_CONTRACT_TOKENS = (
    CARD, "V21-P03-C21", *CONTRACT_NAMES, *ADMISSIONS, *OPERATIONS,
    "immutable", "withdrawal", "history", "platform-neutral", "manual-only",
)

REQUIRED_BEHAVIORS = (
    {
        "id": "CAPABILITY_RANGES",
        "contract": "ClientCapabilityProfileV1",
        "requirement": "A platform-neutral manifest declares bounded semantic capability ranges for schemas, contracts, packages, media, canonicalization, and digests without device or remote identity.",
        "evidence": "C21-S01",
    },
    {
        "id": "CLOSED_ADMISSION_MATRIX",
        "contract": "ClientCapabilityAdmissionDecisionV1",
        "requirement": "Admission is closed to READ_WRITE, READ_ONLY, MIGRATION_REQUIRED, QUARANTINE, and REJECT, and unknown capability, version, workspace, site, or digest input fails closed.",
        "evidence": "C21-S02",
    },
    {
        "id": "CLOSED_OPERATION_MATRIX",
        "contract": "PackageLifecyclePolicyV1",
        "requirement": "START, RESUME, FINALIZE, AMEND, VIEW, EXPORT, RESTORE, REPLAY, and UPGRADE_DRAFT have explicit deterministic dispositions.",
        "evidence": "C21-S03",
    },
    {
        "id": "IMMUTABLE_RELEASES",
        "contract": "PackageLifecycleDispositionV1",
        "requirement": "Versioned package releases are immutable; amendment creates a new version and never silently replaces a finalized release.",
        "evidence": "C21-S04",
    },
    {
        "id": "WITHDRAWAL_HISTORY",
        "contract": "PackageLifecycleDispositionV1",
        "requirement": "Withdrawal blocks new work while finalized history remains readable, restorable, replayable, and exportable.",
        "evidence": "C21-S05",
    },
    {
        "id": "V20_LIFECYCLE",
        "contract": "PERSISTENT_SCHEMA_V20",
        "requirement": "V20 and records19 close migration, backup/restore, import/export, report/search, journal replay, delete/Erase, interruption, recovery, compatibility, and forward-fix behavior for four durable families.",
        "evidence": "C21-S06",
    },
    {
        "id": "ATOMIC_CANONICAL_WRITER",
        "contract": "ClientCapabilityAdmissionDecisionV1",
        "requirement": "Capability admission, lifecycle disposition, mutation receipt, and effect commit use the sole canonical writer in one local transaction.",
        "evidence": "C21-S07",
    },
    {
        "id": "STATIC_BOUNDARY",
        "contract": CARD,
        "requirement": "The tooling result is PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, network, cloud, and Phase 10 claims remain false.",
        "evidence": "C21-B01",
    },
)
EVIDENCE_CASES = (
    {"id": "C21-S01", "kind": "GOLDEN", "assertion": "A known capability manifest admits an immutable package release and produces one canonical READ_WRITE decision."},
    {"id": "C21-S02", "kind": "ALTERNATE", "assertion": "READ_ONLY, MIGRATION_REQUIRED, QUARANTINE, and REJECT alternatives retain exact ordered meaning across capability ranges and version boundaries."},
    {"id": "C21-S03", "kind": "OPERATION_MATRIX", "assertion": "All nine package operations have explicit closed dispositions and no implicit operation is admitted."},
    {"id": "C21-S04", "kind": "IMMUTABILITY", "assertion": "Finalize and amend preserve immutable release bytes, revisions, predecessor identity, and receipt digests."},
    {"id": "C21-S05", "kind": "WITHDRAWAL", "assertion": "Withdrawal denies new START/RESUME work without hiding or mutating finalized history."},
    {"id": "C21-S06", "kind": "LIFECYCLE", "assertion": "V20/records19 migration, backup/restore, import/export, report/search, replay, delete, Erase, interruption, and recovery close four durable families."},
    {"id": "C21-H01", "kind": "HOSTILE", "assertion": "Unknown client, forged capability, stale revision, cross-workspace/site input, remote identity, provider, network, mutable release, and second writer fail closed."},
    {"id": "C21-I01", "kind": "INTERRUPTION", "assertion": "Interruption before or after admission/disposition leaves either no canonical effect or one exact retryable effect with no duplicate receipt."},
    {"id": "C21-R01", "kind": "RECOVERY", "assertion": "Recovery, replay, restore, clone, fork, and forward-fix preserve exact old-or-new immutable package artifacts and readable history."},
    {"id": "C21-F01", "kind": "PATH_FENCE", "assertion": "The hydrated fence is exactly 121 paths: 107 existing and 14 new, with zero S10 overlap and 1,135 authorized prior-fence overlaps."},
    {"id": "C21-B01", "kind": "STATIC_BOUNDARY", "assertion": "All activation and release flags remain false pending later evidence and accepted S10.6 reconciliation."},
)

SOURCE_PROJECTION = {
    "registerRows": [
        "| 58 | <a id=\u0060v23-p03-c21-register\u0060></a>[\u0060V23-P03-C21\u0060](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c21) | Portable client capability admission and package lifecycle disposition | \u0060IMPLEMENT_NOW\u0060 | \u0060NOT_STARTED\u0060 | \u0060V23-P03-C18\u0060, \u0060V23-P03-C19\u0060, \u0060V23-P03-C20\u0060 | \u0060REFINED_WITHOUT_LOSS\u0060 |",
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
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C21).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C22", "V23-P03-C43", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
    "optionalCapabilityProviders": ["NONE"],
    "reservedLegacyOwnerReconciliationDebtCount": 0,
    "reservedLegacyOwnerReconciliationDebtPaths": [],
    "reservedLegacyRawWriteViolationCount": 0,
    "reservedLegacyRawWriteViolationPaths": [],
    "provisionalZeroViolationClosureClaimed": False,
    "directGraphDigest": "DERIVED_FROM_C21_PREREQUISITE_SET",
    "selectorManifestDigest": "DERIVED_FROM_C21_TEST_METHODS",
    "relationManifestDigest": "DERIVED_FROM_C21_CAPABILITY_AND_PACKAGE_RELATIONS",
    "dependencyDispositionDigest": "DERIVED_FROM_C21_ADMISSION_MATRIX",
    "impactManifestDigest": "DERIVED_FROM_C21_BRAND_IMPACT_MANIFEST",
}

DIRECT_PREREQUISITE_EVIDENCE = {
    "schema": "ProvisionalExecutionPrerequisiteSetReceiptV1",
    "schemaVersion": 1,
    "successorCardID": CARD,
    "successorAttemptID": 1,
    "ordinaryDirectEdgeCount": 3,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [
        {
            "cardID": "V23-P03-C18", "attemptID": 1,
            "candidateHead": "83053def0ab93fd24b1d42fffc21480e5f1c3ba1",
            "candidateTree": "3d785ae416444c9c737f0d0644a40666591b7a39",
            "checkpointDigest": "a7f8c4293c3a555bab80f78da55f28c5f3a6831d4abfdc8e4fd1e07605fa075b",
            "verificationReceiptDigest": "92924bedcb47a066e1dbf1f5ea014332f69de8f8f81fd846a611278bbaaf623b",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C18_HEAD",
        },
        {
            "cardID": "V23-P03-C19", "attemptID": 1,
            "candidateHead": "af134ec68a2708bda01b5680c535651952993055",
            "candidateTree": "12bb97d262c282b0f01c41193e61361b81556e9e",
            "checkpointDigest": "029757411a5cfd83e521a4915955af92c80769d3b3eeb3d1b3a5e7dbc9985ed6",
            "verificationReceiptDigest": "e051d867948c8886397047c605548288d86b515a3275a14bd4170e95398a39f3",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C19_HEAD",
        },
        {
            "cardID": "V23-P03-C20", "attemptID": 1,
            "candidateHead": "25d0c788f4faa82fca3a88518fbccb45508a0428",
            "candidateTree": "06844bf5e7096d3e4198355c5b8c10a133d5d88f",
            "checkpointDigest": "185ded43f2c9b2318dfb58edd19cd832dacaa33bc13d2ad152f5224c37d61c03",
            "verificationReceiptDigest": "0e983db6c371fbde7c145060a134ae135456c019025c0f9ce64797fb064331fb",
            "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C20_HEAD",
        },
    ],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV20"],
    "atomicAuthorityPolicy": "CAPABILITY_MANIFEST_ADMISSION_DECISION_PACKAGE_LIFECYCLE_DISPOSITION_AND_MUTATION_RECEIPT_EFFECT_COMMIT_IN_ONE_SWIFTDATA_TRANSACTION_USING_THE_SOLE_CANONICAL_WRITER",
    "capabilityPolicy": "PLATFORM_NEUTRAL_SEMANTIC_CAPABILITY_RANGES_FOR_SCHEMAS_CONTRACTS_PACKAGES_MEDIA_CANONICALIZATION_AND_DIGESTS_WITH_CLOSED_READ_WRITE_READ_ONLY_MIGRATION_REQUIRED_QUARANTINE_AND_REJECT_OUTCOMES_NO_DEVICE_OR_REMOTE_IDENTITY",
    "admissionPolicy": "CLOSED_ADMISSION_MATRIX_READ_WRITE_READ_ONLY_MIGRATION_REQUIRED_QUARANTINE_REJECT_WITH_UNKNOWN_STALE_CROSS_WORKSPACE_CROSS_SITE_AND_DIGEST_DIVERGENCE_FAIL_CLOSED",
    "operationPolicy": "CLOSED_OPERATION_MATRIX_START_RESUME_FINALIZE_AMEND_VIEW_EXPORT_RESTORE_REPLAY_UPGRADE_DRAFT",
    "packagePolicy": "IMMUTABLE_VERSIONED_PACKAGE_RELEASES_WITH_WITHDRAWAL_BLOCKING_NEW_WORK_ONLY_AND_AMENDMENT_CREATING_A_NEW_VERSION",
    "historyPolicy": "FINALIZED_HISTORY_REMAINS_READABLE_RESTORABLE_REPLAYABLE_AND_EXPORTABLE_AFTER_WITHDRAWAL_WITHOUT_PACKAGE_BYTE_REWRITE_OR_SILENT_REPLACEMENT",
    "lifecyclePolicy": "V20_EIGHTY_ONE_MODELS_RECORDS19_ZERO_INVENTION_FROM_V19_BACKUP_RESTORE_CLONE_FORK_IMPORT_EXPORT_JOURNAL_REPLAY_SEARCH_REBUILD_DELETE_ERASE_RETENTION_COMPATIBILITY_AND_FORWARD_FIX_CLOSED",
    "forbiddenPolicy": "NO_REMOTE_CLIENT_REGISTRY_ACCOUNT_USER_TENANT_ENDPOINT_PROVIDER_CREDENTIAL_HEARTBEAT_UPLOAD_ACKNOWLEDGEMENT_UNKNOWN_CLIENT_OPTIMISTIC_WRITE_MUTABLE_RELEASE_ANDROID_WEB_BACKEND_SAAS_CLOUD_OR_SECOND_WRITER",
    "s10Policy": "EXACT_ONE_HUNDRED_TWENTY_ONE_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP_AND_ALL_VISIBLE_UI_DEFERRED",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

CORPUS: dict[str, Any] = {
    "schema": "V21P03C21ClientCapabilityPackageLifecycleCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION,
    "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
    "persistentClientCapabilityKindCount": DURABLE_FAMILY_COUNT,
    "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT,
    "durableFamilyCount": DURABLE_FAMILY_COUNT,
    "migrationInventedClientCapabilityCount": 0,
    "requiredContractNames": list(CONTRACT_NAMES),
    "capabilityRanges": list(CAPABILITY_RANGES),
    "admissions": list(ADMISSIONS),
    "operations": list(OPERATIONS),
    "lifecycleStates": list(LIFECYCLE_STATES),
    "dispositions": list(DISPOSITIONS),
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "evidenceCases": list(EVIDENCE_CASES),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "persistence": {
        "schemaRelease": "CLIENT_CAPABILITY_AND_PACKAGE_LIFECYCLE_V1",
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
        "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V20_WRITE",
        "forwardFix": "RETAIN_IMMUTABLE_RELEASES_AND_RECEIPTS_DENY_UNSAFE_ADMISSION_AND_APPEND_VERSIONED_DISPOSITION_NEVER_REWRITE_HISTORY",
    },
    "goldenCases": [
        {"id": "known-capability-finalize", "admission": "READ_WRITE", "operation": "FINALIZE", "state": "ACTIVE", "immutableRelease": True},
    ],
    "alternateCases": [
        {"id": "legacy-read-only", "admission": "READ_ONLY", "operation": "VIEW", "state": "WITHDRAWN", "historyReadable": True},
        {"id": "migration-required", "admission": "MIGRATION_REQUIRED", "operation": "UPGRADE_DRAFT", "state": "DEPRECATED", "newVersion": True},
        {"id": "quarantine-replay", "admission": "QUARANTINE", "operation": "REPLAY", "state": "QUARANTINED", "newWork": False},
    ],
    "hostileCases": [
        {"id": case_id, "expectedDisposition": "FAIL_CLOSED_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "unknown-client-capability", "forged-capability-digest", "stale-revision", "cross-workspace-reference",
            "cross-site-reference", "unknown-admission", "unknown-operation", "mutable-finalized-release",
            "silent-replacement", "withdrawal-start", "remote-client-registry", "account-or-tenant-state",
            "provider-or-credential", "network-or-heartbeat", "upload-or-acknowledgement", "second-store-or-writer",
        )
    ],
    "interruptionCases": [
        {"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PARTIAL_CANONICAL_SUCCESS"}
        for case_id in (
            "crash-before-admission", "crash-after-admission-before-disposition", "crash-after-disposition-before-receipt",
            "start-interruption", "resume-interruption", "finalize-interruption", "amend-interruption",
            "backup-interruption", "restore-interruption", "delete-erase-interruption", "replay-interruption",
        )
    ],
    "recoveryCases": [
        {"id": case_id, "expectedDisposition": "EXACT_OLD_OR_NEW_IMMUTABLE_PACKAGE_ARTIFACTS_NO_DUPLICATE_OR_REWRITE"}
        for case_id in (
            "recover-draft", "recover-finalized-release", "withdraw-and-view-history", "restore-and-replay",
            "clone-and-fork", "import-export-roundtrip", "search-rebuild", "journal-replay-from-zero", "forward-fix-after-activation",
        )
    ],
    "claims": {
        claim: False
        for claim in (
            "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit",
            "remoteClientRegistry", "accountOrCloudState", "providerState", "network", "secondStore", "secondWriter",
            "android", "web", "backend", "mutableRelease", "unknownClientOptimisticWrite", "phase10PollingDuringParallelExecution",
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
        if subprocess.run(["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{path}"], capture_output=True).returncode == 0
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
            shapes = {json.dumps(_schema_for_value(item), sort_keys=True): _schema_for_value(item) for item in value}
            result["items"] = next(iter(shapes.values())) if len(shapes) == 1 else {"anyOf": [shapes[key] for key in sorted(shapes)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "properties": {key: _schema_for_value(value[key]) for key in sorted(value)},
            "required": sorted(value),
        }
    raise TypeError(type(value))


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/client-capability-package-lifecycle.schema.json",
        "title": "V23 P03 C21 Client Capability and Package Lifecycle Corpus",
    })
    return document


def _flags() -> dict[str, bool]:
    return {
        "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False,
        "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False,
        "acceptanceCredit": False, "releaseReadiness": False, "phase10PollingDuringParallelExecution": False,
    }


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
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "directPrerequisiteCards": ["V23-P03-C18", "V23-P03-C19", "V23-P03-C20"], "nextCard": "V23-P03-C22",
        "sourceDossierSHA256": DOSSIER_SHA256, "sourceDossierUTF8Length": DOSSIER_UTF8_LENGTH,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256, "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    }


def _sealed(body: dict[str, Any], field: str = "artifactDigest") -> dict[str, Any]:
    result = dict(body)
    result[field] = sha256_bytes(pretty(body))
    return result


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    required = {
        "contractNames": list(CONTRACT_NAMES), "capabilityRanges": list(CAPABILITY_RANGES),
        "admissions": list(ADMISSIONS), "operations": list(OPERATIONS), "lifecycleStates": list(LIFECYCLE_STATES),
        "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION, "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
        "persistentKindLifecycleModelCount": PERSISTENT_KIND_LIFECYCLE_MODEL_COUNT, "durableFamilyCount": DURABLE_FAMILY_COUNT,
        "immutableVersionedReleases": True, "withdrawalBlocksNewWork": True, "withdrawalPreservesHistory": True,
        "fiveSelectors": list(TEST_METHODS), "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    }
    body = {
        "artifact": "V23P03C21ClientCapabilityPackageLifecycleContractV1",
        "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "title": TITLE, "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "requiredSemantics": required, "semanticScope": SEMANTIC_SCOPE,
        "persistenceBoundary": CORPUS["persistence"], "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "evidenceIDs": list(EVIDENCE_IDS), "testSelectors": list(TEST_METHODS),
        "schemaArtifact": schema_row, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    required = contract["requiredSemantics"]
    body = {
        "artifact": "V23P03C21ClientCapabilityPackageLifecycleEvidenceReceiptV1",
        "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "authority": _authority(), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows,
        "requiredSemanticsDigest": sha256_value(required), "requiredSemantics": required,
        "evidenceCases": list(EVIDENCE_CASES), "deterministicEvidenceIDs": list(EVIDENCE_IDS),
        "testSelectors": list(TEST_METHODS), "schemaArtifact": schema_row,
        "staticBoundary": "NO_NATIVE_HOSTED_ADOPTION_ACCEPTANCE_RELEASE_NETWORK_CLOUD_OR_PHASE10_CLAIM",
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    }
    return _sealed(body)


def brand_document(contract: dict[str, Any]) -> dict[str, Any]:
    body = {
        "artifact": "V23P03C21ClientCapabilityPackageLifecycleBrandImpactManifestV1",
        "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY",
        "brandSurfaceDelta": True, "uiSurfaceDelta": False,
        "impact": "PACKAGE_ADMISSION_AND_WITHDRAWAL_STATE_REMAINS_LOCAL_MANUAL_AND_ACCESSIBLE_WITH_NO_NEW_S10_UI_SURFACE",
        "preserved": ["immutable-finalized-history", "existing-design-tokens", "existing-accessibility-contracts", "S10-reserved-brand-assets"],
        "deferred": ["native-build", "hosted-CI", "adoption", "acceptance", "release", "Phase10"],
        "pathFenceCount": len(PATH_FENCE), "s10FenceOverlapPaths": [],
        "authorityContextDigest": CONTEXT_DIGEST, "authorityFenceDigest": FENCE_DIGEST,
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
        "contractDigest": contract["artifactDigest"],
    }
    return _sealed(body)


def _manifest_row(root: Path, relative: str, rendered: dict[str, bytes]) -> dict[str, Any]:
    path = root / relative
    if relative in rendered:
        raw = rendered[relative]
        return {"path": relative, "state": "GENERATED", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if path.is_file():
        raw = path.read_bytes()
        return {"path": relative, "state": "WORKTREE", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    if relative in EXISTING_PATHS:
        raw = _git_blob(root, relative)
        return {"path": relative, "state": "BASE_HEAD", "bytes": len(raw), "sha256": sha256_bytes(raw)}
    return {"path": relative, "state": "MISSING_NEW_PATH", "bytes": 0, "sha256": sha256_bytes(b"")}


def all_outputs(root: Path) -> dict[str, bytes]:
    if len(EXISTING_PATHS) != 107 or len(NEW_PATHS) != 14 or len(PATH_FENCE) != 121 or len(set(PATH_FENCE)) != 121:
        raise ValueError("C21 path fence constants are not 121=107+14 unique paths")
    source_rows = source_artifacts(root)
    authority_rows = authority_artifacts(root)
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract = contract_document(root, schema_row)
    contract_raw = pretty(contract)
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract))
    evidence = json.loads(evidence_raw)
    brand_raw = pretty(brand_document(contract))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "artifact": "V23P03C21ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(),
        "baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS),
        "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows,
        "artifacts": rows, "artifactSetDigest": sha256_value(rows), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "persistenceBoundary": CORPUS["persistence"],
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [],
        "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
        "evidenceDigest": evidence["artifactDigest"], "testSelectors": list(TEST_METHODS),
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


def assert_corpus() -> None:
    if CORPUS["requiredContractNames"] != list(CONTRACT_NAMES):
        raise ValueError("C21 contract family set differs")
    if CORPUS["admissions"] != list(ADMISSIONS) or len(ADMISSIONS) != 5:
        raise ValueError("C21 admission set differs")
    if CORPUS["operations"] != list(OPERATIONS) or len(OPERATIONS) != 9:
        raise ValueError("C21 operation set differs")
    if CORPUS["persistentSchemaVersion"] != 20 or CORPUS["recordsSchemaVersion"] != 19:
        raise ValueError("C21 persistence versions differ")
    if CORPUS["persistentKindLifecycleModelCount"] != 81 or CORPUS["durableFamilyCount"] != 4:
        raise ValueError("C21 model/family counts differ")
    if CORPUS["persistence"]["secondStore"] or CORPUS["persistence"]["secondWriter"]:
        raise ValueError("C21 second store/writer is prohibited")


assert_corpus()
