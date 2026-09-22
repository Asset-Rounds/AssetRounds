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
import math
import os
from pathlib import Path
import re
import signal
import shlex
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
         "F25": (300, 900, 1200, 1800, 4500), "D30": (300, 1800, 900, 0, 3000)}
BUILD_WATCHDOG_SELECTION_ID = "c36-parent-finalization-check-no-issue-build30m"
BUILD_WATCHDOG_PARENT = "6289befddaf75036c7fb7a4d971ba7cc171ec003"
BUILD_ORDER_SELECTION_ID = "c36-destination-discard-build-before-boot"
BUILD_ORDER_PARENT = "acf0e7a75969627019ed0dcb7c6254b411af94ed"
BUILD_ORDER_TREES = {
    "FieldEvidenceApp": "34676b2dd2f55f00b3b551a79c06fa565549b511",
    "FieldEvidenceAppTests": "23500681d0ec7cf97deb4b22a9e638cdc4c35311",
    "FieldEvidenceAppUITests": "978eced2587c6ed6cb280aa6cea7d4e3fa6e4190",
    "FieldEvidenceApp.xcodeproj": "4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0",
}
NO_INDEX_SELECTION_ID = "c36-restore-review-no-index"
NO_INDEX_PARENT = '5c1e9831153e9e5feddda08e1152de06ecbaaed2'
NO_INDEX_TREES = {'FieldEvidenceApp': 'cf661d0cb9a754135dfdea02fc7fa81967163331', 'FieldEvidenceAppTests': '6ae80744a230727892ceb04617421d91fd17e53a', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
NO_INDEX_RECEIPT = "no-index-build-command.json"
RESTORE_BUILD_WATCHDOG_SELECTION_ID = "c36-restore-review-no-index-build30m"
RESTORE_BUILD_WATCHDOG_PARENT = 'e3a60f5631edd67b1fac9a74baba5a2011f95ec5'
RESTORE_BUILD_WATCHDOG_TREES = {'FieldEvidenceApp': '3aa48164f61afb614549ee785cbe184118460ae2', 'FieldEvidenceAppTests': '9beb1476664acad52a4892a6f4d4d74ac39cabdc', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
RESTORE_BUILD_WATCHDOG_SELECTORS = tuple(
    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/" + method for method in (
        "testPhysicalForkCreatesReviewReceiptAndSecondHopSurvivesOriginalPackageRemoval",
        "testPopulatedCrossWorkspaceReplacementCreatesOnlyReviewAndRetainsOriginalHistory",
        "testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes",
        "testPrepublicationInterruptionReconcilesToUnchangedPopulatedGeneration",
        "testPhysicalForkKeepsTerminalHistoryAndUnrelatedDraftOwners",
        "testReviewPlanRejectsMissingOrChangedOwnedRowsWithoutConsumingUnrelatedDrafts",
    )
)
REMINDER_BUILD_WATCHDOG_SELECTION_ID = "reminder-production-no-index-build30m"
REMINDER_BUILD_WATCHDOG_PARENT = 'e3a60f5631edd67b1fac9a74baba5a2011f95ec5'
REMINDER_BUILD_WATCHDOG_TREES = {'FieldEvidenceApp': '3aa48164f61afb614549ee785cbe184118460ae2', 'FieldEvidenceAppTests': '9beb1476664acad52a4892a6f4d4d74ac39cabdc', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
REMINDER_BUILD_WATCHDOG_GROUPS = ('reminder-policy-edit', 'reminder-production-settings', 'reminder-detailed-delivery', 'reminder-control-continuation')
REMINDER_BUILD_WATCHDOG_SELECTORS = (
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testUnboundAndRetiredOwnersCannotMintOrRebind',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testDisabledForegroundEditAndFreshAuthorityReplayPreserveExactBytes',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testEnabledPolicyRequiresUnlockAndOldCommandCannotSurviveRelock',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testCommandsCannotTransferAcrossAdaptersOrGateIssuers',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testReplacementOwnerAcceptsOnlyFreshCommandsAndRetirementIsMonotonic',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testProtectedDataAndConfigurationTransitionsRevokeHeldEditsWithoutEffects',
    'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testActualPreferenceWriteSerializesWithRevocationAndRetirement',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionReconciliationRetryKeepsSavedRevisionAndNeverPrompts',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionSettingsReadDoesNotPromptAndDeniedEnablePersistsExplicitChoice',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionDetailChoiceWhileDisabledDoesNotPromptAndRejectsStaleEdit',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionAppLockRequiresUnlockAndOldSettingsPublicationStaysRevoked',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionPermissionReplyAfterBackgroundCannotSaveConsent',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReadNeverPromptsAndExplicitRequestNeverWritesConsent',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testInactiveDisabledAndLockedEnabledStatesCannotPrompt',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testRevocationDuringAuthorizationReadPreventsPrompt',
    'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReplyAfterRevocationCannotRenewForegroundOrConsent',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testGenericEncodingAndReadbackRetainExactLegacyShape',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testBothKindsUseApprovedCopyAndTokenOnlySystemPayload',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenZoneAndEffectiveInstantDistinguishDSTFold',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testDetailedReadbackRejectsUnapprovedCopyAndAncillaryFields',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testNumericZoneFallbackUsesExplicitOffsetWithoutDeviceDefaults',
    'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenOffsetCopyDoesNotResolveCurrentTimeZoneRules',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testIncompleteEnableAndDisableRemainAvailableForAuthenticatedRecovery',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testEnabledAndCompletedDisabledEditsReopenWithoutReplayingPolicyOrOSEffects',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testSecondEditRollsContinuationAndRejectsOldOperationAndAuthenticationSubject',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPreferenceAndPendingPublicationRecoverMetadataExactlyOnce',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPolicyEditRejectsOldSubjectBeforeNewToggleSourceOrOSEffects',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testDivergentPendingBlocksSettlementAndSecondPolicyWriteWithoutDiscardingEvidence',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testUnstampedResetEraseAndChangedStampCannotRepairControl',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testForeignPreferencesControlBindingAndChangedSettingDenyBeforePolicyWrite',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testMissingDisabledControlWithStampOrPendingIsNotReady',
    'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testNilContinuationPreservesLegacyCanonicalControlAndSubjectBytes',
)
RESTORE_HISTORY_SELECTION_ID = "restore-history-no-index-build30m"
RESTORE_HISTORY_PARENT = 'e3a60f5631edd67b1fac9a74baba5a2011f95ec5'
RESTORE_HISTORY_TREES = {'FieldEvidenceApp': '3aa48164f61afb614549ee785cbe184118460ae2', 'FieldEvidenceAppTests': '9beb1476664acad52a4892a6f4d4d74ac39cabdc', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
RESTORE_HISTORY_GROUPS = ("c36-restore-review", "replacement-packet-union")
RESTORE_HISTORY_PACKET_SELECTOR = 'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot'
RESTORE_HISTORY_SELECTORS = RESTORE_BUILD_WATCHDOG_SELECTORS + (RESTORE_HISTORY_PACKET_SELECTOR,)
REPLACEMENT_UNION_SELECTION_ID = "replacement-union-no-index-build30m"
REPLACEMENT_UNION_PARENT = 'e3a60f5631edd67b1fac9a74baba5a2011f95ec5'
REPLACEMENT_UNION_TREES = {'FieldEvidenceApp': '3aa48164f61afb614549ee785cbe184118460ae2', 'FieldEvidenceAppTests': '9beb1476664acad52a4892a6f4d4d74ac39cabdc', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
REPLACEMENT_UNION_SELECTORS = (
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPureRuleCreatesOnlyCurrentOnlyTombstonesAndRejectsCollisions',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testCancelRemovesOnlyOwnedStageAndDirtyCurrentFailsClosed',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPacketCollisionFailsBeforeGenerationOrJournalMutation',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRecoveryPreservesReplacementUnionAcrossEveryJournalPhase',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRestoreIntentTimestampUsesOneCanonicalMillisecondDomain',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C18RegistryPointerBindsPromotionReceiptIdentity',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C05Records42ReplacementUnionsPredecessorClosedMetadata',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C36ReplacementRecordRetainsCanonicalOperationalIdentity',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testC21ClientCapabilityLifecycleAnchor',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C34PackageRouteUsesOneShellAndNoWriter',
    'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testFinalizedReportBytesAndReceiptsSurviveRepeatedForkAndColdReadback',
)
ERASE_BUILD_WATCHDOG_SELECTION_ID = "erase-recovery-no-index-build30m"
ERASE_BUILD_WATCHDOG_PARENT = '462a71141f0189598ff041b3a0dc9f2798e4b23e'
ERASE_BUILD_WATCHDOG_TREES = {'FieldEvidenceApp': '1d2dcbd90fd171e13f2934d8b866fccbabaffbe4', 'FieldEvidenceAppTests': '750961983ffc827c3ed7ca964eca9b53f68c2d2c', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
ERASE_DRAIN_SELECTION_ID = "erase-drain-timing-no-index-build30m"
ERASE_REMAINDER_SELECTION_ID = "erase-remainder-no-index-build30m"
ERASE_PARTITION_PARENT = '16e82a8baded44cea8ed4a2c97a685df7d0b4154'
ERASE_PARTITION_TREES = {'FieldEvidenceApp': '4026fabeab434086e3acbf9dcb03113da5d31128', 'FieldEvidenceAppTests': '9060b1c7c444a17d187f5001a61278fba507359b', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
NO_INDEX_ROUTES = {
    REPLACEMENT_UNION_SELECTION_ID: (REPLACEMENT_UNION_PARENT, "D30"),
    ERASE_DRAIN_SELECTION_ID: (ERASE_PARTITION_PARENT, "D30"),
    ERASE_REMAINDER_SELECTION_ID: (ERASE_PARTITION_PARENT, "D30"),
    ERASE_BUILD_WATCHDOG_SELECTION_ID: (ERASE_BUILD_WATCHDOG_PARENT, "D30"),
    RESTORE_HISTORY_SELECTION_ID: (RESTORE_HISTORY_PARENT, "D30"),
    NO_INDEX_SELECTION_ID: (NO_INDEX_PARENT, "N8"),
    RESTORE_BUILD_WATCHDOG_SELECTION_ID: (RESTORE_BUILD_WATCHDOG_PARENT, "D30"),
    REMINDER_BUILD_WATCHDOG_SELECTION_ID: (REMINDER_BUILD_WATCHDOG_PARENT, "D30"),
}


def no_index_source_trees(selection_id):
    require(selection_id in NO_INDEX_ROUTES, "no-index closed source binding")
    if selection_id == REPLACEMENT_UNION_SELECTION_ID:
        return REPLACEMENT_UNION_TREES
    if selection_id in (ERASE_DRAIN_SELECTION_ID, ERASE_REMAINDER_SELECTION_ID):
        return ERASE_PARTITION_TREES
    if selection_id == ERASE_BUILD_WATCHDOG_SELECTION_ID:
        return ERASE_BUILD_WATCHDOG_TREES
    if selection_id == RESTORE_HISTORY_SELECTION_ID:
        return RESTORE_HISTORY_TREES
    if selection_id == REMINDER_BUILD_WATCHDOG_SELECTION_ID:
        return REMINDER_BUILD_WATCHDOG_TREES
    return (RESTORE_BUILD_WATCHDOG_TREES if selection_id == RESTORE_BUILD_WATCHDOG_SELECTION_ID
            else NO_INDEX_TREES)


BUILD_ORDER_OBSERVATIONS = "build-before-boot.jsonl"
BUILD_ORDER_COMMAND = ("bash", "Scripts/build-smoke.sh")
BUDGET_KEYS = ("setupArtifactTimeoutSeconds", "buildTimeoutSeconds", "testTimeoutSeconds",
               "uiTimeoutSeconds", "totalBudgetSeconds")
PROTOCOL_PATHS = (
    "Scripts/ci-worker-selection.jq",
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
DESTINATION_LEGACY_SELECTION_ID = "c36-destination-legacy-bytes"
DESTINATION_LEGACY_SELECTOR = 'FieldEvidenceAppTests/V9_30FieldDraftResilienceTests/testReviewedTargetCarrierPreservesLegacyMyDayCanonicalResolutionBytes'
ERASE_RECOVERY_SELECTION_ID = "erase-recovery"
ERASE_LEASE_SELECTORS = ('FieldEvidenceAppTests/S2PersistenceLedgerTests/testDeferredEraseRetainsLiveOldContextAcrossAppAccessResumeUntilDrain', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testSuspendedRestoredActivationCannotReleaseANewerBindingInTheSameCoordinator', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testRepeatedLifecyclePausesRetainPostAdoptionActivationForExactRetry', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testPostAdoptionExecutionRevokedAtFirstAwaitCannotInstallAStaleTokenOrRead', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testSupersededPostAdoptionCatchCannotOverwriteNewReadyExecution', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupReleaseFailureRetainsOriginalOwnerAndRetries', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupInterruptionAfterRetirementResumesOriginalTicket', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testImmediateEraseCleanupReplacesRetiredWriterBeforePublication', 'FieldEvidenceAppTests/S2PersistenceLedgerTests/testErasedActivationMismatchAndRepeatedBeginReleaseOnlyTheAcquiredWriter')
ERASE_RECOVERY_SELECTORS = ERASE_LEASE_SELECTORS + ('FieldEvidenceAppTests/V23ProductionAppAccessTests/testPresentationDeferredEraseRetainsDrainAcrossPauseAndResumesWithFreshService', 'FieldEvidenceAppTests/V23ProductionAppAccessTests/testProductionEraseAdoptsFreshSettingOwnerAndNextToggleCommits', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit', 'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState')
ERASE_DIAGNOSTIC_PARTITIONS = (
    (ERASE_DRAIN_SELECTION_ID, ERASE_RECOVERY_SELECTORS[:1]),
    (ERASE_REMAINDER_SELECTION_ID, ERASE_RECOVERY_SELECTORS[1:]),
)
GENERATED_SELECTION_PROFILE = 'replacement-history-coverage-v1'
GENERATED_SELECTION_POOL_SHA256 = 'CAC57003CD7FFFA77BB4213C7132C62F2B74F16BBF12F4F6017D65372E293C06'
GENERATED_SELECTION_MAP_SHA256 = 'ED7B55ACCE7622188EFC8DCE634F8ADC621EA384BD791E2397D3A568E74340D7'
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
PARENT_FINALIZATION_METHOD_PARTITIONS = (
    ('c36-parent-finalization-check-no-issue', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-check-visible-issue', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckVisibleIssueUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-check-could-not-verify', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckCouldNotVerifyUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-recheck-resolved', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckResolvedUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-recheck-still-visible', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckStillVisibleUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-recheck-different-issue', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckDifferentIssueUsesOriginalFiveSagaHistory',)),
    ('c36-parent-finalization-recheck-could-not-verify', ('FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckCouldNotVerifyUsesOriginalFiveSagaHistory',)),
)
PARENT_FINALIZATION_SELECTORS = tuple(
    member for _, members in PARENT_FINALIZATION_METHOD_PARTITIONS for member in members)
CLONE_RETIREMENT_METHOD_PARTITIONS = (
    ('c36-clone-retirement-old-pointer', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementOldPointerRollbackRestoresExactIncumbent',)),
    ('c36-clone-retirement-pointer-cleanup', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementPointerLagAndPrivateCleanupResume',)),
    ('c36-clone-retirement-terminal-metadata', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementTerminalMetadataResumesWithoutBaseIntent',)),
    ('c36-clone-retirement-rollback', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementRollbackInterruptionsResume',)),
    ('c36-clone-retirement-unclaimed-binding', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementUnclaimedScaffoldAndBindingTamperFailClosed',)),
    ('c36-clone-retirement-private-hostility', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementChangedPrivateBytesAndUnknownNodesRemainUntouched',)),
    ('c36-clone-retirement-access-cancel', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementAccessAndCancellationRetainRecoveryOwner',)),
    ('c36-clone-retirement-inode-substitution', ('FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementClaimRejectsAnInodeSubstitution',)),
)
CLONE_RETIREMENT_SELECTORS = tuple(
    member for _, members in CLONE_RETIREMENT_METHOD_PARTITIONS for member in members)
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
SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA = "v23-simulator-file-protection-transport-v2"
SIMULATOR_DIAGNOSTIC_LEGACY_TRANSPORT_SCHEMA = "v23-simulator-file-protection-transport-v1"
SIMULATOR_DIAGNOSTIC_MAX_FILES = 64
SIMULATOR_DIAGNOSTIC_MAX_EVENTS = 100_000
SIMULATOR_DIAGNOSTIC_MAX_TOTAL_EVENTS = SIMULATOR_DIAGNOSTIC_MAX_FILES * SIMULATOR_DIAGNOSTIC_MAX_EVENTS
SIMULATOR_DIAGNOSTIC_MAX_FRAME_BYTES = 8 * 1024
SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES = (
    SIMULATOR_DIAGNOSTIC_MAX_EVENTS * SIMULATOR_DIAGNOSTIC_MAX_FRAME_BYTES
)
SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES = 1024 * 1024 * 1024
SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS = 30
SIMULATOR_DIAGNOSTIC_WORK_SECONDS = 29.5
SIMULATOR_DIAGNOSTIC_LOOKUP_SECONDS = 10
SIMULATOR_DIAGNOSTIC_INTERRUPTED_COLLECTION_SECONDS = 3
SIMULATOR_DIAGNOSTIC_INTERRUPTED_WORK_SECONDS = 2.5
SIMULATOR_DIAGNOSTIC_INTERRUPTED_LOOKUP_SECONDS = 2
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


def _require_collection_time(started, monotonic, work_seconds):
    if monotonic() - started >= work_seconds:
        raise _DiagnosticCollectionDeadline("diagnostic collection deadline")


def collect_simulator_diagnostic_transport(root, artifact, environment, interrupted=False,
                                           run=subprocess.run, monotonic=time.monotonic,
                                           read_chunk=None):
    """Collect closed app-container originals; never parse, repair, or infer a PASS."""
    require(type(interrupted) is bool, "diagnostic interruption mode")
    collection_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_COLLECTION_SECONDS if interrupted
                          else SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS)
    work_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_WORK_SECONDS if interrupted
                    else SIMULATOR_DIAGNOSTIC_WORK_SECONDS)
    lookup_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_LOOKUP_SECONDS if interrupted
                      else SIMULATOR_DIAGNOSTIC_LOOKUP_SECONDS)
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
        "collectionBoundSeconds": collection_seconds,
        "collectionMode": "interrupted" if interrupted else "completed",
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
    remaining = work_seconds - (monotonic() - started)
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
            _require_collection_time(started, monotonic, work_seconds)
            remaining = work_seconds - (monotonic() - started)
            completed = run(
                ["xcrun", "simctl", "get_app_container", udid,
                 SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID, "data"],
                capture_output=True, text=True,
                timeout=min(lookup_seconds, max(0.001, remaining)), check=False,
            )
            _require_collection_time(started, monotonic, work_seconds)
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
                _require_collection_time(started, monotonic, work_seconds)
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
                        _require_collection_time(started, monotonic, work_seconds)
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
                        _require_collection_time(started, monotonic, work_seconds)
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
            _require_collection_time(started, monotonic, work_seconds)
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
        if status.get("schema") == SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA:
            exact_status_keys.add("collectionMode")
            mode = status.get("collectionMode")
            expected_bound = {"completed": 30, "interrupted": 3}.get(
                mode if isinstance(mode, str) else "")
            require(expected_bound is not None
                    and (status.get("status") == "INTERRUPTED") == (mode == "interrupted"),
                    "diagnostic transport mode")
        else:
            require(status.get("schema") == SIMULATOR_DIAGNOSTIC_LEGACY_TRANSPORT_SCHEMA,
                    "diagnostic transport schema")
            expected_bound = 3
        require(set(status) in (exact_status_keys, exact_status_keys | {"error"}),
                "diagnostic transport status fields")
        require(status["appBundleID"] == SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID
                and status["appRelativeDirectory"] == SIMULATOR_DIAGNOSTIC_APP_DIRECTORY
                and status["sourcePath"] == SIMULATOR_DIAGNOSTIC_SOURCE_PATH
                and status["sourceSHA256"] == binding["allowanceSourceSHA256"]
                and type(status["collectionBoundSeconds"]) is int
                and status["collectionBoundSeconds"] == expected_bound,
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
    ui = selection["tier"] not in ("N8", "D30")
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
    if selection["tier"] == "D30":
        require(tuple(selection["unitTestSelectors"]) in (
            PARENT_FINALIZATION_METHOD_PARTITIONS[0][1], RESTORE_BUILD_WATCHDOG_SELECTORS,
            REMINDER_BUILD_WATCHDOG_SELECTORS, RESTORE_HISTORY_SELECTORS, REPLACEMENT_UNION_SELECTORS, ERASE_RECOVERY_SELECTORS,
            *(members for _, members in ERASE_DIAGNOSTIC_PARTITIONS)),
            "build watchdog exact approved methods")


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
        isinstance(groups, list) and len(groups) == 56
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
        clone_members = tuple(default["unitTestSelectors"][716:723])
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
        retirement_members = tuple(default["unitTestSelectors"][723:731])
        require(retirement_members == CLONE_RETIREMENT_SELECTORS
                and len(retirement_members) == len(set(retirement_members)) == 8,
                "clone retirement exact ordered source enrollment")
        retirement_ids = tuple(item[0] for item in CLONE_RETIREMENT_METHOD_PARTITIONS)
        require(len(retirement_ids) == len(set(retirement_ids)) == 8
                and not (set(retirement_ids) & (set(resolved) | {DEFAULT_SELECTION_ID}))
                and not (set(retirement_members) & set(default["unitTestSelectors"][:723])),
                "clone retirement fixed distinct partitions")
        for partition_id, members in CLONE_RETIREMENT_METHOD_PARTITIONS:
            require(len(members) == 1 and members[0] in retirement_members,
                    "clone retirement singleton source partition")
            derived = dict(default)
            derived["unitTestSelectors"] = list(members)
            validate_selection(derived)
            resolved[partition_id] = derived
        parent_members = tuple(default["unitTestSelectors"][731:738])
        require(parent_members == PARENT_FINALIZATION_SELECTORS
                and len(parent_members) == len(set(parent_members)) == 7,
                "parent finalization exact ordered source enrollment")
        parent_ids = tuple(item[0] for item in PARENT_FINALIZATION_METHOD_PARTITIONS)
        require(len(parent_ids) == len(set(parent_ids)) == 7
                and not (set(parent_ids) & (set(resolved) | {DEFAULT_SELECTION_ID}))
                and not (set(parent_members) & set(default["unitTestSelectors"][:731])),
                "parent finalization fixed distinct partitions")
        for partition_id, members in PARENT_FINALIZATION_METHOD_PARTITIONS:
            require(len(members) == 1 and members[0] in parent_members,
                    "parent finalization singleton source partition")
            derived = dict(default)
            derived["unitTestSelectors"] = list(members)
            validate_selection(derived)
            resolved[partition_id] = derived
    if generated_profile_shape:
        legacy_members = tuple(item for item in default["unitTestSelectors"][738:]
                               if selection_class(item) == "V9_30FieldDraftResilienceTests")
        require(legacy_members == (DESTINATION_LEGACY_SELECTOR,),
                "destination legacy exact source enrollment")
        require(DESTINATION_LEGACY_SELECTION_ID not in resolved,
                "destination legacy distinct selector")
        derived = dict(default)
        derived["unitTestSelectors"] = list(legacy_members)
        validate_selection(derived)
        resolved[DESTINATION_LEGACY_SELECTION_ID] = derived
        require(BUILD_WATCHDOG_SELECTION_ID not in resolved, "build watchdog distinct selector")
        diagnostic = dict(resolved[PARENT_FINALIZATION_METHOD_PARTITIONS[0][0]])
        diagnostic.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(diagnostic)
        resolved[BUILD_WATCHDOG_SELECTION_ID] = diagnostic
        require(BUILD_ORDER_SELECTION_ID not in resolved, "build order distinct selector")
        resolved[BUILD_ORDER_SELECTION_ID] = dict(resolved["c36-destination-discard"])
        if "c36-restore-review" in resolved:
            require(NO_INDEX_SELECTION_ID not in resolved, "no-index distinct selector")
            resolved[NO_INDEX_SELECTION_ID] = dict(resolved["c36-restore-review"])
            require(RESTORE_BUILD_WATCHDOG_SELECTION_ID not in resolved,
                    "restore build watchdog distinct selector")
            diagnostic = dict(resolved["c36-restore-review"])
            diagnostic.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
            validate_selection(diagnostic)
            resolved[RESTORE_BUILD_WATCHDOG_SELECTION_ID] = diagnostic
    if any(group in resolved for group in REMINDER_BUILD_WATCHDOG_GROUPS):
        require(all(group in resolved for group in REMINDER_BUILD_WATCHDOG_GROUPS),
                "reminder build watchdog complete source groups")
        members = tuple(method for group in REMINDER_BUILD_WATCHDOG_GROUPS
                        for method in resolved[group]["unitTestSelectors"])
        require(len(members) == len(set(members)) == 33
                and members == REMINDER_BUILD_WATCHDOG_SELECTORS,
                "reminder build watchdog exact ordered disjoint union")
        require(REMINDER_BUILD_WATCHDOG_SELECTION_ID not in resolved,
                "reminder build watchdog distinct selector")
        diagnostic = dict(default)
        diagnostic.update(unitTestSelectors=list(members), tier="D30",
                          **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(diagnostic)
        resolved[REMINDER_BUILD_WATCHDOG_SELECTION_ID] = diagnostic
    if "replacement-packet-union" in resolved:
        require(all(group in resolved for group in RESTORE_HISTORY_GROUPS),
                "restore history complete groups")
        require(resolved["replacement-packet-union"]["unitTestSelectors"].count(
                    RESTORE_HISTORY_PACKET_SELECTOR) == 1,
                "restore history enrolled packet method")
        members = tuple(method for group in RESTORE_HISTORY_GROUPS
                        for method in (resolved[group]["unitTestSelectors"]
                                       if group != "replacement-packet-union"
                                       else [RESTORE_HISTORY_PACKET_SELECTOR]))
        require(len(members) == len(set(members)) == 7
                and members == RESTORE_HISTORY_SELECTORS,
                "restore history exact ordered disjoint union")
        require(RESTORE_HISTORY_SELECTION_ID not in resolved,
                "restore history distinct selection")
        diagnostic = dict(default, unitTestSelectors=list(members))
        diagnostic.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(diagnostic)
        resolved[RESTORE_HISTORY_SELECTION_ID] = diagnostic
        # This closed diagnostic adds no method or profile. Older manifests retain
        # their original available routes and cannot claim the current family.
        if len(default["unitTestSelectors"]) == 895 and len(selection_map["groups"]) == 56:
            require(tuple(resolved["replacement-packet-union"]["unitTestSelectors"])
                    == REPLACEMENT_UNION_SELECTORS
                    and len(set(REPLACEMENT_UNION_SELECTORS)) == 12,
                    "replacement union exact ordered complete family")
            require(REPLACEMENT_UNION_SELECTION_ID not in resolved,
                    "replacement union distinct selection")
            replacement = dict(default, unitTestSelectors=list(REPLACEMENT_UNION_SELECTORS))
            replacement.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
            validate_selection(replacement)
            resolved[REPLACEMENT_UNION_SELECTION_ID] = replacement
    if "erase-lease-lifecycle" in resolved:
        require(tuple(resolved["erase-lease-lifecycle"]["unitTestSelectors"]) == ERASE_LEASE_SELECTORS,
                "erase exact enrolled lifecycle methods")
        require(len(ERASE_RECOVERY_SELECTORS) == len(set(ERASE_RECOVERY_SELECTORS)) == 13
                and set(ERASE_RECOVERY_SELECTORS) <= defaults,
                "erase exact closed recovery question")
        require(ERASE_RECOVERY_SELECTION_ID not in resolved, "erase distinct selection")
        diagnostic = dict(default, unitTestSelectors=list(ERASE_RECOVERY_SELECTORS))
        validate_selection(diagnostic)
        resolved[ERASE_RECOVERY_SELECTION_ID] = diagnostic
        require(ERASE_BUILD_WATCHDOG_SELECTION_ID not in resolved, "erase build watchdog distinct selection")
        development = dict(diagnostic, tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(development)
        resolved[ERASE_BUILD_WATCHDOG_SELECTION_ID] = development
        for partition_id, partition_members in ERASE_DIAGNOSTIC_PARTITIONS:
            require(partition_id not in resolved, "erase partition distinct selection")
            partition = dict(development, unitTestSelectors=list(partition_members))
            validate_selection(partition)
            resolved[partition_id] = partition
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
    expected_partitions = {"schemaVersion": 1, "families": [{
        "parentID": ERASE_RECOVERY_SELECTION_ID,
        "parentSelectors": list(ERASE_RECOVERY_SELECTORS),
        "partitions": [{"id": key, "selectors": list(members)}
                       for key, members in ERASE_DIAGNOSTIC_PARTITIONS],
    }]}
    require(manifest.get("diagnosticPartitions") == expected_partitions,
            "erase diagnostic manifest exact closed partition binding")
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
    watchdog_routes = {
        REPLACEMENT_UNION_SELECTION_ID: (REPLACEMENT_UNION_PARENT, REPLACEMENT_UNION_SELECTORS),
        BUILD_WATCHDOG_SELECTION_ID: (BUILD_WATCHDOG_PARENT, PARENT_FINALIZATION_METHOD_PARTITIONS[0][1]),
        RESTORE_BUILD_WATCHDOG_SELECTION_ID: (RESTORE_BUILD_WATCHDOG_PARENT, RESTORE_BUILD_WATCHDOG_SELECTORS),
        REMINDER_BUILD_WATCHDOG_SELECTION_ID: (REMINDER_BUILD_WATCHDOG_PARENT, REMINDER_BUILD_WATCHDOG_SELECTORS),
        RESTORE_HISTORY_SELECTION_ID: (RESTORE_HISTORY_PARENT, RESTORE_HISTORY_SELECTORS),
        ERASE_BUILD_WATCHDOG_SELECTION_ID: (ERASE_BUILD_WATCHDOG_PARENT, ERASE_RECOVERY_SELECTORS),
        **{key: (ERASE_PARTITION_PARENT, members)
           for key, members in ERASE_DIAGNOSTIC_PARTITIONS},
    }
    if selection["tier"] == "D30" or selection_record["selectionID"] in watchdog_routes:
        require(selection["tier"] == "D30"
                and selection_record["selectionID"] in watchdog_routes,
                "build watchdog selector/tier binding")
        approved_parent, approved_methods = watchdog_routes[selection_record["selectionID"]]
        require(tuple(selection["unitTestSelectors"]) == approved_methods,
                "build watchdog selector/method binding")
        require(provider == "github" and label == "macos-26", "build watchdog GitHub route only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "build watchdog original attempt only")
        header = subprocess.check_output(["git", "cat-file", "commit", checkout_head], cwd=root)
        parents = [line[7:].decode("ascii") for line in header.split(b"\n\n", 1)[0].splitlines()
                   if line.startswith(b"parent ")]
        require(parents == [approved_parent], "build watchdog exact approved parent")
    if selection_record["selectionID"] == BUILD_ORDER_SELECTION_ID:
        require(selection["tier"] == "N8" and provider == "github" and label == "macos-26",
                "build order ordinary-budget GitHub route only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "build order original attempt only")
        header = subprocess.check_output(["git", "cat-file", "commit", checkout_head], cwd=root)
        parents = [line[7:].decode("ascii") for line in header.split(b"\n\n", 1)[0].splitlines()
                   if line.startswith(b"parent ")]
        require(parents == [BUILD_ORDER_PARENT], "build order exact parent")
        for path, expected_tree in BUILD_ORDER_TREES.items():
            tree = subprocess.check_output(["git", "rev-parse", checkout_head + ":" + path],
                                           cwd=root, text=True).strip()
            require(tree == expected_tree, "build order unchanged app/tests/project")
    if selection_record["selectionID"] in NO_INDEX_ROUTES:
        approved_parent, approved_tier = NO_INDEX_ROUTES[selection_record["selectionID"]]
        require(selection["tier"] == approved_tier and provider == "github" and label == "macos-26",
                "no-index exact-budget GitHub route only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "no-index original attempt only")
        header = subprocess.check_output(["git", "cat-file", "commit", checkout_head], cwd=root)
        parents = [line[7:].decode("ascii") for line in header.split(b"\n\n", 1)[0].splitlines()
                   if line.startswith(b"parent ")]
        require(parents == [approved_parent], "no-index exact parent")
        for path, expected_tree in no_index_source_trees(selection_record["selectionID"]).items():
            tree = subprocess.check_output(["git", "rev-parse", checkout_head + ":" + path],
                                           cwd=root, text=True).strip()
            require(tree == expected_tree, "no-index unchanged app/tests/project")
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
            require(current_bundle == bundle, "native case ownership")
            # Xcode attaches runtime warnings to otherwise completed cases. Keep
            # their original result evidence; annotations are not executions.
            for child in children:
                require(isinstance(child, dict)
                        and set(child) == {"nodeType", "name"}
                        and child["nodeType"] == "Runtime Warning"
                        and isinstance(child["name"], str) and bool(child["name"].strip()),
                        "native case warning annotation")
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


def build_order_device_state(raw, selected_udid):
    require(isinstance(raw, bytes) and len(raw) <= 2 * 1024 * 1024, "bounded device observation")
    value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_pairs)
    require(isinstance(value, dict) and isinstance(value.get("devices"), dict), "device inventory")
    devices = []
    for runtime, members in value["devices"].items():
        require(isinstance(runtime, str) and isinstance(members, list), "runtime devices")
        for member in members:
            require(isinstance(member, dict), "device object")
            udid, state = member.get("udid"), member.get("state")
            require(isinstance(udid, str) and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", udid)
                    and isinstance(state, str) and 0 < len(state) <= 80, "device identity/state")
            devices.append({"runtime": runtime, "udid": udid.upper(), "state": state,
                            "available": member.get("isAvailable") is True})
            require(len(devices) <= 256, "device observation count")
    require(len({item["udid"] for item in devices}) == len(devices), "duplicate device identity")
    selected = [item for item in devices if item["udid"] == selected_udid.upper()]
    require(len(selected) == 1 and selected[0]["available"], "selected available device")
    return {"selectedState": selected[0]["state"],
            "devices": sorted(devices, key=lambda item: (item["runtime"], item["udid"]))}


def observe_build_before_boot(root, artifact, record, environment):
    """Run the unchanged build under the incumbent outer watchdog; never boot.

    The child and simctl samples inherit that watchdog's process group. A timeout
    retains the append-only prefix, which cannot pass completed-evidence checks.
    No signal handler or new session can detach build descendants from the owner.
    """
    require(record["selectionID"] == BUILD_ORDER_SELECTION_ID, "build order command admission")
    require(read_json(artifact / "native-admission.json") == record, "build order admission changed")
    require(environment.get("CI_BUILD_TIMEOUT_SECONDS") == "1200", "build order unchanged watchdog")
    udid = environment.get("CI_SIMULATOR_UDID", "")
    require(re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", udid)
            and udid == environment.get("CI_NATIVE_CREATED_SIMULATOR_UDID")
            and environment.get("CI_SIMULATOR_INITIAL_STATE") == "Shutdown",
            "build order exact fresh selected device")
    output = artifact / BUILD_ORDER_OBSERVATIONS
    require(not output.exists() and not output.is_symlink(), "build order evidence already exists")
    started = time.monotonic()
    with output.open("xb") as stream:
        def append(value):
            value["elapsedSeconds"] = round(time.monotonic() - started, 6)
            stream.write(canonical(value))
            stream.flush()
            os.fsync(stream.fileno())

        def sample(phase):
            try:
                result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                                        cwd=root, capture_output=True, timeout=5, check=True)
                value = {"kind": "sample", "phase": phase, "status": "OBSERVED",
                         **build_order_device_state(result.stdout, udid)}
            except (OSError, subprocess.SubprocessError, UnicodeError, ValueError, TypeError) as error:
                value = {"kind": "sample", "phase": phase, "status": "UNAVAILABLE",
                         "errorType": type(error).__name__}
            append(value)
            return value

        append({"kind": "header", "schemaVersion": 1, "admissionSHA256": sha256(canonical(record)),
                "selectedUDID": udid, "command": list(BUILD_ORDER_COMMAND), "watchdogSeconds": 1200})
        before = sample("before")
        require(before.get("selectedState") == "Shutdown", "build order requires observed shutdown before build")
        child = subprocess.Popen(list(BUILD_ORDER_COMMAND), cwd=root)
        append({"kind": "started", "processID": child.pid})
        samples = 0
        while True:
            try:
                code = child.wait(timeout=60)
                break
            except subprocess.TimeoutExpired:
                # The existing 1200s watchdog bounds the process. This additional
                # cap bounds observer work even if its caller is misconfigured.
                if samples < 24:
                    sample("during")
                    samples += 1
        sample("after")
        append({"kind": "completed", "returnCode": code})
    return code if code >= 0 else 128 - code


def build_order_observations(artifact, record, selected_udid):
    path = artifact / BUILD_ORDER_OBSERVATIONS
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4 * 1024 * 1024,
            "bounded build order evidence")
    raw = path.read_bytes()
    require(raw.endswith(b"\n"), "complete build order observation line")
    events = [json.loads(line, object_pairs_hook=unique_pairs) for line in raw.splitlines()]
    require(5 <= len(events) <= 29 and all(isinstance(event, dict) for event in events),
            "build order event count")
    times = [event.get("elapsedSeconds") for event in events]
    require(all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in times)
            and times == sorted(times) and times[-1] <= 1200, "build order event timing")
    header = dict(events[0]); header.pop("elapsedSeconds")
    require(header == {"kind": "header", "schemaVersion": 1,
                       "admissionSHA256": sha256(canonical(record)), "selectedUDID": selected_udid,
                       "command": list(BUILD_ORDER_COMMAND), "watchdogSeconds": 1200},
            "build order source/command binding")
    require(events[2].get("kind") == "started" and type(events[2].get("processID")) is int
            and events[2]["processID"] > 0, "build order child start")
    require(events[-1].get("kind") == "completed" and type(events[-1].get("returnCode")) is int
            and events[-1]["returnCode"] == 0,
            "successful build order completion")
    samples = [events[1], *events[3:-1]]
    require([item.get("phase") for item in samples] == ["before"] + ["during"] * (len(samples) - 2) + ["after"]
            and all(item.get("kind") == "sample" for item in samples), "build order sample sequence")
    observed_states = []
    for item in samples:
        require(item.get("status") in ("OBSERVED", "UNAVAILABLE"), "build order sample status")
        if item["status"] == "OBSERVED":
            devices = item.get("devices")
            require(isinstance(devices, list) and 0 < len(devices) <= 256, "retained device inventory")
            canonical_devices = {}
            for device in devices:
                require(isinstance(device, dict) and set(device) == {"runtime", "udid", "state", "available"}
                        and type(device["available"]) is bool, "retained device fields")
                canonical_devices.setdefault(device["runtime"], []).append(
                    {"udid": device["udid"], "state": device["state"], "isAvailable": device["available"]})
            parsed = build_order_device_state(canonical({"devices": canonical_devices}), selected_udid)
            require(parsed == {"devices": devices, "selectedState": item.get("selectedState")},
                    "retained device state binding")
            observed_states.append(item["selectedState"])
        else:
            require(isinstance(item.get("errorType"), str) and "selectedState" not in item
                    and "devices" not in item, "unavailable observation is not a state")
    require(samples[0].get("selectedState") == "Shutdown", "observed initial shutdown")
    complete = all(item["status"] == "OBSERVED" for item in samples)
    return {"path": BUILD_ORDER_OBSERVATIONS, "sha256": sha256(raw), "sampleCount": len(samples),
            "observationStatus": "COMPLETE" if complete else "INCONCLUSIVE",
            "selectedSimulatorObservedShutdownThroughout": complete and all(state == "Shutdown" for state in observed_states),
            "observedSelectedStates": observed_states, "elapsedSeconds": times[-1],
            "samplingIntervalSeconds": 60, "continuousStateProof": False,
            "acceptance": False, "performanceImprovementProven": False}


def no_index_build_receipt(root, artifact, record, environment):
    require(record["selectionID"] in NO_INDEX_ROUTES, "no-index admitted selection")
    require(read_json(artifact / "native-admission.json") == record, "no-index admission changed")
    e = environment
    require(e.get("PROJECT_PATH") == "FieldEvidenceApp.xcodeproj"
            and e.get("SCHEME") == "FieldEvidenceApp" and e.get("CONFIGURATION") == "Debug"
            and e.get("CODE_SIGNING_ALLOWED") == "NO", "no-index build configuration")
    destination = "platform=iOS Simulator,id=" + e["CI_SIMULATOR_UDID"]
    require(e.get("CI_DESTINATION") == destination, "no-index exact destination")
    require(e.get("CI_ARTIFACT_DIR") == str(artifact), "no-index artifact path")
    arguments = ["xcodebuild", "-project", e["PROJECT_PATH"], "-scheme", e["SCHEME"],
                 "-configuration", e["CONFIGURATION"], "-destination", destination,
                 "-derivedDataPath", str(Path(e["RUNNER_TEMP"]) / "FieldEvidenceDerivedData"),
                 "-resultBundlePath", str(artifact / "Build.xcresult"),
                 "CODE_SIGNING_ALLOWED=NO", "COMPILER_INDEX_STORE_ENABLE=NO", "build-for-testing"]
    return {"schemaVersion": 1, "selectionID": record["selectionID"],
            "head": record["head"], "parent": NO_INDEX_ROUTES[record["selectionID"]][0], "runID": record["runID"],
            "runAttempt": record["runAttempt"], "admissionSHA256": sha256(canonical(record)),
            "buildScriptSHA256": sha256((root / "Scripts/build-smoke.sh").read_bytes()),
            "sourceTrees": no_index_source_trees(record["selectionID"]), "argv": arguments,
            "diagnosticOnly": True, "acceptance": False}


def verify_no_index_build(root, artifact, record, environment):
    expected = no_index_build_receipt(root, artifact, record, environment)
    require(read_json(artifact / NO_INDEX_RECEIPT) == expected, "no-index command receipt changed")
    path = artifact / "build-smoke.log"
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 256 * 1024 * 1024,
            "no-index original build log")
    lines = path.read_text(encoding="utf-8").splitlines()
    markers = [i for i, line in enumerate(lines) if line.strip() == "Command line invocation:"]
    require(len(markers) == 1 and markers[0] + 1 < len(lines), "no-index single Xcode invocation")
    actual = shlex.split(lines[markers[0] + 1].strip())
    require(actual and actual[0] == "/Applications/Xcode_26.6.app/Contents/Developer/usr/bin/xcodebuild"
            and actual[1:] == expected["argv"][1:], "no-index executed command differs")
    compiler_lines = [line for line in lines if "builtin-SwiftDriver -- " in line]
    require(compiler_lines and all("-index-store-path" not in line for line in compiler_lines),
            "no-index compiler still emits index data or command missing")
    require(any(line.strip() == "** TEST BUILD SUCCEEDED **" for line in lines),
            "no-index complete test build required")
    return {"commandReceiptSHA256": sha256(canonical(expected)),
            "executedCommandExact": True, "compilerDriverCommands": len(compiler_lines),
            "compilerIndexEmissionDisabled": True, "unchangedSourceTrees": no_index_source_trees(record["selectionID"]),
            "speedupEstablished": False, "acceptance": False}


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
    build_order = {}
    if record["selectionID"] in NO_INDEX_ROUTES:
        build_order["noIndexBuildDiagnostic"] = verify_no_index_build(root, artifact, record, environment)
    if record["selectionID"] == BUILD_ORDER_SELECTION_ID:
        build_order["buildOrderDiagnostic"] = build_order_observations(artifact, record, simulator["udid"])
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
    return {**record, **build_order, "recordType": "validated-native-checkpoint", "executedUnitMethods": units,
            "executedUIMethods": ui, "simulator": simulator, "provider": provider, "sdk": sdk,
            "simulatorFileProtectionDiagnostics": diagnostic_evidence,
            "wholeAppAcceptance": False, "humanReviewComplete": False,
            "diagnosticOnly": True, "providerQualification": False,
            "acceptance": False, "releaseReady": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("admit", "verify", "select", "collect-diagnostics", "observe-build-before-boot", "record-no-index-build"))
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
    if args.command in ("observe-build-before-boot", "record-no-index-build"):
        require(record is not None, "diagnostic command requires admitted integration route")
    if record is None:
        return
    subprocess.run(["git", "diff", "--exit-code", "HEAD", "--"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    record.update(source_binding(root))
    record["gitTree"] = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    artifact = Path(os.environ["CI_ARTIFACT_DIR"])
    require(artifact.is_dir() and not artifact.is_symlink(), "artifact directory")
    if args.command == "observe-build-before-boot":
        raise SystemExit(observe_build_before_boot(root, artifact, record, os.environ))
    if args.command == "record-no-index-build":
        receipt = no_index_build_receipt(root, artifact, record, os.environ)
        with (artifact / NO_INDEX_RECEIPT).open("xb") as stream:
            stream.write(canonical(receipt))
        return
    name = "native-admission.json"
    if args.command == "verify":
        record = verify_checkpoint(root, artifact, record, selection, os.environ)
        name = "native-checkpoint.json"
    with (artifact / name).open("xb") as stream:
        stream.write(canonical(record))


if __name__ == "__main__":
    main()
