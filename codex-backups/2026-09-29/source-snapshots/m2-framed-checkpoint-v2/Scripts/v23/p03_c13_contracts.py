#!/usr/bin/env python3
"""Deterministic static evidence-assurance artifacts for V23-P03-C13.

The C13 lane describes closed-audience visibility, claim/evidence links,
purpose-bound assurance manifests, and local recorded attestations.  It is a
static, provisional evidence lane: no customer data, account, cloud service,
delivery, legal/nonrepudiation claim, finalization producer, native build, or
hosted acceptance is created here.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


CARD = "V23-P03-C13"
TITLE = "EvidenceVisibilityV1, claim-evidence assurance manifest, and purpose-bound AttestationV1"
SCHEMA_VERSION = 1
REGISTER_ORDINAL = 50
BASE_HEAD = "458a19d2ed16826ec93b1ce688ffa4e1e8e57b59"
BASE_TREE = "74c59c691c72c3d37c08b0c9a5d318d635844a82"
CONTEXT_DIGEST = "2f00ad4af54e789e795d14a64af7b0f66d6c54169043e7585a32e5dd645e7141"
FENCE_DIGEST = "3a8af6eccec4a8842fde87c41ba665400ec2d20a8c80796c9945559b6c4c49ef"
PREREQUISITE_DIGEST = "f9925484fe0549823b164fbcefaa0b7faeceb13c183cd02a8c8afdc0e9c8e3d8"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
COORDINATION_HEAD = "ce96b8bd1c4b53698174a502b1566a73b79ae5c2"
COORDINATION_TREE = "e5ef99d98a223cc1306d3c40f31170bef362d97c"
COORDINATION_LEDGER_DIGEST = "2e2a8858853245c447d702e982c0ea81cbe59539dce159a36248f6fe66930627"
COORDINATION_CAS_SEQUENCE = 212
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
# The context's digest and length are authority values; the section body is
# not re-read from a moving worktree during generation.
REGISTER_SECTION_UTF8_LENGTH = 44217
REGISTER_ROW_SHA256 = "1b47ac0433bba28be866b71c7a61e6f0d7fc1acdd8d36aa786bd96d8715c9946"
DOSSIER_SHA256 = "83bb0b9be5503c9ec1b3789adfa20ade84e3107de694f179b3a41991ace28122"
DOSSIER_UTF8_LENGTH = 7087
INHERITED_V21_BLOCK_SHA256 = "9f23c125b928780b546bef7c24aa5dce69bbeb9f56ecb47ec64e4a1e40ee9670"
INHERITED_V21_BLOCK_UTF8_LENGTH = 8986

SCHEMA_PATH = "Scripts/v23/evidence-assurance.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C13EvidenceAssuranceContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C13EvidenceAssuranceEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C13BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C13-tooling-manifest.json"
FIXTURE_PATH = "FieldEvidenceAppTests/Fixtures/V21/EvidenceAssurance/V21P03C13EvidenceAssuranceCorpusV1.json"

SCRIPT_PATHS = (
    "Scripts/v23/p03_c13_contracts.py",
    "Scripts/v23/generate_p03_c13_contracts.py",
    "Scripts/v23/verify_p03_c13_contracts.py",
)
GENERATED_PATHS = (SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS

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
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
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
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/AuthorityCriterionContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AuthorityCriterionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Authority/AuthorityCriterionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Authority/AuthorityCriterionLifecycleAdapterV1.swift",
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
    "FieldEvidenceAppTests/V9_25AuthorityCriterionDerivationTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V10_03ReplicationConflictRegistryTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/TestSupport/PortableContracts/KernelConformanceFixtureHarnessV1.swift",
)
NEW_PATHS = (
    "FieldEvidenceApp/Domain/Reporting/EvidenceAssuranceContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/EvidenceAssurancePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Reporting/EvidenceAssuranceCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/EvidenceAssuranceLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_27EvidenceAssuranceTests.swift",
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

# One compact owner row per prior fence.  The overlap counts and digests are
# copied from the hydrated PathFenceV1; no path ownership is inferred here.
_PRIOR_ROWS = (
    ("V23-P00-C01", "052b5dd2d1dc05e3c4b87e8c75ef8ac0aca1f697f0d44ca32f67fb48409ce5c6", 0, 6),
    ("V23-P00-C02", "0e1d1d32135d703cab8627e34008ac484e3b0e03a1de709adc97b9781876225c", 0, 8),
    ("V23-P00-C02", "dd9c3ee57ad3cbfc50910d7b135fba83cdda2ae9e794b481ae03d14f5d65c626", 0, 8),
    ("V23-P00-C04", "6f6dfe5252e806915d353cefa0f04fc8c647f95f5b5c94bf648bea86e57260e8", 0, 9),
    ("V23-P00-C04", "2b3be123e51ea77619fc0c80de605d8ca2f9cedc7937cd1e0a4cf217fb1c680e", 0, 9),
    ("V23-P00-C05", "0bf5e3c7c274a819087d8d52b971b8fbdd9bafd149ae869852e90785afea98a7", 0, 10),
    ("V23-P00-C06", "ca49bcc135ddc270e18c42b808a804a6b1de71bb8a08647b32bccd3b1a9a6eca", 0, 8),
    ("V23-P00-C07", "c64e2e6c8241a94432f6683f7daa8ee23a0b74618a229cc898714ccf75f1849d", 0, 16),
    ("V23-P00-C08", "6a227a647dfd279cbd62edaa0501ff153e5ca5676260319aa7031e91b901ef1b", 0, 22),
    ("V23-P00-C09", "7138b44784ebe79a77e3bb243e6048f50d05b4ffd37cf74664bcdb800c54b36e", 0, 25),
    ("V23-P00-C10", "f34d2e3ea8defd5ff7146a499b88e39c76b0a925c519bb524120a2542064d1cb", 0, 21),
    ("V23-P00-C11", "560b3bd0401d0da46bcedc9f7184c8041e198db8cbe8af3011731fc0ad6cc8b1", 1, 22),
    ("V23-P00-C12", "c23d8f566b104f8ebc4cf2192d5c06e447621f72871fb43811e59972a53d9b6d", 0, 6),
    ("V23-P00-C13", "da9de4fd75416c8a3b8a2bb5224894794ac4bf2e3e80b9b1011ea9585c7d559d", 0, 12),
    ("V23-P01-C01", "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b", 3, 10),
    ("V23-P01-C02", "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809", 6, 21),
    ("V23-P01-C03", "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015", 6, 15),
    ("V23-P01-C04", "5ca647e7d47e14b1f758d06092df208626bbd8c4eac6dec3a83de0521800b51f", 3, 15),
    ("V23-P01-C05", "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a", 12, 25),
    ("V23-P01-C06", "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c", 23, 38),
    ("V23-P01-C07", "fa8024bd83119ef97a817b9bc9e5828b8e13328964cf60c8bfd2981e29ca85ce", 7, 33),
    ("V23-P02-C01", "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0", 5, 25),
    ("V23-P02-C02", "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef", 29, 50),
    ("V23-P02-C03", "20ae2fa339b0dfe67a9f862415d67ad85630b6440812063f6c278551777e1ee3", 21, 58),
    ("V23-P02-C04", "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa", 6, 24),
    ("V23-P02-C05", "336ad660a86cb30e4ea70ae99ca157f3dbaac1f89dd3011d0f37dd61926a73ac", 8, 37),
    ("V23-P02-C06", "b90723f324e2126e5fe04878e5016adb6c07e18b9972684415c692203d953f5a", 2, 27),
    ("V23-P02-C07", "2e293ae5e604d6f5c4f83009aad480b3eb278bc80b3c2202272c6bf13115c118", 26, 50),
    ("V23-P02-C08", "486696b004021f1a5095fd41de92b1a4b9a6692cd98a4e463fe09c7ace6f2ce5", 4, 27),
    ("V23-P02-C09", "a0e33d073d2dfa406b9540ea18c52e36286d28bce93500cf2640357c56d61171", 5, 24),
    ("V23-P02-C10", "9d402508388e16f092697f74de5bdc56fbe8eee6934bfa40c5eeb12675d905d7", 0, 24),
    ("V23-P02-C11", "c9bef9203b66eea8e816413a646ee5f3ef530ca3d1d5797be43c8f05314207a5", 0, 24),
    ("V23-P03-C01", "fae827d3757adfaf3af7485b3b5076db54ebbf92193a450a37e7ce8e042fb1d3", 0, 24),
    ("V23-P03-C02", "41823769e2170704e7c6144cb1fa4033dcbcd24f291fc6d35b496e8f78e02bba", 0, 24),
    ("V23-P03-C03", "8e424c0e0718d8df4127a2034744f1a347f14c3aed23f684cc0c0c4f6b525bf6", 0, 24),
    ("V23-P03-C04", "cafb01052cd0eb74fb7a90f0815439d3e3b29811c3a8b920fbae4d948d5c166c", 1, 24),
    ("V23-P03-C05", "f6ef2e304901fc4ccc103c5c210eee65b26faefb6b96a2cd8ae3a171debab614", 0, 24),
    ("V23-P03-C06", "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2", 6, 24),
    ("V23-P03-C07", "3f6a36f8794c159c24c26ec06506bff77a2d998df3cf04a5b8b06bb1d56e8264", 2, 24),
    ("V23-P03-C08", "89d6c2a346c3d944ae655c8f786cc3606e3e0529ba0ab1a80dc74878340f38e6", 9, 30),
    ("V23-P03-C09", "4aca28b9c93f736a67cf49df0ed6e28fa70b9cd38fb34ae95d03636b72ddc7ed", 39, 60),
    ("V23-P03-C10", "7e90b5eb871c6560b395fb487d0155a31a499009c6a2d4303b0aa668476d80f8", 1, 29),
    ("V23-P03-C11", "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1", 5, 13),
    ("V23-P03-C12", "b0d762a6a510d6273e6c11e1d410ab5652003a156b534f774a97778f8fd7d806", 31, 50),
    ("V23-P03-C16", "184ec46a5ec7a017a84bb3f9a487c5aec1d5d1f3ea90d57279333ce0aa5a6e43", 5, 18),
    ("V23-P03-C35", "64717de4cadb146884ba58d336e18dcdf0d1ad884cd527d7ab4faa7108382cfe", 37, 58),
    ("V23-P03-C38", "82717d9d63906a9152c29185ae4a375170cb0e8c772766c60016af91c6277aa4", 48, 63),
    ("V23-P03-C39", "c7e2f5ab8774c7dc42a0b0c571773ec8adbe5c66428bc6a418ddae978fe61ae2", 48, 73),
    ("V23-P03-C40", "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397", 68, 86),
    ("V23-P03-C41", "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000", 69, 91),
)
_DISPOSITION_BY_CARD = {
    "V23-P00-C11": "ERASE_CONCURRENCY_AND_LIFECYCLE_REPROOF_REQUIRED",
    "V23-P01-C01": "SCHEMA_SUCCESSOR_AND_MIGRATION_REPROOF_REQUIRED",
    "V23-P01-C02": "OWNED_FILE_RESTORE_CLONE_FORK_AND_GENERATION_REPROOF_REQUIRED",
    "V23-P01-C03": "COPY_ON_WRITE_MIGRATION_RECOVERY_REPROOF_REQUIRED",
    "V23-P01-C04": "ARCHIVE_AND_OPEN_COMPATIBILITY_REPROOF_REQUIRED",
    "V23-P01-C05": "CANONICAL_BACKUP_RESTORE_AND_IDENTITY_REPROOF_REQUIRED",
    "V23-P01-C06": "DELETE_ERASE_AND_PORTABLE_LIFECYCLE_REPROOF_REQUIRED",
    "V23-P01-C07": "RELEASED_DATA_AND_HISTORIC_REPORT_COMPATIBILITY_REPROOF_REQUIRED",
    "V23-P02-C01": "SOLE_WRITER_AND_COMMAND_REPROOF_REQUIRED",
    "V23-P02-C02": "MUTATION_RECEIPT_JOURNAL_AND_RECOVERY_REPROOF_REQUIRED",
    "V23-P02-C03": "SYNC_CLASSIFICATION_AND_CONFLICT_REPROOF_REQUIRED",
    "V23-P02-C04": "GENERATION_LEASE_AND_STALE_WRITER_REPROOF_REQUIRED",
    "V23-P02-C05": "RESUMABLE_JOB_BOUNDARY_REPROOF_REQUIRED",
    "V23-P02-C06": "DEVICE_TIME_AND_PROTECTED_DATA_REPROOF_REQUIRED",
    "V23-P02-C07": "OBSERVATION_TIME_AND_PROJECTION_REPROOF_REQUIRED",
    "V23-P02-C08": "SYSTEM_HEALTH_CLASSIFICATION_REPROOF_REQUIRED",
    "V23-P02-C09": "PERSISTENT_KIND_LIFECYCLE_COVERAGE_REPROOF_REQUIRED",
    "V23-P03-C04": "FINDING_CLAIM_EVIDENCE_BOUNDARY_REPROOF_REQUIRED",
    "V23-P03-C06": "COMPLETED_SNAPSHOT_IMMUTABILITY_REPROOF_REQUIRED",
    "V23-P03-C07": "KERNEL_BACKUP_RESTORE_DELETE_ERASE_REGISTRY_REPROOF_REQUIRED",
    "V23-P03-C08": "PACK_LIFECYCLE_BACKUP_RESTORE_AND_DELETE_REPROOF_REQUIRED",
    "V23-P03-C09": "SEARCH_SCHEMA_REBUILD_AND_LIFECYCLE_REPROOF_REQUIRED",
    "V23-P03-C10": "PORTABLE_KERNEL_CONFORMANCE_HARNESS_REPROOF_REQUIRED",
    "V23-P03-C11": "JOURNAL_CHECKPOINT_AND_REPLAY_REPROOF_REQUIRED",
    "V23-P03-C12": "REQUIREMENT_ASSURANCE_AND_REPORT_REPROOF_REQUIRED",
    "V23-P03-C16": "LOCALIZATION_ACCESSIBILITY_AND_FROZEN_DISPLAY_REPROOF_REQUIRED",
    "V23-P03-C35": "LOCATION_PLACEMENT_AND_COMPOSITION_OWNER_REPROOF_REQUIRED",
    "V23-P03-C38": "ACCOUNTABILITY_ACTOR_QUALIFICATION_SNAPSHOT_REPROOF_REQUIRED",
    "V23-P03-C39": "ASSET_SEMANTICS_SUBJECT_PACKAGE_AND_LIFECYCLE_REPROOF_REQUIRED",
    "V23-P03-C40": "DIRECT_PREREQUISITE_AUTHORITY_AND_SHARED_LIFECYCLE_REPROOF_REQUIRED",
    "V23-P03-C41": "ORDERING_AUTHORITY_SHARED_LIFECYCLE_REPROOF_REQUIRED",
}
# As in the preceding deterministic lanes, only actual overlap owners are
# listed in the compact artifact while fenceCount retains all prior fences.
PRIOR_FENCE_OVERLAPS = tuple(
    {"cardID": c, "fenceDigest": d, "disposition": _DISPOSITION_BY_CARD[c], "overlapCount": n}
    for c, d, n, _ in _PRIOR_ROWS if n
)
PRIOR_FENCE_PROOF = {
    "fenceCount": 50,
    "priorOwnedPathCount": 837,
    "overlapCount": 536,
    "authorizedOverlapCount": 536,
    "unauthorizedOverlapCount": 0,
    "overlapCards": list(PRIOR_FENCE_OVERLAPS),
}

CONTRACT_NAMES = ("EvidenceVisibilityV1", "ClaimEvidenceLinkV1", "AssuranceManifestV1", "AttestationV1")
VISIBILITY_AUDIENCES = ("INTERNAL_REVIEW", "CUSTOMER_REPORT", "EXTERNAL_COLLABORATOR")
SENSITIVITY_CLASSES = ("ROUTINE", "RESTRICTED", "HIGHLY_RESTRICTED")
INCLUSION_DISPOSITIONS = ("INCLUDED", "EXCLUDED")
ATTESTATION_PURPOSES = ("ACKNOWLEDGE_EVIDENCE", "ACKNOWLEDGE_REPORT", "CONFIRM_LOCAL_REVIEW")
ATTESTATION_METHODS = ("EXPLICIT_LOCAL_CONFIRMATION", "IMPORTED_EXTERNAL_EVIDENCE")
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_V13_VERSIONED_IDENTITY",
    "WRITER_COMMAND_QUERY_EXPECTED_REVISION_MUTATION_ID",
    "V12_TO_V13_COPY_ON_WRITE_MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK_GENERATION",
    "IMPORT_EXPORT_METADATA_ONLY_PREVIEW",
    "JOURNAL_REPLAY_CHECKPOINT",
    "DELETE_ERASE_RETENTION",
    "LOCAL_SEARCH_REBUILD",
    "REPORT_SNAPSHOT_OPEN_JSON",
    "LOCALIZATION_ACCESSIBILITY_PRIVACY",
    "INTERRUPTION_IDEMPOTENT_RECEIPTS",
    "DOWNGRADE_FORWARD_FIX_AFTER_FIRST_V13_WRITE",
)
FORBIDDEN_CLAIMS = (
    "ACCOUNT_OR_AUTHENTICATED_IDENTITY",
    "CLOUD_PROVIDER_OR_REMOTE_STORAGE",
    "OUTBOX_DELIVERY_OR_TRANSMISSION",
    "LEGAL_SIGNATURE_OR_NONREPUDIATION",
    "SECURITY_CERTIFICATION_OR_VERIFIED_IDENTITY",
    "FINALIZATION_OR_RELEASE_APPROVAL_PRODUCER",
    "NATIVE_IPAD_OR_SECOND_UI_SURFACE",
    "CUSTOMER_DATA_TELEMETRY_OR_MARKETING",
    "SECOND_STORE_OR_SECOND_CANONICAL_WRITER",
)
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
TEST_METHODS = (
    "testV23P03C13GoldenVisibilityLinksManifestAndPurposeBoundAttestation",
    "testV23P03C13AlternatePreviewPublicationAndClosedAudienceDisposition",
    "testV23P03C13HostileScopePurposeDigestSupersessionVoidAndForbiddenInputsFailClosed",
    "testV23P03C13InterruptionMigrationWritePreviewManifestAndAttestationRecover",
    "testV23P03C13RecoveryBackupRestoreCloneForkDeleteEraseSearchReportAndJournalPreserveHistory",
)
SOURCE_CONTRACT_TOKENS = (CARD, "V21-P03-C13", *CONTRACT_NAMES)

SEMANTIC_SCOPE = {
    "durableOwner": [*CONTRACT_NAMES, "PersistentSchemaV13"],
    "visibilityPolicy": "CLOSED_AUDIENCE_AND_SENSITIVITY_CLASSIFICATIONS_WITH_DENY_BY_DEFAULT_PROJECTION",
    "manifestPolicy": "CLAIM_EVIDENCE_LINKS_FREEZE_CLAIM_AND_EVIDENCE_IDS_DIGESTS_VISIBILITY_OMISSIONS_SNAPSHOT_DIGEST_AND_PROJECTION_VERSION",
    "attestationPolicy": "PURPOSE_BOUND_SCOPE_SNAPSHOT_ACTOR_METHOD_OCCURRED_RECORDED_AND_SUPERSESSION_OR_VOID_WITH_NO_LEGAL_NONREPUDIATION_CLAIM",
    "publicationPolicy": "PREVIEW_INCLUDED_AND_EXCLUDED_EVIDENCE_BEFORE_IMMUTABLE_REPORT_SNAPSHOT_FINALIZATION",
    "writerPolicy": "SOLE_WORKSPACE_WRITER_EXPECTED_REVISION_MUTATION_ID_DURABLE_RECEIPT_JOURNAL_AND_RECOVERY",
    "fullLifecyclePolicy": "SCHEMA_MIGRATION_BACKUP_RESTORE_DELETE_ERASE_EXPORT_REPORT_SEARCH_JOURNAL_REPLAY_LOCALIZATION_ACCESSIBILITY_PRIVACY_AND_INTERRUPTION_ENROLLED_BEFORE_FIRST_WRITE",
    "forbiddenPolicy": "NO_ACCOUNTS_AUTH_CLOUD_PROVIDER_OUTBOX_DELIVERY_LEGAL_NONREPUDIATION_SIGNING_UPLOAD_SUBMISSION_OR_FINALIZATION_PRODUCER",
    "s10Policy": "EXACT_EIGHTY_SIX_PATH_RESERVATION_FROZEN_WITH_ZERO_OVERLAP",
    "activationPolicy": "PROVISIONAL_PRE_S10_ONLY",
}

REQUIRED_BEHAVIORS = (
    {"id": "CLOSED_VISIBILITY", "contract": "EvidenceVisibilityV1", "requirement": "Explicit audience and sensitivity decisions are closed and deny by default; restricted and highly restricted evidence cannot widen its audience.", "evidence": "C13-S01"},
    {"id": "CLAIM_EVIDENCE_BINDING", "contract": "ClaimEvidenceLinkV1", "requirement": "Each claim/evidence link freezes stable claim and evidence IDs, source revisions and digests, visibility decision, and workspace identity.", "evidence": "C13-S02"},
    {"id": "PREVIEW_PUBLICATION", "contract": "AssuranceManifestV1", "requirement": "Preview separates included and excluded links before immutable publication and requires exact purpose, snapshot digest, and projection version.", "evidence": "C13-S03"},
    {"id": "LOCAL_ATTESTATION", "contract": "AttestationV1", "requirement": "Attestation is a local recorded, purpose-bound assertion over one manifest and scope snapshot; it never asserts identity verification, legal signature, or nonrepudiation.", "evidence": "C13-S04"},
    {"id": "IMMUTABLE_HISTORY", "contract": "V23-P03-C13", "requirement": "Supersession and void are append-only semantic states; released values and snapshots are never rewritten or merged.", "evidence": "C13-S05"},
    {"id": "V13_RECORDS12", "contract": "PersistentSchemaV13", "requirement": "V12-to-V13 copy-on-write enrolls the four assurance families at records schema 12 while preserving compatibility and recovery.", "evidence": "C13-L01"},
    {"id": "FULL_LIFECYCLE", "contract": "V23-P03-C13", "requirement": "Migration, backup/restore, clone/fork, import/export, journal/replay, search, report, delete/Erase, localization, accessibility, privacy, downgrade, and interruption are explicit before first write.", "evidence": "C13-L02"},
    {"id": "STATIC_BOUNDARY", "contract": CARD, "requirement": "The lane is PASS_STATIC_PROVISIONAL; native, hosted, adoption, acceptance, release, and credit flags remain false.", "evidence": "C13-B01"},
)
EVIDENCE_CASES = (
    {"id": "C13-S01", "kind": "VISIBILITY_MATRIX", "assertion": "Synthetic routine, restricted, and highly restricted visibility releases include explicit audience decisions and deny-by-default omissions."},
    {"id": "C13-S02", "kind": "CLAIM_EVIDENCE_LINK", "assertion": "Synthetic links bind claim/evidence IDs, revisions, digests, visibility release, and immutable workspace identity."},
    {"id": "C13-S03", "kind": "PREVIEW_AND_MANIFEST", "assertion": "Synthetic preview and manifest preserve included and excluded links, purpose, snapshot digest, projection version, and zero implicit writes."},
    {"id": "C13-S04", "kind": "PURPOSE_BOUND_ATTESTATION", "assertion": "Synthetic recorded, superseded, and voided local attestations stay bound to a manifest and scope snapshot."},
    {"id": "C13-H01", "kind": "HOSTILE_BOUNDARY", "assertion": "Cross-workspace, undeclared audience, missing purpose or snapshot, digest mismatch, duplicate, rewrite, account/cloud/delivery/legal/nonrepudiation/finalization producer attempts fail closed."},
    {"id": "C13-L01", "kind": "LIFECYCLE_COVERAGE", "assertion": "Records-12 V13 migration, compatibility, backup/restore, clone/fork, import/export, journal/replay, search, report, delete/Erase, privacy, downgrade, and interruption are declared."},
    {"id": "C13-F01", "kind": "PATH_DIGEST_FENCE", "assertion": "Exactly the 91-path fence is accounted for with 77 existing and 14 new paths, 536 authorized prior overlaps, and zero S10 overlap."},
    {"id": "C13-B01", "kind": "STATIC_BOUNDARY", "assertion": "All native, hosted, adoption, acceptance, release, and credit claims remain false pending accepted S10.6 reconciliation."},
)

SOURCE_PROJECTION = {
    "registerRows": ["| 50 | <a id=\"v23-p03-c13-register\"></a>[`V23-P03-C13`](EXPANSION_V23_ARCHITECTURE_BLUEPRINT.md#v23-p03-c13) | EvidenceVisibilityV1, claim-evidence assurance manifest, and purpose-bound AttestationV1 | `IMPLEMENT_NOW` | `NOT_STARTED` | `V23-P03-C40` | `REFINED_WITHOUT_LOSS` |"],
    "registerSectionSHA256": REGISTER_SECTION_SHA256,
    "registerSectionUTF8Length": REGISTER_SECTION_UTF8_LENGTH,
    "registerRowSHA256": REGISTER_ROW_SHA256,
    "dossierSHA256": DOSSIER_SHA256,
    "dossierUTF8Length": DOSSIER_UTF8_LENGTH,
    "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
    "inheritedV21BlockUTF8Length": INHERITED_V21_BLOCK_UTF8_LENGTH,
    "inheritedV21PayloadPresent": True,
    "facetRowCount": 1,
    "canonicalRecordWriterOwnershipRowCount": 9,
    "facetManifestDigest": "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f",
    "policyRefs": ["V23-POL-ARCH-001", "V23-POL-IPHONE-001", "V23-POL-TEST-001", "V23-POL-LIFECYCLE-001", "V23-POL-MUTATION-001"],
    "contractRefs": ["V21ToV23RequirementRebindingV1(V21-P03-C13).CONTRACTS", "DirectPrerequisiteEvidenceSetV1", "CardAcceptanceInclusionProofV1", "CardAcceptanceInclusionProofRecoveryReceiptV1", "CandidateAcceptanceCompatibilityReceiptV1"],
    "journeyRefs": ["NONE"],
    "deterministicEvidenceIDs": list(EVIDENCE_IDS),
    "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
    "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
    "invalidationConsumers": ["V23-P03-C14", "V23-P04-C27:STATE_INVENTORY", "V23-P04-C29:EXACT_CANDIDATE", "V23-P05-C01:RELEASE_SELECTOR"],
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
    "nativeCompileRan": False,
    "physicalLockedState": "REQUIRED_PENDING_OWNER",
    "acceptanceCredit": False,
    "releaseCredit": False,
    "createdAt": "2026-08-28T01:01:19Z",
    "predecessors": [{
        "cardID": "V23-P03-C40",
        "attemptID": 1,
        "candidateHead": "a3dbaeec868333f5940efa9bf5acf7811aed6d25",
        "candidateTree": "ac9539fcbfdcaa0816ac124753f0e1ed515361c1",
        "contextDigest": "fafbec0ccdb5cd65f331caca8fa74373104f31f38b1be9abd97345410bd82c9e",
        "pathFenceDigest": "4a3ecd9b94af09daf515cb3a4a21673dcb0a550c5a17832988e45fe3efd12397",
        "verificationReceiptDigest": "e1046caa5eb0a7532361aafc11e10d9758d897d997674591ec91afbf4db3fefd",
        "checkpointDigest": "1580e2692e9ab050a8e7947b54ed57b129e860b61762f80e9549cfe90cb263bb",
        "disposition": "CHECKPOINTED_PROVISIONAL_CANONICAL_DIRECT_PREREQUISITE_AT_EXACT_C40_HEAD",
    }],
    "prerequisiteDigest": PREREQUISITE_DIGEST,
}
ORDERING_AUTHORITY = {
    "cardID": "V23-P03-C41",
    "attemptID": 1,
    "candidateHead": "458a19d2ed16826ec93b1ce688ffa4e1e8e57b59",
    "candidateTree": "74c59c691c72c3d37c08b0c9a5d318d635844a82",
    "contextDigest": "2a812d74def7b09e4339a99919fcaed0ac7f96ab750622fceb0c0e2280845364",
    "pathFenceDigest": "c044f055f75dd8a2162aea7db70142b87e67fb3129f2f6a694baf8a10f30a000",
    "checkpointDigest": "3f9876516881e4a79cc5ce7065c4f397093a93b17c8a7fac5916adae183553fc",
    "disposition": "CHECKPOINTED_PROVISIONAL_ORDERING_AUTHORITY_AT_EXACT_C41_HEAD",
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
    document.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "https://assetrounds.invalid/v23/evidence-assurance.schema.json", "title": "V23 P03 C13 Evidence Assurance Corpus"})
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
        "fullFencePaths": list(FULL_FENCE_PATHS), "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE, "overrideReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "directPrerequisiteCards": ["V23-P03-C40"], "orderingAuthorityCards": ["V23-P03-C41"],
        "allowedPathCount": len(PATH_FENCE), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [],
        "persistentChangeMode": "NEW_SCHEMA_VERSION", "persistentContractSchema": "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE", "recordSchemaVersion": 12,
        "schemaBehaviorDelta": True, "migrationBehaviorDelta": True, "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True, "exportBehaviorDelta": True,
        "backupCompatibilityRequired": True, "restoreCompatibilityRequired": True, "deleteCompatibilityRequired": True, "exportCompatibilityRequired": True,
        "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V13_WRITE", "uiSurfaceDelta": False, "brandSurfaceDelta": False,
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
    return {"blueprintPath": AUTHORITY_REFERENCE_PATHS[0], "foundationPath": AUTHORITY_REFERENCE_PATHS[1], "sourceProjection": SOURCE_PROJECTION, "sourceTokens": list(SOURCE_CONTRACT_TOKENS), "requiredContractNames": list(CONTRACT_NAMES), "lineage": "EXACT_WITH_GENERATION_REBIND", "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows}


def contract_document(root: Path, schema_row: dict[str, Any]) -> dict[str, Any]:
    source_rows, authority_rows = source_artifacts(root), authority_artifacts(root)
    return _sealed({
        "schema": "V23P03C13EvidenceAssuranceContractV1", "artifact": "V23P03C13EvidenceAssuranceContractV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY, "schemaArtifact": schema_row,
        "sourceContract": _source_contract(source_rows, authority_rows), "semanticScope": SEMANTIC_SCOPE,
        "requiredSemantics": {"contractNames": list(CONTRACT_NAMES), "visibilityAudiences": list(VISIBILITY_AUDIENCES), "sensitivityClasses": list(SENSITIVITY_CLASSES), "inclusionDispositions": list(INCLUSION_DISPOSITIONS), "attestationPurposes": list(ATTESTATION_PURPOSES), "attestationMethods": list(ATTESTATION_METHODS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "forbiddenClaims": list(FORBIDDEN_CLAIMS)},
        "persistenceBoundary": CORPUS["persistence"], "requiredLifecycle": list(LIFECYCLE_DIMENSIONS), "pathEvidence": _path_evidence(source_rows, authority_rows), "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS),
        "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES),
        "successor": {"cardID": "V23-P03-C14", "attemptID": 1, "ordering": "IMMEDIATE_REGISTER_SUCCESSOR"}, "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def evidence_document(source_rows: list[dict[str, Any]], authority_rows: list[dict[str, Any]], schema_row: dict[str, Any], contract_row: dict[str, Any]) -> dict[str, Any]:
    semantics = {"contractNames": list(CONTRACT_NAMES), "visibilityAudiences": list(VISIBILITY_AUDIENCES), "sensitivityClasses": list(SENSITIVITY_CLASSES), "inclusionDispositions": list(INCLUSION_DISPOSITIONS), "attestationPurposes": list(ATTESTATION_PURPOSES), "attestationMethods": list(ATTESTATION_METHODS), "requiredBehaviors": list(REQUIRED_BEHAVIORS), "requiredLifecycle": list(LIFECYCLE_DIMENSIONS)}
    return _sealed({
        "schema": "V23P03C13EvidenceAssuranceEvidenceReceiptV1", "artifact": "V23P03C13EvidenceAssuranceEvidenceReceiptV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "sourceProjection": SOURCE_PROJECTION,
        "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY, "sourceContractDigest": sha256_value(source_rows), "authorityArtifactDigest": sha256_value(authority_rows),
        "schemaArtifact": schema_row, "contractArtifact": contract_row, "evidenceIDs": list(EVIDENCE_IDS), "testMethods": list(TEST_METHODS), "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "evidenceCases": list(EVIDENCE_CASES), "requiredSemanticsDigest": sha256_value(semantics),
        "persistenceBoundary": CORPUS["persistence"], "pathEvidence": _path_evidence(source_rows, authority_rows), "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })


def brand_document(contract_row: dict[str, Any]) -> dict[str, Any]:
    return _sealed({
        "schema": "V23P03C13BrandImpactManifestV1", "artifact": "V23P03C13BrandImpactManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION,
        "status": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "brandImpactDisposition": "CONTRACT_ONLY_NO_SHIPPING_UI", "affectedSurfacePaths": [], "semanticStates": ["INCLUDED", "EXCLUDED", "VOIDED", "SUPERSEDED"], "contractArtifact": contract_row,
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
    schema_raw = pretty(schema_document())
    schema_row = {"path": SCHEMA_PATH, "bytes": len(schema_raw), "sha256": sha256_bytes(schema_raw)}
    contract_raw = pretty(contract_document(root, schema_row))
    contract_row = {"path": CONTRACT_PATH, "bytes": len(contract_raw), "sha256": sha256_bytes(contract_raw)}
    evidence_raw = pretty(evidence_document(source_rows, authority_rows, schema_row, json.loads(contract_raw.decode("utf-8"))))
    brand_raw = pretty(brand_document(json.loads(contract_raw.decode("utf-8"))))
    rendered: dict[str, bytes] = {SCHEMA_PATH: schema_raw, CONTRACT_PATH: contract_raw, EVIDENCE_PATH: evidence_raw, BRAND_PATH: brand_raw}
    manifest_rows = [_manifest_row(root, path, rendered) for path in MANIFEST_INPUT_PATHS]
    manifest = _sealed({
        "schema": "V23P03C13ToolingManifestV1", "artifact": "V23P03C13ToolingManifestV1", "cardID": CARD, "schemaVersion": SCHEMA_VERSION, "result": "PASS_STATIC_PROVISIONAL", "verificationMode": "STATIC_ONLY", "authority": _authority(), "baseHead": BASE_HEAD, "baseTree": BASE_TREE,
        "pathFence": list(PATH_FENCE), "fullFencePaths": list(FULL_FENCE_PATHS), "pathFenceDigest": FENCE_DIGEST, "pathFenceCount": len(PATH_FENCE), "allowedCreateOrReplacePaths": list(PATH_FENCE), "allowedDeletePaths": [], "allowedRenamePaths": [], "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS),
        "sourceReferenceCount": len(SOURCE_REFERENCE_PATHS), "sourceArtifacts": source_rows, "authorityArtifacts": authority_rows, "artifacts": manifest_rows, "artifactSetDigest": sha256_value(manifest_rows), "sourceProjection": SOURCE_PROJECTION, "directPrerequisiteEvidence": DIRECT_PREREQUISITE_EVIDENCE, "orderingAuthority": ORDERING_AUTHORITY,
        "persistenceBoundary": CORPUS["persistence"], "priorFenceOverlaps": list(PRIOR_FENCE_OVERLAPS), "priorFenceProof": PRIOR_FENCE_PROOF, "frozenS10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST, "s10FenceOverlapPaths": [], "statusFlags": _flags(), "requiresAcceptedS10_6Reconciliation": True,
    })
    rendered[MANIFEST_PATH] = pretty(manifest)
    return rendered


CORPUS: dict[str, Any] = {
    "schema": "V21P03C13EvidenceAssuranceCorpusV1", "schemaVersion": SCHEMA_VERSION, "cardID": CARD, "synthetic": True, "containsCustomerData": False, "containsSecrets": False,
    "requiredContractNames": list(CONTRACT_NAMES), "visibilityAudiences": list(VISIBILITY_AUDIENCES), "sensitivityClasses": list(SENSITIVITY_CLASSES), "inclusionDispositions": list(INCLUSION_DISPOSITIONS), "attestationPurposes": list(ATTESTATION_PURPOSES), "attestationMethods": list(ATTESTATION_METHODS),
    "persistence": {
        "schemaRelease": "PERSISTENT_SCHEMA_V13_EVIDENCE_ASSURANCE", "recordSchemaVersion": 12, "predecessorSchemaVersion": 12, "predecessorRecordSchemaVersion": 11, "migration": "EXACT_V12_TO_V13_COPY_ON_WRITE", "canonicalWriter": "V23-P02-C01", "lifecycleOwner": CARD, "firstWriteEnrolled": True, "compatibilityRequired": True, "backupRestoreRequired": True, "deleteEraseRequired": True, "exportImportPreviewRequired": True, "downgrade": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_FIRST_V13_WRITE", "persistedFamilies": list(CONTRACT_NAMES), "currentProjectionRows": 0, "currentProjectionRowCount": 0, "recordsSchemaVersion": 12, "secondStore": False, "secondWriter": False, "accountStore": False, "cloudStore": False, "deliveryOutbox": False, "descriptorEventOnlyPersistence": False,
        "nonPersistentFamilies": ["AssuranceProjectionPreviewV1"], "snapshotBinding": "REPORT_OR_COMPLETED_ACTIVITY_SNAPSHOT_DIGEST_REQUIRED", "purposeBinding": "ATTESTATION_PURPOSE_AND_SCOPE_REQUIRED", "supersessionAndVoid": "APPEND_ONLY_IMMUTABLE_HISTORY", "legacyRowsCreated": 0,
    },
    "visibilityRecords": [
        {"id": "visibility-routine-v1", "workspaceID": "workspace-synthetic-1", "sensitivity": "ROUTINE", "allowedAudiences": ["CUSTOMER_REPORT", "EXTERNAL_COLLABORATOR", "INTERNAL_REVIEW"], "defaultDisposition": "DENY_UNLESS_EXPLICIT", "revision": 1, "immutable": True},
        {"id": "visibility-restricted-v1", "workspaceID": "workspace-synthetic-1", "sensitivity": "RESTRICTED", "allowedAudiences": ["CUSTOMER_REPORT", "INTERNAL_REVIEW"], "defaultDisposition": "DENY_UNLESS_EXPLICIT", "revision": 1, "immutable": True},
        {"id": "visibility-high-v1", "workspaceID": "workspace-synthetic-1", "sensitivity": "HIGHLY_RESTRICTED", "allowedAudiences": ["INTERNAL_REVIEW"], "defaultDisposition": "DENY_UNLESS_EXPLICIT", "revision": 1, "immutable": True},
    ],
    "claimEvidenceLinks": [
        {"id": "link-claim-1", "workspaceID": "workspace-synthetic-1", "claimID": "claim-visibility-1", "evidenceID": "evidence-synthetic-1", "evidenceRevision": 1, "evidenceSHA256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "visibilityID": "visibility-routine-v1", "visibilityRevision": 1, "visibilitySHA256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "audience": "CUSTOMER_REPORT", "disposition": "INCLUDED", "snapshotSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "projectionVersion": "report-projection-v1", "frozen": True},
        {"id": "link-claim-2", "workspaceID": "workspace-synthetic-1", "claimID": "claim-visibility-2", "evidenceID": "evidence-sensitive-1", "evidenceRevision": 1, "evidenceSHA256": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", "visibilityID": "visibility-high-v1", "visibilityRevision": 1, "visibilitySHA256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "audience": "CUSTOMER_REPORT", "disposition": "EXCLUDED", "limitation": "SENSITIVITY_RESTRICTED", "snapshotSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "projectionVersion": "report-projection-v1", "frozen": True},
    ],
    "assuranceProjectionPreviews": [
        {"id": "preview-customer-report", "workspaceID": "workspace-synthetic-1", "audience": "CUSTOMER_REPORT", "includedLinkIDs": ["link-claim-1"], "excludedLinkIDs": ["link-claim-2"], "purpose": "ACKNOWLEDGE_REPORT", "snapshotSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "projectionVersion": "report-projection-v1", "writes": 0, "disposition": "PREVIEW_ONLY", "staleAfterSnapshotChange": True},
    ],
    "assuranceManifests": [
        {"id": "manifest-customer-report-v1", "workspaceID": "workspace-synthetic-1", "audience": "CUSTOMER_REPORT", "includedLinkIDs": ["link-claim-1"], "excludedLinkIDs": ["link-claim-2"], "purpose": "ACKNOWLEDGE_REPORT", "snapshotSHA256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "projectionVersion": "report-projection-v1", "sourcePreviewID": "preview-customer-report", "revision": 1, "supersedesManifestID": None, "voided": False, "immutable": True},
    ],
    "attestations": [
        {"id": "attestation-recorded-1", "workspaceID": "workspace-synthetic-1", "purpose": "ACKNOWLEDGE_REPORT", "scopeKind": "ASSURANCE_MANIFEST", "scopeID": "manifest-customer-report-v1", "scopeRevision": 1, "manifestID": "manifest-customer-report-v1", "manifestRevision": 1, "method": "EXPLICIT_LOCAL_CONFIRMATION", "action": "RECORDED", "revision": 1, "supersedesAttestationID": None, "localOnly": True, "legalOrNonrepudiationClaim": False},
        {"id": "attestation-voided-1", "workspaceID": "workspace-synthetic-1", "purpose": "ACKNOWLEDGE_REPORT", "scopeKind": "ASSURANCE_MANIFEST", "scopeID": "manifest-customer-report-v1", "scopeRevision": 1, "manifestID": "manifest-customer-report-v1", "manifestRevision": 1, "method": "EXPLICIT_LOCAL_CONFIRMATION", "action": "VOIDED", "revision": 2, "supersedesAttestationID": "attestation-recorded-1", "localOnly": True, "legalOrNonrepudiationClaim": False},
    ],
    "currentProjectionRows": [], "currentProjectionPersistence": "NONPERSISTENT_REBUILD_ONLY", "purposeBindingRequired": True, "snapshotBindingRequired": True, "denyByDefault": True, "supersessionImmutable": True, "voidImmutable": True,
    "previewPublication": {"previewIsZeroWrite": True, "publicationRequiresExactSnapshot": True, "publicationRequiresPurpose": True, "publicationCannotRewriteHistory": True, "defaultDisposition": "DENIED"},
    "forbiddenCapabilities": {"accounts": False, "authentication": False, "cloud": False, "delivery": False, "legalClaims": False, "nonrepudiation": False, "finalizationProducer": False, "signing": False, "upload": False, "submission": False, "secondStore": False, "secondWriter": False},
    "lifecycleCoverage": [{"dimension": dimension, "enrolledBeforeFirstWrite": True, "disposition": "EXPLICIT_STATIC_CONTRACT"} for dimension in LIFECYCLE_DIMENSIONS],
    "hostileCases": [{"id": case_id, "expectedDisposition": "FAIL_CLOSED"} for case_id in ("cross-workspace", "undeclared-audience", "sensitivity-widening", "missing-purpose", "missing-snapshot", "snapshot-digest-mismatch", "projection-version-mismatch", "duplicate-link", "duplicate-evidence", "supersession-rewrite", "void-rewrite", "stale-preview-publication", "account-producer", "cloud-producer", "delivery-outbox", "legal-signature", "nonrepudiation", "finalization-producer", "second-store", "second-writer")],
    "interruptionCases": [{"id": case_id, "expectedDisposition": "PRIOR_ACCEPTED_REVISION_OR_NO_PARTIAL_AUTHORITY"} for case_id in ("migration-boundary", "visibility-admission", "link-write", "preview-build", "manifest-write", "attestation-write", "snapshot-bind", "backup-export", "restore-replace", "journal-replay", "search-rebuild", "report-open-json")],
    "recoveryCases": [{"id": case_id, "expectedDisposition": "RECOVER_EFFECT_RECEIPT_AND_HISTORY"} for case_id in ("backup-restore", "clone-fork", "delete-erase", "compatibility-forward-fix", "journal-replay", "search-rebuild", "report-snapshot", "metadata-only-export", "released-v13")],
    "claims": {claim: False for claim in (*FORBIDDEN_CLAIMS, "native", "hosted", "adoption", "acceptance", "release", "acceptanceCredit", "releaseCredit")},
}
