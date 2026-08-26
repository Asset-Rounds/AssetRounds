#!/usr/bin/env python3
"""Deterministic tooling contracts for V23-P01-C06.

The card is intentionally represented as data rather than as a second source of
product behaviour.  The contract, graph fixture, and manifests are generated
from the same constants so that a source reseal after the production slice is
an ordinary ``--apply`` followed by ``--check``.  Missing source files are
recorded as honest ``PENDING`` bindings while the card is being hydrated; no
acceptance or release credit is inferred from that state.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


CARD = "V23-P01-C06"
BASE_HEAD = "417aec8af085ac4e01d4b73c822ba99511a14611"
BASE_TREE = "147f18696ca118a577b000c85850b47ddad82bfc"
COORDINATION_HEAD = "438505bfbe87613ad3afa2309ff978d6a15f8f2a"
COORDINATION_CAS_SEQUENCE = 74
COORDINATION_LEDGER_DIGEST = "201eb3d1d49742fc7412ca4d41d722162ca5451857f188c9ed31cb7999a7b4b0"
TRANSITION_DIGEST = "a11aeaf21b80f95eeb5a9c047effeccbad30b84c54f7c8260330e2b6bce3eca7"
CONTEXT_DIGEST = "ef201489b04abbbbddec862efd462bdba4afcb4a43b50e57f2e1f285bde4f4ad"
FENCE_DIGEST = "914d1e54c267c4069f2f0c89920107012ebbf372301adccf9d79b7a50cf4819c"
PREREQUISITE_DIGEST = "8bb9b15619b5d5029ce8947c9ff345fcbd15259699e26fff91863d81c1c3d8d3"
CORRECTION_RECEIPT_DIGEST = "a8935b4a310b37db1794417d2c9c2538654e27cd43a4d3c02140b7e0aec79099"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DOSSIER_DIGEST = "41ab6dd6355216800cce04b50e2f9d2a28ee43e7dfe4609aa2063e7483a4b739"
INHERITED_DIGEST = "62e25505dd8d40524b6a5a2f8ef25116f78be7e7bc0c85b887ae5a0ca5cabef3"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DISPOSITION_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_RECEIPT_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"
SUPERCEDES_FENCE_DIGEST = "6d5cec5dd55f856160c824d8bec254ee35207d366b184a52fc84900a83e55cdd"
PRIOR_COORDINATION_LEDGER_DIGEST = "d285fc795036fc441a7ee796962232e04d6c7f4606576691b463e253467c7467"


# The first thirty paths are the source projection (including the fixture).
# The final eight are the tooling artifacts.  This ordering is the corrected
# authority's exact 38-path fence; do not sort or regroup it.
SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Deletion/V21P01C06DeletionGraphV1.json",
]
TOOL_PATHS = [
    "Scripts/v23/p01_c06_contracts.py",
    "Scripts/v23/generate_p01_c06_contracts.py",
    "Scripts/v23/verify_p01_c06_contracts.py",
    "Scripts/v23/deletion-ledger.schema.json",
    "Scripts/v23/deletion-graph-fixture.schema.json",
    "docs/design/v23/tooling/V23P01C06DeletionRightsContractV1.json",
    "docs/design/v23/tooling/V23P01C06DeletionGraphManifestV1.json",
    "docs/design/v23/tooling/V23-P01-C06-tooling-manifest.json",
]
FULL_FENCE = SOURCE_PATHS + TOOL_PATHS

FIXTURE_PATH = SOURCE_PATHS[-1]
CONTRACT_SCHEMA = TOOL_PATHS[3]
FIXTURE_SCHEMA = TOOL_PATHS[4]
CONTRACT_ARTIFACT = TOOL_PATHS[5]
GRAPH_ARTIFACT = TOOL_PATHS[6]
MANIFEST = TOOL_PATHS[7]


REGISTERED_KINDS = [
    {"kind": "site", "persistentEntity": "Site", "identityField": "siteID", "scope": "workspace"},
    {"kind": "asset", "persistentEntity": "Asset", "identityField": "assetID", "scope": "site"},
    {"kind": "workflowRecord", "persistentEntity": "WorkflowRecord", "identityField": "recordID", "scope": "asset"},
    {"kind": "evidenceFile", "persistentEntity": "EvidenceFile", "identityField": "evidenceFileID", "scope": "workflowRecord"},
    {"kind": "issue", "persistentEntity": "Issue", "identityField": "issueID", "scope": "asset"},
    {"kind": "packet", "persistentEntity": "Packet", "identityField": "packetID", "scope": "asset"},
    {"kind": "report", "persistentEntity": "Report", "identityField": "reportID", "scope": "packet"},
]
REGISTERED_KIND_NAMES = [row["kind"] for row in REGISTERED_KINDS]

TOMBSTONE_FIELDS = ["schemaVersion", "identity", "deletedAt"]
FORBIDDEN_TOMBSTONE_FIELDS = [
    "content", "payload", "title", "label", "address", "note", "notes", "photo", "snapshot",
    "pdf", "personalContent", "auditNarrative", "retentionReason", "ownerName", "body",
]

DELETION_MODES = [
    {
        "mode": "EMPTY_INSTALL",
        "destinationPrecondition": "NO_CANONICAL_WORKSPACE",
        "ledgerOperation": "UNION_INCOMING_TOMBSTONES_DELETION_WINS",
        "incomingLiveDisposition": "REJECT_IF_CURRENT_LEDGER_TOMBSTONE",
        "incomingTombstoneDisposition": "PRESERVE",
        "existingDestinationDisposition": "NONE",
        "emptySiteDisposition": "PRESERVE_IF_FINAL_ASSET_DELETED",
        "sourceReplicaDisposition": "PROVENANCE_ONLY_NEVER_ACTIVE",
    },
    {
        "mode": "REPLACE_EXISTING",
        "destinationPrecondition": "EXPLICIT_MATCHED_DESTINATION_AUTHORITY",
        "ledgerOperation": "UNION_CURRENT_AND_INCOMING_DELETION_WINS",
        "incomingLiveDisposition": "REJECT_IF_CURRENT_LEDGER_TOMBSTONE",
        "incomingTombstoneDisposition": "PRESERVE",
        "existingDestinationDisposition": "REPLACE_CONTENT_ONLY",
        "emptySiteDisposition": "PRESERVE_IF_FINAL_ASSET_DELETED",
        "sourceReplicaDisposition": "PROVENANCE_ONLY_NEVER_ACTIVE",
    },
    {
        "mode": "CLONE",
        "destinationPrecondition": "EXPLICIT_CLONE_AUTHORIZATION",
        "ledgerOperation": "COPY_INCOMING_TOMBSTONES_DELETION_WINS",
        "incomingLiveDisposition": "MATERIALIZE_ONLY_WITHOUT_TOMBSTONE",
        "incomingTombstoneDisposition": "PRESERVE",
        "existingDestinationDisposition": "NEW_GENERATION_ONLY",
        "emptySiteDisposition": "PRESERVE_IF_FINAL_ASSET_DELETED",
        "sourceReplicaDisposition": "PROVENANCE_ONLY_NEVER_ACTIVE",
    },
    {
        "mode": "FORK",
        "destinationPrecondition": "EXPLICIT_FORK_AUTHORIZATION_AND_LINEAGE",
        "ledgerOperation": "COPY_INCOMING_TOMBSTONES_DELETION_WINS",
        "incomingLiveDisposition": "MATERIALIZE_ONLY_WITHOUT_TOMBSTONE",
        "incomingTombstoneDisposition": "PRESERVE",
        "existingDestinationDisposition": "NEW_GENERATION_ONLY",
        "emptySiteDisposition": "PRESERVE_IF_FINAL_ASSET_DELETED",
        "sourceReplicaDisposition": "PROVENANCE_ONLY_NEVER_ACTIVE",
    },
]
# Readable aliases used by card-level checks and downstream tooling.  The
# canonical serialized field remains ``deletionModes``.
MODES = DELETION_MODES
KIND_REGISTRY = REGISTERED_KINDS

ERASE_PHASES = [
    "empty_generation_prepared",
    "pointer_switched",
    "session_activated",
    "cleanup_complete",
]

ERASE_PREPARATION_PROTOCOL = {
    "schema": "ErasePreparationV2",
    "markerWriteOrder": "DURABLE_MARKER_BEFORE_TARGET_GENERATION",
    "targetBinding": "MARKER_BINDS_TARGET_EMPTY_GENERATION",
    "noIntentOrphanRecovery": "RECONCILE_MARKER_THEN_DISCARD_OR_RETAIN_LEDGER",
    "coreDiscardSeam": "MANIFEST_FIRST_THEN_TARGET_ROOT",
    "ledgerClearPredicate": "VERIFIED_COMPLETE_ERASE_ONLY",
}

FAILURE_CASES = [
    ("OLD_ARCHIVE_RESURRECTION", "REJECT_LIVE_WRITE_WHEN_LEDGER_TOMBSTONE_EXISTS"),
    ("REVOKED_KIND_RESOLUTION", "FAIL_CLOSED_PRESERVE_LEDGER"),
    ("PARTIAL_GRAPH_DELETION", "RETAIN_TOMBSTONES_AND_FORWARD_CLEANUP"),
    ("LEDGER_CLEAR_OUTSIDE_VERIFIED_ERASE", "REJECT_AND_PRESERVE_LEDGER"),
    ("UNKNOWN_RECORD_KIND", "FAIL_CLOSED_PRESERVE_LEDGER"),
    ("UNKNOWN_OWNERSHIP", "FAIL_CLOSED_PRESERVE_LEDGER"),
    ("INTERRUPTED_ERASE", "RELAUNCH_FORWARD_RECOVERY_UNTIL_COMPLETE"),
    ("ORPHAN_CLEANUP_LEDGER_MUTATION", "REJECT_SEPARATE_AUTHORITIES"),
    ("INFERRED_SITE_DELETION_AFTER_LAST_ASSET", "PRESERVE_EMPTY_SITE"),
]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]


# Symbols are semantic anchors, not line numbers.  A missing file is pending
# during parallel hydration; a present file with missing anchors is reported as
# pending as well and cannot be mistaken for a complete source projection.
SOURCE_SPECS = [
    (SOURCE_PATHS[0], ["DeletionLedgerV2", "DeletionRecordKindV2", "DeletionIdentityV2", "DeletionLedgerEntryV2", "union", "canonicalData"]),
    (SOURCE_PATHS[1], ["ReplacementRestoreRule", "ReplacementRestorePlan", "currentOnlyTombstones", "incomingPackets", "contentDeletedAt"]),
    (SOURCE_PATHS[2], ["RestoreIdentityV1", "BackupRestoreMode", "case .emptyInstall", "case .replaceExisting", "case .clone", "case .fork"]),
    (SOURCE_PATHS[3], ["V4BackupPacketDTO", "contentDeletedAt", "evaluationCounted"]),
    (SOURCE_PATHS[4], ["@Model", "DeletionLedgerRow", "WorkflowRecord", "EvidenceFile", "Issue", "Packet", "Report"]),
    (SOURCE_PATHS[5], ["DeletionIntentV1", "countedPacketTombstones", "database_committed"]),
    (SOURCE_PATHS[6], ["EraseIntentV1", "EraseIntentPhaseV1", "empty_generation_prepared", "cleanup_complete"]),
    (SOURCE_PATHS[7], ["WholeSignDeletionRule", "siteIDToDelete", "countedPacketTombstones"]),
    (SOURCE_PATHS[8], ["BackupCanonicalDecoderV1", "decodeManifest", "decodeRecords"]),
    (SOURCE_PATHS[9], ["BackupCanonicalEncoderV1", "encodeManifest", "encodeRecords"]),
    (SOURCE_PATHS[10], ["BackupExportService", "prepareStreaming", "consumedEvaluationRootIDs"]),
    (SOURCE_PATHS[11], ["BackupImportService", "stageAndValidate", "stageAndValidateStreamingArchive", "validateManifestBounds"]),
    (SOURCE_PATHS[12], ["BackupPackageValidatorV1", "ValidatedV4BackupPackageV1", "contentDeletedAt"]),
    (SOURCE_PATHS[13], ["BackupRestoreService", "func restore(", "ReplacementRestoreRule", "DeletionLedgerV2", "reconcileAtStartup"]),
    (SOURCE_PATHS[14], ["DeletionLedgerStore", "snapshot", "stageUnion", "requireContains"]),
    (SOURCE_PATHS[15], ["OrphanFileCleanupService", "reconcile", "referencedRelativePaths"]),
    (SOURCE_PATHS[16], ["EraseAllService", "ErasePreparationV2", "completeCleanup", "reconcileAtStartup", "discardPreparation", "DeletionLedgerStore", "cleanupComplete"]),
    (SOURCE_PATHS[17], ["EraseIntentStore", "ErasePreparationV2", "EraseIntentCodecV1", "createPreparation", "loadPreparation", "removePreparation", "nextPhase"]),
    (SOURCE_PATHS[18], ["WholeSignDeletionService", "DeletionLedgerStore", "stageUnion", "databaseCommitted"]),
    (SOURCE_PATHS[19], ["PersistentSchemaV3", "DeletionLedgerRow", "V3_TOMBSTONES"]),
    (SOURCE_PATHS[20], ["StoreGenerationFactory", "backfillV3DeletionLedger", "DeletionLedgerStore"]),
    (SOURCE_PATHS[21], ["StoreMigrationPhaseV1", "CurrentGenerationPointerV3", "storeSchemaVersion"]),
    (SOURCE_PATHS[22], ["StoreMigrationJournalStoreV1", "reconcileDeletionTombstones", "StoreMigrationFailure"]),
    (SOURCE_PATHS[23], ["StoreSessionCoordinator", "workspaceID", "replicaID"]),
    (SOURCE_PATHS[24], ["S6_1DeletionGraphTests", "test"]),
    (SOURCE_PATHS[25], ["V9_01VersionedSchemaIdentityTests", "PersistentSchemaV3", "DeletionLedgerRow"]),
    (SOURCE_PATHS[26], ["V9_03MigrationRecoveryTests", "StoreMigrationJournalStoreV1", "StoreMigrationFailure", "PersistentSchemaV1"]),
    (SOURCE_PATHS[27], ["V9_06DeletionRightsTests", "testV9_06G01", "DeletionLedgerStore", "DeletionLedgerEntryV2", "BackupRestoreMode"]),
    (SOURCE_PATHS[28], ["V9_06DeletionArchiveIntegrationTests", "testV9_06I01", "OrphanFileCleanupService", "EraseAllFailurePoint", "DeletionLedgerStore"]),
    (SOURCE_PATHS[29], ["V21P01C06DeletionGraphV1", '"registeredKinds"', '"cases"']),
]

REGISTERED_KIND_POLICY = {
    "currentPersistentTagKindPresent": False,
    "dormantTagEntityAuthorized": False,
    "coverageRequirement": "ALL_CURRENTLY_REGISTERED_KINDS",
    "futureRegistrationRequirement": "ADD_DELETION_KIND_AND_REVOCATION_CONTRACT_WITH_REGISTRATION",
}

SEMANTIC_SCOPE = {
    "tombstonePolicy": "DELETION_WINS_PRIVACY_MINIMAL_INDEFINITE_UNTIL_VERIFIED_COMPLETE_ERASE",
    "ledgerClearingAuthority": "VERIFIED_COMPLETE_ERASE_ONLY",
    "orphanCleanup": "SEPARATE_AND_CANNOT_MUTATE_DELETION_LEDGER",
    "emptySitePolicy": "PRESERVE_AFTER_FINAL_ASSET_DELETION",
    "unknownRecordKindPolicy": "FAIL_CLOSED_PRESERVE_LEDGER",
    "currentPersistentTagKindPresent": False,
    "dormantTagEntityAuthorized": False,
    "deletionRegistryCoverage": "ALL_CURRENTLY_REGISTERED_KINDS",
    "futurePersistentKindRegistration": "MUST_ADD_DELETION_KIND_AND_REVOCATION_CONTRACT",
}


class ContractError(ValueError):
    """Raised when deterministic card evidence is absent or inconsistent."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "physicalEvidenceComplete": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True,
        "phase10PollingDuringParallelExecution": False,
    }


