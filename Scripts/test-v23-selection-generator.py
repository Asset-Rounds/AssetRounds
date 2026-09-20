#!/usr/bin/env python3

EXPECTED_RESTORE_REVIEW_SELECTORS = ['FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkCreatesReviewReceiptAndSecondHopSurvivesOriginalPackageRemoval', 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPopulatedCrossWorkspaceReplacementCreatesOnlyReviewAndRetainsOriginalHistory', 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes', 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPrepublicationInterruptionReconcilesToUnchangedPopulatedGeneration', 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkKeepsTerminalHistoryAndUnrelatedDraftOwners', 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testReviewPlanRejectsMissingOrChangedOwnedRowsWithoutConsumingUnrelatedDrafts', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testWrongContextIdentityAndGenerationHaveNoEffects', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testChangedBindingDeniesAdmissionAndCommitWithoutEffects', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testChangedCommandAndEnvelopeAreDeniedBeforeEffects', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testChangedCommandOrEnvelopeCannotCommitAfterExactAdmission', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testGenericWriterCommandReachesAdmissionAndIsDeniedWithoutEffects', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testRecoveryBodyNeverRunsAndHasNoEffects', 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests/testSynchronousRevocationDeniesReadAdmissionAndPreviouslyAdmittedCommit']

EXPECTED_REMINDER_PRODUCTION_SELECTORS = ['FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C37TypedPoseContractAnchor', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C29TypedPlanContractAnchor', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C28TypedScheduleBoundaryIsClosedAndNonpersistent', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C34PackageDestinationRegistrationRemainsNonAutomatic', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testAbortedEraseAdmissionRestoresFreshDisabledAccessAndPreservesOriginalOwners', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testAbortedEraseAdmissionPreservesEnabledConfigurationAndRequiresFreshUnlock', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testAbortedEraseAdmissionRejectsConfigurationABAAndCannotReleaseDurableIntent', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testFullEraseReservationSurvivesBackgroundAndRejectsConfigurationBypasses', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testCompletedErasePreservesProtectedDataAndRequiresFreshActiveStartup', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testCompletedEraseRetainsReceiptUntilFreshSettingsAndAllNotificationLeavesAreEmpty', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testCompletedEraseRejectsOriginalAuthorizationABAAndReceiptReplayAfterConfigurationCycle', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testFullEraseAdmissionExcludesConfigurationWhileAdoptionAllowsBackgroundEvents', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testContentReadReferenceBlocksRevocationAndRejectsRevokedEpochABA', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testRuntimeProtectedDataLossRevokesDisabledAndEnabledCapabilitiesUntilVerifiedRecovery', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testRuntimeProtectedDataLossCancelsPendingAuthenticationAndRejectsUnverifiedRecovery', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testConcreteAppLockSettingReadRequiresFreshProtectedDataAvailability', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testProtectedDataRecoveryGenerationRejectsNewLossDuringRecovery', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testConfigurationAuthenticationSettlesBothCallbackAndActiveOrderings', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testConfigurationAuthenticationPendingActiveIsPreemptedByRevocation', 'FieldEvidenceAppTests/V9_15AppLockLifecycleTests/testRecoveryCompletionRejectsPendingConfigurationAttemptWithoutStrandingCancellation', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedDetailedPolicyUsesAuthenticatedKindsAndReplacesChangedPayloads', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testAppLockEnableProjectsGenericAndDisableUsesCurrentDetailedConsent', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredDetailedRequestIsRemovedOnPrivacyDowngradeWithoutReadding', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredUnobservedGenericReminderStillFailsWithoutEffects', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testPermissionDenialStillRemovesForbiddenDetailWithoutClaimingDelivery', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedReconciliationCannotRenewRevokedOriginalProof', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testNotificationCopySourcesBindExactReleaseAndEffectiveBasis', 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testGenericPolicyRejectsDetailedDurableMappingWithoutSystemEffects', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testUnboundAndRetiredOwnersCannotMintOrRebind', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testDisabledForegroundEditAndFreshAuthorityReplayPreserveExactBytes', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testEnabledPolicyRequiresUnlockAndOldCommandCannotSurviveRelock', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testCommandsCannotTransferAcrossAdaptersOrGateIssuers', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testReplacementOwnerAcceptsOnlyFreshCommandsAndRetirementIsMonotonic', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testProtectedDataAndConfigurationTransitionsRevokeHeldEditsWithoutEffects', 'FieldEvidenceAppTests/V23ReminderPolicyEditTests/testActualPreferenceWriteSerializesWithRevocationAndRetirement', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionReconciliationRetryKeepsSavedRevisionAndNeverPrompts', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionSettingsReadDoesNotPromptAndDeniedEnablePersistsExplicitChoice', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionDetailChoiceWhileDisabledDoesNotPromptAndRejectsStaleEdit', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionAppLockRequiresUnlockAndOldSettingsPublicationStaysRevoked', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionPermissionReplyAfterBackgroundCannotSaveConsent', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReadNeverPromptsAndExplicitRequestNeverWritesConsent', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testInactiveDisabledAndLockedEnabledStatesCannotPrompt', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testRevocationDuringAuthorizationReadPreventsPrompt', 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReplyAfterRevocationCannotRenewForegroundOrConsent', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testGenericEncodingAndReadbackRetainExactLegacyShape', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testBothKindsUseApprovedCopyAndTokenOnlySystemPayload', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenZoneAndEffectiveInstantDistinguishDSTFold', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testDetailedReadbackRejectsUnapprovedCopyAndAncillaryFields', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testNumericZoneFallbackUsesExplicitOffsetWithoutDeviceDefaults', 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenOffsetCopyDoesNotResolveCurrentTimeZoneRules', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testIncompleteEnableAndDisableRemainAvailableForAuthenticatedRecovery', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testEnabledAndCompletedDisabledEditsReopenWithoutReplayingPolicyOrOSEffects', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testSecondEditRollsContinuationAndRejectsOldOperationAndAuthenticationSubject', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPreferenceAndPendingPublicationRecoverMetadataExactlyOnce', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPolicyEditRejectsOldSubjectBeforeNewToggleSourceOrOSEffects', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testDivergentPendingBlocksSettlementAndSecondPolicyWriteWithoutDiscardingEvidence', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testUnstampedResetEraseAndChangedStampCannotRepairControl', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testForeignPreferencesControlBindingAndChangedSettingDenyBeforePolicyWrite', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testMissingDisabledControlWithStampOrPendingIsNotReady', 'FieldEvidenceAppTests/V23ReminderControlContinuationTests/testNilContinuationPreservesLegacyCanonicalControlAndSubjectBytes', 'FieldEvidenceAppTests/S6_3BackupValidationTests/testImportPreservesSupportedSchemaPairsAndRejectsForeignPairs', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testRoundArchiveStagingPreservesVersionAndAuthorityBoundaries', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testEmptyStockProjectionPreservesUnrelatedOriginalHistories', 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests/testEmptyStockRowsCannotHideOwnedCommandHistory', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testRoundAppendUsesDestinationPrefixAndPreservesEveryOriginal', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testRoundBindingsAndSourceHistoryMustMatchExactly', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testRoundAppendPreservesIncumbentQuarantineAndForeignFrontier', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testEarlierTargetRoundCannotBeHiddenByLastReceiptFrontier', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testRoundMetadataIsRetainedAndUnresolvedCausationIsDenied', 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests/testRoundReversalClosureCannotBorrowArchivedStockPlanException']
EXPECTED_REMINDER_PRODUCTION_GROUPS = [{'classes': ['V23ReminderPolicyEditTests'], 'id': 'reminder-policy-edit', 'methodCount': 7}, {'classes': ['V23ReminderProductionSettingsTests'], 'id': 'reminder-production-settings', 'methodCount': 10}, {'classes': ['V23DetailedReminderDeliveryTests'], 'id': 'reminder-detailed-delivery', 'methodCount': 6}, {'classes': ['V23ReminderControlContinuationTests'], 'id': 'reminder-control-continuation', 'methodCount': 10}, {'classes': ['V23RoundRestoreHistoryTests'], 'id': 'round-restore-history', 'methodCount': 6}]
HISTORICAL_PROFILE_PINS = {'incumbent-v1': {'selectionSHA256': '91E6F41D81E982D116611FF4A96219FE3631020B5CB264F76A8BDA1E4E27408E', 'mapSHA256': 'CD41DF01E106199B7CAE86CEDEB4BAA93F812C76D7B510BA6DC941DFCDDF7129'}, 'prospective-v1': {'selectionSHA256': '203335CCCC8FACDC8560C1F23BA28A762854664264884CBFAFB8A0F0EDF42F6E', 'mapSHA256': '6D74CFA1BA6EBC0B46ED0656F285F8BD59DA61D62CB60E02C2B37B2978973EBD'}, 'raw-photo-v1': {'selectionSHA256': '62673E1257EE72462439FA8770F3D3CFB50ED2FB06F0674C7C9E8D5FE2FDBEBB', 'mapSHA256': '77E605D5BE168687CC9EB81C4F695806C6A6E2FCD619411C64AA7E251676CEAC'}, 'pair-startup-v1': {'selectionSHA256': '62F78130A529F9BDAE378F9A9A152E32E178CC5F132BEC1FDEF37D2CAAAAE722', 'mapSHA256': '70D3F3C4C034D82397564BA554425A2FFB93E51A345B1075CBD72F82610FF110'}, 'photo-backup-v1': {'selectionSHA256': '930A9B3C186EDD0D09F9F630A9214A0FDD95362465B8FEFFBC735D78CF83AA5D', 'mapSHA256': '5BB4E7E1FA935EE74B962F4572F9384FBF5DC4E0BFA83178547D89E0A4287248'}, 'configuration-clone-v1': {'selectionSHA256': 'C5BFBCF739DCD2BCAF77801385CD1A16C116D6AFE07F1AD02162F0AEF9030AA0', 'mapSHA256': '955D579A27A62C179660C0F8A4A38FF4D91FB9241244BA3B0334A9AF1B0C7A6E'}, 'clone-retirement-v1': {'selectionSHA256': '42337B38E49081DA1D0F9265235B3787DE105C6E695123A6F2CEB560779E2878', 'mapSHA256': '1891580B81536B16989FDB4976A4288FB548A18DA0280C5D7345A22AD2DD5E85'}, 'parent-finalization-v1': {'selectionSHA256': '1F2C99A95F04D378A6FB6FB0656FC0A9A6DC6A42D711E3FDD55996F86D25D572', 'mapSHA256': 'E1128081C187ABE0B9E2B69CA3998EA79EA71B4124A8BBD14942418F066F3A4E'}, 'destination-review-v1': {'selectionSHA256': '575C83D0CAC78A35C9BB240193B5AC345425175762A73C7604A2EE5AABB04A1F', 'mapSHA256': '86AC237B0F2A650CCB3B083DD8C8DA50F7176D76C0B9F15816EBD27FD79E5411'}, 'production-destination-v1': {'selectionSHA256': 'C82EBC63F02BA3B0A6957A09859C41B4686340402C6D8113A6A45040FFFBEDB5', 'mapSHA256': '732FBF8DC385F248761064F8073AD44C9F057A00CEE02140E0285874896C5F76'}, 'restore-review-v1': {'selectionSHA256': '658B54FBAA5E5907778892FD8F6B07BA5DEE82E5542580AC20723DC711E33584', 'mapSHA256': '143C205A5011FDBF1688CDF885B047070F192471AEDC5BF5B06FBFC20517DB98'}}

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True


HERE = Path(__file__).resolve().parent
REPO = HERE.parent
GENERATOR = HERE / "v23-selection-generator.py"
MANIFEST = HERE / "v23-selection-manifest.json"
HISTORICAL_COMMIT = "67ccbaba65330d4d60fb1aab21cf6cc244c2b257"
SOURCE_COMMIT = "f58be9de74a5e8ec8b74007e726376cae9f57c2b"
SELECTION_SHA = "91E6F41D81E982D116611FF4A96219FE3631020B5CB264F76A8BDA1E4E27408E"
MAP_SHA = "CD41DF01E106199B7CAE86CEDEB4BAA93F812C76D7B510BA6DC941DFCDDF7129"
NEW_SELECTOR = ("FieldEvidenceAppTests/V23MutationReceiptSafetyTests/"
                "testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority")
STARTUP_SELECTORS = [
    "FieldEvidenceAppTests/V9_15AppLockLifecycleTests/"
    "testConfigurationStartupRecoveryTokenBindsRepairOperationAndRevokes",
    "FieldEvidenceAppTests/V9_15AppLockLifecycleTests/"
    "testConfigurationStartupRecoveryTokenRejectsOperationMintABA",
    "FieldEvidenceAppTests/S3_4ResumeRecoveryTests/"
    "testMediaReconcileRemovesOrphansAndPreservesMismatchForMaintenance",
    "FieldEvidenceAppTests/S3_4ResumeRecoveryTests/"
    "testRelaunchAfterWideKeepsExactEvidenceAuthorityAndResumesClose",
]

CONFIGURATION_CLONE_SELECTORS = ['FieldEvidenceAppTests/S6_2BackupExportTests/testConfigurationCloneAcceptsEveryAuthenticPhotoPhaseAndOmitsOperationalFamily', 'FieldEvidenceAppTests/S6_2BackupExportTests/testConfigurationCloneRejectsCorruptFinalMemberAndPopulatedDestinationStagingBeforeEffects', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneColdRecoveryRejectsNewStagingWithoutDeletingIt', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneEmptyRootsRecoverAcrossPublicationBoundaries', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneFrozenEvidenceValidationIsBoundedAndRejectsHostileFiles', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRechecksAccessCancellationAndRootAfterMediaCopy', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetainsIntentWhenStagingChangesDuringFinalColdCleanup']

PHOTO_BACKUP_SELECTORS = [
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
]

CLONE_RETIREMENT_SELECTORS = ['FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementOldPointerRollbackRestoresExactIncumbent', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementPointerLagAndPrivateCleanupResume', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementTerminalMetadataResumesWithoutBaseIntent', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementRollbackInterruptionsResume', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementUnclaimedScaffoldAndBindingTamperFailClosed', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementChangedPrivateBytesAndUnknownNodesRemainUntouched', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementAccessAndCancellationRetainRecoveryOwner', 'FieldEvidenceAppTests/S6_4AtomicRestoreTests/testConfigurationCloneRetirementClaimRejectsAnInodeSubstitution']

PARENT_FINALIZATION_SELECTORS = ['FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckVisibleIssueUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckCouldNotVerifyUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckResolvedUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckStillVisibleUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckDifferentIssueUsesOriginalFiveSagaHistory', 'FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationRecheckCouldNotVerifyUsesOriginalFiveSagaHistory']
HISTORICAL_PROFILE_HASHES = {'incumbent-v1': ['91E6F41D81E982D116611FF4A96219FE3631020B5CB264F76A8BDA1E4E27408E', 'CD41DF01E106199B7CAE86CEDEB4BAA93F812C76D7B510BA6DC941DFCDDF7129'], 'prospective-v1': ['203335CCCC8FACDC8560C1F23BA28A762854664264884CBFAFB8A0F0EDF42F6E', '6D74CFA1BA6EBC0B46ED0656F285F8BD59DA61D62CB60E02C2B37B2978973EBD'], 'raw-photo-v1': ['62673E1257EE72462439FA8770F3D3CFB50ED2FB06F0674C7C9E8D5FE2FDBEBB', '77E605D5BE168687CC9EB81C4F695806C6A6E2FCD619411C64AA7E251676CEAC'], 'pair-startup-v1': ['62F78130A529F9BDAE378F9A9A152E32E178CC5F132BEC1FDEF37D2CAAAAE722', '70D3F3C4C034D82397564BA554425A2FFB93E51A345B1075CBD72F82610FF110'], 'photo-backup-v1': ['930A9B3C186EDD0D09F9F630A9214A0FDD95362465B8FEFFBC735D78CF83AA5D', '5BB4E7E1FA935EE74B962F4572F9384FBF5DC4E0BFA83178547D89E0A4287248'], 'configuration-clone-v1': ['C5BFBCF739DCD2BCAF77801385CD1A16C116D6AFE07F1AD02162F0AEF9030AA0', '955D579A27A62C179660C0F8A4A38FF4D91FB9241244BA3B0334A9AF1B0C7A6E'], 'clone-retirement-v1': ['42337B38E49081DA1D0F9265235B3787DE105C6E695123A6F2CEB560779E2878', '1891580B81536B16989FDB4976A4288FB548A18DA0280C5D7345A22AD2DD5E85']}

spec = importlib.util.spec_from_file_location("v23_selection_generator", GENERATOR)
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def git_bytes(path, commit=HISTORICAL_COMMIT):
    return subprocess.check_output(["git", "show", commit + ":" + path], cwd=REPO)


DESTINATION_SELECTORS = [
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testIterativeLineageComposesFortyHopsAcrossRepeatedWorkspacesWithoutPayloadGrowth",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testLineageBindsLaterCheckpointPrefixAndRejectsBranchPayloadDriftAndUnreviewedActivation",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testLineageRejectsRehashedPredecessorClaimsAndCannotReuseValidationForDifferentHistory",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testForeignLiveLineageReadPreservesAllOriginalsAndDeniesDirtyAncestorQuarantineAndRetirement",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstCreateReceiptAuthenticatesRetainedSourceAndPreservesOriginalBytes",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testSelfConsistentCreateReceiptCannotAuthenticateChangedMappingOrGeneration",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testForeignLiveReviewReadDeniesTamperQuarantineDirtyAndRetiredReadersWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstReviewDerivesCompleteReplacementAndForkRelationsWithoutChangingOriginals",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testFirstReviewRetryUsesGenerationBoundFreshIdentities",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testRehashedPlausibleRelationsStillRequireExactSourceCoverage",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testClosedCodecRejectsUnknownTagsKeysNoncanonicalAndInitialStateSubstitutions",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testEachRetainedGraphGetsItsOwnReviewWithoutRevivingItsDisposition",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests/testPredecessorShapeIsClosedAndDoesNotAuthenticateAnAncestor",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testContinueUsesActualWriterReceiptAndPreservesRoundSourceAndReplay",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testRebaseRequiresAnAdvancedMappedRoundAndGrantsNoReadinessOrRoundEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testDiscardBindsAbsentAndArchivedTargetsWithoutLosingHistoryOrRevivingWork",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testClosedTargetContractRejectsUnboundClaimsAndWrongRoundDigestWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testPreparedProofRejectsContextCommandAndLateRoundChangesAndCannotBeReused",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testResolutionRechecksDirtyCorruptMissingQuarantinedAndRetiredSourceWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests/testReplacementThenForkRetainsOriginalNamespaceAndRequiresFreshReviewReceipt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testConfirmedTerminalUsesActualAtomicReceiptForAbsentAndArchivedTargetsAndExactReplay",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalRecoveryAfterReopenReadsStoredOriginalWithoutAllocatingAnotherAttempt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalRequiresExplicitPendingDiscardAndRejectsWrongPlanTimePayloadAndKnownIDs",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testPreparedTerminalProofIsSingleUseContextBoundAndRechecksCompetingWrites",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testOwnedContentAndUnboundStageWritesDenyDiscardBeforeAnyEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testTerminalAdmissionRejectsDirtyCorruptMissingQuarantinedAndRetiredHistoryWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests/testOriginalWriterInterruptionBoundariesRollbackOrRecoverExactlyOneTerminal",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testSeparateContinuationBindsActualResolutionAndPreservesOneSourceAcrossRereview",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testLegacyCommandBytesStayExactAndClosedBindingTamperingHasNoEffect",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testPreparedContinuationIsSingleUseContextBoundAndRechecksCurrentRoundAndReview",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testColdOriginalRecoverySurvivesArchivedRoundAndRejectsMissingSourceReceipt",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testDirtyCorruptQuarantinedAndPreemptedSourceStateDeniesWithoutEffects",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testRealWriterFaultBoundariesRollbackOrRecoverExactlyOneContinuation",
    "FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests/testProductionServiceRecoversBeforePreparationAndRejectsForeignOrRetiredOwners",
    "FieldEvidenceAppTests/V9_30FieldDraftResilienceTests/testReviewedTargetCarrierPreservesLegacyMyDayCanonicalResolutionBytes"
]
DESTINATION_GROUP_IDS = ['c36-destination-review', 'c36-destination-resolution', 'c36-destination-discard', 'c36-destination-continuation']

EXPECTED_SETTINGS_COMPATIBILITY_SELECTORS = ['FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C45CompatibilityKeepsOutputActivationExplicitAndBounded', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testV23P03C51RuntimeAndCheckRunnerStayLocalExplicitAndDerived', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testTypedEvidenceContextContractAnchor', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testC31TypedLightingPackageContractAnchor', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testC33V914SettingsCapabilityLifecycleCompatibilityBindsTypedTemporalEvidenceToItsOwner', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testC32V914SettingsCapabilityLifecycleCompatibilityKeepsProposalAtExplicitReviewBoundary', 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests/testC46SettingsCannotActivateAutomaticHandoff']


class GeneratorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = generator.load_json(MANIFEST)
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.checkout = Path(cls.temp.name).resolve() / "checkout"
        sources = cls.checkout / "FieldEvidenceAppTests"
        sources.mkdir(parents=True)
        classes = sorted({name for group in cls.manifest["groups"] for name in group["classes"]})
        for class_name in classes:
            relative = "FieldEvidenceAppTests/" + class_name + ".swift"
            overlays = {
                'V9_14SettingsCapabilityLifecycleTests': REPO / 'FieldEvidenceAppTests/V9_14SettingsCapabilityLifecycleTests.swift',
                'V9_85RecurringRoundExperienceTests': REPO / 'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests.swift',
                'V23PartsStockReplacementHistoryTests': REPO / 'FieldEvidenceAppTests/V23PartsStockReplacementHistoryTests.swift',
                'V23RoundRestoreHistoryTests': REPO / 'FieldEvidenceAppTests/V23RoundRestoreHistoryTests.swift',
                'V23ReminderPolicyEditTests': REPO / 'FieldEvidenceAppTests/V23ReminderPolicyEditTests.swift',
                'V23ReminderProductionSettingsTests': REPO / 'FieldEvidenceAppTests/V23ReminderProductionSettingsTests.swift',
                'V23DetailedReminderDeliveryTests': REPO / 'FieldEvidenceAppTests/V23DetailedReminderDeliveryTests.swift',
                'V23ReminderControlContinuationTests': REPO / 'FieldEvidenceAppTests/V23ReminderControlContinuationTests.swift',
                'V23RepetitiveCaptureRestoreReviewTests': REPO / 'FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests.swift',
                'V23RestoreReviewAuthorityTests': REPO / 'FieldEvidenceAppTests/V23RestoreReviewAuthorityTests.swift',
                'V23ProductionDestinationReviewTests': REPO / 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests.swift',
                'V23RepetitiveCaptureDestinationReviewTests': REPO / 'FieldEvidenceAppTests/V23RepetitiveCaptureDestinationReviewTests.swift',
                'V23RepetitiveCaptureDestinationResolutionTests': REPO / 'FieldEvidenceAppTests/V23RepetitiveCaptureDestinationResolutionTests.swift',
                'V23RepetitiveCaptureDestinationDiscardTests': REPO / 'FieldEvidenceAppTests/V23RepetitiveCaptureDestinationDiscardTests.swift',
                'V23RepetitiveCaptureDestinationContinuationTests': REPO / 'FieldEvidenceAppTests/V23RepetitiveCaptureDestinationContinuationTests.swift',
                'V9_30FieldDraftResilienceTests': REPO / 'FieldEvidenceAppTests/V9_30FieldDraftResilienceTests.swift',
                "V9_18PackLifecycleIntegrationTests": REPO / "FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests.swift",
                "S6_2BackupExportTests": REPO / "FieldEvidenceAppTests/S6_2BackupExportTests.swift",
                "S6_3BackupValidationTests": REPO / "FieldEvidenceAppTests/S6_3BackupValidationTests.swift",
                "S6_4AtomicRestoreTests": REPO / "FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift",
                "S4_1DeterministicRendererTests": REPO / "FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift",
                "V9_15AppLockLifecycleTests":
                    REPO / "FieldEvidenceAppTests/V9_15AppLockLifecycleTests.swift",
                "S3_4ResumeRecoveryTests":
                    REPO / "FieldEvidenceAppTests/S3_4ResumeRecoveryTests.swift",
            }
            raw = (overlays[class_name].read_bytes() if class_name in overlays
                   else git_bytes(relative, SOURCE_COMMIT))
            (sources / (class_name + ".swift")).write_bytes(raw)
        cls.incumbent_selection = git_bytes("Scripts/ci-selection.json")
        cls.incumbent_map = git_bytes("Scripts/ci-selection-map.json")

    def generate(self, profile="prospective-v1", manifest=None, checkout=None):
        return generator.generate(manifest or copy.deepcopy(self.manifest), profile,
                                  checkout or self.checkout)

    def test_exact_incumbent_reconstruction_and_prospective_delta(self):
        selection, selection_map, report = self.generate("incumbent-v1")
        self.assertEqual(generator.canonical(selection), self.incumbent_selection)
        self.assertEqual(generator.canonical(selection_map), self.incumbent_map)
        self.assertEqual((report["selectorCount"], report["groupCount"]), (692, 37))
        self.assertEqual((report["selectionSHA256"], report["selectionMapSHA256"]),
                         (SELECTION_SHA, MAP_SHA))

        future, future_map, future_report = self.generate()
        self.assertEqual((future_report["selectorCount"], future_report["groupCount"]),
                         (693, 38))
        self.assertEqual((future_report['selectionSHA256'], future_report['selectionMapSHA256']),
                         ('203335CCCC8FACDC8560C1F23BA28A762854664264884CBFAFB8A0F0EDF42F6E',
                          '6D74CFA1BA6EBC0B46ED0656F285F8BD59DA61D62CB60E02C2B37B2978973EBD'))
        self.assertEqual(future["unitTestSelectors"][:-1], selection["unitTestSelectors"])
        self.assertEqual(future["unitTestSelectors"][-1], NEW_SELECTOR)
        self.assertEqual(future_map["groups"][:-1], selection_map["groups"])
        self.assertEqual(future_map["groups"][-1], {
            "id": "mutation-receipt-safety",
            "classes": ["V23MutationReceiptSafetyTests"],
            "methodCount": 1,
        })
        self.assertFalse(future_report["nativeReady"])
        self.assertFalse(future_report["acceptance"])

    def test_raw_photo_profile_retains_both_historical_profiles_and_enrolls_exact_four(self):
        prior, prior_map, _ = self.generate('prospective-v1')
        current, current_map, report = self.generate('raw-photo-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (697, 39))
        self.assertEqual(current['unitTestSelectors'][:-4], prior['unitTestSelectors'])
        self.assertEqual(current_map['groups'][:-1], prior_map['groups'])
        self.assertEqual(current_map['groups'][-1], {'id': 'c36-raw-staging',
            'classes': ['V9_30FieldDraftResilienceTests'], 'methodCount': 4})
        self.assertEqual(current['unitTestSelectors'][-4:], [
            'FieldEvidenceAppTests/V9_30FieldDraftResilienceTests/' + method for method in (
                'testV9_30A01AlternatePerItemStagingAndExactRetryRemainIndependent',
                'testV9_30R01RecoveryReservationRetentionBackupRestoreAndOneAuthority',
                'testRestoreInitializationMatchesActorPublicationAndReopensExactBytes',
                'testRestoreInitializationRejectsHostileInputsWithoutPublishingEntries')])
        self.assertEqual(report['selectionSHA256'],
            '62673E1257EE72462439FA8770F3D3CFB50ED2FB06F0674C7C9E8D5FE2FDBEBB')
        self.assertEqual(report['selectionMapSHA256'],
            '77E605D5BE168687CC9EB81C4F695806C6A6E2FCD619411C64AA7E251676CEAC')

    def test_pair_startup_profile_appends_exact_four_and_one_group(self):
        prior, prior_map, _ = self.generate('raw-photo-v1')
        current, current_map, report = self.generate('pair-startup-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (701, 40))
        self.assertEqual(current['unitTestSelectors'][:-4], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][-4:], STARTUP_SELECTORS)
        self.assertEqual(current_map['groups'][:-1], [
            ({**group, 'methodCount': 77} if group['id'] == 'notification-owner' else group)
            for group in prior_map['groups']
        ])
        self.assertEqual(current_map['groups'][-1], {
            'id': 'c36-startup-recovery',
            'classes': ['S3_4ResumeRecoveryTests'],
            'methodCount': 2,
        })
        self.assertEqual((report['selectionSHA256'], report['selectionMapSHA256']),
                         ('62F78130A529F9BDAE378F9A9A152E32E178CC5F132BEC1FDEF37D2CAAAAE722',
                          '70D3F3C4C034D82397564BA554425A2FFB93E51A345B1075CBD72F82610FF110'))
        for profile in ('incumbent-v1', 'prospective-v1', 'raw-photo-v1'):
            historical, historical_map, _ = self.generate(profile)
            self.assertFalse(set(STARTUP_SELECTORS) & set(historical['unitTestSelectors']))
            self.assertNotIn('c36-startup-recovery', [g['id'] for g in historical_map['groups']])

    def test_photo_backup_profile_retains_all_historical_outputs_and_appends_exact_fifteen(self):
        prior, prior_map, _ = self.generate('pair-startup-v1')
        current, current_map, report = self.generate('photo-backup-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (716, 41))
        self.assertEqual(current['unitTestSelectors'][:-15], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][-15:], PHOTO_BACKUP_SELECTORS)
        increments = {'report-camera-recovery': 11, 'archive-contracts': 1, 'restore-acceptance': 2}
        self.assertEqual(current_map['groups'][:-1], [
            {**group, 'methodCount': group['methodCount'] + increments.get(group['id'], 0)}
            for group in prior_map['groups']
        ])
        self.assertEqual(current_map['groups'][-1], {
            'id': 'backup-capacity', 'classes': ['S4_1DeterministicRendererTests'], 'methodCount': 1})
        self.assertEqual((report['selectionSHA256'], report['selectionMapSHA256']),
                         ('930A9B3C186EDD0D09F9F630A9214A0FDD95362465B8FEFFBC735D78CF83AA5D', '5BB4E7E1FA935EE74B962F4572F9384FBF5DC4E0BFA83178547D89E0A4287248'))
        for profile in ('incumbent-v1', 'prospective-v1', 'raw-photo-v1', 'pair-startup-v1'):
            historical, historical_map, _ = self.generate(profile)
            self.assertFalse(set(PHOTO_BACKUP_SELECTORS) & set(historical['unitTestSelectors']))
            self.assertNotIn('backup-capacity', [g['id'] for g in historical_map['groups']])
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_configuration_clone_profile_appends_seven_and_preserves_every_prior_profile(self):
        prior, prior_map, _ = self.generate('photo-backup-v1')
        current, current_map, report = self.generate('configuration-clone-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (723, 41))
        self.assertEqual(current['unitTestSelectors'][:716], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][716:], CONFIGURATION_CLONE_SELECTORS)
        increments = {'report-camera-recovery': 2, 'restore-acceptance': 5}
        self.assertEqual(current_map['groups'], [
            {**group, 'methodCount': group['methodCount'] + increments.get(group['id'], 0)}
            for group in prior_map['groups']])
        self.assertEqual((report['selectionSHA256'], report['selectionMapSHA256']),
                         ('C5BFBCF739DCD2BCAF77801385CD1A16C116D6AFE07F1AD02162F0AEF9030AA0', '955D579A27A62C179660C0F8A4A38FF4D91FB9241244BA3B0334A9AF1B0C7A6E'))
        for profile in ('incumbent-v1', 'prospective-v1', 'raw-photo-v1', 'pair-startup-v1', 'photo-backup-v1'):
            historical, _, _ = self.generate(profile)
            self.assertFalse(set(CONFIGURATION_CLONE_SELECTORS) & set(historical['unitTestSelectors']))
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_clone_retirement_appends_eight_without_changing_historical_profiles(self):
        prior, prior_map, _ = self.generate('configuration-clone-v1')
        current, current_map, report = self.generate('clone-retirement-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (731, 41))
        self.assertEqual(current['unitTestSelectors'][:723], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][723:], CLONE_RETIREMENT_SELECTORS)
        self.assertEqual(current_map['groups'], [
            {**group, 'methodCount': group['methodCount'] + (8 if group['id'] == 'restore-acceptance' else 0)}
            for group in prior_map['groups']])
        self.assertEqual((report['selectionSHA256'], report['selectionMapSHA256']),
                         ('42337B38E49081DA1D0F9265235B3787DE105C6E695123A6F2CEB560779E2878',
                          '1891580B81536B16989FDB4976A4288FB548A18DA0280C5D7345A22AD2DD5E85'))
        for profile in ('incumbent-v1', 'prospective-v1', 'raw-photo-v1',
                        'pair-startup-v1', 'photo-backup-v1', 'configuration-clone-v1'):
            historical, _, _ = self.generate(profile)
            self.assertFalse(set(CLONE_RETIREMENT_SELECTORS) & set(historical['unitTestSelectors']))
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_parent_finalization_appends_seven_and_preserves_all_prior_profiles(self):
        prior, prior_map, _ = self.generate('clone-retirement-v1')
        current, current_map, report = self.generate('parent-finalization-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (738, 41))
        self.assertEqual(current['unitTestSelectors'][:731], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][731:], PARENT_FINALIZATION_SELECTORS)
        self.assertEqual(current_map['groups'], [
            {**group, 'methodCount': group['methodCount'] + (7 if group['id'] == 'report-camera-recovery' else 0)}
            for group in prior_map['groups']])
        for profile, hashes in HISTORICAL_PROFILE_HASHES.items():
            historical, _, proof = self.generate(profile)
            self.assertEqual([proof['selectionSHA256'], proof['selectionMapSHA256']], hashes)
            self.assertFalse(set(PARENT_FINALIZATION_SELECTORS) & set(historical['unitTestSelectors']))
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_destination_profile_enrolls_exact_family_and_preserves_eight_historical_outputs(self):
        prior, prior_map, _ = self.generate('parent-finalization-v1')
        current, current_map, report = self.generate('destination-review-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (773, 45))
        self.assertEqual(current['unitTestSelectors'][:738], prior['unitTestSelectors'])
        self.assertEqual(current['unitTestSelectors'][738:], DESTINATION_SELECTORS)
        self.assertEqual(len(set(DESTINATION_SELECTORS)), 35)
        self.assertFalse(set(DESTINATION_SELECTORS) & set(prior['unitTestSelectors']))
        self.assertEqual(current_map['groups'][:41], [
            {**group, 'methodCount': group['methodCount'] + (1 if group['id'] == 'c36-raw-staging' else 0)}
            for group in prior_map['groups']])
        self.assertEqual([g['id'] for g in current_map['groups'][41:]], DESTINATION_GROUP_IDS)
        self.assertEqual([g['methodCount'] for g in current_map['groups'][41:]], [13, 7, 7, 7])
        historical_hashes = dict(HISTORICAL_PROFILE_HASHES)
        historical_hashes['parent-finalization-v1'] = [
            '1F2C99A95F04D378A6FB6FB0656FC0A9A6DC6A42D711E3FDD55996F86D25D572',
            'E1128081C187ABE0B9E2B69CA3998EA79EA71B4124A8BBD14942418F066F3A4E']
        for profile, hashes in historical_hashes.items():
            historical, _, proof = self.generate(profile)
            self.assertEqual([proof['selectionSHA256'], proof['selectionMapSHA256']], hashes)
            self.assertFalse(set(DESTINATION_SELECTORS) & set(historical['unitTestSelectors']))
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_production_destination_appends_four_and_preserves_nine_profiles(self):
        expected = ['FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionFreezesOneChoiceAndRecoversOriginalWithoutNewIDs', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionRejectsStaleTargetAndRetiredOwnerWithoutEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardRequiresConfirmationThenReplaysOriginalWithoutConfirmationOrEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardCanCompleteReviewWithoutOperationalRoundAndRejectsRetirement']
        prior_manifest = json.loads(git_bytes('Scripts/v23-selection-manifest.json',
            'a8200c279894ce0c10f0e6f766577ec22c5d941d'))
        self.assertEqual(len(prior_manifest['profiles']), 9)
        for profile in prior_manifest['profiles']:
            with self.subTest(profile=profile['id']):
                old = self.generate(profile['id'], manifest=prior_manifest)
                current = self.generate(profile['id'])
                self.assertEqual(generator.canonical(current[0]), generator.canonical(old[0]))
                self.assertEqual(generator.canonical(current[1]), generator.canonical(old[1]))
                self.assertFalse(set(expected) & set(current[0]['unitTestSelectors']))
        prior, prior_map, _ = self.generate('destination-review-v1')
        current, mapping, report = self.generate('production-destination-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (777, 46))
        self.assertEqual(current['unitTestSelectors'], prior['unitTestSelectors'] + expected)
        self.assertEqual(mapping['groups'][:-1], prior_map['groups'])
        self.assertEqual(mapping['groups'][-1], {'id': 'c36-production-destination',
            'classes': ['V23ProductionDestinationReviewTests'], 'methodCount': 4})
        self.assertEqual(len(set(expected)), 4)
        self.assertEqual(generator.sha256(generator.canonical(current)), 'C82EBC63F02BA3B0A6957A09859C41B4686340402C6D8113A6A45040FFFBEDB5')
        self.assertEqual(generator.sha256(generator.canonical(mapping)), '732FBF8DC385F248761064F8073AD44C9F057A00CEE02140E0285874896C5F76')
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_restore_review_profile_preserves_all_historical_outputs_and_enrolls_exact_groups(self):
        expected = EXPECTED_RESTORE_REVIEW_SELECTORS
        prior, prior_map, _ = self.generate('production-destination-v1')
        current, mapping, report = self.generate('restore-review-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (790, 48))
        self.assertEqual(current['unitTestSelectors'], prior['unitTestSelectors'] + expected)
        self.assertEqual(mapping['groups'][:-2], prior_map['groups'])
        self.assertEqual(mapping['groups'][-2:], [
            {'id':'c36-restore-review','classes':['V23RepetitiveCaptureRestoreReviewTests'],'methodCount':6},
            {'id':'c36-restore-authority','classes':['V23RestoreReviewAuthorityTests'],'methodCount':7}])
        self.assertEqual(generator.sha256(generator.canonical(current)), HISTORICAL_PROFILE_PINS['restore-review-v1']['selectionSHA256'])
        self.assertEqual(generator.sha256(generator.canonical(mapping)), HISTORICAL_PROFILE_PINS['restore-review-v1']['mapSHA256'])
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_reminder_profile_enrolls_exact_journeys_and_preserves_all_eleven_profiles(self):
        for profile, pins in HISTORICAL_PROFILE_PINS.items():
            selection, mapping, _ = self.generate(profile)
            self.assertEqual(generator.sha256(generator.canonical(selection)), pins['selectionSHA256'])
            self.assertEqual(generator.sha256(generator.canonical(mapping)), pins['mapSHA256'])
        prior, prior_map, _ = self.generate('restore-review-v1')
        current, mapping, report = self.generate('reminder-production-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (861, 53))
        self.assertEqual(current['unitTestSelectors'], prior['unitTestSelectors'] + EXPECTED_REMINDER_PRODUCTION_SELECTORS)
        self.assertEqual(len(set(EXPECTED_REMINDER_PRODUCTION_SELECTORS)), 71)
        self.assertEqual(mapping['groups'][48:], EXPECTED_REMINDER_PRODUCTION_GROUPS)
        deltas = {'notification-controls': 4, 'notification-owner': 16,
                  'notification-schedule-erase': 8, 'archive-contracts': 1,
                  'restore-acceptance': 1, 'mutation-command-codec': 2}
        self.assertEqual(mapping['groups'][:48], [dict(group, methodCount=group['methodCount'] + deltas.get(group['id'], 0)) for group in prior_map['groups']])
        self.assertEqual(generator.sha256(generator.canonical(current)), '5484325202957B1DFF6BCD00918273A7792D6D2E5280D32BFEE1368D67CBAE70')
        self.assertEqual(generator.sha256(generator.canonical(mapping)), '38554B50BAE48ED14098ED2B243B1D19497EB98EBA480A274741BDF6B6416B04')
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])

    def test_settings_compatibility_profile_preserves_twelve_profiles_and_enrolls_seven(self):
        expected = dict(HISTORICAL_PROFILE_PINS)
        expected['reminder-production-v1'] = {
            'selectionSHA256': '5484325202957B1DFF6BCD00918273A7792D6D2E5280D32BFEE1368D67CBAE70',
            'mapSHA256': '38554B50BAE48ED14098ED2B243B1D19497EB98EBA480A274741BDF6B6416B04'}
        self.assertEqual(len(expected), 12)
        for profile, pins in expected.items():
            selection, mapping, _ = self.generate(profile)
            self.assertEqual(generator.sha256(generator.canonical(selection)), pins['selectionSHA256'])
            self.assertEqual(generator.sha256(generator.canonical(mapping)), pins['mapSHA256'])
        prior, prior_map, _ = self.generate('reminder-production-v1')
        current, mapping, report = self.generate('reminder-compatibility-v1')
        self.assertEqual((report['selectorCount'], report['groupCount']), (868, 53))
        self.assertEqual(len(set(EXPECTED_SETTINGS_COMPATIBILITY_SELECTORS)), 7)
        self.assertEqual(current['unitTestSelectors'], prior['unitTestSelectors'] + EXPECTED_SETTINGS_COMPATIBILITY_SELECTORS)
        self.assertEqual(mapping['groups'], [dict(group, methodCount=group['methodCount'] + (7 if group['id'] == 'notification-controls' else 0)) for group in prior_map['groups']])
        self.assertEqual(generator.canonical(current), (HERE / 'ci-selection.json').read_bytes())
        self.assertEqual(generator.canonical(mapping), (HERE / 'ci-selection-map.json').read_bytes())
        self.assertFalse(report['nativeReady'])
        self.assertFalse(report['acceptance'])


    def test_legacy_consumer_shape_disjoint_exhaustive_and_deterministic(self):
        selection, selection_map, report = self.generate()
        self.assertEqual(set(selection), generator.COMMON_KEYS | {"unitTestSelectors"})
        self.assertEqual(set(selection_map), {"schemaVersion", "taskID", "defaultSelectionID", "groups"})
        expected = set(selection["unitTestSelectors"])
        covered = set()
        for group in selection_map["groups"]:
            self.assertEqual(set(group), {"id", "classes", "methodCount"})
            members = [item for item in selection["unitTestSelectors"]
                       if generator.parse_selector(item)[0] in group["classes"]]
            self.assertEqual(len(members), group["methodCount"])
            self.assertFalse(covered & set(members))
            covered.update(members)
        self.assertEqual(covered, expected)
        again = self.generate()
        self.assertEqual(generator.canonical(selection), generator.canonical(again[0]))
        self.assertEqual(generator.canonical(selection_map), generator.canonical(again[1]))
        self.assertEqual(report, again[2])

    def test_manifest_shape_membership_environment_and_path_hostiles(self):
        mutations = []
        value = copy.deepcopy(self.manifest); value["unknown"] = 1; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"].append(value["selectorPool"][0]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"][0] = "FieldEvidenceAppTests/../testEscape"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["commonSelection"]["buildTimeoutSeconds"] = 1201; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["commonSelection"]["runUISmoke"] = 0; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][1]["classes"].append(value["groups"][0]["classes"][0]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][0]["classes"][0] = "UnknownTests"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][1]["id"] = value["groups"][0]["id"]; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedGroupIDs"] = ["unknown"]; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedSelectors"] = ["unknown"]; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedSelectors"].append(value["profiles"][0]["excludedSelectors"][0]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedSelectors"].append(STARTUP_SELECTORS[2]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedGroupIDs"] = []; value["profiles"][0]["excludedSelectors"] = [s for s in value["selectorPool"] if s.split('/')[1] == 'V9_14SettingsCapabilityLifecycleTests']; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["unknown"] = []; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["defaultSelectionID"] = "unadmitted-default"; mutations.append(value)
        value = copy.deepcopy(self.manifest); value["selectorPool"].append({}); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["groups"][0]["classes"].append([]); mutations.append(value)
        value = copy.deepcopy(self.manifest); value["profiles"][0]["excludedGroupIDs"].append({}); mutations.append(value)
        for index, hostile in enumerate(mutations):
            with self.subTest(index=index), self.assertRaises(generator.ManifestError):
                generator.validate_manifest(hostile)

        legacy = copy.deepcopy(self.manifest)
        legacy['profiles'] = [{'id': 'legacy-v1', 'excludedGroupIDs': []}]
        generator.validate_manifest(legacy)

        duplicate = Path(self.temp.name) / "duplicate-keys.json"
        duplicate.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")
        with self.assertRaises(generator.ManifestError):
            generator.load_json(duplicate)
        with self.assertRaisesRegex(generator.ManifestError, "unknown profile"):
            self.generate("unknown-profile")

    def test_missing_unknown_and_duplicate_source_declarations_fail(self):
        target = self.checkout / "FieldEvidenceAppTests/V23MutationReceiptSafetyTests.swift"
        original = target.read_text(encoding="utf-8")
        token = "func testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority("
        self.assertEqual(original.count(token), 1)
        try:
            target.write_text(original.replace(token, "func renamedDayAndNightWorkflow("), encoding="utf-8")
            with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
                self.generate()
            target.write_text(original + "\nextension V23MutationReceiptSafetyTests {\n    " + token + ") {}\n}\n",
                              encoding="utf-8")
            with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
                self.generate()
        finally:
            target.write_text(original, encoding="utf-8")

        hostile = copy.deepcopy(self.manifest)
        receipt_index = hostile["selectorPool"].index(NEW_SELECTOR)
        hostile["selectorPool"][receipt_index] = hostile["selectorPool"][receipt_index].replace(
            "testDayAndNightWorkflowReplayBindsOriginalRequestAndLiveJournalAuthority",
            "testUnknownReceiptSafetyMethod")
        with self.assertRaisesRegex(generator.ManifestError, "missing or duplicate source method"):
            self.generate(manifest=hostile)

    def test_cli_outputs_are_canonical_and_refuse_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            command = [sys.executable, str(GENERATOR), "generate", "--manifest", str(MANIFEST),
                       "--checkout-root", str(self.checkout), "--profile", "prospective-v1",
                       "--selection-output", str(output / "ci-selection.json"),
                       "--map-output", str(output / "ci-selection-map.json"),
                       "--report-output", str(output / "report.json")]
            first = subprocess.run(command, check=True, capture_output=True)
            selection, selection_map, report = self.generate()
            self.assertEqual((output / "ci-selection.json").read_bytes(), generator.canonical(selection))
            self.assertEqual((output / "ci-selection-map.json").read_bytes(), generator.canonical(selection_map))
            self.assertEqual((output / "report.json").read_bytes(), generator.canonical(report))
            self.assertEqual(first.stdout, generator.canonical(report))
            second = subprocess.run(command, capture_output=True)
            self.assertEqual(second.returncode, 65)
            self.assertIn(b"output already exists", second.stderr)

            partial = output / "partial"
            partial.mkdir()
            (partial / "ci-selection-map.json").write_text("occupied", encoding="utf-8")
            hostile = command.copy()
            hostile[hostile.index(str(output / "ci-selection.json"))] = str(partial / "ci-selection.json")
            hostile[hostile.index(str(output / "ci-selection-map.json"))] = str(partial / "ci-selection-map.json")
            hostile[hostile.index(str(output / "report.json"))] = str(partial / "report.json")
            failed = subprocess.run(hostile, capture_output=True)
            self.assertEqual(failed.returncode, 65)
            self.assertFalse((partial / "ci-selection.json").exists())
            self.assertFalse((partial / "report.json").exists())

    def generate_source_case(self, source):
        manifest = copy.deepcopy(self.manifest)
        manifest["selectorPool"] = ["FieldEvidenceAppTests/FixtureTests/testSelected"]
        manifest["groups"] = [{"id": "fixture", "classes": ["FixtureTests"]}]
        manifest["profiles"] = [{"id": "fixture-v1", "excludedGroupIDs": []}]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            directory = root / "FieldEvidenceAppTests"
            directory.mkdir()
            (directory / "FixtureTests.swift").write_text(source, encoding="utf-8")
            return generator.generate(manifest, "fixture-v1", root)

    def test_only_direct_runnable_xctest_methods_are_members(self):
        invalid = {
            "nested function": "class FixtureTests: XCTestCase { func helper() { func testSelected() {} } }",
            "nested type": "class FixtureTests: XCTestCase { struct Helper { func testSelected() {} } }",
            "parameter": "class FixtureTests: XCTestCase { func testSelected(value: Int) {} }",
            "static": "class FixtureTests: XCTestCase { static func testSelected() {} }",
            "multiline static": "class FixtureTests: XCTestCase {\n static\n\n func testSelected() {} }",
            "class method": "class FixtureTests: XCTestCase { class func testSelected() {} }",
            "private": "class FixtureTests: XCTestCase { private func testSelected() {} }",
            "return value": "class FixtureTests: XCTestCase { func testSelected() -> Int { 1 } }",
            "generic": "class FixtureTests: XCTestCase { func testSelected<T>() {} }",
            "not XCTest": "class FixtureTests { func testSelected() {} }",
            "unknown base": "class FixtureTests: MissingBase { func testSelected() {} }",
            "shadowed XCTest class": "class XCTestCase {}\nclass FixtureTests: XCTestCase { func testSelected() {} }",
            "shadowed XCTest alias": "typealias XCTestCase = Fake\nclass FixtureTests: XCTestCase { func testSelected() {} }",
            "shadowed XCTest module": "struct XCTest {}\nclass FixtureTests: XCTest.XCTestCase { func testSelected() {} }",
            "non XCTest base": "class Base {}\nclass FixtureTests: Base { func testSelected() {} }",
            "inheritance cycle": "class Base: FixtureTests {}\nclass FixtureTests: Base { func testSelected() {} }",
            "nested class": "struct Owner { class FixtureTests: XCTestCase { func testSelected() {} } }",
            "private extension": "class FixtureTests: XCTestCase {}\nprivate extension FixtureTests { func testSelected() {} }",
            "conditional extension": "class FixtureTests: XCTestCase {}\nextension FixtureTests where Element: Equatable { func testSelected() {} }",
            "availability": "class FixtureTests: XCTestCase {\n @available(iOS 99, *)\n func testSelected() {} }",
        }
        for label, source in invalid.items():
            with self.subTest(label=label), self.assertRaises(generator.ManifestError):
                self.generate_source_case(source)
        valid = [
            "class FixtureTests: XCTestCase { func testSelected() {} }",
            "final class FixtureTests: XCTestCase {\n @MainActor\n func testSelected() async throws {} }",
            "class FixtureTests: XCTestCase {}\nextension FixtureTests { func testSelected() throws {} }",
            "class Base: XCTestCase {}\nclass FixtureTests: Base { func testSelected() {} }",
            "class FixtureTests: XCTest.XCTestCase { func testSelected()\n async throws {} }",
        ]
        for source in valid:
            with self.subTest(source=source):
                self.assertEqual(self.generate_source_case(source)[2]["selectorCount"], 1)

    def test_closed_debug_simulator_conditions_and_masked_noncode(self):
        method = "func testSelected() {}"
        for condition in ("false", "SWIFT_PACKAGE"):
            source = "class FixtureTests: XCTestCase {\n#if " + condition + "\n" + method + "\n#endif\n}"
            with self.subTest(condition=condition), self.assertRaises(generator.ManifestError):
                self.generate_source_case(source)
        for directives in (
            "#if UNKNOWN\n" + method + "\n#endif",
            "#if DEBUG\n" + method,
            "#else\n" + method,
            "#if DEBUG\n#else\n#else\n" + method + "\n#endif",
            "#if false\n#if UNKNOWN\n#endif\n#else\n" + method + "\n#endif",
        ):
            with self.subTest(directives=directives), self.assertRaises(generator.ManifestError):
                self.generate_source_case("class FixtureTests: XCTestCase {\n" + directives + "\n}")
        for directives in (
            "#if DEBUG\n" + method + "\n#endif",
            "#if DEBUG && os(iOS) && targetEnvironment(simulator)\n" + method + "\n#endif",
            "#if SWIFT_PACKAGE\nfunc helper() {}\n#else\n" + method + "\n#endif",
            "#if SWIFT_PACKAGE\nfunc helper() {}\n#elseif DEBUG\n" + method + "\n#else\nfunc other() {}\n#endif",
            "#if DEBUG\n#if SWIFT_PACKAGE\nfunc helper() {}\n#else\n" + method + "\n#endif\n#endif",
        ):
            with self.subTest(directives=directives):
                self.assertEqual(self.generate_source_case("class FixtureTests: XCTestCase {\n" + directives + "\n}")[2]["selectorCount"], 1)
        fake = 'func testSelected() {}'
        noncode = [
            '// ' + fake,
            '/* outer /* nested */ ' + fake + ' */',
            'let value = "' + fake + '"',
            'let value = #"escaped \\#" ' + fake + '"#',
            'let value = """\n' + fake + '\n"""',
            'let value = ##"""\n' + fake + '\n"""##',
        ]
        for hidden in noncode:
            with self.subTest(hidden=hidden):
                with self.assertRaises(generator.ManifestError):
                    self.generate_source_case("class FixtureTests: XCTestCase {\n" + hidden + "\n}")
                self.assertEqual(self.generate_source_case("class FixtureTests: XCTestCase {\n" + hidden + "\n" + method + "\n}")[2]["selectorCount"], 1)


if __name__ == "__main__":
    unittest.main()
