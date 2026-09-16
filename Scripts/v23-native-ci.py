#!/usr/bin/env python3
"""Closed V23 native admission and factual evidence checks, not a CI scheduler.

The incumbent workflow owns native commands, budgets, credentials and uploads.
This module has no API client and never dispatches, retries or promotes a run.
"""
import argparse
import base64
import contextlib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import time


CONTRACT = "v23.integration.current-native.v1"
TASK = "V23-INTEGRATION-20260910"
REPOSITORY = "Asset-Rounds/AssetRounds"
REFS = {"refs/heads/codex/v23-s10-integration-20260910"}
LANES = {
    "github-xcode-26.6-acceptance": ("github", "macos-26"),
    "bitrise-build-hub-xcode-26.6-acceptance": ("bitrise", "bitrise-runner-Asset Roundddd"),
}
TIERS = {"N8": (300, 1200, 900, 0, 2400), "P12": (300, 600, 900, 900, 3300),
         "F25": (300, 900, 1200, 1800, 4500)}
BUDGET_KEYS = ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
               "uiTimeoutSeconds", "totalBudgetSeconds")
PROTOCOL_PATHS = (
    ".github/workflows/ios-ci.yml", ".github/workflows/ios-ci-worker.yml",
    "Scripts/v23-native-ci.py", "Scripts/build-smoke.sh", "Scripts/test-smoke.sh",
    "Scripts/ui-smoke.sh", "Scripts/run-with-timeout.sh",
    "Scripts/validate-required-evidence.sh",
    "Scripts/v23-selection-manifest.json", "Scripts/v23-selection-generator.py",
)
SELECTION_MAP_PATH = "Scripts/ci-selection-map.json"
DEFAULT_SELECTION_ID = "default-132"
DURABLE_BEGIN_PARENT_ID = "c36-durable-begin"
DURABLE_BEGIN_PARENT_SELECTORS = (
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginPersistsRawParentWithoutWorkflowOrBeginEffects",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginPersistsPreparedBeforeTargetsAndBindsCheck",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRecoversSavedTimeZoneBeforeRecheck",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRecoversWorkflowAndBoundAcknowledgementLoss",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsSourceAdvanceBeforeEitherTargetEffect",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsChangedCommandAndForeignWorkflowWithoutEffects",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginRejectsChangedSiteAndInitialPostimage",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginColdReopenReusesPreparedAttemptAndOriginalReceipts",
    "FieldEvidenceAppTests/V23CheckRunnerDurableInitialBeginTests/testDurableInitialBeginUsesOriginalCreationReceiptForContinuationAccess",
)
DURABLE_BEGIN_METHOD_PARTITIONS = (
    ("c36-durable-begin-lifecycle", (
        DURABLE_BEGIN_PARENT_SELECTORS[0],
        DURABLE_BEGIN_PARENT_SELECTORS[1],
        DURABLE_BEGIN_PARENT_SELECTORS[2],
        DURABLE_BEGIN_PARENT_SELECTORS[3],
        DURABLE_BEGIN_PARENT_SELECTORS[7],
    )),
    ("c36-durable-begin-guards", (
        DURABLE_BEGIN_PARENT_SELECTORS[4],
        DURABLE_BEGIN_PARENT_SELECTORS[5],
        DURABLE_BEGIN_PARENT_SELECTORS[6],
        DURABLE_BEGIN_PARENT_SELECTORS[8],
    )),
)
DURABLE_BEGIN_BASE_POOL_SHA256 = "91E6F41D81E982D116611FF4A96219FE3631020B5CB264F76A8BDA1E4E27408E"
DURABLE_BEGIN_BASE_MAP_SHA256 = "CD41DF01E106199B7CAE86CEDEB4BAA93F812C76D7B510BA6DC941DFCDDF7129"
GENERATED_SELECTION_PROFILE = "configuration-clone-v1"
GENERATED_SELECTION_POOL_SHA256 = "C5BFBCF739DCD2BCAF77801385CD1A16C116D6AFE07F1AD02162F0AEF9030AA0"
GENERATED_SELECTION_MAP_SHA256 = "955D579A27A62C179660C0F8A4A38FF4D91FB9241244BA3B0334A9AF1B0C7A6E"
CONFIGURATION_CLONE_SELECTION_ID = "c36-photo-configuration-clone"
CONFIGURATION_CLONE_SELECTORS = (
    'FieldEvidenceAppTests/S6_2BackupExportTests/testConfigurationCloneAcceptsEveryAuthenticPhotoPhaseAndOmitsOperationalFamily',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testConfigurationCloneRejectsCorruptFinalMemberAndPopulatedDestinationStagingBeforeEffects',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneColdRecoveryRejectsNewStagingWithoutDeletingIt',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneEmptyRootsRecoverAcrossPublicationBoundaries',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneFrozenEvidenceValidationIsBoundedAndRejectsHostileFiles',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRechecksAccessCancellationAndRootAfterMediaCopy',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetainsIntentWhenStagingChangesDuringFinalColdCleanup',
)
PHOTO_BACKUP_PARENT_SELECTORS = (
    'FieldEvidenceAppTests/S6_2BackupExportTests/testMixedExportFreezesAllAuthorityAndRecomputesManifestIndependently',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testSixPhotoSameWorkspaceRestorePublishesCompositionAndColdRecoveryIsAtomic',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testPhotoHistoryAcceptsRealBeginOnlyExportWithZeroPhotoChildren',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testDirtyMalformedAndUnsafeAuthorityFailClosed',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testInsufficientCapacityCreatesNoPackageAndMutatesNoLiveAuthority',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testAsyncExportCancellationDuringWriterRemovesOwnedPackage',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testAsyncExportCancellationImmediatelyAfterWriterSuccessCleansReceiptOwnedPackage',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testPublishedArchiveCleanupDeletesOnlyExactOwnedInode',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testPublishedArchiveCleanupPreservesEqualMagicReplacement',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testPublishedArchiveCleanupPreservesReplacementRacedBeforePrivateClaim',
    'FieldEvidenceAppTests/S6_2BackupExportTests/testFormatMagicProbeRejectsFIFOWithoutBlocking',
    'FieldEvidenceAppTests/S6_3BackupValidationTests/testPhotoBackupMemberStreamingIsBoundedCancellableAndAnchored',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testOwnedGenerationCleanupDoesNotApplyGenerationGrammarToImportPackages',
    'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testGoldenEmptyRestoreSwitchesValidatedGenerationAndRetiresOld',
    'FieldEvidenceAppTests/S4_1DeterministicRendererTests/testCapacityOverflowAndUnexpectedStageOrFinalFailClosed',
)
PHOTO_BACKUP_METHOD_PARTITIONS = (
    ('c36-photo-backup-transport', (
        PHOTO_BACKUP_PARENT_SELECTORS[0],
        PHOTO_BACKUP_PARENT_SELECTORS[2],
        PHOTO_BACKUP_PARENT_SELECTORS[3],
        PHOTO_BACKUP_PARENT_SELECTORS[4],
        PHOTO_BACKUP_PARENT_SELECTORS[5],
        PHOTO_BACKUP_PARENT_SELECTORS[6],
        PHOTO_BACKUP_PARENT_SELECTORS[7],
        PHOTO_BACKUP_PARENT_SELECTORS[8],
        PHOTO_BACKUP_PARENT_SELECTORS[9],
        PHOTO_BACKUP_PARENT_SELECTORS[10],
        PHOTO_BACKUP_PARENT_SELECTORS[11],
        PHOTO_BACKUP_PARENT_SELECTORS[14],
    )),
    ('c36-photo-backup-restore', (
        PHOTO_BACKUP_PARENT_SELECTORS[1],
        PHOTO_BACKUP_PARENT_SELECTORS[12],
        PHOTO_BACKUP_PARENT_SELECTORS[13],
    )),
)
SOURCE_GRAPH_PARENT_ID = "c36-source-graph"
SOURCE_GRAPH_PARENT_SELECTORS = (
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourcePackageTests/testOrdinaryDirectoryPackageIsValidatedAndBoundToExactCanonicalMembers",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourcePackageTests/testPackageCapabilityRejectsTamperedRecordsAndMissingRequiredSourceAuthority",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourcePackageTests/testActualFactoryRejectsNoncanonicalTruncatedMemberDescriptorAndSchemaDrift",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourcePackageTests/testActualFactoryPropagatesCancellationWithoutPublishingCapability",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testValidatedPackageYieldsOrderedCompleteGraphWithCompletedAndPendingEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testAuthenticDiscardedSourceRetainsOriginalGraphAndExactTerminalDisposition",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testDiscardedSourceRejectsOmittedDisplacedAndDuplicateCurrentDiscardReceipt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testForeignWorkspaceOriginalHistoryDoesNotCreateOrTaintSourceGraph",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testAuthenticLaterActivePayloadAndDiscardPendingRemainHistoricalReviewOnly",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testDiscardedHistoricalGraphPreservesCapturedFrontierAndAuthenticatesLaterRound",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testSameScopeHistoricalGraphsAreAllowedButCompetingUnchangedGraphsAreRejected",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testBranchOrphanAndCheckpointAfterPendingEffectAreRejected",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCanonicalEnvelopeAndTypedReceiptSubstitutionAreRejected",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testRequiredEnvelopeQuarantineIsRejectedWhileUnrelatedAndForeignAreAllowed",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testRequiredSemanticReplayQuarantineIsRejectedAfterValidReversalAuthentication",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testMaximumCaptureGraphAuthenticatesTwoStepsForAllTwoHundredItems",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testRehashedPackageCannotOmitAnyCurrentProgressOrEntireSourceGraph",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testRehashedPackageCannotOmitAuthenticatedRoundTail",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testRehashedPackageCannotDropCheckpointHistoryTailOrAlterCurrentCanonicalRow",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferenceAuthenticatesSourceAndAllOriginalCurrentFrontiers",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferenceRejectsCanonicalRecomputedSourceAndFrontierSubstitutions",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferencePreservesDisposedStateAndSeparateRoundFrontiers",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferenceSeparatesGraphsAndIgnoresUnrelatedHistory",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferenceMaximumGraphFitsPayloadBound",
    "FieldEvidenceAppTests/V23RepetitiveCaptureSourceGraphReviewTests/testCompactReferenceLongLifecycleKeepsBoundedPayloadAndCompleteHistory",
)
SOURCE_GRAPH_METHOD_PARTITIONS = (
    ("c36-source-graph-regular", tuple(
        selector for selector in SOURCE_GRAPH_PARENT_SELECTORS
        if selector not in (SOURCE_GRAPH_PARENT_SELECTORS[15], SOURCE_GRAPH_PARENT_SELECTORS[23])
    )),
    ("c36-source-graph-compact-maximum", (SOURCE_GRAPH_PARENT_SELECTORS[23],)),
    ("c36-source-graph-complete-maximum", (SOURCE_GRAPH_PARENT_SELECTORS[15],)),
)
SIMULATOR_DIAGNOSTIC_POLICY_PATH = "docs/design/v23/integration/SIMULATOR_FILE_PROTECTION_DIAGNOSTIC.json"
SIMULATOR_DIAGNOSTIC_OWNER_POLICY_SHA256 = "FDCAF78EEAEDDFC9A2661CB283A16810B88FE83F14348F6FECA69FBFE7DB58F1"
SIMULATOR_DIAGNOSTIC_POLICY_SHA256 = "4CE71CA43D961CF8A1318DA882BBA8989179700AB5202E5CE191185CFC0E44E0"
SIMULATOR_DIAGNOSTIC_POLICY_ID = "V23-SIMULATOR-FILE-PROTECTION-DIAGNOSTIC-20260915"
SIMULATOR_DIAGNOSTIC_SOURCE_PATH = "FieldEvidenceApp/Infrastructure/Persistence/ProtectedFilePolicy.swift"
SIMULATOR_DIAGNOSTIC_SOURCE_SHA256 = "FCFF658FCE118760EAC50B13A3941470EA86ED6FB40E78D17E6A573A10DFA5DB"
SIMULATOR_DIAGNOSTIC_PREFIX = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V2"
SIMULATOR_DIAGNOSTIC_MARKER_STEM = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_"
SIMULATOR_DIAGNOSTIC_OUTPUT = "simulator-file-protection-diagnostics.json"
SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS = "simulator-file-protection-transport-status.json"
SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY = "simulator-file-protection-transport"
SIMULATOR_DIAGNOSTIC_APP_DIRECTORY = "Library/Caches/AssetRoundsNativeDiagnostics"
SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID = "com.palatis3.fieldrecord"
SIMULATOR_DIAGNOSTIC_FRAME_SCHEMA = "v23-simulator-file-protection-frame-v1"
SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA = "v23-simulator-file-protection-transport-v1"
SIMULATOR_DIAGNOSTIC_MAX_FILES = 64
SIMULATOR_DIAGNOSTIC_MAX_EVENTS = 100_000
SIMULATOR_DIAGNOSTIC_MAX_TOTAL_EVENTS = SIMULATOR_DIAGNOSTIC_MAX_FILES * SIMULATOR_DIAGNOSTIC_MAX_EVENTS
SIMULATOR_DIAGNOSTIC_MAX_FRAME_BYTES = 8 * 1024
SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES = (
    SIMULATOR_DIAGNOSTIC_MAX_EVENTS * SIMULATOR_DIAGNOSTIC_MAX_FRAME_BYTES
)
SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES = 1024 * 1024 * 1024
SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS = 3
SIMULATOR_DIAGNOSTIC_WORK_SECONDS = 2.5
SIMULATOR_DIAGNOSTIC_COPY_CHUNK_BYTES = 64 * 1024
SIMULATOR_DIAGNOSTIC_FIELDS = (
    "policyID", "disposition", "kind", "request", "capabilityBefore", "capabilityAfter",
    "urlProtection", "backupExcluded", "expectsDirectory",
    "identityUnchanged",
)
SIMULATOR_DIAGNOSTIC_DISPOSITION = "SIMULATOR_FILE_PROTECTION_UNSUPPORTED"
SIMULATOR_FALLBACK_PROTECTION = "completeUntilFirstUserAuthentication"
OWNED_FILE_DISPOSITIONS = {
    "durableDirectory": (False, True),
    "stagingDirectory": (True, True),
    "restoreStaging": (True, True),
    "stagingFile": (True, False),
    "fieldDraftStagingFile": (True, False),
    "temporaryFile": (True, False),
    "database": (False, False),
    "databaseWAL": (False, False),
    "databaseSHM": (False, False),
    "generationPointer": (False, False),
    "generationPointerTemporary": (True, False),
    "generationLeaseDirectory": (True, True),
    "generationLeaseControl": (True, False),
    "generationLeaseControlTemporary": (True, False),
    "generationLeaseOwnerLock": (True, False),
    "journal": (True, False),
    "journalTemporary": (True, False),
    "mediaOriginal": (False, False),
    "mediaThumbnail": (False, False),
    "reportSnapshot": (False, False),
    "reportPDF": (False, False),
    "diagnostics": (True, False),
    "sceneNavigation": (True, False),
    "commerceEntitlementCache": (True, False),
    "portableExchangeDirectory": (True, True),
    "portableExchangeSessionFile": (True, False),
    "portableExchangeJournalFile": (True, False),
    "portableExchangeQuarantineFile": (True, False),
    "cache": (True, True),
    "scratch": (True, True),
    "searchIndex": (True, False),
}


def require(condition, message):
    if not condition:
        raise ValueError("invalid V23 native evidence: " + message)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read_json(path):
    require(path.is_file() and not path.is_symlink(), "missing or unsafe JSON file")
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)


def sha256(data):
    return hashlib.sha256(data).hexdigest().upper()


def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True) + "\n").encode()


def simulator_diagnostic_policy_binding(root):
    policy_path = root / SIMULATOR_DIAGNOSTIC_POLICY_PATH
    require(policy_path.is_file() and not policy_path.is_symlink(), "simulator diagnostic policy source")
    policy_bytes = policy_path.read_bytes()
    require(sha256(policy_bytes) == SIMULATOR_DIAGNOSTIC_POLICY_SHA256,
            "simulator diagnostic policy digest")
    policy = json.loads(policy_bytes.decode("utf-8"), object_pairs_hook=unique_pairs)
    require(policy.get("schema") == "v23-owner-simulator-file-protection-diagnostic-v1"
            and policy.get("policyID") == SIMULATOR_DIAGNOSTIC_POLICY_ID,
            "simulator diagnostic policy identity")
    require(policy.get("scope") == "Functional development diagnostics in DEBUG iOS Simulator builds only"
            and policy.get("requiredEvidenceDisposition") == SIMULATOR_DIAGNOSTIC_DISPOSITION,
            "simulator diagnostic policy scope")
    require(policy.get("unsupportedCountsAsPerKindProtectionSuccess") is False
            and policy.get("originalFailuresPreserved") is True
            and policy.get("providerQualification") is False
            and policy.get("acceptance") is False
            and policy.get("releaseReady") is False,
            "simulator diagnostic policy classification")
    source_path = root / SIMULATOR_DIAGNOSTIC_SOURCE_PATH
    require(source_path.is_file() and not source_path.is_symlink(), "simulator diagnostic allowance source")
    source_bytes = source_path.read_bytes()
    require(sha256(source_bytes) == SIMULATOR_DIAGNOSTIC_SOURCE_SHA256,
            "simulator diagnostic reviewed source digest")
    source = source_bytes.decode("utf-8")
    require(source.count(SIMULATOR_DIAGNOSTIC_PREFIX) == 1
            and source.count("policyID=" + SIMULATOR_DIAGNOSTIC_POLICY_ID) == 1
            and "#if DEBUG && os(iOS) && targetEnvironment(simulator)" in source,
            "simulator diagnostic allowance source markers")
    return {
        "schema": "v23-native-simulator-file-protection-diagnostic-binding-v1",
        "policyID": SIMULATOR_DIAGNOSTIC_POLICY_ID,
        "policyPath": SIMULATOR_DIAGNOSTIC_POLICY_PATH,
        "policySHA256": SIMULATOR_DIAGNOSTIC_POLICY_SHA256,
        "ownerPolicyOriginalSHA256": SIMULATOR_DIAGNOSTIC_OWNER_POLICY_SHA256,
        "allowanceSourcePath": SIMULATOR_DIAGNOSTIC_SOURCE_PATH,
        "allowanceSourceSHA256": sha256(source_bytes),
        "compiledScope": "DEBUG_IOS_SIMULATOR_ONLY",
        "requiredDisposition": SIMULATOR_DIAGNOSTIC_DISPOSITION,
        "diagnosticOnly": True,
        "countsAsPerKindProtectionSuccess": False,
        "providerQualification": False,
        "acceptance": False,
        "releaseReady": False,
    }


def parse_simulator_diagnostic_line(line):
    stripped = line.strip()
    require(stripped.startswith(SIMULATOR_DIAGNOSTIC_PREFIX + " "),
            "malformed simulator diagnostic marker")
    require(stripped.count(SIMULATOR_DIAGNOSTIC_PREFIX) == 1,
            "duplicate simulator diagnostic marker")
    tokens = stripped.split()
    require(tokens[0] == SIMULATOR_DIAGNOSTIC_PREFIX and len(tokens) == 1 + len(SIMULATOR_DIAGNOSTIC_FIELDS),
            "simulator diagnostic field count")
    pairs = []
    for token in tokens[1:]:
        key, separator, value = token.partition("=")
        require(bool(separator) and bool(key) and bool(value), "simulator diagnostic field")
        pairs.append((key, value))
    values = unique_pairs(pairs)
    require(tuple(values) == SIMULATOR_DIAGNOSTIC_FIELDS, "simulator diagnostic field order")
    require(values["policyID"] == SIMULATOR_DIAGNOSTIC_POLICY_ID
            and values["disposition"] == SIMULATOR_DIAGNOSTIC_DISPOSITION
            and values["request"] == "complete",
            "simulator diagnostic identity")
    require(values["capabilityBefore"] == values["capabilityAfter"] == "false",
            "simulator diagnostic capability")
    require(values["urlProtection"] == SIMULATOR_FALLBACK_PROTECTION,
            "simulator diagnostic protection readback")
    kind = values["kind"]
    require(kind in OWNED_FILE_DISPOSITIONS, "simulator diagnostic owned kind")
    expected_backup, expected_directory = OWNED_FILE_DISPOSITIONS[kind]
    require(values["backupExcluded"] == str(expected_backup).lower()
            and values["expectsDirectory"] == str(expected_directory).lower(),
            "simulator diagnostic kind disposition")
    require(values["identityUnchanged"] == "true", "simulator diagnostic identity change")
    return {
        "policyID": values["policyID"],
        "disposition": values["disposition"],
        "kind": kind,
        "request": values["request"],
        "capabilityBefore": False,
        "capabilityAfter": False,
        "urlProtection": values["urlProtection"],
        "backupExcluded": expected_backup,
        "expectsDirectory": expected_directory,
        "identityUnchanged": True,
    }


def _transport_status_path(artifact):
    return artifact / SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS


def _transport_directory(artifact):
    return artifact / SIMULATOR_DIAGNOSTIC_TRANSPORT_DIRECTORY


def _write_transport_status(artifact, value, replace=False):
    path = _transport_status_path(artifact)
    temporary = artifact / (SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS + ".next")
    require(not temporary.exists() and not temporary.is_symlink(),
            "diagnostic transport temporary status exists")
    if replace:
        require(path.is_file() and not path.is_symlink(), "diagnostic transport status replacement")
    else:
        require(not path.exists() and not path.is_symlink(), "diagnostic transport status exists")
    try:
        with temporary.open("xb") as stream:
            stream.write(canonical(value))
            stream.flush()
            os.fsync(stream.fileno())
        if replace:
            os.replace(temporary, path)
        else:
            os.link(temporary, path)
            temporary.unlink()
    finally:
        if temporary.exists() and not temporary.is_symlink():
            temporary.unlink()


class _DiagnosticCollectionDeadline(Exception):
    pass


@contextlib.contextmanager
def _diagnostic_real_time_limit(seconds):
    """Interrupt blocking local I/O on the native POSIX runner."""
    if (seconds <= 0 or not hasattr(signal, "SIGALRM")
            or not hasattr(signal, "setitimer")):
        if seconds <= 0:
            raise _DiagnosticCollectionDeadline("diagnostic collection deadline")
        yield
        return
    previous = signal.getsignal(signal.SIGALRM)
    def expired(_signum, _frame):
        raise _DiagnosticCollectionDeadline("diagnostic collection deadline")
    signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def _require_collection_time(started, monotonic):
    if monotonic() - started >= SIMULATOR_DIAGNOSTIC_WORK_SECONDS:
        raise _DiagnosticCollectionDeadline("diagnostic collection deadline")


def collect_simulator_diagnostic_transport(root, artifact, environment, interrupted=False,
                                           run=subprocess.run, monotonic=time.monotonic,
                                           read_chunk=None):
    """Collect closed app-container originals; never parse, repair, or infer a PASS."""
    started = monotonic()
    source_path = root / SIMULATOR_DIAGNOSTIC_SOURCE_PATH
    source_sha = None
    udid = environment.get("CI_SIMULATOR_UDID")
    base = {
        "schema": SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA,
        "status": "INTERRUPTED" if interrupted else "UNAVAILABLE",
        "simulatorUDID": udid,
        "appBundleID": SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID,
        "appRelativeDirectory": SIMULATOR_DIAGNOSTIC_APP_DIRECTORY,
        "sourcePath": SIMULATOR_DIAGNOSTIC_SOURCE_PATH,
        "sourceSHA256": source_sha,
        "files": [],
        "fileCount": 0,
        "totalBytes": 0,
        "inventorySHA256": sha256(canonical([])),
        "collectionBoundSeconds": SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS,
    }
    if interrupted:
        base["error"] = "native command interrupted"
    output_dir = _transport_directory(artifact)
    originals = []
    active = None
    require(artifact.is_dir() and not artifact.is_symlink(), "diagnostic artifact directory")
    _write_transport_status(artifact, base)
    def retain(status, error):
        base.update({
            "status": status,
            "error": error,
            "files": originals,
            "fileCount": len(originals),
            "totalBytes": sum(value["bytes"] for value in originals),
            "inventorySHA256": sha256(canonical(originals)),
        })
        _write_transport_status(artifact, base, replace=True)
    remaining = SIMULATOR_DIAGNOSTIC_WORK_SECONDS - (monotonic() - started)
    try:
        with _diagnostic_real_time_limit(remaining):
            source_sha = (sha256(source_path.read_bytes())
                          if source_path.is_file() and not source_path.is_symlink() else None)
            selected = key_values(artifact / "simulator-selection.txt")
            require(re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", udid or ""),
                    "diagnostic Simulator UDID")
            require(environment.get("CI_NATIVE_CREATED_SIMULATOR_UDID") == udid,
                    "diagnostic created Simulator")
            require(selected == {
                "runtime": "iOS 26.2", "runtime_build": "23C54", "name": "iPhone 17",
                "udid": udid, "initial_state": "Shutdown",
            }, "diagnostic fresh Simulator selection")
            require(source_sha is not None, "diagnostic source binding")
            base["sourceSHA256"] = source_sha
            retain("INTERRUPTED" if interrupted else "UNAVAILABLE",
                   "native command interrupted" if interrupted else "diagnostic collection incomplete")
            completed = run(
                ["xcrun", "simctl", "get_app_container", udid,
                 SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID, "data"],
                capture_output=True, text=True, timeout=min(2, max(0.001, remaining)), check=False,
            )
            _require_collection_time(started, monotonic)
            require(completed.returncode == 0 and completed.stderr == "", "diagnostic app container unavailable")
            require(completed.stdout.endswith("\n") and completed.stdout.count("\n") == 1,
                    "diagnostic app container output")
            container = Path(completed.stdout[:-1])
            require(container.is_absolute() and container.is_dir() and not container.is_symlink(),
                    "diagnostic app container")
            require(container.resolve(strict=True) == container, "diagnostic physical app container")
            leaf = container / SIMULATOR_DIAGNOSTIC_APP_DIRECTORY
            if leaf.exists() or leaf.is_symlink():
                require(leaf.is_dir() and not leaf.is_symlink() and leaf.resolve(strict=True) == leaf,
                        "unsafe diagnostic app directory")
                entries = sorted(leaf.iterdir(), key=lambda value: value.name)
            else:
                entries = []
            require(len(entries) <= SIMULATOR_DIAGNOSTIC_MAX_FILES, "diagnostic transport file count")
            output_dir.mkdir(mode=0o700)
            total = 0
            name_pattern = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl")
            reader = read_chunk or (lambda stream, count: stream.read(count))
            for source in entries:
                _require_collection_time(started, monotonic)
                info = source.lstat()
                require(name_pattern.fullmatch(source.name) is not None, "diagnostic transport file name")
                require(stat.S_ISREG(info.st_mode) and not source.is_symlink() and info.st_nlink == 1,
                        "unsafe diagnostic transport file")
                require(0 <= info.st_size <= SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES,
                        "diagnostic transport file size")
                total += info.st_size
                require(total <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES, "diagnostic transport total size")
                target = output_dir / source.name
                digest = hashlib.sha256()
                active = {"name": source.name, "bytes": 0, "sha256": digest.hexdigest().upper()}
                with source.open("rb", buffering=0) as incoming, target.open("xb", buffering=0) as outgoing:
                    while True:
                        _require_collection_time(started, monotonic)
                        chunk = reader(incoming, SIMULATOR_DIAGNOSTIC_COPY_CHUNK_BYTES)
                        if not chunk:
                            break
                        require(isinstance(chunk, bytes)
                                and len(chunk) <= SIMULATOR_DIAGNOSTIC_COPY_CHUNK_BYTES,
                                "diagnostic transport copy chunk")
                        written = outgoing.write(chunk)
                        require(type(written) is int and 0 <= written <= len(chunk),
                                "diagnostic transport copy write")
                        digest.update(chunk[:written])
                        active.update(bytes=active["bytes"] + written,
                                      sha256=digest.hexdigest().upper())
                        require(written == len(chunk), "diagnostic transport short write")
                        _require_collection_time(started, monotonic)
                    outgoing.flush()
                    os.fsync(outgoing.fileno())
                originals.append(active)
                active = None
                retain("INTERRUPTED" if interrupted else "UNSAFE",
                       "native command interrupted" if interrupted else "diagnostic collection incomplete")
                after = source.lstat()
                require((after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns)
                        == (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns),
                        "diagnostic transport changed during collection")
                require(originals[-1]["bytes"] == info.st_size,
                        "diagnostic transport copy size")
            _require_collection_time(started, monotonic)
            base.update({
                "status": "INTERRUPTED" if interrupted else ("AVAILABLE" if originals else "ZERO_USE"),
                "files": originals,
                "fileCount": len(originals),
                "totalBytes": sum(value["bytes"] for value in originals),
                "inventorySHA256": sha256(canonical(originals)),
            })
            if not interrupted:
                base.pop("error", None)
    except (_DiagnosticCollectionDeadline, OSError, subprocess.SubprocessError, ValueError) as error:
        if active is not None:
            originals.append(active)
            active = None
        base["status"] = "INTERRUPTED" if interrupted else (
            "UNAVAILABLE" if "unavailable" in str(error) else "UNSAFE")
        base["error"] = str(error)
        base["files"] = originals
        base["fileCount"] = len(originals)
        base["totalBytes"] = sum(value["bytes"] for value in originals)
        base["inventorySHA256"] = sha256(canonical(originals))
    _write_transport_status(artifact, base, replace=True)
    return base


def _strict_frame(line):
    require(0 < len(line) <= SIMULATOR_DIAGNOSTIC_MAX_FRAME_BYTES, "diagnostic frame size")
    require(line.endswith(b"\n") and b"\n" not in line[:-1] and b"\r" not in line,
            "diagnostic frame delimiter")
    value = json.loads(line[:-1].decode("utf-8"), object_pairs_hook=unique_pairs)
    require(type(value) is dict and set(value) == {
        "schema", "streamID", "sequence", "payloadBase64", "payloadByteCount", "payloadSHA256"
    }, "diagnostic frame fields")
    stream_id = value["streamID"]
    require(value["schema"] == SIMULATOR_DIAGNOSTIC_FRAME_SCHEMA
            and isinstance(stream_id, str)
            and re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", stream_id),
            "diagnostic frame identity")
    require(type(value["sequence"]) is int and value["sequence"] > 0,
            "diagnostic frame sequence")
    require(type(value["payloadByteCount"]) is int and 0 < value["payloadByteCount"] <= 4096,
            "diagnostic payload byte count")
    require(isinstance(value["payloadSHA256"], str)
            and re.fullmatch(r"[0-9A-F]{64}", value["payloadSHA256"]),
            "diagnostic payload digest")
    try:
        payload = base64.b64decode(value["payloadBase64"], validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError("invalid V23 native evidence: diagnostic payload base64") from error
    require(len(payload) == value["payloadByteCount"]
            and sha256(payload) == value["payloadSHA256"], "diagnostic payload binding")
    require(payload.endswith(b"\n") and b"\n" not in payload[:-1] and b"\r" not in payload,
            "diagnostic payload delimiter")
    event = parse_simulator_diagnostic_line(payload.decode("utf-8"))
    return value, payload, event


def simulator_diagnostic_observations(root, artifact, record):
    binding = simulator_diagnostic_policy_binding(root)
    require(record.get("simulatorFileProtectionDiagnosticPolicy") == binding,
            "simulator diagnostic admission binding")
    require(record.get("diagnosticOnly") is True
            and record.get("providerQualification") is False
            and record.get("acceptance") is False
            and record.get("releaseReady") is False,
            "simulator diagnostic admission classification")
    log_path = artifact / "test-smoke.log"
    evidence = {
        "schema": "v23-simulator-file-protection-diagnostics-v1",
        "policy": binding,
        "head": record.get("head"),
        "runID": record.get("runID"),
        "runAttempt": record.get("runAttempt"),
        "testLog": {"availability": "UNAVAILABLE", "path": "test-smoke.log", "sha256": None},
        "transport": {"availability": "UNAVAILABLE"},
        "parseStatus": "UNAVAILABLE",
        "events": [],
        "eventCount": 0,
        "zeroUseObserved": False,
        "countsAsPerKindProtectionSuccess": False,
        "diagnosticOnly": True,
        "providerQualification": False,
        "acceptance": False,
        "releaseReady": False,
    }
    parse_error = None
    log_bytes = None
    log_error = None
    if log_path.exists() or log_path.is_symlink():
        if not log_path.is_file() or log_path.is_symlink():
            evidence["testLog"]["availability"] = "UNSAFE"
            log_error = ValueError("unsafe simulator diagnostic test log")
        else:
            try:
                log_bytes = log_path.read_bytes()
                evidence["testLog"] = {
                    "availability": "AVAILABLE", "path": "test-smoke.log",
                    "sha256": sha256(log_bytes),
                }
            except OSError as error:
                evidence["testLog"]["availability"] = "UNSAFE"
                log_error = error
    try:
        require(SIMULATOR_DIAGNOSTIC_MARKER_STEM.encode() not in (log_bytes or b""),
            "console-only simulator diagnostic marker")
        status = read_json(_transport_status_path(artifact))
        evidence["transport"] = status
        exact_status_keys = {
            "schema", "status", "simulatorUDID", "appBundleID", "appRelativeDirectory",
            "sourcePath", "sourceSHA256", "files", "fileCount", "totalBytes",
            "inventorySHA256", "collectionBoundSeconds",
        }
        require(set(status) in (exact_status_keys, exact_status_keys | {"error"}),
                "diagnostic transport status fields")
        require(status["schema"] == SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA
                and status["appBundleID"] == SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID
                and status["appRelativeDirectory"] == SIMULATOR_DIAGNOSTIC_APP_DIRECTORY
                and status["sourcePath"] == SIMULATOR_DIAGNOSTIC_SOURCE_PATH
                and status["sourceSHA256"] == binding["allowanceSourceSHA256"]
                and status["collectionBoundSeconds"] == 3,
                "diagnostic transport binding")
        require(status["status"] in {
            "AVAILABLE", "ZERO_USE", "UNAVAILABLE", "UNSAFE", "INTERRUPTED"
        }, "diagnostic transport status")
        files = status["files"]
        require(type(files) is list and len(files) <= SIMULATOR_DIAGNOSTIC_MAX_FILES,
                "diagnostic transport inventory")
        for item in files:
            require(type(item) is dict and set(item) == {"name", "bytes", "sha256"}
                    and isinstance(item["name"], str)
                    and re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl",
                                     item["name"])
                    and type(item["bytes"]) is int
                    and 0 <= item["bytes"] <= SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES
                    and isinstance(item["sha256"], str)
                    and re.fullmatch(r"[0-9A-F]{64}", item["sha256"]),
                    "diagnostic transport inventory fields")
        require(type(status["fileCount"]) is int
                and status["fileCount"] == len(files)
                and type(status["totalBytes"]) is int
                and status["totalBytes"] == sum(value["bytes"] for value in files)
                and status["totalBytes"] <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES
                and status["inventorySHA256"] == sha256(canonical(files)),
                "diagnostic transport inventory")
        require((status["status"] in {"AVAILABLE", "ZERO_USE"}) == ("error" not in status),
                "diagnostic transport error classification")
        require(status["status"] in {"AVAILABLE", "ZERO_USE"},
                "diagnostic transport unavailable")
        selected_simulator = key_values(artifact / "simulator-selection.txt")
        require(status["simulatorUDID"] == selected_simulator.get("udid")
                and selected_simulator.get("initial_state") == "Shutdown",
                "diagnostic transport Simulator binding")
        if log_error is not None:
            raise log_error
        transport_dir = _transport_directory(artifact)
        if status["status"] == "ZERO_USE":
            require(files == [] and status["totalBytes"] == 0,
                    "diagnostic zero-use inventory")
            require(not transport_dir.exists() or (
                transport_dir.is_dir() and not transport_dir.is_symlink()
                and list(transport_dir.iterdir()) == []), "diagnostic zero-use directory")
            events = []
            raw_records = []
        else:
            require(files and transport_dir.is_dir() and not transport_dir.is_symlink(),
                    "diagnostic transport directory")
            require(sorted(value.name for value in transport_dir.iterdir())
                    == [value["name"] for value in files], "diagnostic transport members")
            events, raw_records, seen_streams = [], [], set()
            expected_names = []
            for item in files:
                name = item["name"]
                path = transport_dir / name
                info = path.lstat()
                require(stat.S_ISREG(info.st_mode) and not path.is_symlink() and info.st_nlink == 1,
                        "unsafe diagnostic transport member")
                raw = path.read_bytes()
                require(len(raw) == item["bytes"] and sha256(raw) == item["sha256"]
                        and 0 < len(raw) <= SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES,
                        "diagnostic transport member binding")
                lines = raw.splitlines(keepends=True)
                require(lines and len(lines) <= SIMULATOR_DIAGNOSTIC_MAX_EVENTS
                        and len(events) + len(lines) <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_EVENTS,
                        "diagnostic event count")
                stream_id = name[:-6]
                require(stream_id not in seen_streams, "duplicate diagnostic stream")
                seen_streams.add(stream_id)
                for expected_sequence, line in enumerate(lines, 1):
                    frame, payload, event = _strict_frame(line)
                    require(frame["streamID"] == stream_id
                            and frame["sequence"] == expected_sequence,
                            "diagnostic stream sequence")
                    events.append(event)
                    raw_records.append({
                        "streamID": stream_id, "sequence": expected_sequence,
                        "payloadByteCount": len(payload), "payloadSHA256": sha256(payload),
                    })
                expected_names.append(name)
            require(expected_names == sorted(expected_names), "diagnostic inventory order")
        evidence["parseStatus"] = "PASS"
        evidence["events"] = events
        evidence["rawRecords"] = raw_records
        evidence["eventCount"] = len(events)
        evidence["zeroUseObserved"] = status["status"] == "ZERO_USE"
    except (UnicodeDecodeError, json.JSONDecodeError, OSError, TypeError, ValueError) as error:
        evidence["parseStatus"] = "INVALID"
        evidence["events"] = events if "events" in locals() else []
        evidence["rawRecords"] = raw_records if "raw_records" in locals() else []
        evidence["eventCount"] = len(evidence["events"])
        evidence["parseError"] = str(error)
        parse_error = error
    return evidence, parse_error


def persist_simulator_diagnostic_observations(root, artifact, record):
    evidence, parse_error = simulator_diagnostic_observations(root, artifact, record)
    output = artifact / SIMULATOR_DIAGNOSTIC_OUTPUT
    require(not output.exists() and not output.is_symlink(), "simulator diagnostic evidence already exists")
    with output.open("xb") as stream:
        stream.write(canonical(evidence))
    if parse_error is not None:
        raise ValueError("invalid V23 native evidence: simulator diagnostic transport parse") from parse_error
    return evidence


def validate_selection(selection):
    require(isinstance(selection, dict), "selection object")
    require(set(selection) == {"schemaVersion", "taskID", "tier", "runUISmoke",
                              "unitTestSelectors", "uiTestSelectors", *BUDGET_KEYS}, "selection keys")
    require(type(selection["schemaVersion"]) is int and selection["schemaVersion"] == 1, "schema")
    require(selection["taskID"] == TASK and selection["tier"] in TIERS, "task/tier")
    require(all(type(selection[key]) is int for key in BUDGET_KEYS), "integer budgets")
    require(tuple(selection[key] for key in BUDGET_KEYS) == TIERS[selection["tier"]], "budgets")
    ui = selection["tier"] != "N8"
    require(type(selection["runUISmoke"]) is bool and selection["runUISmoke"] == ui, "UI/tier")
    for key, bundle in (("unitTestSelectors", "FieldEvidenceAppTests"),
                        ("uiTestSelectors", "FieldEvidenceAppUITests")):
        selectors = selection[key]
        require(isinstance(selectors, list) and all(isinstance(x, str) for x in selectors), key)
        require(len(selectors) == len(set(selectors)), "duplicate selectors")
        require(all(re.fullmatch(re.escape(bundle) + r"/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+", x)
                    for x in selectors), "exact native method selectors")
    require(bool(selection["unitTestSelectors"]), "no unit methods")
    require(len(selection["uiTestSelectors"]) == int(ui), "UI method count")


def selection_class(selector):
    parts = selector.split("/")
    require(len(parts) == 3 and parts[0] == "FieldEvidenceAppTests", "unit selector class")
    return parts[1]