def authority() -> dict[str, Any]:
    return {
        "branch": "phase/v23-expansion",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "priorCoordinationLedgerDigest": PRIOR_COORDINATION_LEDGER_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "authorityCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "hydrationCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "registerRowDigest": REGISTER_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DISPOSITION_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "ownerParallelOverrideReason": "OWNER_AUTHORIZED_PRE_S10_6_ORDERED_IMPLEMENTATION_V4",
        "lineage": "REFINED_WITHOUT_LOSS",
        "directPrerequisite": "V23-P01-C05",
        "invalidationConsumer": "V23-P01-C07",
        "conformanceSubjectSet": "KernelConformanceSubjectSetV1",
        "activeS10OverlapCount": 0,
        "authorizedPriorFenceOverlapCount": 32,
        "deterministicEvidenceIDs": EVIDENCE_IDS,
        "acceptedS10_6BaselineDigest": None,
        "hydrationRevision": 2,
        "supersedesFenceDigest": SUPERCEDES_FENCE_DIGEST,
        "registeredKindPolicy": REGISTERED_KIND_POLICY,
    }


def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path, symbols in SOURCE_SPECS:
        item = root / path
        # The fixture is itself generated by this module.  Resolve its
        # deterministic bytes in memory so a first ``--apply`` can bootstrap
        # the source projection without a circular read of a missing file.
        if path == FIXTURE_PATH:
            data = pretty(deletion_fixture())
            text = data.decode("utf-8")
            missing = [symbol for symbol in symbols if symbol not in text]
            rows.append({
                "path": path,
                "role": "FENCED_PRODUCT_TEST_OR_FIXTURE_SOURCE",
                "status": "BOUND" if not missing else "PENDING",
                "bytes": len(data),
                "sha256": sha(data),
                "requiredSymbols": symbols,
                "missingSymbols": missing,
            })
            continue
        if not item.is_file():
            rows.append({
                "path": path,
                "role": "FENCED_PRODUCT_TEST_OR_FIXTURE_SOURCE",
                "status": "PENDING",
                "bytes": None,
                "sha256": None,
                "requiredSymbols": symbols,
                "missingSymbols": symbols,
            })
            continue
        data = item.read_bytes()
        text = data.decode("utf-8")
        missing = [symbol for symbol in symbols if symbol not in text]
        rows.append({
            "path": path,
            "role": "FENCED_PRODUCT_TEST_OR_FIXTURE_SOURCE",
            "status": "BOUND" if not missing else "PENDING",
            "bytes": len(data),
            "sha256": sha(data),
            "requiredSymbols": symbols,
            "missingSymbols": missing,
        })
    return rows


