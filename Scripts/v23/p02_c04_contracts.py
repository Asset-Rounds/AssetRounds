#!/usr/bin/env python3
"""Deterministic provisional contracts for V23-P02-C04."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P02-C04"
APP_BASE_HEAD = "b81726024a9ee3af82c19659ac2ff1d316d3744e"
APP_BASE_TREE = "73a849ce3a982c475204f8ec828a09d02303e126"
COORDINATION_HEAD = "5a57191d280f05324f6501c70e28e60e13a452eb"
COORDINATION_TREE = "72a0e0c348572ffdb6b97528b23c6acc2ab17125"
COORDINATION_CAS_SEQUENCE = 97
COORDINATION_LEDGER_DIGEST = "ac08d49d2dd442e494d1f9ef5fecf1e291cb9c07d6ff2811e06ae484dd2e01a7"
HYDRATION_PROJECTION_DIGEST = "3bc6a16e9dd3b7e93fb68d046c0d889dd08a3b30a1dc61f54d1bf2eca74be47d"
CONTEXT_DIGEST = "302ef4657fc1e840b754be5cfaee2542cf5c7cce2007dff4d3f2f55d69e14edb"
FENCE_DIGEST = "fea695e7b500fadbb82b4f45700c291919c2edb0f1d816bd4fdcde49f5711ffa"
PREREQUISITE_DIGEST = "80cf486387f02354af70050f77c8d3722f60da902c06c56f7e05b308a5cbcb8a"
TRANSITION_DIGEST = "64ede9e90e0332c806eeac8409ffc297605e5ce94e31e057a05a07b5d02d6396"
CORRECTION_RECEIPT_DIGEST = "e2f0d2a35c2cc7973c53e0ce59da103c8224db294962030634bf1776be3a979a"
REGISTER_ROW_DIGEST = "bd927832aba21a262e169db53cd50e1b4abf973b1fb56de2730f34daf7de5751"
DOSSIER_DIGEST = "3610631e2ac9e6176fa3380f34600ccaca796c12b54564c27434b346eecdce37"
INHERITED_DIGEST = "56eeab66381897730fdc7e8765bc8bfa89d7537f325bde15f3bbb12e6dd51762"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"

GENERATOR_VERSION = "p02-c04-contracts-v1"
GENERATOR_SEED = 230204

CONTRACT_SCRIPT = "Scripts/v23/p02_c04_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c04_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c04_contracts.py"
LEASE_SCHEMA = "Scripts/v23/generation-lease.schema.json"
FENCE_SCHEMA = "Scripts/v23/stale-writer-fence.schema.json"
PRUNE_SCHEMA = "Scripts/v23/generation-prune-policy.schema.json"
CORPUS_SCHEMA = "Scripts/v23/generation-lease-prune-corpus.schema.json"
LEASE_DOC = "docs/design/v23/tooling/V23P02C04GenerationLeaseContractV1.json"
FENCE_DOC = "docs/design/v23/tooling/V23P02C04StaleWriterFenceContractV1.json"
PRUNE_DOC = "docs/design/v23/tooling/V23P02C04GenerationPrunePolicyV1.json"
CORPUS_DOC = "docs/design/v23/tooling/V23P02C04GenerationLeasePruneCorpusManifestV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C04-tooling-manifest.json"

SOURCE_PATHS = [
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceAppTests/V9_08GenerationLeaseTests.swift",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT,
    LEASE_SCHEMA, FENCE_SCHEMA, PRUNE_SCHEMA, CORPUS_SCHEMA,
    LEASE_DOC, FENCE_DOC, PRUNE_DOC, CORPUS_DOC, MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = TOOL_PATHS[3:]
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_08G01DurableLeaseIdentityAndBoundedRegistry",
    "testV9_08A01ExpectedEpochAndLeaseFenceRejectsStaleCommit",
    "testV9_08H01UnknownCorruptAndUncertainOwnershipRetainsBytes",
    "testV9_08I01CrashExpiredLeaseRecoveryAndPruneBoundaries",
    "testV9_08R01BackupReplaceRestoreAndRelaunchReconciliation",
]
PROHIBITED_TOKENS = ["accountID", "backgroundDaemon", "CloudKit", "CKRecord", "outbox", "providerID", "remoteProvider", "serverCursor", "serverRevision", "tenantID", "vectorClock"]


class ContractError(ValueError):
    pass


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def seal(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value); result["artifactDigest"] = sha(pretty(value)); return result


def flags() -> dict[str, Any]:
    return {
        "nativeCompileRan": False, "hostedDispatchRan": False,
        "physicalEvidenceComplete": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseReady": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "registerOrdinal": 24,
        "title": "Generation leases, stale-writer fencing, and safe prune",
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND", "lineageSource": "V21-P02-C04",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion", "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD, "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST, "hydrationTransitionDigest": TRANSITION_DIGEST,
        "hydrationFenceCorrectionReceiptDigest": CORRECTION_RECEIPT_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST, "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST, "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST, "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST, "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_DIGEST,
        "directPrerequisites": ["V23-P02-C03"], "invalidationConsumers": ["V23-P02-C05"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema_name: str) -> dict[str, Any]:
    return {"schema": schema_name, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def lease_contract() -> dict[str, Any]:
    return seal({
        **base("GenerationLeaseContractV1"),
        "persistentContractSchema": "GENERATION_LEASE_STALE_WRITER_FENCE_AND_SAFE_PRUNE_V1",
        "persistentChangeMode": "CONTENT_ONLY",
        "owners": ["GenerationEpochV1", "GenerationLeaseTokenV1", "GenerationLeaseRegistryV1"],
        "leaseRoles": ["READER", "WRITER"],
        "identity": {
            "epochFields": ["schemaVersion", "generationID", "generationManifestSHA256"],
            "tokenFields": ["schemaVersion", "leaseID", "ownerID", "epoch", "role", "acquiredAt"],
            "generationID": "NONZERO_UUID", "generationManifestSHA256": "LOWERCASE_SHA256",
            "leaseID": "NONZERO_UUID", "ownerID": "NONZERO_LOCAL_PROCESS_UUID",
            "role": "CLOSED_READER_OR_WRITER", "canonicalEncoding": "SORTED_KEY_UTF8_EXACT_BYTES",
        },
        "registry": {
            "owner": "GenerationLeaseRegistryV1", "backing": "DESCRIPTOR_PINNED_CANONICAL_JSON_AND_OWNER_LOCKS",
            "durableBeforeGenerationUse": True, "oneIdentityPerActiveReaderOrWriter": True,
            "duplicateIdentity": "FAIL_CLOSED", "unknownVersion": "FAIL_CLOSED",
            "release": "EXACT_TOKEN_IDENTITY_MATCH_ONLY", "boundedLeaseCountRequired": True,
            "maximumActiveLeaseCount": 256, "maximumOwnerCount": 64,
            "maximumControlFileBytes": 4194304, "durableAtomicReplace": True,
            "apis": ["acquire(epoch:role:)", "release(_:)", "validateActive(_:requiredRole:)", "reconcileAbandonedOwners()", "withExclusiveGenerationMutationLock(_:)", "activeEpochs()"],
            "paths": ["FieldEvidenceOperations/generation-leases/registry.json", "FieldEvidenceOperations/generation-leases/registry.next.json", "FieldEvidenceOperations/generation-leases/mutation.lock", "FieldEvidenceOperations/generation-leases/owners/<ownerID>.lock"],
            "ownedFileKinds": ["generationLeaseDirectory", "generationLeaseControl", "generationLeaseControlTemporary", "generationLeaseOwnerLock"],
            "allOperationalLeaseKindsExcludedFromFilesystemBackup": True,
            "controlFileCrashSafety": {
                "initialPublication": "PROTECTED_FSYNCED_TEMPORARY_THEN_RENAME_EXCL",
                "protectionAppliedBeforeControlBytes": True,
                "loadReverifiesPolicyAndStableDescriptorSnapshot": True,
                "failedCreateCleanupRequiresExactCreatedIdentity": True,
                "renameSuccessDirectoryFsyncFailure": "RETRY_ADOPTS_ONLY_EXACT_DESIRED_CANONICAL_BYTES",
                "partialCanonicalFileCanBecomeAuthority": False,
            },
        },
        "liveness": {
            "live": "OWNER_LOCK_HELD_RETAIN_AND_NEVER_RELEASE",
            "abandonedAndOwnerProvablyDead": "RECOVERY_ELIGIBLE",
            "unknownOrUncertain": "RETAIN_AND_FAIL_CLOSED",
        },
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def fence_contract() -> dict[str, Any]:
    return seal({
        **base("StaleWriterFenceContractV1"), "owner": "StaleWriterFenceV1",
        "canonicalCommitFence": {
            "requiredExpectedValues": ["expectedGenerationEpoch", "writerLeaseToken"],
            "observedValues": ["currentPointerGenerationEpoch", "activeWriterLeaseToken"],
            "allMustMatch": True, "freshValidationImmediatelyBeforeCommit": True,
            "staleEpoch": "REJECT_NO_EFFECT_NO_RECEIPT", "staleOrReleasedLease": "REJECT_NO_EFFECT_NO_RECEIPT",
            "wrongGeneration": "REJECT_NO_EFFECT_NO_RECEIPT", "missingFence": "REJECT_NO_EFFECT_NO_RECEIPT",
        },
        "api": "StaleWriterFenceV1.withAuthorizedCommit(_:)",
        "lockScope": "SAME_CROSS_PROCESS_GENERATION_MUTATION_LOCK_SPANS_VALIDATION_AND_MODEL_CONTEXT_SAVE",
        "commitLockDurability": {
            "rootAuthorityProvedBeforeClosure": True,
            "epochAndActiveWriterLeaseProvedInsideSameLock": True,
            "postCommitPathReproofMayReportOrdinaryFailure": False,
            "nextOperationPerformsNormalPrevalidation": True,
        },
        "coveredCommitters": ["WorkspaceWriterAdapterV1", "MutationJournalStoreV1.commit", "MutationReceiptRecoveryServiceV1", "WholeSignDeletionService.commitCanonicalMutation"],
        "generationSwitch": {
            "changesToNewExactEpoch": True, "oldEpochCannotCommit": True,
            "newLeaseRequiredAfterSwitch": True, "pointerAndEpochAtomic": True,
        },
        "failureAtomicity": "NO_CANONICAL_MODEL_EFFECT_ENVELOPE_RECEIPT_OR_SEQUENCE_ADVANCE",
        "noWallClockOrArrivalOrderAuthority": True,
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def prune_contract() -> dict[str, Any]:
    return seal({
        **base("GenerationPrunePolicyV1"), "owner": "GenerationPrunePolicyV1",
        "inventoryStates": ["CURRENT_ACCEPTED", "KNOWN_INACTIVE_ACCEPTED", "ACTIVE_LEASED", "ABANDONED_PROCESS_LEASE", "UNKNOWN_OWNERSHIP", "CORRUPT_OWNERSHIP", "UNCERTAIN_LIVENESS"],
        "eligibility": {
            "onlyState": "KNOWN_INACTIVE_ACCEPTED", "allLeasesReleased": True,
            "outsideBoundedRetention": True, "manifestAndGenerationIdentityValidated": True,
            "currentGenerationNeverEligible": True, "unacceptedOrUnknownBytesNeverEligible": True,
        },
        "retention": {
            "retainedInactiveAcceptedGenerationCount": 2,
            "pruneDisabledOnRecoveryUncertainty": True,
            "unknownCorruptOrUncertainOwnership": "RETAIN_BYTES_FAIL_CLOSED",
            "liveLease": "RETAIN_BYTES", "expiredButLiveLease": "RETAIN_BYTES",
        },
        "abandonedProcessRecovery": {
            "requiresAbsentOwnerLockAfterExclusiveProbe": True, "requiresProcessProvablyDead": True,
            "reconciliationIdempotent": True, "liveOrUncertainLeaseReleased": False,
            "recoveredLeaseThenRecomputeEligibility": True,
        },
        "pruneTransaction": {
            "planFromFrozenValidatedInventory": True, "revalidateBeforeDelete": True,
            "receiptRequired": True, "partialDelete": "RECONCILE_IDEMPOTENTLY_OR_RETAIN",
            "receiptFields": ["schemaVersion", "operationID", "currentEpoch", "retainedEpochs", "prunedEpochs", "activeRetainedEpochs", "uncertainRetainedGenerationIDs", "ownerLivenessUncertain", "inventoryBeforeSHA256", "inventoryAfterSHA256", "disposition"],
            "boundedCollections": {
                "maximumEntries": 256,
                "boundSource": "GenerationLeaseRegistryV1.maximumActiveLeaseCount",
                "receipt": ["retainedEpochs+prunedEpochs", "activeRetainedEpochs", "uncertainRetainedGenerationIDs"],
                "intent": ["candidateEpochs+retainedEpochs", "activeRetainedEpochs", "uncertainRetainedGenerationIDs", "expectedRetiredGenerationIDs", "desiredRetiredGenerationIDs"],
            },
            "intentPhases": ["PREPARED", "BYTES_REMOVED", "RETIRED_POINTER_PUBLISHED", "RECEIPT_PUBLISHED"],
            "controlPaths": ["FieldEvidenceOperations/generation-leases/prune-intent.json", "FieldEvidenceOperations/generation-leases/prune-intent.next.json", "FieldEvidenceOperations/generation-leases/last-prune-receipt.json", "FieldEvidenceOperations/generation-leases/last-prune-receipt.next.json"],
            "receiptDispositions": ["PRUNED", "NO_ELIGIBLE_GENERATIONS", "DISABLED_RETAIN_ALL", "UNCERTAIN_RETAIN_ALL"],
            "receiptDispositionInvariants": {
                "PRUNED": "PRUNED_EPOCHS_NONEMPTY_AND_OWNER_LIVENESS_CERTAIN_AND_UNCERTAIN_IDS_EMPTY",
                "NO_ELIGIBLE_GENERATIONS": "NO_PRUNING_AND_OWNER_LIVENESS_CERTAIN",
                "DISABLED_RETAIN_ALL": "NO_PRUNING_AND_OWNER_LIVENESS_CERTAIN",
                "UNCERTAIN_RETAIN_ALL": "NO_PRUNING_AND_OWNER_LIVENESS_UNCERTAIN_OR_UNCERTAIN_IDS_NONEMPTY",
            },
            "receiptPublication": {
                "PRUNED": "INTENT_BOUND_PUBLISH_THEN_EXACT_INTENT_REMOVAL",
                "NO_ELIGIBLE_GENERATIONS": "DIRECT_NO_INTENT_PUBLISH",
                "DISABLED_RETAIN_ALL": "DIRECT_NO_INTENT_PUBLISH",
                "UNCERTAIN_RETAIN_ALL": "DIRECT_NO_INTENT_PUBLISH",
                "directAPI": "publishPruneReceipt(_:)",
                "intentBoundAPI": "publishPruneReceipt(_:completing:)",
            },
        },
        "backupReplaceRestore": {
            "backupPreservesAcceptedGenerationInventory": True,
            "operationalProcessLeasesPortable": False,
            "replaceRestoreReconcilesImportedAndDestinationInventory": True,
            "currentPointerEpochAndLeaseRegistryReproved": True,
            "startupReconciliationBeforeValidatedSessionActivation": True,
            "validatedCoordinatorConstructionAndReplacementRequired": True,
            "restoreWithoutLeaseDrainProof": "DISABLE_PRUNING_UNTIL_NEXT_COLD_LAUNCH",
            "sourceLeaseMayBecomeDestinationLiveLease": False,
            "knownInactiveAcceptedRetentionPreserved": True,
            "postRestoreLease": "ORDINARY_NEW_READER_OR_WRITER_LEASE_ON_REPROVED_DESTINATION_EPOCH",
        },
        "factoryAPIs": ["makeGenerationLeaseRegistry(ownerID:)", "currentGenerationEpoch()", "makeWriterFence(expectedGenerationEpoch:writerLeaseToken:registry:)", "reconcileGenerationLeasesAndPrune(policy:)"],
        "lifecycle": {
            "schemaMigrationDelta": False, "deleteBehaviorDelta": False,
            "openExportOfLeaseState": False, "backgroundDaemon": False,
            "serverOrRemoteProvider": False, "vectorClock": False,
            "downgradeDisposition": "FORWARD_FIX_ONLY",
        },
        "prohibitedTokens": PROHIBITED_TOKENS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def corpus_contract() -> dict[str, Any]:
    return seal({
        **base("GenerationLeasePruneCorpusManifestV1"),
        "testPath": SOURCE_PATHS[-1], "embeddedSyntheticCorpus": True,
        "evidence": [{"evidenceID": evidence, "testMethod": method} for evidence, method in zip(EVIDENCE_IDS, TEST_METHODS)],
        "requiredCoverage": {
            "G01": ["BOUNDED_DURABLE_READER_WRITER_LEASE_IDENTITY", "CANONICAL_REGISTRY_REOPEN"],
            "A01": ["EXPECTED_EPOCH_AND_LEASE_COMMIT_FENCE", "STALE_NO_EFFECT_NO_RECEIPT"],
            "H01": ["UNKNOWN_CORRUPT_UNCERTAIN_RETAIN", "LIVE_LEASE_NEVER_RELEASED", "LIMITS_AND_TAMPER_FAIL_CLOSED"],
            "I01": ["FOUR_REAL_PRUNE_FAULT_BOUNDARIES", "ABANDONED_DEAD_PROCESS_RECOVERY", "IDEMPOTENT_RELAUNCH"],
            "R01": ["PRODUCTION_BACKUP_EXPORT_IMPORT", "REPLACE_RESTORE_RECONCILIATION", "KNOWN_INACTIVE_ACCEPTED_RETENTION"],
        },
        "exactFiveTestMethods": True, "customerDataPresent": False, "secretsPresent": False,
        "nativeOrHostedEvidenceClaimed": False,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False, "required": list(value), "properties": {key: _strict(child, key == "artifactDigest") for key, child in value.items()}}
    if isinstance(value, list):
        if not value: return {"type": "array", "minItems": 0, "maxItems": 0}
        return {"type": "array", "minItems": len(value), "maxItems": len(value), "prefixItems": [_strict(item) for item in value], "items": False}
    if isinstance(value, bool) or value is None or isinstance(value, (int, str)):
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"} if digest else {"const": value}
    raise ContractError(f"unsupported schema value: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value); result.update({"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json", "title": title}); return result


def _rows(root: Path, generated: dict[str, bytes]) -> list[dict[str, Any]]:
    rows = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated.get(path)
        if data is None:
            item = root / path
            if not item.is_file(): raise ContractError(f"missing manifest input: {path}")
            data = item.read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _rows(root, generated)
    return seal({
        **base("V23-P02-C04-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "sourcePaths": SOURCE_PATHS, "sourcePathCount": len(SOURCE_PATHS),
        "toolingPaths": TOOL_PATHS, "toolingPathCount": len(TOOL_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows, "artifactCount": len(rows), "artifactSetDigest": sha(pretty(rows)),
        "persistentSchemaActivatedByTooling": False, "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    })


def all_outputs(root: Path) -> dict[str, bytes]:
    lease = lease_contract(); fence = fence_contract(); prune = prune_contract(); corpus = corpus_contract()
    generated = {
        LEASE_SCHEMA: pretty(schema("GenerationLeaseContractV1", lease)),
        FENCE_SCHEMA: pretty(schema("StaleWriterFenceContractV1", fence)),
        PRUNE_SCHEMA: pretty(schema("GenerationPrunePolicyV1", prune)),
        CORPUS_SCHEMA: pretty(schema("GenerationLeasePruneCorpusManifestV1", corpus)),
        LEASE_DOC: pretty(lease), FENCE_DOC: pretty(fence), PRUNE_DOC: pretty(prune), CORPUS_DOC: pretty(corpus),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated)); return generated
