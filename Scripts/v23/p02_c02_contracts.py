#!/usr/bin/env python3
"""Deterministic provisional contracts for V23-P02-C02."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P02-C02"
APP_BASE_HEAD = "56e53031b0f598b2395c5060dd2243136e4af66a"
APP_BASE_TREE = "5989170055899a3ab5bcdfea1b2306175109199d"
COORDINATION_HEAD = "5ab409463ed33b2c21f9c6007a5dd0fb1bffb9ef"
COORDINATION_TREE = "bdb4e2e9168e980a2ac63f7ed3c4e49fdc790a66"
COORDINATION_CAS_SEQUENCE = 88
COORDINATION_LEDGER_DIGEST = "c5f704a60c123e9b71e7d95178cd410e5d884a6bf4a24ae58889da64d9fa70fe"
HYDRATION_PROJECTION_DIGEST = "5594a8413614532282f1e8507618d0ce34c0c9d90ba283669d781e363229acc2"
CONTEXT_DIGEST = "7a640c0d6bf190ccb6f0193d09b7760e60ff5f96c66bf785f2ba971b8cf608a6"
FENCE_DIGEST = "9593de9026efe12b8b89b59c9811ba8848d445f3dc681b637e34c17e6900aaef"
PREREQUISITE_DIGEST = "0860b9b744561a99230db53a1b4803ded94c69cb034663d658559a6ea5e3bd3b"
TRANSITION_DIGEST = "f04daba62cda24e4345a2def0ba0cdad9ae622bf45935e8bd20d6833856d1a02"
REGISTER_ROW_DIGEST = "73dd7fcd314d63bc9e9244a9da68ef67e0c81a85c09343e031117e7b0a0da577"
DOSSIER_DIGEST = "844d28364a666c3abb4a480ba86a11c731b4a2c105c47dc1d99cc2d70575e1af"
INHERITED_DIGEST = "fa87a8ab94d8ff3d543e48f8367c167e58eae400f6a9abfb4d5764c5676af26a"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

GENERATOR_VERSION = "p02-c02-contracts-v1"
GENERATOR_SEED = 230202

CONTRACT_SCRIPT = "Scripts/v23/p02_c02_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c02_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c02_contracts.py"
ENVELOPE_SCHEMA = "Scripts/v23/mutation-envelope.schema.json"
RECEIPT_SCHEMA = "Scripts/v23/mutation-receipt.schema.json"
REVERSAL_SCHEMA = "Scripts/v23/mutation-reversal-linkage.schema.json"
LIFECYCLE_SCHEMA = "Scripts/v23/mutation-lifecycle.schema.json"
ENVELOPE_DOC = "docs/design/v23/tooling/V23P02C02MutationEnvelopeRegistryV1.json"
RECEIPT_DOC = "docs/design/v23/tooling/V23P02C02MutationReceiptContractV1.json"
RECOVERY_DOC = "docs/design/v23/tooling/V23P02C02MutationRecoveryMatrixV1.json"
LIFECYCLE_DOC = "docs/design/v23/tooling/V23P02C02MutationLifecycleContractV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C02-tooling-manifest.json"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationService.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationEnvelopeV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Domain/Mutation/SemanticReversalContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/MutationPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceAppTests/V10_02MutationEnvelopeReceiptTests.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Mutation/V21P02C02MutationEnvelopeReceiptCorpusV1.json",
]
TOOL_PATHS = [
    CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT,
    ENVELOPE_SCHEMA, RECEIPT_SCHEMA, REVERSAL_SCHEMA, LIFECYCLE_SCHEMA,
    ENVELOPE_DOC, RECEIPT_DOC, RECOVERY_DOC, LIFECYCLE_DOC, MANIFEST,
]
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
GENERATED_PATHS = [
    ENVELOPE_SCHEMA, RECEIPT_SCHEMA, REVERSAL_SCHEMA, LIFECYCLE_SCHEMA,
    ENVELOPE_DOC, RECEIPT_DOC, RECOVERY_DOC, LIFECYCLE_DOC, MANIFEST,
]
MANIFEST_INPUT_PATHS = SOURCE_PATHS + TOOL_PATHS[:-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]
OPERATIONAL_COMMAND_KINDS = [
    "begin_check_draft", "capture_evidence", "confirm_site_timezone",
    "create_first_sign", "delete_asset", "delete_site", "erase_workspace",
    "finalize_check", "finalize_correction", "record_work", "restore_workspace",
]
PREVIEW_ONLY_COMMAND_KINDS = ["archive_entities_preview_compensation"]
COMMAND_KINDS = sorted(OPERATIONAL_COMMAND_KINDS + PREVIEW_ONLY_COMMAND_KINDS)
HASH_FIELDS = ["envelopeSHA256", "commandBodySHA256", "postImages.semanticSHA256", "resultSHA256"]
RECEIPT_FIELDS = [
    "schemaVersion", "identity", "mutationID", "envelopeSHA256",
    "commandBodySHA256", "expectedRevision", "resultingRevision", "postImages",
    "contentDependencyIDs", "resultSHA256", "sourceKind", "causationMutationID", "correlationID",
    "reversesMutationID", "committedAt",
]
PROHIBITED_FIELDS = [
    "accountID", "authenticatedUserID", "tenantID", "providerOutbox",
    "providerInbox", "providerAcknowledgement", "providerURL", "serverCursor",
    "serverRevision", "vectorClock", "remoteAcknowledgement", "signedURL",
    "uploadState", "accessToken", "serviceCredential",
]


class ContractError(ValueError):
    pass


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


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
        "cardID": CARD, "attemptID": 1, "registerOrdinal": 22,
        "title": "Portable MutationEnvelopeV1 and atomic durable MutationReceiptV1",
        "classification": "IMPLEMENT_NOW", "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND", "lineageSource": "V21-P02-C02",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion", "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE, "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "foundationRegisterDigest": REGISTER_DIGEST, "directGraphDigest": GRAPH_DIGEST,
        "facetManifestDigest": FACET_DIGEST, "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_DIGEST,
        "directPrerequisites": ["V23-P02-C01"],
        "invalidationConsumers": ["V23-P02-C03"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def base(schema: str) -> dict[str, Any]:
    return {"schema": schema, "schemaVersion": 1, "cardID": CARD, "authority": authority()}


def envelope_contract() -> dict[str, Any]:
    payloads = [{"commandKind": kind, "envelopeSchemaVersion": 1, "durableEffectEligible": kind in OPERATIONAL_COMMAND_KINDS} for kind in COMMAND_KINDS]
    value = {
        **base("MutationEnvelopeRegistryV1"),
        "registryClosed": True,
        "commandKinds": COMMAND_KINDS,
        "operationalCommandKinds": OPERATIONAL_COMMAND_KINDS,
        "previewOnlyCommandKinds": PREVIEW_ONLY_COMMAND_KINDS,
        "payloadRegistry": payloads,
        "requiredEnvelopeFields": [
            "schemaVersion", "workspaceID", "replicaID", "generationID",
            "mutationID", "commandKind", "command", "expectedRevision",
            "contentDependencyIDs", "sourceKind", "causationMutationID",
            "correlationID", "reversalPlanDigest",
            "semanticReversalReplayIdentitySHA256", "semanticReversalExecution",
            "commandBodySHA256",
        ],
        "payloadVersionEncoding": "ENVELOPE_SCHEMA_VERSION_PLUS_CLOSED_TYPED_WORKSPACE_COMMAND_CASE",
        "canonicalEncoding": "RFC8785_STYLE_UTF8_SORTED_KEYS_NO_FLOATS_NO_DUPLICATE_KEYS",
        "bounds": {"maximumContentDependencyCount": 256, "maximumContentDependencyIDUTF8Bytes": 512},
        "identityRules": {
            "workspaceID": "NONZERO_UUID", "mutationID": "NONZERO_UUID",
            "replicaID": "NONZERO_UUID_DISTINCT_FROM_WORKSPACE_ID",
            "causationMutationID": "OPTIONAL_NONZERO_MUTATION_UUID",
            "correlationID": "OPTIONAL_NONZERO_UUID", "sourceKind": "CLOSED_LOCAL_SOURCE_ENUM",
        },
        "identityDecodeHardening": {
            "mutationID": "THROWING_NONZERO_DECODE",
            "entityIdentity": "THROWING_NONZERO_DECODE",
            "receiptIdentity": "THROWING_POSITIVE_SEQUENCE_AND_VALID_WORKSPACE_REPLICA_DECODE",
            "envelopeWorkspaceReplicaPair": "VALIDATED_NONZERO_AND_ROLE_DISTINCT_AFTER_DECODE",
        },
        "strictTargetTokens": {
            "affectedCommandTargets": "EVERY_TARGET_EXPLICITLY_PRESENT_IN_EXPECTED_ENTITY_REVISIONS",
            "missingTarget": "FAIL_CLOSED_INVALID_COMMAND_NO_EFFECT_NO_RECEIPT",
            "implicitOrUntypedTargetAllowed": False,
        },
        "reversalReplayIdentity": {
            "originalPlanBinding": "reversalPlanDigest",
            "executionBinding": "semanticReversalExecution",
            "durableReplayDigestBinding": "semanticReversalReplayIdentitySHA256",
            "mutuallyExclusive": True,
            "canonicalEnvelopeHashIncludesBoth": True,
            "replayProbeBeforeTargetPlanValidation": True,
            "semanticExecutionFields": [
                "targetMutationID", "targetReceiptIdentity", "reversalBasisSHA256",
                "planDigest", "compensatingMutationIDs",
            ],
            "semanticReplayIdentityFields": [
                "schemaVersion", "workspaceID", "replicaID", "generationID",
                "mutationID", "commandBodySHA256", "expectedRevision",
                "targetMutationID", "planDigest", "compensatingMutationIDs",
            ],
            "sameMutationIDChangedPlanOrExecution": "DURABLE_COMPOSITE_QUARANTINE_NO_EFFECT",
        },
        "entityEffects": "CANONICAL_POST_IMAGE_OR_TYPED_TOMBSTONE_NEVER_STORAGE_DIFF_OR_JSON_PATCH",
        "unknownCommandOrPayloadVersion": "FAIL_CLOSED_NO_EFFECT_NO_RECEIPT",
        "previewOnlyDisposition": "NO_CANONICAL_EFFECT_AND_NO_DURABLE_RECEIPT",
        "prohibitedFields": PROHIBITED_FIELDS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    }
    return seal(value)


def receipt_contract() -> dict[str, Any]:
    value = {
        **base("MutationReceiptContractV1"),
        "persistentSchema": "MUTATION_RECEIPT_V1",
        "persistentChangeMode": "NEW_SCHEMA_VERSION",
        "requiredReceiptFields": RECEIPT_FIELDS,
        "hashFields": HASH_FIELDS,
        "bounds": {"maximumPostImageCount": 1024},
        "atomicity": {
            "acceptedEffectAndEnvelopeAndBasisAndReceipt": "ONE_STORE_TRANSACTION",
            "receiptCardinalityPerAcceptedMutation": 1,
            "effectWithoutReceiptAllowed": False, "receiptWithoutEffectAllowed": False,
            "failedAttemptReceiptAllowed": False,
        },
        "durableIdempotency": {
            "lookupKey": ["workspaceID", "mutationID"],
            "persistentCompositeKey": "LOWERCASE_WORKSPACE_UUID_COLON_MUTATION_UUID",
            "receiptAndQuarantineBothUseCompositeKey": True,
            "sameMutationIDDifferentWorkspace": "DISTINCT_HISTORY",
            "sameIDSameEnvelopeHash": "RETURN_BYTE_IDENTICAL_PRIOR_RECEIPT_AFTER_RESTART",
            "sameIDDifferentEnvelopeHash": "DURABLE_QUARANTINE_NO_EFFECT",
            "quarantineSurvivesRestart": True,
        },
        "quarantineIdentityContract": {
            "closedDomains": ["MUTATION_ENVELOPE", "SEMANTIC_REVERSAL_REPLAY_IDENTITY"],
            "fields": ["identityDomain", "acceptedIdentitySHA256", "conflictingIdentitySHA256"],
            "mutationEnvelopeAcceptedIdentity": "PERSISTED_RECEIPT_ENVELOPE_SHA256",
            "semanticReversalAcceptedIdentity": "PERSISTED_ENVELOPE_SEMANTIC_REVERSAL_REPLAY_IDENTITY_SHA256",
            "mixedOrUnknownDomain": "FAIL_CLOSED_AS_CORRUPT_HISTORY",
            "acceptedAndConflictingMustDiffer": True,
        },
        "contentDependencyBinding": "RECEIPT_CONTENT_DEPENDENCY_IDS_BYTE_SEMANTICALLY_EQUAL_ENVELOPE",
        "ordering": {
            "key": ["workspaceID", "replicaID", "localSequence"],
            "localSequenceStartsAt": 1, "strictlyMonotonicPerReplica": True,
            "bareSequenceIsGlobalOrder": False, "committedAtOrdersReceipts": False,
            "sequenceCollision": "FAIL_CLOSED_QUARANTINE_NO_EFFECT",
        },
        "entityRepresentation": {
            "acceptedForms": ["CANONICAL_POST_IMAGE", "TYPED_TOMBSTONE"],
            "forbiddenForms": ["STORAGE_DIFF", "JSON_PATCH", "GENERIC_JSON_EAV"],
        },
        "receiptMeaning": "OPERATIONAL_EVIDENCE_NOT_LEGAL_OR_AUTHENTICATED_USER_AUDIT",
        "prohibitedFields": PROHIBITED_FIELDS,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    }
    return seal(value)


def recovery_contract() -> dict[str, Any]:
    boundaries = [
        "before_effect_transaction", "after_effect_before_envelope_insert",
        "after_envelope_before_basis_insert", "after_basis_before_receipt_insert",
        "after_receipt_before_transaction_commit", "after_transaction_commit_before_return",
        "after_quarantine_commit_before_return",
    ]
    value = {
        **base("MutationRecoveryMatrixV1"),
        "atomicFaultBoundaries": [
            {"boundary": item, "relaunchDisposition": "EXACTLY_PRIOR_RECEIPT_OR_NO_EFFECT_NEVER_PARTIAL"}
            for item in boundaries
        ],
        "implementationFaultInjectionPoints": ["afterEffectBeforeReceipt", "afterReceiptBeforeSave", "afterSaveBeforeReturn"],
        "restartReconciliation": [
            "VERIFY_CANONICAL_EFFECT_POST_IMAGES_OR_TOMBSTONES",
            "VERIFY_ENVELOPE_AND_RECEIPT_HASH_CHAIN",
            "VERIFY_CONTENT_DEPENDENCY_IDENTITIES_AND_HASHES",
            "VERIFY_REPLICA_LOCAL_SEQUENCE_UNIQUENESS",
            "VERIFY_REVERSAL_CHAIN_IF_PRESENT",
            "REBUILD_BOUNDED_PROJECTIONS_FROM_RECEIPTS",
        ],
        "bounds": {
            "maximumReceiptValidationCount": 100000,
            "maximumMutableContentValidationCount": 100000,
            "maximumReversalItemCount": 256,
        },
        "persistedStateRecovery": {
            "postImageBasis": "ACTUAL_PERSISTED_V4_DTO_OR_TYPED_TOMBSTONE",
            "tombstoneDisposition": "ABSENT_AFTER_MUTATION",
            "latestReceiptReproof": "CURRENT_POST_IMAGE_EQUALS_LATEST_RECEIPT_UNLESS_EXTERNAL_PROJECTION_EXISTS",
            "mutableSemantic": "BOUNDED_CURRENT_CONTENT_PLUS_DELETION_LEDGER",
            "externalProjection": "AUTHORIZED_EXTERNAL_MUTATION_OR_RESTORE_REPROVES_CURRENT_POST_IMAGE",
            "importedProjectionRevisionLinkage": "EVERY_MAXIMUM_IMPORTED_POST_IMAGE_REVISION_HAS_ENTITY_PROJECTION_REVISION_AT_LEAST_AS_NEW",
            "relaunchValidation": "VERIFY_ACTUAL_STATE_TOMBSTONES_MUTABLE_SEMANTIC_AND_EXTERNAL_PROJECTIONS",
        },
        "acceptedSemanticReplayReproof": {
            "beforeReturningPriorReceipt": "BOUNDED_FULL_JOURNAL_VALIDATE_ALL",
            "requiredChain": [
                "targetReceipt", "reversalBasis", "basisDigestAndPlan",
                "semanticReversalExecution", "semanticReceiptResultingRevision",
                "singleCompensatingReceipt", "quarantineDomains", "persistedState",
            ],
            "missingOrTamperedLink": "FAIL_CLOSED_AS_CORRUPT_HISTORY",
        },
        "hostileCases": {
            "unknownSchemaOrCommand": "FAIL_CLOSED_NO_EFFECT",
            "staleRevision": "FAIL_CLOSED_NO_EFFECT",
            "crossWorkspace": "FAIL_CLOSED_NO_EFFECT",
            "sourceReplicaAsDestination": "FAIL_CLOSED_NO_EFFECT",
            "tamperedEnvelopeOrReceiptHash": "QUARANTINE_NO_EFFECT",
            "sequenceCollision": "QUARANTINE_NO_EFFECT",
            "missingReversalBasis": "FAIL_CLOSED_NO_INVERSE_RECONSTRUCTION",
        },
        "reversalLinkage": {
            "ownerArtifacts": ["SemanticReversalReplayIdentityV1", "ReversalBasisV1", "SemanticReversalExecutionV1", "SemanticReversalReceiptV1"],
            "forwardHistoryOnly": True,
            "originalReceiptImmutable": True,
            "requiredChain": ["originalReceipt", "reversalBasis", "acceptedPlan", "compensatingMutations", "semanticReversalReceipt"],
            "receiptLinkageFields": ["reversesMutationID"],
            "basisFields": ["targetMutationID", "targetReceiptIdentity", "policyVersion", "planDigest", "compensatingCommandKinds"],
            "semanticReceiptFields": ["reversalReceiptIdentity", "reversesMutationID", "targetReceiptIdentity", "reversalBasisSHA256", "planDigest", "compensatingMutationIDs", "resultingRevision"],
            "executionFields": ["targetMutationID", "targetReceiptIdentity", "reversalBasisSHA256", "planDigest", "compensatingMutationIDs"],
            "replayIdentityFields": ["workspaceID", "replicaID", "generationID", "mutationID", "commandBodySHA256", "expectedRevision", "targetMutationID", "planDigest", "compensatingMutationIDs"],
            "durableReplayProbeBeforeTargetValidation": True,
            "singleCommandExecutionRequired": True,
            "compensatingMutationIDsExactlyCurrentMutation": True,
            "basisCommandKindMustEqualExecutedCommandKind": True,
            "semanticReceiptResultingRevisionMustEqualExecutionReceipt": True,
            "sameIDChangedTargetPlanOrCommands": "DURABLE_QUARANTINE_NO_EFFECT",
            "unknownBasisOrReversalVersion": "FAIL_CLOSED",
            "largeEvidenceBytesDuplicated": False,
            "mayRecallEraseExternalDeliveryOrFinalizedArtifact": False,
        },
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    }
    return seal(value)


def lifecycle_contract() -> dict[str, Any]:
    modes = [
        ("empty", "SOURCE_WORKSPACE_ID", "MINT_NEW_DESTINATION_REPLICA", "PRESERVE_SOURCE_RECEIPTS_IMMUTABLY"),
        ("replace", "PRESERVE_DESTINATION_WORKSPACE_ID", "RETAIN_DESTINATION_REPLICA_OR_MINT_IF_ABSENT", "PRESERVE_DESTINATION_HISTORY_AND_RECORD_SOURCE_PROVENANCE"),
        ("clone", "MINT_NEW_WORKSPACE_ID", "MINT_NEW_DESTINATION_REPLICA", "PRESERVE_RAW_RECORD_IDS_AND_SOURCE_RECEIPTS_AS_PROVENANCE"),
        ("fork", "MINT_NEW_WORKSPACE_ID_WITH_EXPLICIT_SOURCE_LINEAGE", "MINT_NEW_DESTINATION_REPLICA", "PRESERVE_RAW_RECORD_IDS_AND_SOURCE_RECEIPTS_AS_PROVENANCE"),
    ]
    value = {
        **base("MutationLifecycleContractV1"),
        "schemaActivation": {
            "persistentChangeMode": "NEW_SCHEMA_VERSION", "schema": "MUTATION_RECEIPT_V1",
            "persistentSchemaVersion": 4,
            "migrationRequired": True, "backupRestoreRequired": True,
            "deleteEraseRequired": True, "exportReportRequired": True,
            "downgradeDisposition": "FORWARD_FIX_ONLY",
            "beforeFirstSchemaWriteRollback": "DISCARD_CANDIDATE_GENERATION",
            "afterFirstSchemaWriteRollback": "RETAIN_READ_EXPORT_AND_SHIP_COMPATIBLE_FORWARD_FIX",
            "receiptDeletionToHideDefectAllowed": False,
        },
        "v3ToV4Migration": {
            "stage": "LIGHTWEIGHT_V3_TO_V4",
            "historicReceiptsFabricated": False,
            "retryAfterMarkerSaveBeforeJournalAdvance": "REVALIDATE_V3_SEMANTIC_THEN_REQUIRE_OR_BACKFILL_V4_MARKER",
            "crashRetryIdempotent": True,
            "postMigrationRecoveryValidationRequired": True,
        },
        "backup": {
            "backupContract": "V4BackupContracts", "manifestSchemaVersion": 3,
            "recordsSchemaVersion": 3, "envelopesReceiptsBasisAndQuarantineIncluded": True,
            "canonicalHashesReprovedOnImport": True, "unknownVersionDisposition": "FAIL_CLOSED",
            "legacySchema1Or2JournalBootstrap": "EMPTY_SCHEMA3_MUTATION_HISTORY_BEFORE_V4_MATERIALIZATION",
        },
        "mergedHistorySequence": {
            "sameWorkspaceAndReplica": "MAX_CURRENT_AND_INCOMING_LOCAL_SEQUENCE",
            "differentIdentity": "PRESERVE_CURRENT_SEQUENCE_UNTIL_DESTINATION_POLICY_RESETS",
            "newDestinationReplica": "RESET_TO_ZERO",
            "nextWrite": "STRICTLY_GREATER_THAN_RETAINED_LOCAL_SEQUENCE",
        },
        "restoreReplicaMatrix": [
            {"mode": mode, "workspaceIdentity": workspace, "destinationReplicaIdentity": replica,
             "receiptHistory": history, "sourceReplicaMayBecomeDestination": False}
            for mode, workspace, replica, history in modes
        ],
        "delete": "TYPED_TOMBSTONE_AND_RECEIPT_PRESERVED_BY_RETENTION_POLICY",
        "verifiedErase": "REMOVE_WORKSPACE_DATA_ENVELOPES_RECEIPTS_BASIS_QUARANTINE_AND_KEYS_WITHOUT_REVERSAL_CLAIM",
        "export": "SECRET_FREE_CANONICAL_RECEIPT_HISTORY_WITH_HASH_AND_PROVENANCE",
        "rebuildReplay": "DETERMINISTIC_BOUNDED_RECEIPT_ORDER_AND_CONSUMER_CHECKPOINTS",
        "journalLifecycleAPIs": [
            "exportSnapshot", "validateImportedSnapshot", "replaceHistory",
            "stageMutableSemanticStateAfterAuthorizedExternalMutation", "clearForErase",
        ],
        "rawRecordUUIDsRemappedForCloneOrFork": False,
        "networkOrProviderArtifactsAllowed": False,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    }
    return seal(value)


def _strict(value: Any, digest: bool = False) -> dict[str, Any]:
    if isinstance(value, dict):
        return {"type": "object", "additionalProperties": False,
                "required": list(value),
                "properties": {key: _strict(child, key == "artifactDigest") for key, child in value.items()}}
    if isinstance(value, list):
        return {"type": "array", "minItems": len(value), "maxItems": len(value),
                "prefixItems": [_strict(item) for item in value], "items": False}
    if isinstance(value, bool) or value is None or isinstance(value, (int, str)):
        if digest:
            return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        return {"const": value}
    raise ContractError(f"unsupported schema value: {type(value)}")


def schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict(value)
    result.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                   "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json",
                   "title": title})
    return result


def _rows(root: Path, generated: dict[str, bytes]) -> list[dict[str, Any]]:
    rows = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated.get(path)
        if data is None:
            item = root / path
            if not item.is_file():
                raise ContractError(f"missing manifest input: {path}")
            data = item.read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _rows(root, generated)
    value = {
        **base("V23-P02-C02-tooling-manifest"),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "toolingPaths": TOOL_PATHS, "toolingPathCount": len(TOOL_PATHS),
        "sourcePaths": SOURCE_PATHS, "sourcePathCount": len(SOURCE_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows, "artifactCount": len(rows), "artifactSetDigest": sha(pretty(rows)),
        "persistentSchemaActivatedByTooling": False,
        "nativeOrHostedEvidenceClaimed": False,
        "acceptanceOrReleaseClaimed": False,
        "evidenceIDs": EVIDENCE_IDS, "provisional": True, **flags(),
    }
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    envelope = envelope_contract(); receipt = receipt_contract()
    recovery = recovery_contract(); lifecycle = lifecycle_contract()
    generated = {
        ENVELOPE_SCHEMA: pretty(schema("MutationEnvelopeRegistryV1", envelope)),
        RECEIPT_SCHEMA: pretty(schema("MutationReceiptContractV1", receipt)),
        REVERSAL_SCHEMA: pretty(schema("MutationRecoveryMatrixV1", recovery)),
        LIFECYCLE_SCHEMA: pretty(schema("MutationLifecycleContractV1", lifecycle)),
        ENVELOPE_DOC: pretty(envelope), RECEIPT_DOC: pretty(receipt),
        RECOVERY_DOC: pretty(recovery), LIFECYCLE_DOC: pretty(lifecycle),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated
