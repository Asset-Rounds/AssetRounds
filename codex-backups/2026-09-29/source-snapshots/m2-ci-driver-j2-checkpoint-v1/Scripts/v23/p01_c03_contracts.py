#!/usr/bin/env python3
"""Deterministic V23-P01-C03 migration/recovery and release contracts.

The implementation sources are deliberately bound by digest and by a small
set of required symbols. The generated JSON is evidence of the current
repository shape; it is not an acceptance or release claim.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


CARD = "V23-P01-C03"
BASE_HEAD = "977fe7814ce80f1994b4c158a1be6b27b7b60c3e"
BASE_TREE = "41fe77d371a3eba5cacea3f993434f6e250e1228"

# Frozen corrected Card16 coordination evidence. These values are metadata,
# not values inferred from a mutable worktree or a new verification run.
COORDINATION_AUTHORITY_HEAD = "0b773d4337a84096e63b533414ff1ad20ebb5263"
CONTEXT_DIGEST = "d07e06cf4965fdea35cc24d0e60bdf7b10e8effb607d9fc572dda7d96596c1c9"
FENCE_DIGEST = "33ac4424b2bebeaea61ef58953f4fdca129815e939ac5981802ccf27280b1015"
COORDINATION_LEDGER_SEQUENCE = 62
COORDINATION_LEDGER_DIGEST = "e714392955aae61bbebac18023576f8c6df0750b24cfe67dd5fadaf4caa38486"
CORRECTION_RECEIPT_DIGEST = "8bae45e3cb2603d363daddce3504a2b7659d35e0957960a11a8226974884f09e"

PREREQUISITE_DIGEST = "2c9767afd35e005803081f6bae77d85508f42d20cb446f149bd3235fc95295c2"
DOSSIER_DIGEST = "dad1c6971c71aae28187d8a7a290f5a8c47cc6d9fb541f87a2ba487cbe3a40f8"
INHERITED_DIGEST = "e37c99074d86754086f5b7de3d148a2d3da6145b7d87dc2402bac8e679d568d0"
FOUNDATION_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"

C01 = {
    "cardID": "V23-P01-C01",
    "candidateHead": "fd303030608600443c8a0151f8f93c27e5cc928e",
    "candidateTree": "cb5f5fc41379e61ed51dc1b3890ad55c63e98433",
    "contextDigest": "7e182eeb0787008de8c3ebeb5b575d1138dda4c7c2be6198c41e1ae671b3377b",
    "pathFenceDigest": "26f81fe92663d9450a2292347eaf85dfcf49ac0f7323123995cf6cb07993271b",
    "verificationReceiptDigest": "4d4b4b6d30ea0f32d1b2564d5be0519727daa5859e9ea205967b1fc94b2d017d",
    "checkpointDigest": "4692d9b02b90bb779e3d775c6e15abcaa1a53a20bff18234ff531d6ed9107589",
    "schemaIdentityContractDigest": "2344be8d2a2a21a155d2457196d658828e437204a5cfb8d55088802a947a6501",
    "toolingManifestDigest": "af0e6868894a30b535b358fc0d4d62dd8415725fa326443d11fa2262e6ba4ead",
}
C02 = {
    "cardID": "V23-P01-C02",
    "candidateHead": BASE_HEAD,
    "candidateTree": BASE_TREE,
    "contextDigest": "156b0f066a284225ee2a7a569d70b57d8495427f45660c29efc308e3e09eaaee",
    "pathFenceDigest": "516df34be4e6c68ff8a6d1737c8ced37e2eb1b5ebfd6110542a60b9579c36809",
    "verificationReceiptDigest": "b36371b428371d4fa6ec0ab4dbe8f0f76498ed375d8e374227f882348b3f1b55",
    "checkpointDigest": "d63cd3a6050d4c4b6506c0c95560857e2e81960f8bb366e7157b7f135440c436",
    "ownedFileProtectionContractDigest": "82cfa6e86cb89a2b8f80ca6dca00dae9e1d2a7fdd200ccdd467bebb8282f8203",
    "ownedFilePrivacyInventoryDigest": "fa47493f286d967ffffe10329684a197da3b9298c1a84c70e1a4642df5851be1",
    "toolingManifestDigest": "2bcd15b356fdb0b2fc641ba1fb42429562fb3b853b49b27eefc19ca962b66570",
}

SOURCE_PATHS = [
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
]
TOOL_PATHS = [
    "Scripts/v23/p01_c03_contracts.py",
    "Scripts/v23/generate_p01_c03_contracts.py",
    "Scripts/v23/verify_p01_c03_contracts.py",
    "Scripts/v23/migration-recovery.schema.json",
    "Scripts/v23/persistent-schema-release-registry.schema.json",
    "docs/design/v23/tooling/V23P01C03MigrationRecoveryContractV1.json",
    "docs/design/v23/tooling/PersistentSchemaReleaseRegistryV1.json",
    "docs/design/v23/tooling/V23-P01-C03-tooling-manifest.json",
]
FULL_FENCE = SOURCE_PATHS + TOOL_PATHS

MIGRATION_SCHEMA = "Scripts/v23/migration-recovery.schema.json"
REGISTRY_SCHEMA = "Scripts/v23/persistent-schema-release-registry.schema.json"
MIGRATION_ARTIFACT = "docs/design/v23/tooling/V23P01C03MigrationRecoveryContractV1.json"
REGISTRY_ARTIFACT = "docs/design/v23/tooling/PersistentSchemaReleaseRegistryV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P01-C03-tooling-manifest.json"

# These are the actual durable phases and DEBUG injection boundaries exposed by
# StoreMigrationContracts.swift. FAILURE_CLASSES remains the compact matrix
# used by the earlier contract shape; faultBoundaryMatrix covers every named
# runtime boundary as well.
PHASES = [
    "prepared",
    "sourceCloned",
    "v2WriteAuthorized",
    "v2Validated",
    "generationInstalled",
    "pointerPublished",
    "firstLaunchValidated",
    "secondLaunchValidated",
]
FAILURE_CLASSES = [
    "CRASH",
    "PARTIAL_FSYNC",
    "PARTIAL_INSTALL",
    "FUTURE_SCHEMA",
    "LOW_STORAGE",
    "PROTECTED_DATA_DENIAL",
    "SECOND_LAUNCH_FAILURE",
]
# Public compatibility name used by the earlier C03 tooling.
FAULTS = FAILURE_CLASSES
FAULT_BOUNDARIES = [
    "beforePreparedJournalWrite",
    "afterPreparedJournalWrite",
    "beforeSourceClone",
    "afterSourceClone",
    "beforeV2WriteAuthorization",
    "afterV2WriteAuthorization",
    "beforeV2Validation",
    "afterV2Validation",
    "beforeGenerationInstall",
    "afterGenerationInstall",
    "beforePointerPublication",
    "afterPointerPublication",
    "beforeFirstLaunchValidation",
    "afterFirstLaunchValidation",
    "beforeSecondLaunchValidation",
    "afterSecondLaunchValidation",
    "beforeJournalRemoval",
    "afterJournalRemoval",
]

SOURCE_SPECS = [
    (
        SOURCE_PATHS[0],
        [
            "BackupRestoreService",
            "BackupRestoreFailureInjection",
            "BackupRestoreFailurePoint",
            "failureInjection",
            "inject(",
        ],
    ),
    (
        SOURCE_PATHS[1],
        [
            "PersistentSchemaV1",
            "PersistentSchemaV2",
            "PersistentSchemaReleaseRegistryV1",
            "PersistentSchemaReleaseMarker",
            "v2MarkerID",
        ],
    ),
    (
        SOURCE_PATHS[2],
        [
            "StoreGenerationFactory",
            "snapshotInstalledGeneration",
            "cloneInstalledGeneration",
            "switchCurrentGeneration",
            "streamedDigest",
            "reconcile",
        ],
    ),
    (
        SOURCE_PATHS[3],
        [
            "StoreMigrationPhaseV1",
            "StoreMigrationFaultBoundaryV1",
            "StoreMigrationJournalV1",
            "CurrentGenerationPointerV2",
            "StoreMigrationIdentitySourceV1",
            "StoreMigrationFailureInjection",
            "semanticSHA256",
            "sourceSemanticDigest",
            "targetSemanticDigest",
        ],
    ),
    (
        SOURCE_PATHS[4],
        [
            "PreparedMigrationEnvelopeV1",
            "preparedEnvelopeName",
            "preparedEnvelopeTemporaryName",
            "reconcilePreparedEnvelopeIfPresent",
            "reconcileJournalTemporaryIfPresent",
            "replaceJournal",
            "RENAME_EXCL",
        ],
    ),
    (
        SOURCE_PATHS[5],
        [
            "PersistentSchemaV1",
            "PersistentSchemaV2",
            "WorkspaceID",
            "ReplicaID",
            "destinationOwnedForRestore",
            "schemaVersion",
        ],
    ),
    (
        SOURCE_PATHS[6],
        [
            "StoreMigrationFaultBoundaryV1",
            "testEveryFaultBoundaryUsesPreWriteFallbackOrPostWriteForwardRecovery",
            "StoreMigrationFailureInjection",
            "sourceMismatch",
            "pointerSchema",
            "semanticData",
        ],
    ),
]

MARKER_ID = "00000000-0000-0000-0000-000000000002"
TARGET_VERSION = [2, 0, 0]


class ContractError(ValueError):
    """Raised when frozen contract evidence is incomplete or inconsistent."""


def pretty(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    ).encode("utf-8")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result["artifactDigest"] = sha(pretty(value))
    return result


def flags() -> dict[str, Any]:
    return {
        "acceptedS10_6Blocker": True,
        "nativeCompileRan": False,
        "hostedDispatchRan": False,
        "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER",
        "adoptionEnabled": False,
        "acceptanceEnabled": False,
        "acceptanceCredit": False,
        "releaseReady": False,
        "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "branch": "phase/v23-expansion",
        "baseHead": BASE_HEAD,
        "baseTree": BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_AUTHORITY_HEAD,
        "coordinationCASSequence": COORDINATION_LEDGER_SEQUENCE,
        "coordinationLedgerSequence": COORDINATION_LEDGER_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "hydrationCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "registerRowDigest": COORDINATION_LEDGER_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "foundationDigest": FOUNDATION_DIGEST,
        "directPrerequisite": C02,
        "overlapEvidence": [C01, C02],
        "authorizedPriorFenceOverlapCount": 4,
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "deterministicEvidenceIDs": [
            f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")
        ],
        "acceptedS10_6SeedDigest": None,
        "acceptedS10_6SeedBlocker": "PENDING_ACCEPTED_S10_6_PREV21_COMPATIBILITY_SEED",
    }


def lifecycle() -> dict[str, Any]:
    return {
        "mode": "NEW_SCHEMA_VERSION",
        "schemaDelta": True,
        "migrationDelta": True,
        "backupCompatibilityRequired": True,
        "restoreCompatibilityRequired": True,
        "deleteCompatibilityRequired": True,
        "exportCompatibilityRequired": True,
        "supersession": "APPEND_SUCCESSOR_NEVER_REWRITE_ACCEPTED_ARTIFACT",
        "successorTriggers": [
            "SOURCE_CHANGE",
            "SCHEMA_RELEASE_CHANGE",
            "MIGRATION_PHASE_CHANGE",
            "FAULT_MATRIX_CHANGE",
            "SEED_CHANGE",
            "EVIDENCE_CHANGE",
        ],
        "interruption": "FAIL_CLOSED_WITH_PHASE_BOUND_RECOVERY",
        "recovery": "PRE_PUBLICATION_DISCARD_OR_POST_PUBLICATION_FORWARD_FIX",
    }


def source_bindings(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path, required_symbols in SOURCE_SPECS:
        item = root / path
        if not item.is_file():
            raise ContractError(f"missing source binding: {path}")
        data = item.read_bytes()
        rows.append(
            {
                "path": path,
                "role": "FENCED_PRODUCT_SOURCE",
                "status": "BOUND",
                "sha256": sha(data),
                "bytes": item.stat().st_size,
                "requiredSymbols": required_symbols,
            }
        )
    return rows


def identity_intent() -> dict[str, Any]:
    return {
        "generatedWorkspaceIDCount": 0,
        "generatedReplicaIDCount": 0,
        "generatedByV1ToV2": False,
        "existingIDs": "PRESERVE",
        "canonicalSourceTargetSemanticEquality": True,
        "rawSQLiteByteEqualityRequired": False,
        "frozenValues": {
            "migrationID": "PREPARED_JOURNAL_FIELD",
            "targetGenerationID": "PREPARED_JOURNAL_FIELD",
            "markerID": MARKER_ID,
            "targetVersion": TARGET_VERSION,
        },
        "retryReuses": [
            "migrationID",
            "targetGenerationID",
            "markerID",
            "targetVersion",
        ],
        "workspaceIDDisposition": "EXISTING_CANONICAL_VALUE_PRESERVED",
        "replicaIDDisposition": "EXISTING_CANONICAL_VALUE_PRESERVED",
    }


def frozen_intent() -> dict[str, Any]:
    return {
        "workspaceID": True,
        "replicaID": True,
        "entityIDs": True,
        "targetVersion": True,
        "retryReusesIdentity": True,
        "generatedWorkspaceIDCount": 0,
        "generatedReplicaIDCount": 0,
        "existingIDsPreservedByCanonicalSemanticEquality": True,
        "frozenMigrationID": "PREPARED_JOURNAL_FIELD",
        "frozenTargetGenerationID": "PREPARED_JOURNAL_FIELD",
        "frozenMarkerID": MARKER_ID,
        "frozenTargetVersion": TARGET_VERSION,
    }


def semantic_digest_policy() -> dict[str, Any]:
    return {
        "preparedSourceManifestSemanticSHA256": "OPTIONAL_NIL_BEFORE_SOURCE_CLONE",
        "sourceClonedSourceSemanticDigest": "REQUIRED_AND_FROZEN_IN_JOURNAL",
        "v2TargetSemanticSHA256": "REQUIRED",
        "v2TargetComparedToJournalSourceSemanticDigest": True,
        "normalizedCanonicalExport": True,
        "rawSQLiteByteEquality": False,
    }


def claims() -> list[dict[str, Any]]:
    return [
        {
            "id": "PREPARED_ENVELOPE",
            "status": "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE",
            "sourceRequirements": [
                {
                    "path": SOURCE_PATHS[4],
                    "requiredSymbols": [
                        "PreparedMigrationEnvelopeV1",
                        "createPreparedMigration",
                        "preparedEnvelopeName",
                        "preparedEnvelopeTemporaryName",
                        "reconcilePreparedEnvelopeIfPresent",
                        "RENAME_EXCL",
                    ],
                }
            ],
            "assertions": [
                "PREPARE_BINDS_JOURNAL_AND_SOURCE_MANIFEST_DIGESTS_BEFORE_MUTATION",
                "SOURCE_MANIFEST_SEMANTIC_SHA256_MAY_BE_NIL_UNTIL_SOURCE_CLONED",
                "TEMPORARY_ENVELOPE_IS_CANONICAL_READ_BACK_AND_IDENTITY_REPROVED",
                "ENVELOPE_COMMIT_IS_RENAME_EXCL_FSYNC_AND_PAIR_REPROOF",
                "STARTUP_RECONCILES_ENVELOPE_BEFORE_JOURNAL_ACCESS",
                "ENVELOPE_IS_REMOVED_ONLY_AFTER_PERSISTED_PAIR_REPROOF",
            ],
        },
        {
            "id": "BOUNDED_STREAMING_SOURCE_REPROOF",
            "status": "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE",
            "sourceRequirements": [
                {
                    "path": SOURCE_PATHS[2],
                    "requiredSymbols": [
                        "migrationStreamBufferByteCount",
                        "streamedDigest",
                        "snapshotInstalledGeneration",
                        "cloneInstalledGeneration",
                        "sourceMismatch",
                    ],
                },
                {
                    "path": SOURCE_PATHS[6],
                    "requiredSymbols": ["semanticData", "sourceSemanticDigest"],
                },
            ],
            "assertions": [
                "SOURCE_BYTES_ARE_READ_IN_BOUNDED_64_KIB_STREAM_CHUNKS",
                "INITIAL_DIGEST_AND_FILE_IDENTITY_ARE_CAPTURED_BEFORE_CLONE",
                "SOURCE_DIRECTORY_AND_FILE_SET_ARE_REPROVED_AFTER_CLONE",
                "CLONED_STAGING_V1_CANONICAL_EXPORT_FREEZES_SOURCE_SEMANTIC_DIGEST",
                "V2_TARGET_SEMANTIC_DIGEST_IS_REQUIRED_AND_COMPARED_TO_FROZEN_SOURCE_DIGEST",
                "STREAMED_REPROOF_REJECTS_BYTES_SIZE_OR_IDENTITY_DRIFT_AS_SOURCE_MISMATCH",
            ],
        },
        {
            "id": "POINTER_SWAP_TEMP_RECONCILIATION",
            "status": "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE",
            "sourceRequirements": [
                {
                    "path": SOURCE_PATHS[2],
                    "requiredSymbols": [
                        "replacePointer",
                        "RENAME_SWAP",
                        "restore-next",
                        "pointerMutationLock",
                    ],
                },
                {
                    "path": SOURCE_PATHS[4],
                    "requiredSymbols": [
                        "reconcileJournalTemporaryIfPresent",
                        "RENAME_SWAP",
                        "RENAME_EXCL",
                    ],
                },
            ],
            "assertions": [
                "POINTER_REPLACEMENT_WRITES_AND_PROTECTS_A_TEMPORARY_BEFORE_SWAP",
                "SWAP_REPROVES_CURRENT_AND_DISPLACED_IDENTITIES_AFTER_FSYNC",
                "RELAUNCH_RECONCILES_TEMPORARY_ONLY_OR_POST_SWAP_RESIDUE",
                "MISMATCHED_TEMPORARY_BYTES_FAIL_CLOSED_WITHOUT_REOPENING_V1",
            ],
        },
        {
            "id": "PHASE_AWARE_ENOSPC_PROTECTED_CLASSIFICATION",
            "status": "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE",
            "sourceRequirements": [
                {
                    "path": SOURCE_PATHS[2],
                    "requiredSymbols": [
                        "migrationMaintenanceReason",
                        "ENOSPC",
                        "NSFileWriteOutOfSpaceError",
                        "protectedDataUnavailable",
                        "v2WriteAuthorized",
                        "forwardFixRequired",
                    ],
                }
            ],
            "assertions": [
                "ENOSPC_AND_PROTECTED_DATA_MAP_TO_EXPLICIT_MAINTENANCE_REASONS",
                "PRE_PUBLICATION_FAILURE_RETAINS_V1_AND_DISCARDS_ONLY_STAGING",
                "AFTER_V2_WRITE_AUTHORIZATION_UNCLASSIFIED_FAILURES_REQUIRE_FORWARD_FIX",
                "PROTECTED_DATA_DENIAL_IS_NEVER_REPORTED_AS_SUCCESS_OR_ROLLBACK_CREDIT",
            ],
        },
        {
            "id": "DEBUG_ONLY_FAULT_INJECTION",
            "status": "SOURCE_BOUND_BEHAVIORAL_CLAIM_NOT_ACCEPTANCE",
            "sourceRequirements": [
                {
                    "path": SOURCE_PATHS[3],
                    "requiredSymbols": [
                        "#if DEBUG",
                        "StoreMigrationFailureInjection",
                        "injectedFault",
                    ],
                },
                {
                    "path": SOURCE_PATHS[6],
                    "requiredSymbols": [
                        "#if DEBUG",
                        "testEveryFaultBoundaryUsesPreWriteFallbackOrPostWriteForwardRecovery",
                        "StoreMigrationFailureInjection",
                    ],
                },
            ],
            "assertions": [
                "FAULT_HOOKS_ARE_COMPILED_ONLY_UNDER_DEBUG",
                "INJECTION_IS_FAIL_ONCE_AND_BOUND_TO_DECLARED_PHASE_BOUNDARIES",
                "RELEASE_OR_PRODUCTION_EVIDENCE_MUST_NOT_CREDIT_INJECTED_FAULTS",
            ],
        },
    ]


def hostile_checks() -> list[dict[str, Any]]:
    return [
        {
            "id": "PREPARED_ENVELOPE_TAMPER",
            "claimID": "PREPARED_ENVELOPE",
            "mutation": "change_envelope_digest_or_regular_file_identity",
            "expectedOutcome": "REJECT_INVALID_CONTRACT_OR_FORWARD_FIX_REQUIRED",
        },
        {
            "id": "PREPARED_SEMANTIC_DIGEST_STATE",
            "claimID": "BOUNDED_STREAMING_SOURCE_REPROOF",
            "mutation": "require_or_fabricate_source_semantic_digest_before_source_cloned",
            "expectedOutcome": "ALLOW_PREPARED_NIL_THEN_REQUIRE_AND_FREEZE_AT_SOURCE_CLONED",
        },
        {
            "id": "TARGET_SEMANTIC_DIGEST_MISMATCH",
            "claimID": "BOUNDED_STREAMING_SOURCE_REPROOF",
            "mutation": "change_v2_target_semantic_digest_or_journal_source_digest",
            "expectedOutcome": "REJECT_TARGET_MISMATCH_OR_FORWARD_FIX_REQUIRED",
        },
        {
            "id": "SOURCE_STREAM_DRIFT",
            "claimID": "BOUNDED_STREAMING_SOURCE_REPROOF",
            "mutation": "change_source_bytes_size_or_inode_between_reads",
            "expectedOutcome": "REJECT_SOURCE_MISMATCH",
        },
        {
            "id": "POINTER_TEMP_RESIDUE",
            "claimID": "POINTER_SWAP_TEMP_RECONCILIATION",
            "mutation": "retain_mismatched_or_unowned_pointer_swap_temporary",
            "expectedOutcome": "REJECT_FAIL_CLOSED_NO_POINTER_CREDIT",
        },
        {
            "id": "PHASE_AWARE_STORAGE_PROTECTED",
            "claimID": "PHASE_AWARE_ENOSPC_PROTECTED_CLASSIFICATION",
            "mutation": "raise_enospc_or_protected_data_at_each_phase",
            "expectedOutcome": "CLASSIFY_REASON_AND_APPLY_PHASE_BOUND_FORWARD_POLICY",
        },
        {
            "id": "RELEASE_FAULT_HOOK_ESCAPE",
            "claimID": "DEBUG_ONLY_FAULT_INJECTION",
            "mutation": "expose_fault_injection_outside_debug_or_credit_injected_success",
            "expectedOutcome": "REJECT_RELEASE_SURFACE_AND_ACCEPTANCE_OVERCLAIM",
        },
    ]


def fault_matrix() -> list[dict[str, Any]]:
    publication_index = PHASES.index("pointerPublished")
    rows: list[dict[str, Any]] = []
    for phase_index, phase in enumerate(PHASES):
        published = phase_index >= publication_index
        for fault in FAULTS:
            rows.append(
                {
                    "phase": phase,
                    "fault": fault,
                    "publicationBoundaryCrossed": published,
                    "requiredRecovery": (
                        "RETAIN_EVIDENCE_AND_FORWARD_FIX_V2_NEVER_REOPEN_V1"
                        if published
                        else "DISCARD_STAGING_KEEP_IMMUTABLE_V1_ACTIVE"
                    ),
                    "result": "NOT_RUN",
                }
            )
    return rows


def fault_boundary_matrix() -> list[dict[str, Any]]:
    publication_index = PHASES.index("pointerPublished")
    rows: list[dict[str, Any]] = []
    for boundary_index, boundary in enumerate(FAULT_BOUNDARIES):
        phase_index = min(len(PHASES) - 1, boundary_index // 2)
        published = phase_index >= publication_index
        rows.append(
            {
                "boundary": boundary,
                "phase": PHASES[phase_index],
                "publicationBoundaryCrossed": published,
                "requiredRecovery": (
                    "RETAIN_EVIDENCE_AND_FORWARD_FIX_V2_NEVER_REOPEN_V1"
                    if published
                    else "DISCARD_STAGING_KEEP_IMMUTABLE_V1_ACTIVE"
                ),
                "result": "NOT_RUN",
            }
        )
    return rows


def migration(root: Path) -> dict[str, Any]:
    bindings = source_bindings(root)
    return seal(
        {
            "schema": "V23P01C03MigrationRecoveryContractV1",
            "schemaVersion": 1,
            "cardID": CARD,
            "authority": authority(),
            "fullPathFence": FULL_FENCE,
            "sourceBindings": bindings,
            "sourceBindingCount": len(bindings),
            "sourceBindingComplete": True,
            "schemaTransition": {
                "source": "PersistentSchemaV1",
                "sourceVersion": [1, 0, 0],
                "target": "PersistentSchemaV2",
                "targetVersion": TARGET_VERSION,
                "targetStatus": "V2_ACTIVE",
            },
            "pointerTransition": {
                "sourceFormat": 1,
                "targetFormat": 2,
                "publicationPhase": "pointerPublished",
                "soleActivationBoundary": True,
            },
            "migrationPhases": PHASES,
            "faultClasses": FAILURE_CLASSES,
            "faultBoundaries": FAULT_BOUNDARIES,
            "faultMatrix": fault_matrix(),
            "faultBoundaryMatrix": fault_boundary_matrix(),
            "frozenIntent": frozen_intent(),
            "identityIntent": identity_intent(),
            "semanticDigestPolicy": semantic_digest_policy(),
            "claims": claims(),
            "hostileChecks": hostile_checks(),
            "forwardOnlyBoundary": {
                "beforePublication": "DISCARD_STAGING_KEEP_IMMUTABLE_V1_ACTIVE",
                "atOrAfterPublicationOrPossibleV2Write": "NEVER_REOPEN_V1_RETAIN_EVIDENCE_REQUIRE_SCHEMA_COMPATIBLE_FORWARD_FIX",
                "inPlaceAcceptedStoreMutation": False,
                "automaticDestructiveRecovery": False,
            },
            "requiredEvidence": [
                "MIGRATION_STATE_TRACE",
                "BEFORE_AFTER_MANIFESTS_AND_HASHES",
                "FAULT_MATRIX",
                "SECOND_LAUNCH_VERIFICATION",
                "EXACT_HEAD_CI",
            ],
            "compatibility": {
                "normalizedCanonicalExportRequired": True,
                "semanticReportManifestRequired": True,
                "rawSQLiteByteEqualityRequired": False,
                "backup": True,
                "restore": True,
                "deleteErase": True,
                "exportReport": True,
            },
            "lifecycle": lifecycle(),
            **flags(),
        }
    )


def registry(root: Path) -> dict[str, Any]:
    bindings = source_bindings(root)
    return seal(
        {
            "schema": "PersistentSchemaReleaseRegistryV1",
            "schemaVersion": 1,
            "cardID": CARD,
            "authority": authority(),
            "canonicalSwiftDataLease": "SOLE_ACTIVE_REPOSITORY_WIDE",
            "sourceBindings": bindings,
            "sourceBindingCount": len(bindings),
            "sourceBindingComplete": True,
            "releaseRows": [
                {
                    "semanticSchema": "PRE_LOCATION_STORE_V1",
                    "compatibilityID": "FIELD_EVIDENCE_SCHEMA_V1",
                    "concreteVersion": [1, 0, 0],
                    "predecessor": "NONE",
                    "migrationStage": "BOOTSTRAP",
                    "modelCount": 7,
                    "markerID": None,
                    "implementationHead": C01["candidateHead"],
                    "acceptedHead": None,
                    "status": "PROVISIONAL_EXISTING_AWAITING_ACCEPTED_S10_6_SEED",
                },
                {
                    "semanticSchema": "PRE_LOCATION_STORE_V2",
                    "compatibilityID": "FIELD_EVIDENCE_SCHEMA_V2",
                    "concreteVersion": TARGET_VERSION,
                    "predecessor": "PRE_LOCATION_STORE_V1",
                    "migrationStage": "LIGHTWEIGHT",
                    "modelCount": 8,
                    "markerID": MARKER_ID,
                    "implementationHead": None,
                    "acceptedHead": None,
                    "status": "PROVISIONAL_ACTIVE_CANDIDATE_NOT_ACCEPTED",
                },
            ],
            "registryLaws": {
                "monotonicConcreteVersions": True,
                "exactPredecessorRequired": True,
                "duplicateSuccessorRejected": True,
                "skippedPredecessorRejected": True,
                "unorderedMigrationRejected": True,
                "compatibilityCaseBeforeFirstWrite": True,
                "frozenIdentityBeforeConversion": True,
                "retryReusesFrozenIdentity": True,
                "deviceLocalOperationalFormatsConsumeSwiftDataLease": False,
            },
            "activeSchema": "PRE_LOCATION_STORE_V2",
            "downgradeDisposition": "PRE_ACTIVATION_ONLY_FORWARD_FIX_AFTER_ACTIVATION",
            "acceptedS10_6SeedDigest": None,
            "blockers": [
                "PENDING_ACCEPTED_S10_6_PREV21_COMPATIBILITY_SEED",
                "NATIVE_COMPILE_NOT_RUN",
                "FAULT_MATRIX_NOT_RUN",
                "SECOND_LAUNCH_NOT_RUN",
            ],
            "frozenIntent": frozen_intent(),
            "identityIntent": identity_intent(),
            "semanticDigestPolicy": semantic_digest_policy(),
            "claims": claims(),
            "hostileChecks": hostile_checks(),
            "lifecycle": lifecycle(),
            **flags(),
        }
    )


def structural(value: Any, key: str = "") -> dict[str, Any]:
    if key in ("schema", "schemaVersion", "cardID"):
        return {"const": value}
    if value is None:
        return {"type": "null"}
    if isinstance(value, bool):
        return {"type": "boolean"}
    if isinstance(value, int):
        return {"type": "integer", "minimum": 0}
    if isinstance(value, str):
        digest_descriptor_keys = {"sourceClonedSourceSemanticDigest"}
        if (
            key not in digest_descriptor_keys
            and (key.endswith("Digest") or key in ("sha256", "artifactDigest"))
        ):
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        if key in (
            "baseHead",
            "baseTree",
            "candidateHead",
            "candidateTree",
            "implementationHead",
            "acceptedHead",
            "coordinationAuthorityHead",
        ):
            return {"type": "string", "pattern": "^[0-9a-f]{40}$"}
        return {"type": "string", "minLength": 1}
    if isinstance(value, list):
        return {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "prefixItems": [structural(item, key) for item in value],
            "items": False,
        }
    if isinstance(value, dict):
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value),
            "properties": {name: structural(item, name) for name, item in value.items()},
        }
    raise ContractError(f"unsupported value at {key}")


def schema(value: dict[str, Any], name: str) -> dict[str, Any]:
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{name}",
        "title": value["schema"],
        **structural(value),
    }


def outputs(root: Path) -> dict[str, dict[str, Any]]:
    migration_value = migration(root)
    registry_value = registry(root)
    return {
        MIGRATION_SCHEMA: schema(migration_value, "migration-recovery.schema.json"),
        REGISTRY_SCHEMA: schema(
            registry_value, "persistent-schema-release-registry.schema.json"
        ),
        MIGRATION_ARTIFACT: migration_value,
        REGISTRY_ARTIFACT: registry_value,
    }


def manifest(root: Path) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for path in TOOL_PATHS:
        if path == MANIFEST:
            continue
        item = root / path
        if not item.is_file():
            raise ContractError(f"missing tooling path: {path}")
        data = item.read_bytes()
        rows.append({"path": path, "sha256": sha(data), "bytes": len(data)})
    return seal(
        {
            "schema": "V23P01C03ToolingManifestV1",
            "schemaVersion": 1,
            "cardID": CARD,
            "authority": authority(),
            "pathFence": TOOL_PATHS,
            "fullCardFence": FULL_FENCE,
            "sourceBindingCount": len(SOURCE_PATHS),
            "toolingPathCount": len(TOOL_PATHS),
            "artifacts": rows,
            "artifactCount": len(rows),
            "sourceBindingComplete": True,
            "claims": claims(),
            "hostileChecks": hostile_checks(),
            "lifecycle": lifecycle(),
            **flags(),
        }
    )
