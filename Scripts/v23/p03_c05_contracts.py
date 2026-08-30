#!/usr/bin/env python3
"""Deterministic C05 attempt-3 content/evidence metadata tooling.

This module is a read-only projection of the accepted C05 correction.  The
only durable C05 families are the two evidence-metadata rows; content bytes,
locators, derivatives, reports, and lifecycle projections continue to use the
existing authorities named by the path fence.  Generated JSON is deliberately
provisional until the source/test lane is stable and ``FINAL_HASHES_SEALED``
is enabled for the final reseal.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

CARD = "V23-P03-C05"
ATTEMPT_ID = 3
TITLE = (
    "ContentReferenceV1, local ContentLocator/Manifest, media associations, "
    "immutable originals, derivatives, and provenance"
)
REGISTER_ORDINAL = 36

# Immutable application and coordination pins from the accepted attempt-3
# hydration record.  The application checkout may be a descendant of the
# base while this lane is being assembled; its base tree remains immutable.
BASE_HEAD = "4a8e63b7187613919f1e30d31d5154847c197a02"
BASE_TREE = "446193953f7fae06d377aa58a0584bb5d307b906"
APP_BASE_HEAD = BASE_HEAD
APP_BASE_TREE = BASE_TREE
COORDINATION_HEAD = "4178c6390f149f23f62c368560218e08b0f93202"
COORDINATION_TREE = "f6d8784f73943df39fa87df1316879beec4555d5"
COORDINATION_CAS_SEQUENCE = 390
CONTEXT_DIGEST = "148ea188dd2add6ea8bcce6cf2caa0e01dd1a6d10d5395cf552ff1bb3775fc44"
FENCE_DIGEST = "8ca993b5f491de9520c1b38a25f1c0021fcc84ec10f9f4c8b37ad183f7942524"
PREREQUISITE_DIGEST = "fe983760cda3030c95733ba5f7948bb4e367aab3306e9f026efed86dae77b1d4"
CORRECTION_RECEIPT_DIGEST = "e3a0608fe7508e62615ae104d3d11116623c30c7c71634578b15d93d0fc2553a"
HYDRATION_TRANSITION_DIGEST = "d636607fc89d0707f12dbb7efd2ac50ba3c846687bc9826d4389d93fe6c7bfc5"
TRANSITION_DIGEST = HYDRATION_TRANSITION_DIGEST
COORDINATION_LEDGER_DIGEST = "d009d9c3322ae239943c6e9bb0b38cc4231e4d1b2e97587e52035907d961a6fc"
COORDINATION_PROJECTION_DIGEST = "60c4321aa7545f1829de092bff2442b8f46b7cb5b16c0973bc0a8f915a4c865b"
HYDRATION_PROJECTION_DIGEST = COORDINATION_PROJECTION_DIGEST
PRIOR_CONTEXT_DIGEST = "1ca2c721ea156d5a92e0494bb06c59306383a7c7e8f9c3ad224485deaee88bc2"
PRIOR_FENCE_DIGEST = "0faa2d50639929abd8009efda71bebab07e9c92c890eecbe59e17590b68b5ebf"
PRIOR_TRANSITION_DIGEST = "85f790a76efe0d834587ede5b3e57cc52cfc00ec44025fa3f323b653eb542780"
PRIOR_LEDGER_DIGEST = "c2dd7e9af2f0395835525526dcb0eed33327b9aeefb4e853a55a3516025ea618"
CORRECTION_RECEIPT_PATH = "receipts/V23-P04-C02-accepted-provider-clone-fork-mismatch-C05-attempt-2-v1.json"
CORRECTION_TRANSITION_PATH = "transitions/000390-V23-P03-C05-attempt-3-NOT_STARTED-to-HYDRATING.json"
PREREQUISITE_RECEIPT_PATH = "receipts/V23-P03-C05-attempt-2-to-attempt-3-provisional-prerequisite.json"
PRIOR_TRANSITION_PATH = "transitions/000389-V23-P04-C02-attempt-1-HYDRATING-to-HYDRATING-C05-clone-fork-hold.json"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
FROZEN_S10_RESERVATION_DIGEST = S10_RESERVATION_DIGEST
ACCEPTED_DEPENDENCY_MISMATCH_DIGEST = "a83f89eb65d1a73c72b7812715c86c2349b4aaf06e1c918053b5fd9404f76eb1"

# Planning bytes are pinned by the attempt-3 context.  The blueprint slice is
# intentionally not regenerated from a moving plan; the coordination context
# is the source of truth for these values.
DOSSIER_SHA256 = "a28c945fe83b27203b42ef7f5568ed29b93e20312378b6102428ec72057331b4"
DOSSIER_BYTES = 7267
REGISTER_ROW_SHA256 = "c340deb4a2fa32d87f9be7be900347c59a818b26f01821e224fc5233bbec6774"
REGISTER_ROW_BYTES = 307
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217
INHERITED_V21_BLOCK_SHA256 = "81d49b48b336fc1c9347928e8f361684ecd29b3f5b43be02c7b3a420e6ca8442"
INHERITED_V21_BLOCK_BYTES = 9610

EXPECTED_EXISTING_PATH_COUNT = 18
EXPECTED_NEW_PATH_COUNT = 0
EXPECTED_FENCE_PATH_COUNT = 18
PRIOR_FENCE_COUNT = 90
PRIOR_OWNED_PATH_COUNT = 1443
AUTHORIZED_OVERLAP_COUNT = 215
UNAUTHORIZED_OVERLAP_COUNT = 0
S10_RESERVATION_OVERLAP_COUNT = 0
S10_RESERVED_PATH_COUNT = 86

PERSISTENT_SCHEMA_VERSION = 43
RECORDS_SCHEMA_VERSION = 42
ACTIVE_MODEL_COUNT = 144
DURABLE_FAMILY_COUNT = 2
DURABLE_ROWS = (
    "EvidenceAssociationEventRowV1",
    "EvidenceSequenceRevisionRowV1",
)
DURABLE_FAMILIES = (
    "EVIDENCE_ASSOCIATION_EVENT",
    "EVIDENCE_SEQUENCE_REVISION",
)
DERIVED_FAMILY = "PROJECTION:StoreSemanticEnvelopeV43"

ROLE_VALUES = ("CONTEXT", "DETAIL", "BEFORE", "AFTER", "OTHER")
TEXT_PROVENANCE_VALUES = ("USER_AUTHORED", "IMPORTED_THEN_REVIEWED")
MAX_SEQUENCE_ITEMS = 32
MAX_CAPTION_BYTES = 1024
MAX_ACCESSIBILITY_DESCRIPTION_BYTES = 2048

CONTRACT_SCRIPT = "Scripts/v23/p03_c05_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p03_c05_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p03_c05_contracts.py"
SCRIPT_PATHS = (CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT)
SCHEMA_PATHS = (
    "Scripts/v23/content-reference.schema.json",
    "Scripts/v23/content-locator.schema.json",
    "Scripts/v23/content-manifest.schema.json",
    "Scripts/v23/evidence-association.schema.json",
    "Scripts/v23/content-derivative-provenance.schema.json",
    "Scripts/v23/content-evidence-receipt.schema.json",
)
CONTRACT_PATHS = (
    "docs/design/v23/tooling/V23P03C05ContentReferenceContractV1.json",
    "docs/design/v23/tooling/V23P03C05ContentLocatorManifestContractV1.json",
    "docs/design/v23/tooling/V23P03C05EvidenceAssociationContractV1.json",
    "docs/design/v23/tooling/V23P03C05DerivativeProvenanceContractV1.json",
    "docs/design/v23/tooling/V23P03C05ContentEvidenceReceiptV1.json",
)
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C05-tooling-manifest.json"
MANIFEST = MANIFEST_PATH
TOOLING_EDIT_PATHS = (CONTRACT_SCRIPT, *SCHEMA_PATHS, *CONTRACT_PATHS, MANIFEST_PATH)
TOOL_PATHS = TOOLING_EDIT_PATHS
GENERATED_PATHS = (*SCHEMA_PATHS, *CONTRACT_PATHS, MANIFEST_PATH)
OUTPUT_PATHS = GENERATED_PATHS

# Broader inherited semantic inputs remain read-only validation dependencies.
SEMANTIC_INPUT_PATHS = (
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json",
    "FieldEvidenceAppTests/S2PersistenceLedgerTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "Scripts/v23/content-derivative-provenance.schema.json",
    "Scripts/v23/content-evidence-receipt.schema.json",
    "Scripts/v23/content-locator.schema.json",
    "Scripts/v23/content-manifest.schema.json",
    "Scripts/v23/content-reference.schema.json",
    "Scripts/v23/evidence-association.schema.json",
    "Scripts/v23/generate_p03_c05_contracts.py",
    "Scripts/v23/p03_c05_contracts.py",
    "Scripts/v23/verify_p03_c05_contracts.py",
    "docs/design/v23/tooling/V23-P03-C05-tooling-manifest.json",
    "docs/design/v23/tooling/V23P03C05ContentEvidenceReceiptV1.json",
    "docs/design/v23/tooling/V23P03C05ContentLocatorManifestContractV1.json",
    "docs/design/v23/tooling/V23P03C05ContentReferenceContractV1.json",
    "docs/design/v23/tooling/V23P03C05DerivativeProvenanceContractV1.json",
    "docs/design/v23/tooling/V23P03C05EvidenceAssociationContractV1.json",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
)
EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    CONTRACT_SCRIPT,
    *SCHEMA_PATHS,
    *CONTRACT_PATHS,
    MANIFEST_PATH,
)
IMPLEMENTATION_PATHS: tuple[str, ...] = ()
NEW_PATHS: tuple[str, ...] = ()
PATH_FENCE = EXISTING_PATHS
CORRECTION_ADDED_PATHS = (
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
)
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
SOURCE_PATHS = tuple(path for path in PATH_FENCE if path not in TOOLING_EDIT_PATHS)
SOURCE_SWIFT_PATHS = tuple(path for path in SOURCE_PATHS if path.lower().endswith(".swift"))
SEMANTIC_SOURCE_SWIFT_PATHS = tuple(
    path for path in SEMANTIC_INPUT_PATHS if path.lower().endswith(".swift")
) + ("FieldEvidenceApp/Domain/Models/EvidenceMetadataPersistenceModelsV1.swift",)
EVIDENCE_SUFFIXES = ("G01", "A01", "H01", "I01", "R01")
SELECTOR_SUFFIXES = EVIDENCE_SUFFIXES
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in EVIDENCE_SUFFIXES)

INTEGRATION_SOURCE_PATHS = (
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
)
INTEGRATION_TEST_BINDINGS = (
    (
        "FieldEvidenceAppTests/S6_5ReplacementUnionTests.swift",
        "testV23P03C05Records42ReplacementUnionsPredecessorClosedMetadata",
        (
            "C05EvidenceMetadataReplacementRestoreBoundaryV1", "canonicalRows",
            "invalidAuthority", "cloneForkWithoutRebindFailsClosed",
        ),
    ),
    (
        "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
        "testV23P03C05Records42CorpusKeepsOrderedPredecessorClosedMetadata",
        (
            "C05EvidenceMetadataBackupEnrollmentV1", "EvidenceSequenceRevisionRowV1.rowID",
            "invalidSuccessor", "duplicateIdentity",
        ),
    ),
    (
        "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
        "testV23P03C05Records41ReadAndRecords42RestoreRejectFutureMetadata",
        (
            "recordsSchemaVersion", "preserveSameWorkspaceCanonicalHistory",
            "cloneForkWithoutRebindFailsClosed", "rejectCloneForkWithoutRebind",
            "invalidValue",
            "sourceRowsAutomaticallyActivateOnCloneOrFork",
        ),
    ),
    (
        "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
        "testV23P03C05MetadataDeletionIsAppendOnlyAndContentRemainsIncumbentOwned",
        (
            "EvidenceMetadataDeletionLedgerPolicyV1", "ordinaryRemovalCreatesAppendOnlySuccessor",
            "ordinaryRemovalPhysicallyDeletesMetadata", "workspaceEraseClearsRowsAndOwnedDerivatives",
            "durableRowNames",
        ),
    ),
)
INTEGRATION_TEST_METHODS = tuple(binding[1] for binding in INTEGRATION_TEST_BINDINGS)
INTEGRATION_EVENT_KINDS = (
    "evidence.association_event.v1",
    "evidence.sequence_revision.v1",
)
INTEGRATION_EVENT_ORDERING_BASIS = (
    "ACCEPTED_WORKSPACE_REVISION_THEN_RECEIPT_IDENTITY_THEN_PAYLOAD_ORDINAL"
)
INTEGRATION_EVENT_LIFECYCLE = "DERIVED_DROP_AND_REBUILD"
INTEGRATION_REPLAY_LIMIT = 100_000

CONTRACT_REFS = (
    "V21ToV23RequirementRebindingV1(V21-P03-C05).CONTRACTS",
    "DirectPrerequisiteEvidenceSetV1",
    "CardAcceptanceInclusionProofV1",
    "CardAcceptanceInclusionProofRecoveryReceiptV1",
    "CandidateAcceptanceCompatibilityReceiptV1",
)
DIRECT_PREREQUISITES = ("V23-P03-C04",)
OPTIONAL_CAPABILITY_PROVIDERS = ("NONE",)
JOURNEY_REFS = ("FJ15",)
INVALIDATION_CONSUMERS = (
    "V23-P03-C06",
    "V23-P04-C27:STATE_INVENTORY",
    "V23-P04-C29:EXACT_CANDIDATE",
    "V23-P05-C01:RELEASE_SELECTOR",
)
POLICY_REFS = (
    "V23-POL-ARCH-001",
    "V23-POL-IPHONE-001",
    "V23-POL-TEST-001",
    "V23-POL-LIFECYCLE-001",
    "V23-POL-MUTATION-001",
    "V23-POL-HIG-001",
    "V23-POL-A11Y-001",
    "V23-POL-L10N-001",
)
LIFECYCLE_DIMENSIONS = (
    "SCHEMA_VERSION",
    "WRITER_QUERY",
    "MIGRATION",
    "BACKUP_REPLACE_RESTORE",
    "CLONE_FORK",
    "IMPORT_EXPORT",
    "JOURNAL_REPLAY",
    "SEARCH_REBUILD",
    "REPORT_PROJECTION",
    "DELETE_ERASE",
    "RETENTION",
    "COMPATIBILITY",
    "DOWNGRADE_FORWARD_FIX",
    "INTERRUPTION",
    "IDEMPOTENT_RECEIPTS",
)

# Attempt-3 has real durable rows, but it has not earned native/hosted or
# shipping activation evidence.  These values are emitted in every artifact.
FLAGS = {name: False for name in (
    "activation",
    "nativeCompileRan",
    "hostedDispatchRan",
    "hostedDispatchEnabled",
    "physicalEvidenceComplete",
    "adoptionEnabled",
    "acceptanceEnabled",
    "acceptanceCredit",
    "releaseReady",
    "releaseCredit",
    "nativeOrHostedEvidenceClaimed",
    "acceptanceOrReleaseClaimed",
    "phase10PollingDuringParallelExecution",
)}
FLAGS["requiresAcceptedS10_6Reconciliation"] = True

PERSISTENCE = {
    "mode": "PERSISTENT_CANONICAL_EVIDENCE_METADATA_AND_SUCCESSOR_SEQUENCE",
    "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION,
    "recordsSchemaVersion": RECORDS_SCHEMA_VERSION,
    "activeModelCount": ACTIVE_MODEL_COUNT,
    "durableFamilyCount": DURABLE_FAMILY_COUNT,
    "durableFamilies": list(DURABLE_FAMILIES),
    "durableRows": list(DURABLE_ROWS),
    "derivedFamily": DERIVED_FAMILY,
    "sourceRowsMustBeEmpty": True,
    "backfillCreatesEvidenceTruth": False,
    "compatibleRecordsSchemaVersions": [41, 42],
    "backupRestore": "CANONICAL_V4_RECORDS42_FULL_REPLACE_RESTORE",
    "journalReplay": "MUTATION_RECEIPT_AND_SUCCESSOR_REPLAY",
    "searchReport": "DERIVED_ONLY_REBUILT_FROM_CANONICAL_ROWS",
    "deleteErase": "APPEND_ONLY_HISTORY_UNTIL_WORKSPACE_ERASE",
}

# Final hashes are deliberately held until the source/test lane reports a
# stable byte set.  Parent may enable this constant for the final reseal.
FINAL_HASHES_SEALED = True


class ContractError(RuntimeError):
    """Raised for an authority, source, or deterministic projection failure."""


def canonical(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        + "\n"
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_git_text(data: bytes) -> bytes:
    """Return the LF bytes stored for fenced text artifacts in Git."""
    return data.replace(b"\r\n", b"\n")


def sha(value: bytes) -> str:
    return sha256_bytes(value)


def sha256_value(value: Any) -> str:
    return sha256_bytes(canonical(value))


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read(root: Path, relative: str) -> bytes:
    path = root / relative
    if not path.is_file():
        raise ContractError(f"missing fenced input: {relative}")
    return path.read_bytes()


def text(root: Path, relative: str) -> str:
    try:
        return read(root, relative).decode("utf-8")
    except UnicodeDecodeError as error:
        raise ContractError(f"non-UTF-8 fenced input: {relative}") from error


def json_object(root: Path, relative: str) -> dict[str, Any]:
    try:
        value = json.loads(read(root, relative), object_pairs_hook=_strict_pairs)
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid JSON in {relative}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"JSON object required: {relative}")
    return value


def seal(value: dict[str, Any]) -> dict[str, Any]:
    """Add an artifact digest over the exact unsigned pretty projection."""
    result = dict(value)
    result["artifactDigest"] = (
        sha256_bytes(pretty(value)) if FINAL_HASHES_SEALED else None
    )
    return result


def _sealed_field(value: dict[str, Any], field: str) -> str:
    if field not in value or not isinstance(value[field], str):
        raise ContractError(f"sealed field missing: {field}")
    unsigned = dict(value)
    expected = unsigned.pop(field)
    calculated = sha256_bytes(
        (json.dumps(unsigned, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    )
    if calculated != expected:
        raise ContractError(f"coordination {field} seal differs")
    return expected


def _sealed_digest(value: dict[str, Any], expected: str, fields: tuple[str, ...]) -> None:
    matches = [field for field in fields if isinstance(value.get(field), str)]
    if len(matches) != 1 or _sealed_field(value, matches[0]) != expected:
        raise ContractError("coordination authority digest differs")


def _git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout.strip()


def _git_paths(root: Path, *args: str) -> set[str]:
    return {
        line.replace("\\", "/")
        for line in _git(root, *args).splitlines()
        if line.strip()
    }


def observed_changed_paths(root: Path) -> set[str]:
    changed = _git_paths(root, "diff", "--name-only", BASE_HEAD, "--")
    changed |= _git_paths(root, "diff", "--cached", "--name-only", "--")
    changed |= _git_paths(root, "ls-files", "--others", "--exclude-standard")
    return changed


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(
        ["git", "-C", str(root), "cat-file", "-e", f"{BASE_HEAD}:{relative}"],
        capture_output=True,
    ).returncode == 0


def _coordination_root() -> Path:
    # This is a read-only authority input, never the application checkout.
    return Path("C:/AssetRounds-v23-coordination")


def _coordination_file(relative: str) -> Path:
    path = _coordination_root() / relative
    if not path.is_file():
        raise ContractError(f"missing coordination authority: {relative}")
    return path


def _load_coordination(relative: str) -> dict[str, Any]:
    path = _coordination_file(relative)
    try:
        value = json.loads(path.read_bytes(), object_pairs_hook=_strict_pairs)
    except json.JSONDecodeError as error:
        raise ContractError(f"invalid coordination JSON: {relative}: {error}") from error
    if not isinstance(value, dict):
        raise ContractError(f"coordination object required: {relative}")
    return value


def _assert_coordination_authority() -> None:
    coord = _coordination_root()
    if _git(coord, "rev-parse", "HEAD") != COORDINATION_HEAD:
        raise ContractError("coordination authority HEAD differs")
    if _git(coord, "show", "-s", "--format=%T", "HEAD") != COORDINATION_TREE:
        raise ContractError("coordination authority tree differs")

    context = _load_coordination(
        "contexts/V23-P03-C05-attempt-3/BootstrapCardContextV1.json"
    )
    if _sealed_field(context, "contextDigest") != CONTEXT_DIGEST:
        raise ContractError("attempt-3 context digest differs")
    if context.get("cardID") != CARD or context.get("attemptID") != ATTEMPT_ID:
        raise ContractError("attempt-3 context card/attempt differs")
    repository = context.get("repository", {})
    if repository.get("appBaseHead") != BASE_HEAD or repository.get("appBaseTree") != BASE_TREE:
        raise ContractError("attempt-3 application base differs")
    if not isinstance(context.get("persistentChangeMode"), str):
        raise ContractError("attempt-3 persistence mode absent")

    fence = _load_coordination(
        "contexts/V23-P03-C05-attempt-3/BootstrapPathFenceV1.json"
    )
    if _sealed_field(fence, "fenceDigest") != FENCE_DIGEST:
        raise ContractError("attempt-3 fence digest differs")
    if fence.get("cardID") != CARD or fence.get("attemptID") != ATTEMPT_ID:
        raise ContractError("attempt-3 fence card/attempt differs")
    if fence.get("existingPaths") != list(EXISTING_PATHS):
        raise ContractError("attempt-3 existing path order differs")
    if fence.get("newPaths") != [] or fence.get("allowedCreateOrReplacePaths") != list(PATH_FENCE):
        raise ContractError("attempt-3 create/replace fence differs")
    if fence.get("allowedDeletePaths") != [] or fence.get("allowedRenamePaths") != []:
        raise ContractError("attempt-3 delete/rename permissions differ")

    mismatch = _load_coordination(CORRECTION_RECEIPT_PATH)
    _sealed_digest(
        mismatch,
        CORRECTION_RECEIPT_DIGEST,
        ("receiptDigest", "mismatchDigest", "contentDigest"),
    )
    prerequisite = _load_coordination(PREREQUISITE_RECEIPT_PATH)
    _sealed_digest(
        prerequisite,
        PREREQUISITE_DIGEST,
        ("receiptDigest", "prerequisiteDigest", "contentDigest"),
    )
    prior_transition = _load_coordination(PRIOR_TRANSITION_PATH)
    if _sealed_field(prior_transition, "transitionDigest") != PRIOR_TRANSITION_DIGEST:
        raise ContractError("attempt-3 prior transition differs")
    transition = _load_coordination(CORRECTION_TRANSITION_PATH)
    if _sealed_field(transition, "transitionDigest") != HYDRATION_TRANSITION_DIGEST:
        raise ContractError("attempt-3 hydration transition differs")
    if transition.get("sequence") != COORDINATION_CAS_SEQUENCE:
        raise ContractError("attempt-3 hydration sequence differs")
    if transition.get("contextDigest") != CONTEXT_DIGEST or transition.get("pathFenceDigest") != FENCE_DIGEST:
        raise ContractError("attempt-3 hydration authority binding differs")

    ledger = _load_coordination("state/BootstrapExecutionLedgerEnvelopeV1.json")
    if _sealed_field(ledger, "ledgerDigest") != COORDINATION_LEDGER_DIGEST or ledger.get("casSequence") != COORDINATION_CAS_SEQUENCE:
        raise ContractError("attempt-3 coordination ledger differs")
    projection = _load_coordination("projections/ActiveWorkSetProjectionV1.json")
    if _sealed_field(projection, "projectionDigest") != COORDINATION_PROJECTION_DIGEST:
        raise ContractError("attempt-3 coordination projection differs")
    return

def _s10_reservation(root: Path) -> dict[str, Any]:
    relative = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
    value = json_object(root, relative)
    if value.get("contentDigest") != S10_RESERVATION_DIGEST:
        raise ContractError("active S10 reservation digest differs")
    if value.get("reservedPathCount") != S10_RESERVED_PATH_COUNT:
        raise ContractError("active S10 reservation count differs")
    reserved = value.get("reservedPaths")
    if not isinstance(reserved, list):
        raise ContractError("active S10 reservation paths absent")
    if set(PATH_FENCE).intersection(reserved):
        raise ContractError("C05 path fence intersects active S10 reservation")
    return value


def assert_scaffold(root: Path) -> None:
    if len(EXISTING_PATHS) != EXPECTED_EXISTING_PATH_COUNT:
        raise ContractError("C05 existing fence cardinality differs")
    if len(NEW_PATHS) != EXPECTED_NEW_PATH_COUNT:
        raise ContractError("C05 new fence cardinality differs")
    if len(PATH_FENCE) != EXPECTED_FENCE_PATH_COUNT or len(set(PATH_FENCE)) != EXPECTED_FENCE_PATH_COUNT:
        raise ContractError("C05 fence cardinality or uniqueness differs")
    if len(TOOLING_EDIT_PATHS) != 13 or len(SCHEMA_PATHS) != 6 or len(CONTRACT_PATHS) != 5:
        raise ContractError("C05 tooling partition differs")
    if any(path not in EXISTING_PATHS for path in TOOLING_EDIT_PATHS):
        raise ContractError("C05 tooling path is not an inherited fence input")
    if any("s10" in path.lower() or "phase10" in path.lower() for path in PATH_FENCE):
        raise ContractError("C05 fence contains an S10 path")
    if AUTHORIZED_OVERLAP_COUNT != 215 or UNAUTHORIZED_OVERLAP_COUNT != 0:
        raise ContractError("C05 overlap authority differs")
    if _git(root, "rev-parse", "--verify", "HEAD") == "":
        raise ContractError("application HEAD unavailable")
    if subprocess.run(
        ["git", "-C", str(root), "merge-base", "--is-ancestor", BASE_HEAD, "HEAD"],
        capture_output=True,
    ).returncode != 0:
        raise ContractError("application candidate is not a descendant of base")
    for relative in PATH_FENCE:
        if not (root / relative).is_file():
            raise ContractError(f"missing fenced path: {relative}")
    missing = [path for path in EXISTING_PATHS if not _base_exists(root, path)]
    if missing:
        raise ContractError("inherited path absent from application base: " + ",".join(missing))
    present = [path for path in NEW_PATHS if _base_exists(root, path)]
    if present:
        raise ContractError("new path already exists at application base: " + ",".join(present))
    _s10_reservation(root)
    _assert_coordination_authority()


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD,
        "attemptID": ATTEMPT_ID,
        "registerOrdinal": REGISTER_ORDINAL,
        "title": TITLE,
        "appBaseHead": BASE_HEAD,
        "appBaseTree": BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationHead": COORDINATION_HEAD,
        "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "hydrationRevision": 1,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "correctionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "previousContextDigest": PRIOR_CONTEXT_DIGEST,
        "previousPathFenceDigest": PRIOR_FENCE_DIGEST,
        "previousTransitionDigest": PRIOR_TRANSITION_DIGEST,
        "previousLedgerDigest": PRIOR_LEDGER_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "dossierSHA256": DOSSIER_SHA256,
        "dossierByteCount": DOSSIER_BYTES,
        "registerRowSHA256": REGISTER_ROW_SHA256,
        "registerRowByteCount": REGISTER_ROW_BYTES,
        "registerSectionSHA256": REGISTER_SECTION_SHA256,
        "registerSectionByteCount": REGISTER_SECTION_BYTES,
        "inheritedV21BlockSHA256": INHERITED_V21_BLOCK_SHA256,
        "inheritedV21BlockByteCount": INHERITED_V21_BLOCK_BYTES,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "acceptedDependencyMismatchDigest": ACCEPTED_DEPENDENCY_MISMATCH_DIGEST,
        "directPrerequisiteCards": list(DIRECT_PREREQUISITES),
        "optionalCapabilityProviders": list(OPTIONAL_CAPABILITY_PROVIDERS),
        "journeyRefs": list(JOURNEY_REFS),
        "evidenceIDs": list(EVIDENCE_IDS),
        "invalidationConsumers": list(INVALIDATION_CONSUMERS),
        "expectedExistingPathCount": EXPECTED_EXISTING_PATH_COUNT,
        "expectedNewPathCount": EXPECTED_NEW_PATH_COUNT,
        "expectedFencePathCount": EXPECTED_FENCE_PATH_COUNT,
        "priorFenceCount": PRIOR_FENCE_COUNT,
        "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT,
        "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT,
        "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT,
        "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT,
        "s10ReservedPathCount": S10_RESERVED_PATH_COUNT,
    }


def flags() -> dict[str, Any]:
    return dict(FLAGS)


def _common(schema_name: str) -> dict[str, Any]:
    return {
        "schema": schema_name,
        "schemaVersion": 1,
        "cardID": CARD,
        "attemptID": ATTEMPT_ID,
        "title": TITLE,
        "authority": authority(),
        "evidenceIDs": list(EVIDENCE_IDS),
        "selectors": list(SELECTOR_SUFFIXES),
        "persistentChangeMode": PERSISTENCE["mode"],
        "persistentContractSchema": "EVIDENCE_METADATA_V1_V43_RECORDS42",
        "persistence": PERSISTENCE,
        "lifecycleCoverage": list(LIFECYCLE_DIMENSIONS),
        "statusFlags": flags(),
        "provisional": not FINAL_HASHES_SEALED,
        "finalHashesSealed": FINAL_HASHES_SEALED,
        "status": "SEALED" if FINAL_HASHES_SEALED else "PROVISIONAL_UNSEALED",
    }


def _require_tokens(value: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in value]
    if missing:
        raise ContractError(f"{label} missing: {','.join(missing)}")


def _require_patterns(value: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, value, re.I | re.S) is None]
    if missing:
        raise ContractError(f"{label} missing patterns: {','.join(missing)}")


def _require_one_of(value: str, alternatives: Iterable[str], label: str) -> None:
    if not any(option in value for option in alternatives):
        raise ContractError(f"{label} missing alternatives: {','.join(alternatives)}")


def fixture(root: Path) -> dict[str, Any]:
    relative = "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json"
    value = json_object(root, relative)
    raw = read(root, relative)
    if raw != canonical(value) + b"\n":
        raise ContractError("C05 fixture must be canonical compact sorted JSON plus LF")
    if value.get("schema") != "V21P03C05ContentReferenceProvenanceCorpusV1" or value.get("schemaVersion") != 1:
        raise ContractError("C05 fixture identity differs")
    if value.get("testOnly") is not True or value.get("failureDisposition") != "FAIL_CLOSED":
        raise ContractError("C05 fixture safety disposition differs")
    for marker in (
        "BYTE_LENGTH_MISMATCH",
        "UNKNOWN_DIGEST_ALGORITHM",
        "ORPHAN_ASSOCIATION",
        "PROVENANCE_TAMPER",
    ):
        if marker not in raw.decode("utf-8"):
            raise ContractError(f"C05 fixture missing hostile case: {marker}")
    return value


def test_methods(root: Path) -> tuple[str, ...]:
    relative = "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift"
    value = text(root, relative)
    methods = tuple(
        re.findall(r"\bfunc\s+(testV9_15(?:G|A|H|I|R)01[A-Za-z0-9_]*)\s*\(", value)
    )
    if len(methods) != 5 or len(set(methods)) != 5:
        raise ContractError(f"C05 requires exactly five V9_15 selectors, found {methods}")
    if tuple(method[9:12] for method in methods) != SELECTOR_SUFFIXES:
        raise ContractError(f"C05 selector order differs: {methods}")
    return methods


def integration_test_methods(root: Path) -> tuple[str, ...]:
    """Return the four correction-fence tests that exercise integration closure."""
    methods: list[str] = []
    for relative, expected, tokens in INTEGRATION_TEST_BINDINGS:
        value = text(root, relative)
        matches = tuple(re.findall(rf"\bfunc\s+{re.escape(expected)}\s*\(", value))
        if len(matches) != 1:
            raise ContractError(f"C05 integration test selector differs: {relative}:{expected}")
        _require_tokens(value, tokens, f"C05 integration test coverage {expected}")
        methods.append(expected)
    return tuple(methods)


def _assert_integration_contracts(source: dict[str, str]) -> None:
    receipt = source[INTEGRATION_SOURCE_PATHS[0]]
    journal = source[INTEGRATION_SOURCE_PATHS[1]]
    event_contracts = source[INTEGRATION_SOURCE_PATHS[2]]
    projection = source[INTEGRATION_SOURCE_PATHS[3]]
    consumer = source[INTEGRATION_SOURCE_PATHS[4]]
    checkpoint_store = source[INTEGRATION_SOURCE_PATHS[5]]

    _require_tokens(
        receipt,
        (
            "MutationReceiptIdentityV1", "orderedAcceptedProjectionReceipts",
            "maximumAcceptedProjectionCount", "IntegrationEventJournalCoverageV1",
            "evidenceAssociationEvent", "evidenceSequenceRevision",
            "EvidenceMetadataMutationReceiptV1", "mutationReceipt.postImages == images",
            "affectedIdentities", "concurrencyIdentities",
        ),
        "C05 mutation receipt integration",
    )
    _require_patterns(
        receipt,
        (
            r"resultingRevision\.workspaceRevision",
            r"identity\.stableKey",
            r"mutationID\.rawValue\.uuidString\.lowercased\(\)",
            r"receiptIdentities\.insert",
            r"workspaceRevisions\.insert",
        ),
        "C05 mutation receipt ordering/deduplication",
    )

    _require_tokens(
        journal,
        (
            "IntegrationEventJournalCoverageV1", "acceptedReceiptAndJournalOnly",
            "canonicalPersistence = false", "backupIncluded = false",
            "restoreIncluded = false", "exportIncluded = false",
            "reportSourceOfTruth = false", "dropAndRebuild",
            "EvidenceMetadataJournalContractV1", "applyEvidenceMetadata",
            "entityChanges.count == 2", "EvidenceMetadataMutationReceiptV1",
            "productionMaximumEntitiesPerCheckpoint = 100_000",
            "productionMaximumContentEntriesPerCheckpoint = 100_000",
        ),
        "C05 journal integration",
    )

    _require_tokens(
        event_contracts,
        (
            "IntegrationEventContractDefinitionV1", "EvidenceMetadataIntegrationContractV1",
            '"evidence.association_event.v1"', '"evidence.sequence_revision.v1"',
            "evidenceAssociationEvent", "evidenceSequenceRevision",
            "workspaceData", "workspaceInternal", "notRequired",
            "IntegrationEventOrderV1", "sourceReceiptID", "sourceReceiptSHA256",
            "eventID", "eventSHA256", "payloadSHA256",
            "acceptedWorkspaceRevisionThenReceiptIdentityThenPayloadOrdinal",
            "IntegrationEventCanonicalCodecV1", "millisecondsSince1970",
        ),
        "C05 integration event contract",
    )

    _require_tokens(
        projection,
        (
            "evidenceMetadataKinds", "validateEvidenceMetadataReceiptShape",
            "validateEvidenceMetadataReplay", "evidenceAssociationEvent",
            "evidenceSequenceRevision", "receipt.postImages.count == 2",
            "Set(identities.map(\\.kind)) == evidenceMetadataKinds",
            "identities == concurrency", "Set(expected.keys) == Set(concurrency)",
            "image.revision == priorRevision + 1", "validateProjectedStream",
            "seenReceiptIDs", "seenWorkspaceRevisions", "sourceLocalSequence",
            "payloadOrdinal", "maximumEventsPerReplay",
        ),
        "C05 integration projection",
    )

    _require_tokens(
        consumer,
        (
            "IntegrationConformanceConsumerV1", "advance", "rebuild",
            "validateEvidenceMetadataReplay", "recordDerivedConsumerEffects",
            "replaceDerivedProjection", "dropDerivedProjection",
            "acceptedReceipts.count <= ChangeJournalLimitsV1.productionMaximumEntitiesPerCheckpoint",
        ),
        "C05 integration conformance consumer",
    )
    if consumer.count("validateEvidenceMetadataReplay") < 2:
        raise ContractError("C05 integration consumer advance/rebuild coverage is incomplete")

    _require_tokens(
        checkpoint_store,
        (
            "IntegrationProjectionCheckpointStoreV1", "ProjectionCheckpointV1",
            "validateEvidenceMetadataEventPage", "IntegrationEventProjectionV1.evidenceMetadataKinds",
            "recordDerivedConsumerEffects", "replaceDerivedProjection",
            "dropDerivedProjection", "checkpoint",
            "events.count <= maximumStoredEvents", ".atomic",
            "page.count == 2", "kinds == IntegrationEventProjectionV1.evidenceMetadataKinds",
        ),
        "C05 projection checkpoint store",
    )


def _source_texts(root: Path) -> dict[str, str]:
    return {path: text(root, path) for path in SEMANTIC_SOURCE_SWIFT_PATHS}


def _assert_source_contracts(root: Path) -> tuple[str, ...]:
    missing = [path for path in SEMANTIC_INPUT_PATHS if not (root / path).is_file()]
    if missing:
        raise ContractError("C05 source paths missing: " + ",".join(missing))
    methods = test_methods(root)
    integration_methods = integration_test_methods(root)
    fixture_value = fixture(root)
    source = _source_texts(root)
    joined = "\n".join(source.values())
    _assert_integration_contracts(source)

    ref = source["FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift"]
    locator = source["FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift"]
    provenance = source["FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift"]
    local_store = source["FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift"]
    association = source["FieldEvidenceApp/Domain/Evidence/EvidenceAssociationContractsV1.swift"]
    persistence_row = source["FieldEvidenceApp/Domain/Models/EvidenceMetadataPersistenceModelsV1.swift"]
    migration = source["FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift"]
    schemas = source["FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift"]
    lifecycle = source["FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift"]
    sync = source["FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift"]
    writer = source["FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift"]

    _require_tokens(
        ref,
        (
            "ContentReferenceV1", "ContentDigestSetV1", "ContentByteRoleV1",
            "IMMUTABLE_ORIGINAL", "DERIVATIVE", "validateImmutableIdentity",
        ),
        "C05 content reference",
    )
    _require_tokens(
        locator,
        (
            "ContentLocatorV1", "ContentManifestV1", "ContentManifestCanonicalCodecV1",
            "requiredForOpen", "staleReference",
        ),
        "C05 locator/manifest",
    )
    _require_tokens(
        local_store,
        ("LocalContentStoreV1", "replaceLocator", "resolve", "staleReference", "ContentLocatorV1"),
        "C05 local content store",
    )
    _require_tokens(
        provenance,
        (
            "ContentOriginalProvenanceV1", "ContentDerivativeProvenanceV1",
            "ContentProvenanceGraphV1", "IMMUTABLE_ORIGINAL", "SANITIZED",
            "THUMBNAIL", "ANNOTATION", "SEQUENCE", "immutableOriginal",
        ),
        "C05 provenance",
    )
    _require_tokens(
        association,
        (
            "EvidenceAssociationV1", "EvidenceAssociationActionV1", "ContentEvidenceGraphV1",
            "validateOrphanFree", "ASSIGNED", "REASSIGNED", "REMOVED",
            "EvidenceMetadataFailureV1", "EvidenceMetadataLimitsV1",
            "maximumSequenceItems = 32", "maximumCaptionBytes = 1_024",
            "maximumAccessibilityDescriptionBytes = 2_048", "EvidenceCurationPolicyV1",
            "policyID", "maximumSequenceItems", "maximumCaptionBytes",
            "maximumAccessibilityDescriptionBytes", "EvidenceRoleV1",
            'context = "CONTEXT"', 'detail = "DETAIL"', 'before = "BEFORE"',
            'after = "AFTER"', 'other = "OTHER"', "EvidenceReviewedTextProvenanceV1",
            "USER_AUTHORED", "IMPORTED_THEN_REVIEWED", "EvidenceReviewedCaptionV1",
            "EvidenceAccessibilityDescriptionV1", "EvidenceSequenceItemV1",
            "accessibilityDescription", "ordinal", "associationBinding",
            "EvidenceAssociationBindingV1", "EvidenceSequenceReferenceV1",
            "EvidenceSequenceV1", "orderedItems", "predecessor", "sequenceSHA256",
            "validateSuccessor", "EvidenceMetadataMutationV1", "expectedSequenceRevision",
            "sequenceSuccessor", "EvidenceMetadataCanonicalCodecV1", "associationSHA256",
            "expectedEvidenceRevision", "resultingEvidenceRevision",
            "supersedesAssociationEventID", "addingReportingOverflow", "invalidSuccessor",
            "staleAssociation", "invalidDigest",
        ),
        "C05 evidence metadata correction",
    )
    _require_patterns(
        association,
        (
            r"orderedItems\.map\(\\\.ordinal\)\s*==\s*Array\(0\.\.\<orderedItems\.count\)",
            r"predecessor\?\.sequenceID\s*==\s*sequenceID",
            r"resultingEvidenceRevision\s*==\s*nextRevision",
            r"sequenceSuccessor\.revision\s*==\s*nextRevision",
        ),
        "C05 metadata successor/order CAS",
    )
    _require_tokens(
        persistence_row,
        (
            "EvidenceMetadataPersistenceEnrollmentV1", "schemaVersion = 43",
            "recordsSchemaVersion = 42", "durableModelCount = 2",
            "totalSchemaModelCount = 144", 'associationEventFamily = "EVIDENCE_ASSOCIATION_EVENT"',
            'sequenceRevisionFamily = "EVIDENCE_SEQUENCE_REVISION"', "@Model",
            "EvidenceAssociationEventRowV1", "EvidenceSequenceRevisionRowV1",
            "canonicalData", "EvidenceMetadataCanonicalCodecV1.data",
            "EvidenceMetadataCanonicalCodecV1.decode",
        ),
        "C05 persistence rows",
    )
    _require_tokens(
        migration,
        (
            "C05EvidenceCurationMigrationBoundaryV1", "sourcePersistentSchemaVersion = 42",
            "targetPersistentSchemaVersion = 43", "currentRecordsSchemaVersion = 42",
            "compatibleRecordsSchemaVersions = [41, 42]", '"EvidenceAssociationEventRowV1"',
            '"EvidenceSequenceRevisionRowV1"', "newlyAddedRows.count == 2",
            "sourceRowsMustBeEmpty", "backfillCreatesEvidenceTruth",
        ),
        "C05 migration",
    )
    _require_tokens(
        schemas,
        (
            "PersistentSchemaV43", "EvidenceAssociationEventRowV1.self",
            "EvidenceSequenceRevisionRowV1.self",
        ),
        "C05 schema V43/144",
    )
    _require_tokens(joined, ("PersistentSchemaV43.models.count == 144", "StoreSemanticEnvelopeV43"), "C05 V43 projection")
    _require_tokens(
        lifecycle,
        (
            "C05EvidenceCurationPersistentKindPolicyV1",
            "PERSISTENT_MODEL:EvidenceAssociationEventRowV1",
            "PERSISTENT_MODEL:EvidenceSequenceRevisionRowV1",
            "PROJECTION:StoreSemanticEnvelopeV43", "durableKindIDs.count == 2",
            "derivedKindIDs.count == 1",
        ),
        "C05 lifecycle registry",
    )
    _require_tokens(
        sync,
        (
            "PersistentSchemaV43.models.count == 144", "EvidenceAssociationEventRowV1.self",
            "EvidenceSequenceRevisionRowV1.self", "StoreSemanticEnvelopeV43",
        ),
        "C05 sync classification",
    )
    _require_tokens(
        writer,
        (
            "WorkspaceWriterV1", "commitEvidenceMetadata", "EvidenceMetadataMutationReceiptV1",
            "expectedRevision", "mutationID", "WorkspaceMutationRequestV1", "journalStore.commit",
            "execute",
        ),
        "C05 existing canonical writer",
    )

    backup_paths = (
        "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
        "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
        "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
        "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
        "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
        "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
        "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    )
    backup_text = "\n".join(source[path] for path in backup_paths)
    _require_tokens(
        backup_text,
        (
            "C05EvidenceMetadataBackupEnrollmentV1", "evidenceAssociationEvents",
            "evidenceSequenceRevisions", "recordsSchemaVersion", "canonical", "replace",
            "restore", "EvidenceAssociationEventRowV1", "EvidenceSequenceRevisionRowV1",
        ),
        "C05 backup/restore closure",
    )
    journal_text = "\n".join(
        source[path]
        for path in (
            "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
            "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
            "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
        )
    )
    _require_one_of(journal_text.lower(), ("replay", "recover"), "C05 journal replay")
    _require_one_of(journal_text, ("MutationReceipt", "mutationReceipt", "receipt"), "C05 receipt journal")
    report_text = "\n".join(
        source[path]
        for path in (
            "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
            "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
            "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
            "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
        )
    )
    _require_one_of(report_text.lower(), ("evidence", "snapshot", "projection"), "C05 report projection")
    deletion_text = "\n".join(
        source[path]
        for path in (
            "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
            "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
            "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
            "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
        )
    )
    _require_tokens(deletion_text, ("Erase", "erase"), "C05 delete/Erase closure")
    _require_one_of(deletion_text, ("EvidenceMetadata", "EvidenceAssociation", "EvidenceSequence"), "C05 delete metadata closure")

    all_test_text = text(root, "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift")
    _require_tokens(all_test_text, EVIDENCE_SUFFIXES, "C05 test selector families")
    if len(fixture_value.get("negativeCases", [])) < 18:
        raise ContractError("C05 hostile fixture coverage is incomplete")

    # C05 does not introduce a transport, account, cloud, or second canonical
    # writer.  Restrict this scan to its semantic source slices, not unrelated
    # inherited features that happen to share the fence.
    semantic_text = "\n".join((ref, locator, provenance, local_store, association, persistence_row, writer, backup_text))
    for pattern in (
        r"\bURLSession\b", r"\bCloudKit\b", r"\bFirebase\b", r"\bTestFlight\b",
        r"\bAppStore\b", r"\b(?:Remote|Backend)(?:Content|Evidence|Store|Service|Client)\b",
    ):
        if re.search(pattern, semantic_text, re.I):
            raise ContractError(f"C05 prohibited source token: {pattern}")
    _require_tokens(
        semantic_text,
        ("secondByteStoreAllowed = false", "createsSecondByteStore = false", "secondByteStoreOrWriter = false"),
        "C05 single byte-store boundary",
    )
    _require_one_of(semantic_text.lower(), ("sole", "existing"), "C05 single writer boundary")
    return methods


def assert_source_contracts(root: Path) -> tuple[str, ...]:
    return _assert_source_contracts(root)


def require_source_ready(root: Path) -> tuple[str, ...]:
    return _assert_source_contracts(root)


def source_projection(root: Path) -> dict[str, Any]:
    rows = [
        {"path": path, "byteCount": len(read(root, path)), "sha256": sha256_bytes(read(root, path))}
        for path in SOURCE_PATHS
    ]
    integration_methods = integration_test_methods(root)
    return {
        "paths": rows,
        "pathCount": len(rows),
        "sourceSetDigest": sha256_bytes(canonical(rows)),
        "semanticSourcePathCount": len(SOURCE_SWIFT_PATHS),
        "implementationPaths": list(IMPLEMENTATION_PATHS),
        "integrationSourcePaths": list(INTEGRATION_SOURCE_PATHS),
        "integrationSourcePathCount": len(INTEGRATION_SOURCE_PATHS),
        "integrationTestMethods": list(integration_methods),
        "integrationTestCount": len(integration_methods),
        "integrationEventKinds": list(INTEGRATION_EVENT_KINDS),
        "integrationOrderingBasis": INTEGRATION_EVENT_ORDERING_BASIS,
        "integrationLifecycle": INTEGRATION_EVENT_LIFECYCLE,
        "integrationReplayLimit": INTEGRATION_REPLAY_LIMIT,
    }


def _obj(properties: dict[str, Any], required: Iterable[str] | None = None) -> dict[str, Any]:
    keys = list(properties)
    return {
        "type": "object",
        "additionalProperties": False,
        "properties": properties,
        "required": keys if required is None else list(required),
    }


def identifier() -> dict[str, Any]:
    return {"type": "string", "pattern": "^[a-z0-9._-]+$", "maxLength": 128}


def integer() -> dict[str, Any]:
    return {"type": "integer", "minimum": 0}


def instant() -> dict[str, Any]:
    return {"type": "string", "format": "date-time"}


def digest_schema() -> dict[str, Any]:
    digest = _obj(
        {
            "algorithm": {"type": "string", "enum": ["SHA256", "SHA512"]},
            "hexadecimalValue": {
                "type": "string", "pattern": "^[0-9a-f]+$", "minLength": 64, "maxLength": 128,
            },
        }
    )
    digest["allOf"] = [
        {
            "if": {"properties": {"algorithm": {"const": algorithm}}, "required": ["algorithm"]},
            "then": {"properties": {"hexadecimalValue": {"minLength": size, "maxLength": size}}},
        }
        for algorithm, size in (("SHA256", 64), ("SHA512", 128))
    ]
    return digest


def _schema(title: str, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{CARD.lower()}/{title}.schema.json",
        "title": title,
        "x-assetrounds-restoreSemantics": {
            "replace": "EXACT_C05_METADATA",
            "cloneForkNonemptyC05Metadata": "FAIL_CLOSED",
            "cloneForkEmptyC05Metadata": "UNCHANGED",
            "recordsAtOrBelow41": "UNCHANGED",
        },
        **body,
    }


def schemas() -> dict[str, dict[str, Any]]:
    digest = digest_schema()
    required_sha256 = digest_schema()
    required_sha256["properties"]["algorithm"] = {"const": "SHA256"}
    digest_values = {
        "type": "array", "items": digest, "prefixItems": [required_sha256],
        "minItems": 1, "maxItems": 2, "uniqueItems": True,
        "allOf": [
            {"not": {"contains": {"properties": {"algorithm": {"const": algorithm}}, "required": ["algorithm"]}, "minContains": 2}}
            for algorithm in ("SHA256", "SHA512")
        ],
    }
    digest_set = _obj({"values": digest_values})
    media_type = {"type": "string", "pattern": "^[a-z0-9.+-]+/[a-z0-9.+-]+$", "maxLength": 127}
    reference = _obj({
        "schemaVersion": {"const": 1}, "workspaceID": identifier(), "contentID": identifier(),
        "byteLength": integer(), "mediaType": media_type, "digests": digest_set,
        "byteRole": {"type": "string", "enum": ["IMMUTABLE_ORIGINAL", "DERIVATIVE"]}, "createdAt": instant(),
    })
    reference["x-assetrounds-runtimeSemanticConstraints"] = [
        "WORKSPACE_AND_CONTENT_ID_STABLE", "IMMUTABLE_ORIGINAL_BYTES_NEVER_REWRITTEN",
        "SHA256_REQUIRED_AND_UNKNOWN_ALGORITHMS_FAIL_CLOSED",
    ]
    locator = _obj({
        "schemaVersion": {"const": 1}, "locatorID": identifier(), "workspaceID": identifier(),
        "contentID": identifier(), "locatorRevision": integer(), "contentDigest": digest_schema(),
        "expectedByteLength": integer(),
    })
    locator["x-assetrounds-runtimeSemanticConstraints"] = [
        "LOCATOR_REPLACEMENT_USES_EXPECTED_REVISION", "LOCATOR_RESOLUTION_IS_OWNED_STORE_ONLY",
        "STALE_OR_FOREIGN_LOCATORS_FAIL_CLOSED",
    ]
    entry = _obj({
        "contentID": identifier(), "expectedByteLength": integer(), "mediaType": media_type,
        "digest": digest_schema(), "expectedLocatorRevision": integer(), "requiredForOpen": {"type": "boolean"},
    })
    manifest = _obj({
        "schemaVersion": {"const": 1}, "manifestID": identifier(), "workspaceID": identifier(),
        "manifestRevision": integer(), "entries": {"type": "array", "items": entry, "minItems": 1, "maxItems": 256, "uniqueItems": True},
    })
    manifest["x-assetrounds-runtimeSemanticConstraints"] = [
        "ENTRIES_SORTED_BY_CONTENT_ID", "CONTENT_ID_UNIQUE", "REQUIRED_FOR_OPEN_IS_EXPLICIT",
    ]
    target = _obj({
        "workspaceID": identifier(), "kind": {"type": "string", "enum": ["INSPECTION_NODE", "INSPECTION_RESPONSE", "FINDING", "CORRECTIVE_WORK", "ASSET", "WORK_RECORD"]},
        "targetID": identifier(), "targetRevision": integer(),
    })
    association = _obj({
        "schemaVersion": {"const": 1}, "associationEventID": identifier(), "workspaceID": identifier(),
        "evidenceID": identifier(), "expectedEvidenceRevision": integer(), "resultingEvidenceRevision": integer(),
        "mutationID": identifier(), "action": {"type": "string", "enum": ["ASSIGNED", "REASSIGNED", "REMOVED"]},
        "contentID": identifier(), "target": target, "previousContentID": identifier(), "previousTarget": target,
        "supersedesAssociationEventID": identifier(), "actorID": identifier(),
        "reason": {"type": "string", "pattern": ".*\\S.*", "minLength": 1, "maxLength": 1024}, "effectiveAt": instant(),
    }, required=("schemaVersion", "associationEventID", "workspaceID", "evidenceID", "expectedEvidenceRevision", "resultingEvidenceRevision", "mutationID", "action", "actorID", "reason", "effectiveAt"))
    association["allOf"] = [
        {
            "if": {"properties": {"action": {"const": "ASSIGNED"}}, "required": ["action"]},
            "then": {
                "required": ["contentID", "target"],
                "not": {"anyOf": [
                    {"required": ["previousContentID"]},
                    {"required": ["previousTarget"]},
                    {"required": ["supersedesAssociationEventID"]},
                ]},
            },
        },
        {
            "if": {"properties": {"action": {"const": "REASSIGNED"}}, "required": ["action"]},
            "then": {"required": ["contentID", "target", "previousContentID", "previousTarget", "supersedesAssociationEventID"]},
        },
        {
            "if": {"properties": {"action": {"const": "REMOVED"}}, "required": ["action"]},
            "then": {
                "required": ["previousContentID", "previousTarget", "supersedesAssociationEventID"],
                "not": {"anyOf": [{"required": ["contentID"]}, {"required": ["target"]}]},
            },
        },
    ]
    association["x-assetrounds-runtimeSemanticConstraints"] = [
        "RESULTING_REVISION_EQUALS_EXPECTED_PLUS_ONE", "ACTION_REVISION_MATRIX",
        "REASSIGNMENT_CHANGES_BINDING", "TARGET_WORKSPACE_EQUALS_ASSOCIATION_WORKSPACE",
        "METADATA_SEQUENCE_ASSOCIATION_CAS",
    ]
    source_binding = _obj({"contentID": identifier(), "digest": digest_schema()})
    transform_payloads = {"SANITIZED": "sanitized", "THUMBNAIL": "thumbnail", "ANNOTATION": "annotation", "SEQUENCE": "sequence"}
    transform = _obj({
        "kind": {"type": "string", "enum": list(transform_payloads)},
        "sanitized": _obj({"sanitizerID": identifier(), "sanitizerVersion": identifier()}),
        "thumbnail": _obj({"rendererID": identifier(), "rendererVersion": identifier(), "pixelWidth": {"type": "integer", "minimum": 1, "maximum": 16384}, "pixelHeight": {"type": "integer", "minimum": 1, "maximum": 16384}}),
        "annotation": _obj({"rendererID": identifier(), "rendererVersion": identifier(), "annotationManifestSHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}}),
        "sequence": _obj({"assemblerID": identifier(), "assemblerVersion": identifier(), "orderedSourceCount": {"type": "integer", "minimum": 1, "maximum": MAX_SEQUENCE_ITEMS}}),
    }, required=("kind",))
    transform["oneOf"] = [
        {"properties": {"kind": {"const": kind}}, "required": [payload], "not": {"anyOf": [{"required": [other]} for other in transform_payloads.values() if other != payload]}}
        for kind, payload in transform_payloads.items()
    ]
    provenance = _obj({
        "schemaVersion": {"const": 1}, "provenanceID": identifier(), "workspaceID": identifier(),
        "sources": {"type": "array", "items": source_binding, "minItems": 1, "maxItems": MAX_SEQUENCE_ITEMS, "uniqueItems": True},
        "derivativeContentID": identifier(), "derivativeDigest": digest_schema(), "transform": transform,
        "metadataSanitizerID": identifier(), "metadataSanitizerVersion": identifier(), "createdAt": instant(),
    })
    provenance["x-assetrounds-runtimeSemanticConstraints"] = [
        "SOURCE_CONTENT_ID_UNIQUE", "SOURCE_NOT_DERIVATIVE_SELF", "DERIVATIVE_DIGEST_AND_TRANSFORM_REQUIRED",
        "ORIGINALS_IMMUTABLE", "METADATA_SANITIZER_VERSION_BOUND",
    ]
    source_artifact = _obj({"path": {"type": "string", "minLength": 1, "maxLength": 512}, "byteCount": integer(), "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"}})
    receipt = _obj({
        "schemaVersion": {"const": 1}, "cardID": {"const": CARD}, "receiptID": identifier(),
        "persistentSchemaVersion": {"const": PERSISTENT_SCHEMA_VERSION}, "recordsSchemaVersion": {"const": RECORDS_SCHEMA_VERSION},
        "durableFamilyCount": {"const": DURABLE_FAMILY_COUNT}, "durableFamilies": {"const": list(DURABLE_FAMILIES)},
        "registrySHA256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
        "sourceArtifacts": {"type": "array", "items": source_artifact, "minItems": len(SOURCE_PATHS), "maxItems": len(SOURCE_PATHS), "uniqueItems": True},
        "integrationSourcePathCount": {"const": len(INTEGRATION_SOURCE_PATHS)},
        "integrationTestCount": {"const": len(INTEGRATION_TEST_METHODS)},
        "integrationTestMethods": {"const": list(INTEGRATION_TEST_METHODS)},
        "integrationEventKinds": {"const": list(INTEGRATION_EVENT_KINDS)},
        "integrationOrderingBasis": {"const": INTEGRATION_EVENT_ORDERING_BASIS},
        "integrationLifecycle": {"const": INTEGRATION_EVENT_LIFECYCLE},
        "integrationReplayLimit": {"const": INTEGRATION_REPLAY_LIMIT},
        "evidenceIDs": {"type": "array", "items": {"type": "string", "enum": list(EVIDENCE_IDS)}, "minItems": 5, "maxItems": 5, "uniqueItems": True},
        "result": {"const": "PASS"}, "verificationStatus": {"const": "PASS_STATIC_PROVISIONAL"},
        "nativeCompileRan": {"const": False}, "hostedDispatchRan": {"const": False},
        "acceptanceCredit": {"const": False}, "releaseCredit": {"const": False},
        "requiresAcceptedS10_6Reconciliation": {"const": True},
    })
    return {
        path: value for path, value in zip(
            SCHEMA_PATHS,
            (_schema("ContentReferenceV1", reference), _schema("ContentLocatorV1", locator),
             _schema("ContentManifestV1", manifest), _schema("EvidenceAssociationV1", association),
             _schema("ContentDerivativeProvenanceV1", provenance), _schema("ContentEvidenceReceiptV1", receipt)),
        )
    }


def _replication_projection() -> dict[str, Any]:
    return {
        "sourceTruth": "ACCEPTED_MUTATION_RECEIPTS_AND_CHANGE_JOURNAL_V1",
        "receipt": {
            "identityType": "MutationReceiptIdentityV1",
            "projectionInput": "orderedAcceptedProjectionReceipts",
            "maximumAcceptedProjectionCount": INTEGRATION_REPLAY_LIMIT,
            "postImageKinds": ["evidenceAssociationEvent", "evidenceSequenceRevision"],
            "postImageCount": 2,
            "canonicalReceipt": "EvidenceMetadataMutationReceiptV1",
            "duplicateWorkspaceRevisionRejected": True,
        },
        "journal": {
            "contract": "EvidenceMetadataJournalContractV1",
            "commandKind": "applyEvidenceMetadata",
            "entityChangeCount": 2,
            "acceptedReceiptOnly": True,
        },
        "events": {
            "contract": "EvidenceMetadataIntegrationContractV1",
            "eventKinds": list(INTEGRATION_EVENT_KINDS),
            "eventVersion": 1,
            "sensitivity": "WORKSPACE_DATA",
            "visibility": "WORKSPACE_INTERNAL",
            "redaction": "NOT_REQUIRED",
            "orderingBasis": INTEGRATION_EVENT_ORDERING_BASIS,
            "lifecycle": INTEGRATION_EVENT_LIFECYCLE,
        },
        "projection": {
            "receiptShapeValidator": "validateEvidenceMetadataReceiptShape",
            "replayValidator": "validateEvidenceMetadataReplay",
            "streamValidator": "validateProjectedStream",
            "checkpointType": "ProjectionCheckpointV1",
            "maximumEventsPerReplay": INTEGRATION_REPLAY_LIMIT,
        },
        "consumer": {
            "advanceAndRebuild": True,
            "derivedEffectsOnly": True,
            "dropAndRebuild": True,
        },
        "checkpointStore": {
            "type": "IntegrationProjectionCheckpointStoreV1",
            "pageValidator": "validateEvidenceMetadataEventPage",
            "replaceable": True,
            "canonicalTruth": False,
        },
        "testMethods": list(INTEGRATION_TEST_METHODS),
    }


def _semantic_projection(methods: tuple[str, ...]) -> dict[str, Any]:
    return {
        "roles": list(ROLE_VALUES), "textProvenance": list(TEXT_PROVENANCE_VALUES),
        "policy": {"type": "EvidenceCurationPolicyV1", "schemaVersion": 1, "fields": ["policyID", "workspaceID", "maximumSequenceItems", "maximumCaptionBytes", "maximumAccessibilityDescriptionBytes"], "maximumSequenceItems": MAX_SEQUENCE_ITEMS, "maximumCaptionBytes": MAX_CAPTION_BYTES, "maximumAccessibilityDescriptionBytes": MAX_ACCESSIBILITY_DESCRIPTION_BYTES},
        "caption": {"type": "EvidenceReviewedCaptionV1", "provenance": list(TEXT_PROVENANCE_VALUES), "utf8MaximumBytes": MAX_CAPTION_BYTES, "reviewerRequired": True, "reviewedAtRequired": True},
        "accessibilityDescription": {"type": "EvidenceAccessibilityDescriptionV1", "optional": True, "utf8MaximumBytes": MAX_ACCESSIBILITY_DESCRIPTION_BYTES, "reviewerRequired": True, "reviewedAtRequired": True},
        "order": {"type": "EvidenceSequenceItemV1", "ordinalStartsAt": 0, "ordinalsContiguous": True, "sequenceMaximumItems": MAX_SEQUENCE_ITEMS, "fields": ["role", "caption", "accessibilityDescription", "ordinal", "target", "associationBinding"]},
        "sequenceCAS": {"type": "EvidenceSequenceV1", "successor": "predecessor", "expectedRevisionPlusOne": True, "overflowRejected": True, "canonicalDigest": "sequenceSHA256", "codec": "EvidenceMetadataCanonicalCodecV1"},
        "associationCAS": {"type": "EvidenceAssociationV1", "expectedRevisionField": "expectedEvidenceRevision", "resultingRevisionField": "resultingEvidenceRevision", "supersedesField": "supersedesAssociationEventID", "mutationIDRequired": True, "staleOrRemovedBindingRejected": True},
        "mutation": {"type": "EvidenceMetadataMutationV1", "expectedSequenceRevision": True, "sequenceSuccessor": True, "mutationID": True, "existingWorkspaceWriter": "WorkspaceWriterV1"},
        "durableRows": list(DURABLE_ROWS), "durableFamilies": list(DURABLE_FAMILIES), "selectors": list(methods),
        "replication": _replication_projection(),
    }


def _lifecycle_projection() -> dict[str, Any]:
    return {
        "dimensions": list(LIFECYCLE_DIMENSIONS),
        "backup": {"recordsSchemaVersion": RECORDS_SCHEMA_VERSION, "associationField": "evidenceAssociationEvents", "sequenceField": "evidenceSequenceRevisions", "canonicalCodec": "EvidenceMetadataCanonicalCodecV1"},
        "restore": {"materializesRows": list(DURABLE_ROWS), "sourceRowsMustBeEmpty": True, "partialEffect": "FAIL_CLOSED"},
        "replace": {"c05Metadata": "EXACT", "unionOrProjection": False},
        "cloneFork": {"nonemptyC05Metadata": "FAIL_CLOSED", "emptyC05Metadata": "UNCHANGED", "recordsAtOrBelow41": "UNCHANGED", "sourceHistoryCarried": False, "noSecondWriter": True},
        "journalReplay": {"receiptBound": True, "successorReplay": True, "divergence": "FAIL_CLOSED"},
        "searchRebuild": {"canonicalRowsOnly": True, "projectionIsDerived": True},
        "reportProjection": {"metadataOnly": True, "contentBytesRemainExistingAuthority": True},
        "deleteErase": {"ordinaryDelete": "APPEND_ONLY_HISTORY", "workspaceErase": "CLEAR_TWO_DURABLE_FAMILIES_AND_OWNED_DERIVATIVES", "orphanCleanup": True},
        "retention": {"originalsImmutable": True, "derivativesRegenerable": True},
        "compatibility": {"records": [41, 42], "downgrade": "FAIL_CLOSED_PRESERVE_RELEASED_EVIDENCE_METADATA", "forwardFix": True},
        "interruption": {"publication": "ZERO_OR_COMPLETE", "receiptReadBack": True},
        "idempotency": {"mutationID": True, "expectedRevision": True, "receipt": True},
    }


def documents(root: Path, methods: tuple[str, ...], source: dict[str, Any], fixture_value: dict[str, Any]) -> dict[str, dict[str, Any]]:
    shared = {
        "sourceProjection": source,
        "fixtureProjection": {"path": "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json", "sha256": sha256_bytes(read(root, "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json")), "negativeCaseCount": len(fixture_value.get("negativeCases", []))},
        "testMethods": list(methods), "evidenceIDs": list(EVIDENCE_IDS), "semantics": _semantic_projection(methods), "lifecycle": _lifecycle_projection(),
    }
    reference = {**_common("V23P03C05ContentReferenceContractV1"), **shared, "identityFields": ["workspaceID", "contentID"], "locationIndependent": True, "algorithmScopedDigests": True, "immutableOriginal": True, "unknownAlgorithmsFailClosed": True, "byteLengthAndMediaTypeBound": True}
    locator = {**_common("V23P03C05ContentLocatorManifestContractV1"), **shared, "locatorReplaceable": True, "locatorResolvedOnlyByOwnedStore": True, "manifestCanonicalCodec": "ContentManifestCanonicalCodecV1", "manifestEntryLimit": 256, "requiredForOpenExplicit": True, "networkTransferState": False}
    association = {**_common("V23P03C05EvidenceAssociationContractV1"), **shared, "stableEvidenceID": True, "appendOnlyAssociationHistory": True, "workspaceScoped": True, "orphanPrevention": True, "actions": list(fixture_value.get("associationActions", [])), "cas": _semantic_projection(methods)["associationCAS"], "reviewedMetadata": True, "sequenceAndAssociationUseExistingWorkspaceWriter": True}
    provenance = {**_common("V23P03C05DerivativeProvenanceContractV1"), **shared, "originalsImmutable": True, "derivativeKinds": list(fixture_value.get("derivativeKinds", [])), "sourceDigestRequired": True, "derivativeDigestRequired": True, "transformBindingRequired": True, "sanitizerVersionBoundWhenApplicable": True}
    registry_basis = {"schemaVersion": 1, "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION, "recordsSchemaVersion": RECORDS_SCHEMA_VERSION, "activeModelCount": ACTIVE_MODEL_COUNT, "durableFamilies": list(DURABLE_FAMILIES), "durableRows": list(DURABLE_ROWS), "derivedFamily": DERIVED_FAMILY, "declaredContracts": ["ContentReferenceV1", "ContentLocatorV1", "ContentManifestV1", "EvidenceAssociationV1", "ContentDerivativeProvenanceV1", "EvidenceCurationPolicyV1", "EvidenceSequenceV1", "EvidenceMetadataMutationV1"], "writer": "WorkspaceWriterV1"}
    receipt = {**_common("V23P03C05ContentEvidenceReceiptV1"), **shared, "receiptID": "v23-p03-c05-attempt-3-static-receipt", "registrySHA256": sha256_bytes(canonical(registry_basis)), "fixtureSHA256": sha256_bytes(read(root, "FieldEvidenceAppTests/Fixtures/V21/Content/V21P03C05ContentReferenceProvenanceCorpusV1.json")), "persistentSchemaVersion": PERSISTENT_SCHEMA_VERSION, "recordsSchemaVersion": RECORDS_SCHEMA_VERSION, "durableFamilyCount": DURABLE_FAMILY_COUNT, "durableFamilies": list(DURABLE_FAMILIES), "sourceArtifacts": [{"path": path, "byteCount": len(read(root, path)), "sha256": sha256_bytes(read(root, path))} for path in SOURCE_PATHS], "integrationSourcePathCount": len(INTEGRATION_SOURCE_PATHS), "integrationTestCount": len(INTEGRATION_TEST_METHODS), "integrationTestMethods": list(INTEGRATION_TEST_METHODS), "integrationEventKinds": list(INTEGRATION_EVENT_KINDS), "integrationOrderingBasis": INTEGRATION_EVENT_ORDERING_BASIS, "integrationLifecycle": INTEGRATION_EVENT_LIFECYCLE, "integrationReplayLimit": INTEGRATION_REPLAY_LIMIT, "result": "PASS", "verificationStatus": "PASS_STATIC_PROVISIONAL"}
    return {CONTRACT_PATHS[0]: seal(reference), CONTRACT_PATHS[1]: seal(locator), CONTRACT_PATHS[2]: seal(association), CONTRACT_PATHS[3]: seal(provenance), CONTRACT_PATHS[4]: seal(receipt)}


def _manifest_status(path: str) -> str:
    if FINAL_HASHES_SEALED:
        return "SEALED_TOOLING" if path in TOOLING_EDIT_PATHS else "SEALED_SOURCE"
    return "PROVISIONAL_TOOLING" if path in TOOLING_EDIT_PATHS else "PROVISIONAL_SOURCE"


def manifest(root: Path, rendered: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    pending = []
    for path in MANIFEST_INPUT_PATHS:
        if path in rendered:
            data = rendered[path]
        elif (root / path).is_file():
            data = (root / path).read_bytes()
        else:
            pending.append(path)
            continue
        # Git stores these fenced text artifacts with LF line endings even when
        # a Windows checkout materializes selected scripts as CRLF.  Seal the
        # canonical Git-text bytes so a fresh checkout reproduces the same
        # manifest as the authoring worktree.
        canonical_data = canonical_git_text(data)
        rows.append({"path": path, "byteCount": len(canonical_data), "sha256": sha256_bytes(canonical_data), "status": _manifest_status(path)})
    value = {**_common("V23P03C05ToolingManifestV1"), "pathFence": list(PATH_FENCE), "existingPaths": list(EXISTING_PATHS), "newPaths": list(NEW_PATHS), "toolingEditPaths": list(TOOLING_EDIT_PATHS), "sourcePaths": list(SOURCE_PATHS), "generatedPaths": list(GENERATED_PATHS), "existingPathCount": len(EXISTING_PATHS), "newPathCount": len(NEW_PATHS), "fencePathCount": len(PATH_FENCE), "manifestInputCount": len(MANIFEST_INPUT_PATHS), "sourcePathCount": len(SOURCE_PATHS), "toolingPathCount": len(TOOLING_EDIT_PATHS), "generatedArtifactCount": len(GENERATED_PATHS), "artifactCount": len(rows), "pendingFencePaths": pending, "pendingArtifactCount": len(pending), "authorizedOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "s10ReservationOverlapCount": S10_RESERVATION_OVERLAP_COUNT, "hashDisposition": "SEALED_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED" if FINAL_HASHES_SEALED else "PROVISIONAL_CURRENT_FENCE_INPUTS_MANIFEST_SELF_EXCLUDED", "files": rows, "artifactSetDigest": sha256_bytes(canonical(rows)), "sourceProjection": source_projection(root), "fenceProof": {"baseHead": BASE_HEAD, "baseTree": BASE_TREE, "pathFenceDigest": FENCE_DIGEST, "allowedPathCount": EXPECTED_FENCE_PATH_COUNT, "existingPathCount": EXPECTED_EXISTING_PATH_COUNT, "newPathCount": EXPECTED_NEW_PATH_COUNT, "priorFenceCount": PRIOR_FENCE_COUNT, "priorOwnedPathCount": PRIOR_OWNED_PATH_COUNT, "authorizedPriorFenceOverlapCount": AUTHORIZED_OVERLAP_COUNT, "unauthorizedPriorFenceOverlapCount": UNAUTHORIZED_OVERLAP_COUNT, "activeS10ReservationDigest": S10_RESERVATION_DIGEST, "activeS10Overlap": False}}
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    methods = require_source_ready(root)
    source = source_projection(root)
    fixture_value = fixture(root)
    rendered: dict[str, bytes] = {path: pretty(value) for path, value in schemas().items()}
    rendered.update({path: pretty(value) for path, value in documents(root, methods, source, fixture_value).items()})
    rendered[MANIFEST_PATH] = pretty(manifest(root, rendered))
    return rendered


__all__ = [
    "CARD", "FINAL_HASHES_SEALED", "PATH_FENCE", "EXISTING_PATHS", "NEW_PATHS", "TOOLING_EDIT_PATHS",
    "SCRIPT_PATHS", "SCHEMA_PATHS", "CONTRACT_PATHS", "GENERATED_PATHS", "OUTPUT_PATHS", "MANIFEST_PATH",
    "MANIFEST_INPUT_PATHS", "SOURCE_PATHS", "INTEGRATION_SOURCE_PATHS", "INTEGRATION_TEST_METHODS",
    "INTEGRATION_TEST_BINDINGS", "INTEGRATION_EVENT_KINDS", "INTEGRATION_EVENT_ORDERING_BASIS",
    "INTEGRATION_EVENT_LIFECYCLE", "INTEGRATION_REPLAY_LIMIT", "EVIDENCE_IDS", "SELECTOR_SUFFIXES", "FLAGS", "PERSISTENCE",
    "ContractError", "canonical", "pretty", "sha256_bytes", "canonical_git_text", "sha", "authority", "flags", "assert_scaffold",
    "assert_source_contracts", "require_source_ready", "source_projection", "test_methods", "integration_test_methods",
    "observed_changed_paths",
    "all_outputs",
]
