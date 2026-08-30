#!/usr/bin/env python3
"""Fail-closed deterministic schedule-exception tooling for V23-P03-C51."""
from __future__ import annotations

import ast
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

CARD = "V23-P03-C51"
TITLE = "Advanced recurrence, immutable exception calendar releases, and append-only schedule overrides"
REGISTER_ORDINAL = 81
BASE_HEAD = "e13296a874eb3c8cedc3fec6a91e4d2e7a8d4af7"
BASE_TREE = "7eee693887d8a1943a91876ab2589f6c992b29ab"
COORDINATION_HEAD = "39eb63ff380a9c0036495e56e9efa3958d49471b"
COORDINATION_TREE = "d1b5364b8833728b1417fd5fec12478c1867f1a0"
COORDINATION_CAS_SEQUENCE = 343
CONTEXT_DIGEST = "d60a6326b5da8e563f5069e5af5e93b174044693afedb274a2fa5e1036beabeb"
FENCE_DIGEST = "8937c7d17e699db09925ad0deeeae769b7a677b2b796599dcf21b2aa34423094"
PREREQUISITE_DIGEST = "c5445c9408d5a8e41ebf196b1646fb528dc67103b3b56cd066ca3c5f7d4b5ca0"
HYDRATION_TRANSITION_DIGEST = "3496010a25438a36ec4b065e7ac72afbe99144719c2055b34c307cb9ac0ded92"
COORDINATION_LEDGER_DIGEST = "693f51a56743420cae2a60364104ea95811263e7f02d118b0ddd26e4835b1f1b"
COORDINATION_PROJECTION_DIGEST = "7e6278a2928328d2387f018748e640e224493f8f1c85fe496325e6d3852691d7"
FROZEN_S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

DOSSIER_SHA256 = "3aca94cfcb1c000ca8fc2227b08763348aa7a420bb0b41e82cf0d0222531c6e3"
DOSSIER_BYTES = 7263
INHERITED_SHA256 = "48f60ca08a859154cf07bd5fe102687ec85bbd55aad24ff52d816b59940f84c6"
INHERITED_BYTES = 6917
REGISTER_ROW_SHA256 = "009d437b38eda596b7e795e9146a7aa14355b50907ae0a5f8a3f4d5db26bfefd"
REGISTER_ROW_BYTES = 302
REGISTER_SECTION_SHA256 = "3047a8c7f8baeca754bdf635811796eacc6400f91521f40c6294343c66f702d5"
REGISTER_SECTION_BYTES = 44217

SCHEMA_PATH = "Scripts/v23/schedule-exception-calendar.schema.json"
CONTRACT_PATH = "docs/design/v23/tooling/V23P03C51ScheduleExceptionCalendarContractV1.json"
EVIDENCE_PATH = "docs/design/v23/tooling/V23P03C51ScheduleExceptionCalendarEvidenceReceiptV1.json"
BRAND_PATH = "docs/design/v23/tooling/V23P03C51BrandImpactManifestV1.json"
MANIFEST_PATH = "docs/design/v23/tooling/V23-P03-C51-tooling-manifest.json"
SCRIPT_PATHS = (
    "Scripts/v23/p03_c51_contracts.py",
    "Scripts/v23/generate_p03_c51_contracts.py",
    "Scripts/v23/verify_p03_c51_contracts.py",
)
GENERATED_DOCUMENT_PATHS = (CONTRACT_PATH, EVIDENCE_PATH, BRAND_PATH, MANIFEST_PATH)
IMPLEMENTATION_PATHS = (
    "FieldEvidenceApp/Domain/Scheduling/ScheduleExceptionCalendarContractsV1.swift",
    "FieldEvidenceApp/Domain/Scheduling/ScheduleOverrideContractsV1.swift",
    "FieldEvidenceApp/Application/Scheduling/ScheduleExceptionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Scheduling/ScheduleExceptionLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_58ScheduleExceptionCalendarTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Scheduling/V22P03C51ScheduleExceptionCalendarCorpusV1.json",
)

PRIOR_C50_ACCEPTANCE = {
    "cardID": "V23-P03-C50",
    "immediateSequencingCheckpoint": "e89b1e98c209cb621e4103f11e2ee7a110250d16baa8612db33a7a81e1231c3e",
    "verificationReceiptDigest": "bd9d20904dad4e89a3453e9d7a946026ce107886298d06599fe28ce7c94e211b",
    "candidateHead": "e13296a874eb3c8cedc3fec6a91e4d2e7a8d4af7",
    "candidateTree": "7eee693887d8a1943a91876ab2589f6c992b29ab",
    "contextDigest": "04061e30aaf4968b271b9657af03e71152ae446bdf84f24730d06e1b8cf129e1",
    "pathFenceDigest": "43add5f59574b0686a74dd09f9379e6dc4b07cb93ad6578d8e0910d6947e6800",
}
PRIOR_FENCE_PROOF = {
    "authorizedOverlapCount": 0,
    "immediateSequencingCheckpoint": {
        "checkpointDigest": PRIOR_C50_ACCEPTANCE["immediateSequencingCheckpoint"],
        "verificationReceiptDigest": PRIOR_C50_ACCEPTANCE["verificationReceiptDigest"],
    },
    "overlapCount": 0,
    "semanticPrerequisiteCardID": "V23-P03-C28",
    "semanticPrerequisiteExistingPathCount": 146,
    "semanticPrerequisiteFenceDigest": "59de5cf7743a73e39d7d2bab3097f0ac71104737b2436122d17333a82bf69c15",
    "semanticPrerequisiteFullFencePathCount": 160,
    "semanticPrerequisiteNewPathCount": 14,
    "unauthorizedOverlapCount": 0,
}
PRIOR_FENCE_PROOF_BYTES = 560
PRIOR_FENCE_PROOF_SHA256 = "800acb2bf90db43522d852f988fa823cdb615c4f5875285777a1fe0215b99b7e"