def source_binding_complete(bindings: list[dict[str, Any]]) -> bool:
    return bool(bindings) and all(row["status"] == "BOUND" for row in bindings)


def _node(kind: str, ident: str, parent: str | None = None) -> dict[str, Any]:
    value: dict[str, Any] = {"kind": kind, "id": ident}
    if parent is not None:
        value["parentID"] = parent
    return value


def deletion_fixture() -> dict[str, Any]:
    site = "00000000-0000-4000-8000-000000000001"
    asset = "00000000-0000-4000-8000-000000000002"
    packet = "00000000-0000-4000-8000-000000000003"
    workflow_record = "00000000-0000-4000-8000-000000000004"
    evidence_file = "00000000-0000-4000-8000-000000000005"
    issue = "00000000-0000-4000-8000-000000000006"
    report = "00000000-0000-4000-8000-000000000007"
    second_site = "00000000-0000-4000-8000-000000000008"
    second_asset = "00000000-0000-4000-8000-000000000009"
    second_packet = "00000000-0000-4000-8000-00000000000a"
    tombstone_at = "2026-01-02T03:04:05Z"
    entries = [
        {"schemaVersion": 2, "identity": {"kind": kind, "id": ident}, "deletedAt": tombstone_at}
        for kind, ident in (
            ("asset", asset), ("evidenceFile", evidence_file), ("issue", issue),
            ("packet", packet), ("report", report), ("workflowRecord", workflow_record),
        )
    ]
    entries.sort(key=lambda row: (row["identity"]["kind"], row["identity"]["id"]))
    before = [
        _node("site", site), _node("asset", asset, site), _node("workflowRecord", workflow_record, asset),
        _node("evidenceFile", evidence_file, workflow_record), _node("issue", issue, asset),
        _node("packet", packet, asset), _node("report", report, packet),
        _node("site", second_site), _node("asset", second_asset, second_site), _node("packet", second_packet, second_asset),
    ]
    after = [
        _node("site", site), _node("site", second_site), _node("asset", second_asset, second_site),
        _node("packet", second_packet, second_asset),
    ]
    cases = [
        {"id": "DELETE_THEN_RESTORE_ALL_MODES", "family": "G01", "evidenceID": f"{CARD}-G01", "modes": [row["mode"] for row in DELETION_MODES], "expectedOutcome": "TOMBSTONE_WINS_AND_EMPTY_SITE_SURVIVES"},
        {"id": "FINAL_ASSET_DELETE_PRESERVES_EMPTY_SITE", "family": "G01", "evidenceID": f"{CARD}-G01", "modes": ["EMPTY_INSTALL", "REPLACE_EXISTING", "CLONE", "FORK"], "expectedOutcome": "SITE_REMAINS_VALID_WITHOUT_ASSETS"},
        {"id": "DELETE_RECREATE_DISTINCT_IDENTITY", "family": "A01", "evidenceID": f"{CARD}-A01", "modes": ["REPLACE_EXISTING"], "expectedOutcome": "NEW_IDENTITY_MATERIALIZES_WHILE_OLD_TOMBSTONE_REMAINS"},
        {"id": "ORPHAN_CLEANUP_AFTER_GRAPH_DELETE", "family": "A01", "evidenceID": f"{CARD}-A01", "modes": ["ALL"], "expectedOutcome": "FILES_CLEANED_BY_SEPARATE_SERVICE"},
        {"id": "OLD_ARCHIVE_RESURRECTION", "family": "H01", "evidenceID": f"{CARD}-H01", "modes": ["ALL"], "expectedOutcome": "REJECT_LIVE_RECORD_AGAINST_TOMBSTONE"},
        {"id": "REVOKED_KIND_AND_UNKNOWN_KIND", "family": "H01", "evidenceID": f"{CARD}-H01", "modes": ["ALL"], "expectedOutcome": "FAIL_CLOSED_PRESERVE_LEDGER"},
        {"id": "NON_ERASE_LEDGER_CLEAR", "family": "H01", "evidenceID": f"{CARD}-H01", "modes": ["ALL"], "expectedOutcome": "REJECT_UNVERIFIED_CLEAR"},
        {"id": "PARTIAL_GRAPH_DELETION", "family": "I01", "evidenceID": f"{CARD}-I01", "modes": ["ALL"], "expectedOutcome": "TOMBSTONES_RETAINED_AND_FORWARD_CLEANUP"},
        {"id": "INTERRUPTED_ERASE_EACH_PHASE", "family": "I01", "evidenceID": f"{CARD}-I01", "modes": ["ALL"], "expectedOutcome": "RELAUNCH_FORWARD_RECOVERY"},
        {"id": "ERASE_PREPARATION_MARKER_BEFORE_TARGET", "family": "I01", "evidenceID": f"{CARD}-I01", "modes": ["ALL"], "expectedOutcome": "DURABLE_MARKER_PRECEDES_TARGET_GENERATION"},
        {"id": "CORE_DISCARD_SEAM_MANIFEST_FIRST", "family": "I01", "evidenceID": f"{CARD}-I01", "modes": ["ALL"], "expectedOutcome": "DISCARD_PREPARED_TARGET_ONLY_AFTER_MANIFEST_PROOF"},
        {"id": "DISABLED_DELETE_PATH_RETAIN_TOMBSTONES", "family": "R01", "evidenceID": f"{CARD}-R01", "modes": ["ALL"], "expectedOutcome": "NO_LEDGER_CLEAR_UNTIL_VERIFIED_ERASE"},
        {"id": "VERIFIED_COMPLETE_ERASE_CLEARS_LEDGER", "family": "R01", "evidenceID": f"{CARD}-R01", "modes": ["ALL"], "expectedOutcome": "EMPTY_GENERATION_AND_LEDGER_CLEAR"},
        {"id": "NO_INTENT_ORPHAN_PREPARATION_RECOVERY", "family": "R01", "evidenceID": f"{CARD}-R01", "modes": ["ALL"], "expectedOutcome": "RECONCILE_PREPARATION_MARKER_WITHOUT_CLEARING_LEDGER"},
    ]
    body = {
        "schema": "V21P01C06DeletionGraphV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "fixtureID": "V21P01C06DeletionGraphV1",
        "authority": authority(),
        "registeredKinds": REGISTERED_KINDS,
        "registeredKindPolicy": REGISTERED_KIND_POLICY,
        "semanticScope": SEMANTIC_SCOPE,
        "deletionModes": DELETION_MODES,
        "erasePhases": ERASE_PHASES,
        "erasePreparation": ERASE_PREPARATION_PROTOCOL,
        "clock": {"tombstoneAt": tombstone_at, "recreateAt": "2026-01-02T03:05:05Z"},
        "beforeDelete": {"nodes": before, "assetFileIDs": [evidence_file]},
        "afterDelete": {"nodes": after, "ledgerEntries": entries, "assetFileIDs": [], "emptySiteIDs": [site]},
        "recreated": {"oldAssetID": asset, "newAssetID": "00000000-0000-4000-8000-00000000000b", "oldTombstonePreserved": True},
        "cases": cases,
        "coverage": {
            "evidenceIDs": EVIDENCE_IDS,
            "families": ["G01", "A01", "H01", "I01", "R01"],
            "allDeletionModes": True,
            "allCurrentlyRegisteredKinds": True,
            "privacyMinimalTombstones": True,
            "deletionWins": True,
            "eraseOnlyClearing": True,
            "emptySitePreserved": True,
            "orphanCleanupSeparated": True,
            "unknownKindFailClosed": True,
            "erasePreparationMarkerRecovery": True,
            "noIntentOrphanRecovery": True,
            "manifestFirstDiscard": True,
        },
        **flags(),
    }
    return seal(body)


def _schema_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "string"


def _looks_like_digest(key: str) -> bool:
    lowered = key.lower()
    return lowered == "artifactdigest" or lowered == "sha256" or "digest" in lowered


def _looks_like_head(key: str) -> bool:
    lowered = key.lower()
    return lowered.endswith("head") or lowered in {"basehead", "commit"}


def _structural(value: Any, key: str = "") -> dict[str, Any]:
    """Make a strict, deterministic JSON Schema for the generated sample."""
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value.keys()),
            "properties": {name: _structural(child, name) for name, child in value.items()},
        }
    if isinstance(value, list):
        result: dict[str, Any] = {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "uniqueItems": len({json.dumps(item, sort_keys=True) for item in value}) == len(value),
            "prefixItems": [_structural(item, key) for item in value],
            "items": False,
        }
        return result
    if value is None:
        return {"type": "null"}
    if _looks_like_digest(key):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    if _looks_like_head(key):
        return {"type": "string", "pattern": "^[0-9a-f]{40}$"}
    if isinstance(value, str):
        return {"const": value}
    return {"const": value}


def _schema_for(value: dict[str, Any], schema_id: str, title: str) -> dict[str, Any]:
    body = _structural(value)
    body.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": schema_id,
        "title": title,
    })
    return body


def _contract_body(root: Path) -> dict[str, Any]:
    bindings = source_bindings(root)
    return {
        "schema": "V23P01C06DeletionRightsContractV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "persistentSchema": {
            "activeVersion": "V2_TOMBSTONES",
            "migrationRequired": True,
            "downgradePolicy": "FORWARD_FIX_ONLY",
            "unknownRecordKindPolicy": "FAIL_CLOSED_PRESERVE_LEDGER",
        },
        "registeredKinds": REGISTERED_KINDS,
        "registeredKindPolicy": REGISTERED_KIND_POLICY,
        "semanticScope": SEMANTIC_SCOPE,
        "tombstonePolicy": {
            "deletionWins": True,
            "privacyMinimal": True,
            "residency": "LEDGER_ONLY",
            "retention": "INDEFINITE_UNTIL_VERIFIED_COMPLETE_ERASE",
            "fields": TOMBSTONE_FIELDS,
            "forbiddenFields": FORBIDDEN_TOMBSTONE_FIELDS,
            "containsPersonalContent": False,
            "containsAuditNarrative": False,
        },
        "deletionWinsModes": DELETION_MODES,
        "ledgerClearingPolicy": {
            "authority": "VERIFIED_COMPLETE_ERASE_ONLY",
            "allowedPhases": ["cleanup_complete"],
            "ordinaryDeletionMayClear": False,
            "ageMayClear": False,
            "sizeMayClear": False,
            "versionMayClear": False,
            "orphanCleanupMayClear": False,
            "interruptedErasePreservesLedger": True,
        },
        "emptySitePolicy": {
            "finalAssetDeletion": "PRESERVE_SITE",
            "validAfterDeletion": True,
            "backupRestore": "PRESERVE_EMPTY_SITE",
            "laterAssetCreation": "ALLOWED",
            "siteDeletion": "EXPLICIT_PREVIEWED_COMMAND_ONLY",
            "verifiedErase": "MAY_REMOVE_SITE_CONTENT_AND_LEDGER",
        },
        "orphanCleanupPolicy": {
            "service": "OrphanFileCleanupService",
            "authority": "SEPARATE_FROM_DELETION_LEDGER",
            "mayMutateDeletionLedger": False,
            "requiresOwnershipProof": True,
            "retriesForwardOnly": True,
        },
        "eraseProtocol": {
            "phases": ERASE_PHASES,
            "completePredicate": "EMPTY_GENERATION_ACTIVE_AND_ORPHAN_CLEANUP_COMPLETE",
            "clearsLedgerOnlyAfterComplete": True,
            "interruption": "RETAIN_TOMBSTONES_AND_FORWARD_RECOVER",
            "preparation": ERASE_PREPARATION_PROTOCOL,
        },
        "failureRecovery": [{"failure": failure, "expectedOutcome": outcome} for failure, outcome in FAILURE_CASES],
        "hostileChecks": [
            "OLD_ARCHIVE_RESURRECTION",
            "REVOKED_KIND_RESOLUTION",
            "UNKNOWN_RECORD_KIND",
            "UNKNOWN_OWNERSHIP",
            "LEDGER_CLEAR_OUTSIDE_VERIFIED_ERASE",
            "ORPHAN_CLEANUP_LEDGER_MUTATION",
            "INFERRED_SITE_DELETION_AFTER_LAST_ASSET",
        ],
        "lifecycle": {
            "schemaDelta": True,
            "migrationRequired": True,
            "backupCompatibilityRequired": True,
            "restoreCompatibilityRequired": True,
            "deleteCompatibilityRequired": True,
            "eraseCompatibilityRequired": True,
            "exportCompatibilityRequired": True,
            "deviceLocalOnly": True,
            "remoteSync": False,
            "accountsOrAuth": False,
            "journalReplay": "ERASE_INTENT_PHASE_BOUND",
            "searchRebuild": "RECONCILE_AFTER_DELETION_COMMIT",
            "retention": "TOMBSTONES_UNTIL_VERIFIED_COMPLETE_ERASE",
            "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
        },
        "evidencePlan": {
            "golden": "DELETE_THEN_RESTORE_EVERY_MODE",
            "alternate": "DELETE_RECREATE_DISTINCT_IDENTITY",
            "hostile": "OLD_ARCHIVE_AND_FAILURE_MATRIX",
            "interruption": "PARTIAL_GRAPH_DELETION_AND_ERASE_PHASES",
            "recovery": "DISABLE_PATH_RETAIN_TOMBSTONES_UNTIL_VERIFIED_ERASE",
            "evidenceIDs": EVIDENCE_IDS,
        },
        "sourceBindings": bindings,
        "sourceBindingComplete": source_binding_complete(bindings),
        "fullCardFence": FULL_FENCE,
        **flags(),
    }


