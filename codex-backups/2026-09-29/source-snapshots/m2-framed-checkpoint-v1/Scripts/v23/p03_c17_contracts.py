#!/usr/bin/env python3
"""Deterministic static contract corpus and evidence builders for V23-P03-C17.

This module records the hydrated authority and inherited semantic contract for
provider-neutral integration-event projections.  It is intentionally
static-only: it never reads customer data, creates a canonical store or
writer, contacts a provider, or claims native, hosted, adoption, acceptance,
or release evidence.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C17"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 54
BASE_HEAD = "f2eeb472d70ef0febc3d081e776f12741b7203c3"
BASE_TREE = "63e2b268fdb19f26daa3cb14818280f2bd9a8d5d"
CONTEXT_DIGEST = "043b7a5394e58eb6b1bbca4f4df452a7549e0ee85b656a39305bce048989b684"
FENCE_DIGEST = "b765e7b546e1cf125b8d5d1af881158aa2ad95f7db34b2104a64bdc69e5c12ad"
PREREQUISITE_DIGEST = "9f9007b1076c063b412ffd16acd79ebec0cd1537f2395192b6abd136b8ca89ea"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
# Coordination authority is bound to the exact hydrated coordination head/tree.
COORDINATION_HEAD = "70b61f040744362748e21457831bc27bbb213995"
COORDINATION_TREE = "3d48b1912ced4a3cbbaf41ede9c2ef27f835ceba"
COORDINATION_LEDGER_DIGEST = "c78a83c9ce144c04877ec5a5342d263af691dca85c9fcce9931fe83a319f18b8"
COORDINATION_PROJECTION_DIGEST = "9fb4a203c1cac6d8481861b295c792c8440bf631577baabd73920431299a7036"
COORDINATION_CAS_SEQUENCE = 229
HYDRATION_TRANSITION_SEQUENCE = 229
HYDRATION_TRANSITION_DIGEST = "73122e23c5e4773f1329fbbdfce0a7ba2b2e584e1417c548ac5da740c02df5ba"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "e062909a3b12b7b067add5c2141e9279dcac3ae69430d5aa01e2f3507d80d56f"
REGISTER_ROW_UTF8_LENGTH = 280
DOSSIER_SHA256 = "56f9c6d5667c51c26e5d9dd4bd09229449062f6d041e097ab70efaaa47ed40f8"
DOSSIER_UTF8_LENGTH = 7115
INHERITED_V21_BLOCK_SHA256 = "d0e97f1db3dd7a8f9255c5dd3e8c45a8b42abe2ca17f8e51ad0b50828d8d4d8a"
INHERITED_V21_BLOCK_UTF8_LENGTH = 9106

SCHEMA_PATH = "Scripts/v23/integration-event-projection.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C17IntegrationEventProjectionContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C17IntegrationEventProjectionEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C17BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C17-tooling-manifest.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c17_contracts.py",
    "Scripts/v23/generate_p03_c17_contracts.py",
    "Scripts/v23/verify_p03_c17_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

# The exact 26 BASE_HEAD paths in the hydrated C17 fence.
EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)

# Four C17 production/test paths are hydrated alongside the tooling.  The
# tooling lane owns only the eight paths in TOOL_PATHS; these remain explicit
# fence evidence and are not generated by this module.
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceAppTests/V9_31IntegrationEventProjectionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Integration/V21P03C17IntegrationEventProjectionCorpusV1.json",
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

# Compact rows preserve the sealed authorized total without repeating every
# path-level edge.  The exact edge set remains bound to FENCE_DIGEST.
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
    {"cardID": "V23-P03-C12", "fenceDigest": "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", "disposition": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED", "overlapCount": 28},
    {"cardID": "V23-P03-C16", "fenceDigest": "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", "disposition": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED", "overlapCount": 6},
    {"cardID": "V23-P03-C35", "fenceDigest": "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", "disposition": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED", "overlapCount": 27},
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 53,
    "priorOwnedPathCount": 700,
    "overlapCount": 269,
    "authorizedOverlapCount": 269,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = (
    "IntegrationEventLimitsV1",
    "IntegrationEventContractDefinitionV1",
    "IntegrationContractRegistryV1",
    "IntegrationEventOrderV1",
    "IntegrationEventPayloadV1",
    "IntegrationEventV1",
    "ProjectionCheckpointV1",
    "IntegrationProjectionSchemaV1",
    "IntegrationEventValidationV1",
)
VISIBILITY_CLASSES = ("PUBLIC_SAFE", "WORKSPACE_INTERNAL", "SENSITIVE_REDACTED")
SENSITIVITY_CLASSES = ("PUBLIC_METADATA", "WORKSPACE_DATA", "SENSITIVE_WORKSPACE_DATA")
REDACTION_MODES = ("NOT_REQUIRED", "IDENTIFIERS_ONLY")
EVENT_KINDS = ("ADDED", "UPDATED", "ENDED", "SUPERSEDED")
CHECKPOINT_STATES = ("EMPTY", "ADVANCED", "STALE", "RECOVERY_REQUIRED", "REBUILT")
LIFECYCLE_MODES = ("DERIVED_DROP_AND_REBUILD",)
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V1_VERSIONED_IDENTITY",
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
    "ACCOUNTS_AUTHENTICATION_OR_COMPANY_MEMBERSHIP",
    "TENANT_AUTHORIZATION_OR_REMOTE_CONFLICT_UI",
    "REMOTE_SYNC_TRANSPORT_PROVIDER_SDK_OR_HOSTED_SERVICE",
    "PROVIDER_OUTBOX_INBOX_DELIVERY_OR_CREDENTIAL_MODEL",
    "FULL_CMMS_WORK_ORDER_INVENTORY_PURCHASING_OR_INVOICING",
    "PAYROLL_ROUTE_OPTIMIZATION_OR_GENERIC_WORKFLOW_BUILDER",
    "AI_DIAGNOSIS_COMPLIANCE_DECISION_OR_OPAQUE_SCORE",
    "CAD_LIDAR_PUBLIC_PORTAL_ANDROID_OR_WEB_CLIENT",
    "REMOTE_EMAIL_BILLING_ANALYTICS_OR_TELEMETRY",
    "UNBOUNDED_MEDIA_EXECUTABLE_WORKFLOW_OR_GENERIC_EAV",
    "SECOND_SOURCE_OF_TRUTH_STORE_WRITER_OR_CANONICAL_PROJECTION",
    "LEGAL_REGULATORY_TAMPERPROOF_OR_NONREPUDIATION_CLAIM",
    "SIGNING_TESTFLIGHT_APP_STORE_OR_DEPLOYMENT",
    "NATIVE_IPAD_SURFACE_OR_PUBLIC_METADATA",
    "S10_RELEASE_OR_BRAND_APPROVAL",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C17G01AcceptedReceiptsProjectStableOrderedIDsAndDigests",
    "testV23P03C17A01LegacyCompatibleConsumerReplaysFromZeroAndArbitraryBoundaries",
    "testV23P03C17H01UnknownVersionDivergentSameIDSensitiveCanaryAndForgedCheckpointFailClosed",
    "testV23P03C17I01EffectBeforeCheckpointCrashRetriesWithoutProviderDeliveryState",
    "testV23P03C17R01DropAndRebuildReproducesExactConsumerResultAndLeavesCanonicalReceiptsUntouched",
)
SOURCE_CONTRACT_TOKENS = (
    CARD,
    "V21-P03-C17",
    "IntegrationEventV1",
    "IntegrationContractRegistryV1",
    "ProjectionCheckpointV1",
    "deterministic enumeration",
    "checkpoint recovery",
)
REQUIRED_BEHAVIORS = (
    {"id": "EVENT_PROJECTION", "contract": "IntegrationEventV1", "requirement": "Accepted mutation receipts and journal entries project to immutable versioned events with stable source identity, revision, subject, visibility, timestamps, bounded payload, and canonical digests.", "evidence": "C17-S01"},
    {"id": "CONTRACT_REGISTRY", "contract": "IntegrationContractRegistryV1", "requirement": "The registry declares event kind/version, source entity, sensitivity, replayability, ordering, lifecycle, and minimum compatible consumer version with canonical registry digest.", "evidence": "C17-S02"},
    {"id": "CONSUMER_CHECKPOINT", "contract": "ProjectionCheckpointV1", "requirement": "Per-consumer checkpoints are disposable operational state bound to workspace and registry identity; stale or cross-workspace checkpoints fail closed.", "evidence": "C17-S03"},
    {"id": "DETERMINISTIC_ORDER", "contract": "IntegrationEventOrderV1", "requirement": "Replay order is accepted workspace revision, receipt identity, local sequence, and payload ordinal; replay from zero and arbitrary boundaries converge.", "evidence": "C17-S04"},
    {"id": "IDEMPOTENT_CONSUMER", "contract": "IntegrationEventValidationV1", "requirement": "The single local conformance consumer applies duplicate delivery once and advances only after a valid event effect.", "evidence": "C17-S05"},
    {"id": "REDACTION_BOUNDARY", "contract": "IntegrationEventRedactionV1", "requirement": "Sensitive inputs use identifiers-only redaction and internal-only material never crosses the declared visibility boundary.", "evidence": "C17-S06"},
    {"id": "UNKNOWN_VERSION_FAILURE", "contract": "IntegrationContractRegistryV1", "requirement": "Unknown event kinds or payload versions fail closed without advancing a checkpoint or changing canonical truth.", "evidence": "C17-S07"},
    {"id": "DERIVED_LIFECYCLE", "contract": "IntegrationProjectionSchemaV1", "requirement": "Projection and checkpoint caches are derived-only, disposable, and rebuilt from accepted receipts and journal truth with DROP_AND_REBUILD downgrade.", "evidence": "C17-L01"},
    {"id": "PROVIDER_ABSENCE", "contract": "V23-P03-C17", "requirement": "Static and runtime evidence keep transport, webhook, outbox, inbox, provider, credential, acknowledgement, and retry rows absent.", "evidence": "C17-B01"},
    {"id": "STATIC_BOUNDARY", "contract": "V23-P03-C17", "requirement": "This lane is PASS_STATIC_PROVISIONAL and all native, hosted, adoption, acceptance, and release flags remain false.", "evidence": "C17-B02"},
)
EVIDENCE_CASES = (
    {"id": "C17-S01", "kind": "EVENT_IDENTITY", "assertion": "A golden accepted receipt stream produces stable event IDs, event digests, source receipt identity, ordered subjects, and bounded payloads."},
    {"id": "C17-S02", "kind": "REGISTRY_CLOSURE", "assertion": "Registry definitions close kind/version, sensitivity, replayability, ordering, lifecycle, and compatibility metadata."},
    {"id": "C17-S03", "kind": "CHECKPOINT_BOUNDARY", "assertion": "Zero, older, current, stale, cross-workspace, and forged checkpoints are explicit and validated."},
    {"id": "C17-S04", "kind": "REPLAY_CONVERGENCE", "assertion": "Replay from zero or arbitrary checkpoint boundaries produces identical ordered event IDs and digests."},
    {"id": "C17-S05", "kind": "CONSUMER_IDEMPOTENCY", "assertion": "Duplicate delivery and crash-before/after-checkpoint boundaries have one logical effect and safe resume."},
    {"id": "C17-S06", "kind": "PRIVACY_REDACTION", "assertion": "Sensitive canaries and internal-only material are redacted or rejected without checkpoint advancement."},
    {"id": "C17-L01", "kind": "DROP_REBUILD", "assertion": "Deleting derived events and checkpoints followed by bounded replay restores event and consumer digests without a provider row."},
    {"id": "C17-F01", "kind": "PATH_DIGEST_FENCE", "assertion": "The hydrated fence is exactly 40 paths: 26 existing and 14 new, with zero overlap against the frozen S10 reservation."},
    {"id": "C17-B01", "kind": "STATIC_BOUNDARY", "assertion": "All status flags remain false until accepted S10.6 reconciliation and later card gates."},
)

SOURCE_PROJECTION = {
    "registerRows": ['| 54 | <a id="v23-p03-c17-register"></a>[`V23-P03-C17`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c17) | Provider-neutral IntegrationEventV1 projection and rebuildable consumer checkpoints | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C36` | `EXACT_WITH_GENERATION_REBIND` |'],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "registerRowUTF8Length": REGISTER_ROW_UTF8_LENGTH,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C17).CONTRACTS", *CONTRACT_NAMES, "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C18", "V23-P03-C19", "V23-P03-C20", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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
    "ordinaryDirectEdgeCount": 1,
    "nonreleaseSpecialEdgeApplied": False,
    "canonicalRelationPreserved": True,
    "disposition": "PROVISIONALLY_SATISFIED_FOR_ORDERED_IMPLEMENTATION_AND_STATIC_TEST_ONLY",
    "predecessors": [{
        "cardID": "V23-P03-C36",
        "attemptID": 1,
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "checkpointDigest": "d52ffb771acff2df694d4aaae44a6d53689cb246ba517976f454dc94f0a78725",
        "contextDigest": "4daf6b1a4556c4db876efdce8c9f0681a5e257d7fd352dde6413bdf86b67b6bf",
        "pathFenceDigest": "205df5643f4f73344eb052a36a8271500eceeb131bef4fdb1084f6efc56aa629",
        "verificationReceiptDigest": None,
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AND_ORDERING_AUTHORITY_AT_EXACT_APP_HEAD",
    }],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}

SEMANTIC_SCOPE = {
    "durableOwner": ["IntegrationEventV1", "IntegrationContractRegistryV1", "ProjectionCheckpointV1", "IntegrationProjectionSchemaV1"],
    "eventPolicy": "IMMUTABLE_PROVIDER_NEUTRAL_PROJECTIONS_FROM_ACCEPTED_RECEIPTS_AND_JOURNAL_ENTRIES_WITH_STABLE_KIND_VERSION_WORKSPACE_SOURCE_IDENTITY_REVISION_SUBJECT_VISIBILITY_TIMESTAMPS_BOUNDED_PAYLOAD_AND_CANONICAL_DIGEST",
    "registryPolicy": "REGISTRY_DECLARES_SCHEMA_SENSITIVITY_REPLAYABILITY_ORDERING_LIFECYCLE_AND_MINIMUM_COMPATIBLE_CONSUMER_VERSION_WITH_CANONICAL_DIGEST",
    "checkpointPolicy": "ONE_DISPOSABLE_PER_CONSUMER_WORKSPACE_CHECKPOINT_BOUND_TO_REGISTRY_IDENTITY_AND_DROPPABLE_WITHOUT_CANONICAL_DATA_LOSS",
    "orderingPolicy": "ACCEPTED_WORKSPACE_REVISION_THEN_RECEIPT_IDENTITY_THEN_LOCAL_SEQUENCE_THEN_PAYLOAD_ORDINAL",
    "consumerPolicy": "ONE_LOCAL_CONFORMANCE_CONSUMER_ENUMERATES_DETERMINISTICLY_REDACTS_SENSITIVE_INPUTS_APPLIES_DUPLICATES_IDEMPOTENTLY_AND_FAILS_CLOSED_ON_UNKNOWN_KIND_OR_VERSION",
    "persistencePolicy": "DERIVED_ONLY_INTEGRATIONPROJECTIONSCHEMAV1_NO_CANONICAL_SCHEMA_MIGRATION_NO_PROVIDER_OUTBOX_INBOX_DELIVERY_OR_CREDENTIAL_ROW",
    "recoveryPolicy": "DROP_DERIVED_EVENTS_AND_CHECKPOINTS_THEN_REBUILD_FROM_IMMUTABLE_RECEIPT_AND_JOURNAL_TRUTH_WITH_IDENTICAL_EVENT_AND_CONSUMER_DIGESTS",
    "lifecyclePolicy": "MIGRATION_BACKUP_RESTORE_DELETE_ERASE_EXPORT_REPORT_AND_CANONICAL_RELEASE_BEHAVIORS_ARE_EXPLICITLY_NOT_APPLICABLE_TO_DERIVED_CACHE_AND_MUST_NOT_CREATE_A_SECOND_STORE_OR_WRITER",
    "privacyPolicy": "PUBLIC_SAFE_WORKSPACE_INTERNAL_AND_SENSITIVE_REDACTED_VISIBILITY_CLASSES_ARE_DECLARED_INTERNAL_ONLY_OR_SENSITIVE_CANARIES_NEVER_LEAK",
    "structuralBoundaryPolicy": "C35_REMAINS_THE_SOLE_STRUCTURAL_COMPOSITION_OWNER_C17_EVENTS_DO_NOT_IMPLY_PLACEMENT_CONTAINMENT_OWNERSHIP_AUTHORIZATION_OR_CASCADE_DELETE",
    "activationPolicy": "PROVISIONAL_PRE_S10_NONRESERVED_SCHEMA_CONTRACT_LIFECYCLE_FIXTURE_AND_TEST_IMPLEMENTATION_ONLY_NATIVE_HOSTED_ACCEPTANCE_RELEASE_AND_PHASE10_POLLING_DEFERRED",
}

CORPUS: dict[str, Any] = {
    "schema": "V21P03C17IntegrationEventProjectionCorpusV1",
    "schemaVersion": SCHEMA_VERSION,
    "cardID": CARD,
    "synthetic": True,
    "containsCustomerData": False,
    "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES),
    "visibilityClasses": list(VISIBILITY_CLASSES),
    "sensitivityClasses": list(SENSITIVITY_CLASSES),
    "redactionModes": list(REDACTION_MODES),
    "eventKinds": list(EVENT_KINDS),
    "checkpointStates": list(CHECKPOINT_STATES),
    "lifecycleModes": list(LIFECYCLE_MODES),
    "orderingBasis": "ACCEPTED_WORKSPACE_REVISION_THEN_RECEIPT_IDENTITY_THEN_PAYLOAD_ORDINAL",
    "requiredBehaviors": list(REQUIRED_BEHAVIORS),
    "forbiddenClaims": list(FORBIDDEN_CLAIMS),
    "evidenceCases": list(EVIDENCE_CASES),
    "persistence": {
        "schemaRelease": "IntegrationProjectionSchemaV1",
        "schemaVersion": 1,
        "mode": "DERIVED_ONLY",
        "migrationRequired": False,
        "backupRestoreRequired": False,
        "deleteEraseRequired": False,
        "exportReportRequired": False,
        "canonicalWriter": "V23-P02-C01",
        "canonicalSourceOfTruth": ["MutationReceiptV1", "ChangeJournalContractsV1"],
        "persistedFamilies": [],
        "nonPersistentFamilies": ["IntegrationEventV1", "ProjectionCheckpointV1"],
        "currentProjectionRowCount": 0,
        "providerRows": 0,
        "secondStore": False,
        "secondWriter": False,
        "downgrade": "DROP_AND_REBUILD",
        "forwardFix": "REBUILD_FROM_ACCEPTED_RECEIPTS_AND_JOURNAL",
    },
    "registryDefinitions": [
        {"eventKind": "mutation.accepted", "eventVersion": 1, "source": "MutationReceiptV1", "sensitivity": "WORKSPACE_DATA", "visibility": "WORKSPACE_INTERNAL", "redaction": "NOT_REQUIRED", "replayable": True, "lifecycle": "DERIVED_DROP_AND_REBUILD", "minimumCompatibleConsumerVersion": 1},
        {"eventKind": "subject.sensitive", "eventVersion": 1, "source": "WorkspaceEntityIdentityV1", "sensitivity": "SENSITIVE_WORKSPACE_DATA", "visibility": "SENSITIVE_REDACTED", "redaction": "IDENTIFIERS_ONLY", "replayable": True, "lifecycle": "DERIVED_DROP_AND_REBUILD", "minimumCompatibleConsumerVersion": 1},
    ],
    "acceptedEvents": [
        {"eventID": "event-golden-001", "eventKind": "mutation.accepted", "eventVersion": 1, "sourceReceiptID": "receipt-golden-001", "sourceWorkspaceRevision": 41, "subjectID": "subject-golden-001", "visibility": "WORKSPACE_INTERNAL", "redaction": "NOT_REQUIRED", "order": [41, "replica-a", 7, 0], "payloadBytes": 256, "payloadDigest": "1" * 64, "eventDigest": "2" * 64},
        {"eventID": "event-golden-002", "eventKind": "mutation.accepted", "eventVersion": 1, "sourceReceiptID": "receipt-golden-002", "sourceWorkspaceRevision": 42, "subjectID": "subject-golden-002", "visibility": "WORKSPACE_INTERNAL", "redaction": "NOT_REQUIRED", "order": [42, "replica-a", 8, 0], "payloadBytes": 256, "payloadDigest": "3" * 64, "eventDigest": "4" * 64},
        {"eventID": "event-sensitive-001", "eventKind": "subject.sensitive", "eventVersion": 1, "sourceReceiptID": "receipt-sensitive-001", "sourceWorkspaceRevision": 43, "subjectID": "subject-sensitive-001", "visibility": "SENSITIVE_REDACTED", "redaction": "IDENTIFIERS_ONLY", "order": [43, "replica-a", 9, 0], "payloadBytes": 192, "payloadDigest": "5" * 64, "eventDigest": "6" * 64},
    ],
    "checkpoints": [
        {"id": "checkpoint-zero", "state": "EMPTY", "consumedEventCount": 0, "lastEventID": None, "lastEventDigest": None, "registryDigest": "7" * 64, "consumerStateDigest": "8" * 64},
        {"id": "checkpoint-older", "state": "ADVANCED", "consumedEventCount": 1, "lastEventID": "event-golden-001", "lastEventDigest": "2" * 64, "registryDigest": "7" * 64, "consumerStateDigest": "9" * 64},
        {"id": "checkpoint-rebuilt", "state": "REBUILT", "consumedEventCount": 3, "lastEventID": "event-sensitive-001", "lastEventDigest": "6" * 64, "registryDigest": "7" * 64, "consumerStateDigest": "a" * 64},
    ],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED_NO_CHECKPOINT_ADVANCE"} for case_id in (
        "unknown-event-kind", "unknown-payload-version", "divergent-same-id-bytes", "forged-event-digest", "forged-checkpoint-digest",
        "cross-workspace-checkpoint", "stale-registry-checkpoint", "internal-only-canary", "sensitive-canary-without-redaction",
        "noncanonical-order", "oversized-payload", "duplicate-registry-definition", "provider-outbox-row", "second-writer-or-store",
    )],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "RETRY_IDEMPOTENT_NO_PROVIDER_STATE"} for case_id in (
        "crash-before-event-effect", "crash-after-event-effect-before-checkpoint", "crash-after-checkpoint-write",
        "checkpoint-store-interruption", "projection-cache-interruption", "replay-interruption",
    )],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "DROP_AND_REBUILD_IDENTICAL_DIGESTS"} for case_id in (
        "delete-event-cache", "delete-all-checkpoints", "relaunch-from-zero", "replay-arbitrary-boundary",
        "registry-compatible-consumer-upgrade", "protected-data-relaunch",
    )],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
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
    rows: list[dict[str, Any]] = []
    for relative in SOURCE_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        rows.append({"path": relative, "source": "BASE_HEAD_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return rows


def authority_artifacts(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for relative in AUTHORITY_REFERENCE_PATHS:
        raw = _git_blob(root, relative)
        rows.append({"path": relative, "source": "BASE_HEAD_AUTHORITY_BLOB", "bytes": len(raw), "sha256": sha256_bytes(raw)})
    return rows


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
        schemas = {_schema_for_value(item).__repr__(): _schema_for_value(item) for item in value}
        if schemas:
            result["items"] = next(iter(schemas.values())) if len(schemas) == 1 else {"anyOf": [schemas[key] for key in sorted(schemas)]}
        if all(isinstance(item, str) for item in value):
            result["uniqueItems"] = True
        return result
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "properties": {key: _schema_for_value(value[key]) for key in sorted(value)}, "required": sorted(value)}
    raise TypeError(f"unsupported schema value: {type(value)!r}")


def schema_document() -> dict[str, Any]:
    document = _schema_for_value(CORPUS)
    document.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/v23/integration-event-projection.schema.json",
        "title": "V23 P03 C17 Integration Event Projection Corpus",
    })
    return document


def _flags() -> dict[str, bool]:
    return {
        "native": False, "hosted": False, "adoption": False, "acceptance": False, "release": False,
        "nativeAcceptance": False, "hostedAcceptance": False, "adoptionEvidence": False,
        "acceptanceCredit": False, "releaseReadiness": False,
    }


def _authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": REGISTER_ORDINAL,
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "contextDigest": CONTEXT_DIGEST,
        "fenceDigest": FENCE_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "hydrationTransitionSequence": HYDRATION_TRANSITION_SEQUENCE,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C36"],
        "nextCard": "V23-P03-C18",
        "allowedPathCount": len(PATH_FENCE),
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "persistentChangeMode": "DERIVED_ONLY",
        "persistentContractSchema": "IntegrationProjectionSchemaV1",
        "recordSchemaVersion": 1,
        "schemaBehaviorDelta": False,
        "migrationBehaviorDelta": False,
        "backupBehaviorDelta": False,
        "restoreBehaviorDelta": False,
        "deleteBehaviorDelta": False,
        "exportBehaviorDelta": False,
        "backupCompatibilityRequired": False,
        "restoreCompatibilityRequired": False,
        "deleteCompatibilityRequired": False,
        "exportCompatibilityRequired": False,
        "downgradeDisposition": "DROP_AND_REBUILD",
        "uiSurfaceDelta": False,
        "brandSurfaceDelta": False,
        "nativeCompileRan": False,
        "hostedDispatchEnabled": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "priorFenceProof": PRIOR_FENCE_PROOF,
    }


def _sealed(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha256_bytes(pretty(result))
    return result


def _path_evidence(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "pathFence": list(PATH_FENCE),
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "existingPaths": list(EXISTING_PATHS),
        "newPaths": list(NEW_PATHS),
        "pathFenceDigest": FENCE_DIGEST,
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
        "s10FenceOverlapPaths": [],
    }


def _source_contract(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "blueprintPath": AUTHORITY_REFERENCE_PATHS[0],
        "foundationPath": AUTHORITY_REFERENCE_PATHS[1],
        "sourceProjection": SOURCE_PROJECTION,
        "sourceTokens": list(SOURCE_CONTRACT_TOKENS),
        "requiredContractNames": list(CONTRACT_NAMES),
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
    }


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({
        "schema": "V23P03C17IntegrationEventProjectionContractV1",
        "artifact": "V23P03C17IntegrationEventProjectionContractV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "schemaArtifact": schema_row,
        "sourceContract": _source_contract(source_rows, authority_rows),
        "semanticScope": SEMANTIC_SCOPE,
        "requiredSemantics": {
            "contractNames": list(CONTRACT_NAMES),
            "visibilityClasses": list(VISIBILITY_CLASSES),
            "sensitivityClasses": list(SENSITIVITY_CLASSES),
            "redactionModes": list(REDACTION_MODES),
            "eventKinds": list(EVENT_KINDS),
            "checkpointStates": list(CHECKPOINT_STATES),
            "lifecycleModes": list(LIFECYCLE_MODES),
            "requiredBehaviors": list(REQUIRED_BEHAVIORS),
            "forbiddenClaims": list(FORBIDDEN_CLAIMS),
        },
        "persistenceBoundary": CORPUS["persistence"],
        "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
        "pathEvidence": _path_evidence(source_rows, authority_rows),
        "evidenceIDs": list(EVIDENCE_IDS),
        "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C18", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"},
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {
        "contractNames": list(CONTRACT_NAMES),
        "visibilityClasses": list(VISIBILITY_CLASSES),
        "sensitivityClasses": list(SENSITIVITY_CLASSES),
        "redactionModes": list(REDACTION_MODES),
        "eventKinds": list(EVENT_KINDS),
        "checkpointStates": list(CHECKPOINT_STATES),
        "lifecycleModes": list(LIFECYCLE_MODES),
        "requiredBehaviors": list(REQUIRED_BEHAVIORS),
        "requiredLifecycle": list(LIFECYCLE_DIMENSIONS),
    }
    return _sealed({
        "schema": "V23P03C17IntegrationEventProjectionEvidenceReceiptV1",
        "artifact": "V23P03C17IntegrationEventProjectionEvidenceReceiptV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "sourceContractDigest": sha256_value(source_rows),
        "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row,
        "contractArtifact": contract_row,
        "evidenceIDs": list(EVIDENCE_IDS),
        "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "evidenceCases": list(EVIDENCE_CASES),
        "requiredSemanticsDigest": sha256_value(semantics),
        "persistenceBoundary": CORPUS["persistence"],
        "pathEvidence": _path_evidence(source_rows, authority_rows),
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C17BrandImpactManifestV1",
        "artifact": "V23P03C17BrandImpactManifestV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI",
        "affectedSurfacePaths": [],
        "semanticStates": ["WORKSPACE_INTERNAL", "SENSITIVE_REDACTED", "RECOVERY_REQUIRED", "STALE"],
        "contractArtifact": contract_row,
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "s10FenceOverlapPaths": [],
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
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
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = json.loads(contract_raw.decode("utf-8"))
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, contract_row))
    brand_raw = pretty(brand_document(contract_row))
    rendered: dict[str, bytes] = {
        SCHEMA_PATH: schema_raw,
        CONTRACT_PATH: contract_raw,
        EVIDENCE_PATH: evidence_raw,
        BRAND_PATH: brand_raw,
    }
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C17ToolingManifestV1",
        "artifact": "V23P03C17ToolingManifestV1",
        "cardID": CARD,
        "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL",
        "verificationMode": "STATIC_ONLY",
        "authority": _authority(),
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE),
        "fullFencePaths": list(FULL_FENCE_PATHS),
        "pathFenceDigest": FENCE_DIGEST,
        "pathFenceCount": len(PATH_FENCE),
        "allowedCreateOrReplacePaths": list(PATH_FENCE),
        "allowedDeletePaths": [],
        "allowedRenamePaths": [],
        "existingPathCount": len(EXISTING_PATHS),
        "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS),
        "sourceArtifacts": source_rows,
        "authorityArtifacts": authority_rows,
        "artifacts": manifest_rows,
        "artifactSetDigest": sha256_value(manifest_rows),
        "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE,
        "persistenceBoundary": CORPUS["persistence"],
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS),
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "s10FenceOverlapPaths": [],
        "statusFlags": _flags(),
        "requiresAcceptedS10_6Reconciliation": True,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered
