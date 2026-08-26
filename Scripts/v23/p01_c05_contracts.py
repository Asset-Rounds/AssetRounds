#!/usr/bin/env python3
"""Deterministic source-bound contracts for V23-P01-C05 restore identity."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


CARD = "V23-P01-C05"
BASE_HEAD = "8e2536f42e6381412d22de302b013f606c2ec42f"
BASE_TREE = "f5db4dbdb8b393dc35e963ca05bd598a9fccf953"
COORDINATION_HEAD = "c73c6b05cf1f50e135e265be033fbe9d6a55c8bb"
CONTEXT_DIGEST = "3c58e2346b8c608c52729580bd867e8c8f329ea19119cb029e9bcff228e34ff5"
FENCE_DIGEST = "d33d9dc7eb467939eb7e682e56dbd0c5b0152f7c140867115bd17bd918d7083a"
TRANSITION_DIGEST = "3c8473e539474d2e23f4932ae81b0f072c9be71b855c81bc5b3dc91bfd38c5d4"
PREREQUISITE_DIGEST = "8d812b35d7d8c0d68148dfebfee38049caae7083db54138763d8430f0f9d1a95"
SUPPLEMENTAL_PREREQUISITE_DIGEST = "7c3f0c6ee84c789587dc0b24503399b271a09c2df7c954d6137026e86eadf633"
CORRECTION_RECEIPT_DIGEST = "5d230487a628b897a939ab82817698b0e757836f99679d5dc9f965874fd4c8da"
PROJECTION_DIGEST = "61bf7e0788893bdc015118a86290e1e8b3d4b3407eb7d00e856582d48e98538e"
LEDGER_DIGEST = "53bc489b243045d2abc9174e27d490f9324b6ab77b913fd80754e5def1efbda5"
PRIOR_LEDGER_DIGEST = "da7699908e225b0f2e6d6c771d8887d9fee7ae797822071f16cea593f54b9e59"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
DOSSIER_DIGEST = "528e5aacfac8fb5f330b31fe6da18188cbf21b730f5d41549f1c222a26b1abc0"
INHERITED_DIGEST = "451ce63ceafea76f32c23face560273ee75aed24a9d7fda0f9d0c9f613700176"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIntentV1.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceIdentity.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Restore/V21P01C05IdentityTransformationsV1.json",
]
TOOL_PATHS = [
    "Scripts/v23/p01_c05_contracts.py",
    "Scripts/v23/generate_p01_c05_contracts.py",
    "Scripts/v23/verify_p01_c05_contracts.py",
    "Scripts/v23/restore-identity.schema.json",
    "Scripts/v23/restore-identity-fixture.schema.json",
    "docs/design/v23/tooling/V23P01C05RestoreIdentityContractV1.json",
    "docs/design/v23/tooling/V23P01C05IdentityTransformationManifestV1.json",
    "docs/design/v23/tooling/V23-P01-C05-tooling-manifest.json",
]
FULL_FENCE = SOURCE_PATHS + TOOL_PATHS

CONTRACT_SCHEMA = TOOL_PATHS[3]
FIXTURE_SCHEMA = TOOL_PATHS[4]
CONTRACT_ARTIFACT = TOOL_PATHS[5]
TRANSFORMATION_ARTIFACT = TOOL_PATHS[6]
MANIFEST = TOOL_PATHS[7]

# Bind stable semantic names, never line numbers or formatting.
SOURCE_SPECS = [
    (SOURCE_PATHS[0], ["BackupRestoreMode", "RestoreIdentityDecisionV1", "sourceReplicaReuse", "knownReplicaIDs", "recordDisposition = .preserve", "case .emptyInstall", "case .replaceExisting", "case .clone", "case .fork"]),
    (SOURCE_PATHS[1], ["RestoreIntentV1", "schemaVersion = 2", "case 1:", "case 2:", "isSuperset(", "identity"]),
    (SOURCE_PATHS[2], ["V4BackupManifestV1", "backupSchemaVersion", "replicaID"]),
    (SOURCE_PATHS[3], ["BackupCanonicalEncoderV1", "encodeManifest", "case (1, nil, nil)", "case (2, let workspaceID?, let replicaID?)"]),
    (SOURCE_PATHS[4], ["BackupExportService", "backupSchemaVersion: 2", "replicaID: sourceIdentity.replicaID.rawValue"]),
    (SOURCE_PATHS[5], ["BackupImportService", "stageAndValidate", "validateManifestBounds", "let zero = UUID", "workspaceID != zero", "replicaID != zero", "case (1, nil, nil)", "case (2, let workspaceID?, let replicaID?)"]),
    (SOURCE_PATHS[6], ["BackupPackageValidatorV1", "ValidatedV4BackupPackageV1", "let zero = UUID", "workspaceID != zero", "replicaID != zero", "case (1, nil, nil)", "case (2, let workspaceID?, let replicaID?)"]),
    (SOURCE_PATHS[7], ["BackupRestoreService", "func restore(", "RestoreIdentityDecisionV1.decide", "currentGenerationPointerV3", "prepareRestoreStagingGenerationManifest", "requireInstalledRestoreGenerationSnapshot", "removePreparedRestoreGenerationManifestBeforeDiscard", "prepareStreaming()", "unavailableWorkspaces.formUnion", "unavailableReplicas.formUnion", "destinationWorkspaceID", "destinationOwnedForRestore", "for _ in 0..<16", "reconcileAtStartup"]),
    (SOURCE_PATHS[8], ["RestoreIntentStore", "RestoreIntentCodecV1", "func load()", "func create("]),
    (SOURCE_PATHS[9], ["WorkspaceID", "ReplicaID", "WorkspaceIdentity"]),
    (SOURCE_PATHS[10], ["CurrentGenerationPointerV3", "knownReplicaIDs", "decodeCanonical"]),
    (SOURCE_PATHS[11], ["StoreGenerationFactory", "CurrentGenerationPointerV3", "makeRestoreCurrentPointerV3", "switchCurrentGeneration"]),
    (SOURCE_PATHS[12], ["StoreSessionCoordinator", "workspaceID", "replicaID"]),
    (SOURCE_PATHS[13], ["V9_05RestoreIdentityTests", "test"]),
    (SOURCE_PATHS[14], ["V9_01VersionedSchemaIdentityTests", "WorkspaceID", "ReplicaID"]),
    (SOURCE_PATHS[15], ["V9_03MigrationRecoveryTests", "CurrentGenerationPointer"]),
    (SOURCE_PATHS[16], ['"schemaVersion"', '"cases"']),
]

IDENTITY_TABLE = [
    {
        "mode": "EMPTY",
        "destinationPrecondition": "NO_CANONICAL_WORKSPACE",
        "workspaceID": "PRESERVE_SOURCE",
        "replicaID": "MINT_DESTINATION_OWNED",
        "recordIDs": "PRESERVE_SOURCE",
        "existingDestinationContent": "MUST_BE_EMPTY",
        "sourceReplicaID": "PROVENANCE_ONLY_NEVER_ACTIVE",
        "sourceWorkspaceLineage": "CONTINUATION_SOURCE_WORKSPACE",
    },
    {
        "mode": "REPLACE",
        "destinationPrecondition": "EXPLICIT_MATCHED_DESTINATION_AUTHORITY",
        "workspaceID": "PRESERVE_DESTINATION",
        "replicaID": "RETAIN_DESTINATION_OR_MINT_IF_ABSENT",
        "recordIDs": "PRESERVE_SOURCE_REPLACEMENT_UNION",
        "existingDestinationContent": "REPLACE_UNDER_DELETION_WINS",
        "sourceReplicaID": "PROVENANCE_ONLY_NEVER_ACTIVE",
        "sourceWorkspaceLineage": "SOURCE_ARCHIVE_PROVENANCE_ONLY",
    },
    {
        "mode": "CLONE",
        "destinationPrecondition": "EXPLICIT_CLONE_AUTHORIZATION",
        "workspaceID": "MINT_DESTINATION_OWNED",
        "replicaID": "MINT_DESTINATION_OWNED",
        "recordIDs": "PRESERVE_SOURCE",
        "existingDestinationContent": "NEW_GENERATION_ONLY",
        "sourceReplicaID": "PROVENANCE_ONLY_NEVER_ACTIVE",
        "sourceWorkspaceLineage": "SOURCE_ARCHIVE_PROVENANCE_ONLY",
    },
    {
        "mode": "FORK",
        "destinationPrecondition": "EXPLICIT_FORK_AUTHORIZATION",
        "workspaceID": "MINT_DESTINATION_OWNED",
        "replicaID": "MINT_DESTINATION_OWNED",
        "recordIDs": "PRESERVE_RAW_UUID_RESCOPED_BY_NEW_WORKSPACE",
        "existingDestinationContent": "NEW_GENERATION_ONLY",
        "sourceReplicaID": "PROVENANCE_ONLY_NEVER_ACTIVE",
        "sourceWorkspaceLineage": "REQUIRED_EXPLICIT_SOURCE_WORKSPACE_LINEAGE",
    },
]

ACTIVATION_PHASES = [
    "intentPrepared",
    "sourceValidated",
    "identityPlanFrozen",
    "generationStaged",
    "generationValidated",
    "pointerPublished",
    "firstLaunchReconciled",
    "secondLaunchReconciled",
    "exportReconciled",
]

FAILURE_CASES = [
    ("SOURCE_REPLICA_REUSE", "REJECT_ALL_MODES_BEFORE_ACTIVATION"),
    ("WORKSPACE_ID_COLLISION", "REJECT_OR_DETERMINISTICALLY_MINT_PER_MODE"),
    ("REPLICA_ID_COLLISION", "REJECT_OR_RETRY_FROZEN_DESTINATION_MINT"),
    ("RECORD_ID_COLLISION", "REJECT_SAME_WORKSPACE_COLLISION_ALLOW_RAW_UUID_RESCOPING_BY_DISTINCT_WORKSPACE"),
    ("WRONG_RESTORE_MODE", "REJECT_BEFORE_STAGING"),
    ("STALE_POINTER", "REJECT_WITHOUT_PUBLICATION"),
    ("STALE_REVISION", "REJECT_WITHOUT_PUBLICATION"),
    ("CANCELLED", "DISCARD_PREPUBLICATION_STAGING"),
    ("LOW_STORAGE", "DISCARD_PREPUBLICATION_STAGING"),
    ("FUTURE_SCHEMA", "REJECT_WITHOUT_MUTATION"),
    ("CORRUPT_MANIFEST", "REJECT_WITHOUT_MUTATION"),
    ("CRASH_BEFORE_POINTER", "RELAUNCH_DISCARDS_OR_RESUMES_FROZEN_STAGING"),
    ("CRASH_DURING_POINTER", "RELAUNCH_RECONCILES_ATOMIC_POINTER_V3"),
    ("CRASH_AFTER_POINTER", "FORWARD_ONLY_RECONCILIATION_NEVER_REVERSE_MIGRATES"),
    ("SECOND_LAUNCH_MISMATCH", "FAIL_CLOSED_FORWARD_FIX_REQUIRED"),
    ("EXPORT_RECONCILIATION_MISMATCH", "FAIL_CLOSED_NO_SUCCESS_RECEIPT"),
]

CRASH_RECOVERY_MATRIX = [
    {
        "phase": phase,
        "publicationState": "POST_PUBLICATION" if ACTIVATION_PHASES.index(phase) >= ACTIVATION_PHASES.index("pointerPublished") else "PRE_PUBLICATION",
        "expectedRecovery": "FORWARD_ONLY_RECONCILE_NEVER_REVERSE_MIGRATE" if ACTIVATION_PHASES.index(phase) >= ACTIVATION_PHASES.index("pointerPublished") else "DISCARD_OR_RESUME_FROZEN_STAGING_NO_CANONICAL_CHANGE",
    }
    for phase in ACTIVATION_PHASES
]


class ContractError(ValueError):
    """Raised when frozen restore evidence is absent or inconsistent."""


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
        "coordinationCASSequence": 71,
        "coordinationLedgerSequence": 71,
        "coordinationLedgerDigest": LEDGER_DIGEST,
        "priorCoordinationLedgerDigest": PRIOR_LEDGER_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "supplementalPrerequisiteDigest": SUPPLEMENTAL_PREREQUISITE_DIGEST,
        "authorityCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "correctedProjectionDigest": PROJECTION_DIGEST,
        "registerRowDigest": REGISTER_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_RECEIPT_DIGEST,
        "ownerParallelOverrideReason": "OWNER_AUTHORIZED_PRE_S10_6_ORDERED_IMPLEMENTATION_V4",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "directPrerequisite": "V23-P01-C04",
        "invalidationConsumer": "V23-P01-C06",
        "conformanceSubjectSet": "KernelConformanceSubjectSetV1",
        "activeS10OverlapCount": 0,
        "deterministicEvidenceIDs": [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")],
        "acceptedS10_6BaselineDigest": None,
    }


def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows = []
    for path, symbols in SOURCE_SPECS:
        item = root / path
        if not item.is_file():
            raise ContractError(f"missing source binding: {path}")
        data = item.read_bytes()
        text = data.decode("utf-8")
        missing = [symbol for symbol in symbols if symbol not in text]
        if missing:
            raise ContractError(f"missing source symbols in {path}: {missing}")
        rows.append({"path": path, "role": "FENCED_PRODUCT_TEST_OR_FIXTURE_SOURCE", "status": "BOUND", "bytes": len(data), "sha256": sha(data), "requiredSymbols": symbols})
    return rows


def contract_schema() -> dict[str, Any]:
    required = ["schema", "schemaVersion", "cardID", "authority", "protocolVersions", "identityTable", "sourceReplicaPolicy", "collisionPolicy", "activationPhases", "crashRecoveryMatrix", "reconciliation", "failureRecovery", "lifecycle", "sourceBindings", "fullCardFence", *flags().keys(), "artifactDigest"]
    properties: dict[str, Any] = {
        "schema": {"const": "V23P01C05RestoreIdentityContractV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
        "authority": {"type": "object"}, "protocolVersions": {"type": "object"},
        "identityTable": {"type": "array", "minItems": 4, "maxItems": 4, "prefixItems": [{"const": row} for row in IDENTITY_TABLE], "items": False},
        "sourceReplicaPolicy": {"type": "object"}, "collisionPolicy": {"type": "object"},
        "activationPhases": {"type": "array", "minItems": len(ACTIVATION_PHASES), "maxItems": len(ACTIVATION_PHASES), "prefixItems": [{"const": phase} for phase in ACTIVATION_PHASES], "items": False},
        "crashRecoveryMatrix": {"const": CRASH_RECOVERY_MATRIX},
        "reconciliation": {"type": "object"},
        "failureRecovery": {"type": "array", "minItems": len(FAILURE_CASES), "uniqueItems": True, "items": {"type": "object", "required": ["failure", "expectedOutcome"]}},
        "lifecycle": {"type": "object"}, "sourceBindings": {"type": "array", "minItems": 17, "maxItems": 17},
        "fullCardFence": {"type": "array", "minItems": 25, "maxItems": 25, "prefixItems": [{"const": path} for path in FULL_FENCE], "items": False},
        "artifactDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
    }
    properties.update({key: {"const": value} for key, value in flags().items()})
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "urn:assetrounds:v23:p01:c05:restore-identity:v1", "title": "V23P01C05RestoreIdentityContractV1", "type": "object", "additionalProperties": False, "required": required, "properties": properties}


def fixture_schema() -> dict[str, Any]:
    properties: dict[str, Any] = {
        "schema": {"const": "V23P01C05IdentityTransformationManifestV1"}, "schemaVersion": {"const": 1}, "cardID": {"const": CARD},
        "authority": {"type": "object"}, "fixtureBinding": {"type": "object", "required": ["path", "bytes", "sha256"]},
        "identityTable": {"const": IDENTITY_TABLE},
        "cases": {
            "type": "array",
            "minItems": 12,
            "uniqueItems": True,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["id", "family", "mode", "expectedOutcome", "evidenceID"],
                "properties": {
                    "id": {"type": "string"},
                    "family": {"enum": ["G01", "A01", "H01", "I01", "R01"]},
                    "mode": {"enum": ["EMPTY", "REPLACE", "CLONE", "FORK", "ALL"]},
                    "expectedOutcome": {"type": "string"},
                    "evidenceID": {"pattern": "^V23-P01-C05-[GAHIR]01$"},
                },
            },
        },
        "coverage": {"type": "object"}, "artifactDigest": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
    }
    properties.update({key: {"const": value} for key, value in flags().items()})
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": "urn:assetrounds:v23:p01:c05:identity-transformation-manifest:v1", "title": "V23P01C05IdentityTransformationManifestV1", "type": "object", "additionalProperties": False, "required": ["schema", "schemaVersion", "cardID", "authority", "fixtureBinding", "identityTable", "cases", "coverage", *flags().keys(), "artifactDigest"], "properties": properties}


def restore_contract(root: Path) -> dict[str, Any]:
    value: dict[str, Any] = {
        "schema": "V23P01C05RestoreIdentityContractV1", "schemaVersion": 1, "cardID": CARD, "authority": authority(),
        "protocolVersions": {"currentGenerationPointerWriter": 3, "currentGenerationPointerReaders": [2, 3], "restoreIntentWriter": 2, "restoreIntentReaders": [1, 2], "backupManifestWriter": 2, "backupManifestReaders": [1, 2], "legacyManifestV1Retained": True, "unknownVersionDisposition": "FAIL_CLOSED"},
        "identityTable": IDENTITY_TABLE,
        "sourceReplicaPolicy": {"archiveFieldRequiredInManifestV2": True, "manifestV1Disposition": "EXPLICIT_LEGACY_UNKNOWN_PROVENANCE", "mayBecomeDestinationActiveReplica": False, "rejectReuseAcrossModes": ["EMPTY", "REPLACE", "CLONE", "FORK"], "destinationReplicaAuthority": "DEVICE_LOCAL_DESTINATION_OWNED"},
        "collisionPolicy": {"workspace": "MODE_BOUND_REJECT_OR_FROZEN_MINT", "replica": "REJECT_SOURCE_REUSE_AND_DESTINATION_COLLISION", "record": "PRESERVE_RAW_UUID_AND_SCOPE_SEMANTIC_IDENTITY_BY_WORKSPACE_ID", "identityPlanFrozenBeforeCanonicalWrite": True, "retryReusesFrozenIdentityPlan": True, "rawRecordUUIDRemapping": False, "immutableEmbeddedRecordIDsPreserved": True, "silentRewrite": False},
        "activationPhases": ACTIVATION_PHASES,
        "crashRecoveryMatrix": CRASH_RECOVERY_MATRIX,
        "reconciliation": {"relaunch": "INTENT_POINTER_AND_GENERATION_IDENTITY_EXACT", "secondLaunch": "NO_PENDING_INTENT_ACTIVE_POINTER_V3_IDENTICAL", "export": "MANIFEST_V2_SOURCE_IDENTITY_MATCHES_ACTIVE_POINTER_V3", "mismatchDisposition": "FAIL_CLOSED_FORWARD_FIX_REQUIRED_NO_SUCCESS_RECEIPT"},
        "failureRecovery": [{"failure": failure, "expectedOutcome": outcome} for failure, outcome in FAILURE_CASES],
        "lifecycle": {"mode": "CONTENT_ONLY", "schemaDelta": False, "migrationRequired": False, "backupCompatibilityRequired": True, "replaceRestoreRequired": True, "cloneForkRequired": True, "importExportRequired": True, "journalReplay": "RESTORE_INTENT_V2_PHASE_BOUND", "searchRebuild": "RECONCILE_AFTER_POINTER_PUBLICATION", "deleteErase": "DELETION_WINS_PRESERVED", "retention": "SOURCE_GENERATION_IMMUTABLE", "downgradePolicy": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION", "interruption": "DISCARD_BEFORE_PUBLICATION_FORWARD_FIX_AFTER", "recovery": "ATOMIC_POINTER_V3_RELAUNCH_RECONCILIATION", "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT"},
        "sourceBindings": source_bindings(root), "fullCardFence": FULL_FENCE, **flags(),
    }
    return seal(value)


def transformation_manifest(root: Path) -> dict[str, Any]:
    fixture_path = SOURCE_PATHS[-1]
    fixture = (root / fixture_path).read_bytes()
    cases = []
    for mode in ("EMPTY", "REPLACE", "CLONE", "FORK"):
        cases.append({"id": f"{mode}_IDENTITY_TRANSFORMATION", "family": "G01", "mode": mode, "expectedOutcome": "MATCH_EXACT_IDENTITY_TABLE_AND_ATOMIC_ACTIVATION", "evidenceID": f"{CARD}-G01"})
        cases.append({"id": f"{mode}_SOURCE_REPLICA_REUSE", "family": "H01", "mode": mode, "expectedOutcome": "REJECT_BEFORE_ACTIVATION", "evidenceID": f"{CARD}-H01"})
    cases.extend([
        {"id": "COLLISION_AND_CROSS_WORKSPACE_NEGATIVES", "family": "A01", "mode": "ALL", "expectedOutcome": "REJECT_OR_APPLY_EXACT_MODE_TRANSFORMATION", "evidenceID": f"{CARD}-A01"},
        {"id": "CRASH_EACH_ACTIVATION_PHASE", "family": "I01", "mode": "ALL", "expectedOutcome": "DISCARD_PREPUBLICATION_OR_FORWARD_RECONCILE_POSTPUBLICATION", "evidenceID": f"{CARD}-I01"},
        {"id": "SECOND_LAUNCH_RECONCILIATION", "family": "R01", "mode": "ALL", "expectedOutcome": "EXACT_POINTER_IDENTITY_AND_NO_PENDING_INTENT", "evidenceID": f"{CARD}-R01"},
        {"id": "EXPORT_RECONCILIATION", "family": "R01", "mode": "ALL", "expectedOutcome": "MANIFEST_V2_EXPORT_MATCHES_ACTIVE_POINTER_V3", "evidenceID": f"{CARD}-R01"},
        {"id": "MANIFEST_V1_LEGACY_READ", "family": "A01", "mode": "ALL", "expectedOutcome": "READ_WITH_EXPLICIT_UNKNOWN_SOURCE_REPLICA_PROVENANCE", "evidenceID": f"{CARD}-A01"},
        {"id": "MANIFEST_V2_SOURCE_REPLICA", "family": "G01", "mode": "ALL", "expectedOutcome": "PROVENANCE_PRESERVED_NEVER_ACTIVE_WRITER", "evidenceID": f"{CARD}-G01"},
    ])
    value: dict[str, Any] = {
        "schema": "V23P01C05IdentityTransformationManifestV1", "schemaVersion": 1, "cardID": CARD, "authority": authority(),
        "fixtureBinding": {"path": fixture_path, "bytes": len(fixture), "sha256": sha(fixture)},
        "identityTable": IDENTITY_TABLE, "cases": cases,
        "coverage": {"caseCount": len(cases), "modeCount": 4, "sourceReplicaRejectionModeCount": 4, "pointerV3": True, "intentV2": True, "manifestV1Read": True, "manifestV2ReadWrite": True, "collision": True, "crashEveryPhase": True, "secondLaunch": True, "exportReconciliation": True},
        **flags(),
    }
    return seal(value)


def base_outputs(root: Path) -> dict[str, bytes]:
    return {CONTRACT_SCHEMA: pretty(contract_schema()), FIXTURE_SCHEMA: pretty(fixture_schema()), CONTRACT_ARTIFACT: pretty(restore_contract(root)), TRANSFORMATION_ARTIFACT: pretty(transformation_manifest(root))}


def tooling_manifest(root: Path, outputs: dict[str, bytes]) -> dict[str, Any]:
    rows = []
    for path in TOOL_PATHS[:-1]:
        data = outputs[path] if path in outputs else (root / path).read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    value: dict[str, Any] = {"schema": "V23P01C05ToolingManifestV1", "schemaVersion": 1, "cardID": CARD, "authority": authority(), "pathFence": TOOL_PATHS, "fullCardFence": FULL_FENCE, "toolingPathCount": 8, "sourceBindingCount": 17, "sourceBindingComplete": True, "artifactCount": len(rows), "artifacts": rows, "artifactSetDigest": sha(pretty(rows)), **flags()}
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    outputs = base_outputs(root)
    outputs[MANIFEST] = pretty(tooling_manifest(root, outputs))
    return outputs