def deletion_rights_contract(root: Path) -> dict[str, Any]:
    return seal(_contract_body(root))


def _fixture_binding(root: Path) -> dict[str, Any]:
    # The fixture is generated, so its binding must never be derived from a
    # stale on-disk predecessor during the same ``--apply`` transaction.
    data = pretty(deletion_fixture())
    return {"path": FIXTURE_PATH, "bytes": len(data), "sha256": sha(data)}


def deletion_graph_manifest(root: Path) -> dict[str, Any]:
    fixture = deletion_fixture()
    bindings = source_bindings(root)
    cases = fixture["cases"]
    body = {
        "schema": "V23P01C06DeletionGraphManifestV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "fixtureBinding": _fixture_binding(root),
        "registeredKinds": REGISTERED_KINDS,
        "semanticScope": SEMANTIC_SCOPE,
        "deletionModes": DELETION_MODES,
        "erasePhases": ERASE_PHASES,
        "erasePreparation": ERASE_PREPARATION_PROTOCOL,
        "evidenceCases": cases,
        "evidenceIDs": EVIDENCE_IDS,
        "graphInventory": {
            "beforeNodeCount": len(fixture["beforeDelete"]["nodes"]),
            "afterNodeCount": len(fixture["afterDelete"]["nodes"]),
            "ledgerEntryCount": len(fixture["afterDelete"]["ledgerEntries"]),
            "emptySiteCount": len(fixture["afterDelete"]["emptySiteIDs"]),
            "orphanFileCountAfterCleanup": 0,
            "preparationMarkerCaseCount": 1,
            "noIntentOrphanRecoveryCaseCount": 1,
        },
        "coverage": fixture["coverage"],
        "sourceBindingDigest": sha(pretty(bindings)),
        "sourceBindingComplete": source_binding_complete(bindings),
        "fullCardFence": FULL_FENCE,
        **flags(),
    }
    return seal(body)


