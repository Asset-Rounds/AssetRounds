#!/usr/bin/env python3
"""Deterministic provisional contracts for V23-P02-C01.

The generated artifacts describe the C01 writer, revision, idempotency,
reversal-preview, and direct-writer closure boundaries. They intentionally do
not create or activate any C02 durable envelope, receipt, basis, replay, or
quarantine format.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P02-C01"
APP_BASE_HEAD = "f271eae43631d17aee2c1c1651018f1ff800949e"
APP_BASE_TREE = "65c69840898153109d8b0f0d2809d369eacdabb3"
COORDINATION_HEAD = "08254606545bb7b42a5286930b769e560816c268"
COORDINATION_TREE = "148626c3301ce57f895a52013b1aee315b037f61"
COORDINATION_CAS_SEQUENCE = 84
COORDINATION_LEDGER_DIGEST = "c37bdad80bf23ac544fb3c49bf7920f1c59bfa246e3b8af35cee39af5003fdb0"
HYDRATION_PROJECTION_DIGEST = "4ddb4e577159c8d8d94fc390510ad74c3f8108ec09cca6ddaf7bdf772c38ea45"
CONTEXT_DIGEST = "a167a0be18594ed94e61b7a58a6418abc1bf345d1ddaeceb144cf813dee9f768"
FENCE_DIGEST = "55bcd0764981d6db9bdd26874f9b70779c7a9a0c4e3c2ee19a4d51dc51c465a0"
PREREQUISITE_DIGEST = "39cd7ce015fa9084728870762f06ca4dec85bd9f41320ef29730dcc782fa6b15"
TRANSITION_DIGEST = "82a15e7313b9f98f41c4abb58397b68e3cf650c9d2913625cca7f2fcbd51d112"
REGISTER_ROW_DIGEST = "277c6a52c582ac6fcae446557f7a790909395805d90441a262da6bdf68d63687"
DOSSIER_DIGEST = "d8470d77c977b6c4076ecc5c044f9a024b46a8fe84313d7d4c1ba737e62680d4"
INHERITED_DIGEST = "f38651e27c4b0a0856978b9f8d1ee8df8434e9eaf45333bc758a670af1266299"
REGISTER_DIGEST = "edd6109aab118cc35c91495b789f70eb0b7c4d5f3d0780ad7a1918e5379e4cbd"
GRAPH_DIGEST = "4e9feb8b0cb65deddd3a5802efb380911a3439e44f1a0dc56656eadb29aac2ae"
FACET_DIGEST = "b255fe1249ef40cf835fb6717876f20eee864407c206e4ae3baf4a109ab8949f"
SELECTOR_DIGEST = "6ef4089521319677f3d69ed691d638dcc12521789c575c7939966e47670ce7f2"
RELATION_DIGEST = "9b5c7f664af7d79d219e3ca55a28352bc0da7d9ddf998033b9a82187b428fac4"
DEPENDENCY_DIGEST = "f30d779c19e94d57d9b3114c09ac07538588676606c78d2e369683ee91169b8c"
IMPACT_DIGEST = "a460620a0f0242fe0e71d8604284826204f000bb45fa09249c2db994dd0fa70b"
RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
AUTHORITY_RECEIPT_DIGEST = "07adfd64d92e9dbe27fa0011d9ab59c190da6ac5b63b99257d307434c1115752"
OVERRIDE_DIGEST = "e928e8f8415d8a35bbedbdf33a14c20c7f85f2d02600e762465eed8b48bae452"

GENERATOR_VERSION = "p02-c01-contracts-v1"
GENERATOR_SEED = 230201

FIXTURE = "FieldEvidenceAppTests/Fixtures/V21/Mutation/V21P02C01WorkspaceMutationVectorsV1.json"
CONTRACT_SCRIPT = "Scripts/v23/p02_c01_contracts.py"
GENERATOR_SCRIPT = "Scripts/v23/generate_p02_c01_contracts.py"
VERIFIER_SCRIPT = "Scripts/v23/verify_p02_c01_contracts.py"
WRITER_SCHEMA = "Scripts/v23/workspace-writer.schema.json"
REVERSAL_SCHEMA = "Scripts/v23/mutation-reversal-policy.schema.json"
BOUNDARY_SCHEMA = "Scripts/v23/mutation-boundary-closure.schema.json"
WRITER_DOC = "docs/design/v23/tooling/V23P02C01WorkspaceWriterContractV1.json"
REVERSAL_DOC = "docs/design/v23/tooling/V23P02C01MutationReversalPolicyRegistryV1.json"
BOUNDARY_DOC = "docs/design/v23/tooling/V23P02C01MutationBoundaryClosureReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P02-C01-tooling-manifest.json"

TOOL_PATHS = [
    FIXTURE, CONTRACT_SCRIPT, GENERATOR_SCRIPT, VERIFIER_SCRIPT,
    WRITER_SCHEMA, REVERSAL_SCHEMA, BOUNDARY_SCHEMA,
    WRITER_DOC, REVERSAL_DOC, BOUNDARY_DOC, MANIFEST,
]
GENERATED_PATHS = [
    FIXTURE, WRITER_SCHEMA, REVERSAL_SCHEMA, BOUNDARY_SCHEMA,
    WRITER_DOC, REVERSAL_DOC, BOUNDARY_DOC, MANIFEST,
]
MANIFEST_INPUT_PATHS = TOOL_PATHS[:-1]

EVIDENCE_IDS = [f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01")]

OPERATIONAL_COMMAND_KINDS = [
    "begin_check_draft", "capture_evidence", "confirm_site_timezone",
    "create_first_sign", "delete_asset", "delete_site", "erase_workspace",
    "finalize_check", "finalize_correction", "record_work", "restore_workspace",
]
PREVIEW_ONLY_COMMAND_KINDS = ["archive_entities_preview_compensation"]
COMMAND_KINDS = sorted(OPERATIONAL_COMMAND_KINDS + PREVIEW_ONLY_COMMAND_KINDS)

FENCED_SWIFT_PATHS = [
    "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift",
    "FieldEvidenceApp/Infrastructure/System/SystemRuntimeAdapters.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
]

DIRECT_WRITERS = [
    ("FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift", "FirstSignCoordinator.create", "CREATE_FIRST_SIGN"),
    ("FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift", "CheckRunnerCoordinator", "DRAFT_EVIDENCE_TIMEZONE_FINALIZATION"),
    ("FieldEvidenceApp/Features/Issues/WorkCoordinator.swift", "WorkCoordinator.saveWork", "RECORD_WORK"),
    ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "materializeMixedFixture", "COMPATIBILITY_FIXTURE_ONLY"),
    ("FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift", "FinalizationService", "FINALIZATION_AUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift", "FinalizationRecoveryService", "RECOVERY_ONLY"),
    ("FieldEvidenceApp/Infrastructure/Finalization/FinalizationIntentStore.swift", "FinalizationIntentStore", "FINALIZATION_JOURNAL_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift", "WholeSignDeletionService", "DELETION_AUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift", "DeletionLedgerStore", "DELETION_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift", "EraseAllService", "ERASE_AUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift", "EraseIntentStore", "ERASE_JOURNAL_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift", "OrphanFileCleanupService", "RECOVERY_ONLY"),
    ("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "BackupRestoreService.restore", "RESTORE_AUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Backup/RestoreIntentStore.swift", "RestoreIntentStore", "RESTORE_JOURNAL_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift", "StoreGenerationFactory", "GENERATION_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift", "EvidenceBundleStore", "MEDIA_FILE_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift", "ReportRenderService", "FINALIZATION_DERIVED_SUBAUTHORITY"),
    ("FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift", "ReportRecoveryService", "RECOVERY_ONLY"),
    ("FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift", "WorklightPDFRendererV1", "REPORT_FILE_SUBAUTHORITY"),
]

C02_RESERVED = [
    "MutationEnvelopeV1", "MutationReceiptV1", "ReversalBasisV1",
    "SemanticReversalReceiptV1", "durableReplayIndex", "durableMutationQuarantine",
]


class ContractError(ValueError):
    """Raised when generated C01 evidence is inconsistent."""


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


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
        "cardID": CARD,
        "attemptID": 1,
        "registerOrdinal": 21,
        "title": "Serialized WorkspaceWriter, expected revisions, idempotent MutationID, deterministic authorities, and semantic reversal",
        "classification": "IMPLEMENT_NOW",
        "planningStatus": "NOT_STARTED",
        "lineage": "EXACT_WITH_GENERATION_REBIND",
        "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "branch": "phase/v23-expansion",
        "appBaseHead": APP_BASE_HEAD,
        "appBaseTree": APP_BASE_TREE,
        "coordinationAuthorityHead": COORDINATION_HEAD,
        "coordinationAuthorityTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST,
        "contextDigest": CONTEXT_DIGEST,
        "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": TRANSITION_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST,
        "dossierDigest": DOSSIER_DIGEST,
        "inheritedV21BlockDigest": INHERITED_DIGEST,
        "foundationRegisterDigest": REGISTER_DIGEST,
        "directGraphDigest": GRAPH_DIGEST,
        "facetManifestDigest": FACET_DIGEST,
        "selectorManifestDigest": SELECTOR_DIGEST,
        "relationManifestDigest": RELATION_DIGEST,
        "dependencyDispositionDigest": DEPENDENCY_DIGEST,
        "impactManifestDigest": IMPACT_DIGEST,
        "frozenS10ReservationDigest": RESERVATION_DIGEST,
        "authorityReceiptDigest": AUTHORITY_RECEIPT_DIGEST,
        "ownerParallelOverrideAuthorityReceiptDigest": OVERRIDE_DIGEST,
        "directPrerequisites": ["V23-P01-C07"],
        "invalidationConsumers": ["V23-P02-C02"],
        "aggregateAcceptanceMemberships": ["AutonomousRequiredAcceptedSetV1"],
        "conformanceSubjects": ["KernelConformanceSubjectSetV1"],
        "deterministicEvidenceIDs": EVIDENCE_IDS,
    }


def revision_contract() -> dict[str, Any]:
    return {
        "workspaceBasis": ["workspaceID", "replicaID", "generationID"],
        "generationBasis": ["generationID", "writerInstanceID"],
        "sessionRevision": ["writerInstanceID", "ordinal"],
        "entityRevision": ["entityKind", "entityID", "sessionOrdinal"],
        "expectedRevisionRequired": True,
        "staleDisposition": "FAIL_CLOSED_NO_EFFECT",
        "crossGenerationDisposition": "FAIL_CLOSED_NO_EFFECT",
        "relaunchDisposition": "OLD_SESSION_REVISION_REJECTED",
        "durableSequenceClaimed": False,
        "persistentRevisionSchemaAdded": False,
    }


def idempotency_contract() -> dict[str, Any]:
    return {
        "mutationID": "NONZERO_CANONICAL_UUID",
        "commandDigest": "SHA256_CANONICAL_COMMAND_WITH_EXPECTED_REVISIONS",
        "activeGenerationCache": "BOUNDED_MEMORY_ONLY",
        "sameIDSameDigest": "RETURN_SAME_EPHEMERAL_OUTCOME_OR_EXISTING_EFFECT_PROOF",
        "sameIDDifferentDigest": "FAIL_CLOSED_QUARANTINED_FOR_ACTIVE_WRITER_ONLY",
        "postRestart": "DELEGATE_EXISTING_INTENT_RECOVERY_THEN_REJECT_STALE_SESSION_REVISION",
        "durableReplayClaimed": False,
        "durableQuarantineClaimed": False,
        "c02Owner": "V23-P02-C02",
    }


def deterministic_authorities() -> dict[str, Any]:
    return {
        "clock": "ApplicationClock",
        "idSource": "ApplicationIDSource",
        "sleeper": "ApplicationSleeper",
        "fileAuthority": "GENERATION_ROOT_PINNED_ROLE_DERIVATION",
        "operationIDRule": "MutationIDV1_REUSED_AS_EXISTING_INTENT_OPERATION_ID",
        "childIDRule": "ROLE_STABLE_BOUNDED_OPERATION_SCOPED_ALLOCATION",
        "directDateUUIDReadsInsideCanonicalMutationAllowed": False,
    }


def deferred_writers() -> list[dict[str, Any]]:
    integrated = {
        "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
        "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    }
    rows = []
    for path, symbol, role in DIRECT_WRITERS:
        rows.append({
            "path": path,
            "symbol": symbol,
            "role": role,
            "observedAtBaseTree": APP_BASE_TREE,
            "disposition": (
                "FENCED_CANDIDATE_REBIND_IMPLEMENTED_STATIC_ONLY"
                if path in integrated
                else "RESERVED_DEFERRED_TO_RECONCILIATION_OR_ACCEPTED_SUBAUTHORITY"
            ),
            "closureClaimed": False,
        })
    return rows


def writer_contract() -> dict[str, Any]:
    value = {
        "schema": "WorkspaceWriterContractV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "writer": {
            "type": "WorkspaceWriterV1",
            "isolation": "MAIN_ACTOR_SERIAL_APPLICATION_SERVICE",
            "instanceCardinality": "EXACTLY_ONE_PER_ACTIVE_WORKSPACE_GENERATION",
            "commandType": "WorkspaceCommandV1",
            "queryType": "WorkspaceQueryClientV1",
            "temporaryAdapter": "WorkspaceWriterAdapterV1",
            "adapterRemovalOwner": "V23-P02-C02",
            "commands": COMMAND_KINDS,
            "operationalCommands": OPERATIONAL_COMMAND_KINDS,
            "previewOnlyCommands": PREVIEW_ONLY_COMMAND_KINDS,
            "previewOnlyDisposition": "TYPED_SEMANTIC_PLAN_ONLY_PRODUCTION_ADAPTER_REJECTS",
        },
        "revisionContract": revision_contract(),
        "idempotencyContract": idempotency_contract(),
        "deterministicAuthorities": deterministic_authorities(),
        "generationActivation": {
            "oldWriterDisposition": "INVALIDATE_BEFORE_NEW_SESSION_PUBLICATION",
            "newWriterDisposition": "CREATE_EXACTLY_ONCE_FOR_ACTIVATED_SESSION",
            "restoreEraseCASPreserved": True,
            "startupRecoveryOrderPreserved": True,
        },
        "existingIntentAuthorities": [
            {"command": "finalize_check", "operationField": "finalizationMutationID", "journal": "FinalizationIntentV1"},
            {"command": "delete_asset", "operationField": "deletionID", "journal": "DeletionIntentV1"},
            {"command": "erase_workspace", "operationField": "eraseID", "journal": "EraseIntentV1"},
            {"command": "restore_workspace", "operationField": "restoreID", "journal": "RestoreIntentV1"},
        ],
        "c02Reservation": {
            "owner": "V23-P02-C02",
            "reservedArtifacts": C02_RESERVED,
            "persistentArtifactCreatedByC01": False,
            "activationAllowed": False,
        },
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    }
    return seal(value)


def reversal_rows() -> list[dict[str, Any]]:
    values = {
        "archive_entities_preview_compensation": ("COMPENSATABLE", "APPEND_SEMANTIC_SUCCESSOR_ONLY"),
        "begin_check_draft": ("REVERSIBLE", "RESTORE_BOUNDED_DRAFT_PREIMAGE"),
        "capture_evidence": ("IRREVERSIBLE", "PURGED_OR_ESCAPED_MEDIA_MUST_NOT_BE_RESURRECTED"),
        "confirm_site_timezone": ("REVERSIBLE", "RESTORE_PRIOR_CANONICAL_TIMEZONE_IF_UNCHANGED"),
        "create_first_sign": ("COMPENSATABLE", "EXPLICIT_DEPENDENCY_CHECKED_DELETE_ONLY"),
        "delete_asset": ("IRREVERSIBLE", "DELETION_LEDGER_AND_PURGED_CONTENT"),
        "delete_site": ("IRREVERSIBLE", "DELETION_LEDGER_AND_PURGED_CONTENT"),
        "erase_workspace": ("IRREVERSIBLE", "ERASE_IS_NEVER_REVERSIBLE"),
        "finalize_check": ("IRREVERSIBLE", "IMMUTABLE_FINALIZED_ARTIFACT_SUPERSESSION_ONLY"),
        "finalize_correction": ("IRREVERSIBLE", "IMMUTABLE_CORRECTION_CHAIN_SUPERSESSION_ONLY"),
        "record_work": ("IRREVERSIBLE", "COMPLETED_RECORD_AND_EVIDENCE_SUPERSESSION_ONLY"),
        "restore_workspace": ("IRREVERSIBLE", "GENERATION_PUBLICATION_AND_IDENTITY_TRANSFORMATION"),
    }
    return [
        {
            "commandKind": command,
            "classification": values[command][0],
            "reason": values[command][1],
            "previewAvailable": values[command][0] != "IRREVERSIBLE",
            "commitActive": False,
        }
        for command in COMMAND_KINDS
    ]


def reversal_contract() -> dict[str, Any]:
    value = {
        "schema": "MutationReversalPolicyRegistryV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "registry": reversal_rows(),
        "closedCommandKinds": COMMAND_KINDS,
        "previewOnlyCommandKinds": PREVIEW_ONLY_COMMAND_KINDS,
        "unknownCommandDisposition": "FAIL_CLOSED_IRREVERSIBLE",
        "preview": {
            "type": "SemanticReversalPlanV1",
            "requiredBindings": [
                "mutationID", "currentWorkspaceRevision", "currentEntityRevisions",
                "prospectiveTargetIdentity", "boundedSemanticValues",
                "contentReferences", "dependencyGraph", "conflicts",
                "compensatingCommands", "planDigest",
            ],
            "eligibilityBasis": "GRAPH_AND_REVISION_NOT_TIME_ONLY",
            "batchSemantics": "ALL_OR_NOTHING_UNLESS_NEW_ELIGIBLE_ITEMS_ONLY_PLAN",
            "maximumSemanticValueBytes": 1048576,
            "maximumDependencyCount": 256,
            "unboundedPreimageAllowed": False,
        },
        "activation": {
            "previewOnly": True,
            "commitEnabled": False,
            "basisPersistenceEnabled": False,
            "receiptPersistenceEnabled": False,
            "activationOwner": "V23-P02-C02",
        },
        "c02Reservation": C02_RESERVED,
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    }
    return seal(value)


def boundary_contract() -> dict[str, Any]:
    value = {
        "schema": "MutationBoundaryClosureReceiptV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "receiptStatus": "PROVISIONAL_INVENTORY_NOT_CLOSURE_ACCEPTANCE",
        "closureClaimed": False,
        "reservedDeferredDirectWriters": deferred_writers(),
        "requiredClosure": {
            "productionFeatureOwnedInsertSaveDeleteRemaining": 0,
            "writerInstancesPerActiveWorkspaceGeneration": 1,
            "viewsOwnRawModelContextWrites": False,
            "featureCoordinatorsOwnRawModelContextWrites": False,
            "recoveryServicesRemainAdapterSubauthorities": True,
            "backupExportImportAreQueriesUntilRestore": True,
        },
        "observedProvisionalBoundary": {
            "fencedCandidateReboundPaths": [
                "FieldEvidenceApp/Features/Signs/FirstSignCoordinator.swift",
                "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
            ],
            "reservedFeatureDirectWritePaths": [
                "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
                "FieldEvidenceApp/Features/Shell/AppShellView.swift",
            ],
            "productionFeatureOwnedInsertSaveDeleteRemaining": 2,
            "viewsOwnRawModelContextWrites": True,
            "featureCoordinatorsOwnRawModelContextWrites": True,
            "acceptanceBlockedUntilReconciliation": True,
        },
        "scannerRules": {
            "forbiddenProductionCalls": ["ModelContext.insert", "ModelContext.save", "ModelContext.delete"],
            "allowedBehindTemporaryAdapterOnly": True,
            "testAndCompatibilityFixtureExceptionsMustBeNamed": True,
            "unknownWriterDisposition": "FAIL_CLOSED",
        },
        "c02AbsenceProof": {
            "reservedNames": C02_RESERVED,
            "durableEnvelopeSchemaPresent": False,
            "durableReceiptSchemaPresent": False,
            "durableReversalBasisPresent": False,
            "durableReplayOrQuarantinePresent": False,
        },
        "evidenceIDs": EVIDENCE_IDS,
        "provisional": True,
        **flags(),
    }
    return seal(value)


def mutation_fixture() -> dict[str, Any]:
    vectors = [
        ("G01", "EXPECTED_REVISION_SUCCESS", "ACCEPT_ONCE_IN_SERIAL_ORDER"),
        ("A01", "SAME_ID_SAME_DIGEST_RETRY", "RETURN_SAME_EPHEMERAL_OUTCOME"),
        ("H01", "SAME_ID_CHANGED_DIGEST", "FAIL_CLOSED_ACTIVE_WRITER_QUARANTINE"),
        ("H01", "STALE_ENTITY_REVISION", "FAIL_CLOSED_NO_EFFECT"),
        ("H01", "UNKNOWN_COMMAND_OR_REVERSAL_POLICY", "FAIL_CLOSED_IRREVERSIBLE"),
        ("I01", "CANCEL_BEFORE_ADAPTER_EFFECT", "NO_EFFECT"),
        ("I01", "INTERRUPT_EXISTING_INTENT_PHASE", "EXISTING_JOURNAL_RECOVERY_ONLY"),
        ("R01", "RELAUNCH_OLD_SESSION_REVISION", "REJECT_STALE_NO_EFFECT"),
        ("R01", "RESTORE_OR_ERASE_GENERATION_SWITCH", "INVALIDATE_OLD_WRITER_CREATE_ONE_NEW"),
    ]
    value = {
        "schema": "V21P02C01WorkspaceMutationVectorsV1",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "synthetic": True,
        "containsCustomerData": False,
        "containsSecrets": False,
        "licenseIdentifier": "SYNTHETIC_INTERNAL_FIXTURE_V1",
        "workspaceIdentity": {
            "workspaceID": "21000000-0000-0000-0000-000000000001",
            "replicaID": "21000000-0000-0000-0000-000000000002",
            "generationID": "21000000-0000-0000-0000-000000000003",
        },
        "mutationID": "21000000-0000-0000-0000-000000000004",
        "commandDigest": sha(canonical({"command": "finalize_check", "expectedRevision": 7})),
        "changedCommandDigest": sha(canonical({"command": "finalize_check", "expectedRevision": 8})),
        "vectors": [
            {"evidenceFamily": family, "case": case, "expected": expected}
            for family, case, expected in vectors
        ],
        "reversalVectors": reversal_rows(),
        "c02ArtifactsPresent": [],
        "c02ReservedNames": C02_RESERVED,
        "provisional": True,
        **flags(),
    }
    return seal(value)


def _strict_shape(value: Any, *, artifact_digest: bool = False) -> dict[str, Any]:
    """Return an exact-key recursive schema while leaving digests reusable."""
    if isinstance(value, dict):
        properties = {
            key: _strict_shape(child, artifact_digest=(key == "artifactDigest"))
            for key, child in value.items()
        }
        return {
            "type": "object",
            "additionalProperties": False,
            "required": list(value.keys()),
            "properties": properties,
        }
    if isinstance(value, list):
        item_schemas = [_strict_shape(item) for item in value]
        return {
            "type": "array",
            "minItems": len(value),
            "maxItems": len(value),
            "prefixItems": item_schemas,
            "items": False,
        }
    if isinstance(value, bool):
        return {"const": value}
    if isinstance(value, int):
        return {"const": value}
    if value is None:
        return {"type": "null"}
    if artifact_digest:
        return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    return {"const": value}


def _strict_document_schema(title: str, value: dict[str, Any]) -> dict[str, Any]:
    result = _strict_shape(value)
    result.update({
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": f"https://assetrounds.invalid/v23/{value['schema']}.schema.json",
        "title": title,
    })
    return result


def writer_schema() -> dict[str, Any]:
    return _strict_document_schema("WorkspaceWriterContractV1", writer_contract())


def reversal_schema() -> dict[str, Any]:
    return _strict_document_schema("MutationReversalPolicyRegistryV1", reversal_contract())


def boundary_schema() -> dict[str, Any]:
    return _strict_document_schema("MutationBoundaryClosureReceiptV1", boundary_contract())


def _artifact_rows(root: Path, generated: dict[str, bytes]) -> list[dict[str, Any]]:
    rows = []
    for path in MANIFEST_INPUT_PATHS:
        data = generated.get(path)
        if data is None:
            item = root / path
            if not item.is_file():
                raise ContractError(f"missing tooling input: {path}")
            data = item.read_bytes()
        rows.append({"path": path, "bytes": len(data), "sha256": sha(data)})
    return rows


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    rows = _artifact_rows(root, generated)
    value = {
        "schema": "V23-P02-C01-tooling-manifest",
        "schemaVersion": 1,
        "cardID": CARD,
        "authority": authority(),
        "generator": {"version": GENERATOR_VERSION, "seed": GENERATOR_SEED},
        "pathFence": TOOL_PATHS,
        "toolingPathCount": len(TOOL_PATHS),
        "generatedPaths": GENERATED_PATHS,
        "artifacts": rows,
        "artifactCount": len(rows),
        "artifactSetDigest": sha(pretty(rows)),
        "evidenceIDs": EVIDENCE_IDS,
        "boundaryClosureClaimed": False,
        "c02ArtifactsActivated": False,
        "provisional": True,
        **flags(),
    }
    return seal(value)


def all_outputs(root: Path) -> dict[str, bytes]:
    generated: dict[str, bytes] = {
        FIXTURE: pretty(mutation_fixture()),
        WRITER_SCHEMA: pretty(writer_schema()),
        REVERSAL_SCHEMA: pretty(reversal_schema()),
        BOUNDARY_SCHEMA: pretty(boundary_schema()),
        WRITER_DOC: pretty(writer_contract()),
        REVERSAL_DOC: pretty(reversal_contract()),
        BOUNDARY_DOC: pretty(boundary_contract()),
    }
    generated[MANIFEST] = pretty(tooling_manifest(root, generated))
    return generated
