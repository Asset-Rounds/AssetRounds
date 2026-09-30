#!/usr/bin/env python3
"""Deterministic, language-neutral contract projections for V23-P03-C11.

This module deliberately contains no runtime application behaviour.  It binds the
hydrated Card 40 authority, projects the fixed corpus into a strict Draft 2020-12
schema, and computes the two sealed contract documents plus their manifest.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C11"
TITLE = "Delivery-neutral change journal, WorkspaceSnapshotManifestV1 checkpoints, bounded compaction, and deterministic isolated replay"
APP_BASE_HEAD = "716f3d049c443725fdf4ce4572e7aecb241a39d8"
APP_BASE_TREE = "d8a94fd319db84e804b755ea770ffd96804b3cc4"
CONTEXT_DIGEST = "c7f893ea349af7bf9ece0f55d2c3c6031339c33441b096eeafa44e718c1b0987"
FENCE_DIGEST = "c5a789b3ecc2e550050309673115ac8190239af5efcc63bacec0ea20262aa9d1"
PREREQUISITE_DIGEST = "3bc4ace9cd38872122e28a23621891297e6d4c3a9e01f2d30be4bd47856e4d2c"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
INHERITED_BLOCK_DIGEST = "4c46417e297587999b92472bd41a0e4912bf71025e723faafea189ec2b6406dc"
DOSSIER_DIGEST = "9db3cd172ee34cb66eca678983ab545591aff1a045d98588e7688800ae945426"
REGISTER_ROW_DIGEST = "53dea30dc0ea14eefa15c411a42421e8df4fcd8c411f66f4c67be5826a105118"
REGISTER_SECTION_DIGEST = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
COORDINATION_LEDGER_DIGEST = "fd8af3b70448dde967df5de8863f9b585cb92e606cd29a063a92ca5480ad521f"
COORDINATION_CAS_SEQUENCE = 167

SOURCE_PATHS = [
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/ChangeJournal/V21P03C11ChangeJournalCheckpointReplayCorpusV1.json",
]
SCRIPT_PATHS = [
    "Scripts/v23/p03_c11_contracts.py",
    "Scripts/v23/generate_p03_c11_contracts.py",
    "Scripts/v23/verify_p03_c11_contracts.py",
]
SCHEMA_PATH = "Scripts/v23/change-journal-checkpoint-replay.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C11ChangeJournalCheckpointReplayContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C11ChangeJournalCheckpointReplayEvidenceReceiptV1.json"
MANIFEST = "docs/design/v23/tooling/V23-P03-C11-tooling-manifest.json"
GENERATED_PATHS = [SCHEMA_PATH, CONTRACT_PATH, EVIDENCE_PATH, MANIFEST]
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
EXISTING_PATHS = SOURCE_PATHS[:2]
NEW_PATHS = PATH_FENCE[2:]
FIXTURE = SOURCE_PATHS[-1]
TEST_PATH = SOURCE_PATHS[4]
EVIDENCE_IDS = [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
TEST_METHODS = [
    "testV9_ChangeJournalCheckpointReplayG01CheckpointThenPostRIsSemanticallyExact",
    "testV9_ChangeJournalCheckpointReplayA01BoundedSchedulesContentResumeAndScale",
    "testV9_ChangeJournalCheckpointReplayH01HostileContentConflictsAndReleaseAbsence",
    "testV9_ChangeJournalCheckpointReplayI01CrashMatrixIsRestartSafeAtEveryBoundary",
    "testV9_ChangeJournalCheckpointReplayR01ReplicaConvergenceReversalRollbackAndCompaction",
]

FIXED_SEED = "v21-p03-c11-fixed-seed-2026-08-27"
WORKSPACE_ID = "11111111-1111-4111-8111-111111111111"
SOURCE_REPLICA_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
SCALE_GENERATION_RULE = "INDEX_ASCENDING_UTF8_LINE"
CHECKPOINT_ID = "2222222222224222822222222222222222222222222242228222222222222222"
DESTINATION_REPLICA_IDS = [
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
]
FORBIDDEN_PRODUCTION_SYMBOLS = [
    "Replica" + "ConvergenceScenarioV1",
    "Replica" + "DeliveryScheduleV1",
    "Replica" + "ConvergenceReceiptV1",
]
FORBIDDEN_PRODUCTION_PATHS = [
    "FieldEvidenceApp/Domain/Replication/Replica" + "ConvergenceScenarioV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/Network" + "Transport.swift",
    "FieldEvidenceApp/Infrastructure/Replication/Provider" + "Outbox.swift",
]

# Frozen Phase 10 reservation copied from the hydrated fence.  It is embedded so
# the disjointness proof does not depend on a mutable coordination checkout.
ACTIVE_S10_RESERVED_PATHS = [
    ".github/workflows/ios-ci-worker.yml", ".github/workflows/ios-ci.yml", "AGENTS.md",
    "FieldEvidenceApp.xcodeproj/project.pbxproj",
    "FieldEvidenceApp.xcodeproj/xcshareddata/xcschemes/FieldEvidenceApp.xcscheme",
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift", "FieldEvidenceApp/App/LaunchView.swift",
    "FieldEvidenceApp/DesignSystem/DesignTokens.swift", "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
    "FieldEvidenceApp/Features/Issues/IssueDetailView.swift", "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
    "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
    "FieldEvidenceApp/Features/Sample/PackSampleView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
    "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "FieldEvidenceApp/Features/Signs/NewSignView.swift", "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
    "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
    "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
    "FieldEvidenceApp/Infrastructure/Commerce/StoreKitTransactionProcessor.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/FinalizationService.swift",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Default-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted-1024.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsAccentTeal.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandCanvas.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-1x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-2x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/AssetRoundsBrandSymbol-3x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbol.imageset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-1x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-2x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/AssetRoundsBrandSymbolTemplate-3x.png",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsBrandSymbolTemplate.imageset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsCheckpointGreen.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsDeepTeal.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsInk.colorset/Contents.json",
    "FieldEvidenceApp/Resources/Assets.xcassets/AssetRoundsSlate.colorset/Contents.json",
    "FieldEvidenceAppTests/S10_1BrandInventoryTests.swift", "FieldEvidenceAppTests/S10_2BrandComponentTests.swift",
    "FieldEvidenceAppTests/S10_3BrandMigrationTests.swift", "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests.swift",
    "FieldEvidenceAppUITests/S10_1BrandInventoryUITests.swift", "FieldEvidenceAppUITests/S10_2BrandComponentUITests.swift",
    "FieldEvidenceAppUITests/S10_3BrandMigrationUITests.swift", "Scripts/ci-selection.json",
    "Scripts/s10-4-segment-assembler.sh", "Scripts/s10-4-segment-plan.json", "Scripts/s10-4-shards.json",
    "Scripts/ui-smoke.sh", "docs/design/s10/authority/asset-manifest.json",
    "docs/design/s10/authority/assetrounds-brand-assets-v4.1-20260815.zip",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/manifest.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-accessibility-common-tasks.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/s10-visual-regression.schema.json",
    "docs/design/s10/authority/s10.4-automation-amendment-v1/validate-s10-contracts.ps1",
    "docs/design/s10/s10-accessibility-common-tasks.json", "docs/design/s10/s10-activation.json",
    "docs/design/s10/s10-experience-validation.json", "docs/design/s10/s10-screen-state-inventory.json",
    "docs/design/s10/s10-stage-checkpoints.json", "docs/design/s10/s10-store-readiness.json",
    "docs/design/s10/s10-token-coverage.json", "docs/design/s10/s10-visual-regression.json",
    "docs/execution/CODEX_EXECUTION_CONTRACT_V4.md", "docs/execution/CURRENT_TASK.md",
    "docs/execution/HANDOFF.md", "docs/execution/V4_IMPLEMENTATION_RUNBOOK.md", "docs/product/BUILD_PLAN_V4.md",
]

SEMANTIC_SCOPE = {
    "durableOwner": ["ChangeJournalContractsV1", "LocalChangeJournalV1", "WorkspaceSnapshotManifestV1", "ChangeBatchV1"],
    "journalPolicy": "IMMUTABLE_DELIVERY_NEUTRAL_WORKSPACE_SCOPED_CHANGE_RECEIPTS_WITH_STABLE_REPLICA_CURSOR_AND_BOUNDED_CHANGE_BATCHES",
    "checkpointPolicy": "CHECKPOINT_FIRST_BOOTSTRAP_USES_VERIFIED_WORKSPACE_SNAPSHOT_MANIFEST_V1_THEN_INCREMENTAL_PAGES_FROM_THE_EXACT_BOUND_CURSOR",
    "compactionPolicy": "BOUNDED_COMPACTION_IS_ALLOWED_ONLY_AFTER_A_COMPLETE_VERIFIED_CHECKPOINT_AND_PRESERVES_REPLAY_REVERSAL_AND_CONTENT_DEPENDENCIES",
    "replayPolicy": "ISOLATED_LOCAL_REPLAY_USES_THE_SAME_WORKSPACE_WRITER_AND_FAILS_CLOSED_FOR_DUPLICATES_REORDERING_INTERRUPTION_MISSING_CONTENT_AND_RESTART",
    "convergencePolicy": "TWO_WORKSPACE_ISOLATION_AND_TEST_ONLY_A_B_AND_A_B_C_REPLICA_SCENARIOS_PROVE_DETERMINISTIC_CONVERGENCE_WITHOUT_CROSS_WORKSPACE_EFFECTS",
    "backupPolicy": "BACKUP_RESTORE_CLONE_FORK_DELETE_ERASE_AND_OPEN_EXPORT_PRESERVE_OR_EXPLICITLY_DISPOSE_JOURNAL_CHECKPOINT_AND_COMPACTION_STATE",
    "deliveryNeutralPolicy": "NO_PROVIDER_OUTBOX_NETWORK_BACKEND_ACCOUNT_TENANCY_REMOTE_SYNC_OR_DELIVERY_STATUS_IS_CREATED_OR_CLAIMED",
    "persistencePolicy": "CONTENT_ONLY_NO_SCHEMA_OR_MIGRATION_DELTA_AND_DOWNGRADE_IS_CONTENT_ROLLBACK_ONLY",
    "s10Policy": "CARD_PATH_FENCE_HAS_ZERO_S10_RESERVED_PATH_OVERLAP_AND_CARRIES_NO_C08_RESERVED_OWNER_OR_RAW_WRITE_DEBT",
    "activationPolicy": "PROVISIONAL_STATIC_CONTRACT_FIXTURE_AND_TEST_SEAMS_ONLY_NATIVE_HOSTED_ADOPTION_ACCEPTANCE_RELEASE_AND_PHASE10_POLLING_DEFERRED_PENDING_ACCEPTED_S10_6_RECONCILIATION",
}

FAILURE_CASES = [
    "DUPLICATE_BATCH", "OUT_OF_ORDER_BATCH", "TRUNCATED_BATCH", "TAMPERED_BATCH", "FUTURE_VERSION_BATCH",
    "MISSING_CONTENT", "CORRUPT_CONTENT", "MANIFEST_MISMATCH", "CHECKPOINT_INTERRUPTION", "PAGE_INTERRUPTION",
    "REPLAY_INTERRUPTION", "ACTIVATION_INTERRUPTION", "COMPACTION_INTERRUPTION", "OLD_BACKUP_RESURRECTION",
    "DELETE_VERSUS_UPDATE", "SAME_FIELD_CONFLICT", "FOREIGN_WORKSPACE", "STALE_CURSOR", "REUSED_REPLICA_ID",
    "CANCELLATION", "LOW_STORAGE",
]
OPTIONAL_CODABLE_FIELDS = [
    "ChangeCursorV1.previousBatchSHA256", "ReversalEligibilitySnapshotV1.portablePlan",
    "ReversalEligibilitySnapshotV1.reversingMutationID", "ReversalEligibilitySnapshotV1.basisSHA256",
    "EntityChangeV1.conflictIdentity", "JournalChangeV1.reversalBasis",
    "JournalChangeV1.portableReversalPlan", "JournalChangeV1.semanticReversalReceipt",
    "MutationReplayDispositionV1.conflictIdentity",
    "MutationReplayDispositionV1.reasonCode",
]

CODABLE_FIELDS = {
    "ChangeJournalLimitsV1": ["schemaVersion", "maximumChangesPerBatch", "maximumBatchBytes",
                              "maximumEntitiesPerCheckpoint", "maximumContentEntriesPerCheckpoint",
                              "maximumReplicaFrontiers", "maximumConflicts"],
    "ReplicaRevisionFrontierV1": ["replicaID", "localSequence"],
    "ChangeJournalFrontierV1": ["schemaVersion", "workspaceRevision", "replicas",
                                 "entityRevisionSHA256", "observedMutationSetSHA256"],
    "ChangeCursorV1": ["schemaVersion", "workspaceID", "consumerReplicaID", "checkpointID",
                       "frontierSHA256", "nextOrdinal", "previousBatchSHA256"],
    "CheckpointPackageDigestV1": ["packageID", "packageSchemaVersion", "contentVersion", "packageSHA256"],
    "WorkspaceSnapshotManifestV1": ["schemaVersion", "workspaceID", "sourceReplicaID",
                                    "sourceGenerationID", "persistentSchemaVersion",
                                    "persistentSchemaSHA256", "recordSchemaVersion",
                                    "recordSchemaSHA256", "packages", "frontier",
                                    "normalizedRecordsSHA256", "tombstonesSHA256",
                                    "contentManifestSHA256", "reversalEligibilitySHA256",
                                    "checkpointID", "manifestSHA256"],
    "CheckpointContentEntryV1": ["reference", "archiveRelativePath"],
    "PortableReversalPlanV1": ["schemaVersion", "targetMutationID", "targetReceiptIdentity",
                               "expectedRevision", "planDigest", "compensatingCommands"],
    "ReversalEligibilitySnapshotV1": ["targetMutationID", "eligibility", "portablePlan",
                                      "reversingMutationID", "basisSHA256"],
    "WorkspaceCheckpointContentV1": ["schemaVersion", "manifest", "normalizedRecordData",
                                     "tombstoneIdentities", "contentEntries", "reversalEligibility"],
    "EntityChangeV1": ["identity", "postImage", "conflictPolicy", "conflictIdentity"],
    "JournalChangeV1": ["schemaVersion", "envelope", "receipt", "entityChanges",
                        "reversalBasis", "portableReversalPlan", "semanticReversalReceipt",
                        "contentReferences"],
    "ChangeBatchV1": ["schemaVersion", "workspaceID", "sourceReplicaID", "checkpointID",
                      "beforeCursor", "afterCursor", "changes", "batchSHA256"],
    "MutationReplayDispositionV1": ["mutationID", "disposition", "missingContentIDs",
                                    "conflictIdentity", "reasonCode"],
    "ChangeReplayReceiptV1": ["schemaVersion", "workspaceID", "destinationReplicaID",
                              "destinationGenerationID", "batchSHA256", "resultingFrontier",
                              "dispositions", "semanticProjectionSHA256", "receiptSHA256"],
    "CheckpointActivationReceiptV1": ["schemaVersion", "workspaceID", "destinationReplicaID",
                                      "destinationGenerationID", "checkpointID", "manifestSHA256",
                                      "activatedFrontier", "semanticProjectionSHA256",
                                      "contentDispositionSHA256", "receiptSHA256"],
    "ChangeJournalCompactionReceiptV1": ["schemaVersion", "workspaceID", "sourceReplicaID",
                                         "checkpointID", "checkpointManifestSHA256",
                                         "compactedThrough", "preservedReceiptSetSHA256",
                                         "preservedReversalBasisSetSHA256", "removedChangeCount",
                                         "canonicalHistoryDeleted", "receiptSHA256"],
    "SemanticConvergenceProjectionV1": ["schemaVersion", "workspaceID", "canonicalSnapshotSHA256",
                                        "tombstoneIdentities", "unresolvedConflictIdentities",
                                        "contentDispositionSHA256", "observedMutationIDs", "semanticSHA256"],
    "CheckpointArchiveEntryDigestV1": ["relativePath", "byteCount", "sha256"],
    "WorkspaceCheckpointPreparationV1": ["schemaVersion", "preparationID", "manifest",
                                         "entries", "preparationSHA256"],
    "WorkspaceCheckpointExportV1": ["schemaVersion", "preparationID", "workspaceID",
                                    "checkpointID", "packageRelativePath", "packageByteCount",
                                    "packageSHA256", "manifestSHA256", "exportSHA256"],
}
CODABLE_ENUMS = {
    "PortableReversalEligibilityV1": ["ELIGIBLE", "ALREADY_REVERSED", "SUPERSEDED", "IRREVERSIBLE", "ERASED"],
    "ChangeReplayDispositionV1": ["APPLIED", "ALREADY_APPLIED", "DEFERRED_GAP",
                                  "DEFERRED_CONTENT", "UNRESOLVED_CONFLICT", "DELETE_WON",
                                  "DERIVED_REBUILD", "LOCAL_ONLY_EXCLUDED", "REJECTED"],
}


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def authority() -> dict[str, Any]:
    return {
        "cardID": CARD, "attemptID": 1, "executionMode": "PRE_S10_6_PROVISIONAL_ORDERED_IMPLEMENTATION",
        "appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE,
        "contextDigest": CONTEXT_DIGEST, "fenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "frozenS10ReservationDigest": S10_RESERVATION_DIGEST,
        "inheritedV21BlockDigest": INHERITED_BLOCK_DIGEST, "dossierDigest": DOSSIER_DIGEST,
        "registerRowDigest": REGISTER_ROW_DIGEST, "registerSectionDigest": REGISTER_SECTION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "persistentChangeMode": "CONTENT_ONLY", "persistentContractSchema": "NOT_APPLICABLE",
        "schemaBehaviorDelta": False, "migrationBehaviorDelta": False,
        "backupBehaviorDelta": True, "restoreBehaviorDelta": True, "deleteBehaviorDelta": True,
        "exportBehaviorDelta": True, "downgradeDisposition": "CONTENT_ROLLBACK_ONLY",
        "writerAuthority": {"ownerID": "A00_BOOTSTRAP_CONTROLLER", "writerGeneration": 0},
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "physicalEvidenceComplete": False,
        "physicalLockedState": "REQUIRED_PENDING_OWNER", "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True,
    }


def source_rows(root: Path) -> list[dict[str, Any]]:
    rows = []
    for relative in SOURCE_PATHS:
        path = root / relative
        if not path.is_file():
            raise ContractError(f"missing source artifact: {relative}")
        raw = path.read_bytes()
        rows.append({"path": relative, "bytes": len(raw), "sha256": digest(raw)})
    return rows


def fixture(root: Path) -> dict[str, Any]:
    path = root / FIXTURE
    if not path.is_file():
        raise ContractError(f"missing fixture: {FIXTURE}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ContractError(f"invalid fixture JSON: {error}") from error
    if not isinstance(value, dict):
        raise ContractError("fixture root must be an object")
    return value


def _sha_schema() -> dict[str, Any]:
    return {"type": "string", "pattern": "^[0-9a-f]{64}$"}


def _uuid_schema() -> dict[str, Any]:
    return {"type": "string", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"}


def _nullable(inner: dict[str, Any]) -> dict[str, Any]:
    return {"anyOf": [inner, {"type": "null"}]}


def _strict(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {
        "type": "object", "additionalProperties": False, "properties": properties,
        "required": required if required is not None else list(properties),
    }


def _array(items: dict[str, Any], *, minimum: int = 0, maximum: int | None = None,
           unique: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "array", "items": items, "minItems": minimum}
    if maximum is not None:
        result["maxItems"] = maximum
    if unique:
        result["uniqueItems"] = True
    return result


def _exact_array(values: list[Any]) -> dict[str, Any]:
    return {
        "type": "array", "prefixItems": [{"const": value} for value in values],
        "items": False, "minItems": len(values), "maxItems": len(values),
    }


def change_journal_schema() -> dict[str, Any]:
    sha = _sha_schema()
    uuid = _uuid_schema()
    null_sha = _nullable(sha)
    null_uuid = _nullable(uuid)
    change = _strict({
        "sequence": {"type": "integer", "minimum": 1},
        "mutationID": uuid, "kind": {"enum": ["UPSERT", "CONTENT_ATTACH", "SEMANTIC_REVERSAL", "TOMBSTONE"]},
        "entity": {"type": "string", "minLength": 1, "maxLength": 256},
        "canonicalInputSHA256": sha, "contentSHA256": null_sha, "reversesMutationID": null_uuid,
    }, ["sequence", "mutationID", "kind", "entity", "canonicalInputSHA256"])
    page = _strict({
        "pageID": {"type": "string", "pattern": "^page-[0-9]+-[0-9]+$"},
        "afterSequence": {"type": "integer", "minimum": 0},
        "throughSequence": {"type": "integer", "minimum": 1},
        "sequences": _array({"type": "integer", "minimum": 1}, minimum=1, maximum=128, unique=True),
        "isTerminal": {"type": "boolean"}, "pageSHA256": sha,
    })
    replay = _strict({
        "id": {"type": "string", "minLength": 1, "maxLength": 128},
        "deliveries": _array({"type": "string", "minLength": 1}, minimum=1, maximum=64),
        "expectedDisposition": {"enum": [
            "APPLIED_TO_46", "GAP_BUFFERED_THEN_APPLIED_DUPLICATES_IGNORED",
            "DURABLE_GAP_RESUMED_TO_46", "REJECTED_GAP_BOUND_EXCEEDED_NO_EFFECT",
        ]},
        "expectedSemanticSHA256": sha,
    })
    content = _strict({
        "id": {"type": "string", "minLength": 1, "maxLength": 128},
        "sequence": {"type": "integer", "minimum": 1},
        "observedSHA256": null_sha, "resumeSHA256": null_sha,
        "expectedDisposition": {"enum": ["APPLIED", "DEFERRED_THEN_APPLIED",
                                         "QUARANTINED_THEN_APPLIED_FROM_VERIFIED_BYTES"]},
    }, ["id", "sequence", "expectedDisposition"])
    conflict = _strict({
        "id": {"type": "string", "minLength": 1, "maxLength": 128},
        "competitors": _array({"type": "string", "minLength": 1}, minimum=2, maximum=3, unique=True),
        "policy": {"enum": ["DELETE_WINS", "MANUAL"]},
        "expectedDisposition": {"enum": [
            "TOMBSTONED_NO_RESURRECTION", "UNRESOLVED_STABLE_CONFLICT_ID",
            "DELETE_WINS_NO_RESURRECTION", "CAUSALLY_DEFERRED_THEN_RESOLVED",
            "EARLIER_BASIS_REMAINS_RESOLVED_SUCCESSOR_CONFLICT_CREATED",
        ]},
    })
    crash = _strict({
        "boundary": {"enum": [
            "CHECKPOINT_PREPARED", "CHECKPOINT_COMMITTED", "PAGE_PREPARED", "PAGE_COMMITTED",
            "REPLAY_AFTER_EFFECT_BEFORE_CURSOR", "ACTIVATION_PRE_POINTER", "ACTIVATION_POST_POINTER",
            "COMPACTION_PRE_REPLACEMENT", "COMPACTION_POST_REPLACEMENT",
        ]},
        "expected": {"type": "string", "minLength": 1, "maxLength": 128},
    })
    schedule = _strict({
        "id": {"type": "string", "minLength": 1, "maxLength": 128},
        "replicas": _array({"type": "string", "pattern": "^[A-Z]$"}, minimum=2, maximum=3, unique=True),
        "deliveries": _array({"type": "string", "minLength": 1}, minimum=1, maximum=64),
        "expectedQuiescenceRounds": {"type": "integer", "minimum": 1},
        "expectedSemanticSHA256": sha,
    })
    root = _strict({
        "schema": {"const": "V21P03C11ChangeJournalCheckpointReplayCorpusV1"},
        "schemaVersion": {"const": 1}, "fixedSeed": {"const": FIXED_SEED},
        "workspaceID": {"const": WORKSPACE_ID}, "sourceReplicaID": {"const": SOURCE_REPLICA_ID},
        "destinationReplicaIDs": _exact_array(DESTINATION_REPLICA_IDS),
        "bounds": _strict({
            "maximumPageItems": {"const": 3}, "maximumPageBytes": {"const": 65536},
            "maximumGapPages": {"const": 2}, "maximumReplayAttempts": {"const": 4},
            "scaleAssetCount": {"const": 10000}, "scalePageItems": {"const": 128},
            "scaleExpectedPageCount": {"const": 79}, "scaleMaximumResidentBytes": {"const": 16777216},
        }),
        "checkpoint": _strict({
            "checkpointID": {"const": CHECKPOINT_ID},
            "revision": {"const": 40}, "cursorSequence": {"const": 40},
            "schemaRelease": {"const": "KERNEL_PERSISTENCE_V4"},
            "packageID": {"const": "kernel_persistence_v4"},
            "packageSchemaVersion": {"const": 4},
            "packageContentVersion": {"const": 1},
            "generationID": {"const": "33333333-3333-4333-8333-333333333333"},
            "packageReleaseSHA256": sha, "normalizedSnapshotSHA256": sha,
            "contentManifestSHA256": sha, "complete": {"const": True}, "verified": {"const": True},
        }),
        "postCheckpointChanges": _array(change, minimum=6, maximum=6, unique=True),
        "pages": _array(page, minimum=2, maximum=2, unique=True),
        "replaySchedules": _array(replay, minimum=4, maximum=4, unique=True),
        "contentCases": _array(content, minimum=3, maximum=3, unique=True),
        "conflictCases": _array(conflict, minimum=5, maximum=5, unique=True),
        "reversal": _strict({
            "targetMutationID": uuid, "reversalMutationID": uuid,
            "targetReceiptStableKey": {"type": "string", "pattern": "^[0-9a-f-]+:[0-9a-f-]+:[0-9]+$"},
            "reversalReceiptStableKey": {"type": "string", "pattern": "^[0-9a-f-]+:[0-9a-f-]+:[0-9]+$"},
            "expectedCompactionDisposition": {"const": "BASIS_AND_BOTH_RECEIPT_IDENTITIES_RETAINED"},
        }),
        "crashMatrix": _array(crash, minimum=9, maximum=9, unique=True),
        "replicaSchedules": _array(schedule, minimum=2, maximum=2, unique=True),
        "scale": _strict({
            "assetCount": {"const": 10000}, "seed": {"const": 230311},
            "generationRule": {"const": SCALE_GENERATION_RULE},
            "labelRule": {"const": "Asset-%05d"}, "pageItemLimit": {"const": 128},
            "expectedPageCount": {"const": 79}, "expectedFinalRevision": {"const": 10000},
            "expectedNormalizedMetadataSHA256": sha, "maximumResidentBytes": {"const": 16777216},
        }),
        "rollback": _strict({
            "policy": {"const": "CONTENT_ROLLBACK_ONLY"},
            "incompleteDerivedCheckpointsDiscardable": {"const": True},
            "acceptedReceiptsImmutable": {"const": True},
            "releasedSchemaDowngradeAllowed": {"const": False},
            "providerStateCreated": {"const": False},
        }),
        "releaseAbsence": _strict({
            "forbiddenProductionSymbols": _array(
                {"type": "string", "minLength": 1, "maxLength": 128},
                minimum=3, maximum=3, unique=True,
            ),
            "forbiddenProductionPaths": _array(
                {"type": "string", "minLength": 1, "maxLength": 256},
                minimum=3, maximum=3, unique=True,
            ),
        }),
    })
    return {
        "$schema": "https://json-schema.org/draft/2020-12/schema",
        "$id": "https://assetrounds.invalid/schemas/v23/change-journal-checkpoint-replay.schema.json",
        "title": "V23 P03 C11 change journal checkpoint and isolated replay corpus",
        "$ref": "#/$defs/corpus",
        "$defs": {
            "corpus": root, "change": change, "page": page, "replaySchedule": replay,
            "contentCase": content, "conflictCase": conflict, "crashCase": crash,
            "replicaSchedule": schedule,
        },
    }


def codable_projection() -> dict[str, Any]:
    return {
        "types": [
            {"typeID": type_id, "version": 1, "unknownFieldPolicy": "REJECT",
             "codingKeys": fields}
            for type_id, fields in CODABLE_FIELDS.items()
        ],
        "enums": [
            {"typeID": type_id, "version": 1, "policy": "CLOSED", "knownValues": values}
            for type_id, values in CODABLE_ENUMS.items()
        ],
        "optionalFields": OPTIONAL_CODABLE_FIELDS,
        "decodePolicy": "EXACT_CODING_KEYS_AND_DECODE_IF_PRESENT_FOR_NULLABLE_OPTIONALS",
    }


def contract_document(root: Path) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C11ChangeJournalCheckpointReplayContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "authority": authority(),
        "semanticScope": SEMANTIC_SCOPE,
        "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "sourcePaths": SOURCE_PATHS, "toolPaths": TOOL_PATHS,
        "generatedPaths": GENERATED_PATHS, "fixturePath": FIXTURE, "schemaPath": SCHEMA_PATH,
        "codableProjection": codable_projection(),
        "includedInvariants": [
            "CHECKPOINT_BINDS_WORKSPACE_SCHEMA_GENERATION_PACKAGE_HASHES_AND_EXACT_REVISION_FRONTIER",
            "BATCHES_ARE_BOUNDED_WORKSPACE_SCOPED_IMMUTABLE_RECEIPT_PAGES",
            "CURSORS_REJECT_FOREIGN_WORKSPACE_UNKNOWN_REPLICA_STALE_AND_DISCONTINUOUS_INPUT",
            "CHECKPOINT_FIRST_BOOTSTRAP_THEN_POST_FRONTIER_REPLAY_RECONSTRUCTS_CANONICAL_STATE",
            "COMPACTION_REQUIRES_COMPLETE_VERIFIED_CHECKPOINT_AND_RETAINS_REVERSAL_AND_CONTENT_BASIS",
            "REPLAY_USES_THE_SAME_WORKSPACE_WRITER_AND_IGNORES_EXACT_DUPLICATES",
            "DELIVERY_ORDER_AND_DESTINATION_RECEIPT_ORDER_NEVER_ENTER_SEMANTIC_IDENTITY",
            "DELETE_WINS_NEVER_RESURRECTS_AND_MANUAL_CONFLICTS_REMAIN_STABLE_UNTIL_RESOLUTION",
            "MISSING_OR_CORRUPT_CONTENT_DEFERS_OR_QUARANTINES_WITH_VERIFIED_RESUME",
            "INCOMPLETE_DERIVED_STATE_IS_DISCARDABLE_BUT_CANONICAL_RECEIPTS_ARE_IMMUTABLE",
        ],
        "failureCases": FAILURE_CASES,
        "optionalFieldSemantics": {
            "missingAndNullAccepted": OPTIONAL_CODABLE_FIELDS,
            "nonOptionalMissingRejected": True,
            "unknownObjectFieldsRejected": True,
            "nullForNonNullableRejected": True,
        },
        "testMethods": [{"evidenceID": evidence_id, "method": method}
                        for evidence_id, method in zip(EVIDENCE_IDS, TEST_METHODS, strict=True)],
        "evidenceIDs": EVIDENCE_IDS,
        "sourceArtifacts": source_rows(root),
        "fixtureArtifact": {"path": FIXTURE, "bytes": (root / FIXTURE).stat().st_size,
                            "sha256": digest((root / FIXTURE).read_bytes())},
        "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchEnabled": False,
        "adoptionEnabled": False, "acceptanceEnabled": False, "acceptanceCredit": False,
        "releaseCredit": False, "phase10PollingDuringParallelExecution": False,
        "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def evidence_document(root: Path, schema: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    unsigned = {
        "schema": "V23P03C11ChangeJournalCheckpointReplayEvidenceReceiptV1", "schemaVersion": 1,
        "cardID": CARD, "authority": authority(), "result": "PASS",
        "verificationMode": "STATIC_ONLY", "evidenceIDs": EVIDENCE_IDS,
        "testMethods": TEST_METHODS,
        "sourceArtifacts": source_rows(root),
        "fixtureArtifact": {"path": FIXTURE, "bytes": (root / FIXTURE).stat().st_size,
                            "sha256": digest((root / FIXTURE).read_bytes())},
        "schemaArtifact": {"path": SCHEMA_PATH, "sha256": digest(pretty(schema)),
                           "draft": "https://json-schema.org/draft/2020-12/schema"},
        "contractArtifact": {"path": CONTRACT_PATH, "sha256": digest(pretty(contract))},
        "checks": [
            "EXACT_AUTHORITY_AND_13_PATH_FENCE", "BASE_HEAD_TREE_AND_EXISTENCE_PARTITION",
            "S10_ZERO_OVERLAP_AND_EXTERNAL_SCOPE_ABSENCE", "CANONICAL_FIXTURE_AND_FIXED_SEMANTIC_VECTORS",
            "STRICT_DRAFT_2020_12_META_SCHEMA_AND_POSITIVE_NEGATIVE_INSTANCES",
            "SWIFT_CODABLE_CODINGKEYS_AND_OPTIONAL_MISSING_NULL_PARITY",
            "EXACT_FIVE_EVIDENCE_IDS_AND_TEST_METHODS", "MANIFEST_BYTE_DIGEST_CLOSURE",
            "INDEPENDENT_SUBPROCESS_GENERATION_REPEATABILITY", "PYTHON_CACHE_ABSENCE",
        ],
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def tooling_manifest(root: Path, generated: dict[str, bytes]) -> dict[str, Any]:
    artifacts = []
    for relative in MANIFEST_INPUT_PATHS:
        raw = generated.get(relative)
        if raw is None:
            path = root / relative
            if not path.is_file():
                raise ContractError(f"missing manifest input: {relative}")
            raw = path.read_bytes()
        artifacts.append({"path": relative, "bytes": len(raw), "sha256": digest(raw)})
    unsigned = {
        "schema": "V23P03C11ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
        "authority": authority(), "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE),
        "existingPaths": EXISTING_PATHS, "newPaths": NEW_PATHS,
        "sourcePathCount": len(SOURCE_PATHS), "toolPathCount": len(TOOL_PATHS),
        "generatedArtifactCount": len(GENERATED_PATHS), "manifestInputCount": len(MANIFEST_INPUT_PATHS),
        "artifacts": artifacts, "artifactSetDigest": digest(canonical(artifacts)),
        "activeS10ReservationPathCount": len(ACTIVE_S10_RESERVED_PATHS),
        "s10FenceOverlapPaths": sorted(set(PATH_FENCE) & set(ACTIVE_S10_RESERVED_PATHS)),
        "evidenceIDs": EVIDENCE_IDS, "verificationMode": "STATIC_ONLY",
        "nativeCompileRan": False, "hostedDispatchEnabled": False, "adoptionEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseCredit": False,
        "phase10PollingDuringParallelExecution": False, "requiresAcceptedS10_6Reconciliation": True,
    }
    return {**unsigned, "artifactDigest": digest(pretty(unsigned))}


def all_outputs(root: Path) -> dict[str, bytes]:
    schema = change_journal_schema()
    contract = contract_document(root)
    evidence = evidence_document(root, schema, contract)
    partial = {
        SCHEMA_PATH: pretty(schema), CONTRACT_PATH: pretty(contract), EVIDENCE_PATH: pretty(evidence),
    }
    manifest = tooling_manifest(root, partial)
    outputs = {**partial, MANIFEST: pretty(manifest)}
    if set(outputs) != set(GENERATED_PATHS) or len(outputs) != 4:
        raise ContractError("exact four generated outputs required")
    return outputs