EXISTING_PATHS = (
    "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift",
    "FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift",
    "FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift",
    "FieldEvidenceApp/Domain/Backup/ReplacementRestoreRule.swift",
    "FieldEvidenceApp/Domain/Backup/DeletionLedgerV2.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift",
    "FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/PersistentSchemas.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreGenerationFactory.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/StoreMigrationContracts.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentPersistentKindLifecycleCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift",
    "FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift",
    "FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift",
    "FieldEvidenceAppTests/V9_01VersionedSchemaIdentityTests.swift",
    "FieldEvidenceAppTests/V9_03MigrationRecoveryTests.swift",
    "FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionRightsTests.swift",
    "FieldEvidenceAppTests/V9_06DeletionArchiveIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityPolicyTests.swift",
    "FieldEvidenceAppTests/V9_07CompatibilityCorpusIntegrationTests.swift",
    "FieldEvidenceAppTests/V9_13PersistentKindLifecycleCoverageTests.swift",
    "FieldEvidenceAppTests/V9_04StreamingArchiveTests.swift",
    "FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift",
    "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
    "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
    "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
    "FieldEvidenceAppTests/S6_6EraseRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift",
    "FieldEvidenceAppTests/V9_12SystemHealthOperationalDiagnosticsTests.swift",
    "FieldEvidenceAppTests/V9_20KernelConformanceTests.swift",
    "FieldEvidenceAppTests/V10_01WorkspaceWriterTests.swift",
    "FieldEvidenceApp/Domain/AssetSemantics/AssetSemanticContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/AssetSemanticPersistenceModelsV1.swift",
    "FieldEvidenceApp/Domain/Models/Asset.swift",
    "FieldEvidenceApp/Application/AssetSemantics/AssetSemanticsCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetSemanticLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentReferenceContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentLocatorManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/LocalContentStoreContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentIntegrityV1.swift",
    "FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift",
    "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WorkflowContracts.swift",
    "FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkflowModels.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift",
    "FieldEvidenceApp/Domain/Search/SearchContractsV1.swift",
    "FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift",
    "FieldEvidenceApp/Resources/Localizable.xcstrings",
    "FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/DeletionIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift",
    "FieldEvidenceApp/Domain/Workflow/WholeSignDeletionRule.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/WholeSignDeletionService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseIntentStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/KernelDeletionEraseRegistryV4.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/DeletionLedgerStore.swift",
    "FieldEvidenceApp/Infrastructure/Deletion/OrphanFileCleanupService.swift",
    "FieldEvidenceApp/Domain/Replication/PersistentKindLifecycleRegistryV1.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift",
    "FieldEvidenceApp/Features/CheckRunner/CheckRunnerCoordinator.swift",
    "FieldEvidenceAppTests/S3_6CameraRecoveryTests.swift",
    "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
    "FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift",
    "FieldEvidenceAppTests/S4_4HistoryComparisonTests.swift",
    "FieldEvidenceAppTests/S6_1DeletionGraphTests.swift",
    "FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/V9_19LocalSearchTests.swift",
    "FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift",
    "FieldEvidenceAppTests/V9_24AssetSemanticLifecycleTests.swift",
    "FieldEvidenceApp/Domain/Mutation/WorkspaceMutationContractsV1.swift",
    "FieldEvidenceApp/Domain/Mutation/MutationReceiptV1.swift",
    "FieldEvidenceApp/Application/Mutation/WorkspaceWriterV1.swift",
    "FieldEvidenceApp/Infrastructure/Persistence/KernelMutationReceiptRegistryV4.swift",
    "FieldEvidenceApp/Domain/Replication/IntegrationEventContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationProjectionCheckpointStoreV1.swift",
    "FieldEvidenceApp/Infrastructure/Replication/IntegrationConformanceConsumerV1.swift",
    "FieldEvidenceApp/Domain/Compatibility/ReleasedDataCompatibilityPolicyV1.swift",
    "FieldEvidenceApp/Domain/Backup/StreamingArchiveContracts.swift",
    "FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift",
    "FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift",
    "FieldEvidenceAppTests/V9_10LifecycleBoundaryTests.swift",
    "FieldEvidenceAppTests/V9_17KernelPersistenceTests.swift",
    "FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift",
    "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift",
    "FieldEvidenceApp/Application/Ports/ResumableLocalJobPortV1.swift",
    "FieldEvidenceApp/Domain/Models/ObservationAndTimeModelsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/TimeContextRule.swift",
    "FieldEvidenceApp/Domain/Workflow/WorkRule.swift",
    "FieldEvidenceApp/Infrastructure/System/DeviceTimeSemanticsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkPacketManifestContractsV1.swift",
    "FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift",
    "FieldEvidenceApp/Domain/Workflow/SurveySessionContractsV1.swift",
    "FieldEvidenceApp/Domain/Accountability/PartyAccountabilityContractsV1.swift",
    "FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift",
    "FieldEvidenceApp/Infrastructure/WorkPacket/WorkPacketManifestLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Application/WorkPacket/WorkPacketManifestCoordinatorV1.swift",
    "FieldEvidenceApp/Domain/Models/WorkPacketManifestPersistenceModelsV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobV1.swift",
    "FieldEvidenceApp/Infrastructure/Jobs/ResumableLocalJobRunnerV1.swift",
    "FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift",
    "FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveyDefinitionPersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Workflow/SurveySessionCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Workflow/SurveySessionLifecycleAdapterV1.swift",
    "FieldEvidenceApp/Domain/Models/SurveySessionPersistenceModelsV1.swift",
    "FieldEvidenceAppTests/V9_29WorkPacketManifestTests.swift",
    "FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift",
    "FieldEvidenceAppTests/V9_40SurveySessionTests.swift",
    "FieldEvidenceAppTests/V9_11ObservationTemporalSemanticsTests.swift",
    "FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests.swift",
    "FieldEvidenceAppTests/V9_35ClientCapabilityPackageLifecycleTests.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Domain/Workflow/ScheduleContractsV1.swift",
    "FieldEvidenceApp/Domain/Models/SchedulePersistenceModelsV1.swift",
    "FieldEvidenceApp/Application/Workflow/ScheduleCoordinatorV1.swift",
    "FieldEvidenceApp/Infrastructure/Workflow/ScheduleLifecycleAdapterV1.swift",
    "FieldEvidenceAppTests/V9_42ScheduleTests.swift",
    "FieldEvidenceAppTests/Fixtures/V22/Schedules/V22P03C28ScheduleCorpusV1.json",
)
NEW_PATHS = (*IMPLEMENTATION_PATHS, *SCRIPT_PATHS, SCHEMA_PATH, *GENERATED_DOCUMENT_PATHS)
PATH_FENCE = EXISTING_PATHS + NEW_PATHS
MANIFEST_INPUT_PATHS = tuple(path for path in PATH_FENCE if path != MANIFEST_PATH)
FLAGS = {name: False for name in (
    "native", "hosted", "physical", "adoption", "acceptance", "release",
    "nativeAcceptance", "hostedAcceptance", "physicalAcceptance", "adoptionEvidence",
    "acceptanceCredit", "releaseReadiness", "phase10PollingDuringParallelExecution",
)}
EVIDENCE_IDS = tuple(f"{CARD}-{suffix}" for suffix in ("G01", "A01", "H01", "I01", "R01"))
DISALLOWED_SOURCE_PATTERNS = (
    r"\b(?:EventKit|EKEventStore|EKEvent|EKCalendar|EKReminder)\b",
    r"\b(?:RRULE|cron|CronJob|UNCalendarNotificationTrigger)\b",
    r"\b(?:URLSession|URLRequest|URLComponents|NWConnection|WebSocket|HTTPClient|Alamofire)\b",
    r"\b(?:RemoteHoliday|HolidayFeed|WeatherFeed|RemoteCalendar|CalendarSubscription)\b",
    r"\b(?:rewriteHistory|replaceHistory|deleteCompletedOccurrence|mutateStartedOccurrence)\b",
    r"\b(?:unbounded(?:Preview|Generation|Occurrence|Lookahead)|generateAllOccurrences)\b",
)


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"