def resolve_selection(default, selection_map, selection_id):
    """Resolve a closed N8 partition from the checked-in default selection.

    The map cannot carry selectors or paths.  It may only name complete XCTest
    classes already present in the default selection, so it cannot become an
    out-of-band selector override.
    """
    validate_selection(default)
    require(isinstance(selection_map, dict), "selection map object")
    require(set(selection_map) == {"schemaVersion", "taskID", "defaultSelectionID", "groups"},
            "selection map keys")
    require(selection_map["schemaVersion"] == 1 and selection_map["taskID"] == TASK,
            "selection map identity")
    require(selection_map["defaultSelectionID"] == DEFAULT_SELECTION_ID, "selection map default")
    require(isinstance(selection_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", selection_id),
            "selection ID")
    groups = selection_map["groups"]
    c36_group = {
        "id": "c36-restore-correspondence",
        "classes": ["V23CheckRunnerRestoreCorrespondenceTests",
                    "V23CheckRunnerRestoreBeginCorrespondenceTests",
                    "V23CheckRunnerBeginReceiptReferenceTests"],
        "methodCount": 30,
    }
    source_graph_shape = (
        isinstance(groups, list) and len(groups) == 32 and groups[-2] == c36_group
        and isinstance(groups[-1], dict) and groups[-1].get("id") == "c36-source-graph"
        and groups[-1].get("classes") == ["V23RepetitiveCaptureSourcePackageTests",
                                         "V23RepetitiveCaptureSourceGraphReviewTests"]
    )
    report_partition_layout = [{'id': 'c36-checkrunner-foundations', 'classes': ['V23CheckRunnerEditableFieldValuesTests', 'V23CheckRunnerBeginHistoryTests']}, {'id': 'c36-frozen-begin-preparation', 'classes': ['V23CheckRunnerFrozenBeginPreparationTests']}, {'id': 'c36-frozen-begin-writer', 'classes': ['V23CheckRunnerFrozenBeginWriterTests']}, {'id': 'c36-durable-begin', 'classes': ['V23CheckRunnerDurableInitialBeginTests']}, {'id': 'c36-field-contracts', 'classes': ['V23CheckRunnerItemFieldContractsTests']}]
    report_partition_shape = (
        isinstance(groups, list) and len(groups) == 37 and groups[30] == c36_group
        and isinstance(groups[31], dict) and groups[31].get("id") == "c36-source-graph"
        and groups[31].get("classes") == ["V23RepetitiveCaptureSourcePackageTests", "V23RepetitiveCaptureSourceGraphReviewTests"]
        and [{k: g.get(k) for k in ("id", "classes")} for g in groups[32:] if isinstance(g, dict)] == report_partition_layout
        and len([g for g in groups[:32] if isinstance(g, dict) and g.get("id") == "report-camera-recovery"
                 and g.get("classes") == ['S3_6CameraRecoveryTests', 'S4_5CorrectionTests', 'S6_2BackupExportTests', 'V9_18PackLifecycleIntegrationTests']]) == 1
    )
    generated_profile_shape = (
        isinstance(groups, list) and len(groups) == 41
        and sha256(canonical(default)) == GENERATED_SELECTION_POOL_SHA256
        and sha256(canonical(selection_map)) == GENERATED_SELECTION_MAP_SHA256
    )
    require(isinstance(groups, list) and
            (len(groups) == 30 or (len(groups) == 31 and groups[-1] == c36_group)
             or source_graph_shape or report_partition_shape or generated_profile_shape),
            "selection group count")
    defaults = set(default["unitTestSelectors"])
    default_classes = {selection_class(item) for item in defaults}
    covered = set()
    ids = set()
    resolved = {}
    for group in groups:
        require(isinstance(group, dict) and set(group) == {"id", "classes", "methodCount"},
                "selection group shape")
        group_id, classes, count = group["id"], group["classes"], group["methodCount"]
        require(isinstance(group_id, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", group_id)
                and group_id != DEFAULT_SELECTION_ID and group_id not in ids, "selection group ID")
        require(isinstance(classes, list) and classes and all(isinstance(item, str) and
                re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*Tests", item) for item in classes)
                and len(classes) == len(set(classes)), "selection group classes")
        require(set(classes) <= default_classes, "selection group contains unselected class")
        require(type(count) is int and count > 0, "selection group count value")
        members = [item for item in default["unitTestSelectors"] if selection_class(item) in classes]
        require(len(members) == count and members, "selection group members")
        member_set = set(members)
        require(not (covered & member_set), "overlapping selection group")
        covered.update(member_set)
        ids.add(group_id)
        derived = dict(default)
        derived["unitTestSelectors"] = members
        validate_selection(derived)
        resolved[group_id] = derived
    require(covered == defaults, "selection groups must cover default exactly")
    if report_partition_shape or generated_profile_shape:
        # Method partitions are source constants derived only after the complete
        # generated class map has passed every identity, overlap and coverage gate.
        require((sha256(canonical(default)), sha256(canonical(selection_map))) in (
                    (DURABLE_BEGIN_BASE_POOL_SHA256, DURABLE_BEGIN_BASE_MAP_SHA256),
                    (GENERATED_SELECTION_POOL_SHA256, GENERATED_SELECTION_MAP_SHA256)),
                "durable begin exact base pool/map")
        parent_members = tuple(resolved[DURABLE_BEGIN_PARENT_ID]["unitTestSelectors"])
        require(parent_members == DURABLE_BEGIN_PARENT_SELECTORS,
                "durable begin exact ordered parent")
        partition_ids = tuple(item[0] for item in DURABLE_BEGIN_METHOD_PARTITIONS)
        partition_members = tuple(member for _, members in DURABLE_BEGIN_METHOD_PARTITIONS
                                  for member in members)
        require(len(partition_ids) == len(set(partition_ids)) == 2
                and not (set(partition_ids) & (ids | {DEFAULT_SELECTION_ID})),
                "durable begin fixed partition IDs")
        require(len(partition_members) == len(set(partition_members)) == 9
                and set(partition_members) == set(parent_members),
                "durable begin complete disjoint union")
        for partition_id, members in DURABLE_BEGIN_METHOD_PARTITIONS:
            require(tuple(item for item in parent_members if item in set(members)) == members,
                    "durable begin fixed ordered partition members")
            derived = dict(default)
            derived["unitTestSelectors"] = list(members)
            validate_selection(derived)
            resolved[partition_id] = derived
        graph_parent_members = tuple(resolved[SOURCE_GRAPH_PARENT_ID]["unitTestSelectors"])
        require(graph_parent_members == SOURCE_GRAPH_PARENT_SELECTORS,
                "source graph exact ordered parent")
        graph_partition_ids = tuple(item[0] for item in SOURCE_GRAPH_METHOD_PARTITIONS)
        graph_partition_members = tuple(member for _, members in SOURCE_GRAPH_METHOD_PARTITIONS
                                        for member in members)
        require(len(graph_partition_ids) == len(set(graph_partition_ids)) == 3
                and not (set(graph_partition_ids) & (ids | set(partition_ids) | {DEFAULT_SELECTION_ID})),
                "source graph fixed partition IDs")
        require(len(graph_partition_members) == len(set(graph_partition_members)) == 25
                and set(graph_partition_members) == set(graph_parent_members),
                "source graph complete disjoint union")
        for partition_id, members in SOURCE_GRAPH_METHOD_PARTITIONS:
            require(tuple(item for item in graph_parent_members if item in set(members)) == members,
                    "source graph fixed ordered partition members")
            derived = dict(default)
            derived["unitTestSelectors"] = list(members)
            validate_selection(derived)
            resolved[partition_id] = derived
    if generated_profile_shape:
        photo_parent = tuple(default["unitTestSelectors"][701:716])
        require(photo_parent == PHOTO_BACKUP_PARENT_SELECTORS,
                "photo backup exact ordered source enrollment")
        photo_ids = tuple(item[0] for item in PHOTO_BACKUP_METHOD_PARTITIONS)
        photo_members = tuple(member for _, members in PHOTO_BACKUP_METHOD_PARTITIONS
                              for member in members)
        require(len(photo_ids) == len(set(photo_ids)) == 2
                and not (set(photo_ids) & (set(resolved) | {DEFAULT_SELECTION_ID})),
                "photo backup fixed partition IDs")
        require(len(photo_members) == len(set(photo_members)) == 15
                and set(photo_members) == set(photo_parent),
                "photo backup complete disjoint union")
        for partition_id, members in PHOTO_BACKUP_METHOD_PARTITIONS:
            require(tuple(item for item in photo_parent if item in set(members)) == members,
                    "photo backup fixed ordered partition members")
            derived = dict(default)
            derived["unitTestSelectors"] = list(members)
            validate_selection(derived)
            resolved[partition_id] = derived
    if generated_profile_shape:
        clone_members = tuple(default["unitTestSelectors"][716:])
        require(clone_members == CONFIGURATION_CLONE_SELECTORS
                and len(clone_members) == len(set(clone_members)) == 7,
                "configuration clone exact ordered source enrollment")
        require(CONFIGURATION_CLONE_SELECTION_ID not in set(resolved) | {DEFAULT_SELECTION_ID}
                and not (set(clone_members) & set(PHOTO_BACKUP_PARENT_SELECTORS)),
                "configuration clone fixed distinct selection")
        derived = dict(default)
        derived["unitTestSelectors"] = list(clone_members)
        validate_selection(derived)
        resolved[CONFIGURATION_CLONE_SELECTION_ID] = derived
    if selection_id == DEFAULT_SELECTION_ID:
        return default
    require(selection_id in resolved, "unknown selection ID")
    return resolved[selection_id]


def verify_generated_selection(root, default, selection_map):
    """The current pinned output must still equal its closed manifest/source."""
    source = root / "Scripts/v23-selection-generator.py"
    require(source.is_file() and not source.is_symlink(), "selection generator source")
    spec = importlib.util.spec_from_file_location("v23_selection_generator", source)
    require(spec is not None and spec.loader is not None, "selection generator module")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    manifest = generator.load_json(root / "Scripts/v23-selection-manifest.json")
    expected, expected_map, report = generator.generate(manifest, GENERATED_SELECTION_PROFILE, root)
    require(canonical(default) == canonical(expected) and canonical(selection_map) == canonical(expected_map),
            "generated selection differs from manifest/source")
    require(report["selectionSHA256"] == GENERATED_SELECTION_POOL_SHA256
            and report["selectionMapSHA256"] == GENERATED_SELECTION_MAP_SHA256,
            "generated selection profile digest")
    return report


def selected_input(root, environment):
    """Return the exact default or closed mapped selection for this execution."""
    default = read_json(root / "Scripts/ci-selection.json")
    selection_id = environment.get("NATIVE_SELECTION_ID", DEFAULT_SELECTION_ID)
    enabled = (environment.get("CI_NATIVE_ACCEPTANCE_CONTRACT") == CONTRACT
               or environment.get("SHARED_LANE") in LANES)
    if not enabled:
        require(selection_id == DEFAULT_SELECTION_ID, "selection ID outside ordinary route")
        return default, {"selectionID": DEFAULT_SELECTION_ID,
                         "selectionSHA256": sha256(canonical(default)), "selectionMapSHA256": ""}
    selection_map = read_json(root / SELECTION_MAP_PATH)
    selected = resolve_selection(default, selection_map, selection_id)
    if sha256(canonical(default)) == GENERATED_SELECTION_POOL_SHA256:
        verify_generated_selection(root, default, selection_map)
    return selected, {"selectionID": selection_id, "selectionSHA256": sha256(canonical(selected)),
                      "selectionMapSHA256": sha256((root / SELECTION_MAP_PATH).read_bytes())}


def admission(selection, environment, checkout_head, stage, selection_record=None, root=None):
    """Validate actual source inputs. Return None only for unchanged legacy routes."""
    e = environment
    if root is None:
        root = Path(__file__).resolve().parents[1]
    if selection_record is None:
        selection_record = {"selectionID": DEFAULT_SELECTION_ID,
                            "selectionSHA256": sha256(canonical(selection)), "selectionMapSHA256": ""}
    require(stage in ("dispatch", "worker"), "admission stage")
    if stage == "dispatch":
        lane = e.get("SHARED_LANE", "")
        if selection.get("taskID") != TASK and lane != "bitrise-build-hub-xcode-26.6-acceptance":
            return None
        require(lane in LANES, "integration lane")
        provider, label = LANES[lane]
        fields = {
            "SHARED_SHARD": "none", "SHARED_SEGMENT": "none", "SMOKE_ID": "none",
            "SHARED_SOURCE_RUN": "", "SHARED_SOURCE_MAP": "",
        }
        ui = e.get("SHARED_UI")
    else:
        contract = e.get("CI_NATIVE_ACCEPTANCE_CONTRACT", "none")
        if contract == "none" and selection.get("taskID") != TASK:
            return None
        require(contract == CONTRACT, "worker contract")
        provider, label = e.get("CI_RUNNER_PROVIDER"), e.get("CI_RUNNER_LABEL")
        lanes = [name for name, binding in LANES.items() if binding == (provider, label)]
        require(len(lanes) == 1, "provider/label")
        lane = lanes[0]
        fields = {
            "DISPATCH_S10_4_SHARD_ID": "none", "DISPATCH_S10_4_SEGMENT_ID": "none",
            "DISPATCH_S10_4_EXECUTION_ROLE": "independent", "DISPATCH_S10_4_PILOT_MODE": "false",
            "DISPATCH_S10_4_UNIT_ONLY": "false", "DISPATCH_S10_4_PAYLOAD_ARTIFACT_NAME": "",
            "DISPATCH_S10_4_DIAGNOSTIC_PROBE_ID": "none",
            "DISPATCH_S10_4_DIAGNOSTIC_EXECUTION_LANE": "none",
            "CI_S10_4_SHARED_BUILD_MODE": "none", "CI_S10_4_SHARED_PAYLOAD_RUN_ID": "",
            "WORKER_S10_4_MINIMUM_SEGMENT_ID": "none", "WORKER_S10_4_SHARED_MATRIX_ID": "",
            "WORKER_S10_4_MINIMUM_CORE_SMOKE_ID": "none", "WORKER_S10_4_SEGMENT_SOURCE_RUN_IDS": "",
        }
        ui = e.get("DISPATCH_RUN_UI_SMOKE")
    validate_selection(selection)
    require(e.get("GITHUB_REF") == "refs/heads/codex/v23-s10-integration-20260910",
            "simulator diagnostic source is never a main route")
    require(not any("SIMULATOR_FILE_PROTECTION" in key for key in e),
            "caller-supplied simulator diagnostic policy")
    diagnostic_policy = simulator_diagnostic_policy_binding(root)
    if stage == "worker" and e.get("CI_NATIVE_ACCEPTANCE_CONTRACT") == CONTRACT:
        require(e.get("DISPATCH_NATIVE_SELECTION_ID") == selection_record["selectionID"],
                "dispatcher selection ID")
        require(e.get("DISPATCH_NATIVE_SELECTION_SHA256") == selection_record["selectionSHA256"],
                "dispatcher selection digest")
        require(e.get("DISPATCH_NATIVE_SELECTION_MAP_SHA256") == selection_record["selectionMapSHA256"],
                "dispatcher selection map digest")
    require(all(e.get(key) == value for key, value in fields.items()), "foreign execution inputs")
    require(ui == str(selection["runUISmoke"]).lower(), "dispatch UI selection")
    require(e.get("GITHUB_REPOSITORY") == REPOSITORY, "repository")
    require(e.get("GITHUB_REF") in REFS, "ref")
    require(e.get("GITHUB_EVENT_NAME") == "workflow_dispatch", "event")
    head = e.get("GITHUB_SHA", "")
    require(re.fullmatch(r"[0-9a-f]{40}", head) is not None and checkout_head == head, "exact checkout head")
    require(all(re.fullmatch(r"[1-9][0-9]*", e.get(key, ""))
                for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT")), "original run identity")
    return {"contractID": CONTRACT, "taskID": TASK, "repository": REPOSITORY,
            "ref": e["GITHUB_REF"], "head": head, "runID": e["GITHUB_RUN_ID"],
            "runAttempt": e["GITHUB_RUN_ATTEMPT"], "executionLane": lane,
            "runnerProvider": provider, "runnerLabel": label, **selection_record,
            "simulatorFileProtectionDiagnosticPolicy": diagnostic_policy,
            "diagnosticOnly": True, "providerQualification": False,
            "acceptance": False, "releaseReady": False}


def executed_methods(result, expected, bundle, bundle_type):
    """Read original xcresult test nodes; never deduplicate or count skipped tests."""
    require(isinstance(result, dict) and isinstance(result.get("testNodes"), list), "native test tree")
    observed = []
    bundles = []

    def walk(node, current_bundle=None):
        require(isinstance(node, dict), "native test node")
        children = node.get("children", [])
        require(isinstance(children, list), "native test children")
        if node.get("nodeType") in ("Unit test bundle", "UI test bundle"):
            require(node.get("nodeType") == bundle_type and node.get("name") == bundle, "native bundle")
            current_bundle = bundle
            bundles.append(bundle)
        if node.get("nodeType") == "Test Case":
            require(current_bundle == bundle and not children, "leaf native case ownership")
            identifier = node.get("nodeIdentifier")
            require(isinstance(identifier, str), "native identifier")
            identifier = re.sub(r"\(\)$", "", identifier)
            if not identifier.startswith(bundle + "/"):
                identifier = bundle + "/" + identifier
            require(node.get("result") == "Passed", "native case did not pass")
            observed.append(identifier)
        else:
            for child in children:
                walk(child, current_bundle)

    for node in result["testNodes"]:
        walk(node)
    require(bundles == [bundle], "exactly one native bundle")
    require(len(observed) == len(set(observed)), "duplicate native methods")
    require(sorted(observed) == sorted(expected) and observed, "exact executed method set")
    return sorted(observed)


def key_values(path):
    require(path.is_file() and not path.is_symlink(), "missing fact file")
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        require(bool(separator) and bool(key), "fact line")
        pairs.append((key, value))
    return unique_pairs(pairs)


def source_binding(root):
    sources = {}
    for relative in PROTOCOL_PATHS:
        path = root / relative
        require(path.is_file() and not path.is_symlink(), "protocol source")
        sources[relative] = sha256(path.read_bytes())
    selection_map = root / SELECTION_MAP_PATH
    require(selection_map.is_file() and not selection_map.is_symlink(), "selection map source")
    return {"protocolSources": sources, "protocolSHA256": sha256(canonical(sources)),
            "selectorSHA256": sha256((root / "Scripts/ci-selection.json").read_bytes()),
            "selectionMapSHA256": sha256(selection_map.read_bytes()),
            "simulatorFileProtectionDiagnosticPolicy": simulator_diagnostic_policy_binding(root)}


def verify_checkpoint(root, artifact, record, selection, environment):
    diagnostic_evidence = persist_simulator_diagnostic_observations(root, artifact, record)
    require(environment.get("NATIVE_PRIOR_JOB_STATUS") == "success", "earlier job failure")
    require(diagnostic_evidence["testLog"]["availability"] == "AVAILABLE"
            and diagnostic_evidence["parseStatus"] == "PASS",
            "successful units require simulator diagnostic log")
    require(read_json(artifact / "native-admission.json") == record, "admission changed")
    selected_artifact = artifact / "ci-selection.selected.json"
    require(selected_artifact.is_file() and not selected_artifact.is_symlink()
            and selected_artifact.read_bytes() == canonical(selection), "selected artifact binding")
    if record["selectionMapSHA256"]:
        selection_map = artifact / "ci-selection-map.json"
        require(selection_map.is_file() and not selection_map.is_symlink()
                and sha256(selection_map.read_bytes()) == record["selectionMapSHA256"],
                "selection map artifact binding")
    provider = key_values(artifact / "runner-provider.txt")
    require(provider.get("provider") == record["runnerProvider"]
            and provider.get("label") == record["runnerLabel"], "observed provider")
    require(provider.get("runner_architecture") == "ARM64"
            and provider.get("uname_architecture") == "arm64", "architecture")
    expected_dir = ("/Applications/Xcode-26.6.0.app/Contents/Developer"
                    if record["runnerProvider"] == "bitrise"
                    else "/Applications/Xcode_26.6.app/Contents/Developer")
    require(provider.get("developer_dir") == expected_dir, "resolved developer directory")
    require((artifact / "xcode-version.txt").read_text().splitlines()
            == ["Xcode 26.6", "Build version 17F113"], "observed Xcode")
    sdk = key_values(artifact / "native-sdk.txt")
    require(sdk == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"}, "observed SDK")
    simulator = key_values(artifact / "simulator-selection.txt")
    require((simulator.get("runtime"), simulator.get("runtime_build"), simulator.get("name"))
            == ("iOS 26.2", "23C54", "iPhone 17"), "observed Simulator")
    require(simulator.get("initial_state") == "Shutdown"
            and simulator.get("udid") == environment.get("CI_NATIVE_CREATED_SIMULATOR_UDID"),
            "fresh owned Simulator")
    units = executed_methods(read_json(artifact / "unit-test-results.json"),
                             selection["unitTestSelectors"], "FieldEvidenceAppTests", "Unit test bundle")
    ui = []
    if selection["runUISmoke"]:
        ui = executed_methods(read_json(artifact / "ui-test-results.json"),
                              selection["uiTestSelectors"], "FieldEvidenceAppUITests", "UI test bundle")
        screenshot = artifact / "ui-final.png"
        require(screenshot.is_file() and not screenshot.is_symlink()
                and screenshot.stat().st_size > 8, "native UI screenshot")
        with screenshot.open("rb") as stream:
            require(stream.read(8) == b"\x89PNG\r\n\x1a\n", "native UI PNG")
    else:
        require(not any((artifact / name).exists() for name in
                        ("UISmoke.xcresult", "ui-test-results.json", "ui-final.png", "ui-smoke.log")),
                "unexpected UI evidence")
    if record["runnerProvider"] == "bitrise":
        require(provider.get("macos_product_version") == "26.6.1", "Bitrise OS")
        for name in ("bitrise-build-cache-cli-verification.txt", "bitrise-build-cache-wrapper-paths.txt"):
            path = artifact / name
            require(path.is_file() and not path.is_symlink() and path.stat().st_size > 0, "cache provenance")
        activation = (artifact / "bitrise-build-cache-activation.log").read_text().splitlines()
        require(activation.count("benchmark_phase=established") > 0
                and activation.count("benchmark_phase=established") == activation.count("activation_exit=0")
                and activation.count("cache=true") == activation.count("activation_exit=0")
                and activation.count("cache_push=true") == activation.count("activation_exit=0"), "cache activation")
    return {**record, "recordType": "validated-native-checkpoint", "executedUnitMethods": units,
            "executedUIMethods": ui, "simulator": simulator, "provider": provider, "sdk": sdk,
            "simulatorFileProtectionDiagnostics": diagnostic_evidence,
            "wholeAppAcceptance": False, "humanReviewComplete": False,
            "diagnosticOnly": True, "providerQualification": False,
            "acceptance": False, "releaseReady": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("admit", "verify", "select", "collect-diagnostics"))
    parser.add_argument("--stage", choices=("dispatch", "worker"), default="worker")
    parser.add_argument("--output")
    parser.add_argument("--interrupted", action="store_true")
    args = parser.parse_args()
    root = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    if args.command == "collect-diagnostics":
        artifact = Path(os.environ["CI_ARTIFACT_DIR"])
        collect_simulator_diagnostic_transport(
            root, artifact, os.environ, interrupted=args.interrupted
        )
        return
    selection, selection_record = selected_input(root, os.environ)
    if args.command == "select":
        require(args.output is not None, "selection output")
        output = Path(args.output)
        require(output.parent.is_dir() and not output.exists() and not output.is_symlink(), "selection output path")
        output.write_bytes(canonical(selection))
        return
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    record = admission(selection, os.environ, head, args.stage, selection_record, root=root)
    if args.stage == "dispatch":
        require(args.command == "admit", "dispatch command")
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
            stream.write("native_acceptance_contract=" + (CONTRACT if record else "none") + "\n")
            if record:
                stream.write("native_selection_id=" + record["selectionID"] + "\n")
                stream.write("native_selection_sha256=" + record["selectionSHA256"] + "\n")
                stream.write("native_selection_map_sha256=" + record["selectionMapSHA256"] + "\n")
        return
    if record is None:
        return
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    record.update(source_binding(root))
    record["gitTree"] = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    artifact = Path(os.environ["CI_ARTIFACT_DIR"])
    require(artifact.is_dir() and not artifact.is_symlink(), "artifact directory")
    name = "native-admission.json"
    if args.command == "verify":
        record = verify_checkpoint(root, artifact, record, selection, os.environ)
        name = "native-checkpoint.json"
    with (artifact / name).open("xb") as stream:
        stream.write(canonical(record))


if __name__ == "__main__":
    main()