def base_outputs(root: Path) -> dict[str, bytes]:
    fixture = deletion_fixture()
    contract = deletion_rights_contract(root)
    graph = deletion_graph_manifest(root)
    # The fixture is a fenced source artifact, so its bytes are generated too;
    # this keeps the source binding and manifest reproducible from one command.
    return {
        FIXTURE_PATH: pretty(fixture),
        CONTRACT_SCHEMA: pretty(_schema_for(contract, "urn:assetrounds:v23:p01:c06:deletion-rights:v1", "V23P01C06DeletionRightsContractV1")),
        FIXTURE_SCHEMA: pretty(_schema_for(fixture, "urn:assetrounds:v23:p01:c06:deletion-graph-fixture:v1", "V23P01C06DeletionGraphV1")),
        CONTRACT_ARTIFACT: pretty(contract),
        GRAPH_ARTIFACT: pretty(graph),
    }


def tooling_manifest(root: Path, outputs: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    for path in TOOL_PATHS[:-1]:
        data = outputs[path] if path in outputs else (root / path).read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    bindings = source_bindings(root)
    body = {
        "schema": "V23P01C06ToolingManifestV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "pathFence": TOOL_PATHS,
        "fullCardFence": FULL_FENCE,
        "toolingPathCount": len(TOOL_PATHS),
        "sourceBindingCount": len(bindings),
        "sourceBindingComplete": source_binding_complete(bindings),
        "artifactCount": len(rows),
        "artifacts": rows,
        "artifactSetDigest": sha(pretty(rows)),
        "evidenceIDs": EVIDENCE_IDS,
        **flags(),
    }
    return seal(body)


def all_outputs(root: Path) -> dict[str, bytes]:
    outputs = base_outputs(root)
    outputs[MANIFEST] = pretty(tooling_manifest(root, outputs))
    return outputs


def source_paths() -> tuple[str, ...]:
    return tuple(SOURCE_PATHS)


def tool_paths() -> tuple[str, ...]:
    return tuple(TOOL_PATHS)