def pretty(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _text(root: Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        raise ValueError("source path absent:" + relative)
    return path.read_text(encoding="utf-8")


def _strict_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key:" + key)
        result[key] = value
    return result


def _json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(_text(root, relative), object_pairs_hook=_strict_pairs)
    if not isinstance(value, dict):
        raise ValueError("JSON object required:" + relative)
    return value


def _base_exists(root: Path, relative: str) -> bool:
    return subprocess.run(["git", "cat-file", "-e", f"{BASE_HEAD}:{relative}"], cwd=root,
                          capture_output=True).returncode == 0


def observed_changed_paths(root: Path) -> tuple[str, ...]:
    changed = set()
    for raw in subprocess.run(["git", "diff", "--name-only", BASE_HEAD, "--"], cwd=root,
                              check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            changed.add(raw.strip().replace("\\", "/"))
    for raw in subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], cwd=root,
                              check=True, capture_output=True, text=True).stdout.splitlines():
        if raw.strip():
            changed.add(raw.strip().replace("\\", "/"))
    return tuple(sorted(changed))


def _require_tokens(text: str, tokens: Iterable[str], label: str) -> None:
    missing = [token for token in tokens if token not in text]
    if missing:
        raise ValueError(f"{label} missing tokens:" + ",".join(missing))


def _require_patterns(text: str, patterns: Iterable[str], label: str) -> None:
    missing = [pattern for pattern in patterns if re.search(pattern, text, re.I | re.S) is None]
    if missing:
        raise ValueError(f"{label} missing patterns:" + ",".join(missing))


def _require_ordered(text: str, tokens: tuple[str, ...], label: str) -> None:
    positions = [text.find(token) for token in tokens]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        raise ValueError(label + " ordering or token absence")


def _assert_cross_owner_lifecycle(root: Path) -> None:
    """C51 persistence is owned by the established durable lifecycle boundaries."""
    backup_contracts = _text(root, "FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift")
    backup_export = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift")
    backup_restore = _text(root, "FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift")
    erase_boundary = _text(root, "FieldEvidenceApp/Domain/Workflow/EraseIntentV1.swift")
    erase_service = _text(root, "FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift")
    journal = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift")
    recovery = _text(root, "FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationReceiptRecoveryServiceV1.swift")
    reporting = _text(root, "FieldEvidenceApp/Infrastructure/Reporting/ReportRecoveryService.swift")
    rebuild = _text(root, "FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift")
    localization = _text(root, "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift")

    _require_tokens(backup_contracts, (
        "C51ScheduleBackupClosureV1", "persistentSchemaVersion = 27", "recordsSchemaVersion = 26",
        "persistedRecordKindCount = 4", "ExceptionCalendarReleaseV1", "ScheduleOverrideEventV1",
        "OccurrenceScheduleBasisV2", "ScheduleChangeReceiptV1", "preservedV27RecordBytes = true",
        "allDaysMigrationPreservesOccurrenceIdentityAndDate = true",
        "sourceScheduleAutomaticallyActiveAfterCloneOrFork = false",
        "derivedDueReminderAndPreviewStateIsArchived = false", "validatesEnvelope",
    ), "C51 backup closure")
    _require_tokens(backup_export, (
        "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow", "scheduleRecords",
        "C51ScheduleBackupClosureV1.validatesAdvancedCalendarReferences",
        "C51ScheduleBackupClosureV1.validatesEnvelope", ".exceptionCalendarRelease", ".scheduleOverrideEvent",
    ), "C51 backup export closure")
    _require_tokens(backup_restore, (
        "C51ScheduleBackupClosureV1.validatesEnvelope",
        "ScheduleRestoreIdentityPolicyV1.calendarOverrideAndBasisClosureReboundAtomically",
        "ScheduleReplacementRestorePolicyV1.validate", "ExceptionCalendarReleaseV1",
        "ScheduleOverrideEventV1", "ScheduleOverridePrecedenceV1.closureSHA256",
        "ScheduleOverridePrecedenceV1.activeEvents", "sourceScheduleAutomaticallyActiveAfterCloneOrFork",
    ), "C51 restore and clone/fork rebind")
    _require_tokens(erase_boundary, (
        "ScheduleEraseBoundaryV1", "atomicFamilyCount = 4", "lifecycleHistoryIsMutationJournalBacked = true",
        "ordinaryDeletionPreservesReleaseAndOccurrenceHistory = true",
        "workspaceEraseClearsEntireLifecycleClosure = true",
        "erasePublishesNoPartialCalendarOverrideOrBasisClosure = true",
        "dueAndReminderProjectionsAreNonpersistent = true", "notificationStateIsTruth = false",
    ), "C51 deletion boundary")
    _require_tokens(erase_service, (
        "ScheduleEraseAllPolicyV1", "ExceptionCalendarReleaseRow", "ScheduleOverrideEventRow",
        "ScheduleEraseBoundaryV1.erasePublishesNoPartialCalendarOverrideOrBasisClosure",
        "projectionsAreDerived", "!notificationStateIsTruth",
    ), "C51 erase publication")
    _require_tokens(journal, (
        "validateScheduleReferences", ".appendExceptionCalendarRelease", "ExceptionCalendarReleaseRow",
        "receiptHistoryCorrupt", ".advanced(configuration)", "configuration.calendarRelease",
    ), "C51 journal persistence")
    _require_tokens(recovery, (
        "C51ScheduleOverrideRecoveryBoundaryV1", ".applySchedule",
        "effectBeforeReceiptRecoveryUsesCanonicalPostimages=true",
        "divergentSameMutationIsQuarantined=true", "overrideFrontierIsRevalidatedFromPersistedRows=true",
        "createsParallelWriter=false",
    ), "C51 journal recovery")
    _require_tokens(reporting, (
        "AdvancedScheduleReportRecoveryPolicyV1", "FROZEN_SCHEDULE_CALENDAR_OVERRIDE_AND_OCCURRENCE_LINEAGE",
        "derivedProjectionIsDropAndRebuild = true", "finalizedHistoryIsNotRewritten = true",
        "ScheduleChangeFrontierV1", "ScheduleOverrideEventV1", "ScheduleChangeReceiptV1",
    ), "C51 reporting rebuild")
    _require_tokens(rebuild, (
        "advancedScheduleRebuildParityRequired = true",
        "DROP_AND_REBUILD_FROM_CANONICAL_SCHEDULE_RELEASE_AND_OCCURRENCE_HISTORY",
        "EXCLUDE_SCHEDULE_ROWS_AND_REBUILD_AFTER_CANONICAL_RESTORE",
    ), "C51 search rebuild")
    _require_tokens(localization, (
        "ScheduleLocalizationPolicyV1.validate", "ScheduleLocalizationKeyV1", "scheduleRegistry",
        ".advancedRecurrence", ".exceptionCalendar", ".calendarRelease", ".businessDayAdjustment",
        ".completionGap", ".nominalBasis", ".effectiveBasis", ".occurrenceLineage",
        ".scheduleOverride", ".overridePrecedence", ".changePreview", ".recovery",
        ".manualResolutionRequired", ".recoveryRebuilt",
    ), "C51 localization and frozen display")


def _assert_sources(root: Path) -> None:
    calendar, override, coordinator, lifecycle, tests, fixture_path = IMPLEMENTATION_PATHS
    contracts = _text(root, calendar)
    overrides = _text(root, override)
    coordination = _text(root, coordinator)
    projection_adapter = _text(root, lifecycle)
    test_source = _text(root, tests)
    fixture = canonical(_json(root, fixture_path)).decode()
    production = "\n".join((contracts, overrides, coordination, projection_adapter))

    _require_tokens(contracts, (
        "AdvancedRecurrenceRuleV1", "case daily", "case weekly", "case monthlyDay", "case monthlyWeekday",
        "case yearly", "case completionRelative", "ExceptionCalendarReleaseV1", "gregorian",
        "ianaTimeZoneIdentifier", "baseIncludedWeekdays", "excludedDates", "excludedRanges",
        "includedOverrideDates", "BusinessDayAdjustmentPolicyV1", "NEXT_INCLUDED_DAY",
        "PREVIOUS_INCLUDED_DAY", "SKIP_WITH_REASON", "REQUIRE_MANUAL_RESOLUTION",
        "CompletionGapPolicyV1", "PAUSE_CHAIN", "ANCHOR_TO_NOMINAL_AFTER_EXPLICIT_SKIP",
        "REQUIRE_MANUAL_ANCHOR", "OccurrenceScheduleBasisV2", "ambiguousTimePolicy",
        "nonexistentTimePolicy", "calendarRelease", "releaseSHA256", "limitExceeded",
    ), "C51 recurrence and calendar contracts")
    _require_tokens(overrides, (
        "ScheduleOverrideScopeV1", "THIS_OCCURRENCE", "THIS_AND_FUTURE", "ENTIRE_SERIES",
        "ScheduleOccurrenceOverrideKindV1", "SKIP", "MOVE", "ADD_ONE",
        "ScheduleOverrideEventV1", "expectedScheduleRevision", "expectedOverrideFrontierSHA256",
        "effectiveRange", "supersedesEventID", "mutationID", "ScheduleOverridePrecedenceV1",
        "ScheduleChangePreviewV1", "requiresManualResolution", "validateHistoryImmutability",
    ), "C51 override and precedence contracts")
    _require_tokens(coordination, (
        "preview", "validateCommit", "ScheduleOverridePrecedenceV1.resolve",
        "AdvancedScheduleGenerationBudgetV1", "validate(generatedCount",
        "ScheduleOccurrenceLineageV1", "validateHistoryImmutability",
        "successorOccurrenceID", "staleBasis",
    ), "C51 coordinator bounds and lineage")
    _assert_cross_owner_lifecycle(root)
    _require_ordered(overrides, ("baseRecurrence = 0", "exceptionCalendar = 1",
                                 "effectiveSeriesOverride = 2", "explicitOccurrenceOverride = 3"),
                     "C51 precedence levels")
    _require_tokens(overrides, (
        "exact.first ?? series.first", "calendar.isIncluded(nominalDate)",
        "level: .exceptionCalendar", "ScheduleFailureV1.divergentReplay",
    ), "C51 precedence resolution")
    _require_patterns(contracts + overrides, (
        r"max(?:imum)?ExcludedDates\s*[:=]\s*366",
        r"max(?:imum)?ExcludedRanges\s*[:=]\s*32",
        r"max(?:imum)?IncludedOverrideDates\s*[:=]\s*366",
        r"lookahead.{0,160}400|400.{0,160}lookahead",
    ), "C51 explicit bounded constants")
    _require_tokens(test_source, (
        "testV23P03C51G01", "testV23P03C51A01", "testV23P03C51H01",
        "testV23P03C51H02", "testV23P03C51I01", "testV23P03C51R01", "XCTAssertThrowsError",
        "GrammarDSTLeapMonthAndNthLastWeekdayCorpus", "CalendarPrecedenceEveryOverrideScopeKindAndConflict",
        "StableLineageAndImmutableStartedCompletedMissedHistory",
        "EffectBeforeReceiptPartialGenerationRetryAndBackupReplay",
        "RestoreRebuildsDerivedSearchReportReminderAndAllDaysWithoutForbiddenTruth",
        "retryPlan.candidates.isEmpty", "existingOccurrenceIDs", "C51ScheduleBackupClosureV1",
    ), "C51 G/A/H/I/R and FJ07 tests")
    _require_tokens(fixture, (
        '"G01_GRAMMAR_DST_LEAP_MONTH_NTH_LAST"',
        '"A01_CALENDAR_PRECEDENCE_OVERRIDE_SCOPE_KIND"',
        '"H01_BOUNDS_FRONTIER_DIGEST_ZONE_RANGE_ROLLBACK_CORRUPTION"',
        '"I01_EFFECT_BEFORE_RECEIPT_PARTIAL_RETRY_BACKUP_REPLAY"',
        '"R01_RESTORE_DERIVED_EQUALITY_ALL_DAYS_FORBIDDEN_CAPABILITIES"',
    ), "C51 fixture G/A/H/I/R evidence")
    _require_tokens(fixture, (
        '"EVENTKIT_PERMISSION"', '"NETWORK_CALENDAR_FEED"',
        '"NOTIFICATION_DELIVERY_AS_SCHEDULE_TRUTH"', '"acceptance":false',
        '"adoption":false', '"hosted":false', '"native":false', '"release":false',
    ), "C51 fixture prohibitions and provisional flags")
    for pattern in DISALLOWED_SOURCE_PATTERNS:
        if re.search(pattern, production) is not None:
            raise ValueError("C51 prohibited source capability:" + pattern)


def _assert_prior_proof() -> None:
    """Bind sealed C50 acceptance, never C50's mutable working-tree artifacts."""
    expected = {
        "cardID": "V23-P03-C50",
        "immediateSequencingCheckpoint": "e89b1e98c209cb621e4103f11e2ee7a110250d16baa8612db33a7a81e1231c3e",
        "verificationReceiptDigest": "bd9d20904dad4e89a3453e9d7a946026ce107886298d06599fe28ce7c94e211b",
        "candidateHead": BASE_HEAD,
        "candidateTree": BASE_TREE,
        "contextDigest": "04061e30aaf4968b271b9657af03e71152ae446bdf84f24730d06e1b8cf129e1",
        "pathFenceDigest": "43add5f59574b0686a74dd09f9379e6dc4b07cb93ad6578d8e0910d6947e6800",
    }
    if PRIOR_C50_ACCEPTANCE != expected:
        raise ValueError("C51 sealed C50 acceptance tuple differs")
    # Hydration signs compact canonical JSON without the newline used for files.
    encoded = json.dumps(PRIOR_FENCE_PROOF, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    if len(encoded) != PRIOR_FENCE_PROOF_BYTES or sha256_bytes(encoded) != PRIOR_FENCE_PROOF_SHA256:
        raise ValueError("C51 hydration prior fence proof differs")


def assert_scaffold(root: Path) -> None:
    if (len(EXISTING_PATHS), len(NEW_PATHS), len(PATH_FENCE)) != (152, 14, 166):
        raise ValueError("C51 fence cardinality")
    if len(set(PATH_FENCE)) != len(PATH_FENCE):
        raise ValueError("C51 duplicate fence path")
    if any(_base_exists(root, path) for path in NEW_PATHS):
        raise ValueError("C51 new path exists at base")
    if any(not _base_exists(root, path) for path in EXISTING_PATHS):
        raise ValueError("C51 existing path absent at base")
    for path in SCRIPT_PATHS:
        ast.parse(_text(root, path), filename=path)
    if any(FLAGS.values()):
        raise ValueError("C51 provisional flag true")
    _assert_prior_proof()
    _assert_sources(root)


def authority() -> dict[str, Any]:
    return {
        "appBaseHead": BASE_HEAD, "appBaseTree": BASE_TREE,
        "coordinationHead": COORDINATION_HEAD, "coordinationTree": COORDINATION_TREE,
        "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
        "contextDigest": CONTEXT_DIGEST, "pathFenceDigest": FENCE_DIGEST,
        "provisionalPrerequisiteDigest": PREREQUISITE_DIGEST,
        "hydrationTransitionDigest": HYDRATION_TRANSITION_DIGEST,
        "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST,
        "coordinationProjectionDigest": COORDINATION_PROJECTION_DIGEST,
        "directPrerequisites": ["V23-P03-C28", "V23-P03-C50"],
    }


def _file_inventory(root: Path, outputs: dict[str, bytes]) -> list[dict[str, Any]]:
    inventory = []
    for relative in MANIFEST_INPUT_PATHS:
        data = outputs.get(relative)
        if data is None:
            data = (root / relative).read_bytes()
        inventory.append({"path": relative, "byteCount": len(data), "sha256": sha256_bytes(data)})
    return inventory


def contract_document() -> dict[str, Any]:
    return {
        "schema": "V23P03C51ScheduleExceptionCalendarContractV1", "schemaVersion": 1,
        "cardID": CARD, "title": TITLE, "registerOrdinal": REGISTER_ORDINAL,
        "authority": authority(),
        "sourceAuthority": {
            "dossier": {"byteCount": DOSSIER_BYTES, "sha256": DOSSIER_SHA256},
            "inheritedV21": {"byteCount": INHERITED_BYTES, "sha256": INHERITED_SHA256},
            "registerRow": {"byteCount": REGISTER_ROW_BYTES, "sha256": REGISTER_ROW_SHA256},
            "registerSection": {"byteCount": REGISTER_SECTION_BYTES, "sha256": REGISTER_SECTION_SHA256},
        },
        "priorC50Acceptance": PRIOR_C50_ACCEPTANCE,
        "priorFenceProof": PRIOR_FENCE_PROOF,
        "priorFenceProofSHA256": PRIOR_FENCE_PROOF_SHA256,
        "calendar": {"calendar": "GREGORIAN_V1", "immutableReleases": True,
                     "inclusionPrecedence": ["INCLUDED_OVERRIDE", "EXCLUDED", "BASE_WEEKDAY"],
                     "maxExcludedDates": 366, "maxExcludedRanges": 32, "maxIncludedOverrideDates": 366},
        "recurrence": {"bounded": True, "maxLookaheadDays": 400, "maxBackfillDays": 90,
                       "maxOccurrencesPerSchedule": 512, "maxWorkspaceActiveUpcoming": 10000,
                       "silentTruncation": False, "explicitGapPolicy": True},
        "overrides": {"appendOnly": True, "expectedRevision": True, "immutableHistory": True,
                      "precedence": ["OCCURRENCE_OVERRIDE", "LATEST_NONOVERLAPPING_SERIES_OVERRIDE",
                                     "EXCEPTION_CALENDAR", "BASE_RECURRENCE"]},
        "lifecycle": {"backup": True, "restore": True, "clone": True, "fork": True, "erase": True,
                      "journalReplay": True, "historicalBytesRewritten": False},
        "forbidden": {"eventKit": False, "rrule": False, "cron": False, "network": False,
                      "remoteTruth": False, "historyRewrite": False, "unboundedGeneration": False},
        "evidenceIDs": list(EVIDENCE_IDS), "statusFlags": FLAGS,
    }


def evidence_document() -> dict[str, Any]:
    cases = {key: {"evidenceID": evidence, "status": "STATIC_CONTRACT_BOUND"}
             for key, evidence in zip(("golden", "alternate", "hostile", "interruption", "recovery"), EVIDENCE_IDS)}
    return {"schema": "V23P03C51ScheduleExceptionCalendarEvidenceReceiptV1", "schemaVersion": 1,
            "cardID": CARD, "authority": authority(), "cases": cases,
            "fixtureJourney": "FJ07", "nativeCompileRan": False, "hostedDispatchEnabled": False,
            "physicalLockedState": "REQUIRED_PENDING_OWNER", "acceptanceCredit": False,
            "releaseCredit": False, "statusFlags": FLAGS}


def brand_document() -> dict[str, Any]:
    return {"schema": "V23P03C51BrandImpactManifestV1", "schemaVersion": 1, "cardID": CARD,
            "brandSurfaceDelta": True, "uiSurfaceDelta": False, "providerClaim": None,
            "presentation": "LOCAL_DETERMINISTIC_SCHEDULE_EXCEPTION_CALENDAR",
            "truthfulDisclosure": "Scheduling remains local, bounded, and release-pinned.",
            "prohibitedClaims": ["calendar sync", "EventKit integration", "remote holiday feed", "automation service"],
            "statusFlags": FLAGS}


def all_outputs(root: Path) -> dict[str, bytes]:
    assert_scaffold(root)
    outputs = {CONTRACT_PATH: pretty(contract_document()), EVIDENCE_PATH: pretty(evidence_document()),
               BRAND_PATH: pretty(brand_document())}
    manifest = {"schema": "V23P03C51ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
                "authority": authority(), "fencePathCount": 166, "existingPathCount": 152,
                "newPathCount": 14, "s10ReservedPathCount": 86, "s10ReservationOverlapCount": 0,
                "authorizedOverlapCount": 0, "unauthorizedOverlapCount": 0,
                "s10ReservationDigest": FROZEN_S10_RESERVATION_DIGEST,
                "priorC50Acceptance": PRIOR_C50_ACCEPTANCE,
                "priorFenceProof": PRIOR_FENCE_PROOF,
                "priorFenceProofSHA256": PRIOR_FENCE_PROOF_SHA256,
                "statusFlags": FLAGS, "files": _file_inventory(root, outputs)}
    outputs[MANIFEST_PATH] = pretty(manifest)
    return outputs
