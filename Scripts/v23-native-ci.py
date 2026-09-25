#!/usr/bin/env python3
"""Closed V23 native admission and factual evidence checks, not a CI scheduler.

The incumbent workflow owns native commands, budgets, credentials and uploads.
This module has no API client and never dispatches, retries or promotes a run.
"""
import argparse
import base64
import contextlib
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import platform
import re
import runpy
import signal
import shlex
import stat
import subprocess
import tarfile
import time
import zlib


CONTRACT = "v23.integration.current-native.v1"
TASK = "V23-INTEGRATION-20260910"
REPOSITORY = "Asset-Rounds/AssetRounds"
REFS = {"refs/heads/codex/v23-s10-integration-20260910"}
LANES = {
    "github-xcode-26.6-acceptance": ("github", "macos-26"),
    "bitrise-build-hub-xcode-26.6-acceptance": ("bitrise", "bitrise-runner-Asset Roundddd"),
}
TIERS = {"N8": (300, 1200, 900, 0, 2400), "P12": (300, 600, 900, 900, 3300),
         "F25": (300, 900, 1200, 1800, 4500), "D30": (300, 1800, 900, 0, 3000),
         "D50": (300, 1800, 3000, 0, 5100),
         # Development-only shared coverage: one build-only producer, then test-only consumers.
         # Each total adds 300 s for the payload seal/upload or the fingerprints and evidence.
         "D40P": (300, 2400, 0, 0, 3000), "D50C": (300, 0, 3000, 0, 3600),
         # Owner decision 16 (2026-09-25): a consumer partition of exactly ONE known-slow
         # method may test for up to 5,400 s until the performance fix lands.
         "D90S": (300, 0, 5400, 0, 6000)}
NO_UI_TIERS = ("N8", "D30", "D50", "D40P", "D50C", "D90S")
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
RESTORE_BUILD_WATCHDOG_PARENT = '0f8bad2567c630ec07d821f31926af8eeb1a8355'
RESTORE_BUILD_WATCHDOG_TREES = {'FieldEvidenceApp': '590eaf1db6312f48a2d298eac22e9df1110183bd', 'FieldEvidenceAppTests': 'c6601753da678593a9f5b76a13da9b54b17eb485', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
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
REMINDER_BUILD_WATCHDOG_PARENT = '0f8bad2567c630ec07d821f31926af8eeb1a8355'
REMINDER_BUILD_WATCHDOG_TREES = {'FieldEvidenceApp': '590eaf1db6312f48a2d298eac22e9df1110183bd', 'FieldEvidenceAppTests': 'c6601753da678593a9f5b76a13da9b54b17eb485', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
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
RESTORE_HISTORY_PARENT = '0f8bad2567c630ec07d821f31926af8eeb1a8355'
RESTORE_HISTORY_TREES = {'FieldEvidenceApp': '590eaf1db6312f48a2d298eac22e9df1110183bd', 'FieldEvidenceAppTests': 'c6601753da678593a9f5b76a13da9b54b17eb485', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
RESTORE_HISTORY_GROUPS = ("c36-restore-review", "replacement-packet-union")
RESTORE_HISTORY_PACKET_SELECTOR = 'FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot'
RESTORE_HISTORY_SELECTORS = RESTORE_BUILD_WATCHDOG_SELECTORS + (RESTORE_HISTORY_PACKET_SELECTOR,)
REPLACEMENT_UNION_SELECTION_ID = "replacement-union-no-index-build30m"
REPLACEMENT_UNION_PARENT = '0f8bad2567c630ec07d821f31926af8eeb1a8355'
REPLACEMENT_UNION_TREES = {'FieldEvidenceApp': '590eaf1db6312f48a2d298eac22e9df1110183bd', 'FieldEvidenceAppTests': 'c6601753da678593a9f5b76a13da9b54b17eb485', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
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
REPLACEMENT_REMAINDER_SELECTION_ID = "replacement-remainder-no-index-build30m"
REPLACEMENT_REPORT_SELECTION_ID = "replacement-report-fork-no-index-build30m"
REPLACEMENT_DIAGNOSTIC_PARTITIONS = (
    (REPLACEMENT_REMAINDER_SELECTION_ID, REPLACEMENT_UNION_SELECTORS[:-1]),
    (REPLACEMENT_REPORT_SELECTION_ID, REPLACEMENT_UNION_SELECTORS[-1:]),
)
ERASE_DRAIN_SELECTION_ID = "erase-drain-timing-no-index-build30m"
ERASE_REMAINDER_SELECTION_ID = "erase-remainder-no-index-build30m"
ERASE_PARTITION_PARENT = '16e82a8baded44cea8ed4a2c97a685df7d0b4154'
ERASE_PARTITION_TREES = {'FieldEvidenceApp': '4026fabeab434086e3acbf9dcb03113da5d31128', 'FieldEvidenceAppTests': '9060b1c7c444a17d187f5001a61278fba507359b', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
ACTIVITY_BUILD30_SELECTION_ID = "activity-contracts-no-index-build30m"
ACTIVITY_CONTRACT_SELECTORS = (
    'FieldEvidenceAppTests/V9_54ActivityContractFamiliesTests/testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed',
)
ACTIVITY_CODEC_PUNCH_SELECTION_ID = "activity-codec-punch-no-index-build30m"
ACTIVITY_CODEC_SELECTORS = (
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyEnvelopeArchiveSnapshotBytesRemainExact',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyMutationCommandRequestBytesRemainExact',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyEnvelopeRowsRejectCorruptMirrorsAndBytes',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testSchema3RoundTripBindsSeparateTypedAndFileDigests',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testClosedFileReferenceRejectsUnknownFieldsVersionsAndNoncanonicalIdentity',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testEnvelopeRejectsUnknownSchemasReservedLegacyFieldAndIncompleteSchema3',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testOnlyUnfinishedSchema2CanFinalizeIntoSchema3',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testSchema3SupersessionRetainsWholeReferenceAndRejectsDowngrade',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyMutationAndGenericCommandRejectSchema3EvenWithRecomputedMutationHash',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyAndSchema3ForkRepeatForkPreserveSourceAndFileIdentity',
    'FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyUnknownKindRemainsReadableButNotWritable',
)
PUNCH_CONTEXT_SELECTORS = (
    'FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34G01StandalonePreparationDecisionCorrectionRecheckCloseoutAndReport',
    'FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34H01StaleWrongAssetConflictingRecheckAndUnresolvedCountFailWithoutEffect',
    'FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34I01EffectBeforeReceiptInterruptionRecoversExactlyOnce',
    'FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34R01ReopenRetryImmutableHistoryAndDeterministicReportReconstruction',
)
ACTIVITY_CODEC_PUNCH_SELECTORS = ACTIVITY_CODEC_SELECTORS + PUNCH_CONTEXT_SELECTORS + ACTIVITY_CONTRACT_SELECTORS
ACTIVITY_COMPLETED_SOURCE_SELECTION_ID = 'activity-completed-source-no-index-build30m'
ACTIVITY_COMPLETED_SOURCE_PARENT = '422a9a18ad5736ea24bd3e06b50bc1b3862b0849'
ACTIVITY_COMPLETED_SOURCE_TREES = {'FieldEvidenceApp': 'b0e15d6aff470235bac00758b26f367c7863354d', 'FieldEvidenceAppTests': '9373278bf3f1eef592b248c746cb1033ad5acab2', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
ACTIVITY_COMPLETED_SOURCE_GROUPS = (
    ('activity-completed-manifest', (
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testPublishedV1ManifestRoundTripPreservesCanonicalBytesAndOmitsExtensions',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testUnsignedBoundsRoundTripPreservesEntireUInt64Domain',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testSignedDomainAndMixedWrongKindOrInvertedBounds',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestVersionsRequireMatchingCodecAndReader',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testExtendedScalarAndArrayKindsRequireManifestTwo',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestDecoderRejectsInvalidNumericBoundsWithoutRounding',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestDecoderRejectsUnknownMalformedAndExplicitNullFields',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testCodecTwoKeepsExistingRulesAndClosesVersionSpecificTimeMetadata',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testPreservedStringAndStringMapMetadataRoundTripWithoutInventedCountLimit',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testStringMapMetadataRejectsInvalidBoundsShapesAndArrayUse',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testNumericEnumMetadataPreservesExactSourceRotationWireValues',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testNumericEnumMetadataRejectsMixedMalformedAndLegacyDefinitions',
        'FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testClosedEmptyObjectMetadataRequiresSchemaTwoAndMatchesPoseWire',
    )),
    ('activity-completed-file', (
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testClosedCompletedFileRoundTripPreservesRealNestedV2AndSeparateHashes',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureUsesActivityRevisionsAndKeepsWorkspaceFrontierPortable',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureRejectsStaleActivityRevisionAndInvalidTransitionOrderingOrStateChain',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureRejectsOverflowAndNonfiniteOrResampledTime',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testFileRejectsWrongFamilyVersionOutputAndUnknownFields',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testTypedPayloadTamperFailsEvenWithRecomputedWholeFileHash',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testWholeFileTamperFailsEvenWhenNestedSnapshotIsUnchanged',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCapturedAbsenceRequiresEveryClosedQueryAtExactFrontier',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testFullFrozenProfileAndManifestAreBoundToSnapshot',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testExplicitSelectionUsesCanonicalObjectsAndClosedKeys',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testStandalonePunchDoesNotManufactureInstallationOrAccountabilityAbsence',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testLegacyPredecessorOwnerKeepsUUIDPathAndWholeFileDigestDistinct',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCrossActivityCorrectionOwnsNewOriginalForLegacyAndClosedPredecessors',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testUnfinishedAmendmentRetainsActualPriorWithoutInventingCompletedOutput',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testApprovedMediaRequiresExactBytesLengthWorkspaceAndOutputScope',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testPlacementSourcesRetainExactPoseAndPhysicalAncestors',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testPlacementSourcesRejectMissingForeignAndUnselectedValues',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testReviewedEvidenceFreezesPlanProjectionAndSeparateFieldMediaHashes',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testReviewedEvidenceRejectsMissingTamperedAndForeignSources',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testNewProvenanceArraysAreRequiredClosedWireFields',
        'FieldEvidenceAppTests/V23ActivityCompletedFileTests/testLegacy32CorpusPreservesLiteralBytesAndBareV2Codec',
    )),
    ('activity-completed-production', (
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testRealWriterReadsPopulatedInstallationAndEntireSelectedProfileWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCaptureFreezesExactPromotedPackageAndSourceWorkflow',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testHistoricalCompletionRetainsRecordedPackageWithoutCurrentStartPointer',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testMissingRecordedPackageRejectsCaptureAndOldFrameWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCaptureUsesActualActivityRevisionTransitionsIncludingTaskAndAsBuiltGaps',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testWrongWorkspaceMissingActivityAndUnavailableSelectedProfileRejectWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCommittedProfileChangeRejectsOldSelectionAndFrameWithoutAdoptingNewProfile',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testWriterInvalidationAndGenerationChangeRejectPreviouslyReadFrameWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameFrontierTaskReplacementAndFamilyInsertionOrRemovalRejectWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameFrontierAcceptedReceiptTamperRejectsWithoutEffects',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameRevisionRehashedProfileCannotReplaceAcceptedBytesEvenWhenSelectedByNewReference',
        'FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testQuarantinedActivityOrProfileReceiptCannotAuthorizeSourceRead',
    )),
    ('activity-evidence-projection', (
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionAcceptsDistinctFieldAndApprovedMediaDigests',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsUnapprovedAndMixedMedia',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsOriginalAndMissingOutputReferences',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsWrongWorkspaceAndAudience',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsMissingRejectedStaleAndChangedSource',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsSemanticCardTampering',
        'FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRebuildsMarkupWithoutChangingReviewedPlan',
    )),
    ('activity-completed-release', (
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testActualAppBundleAdmitsExactCompleteManifestAndBothSchemas',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testPublishedDefinitionsAndSevenSectionRegistryRemainExactButOldReleaseIsExcluded',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testActualBundleLookupSupportsFlattenedAndPreservedResourceLayouts',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testMissingAndRenamedResourcesCannotFallBackToAnotherBundle',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testDuplicateResourceIdentityFailsEvenWhenBothCopiesAreAuthentic',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testTruncatedOversizedAndSameSizeTamperedResourcesFailAtRealLoader',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testSchemaResourceIdentityCannotBeSwappedAndManifestIdentityCannotBeRewritten',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testSymlinkedResourceIsNotAnAppOwnedResource',
        'FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testFrozenReadbackRejectsWrongIdentityVersionReaderRegistryAndIncompleteCatalog',
    )),
)
ACTIVITY_COMPLETED_SOURCE_SELECTORS = tuple(
    member for _, members in ACTIVITY_COMPLETED_SOURCE_GROUPS for member in members
) + ACTIVITY_CONTRACT_SELECTORS
NOTIFICATION_INTERRUPTION_SELECTION_ID = 'notification-interruption-no-index-build30m'
NOTIFICATION_INTERRUPTION_PARENT = 'cf357a4e75dce1a9bff56f4b72af60989d3df643'
NOTIFICATION_INTERRUPTION_TREES = {'FieldEvidenceApp': '7731c5593306ce9bc2fa8ef49e928e50ad4f1ba3', 'FieldEvidenceAppTests': '6c326564ba3538891a086515168d7d3e2a541f28', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
NOTIFICATION_INTERRUPTION_SELECTORS = (
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testRetainedLiveContextDefersCleanupUntilColdRecovery',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEveryInterruptionRecoversOldOrFullyErasedNew',
)
NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID = 'notification-schedule-erase-no-index-build30m'
NOTIFICATION_SCHEDULE_ERASE_BUILD30_PARENT = 'ea0f890edf7abc3e2b08c04c97ca87ef657d463c'
NOTIFICATION_SCHEDULE_ERASE_BUILD30_TREES = {'FieldEvidenceApp': '7731c5593306ce9bc2fa8ef49e928e50ad4f1ba3', 'FieldEvidenceAppTests': '12653533bdfdf89dcf322a0c69266bc623b74999', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTORS = (
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testNotificationPreferenceEraseFencePreservesExactCooldownAndRejectsHeldSettingAuthority',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testAbsentApplicationSupportHasNoEraseAuthority',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testRetainedLiveContextDefersCleanupUntilColdRecovery',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEveryInterruptionRecoversOldOrFullyErasedNew',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testCancelAndDirtyContextChangeNothingBeforeMarker',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testLiveCleanupWaitsForOldContextReferenceDrain',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSystemNotificationReadbackRejectsAlteredContentAndCalendarComponents',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testConcreteReminderOwnerRejectsCallerProjectionAndUsesPrivateOpaqueSystemIDs',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testConcreteReminderEraseAcrossOwnersDrainsLateAddBeforeDeletingMapping',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22G01FixedCompletionRelativeEditorDueAndStartOnce',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22A01ReminderDenialEvictionStableIDReconcileKeepsDueTruth',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22H01DSTTimeZoneActiveEditHorizonRetiredPartialPacketFailClosed',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22I01InterruptedWritesAndSameMutationIDRecoverIdempotently',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22R01BackupReplaceCloneForkRebuildAndHistoryRemainImmutable',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testActualEraseRetainsGenerationAndPreferencesUntilNotificationAbsenceIsVerified',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testC22RecoverabilityVerificationAnchor',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testSeededEraseFixtureRejectsLaterDirectMutationWithoutCheckpointAdoption',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedDetailedPolicyUsesAuthenticatedKindsAndReplacesChangedPayloads',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testAppLockEnableProjectsGenericAndDisableUsesCurrentDetailedConsent',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredDetailedRequestIsRemovedOnPrivacyDowngradeWithoutReadding',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredUnobservedGenericReminderStillFailsWithoutEffects',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testPermissionDenialStillRemovesForbiddenDetailWithoutClaimingDelivery',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedReconciliationCannotRenewRevokedOriginalProof',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testNotificationCopySourcesBindExactReleaseAndEffectiveBasis',
    'FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testGenericPolicyRejectsDetailedDurableMappingWithoutSystemEffects',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEraseManifestHandoffPreservesExactInodeAndSupportsRepeatedConstructorRecovery',
    'FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEraseManifestHandoffRejectsHostileSidecarsTargetsAndChangedPointerWithoutConsumption',
)
FINDING_PROFILE_FIXTURES_SELECTION_ID = 'finding-profile-fixtures-no-index-build30m'
FINDING_PROFILE_FIXTURES_PARENT = '803a3d495191333da7c5753064220a901417e910'
FINDING_PROFILE_FIXTURES_TREES = {'FieldEvidenceApp': '19bf6a35bfcc725bf1358c1e01f57afa2bb6702c', 'FieldEvidenceAppTests': 'ab493b1146c525be2f39425a3b7fab0fc87e9a62', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
FINDING_PROFILE_FIXTURES_GROUPS = (
    ('finding-owner-selection', (
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNineValuesRoundTripAndExposeExactClosedFields',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testLegalNonUUIDStringsStayExactAndIncumbentIDGrammarIsNotBroadened',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testOptionalFieldsMustBeAbsentRatherThanExplicitNull',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testWrongVersionKindWorkspaceAndNilIdentitiesAreRejected',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testEmptySelectionMatchesIndependentLiteralBytesAndHash',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNestedLegacyValueGroupsAreClosedOnlyAtTheNewBoundary',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testRevisionBoundariesPreserveUInt64AndIntWithoutNarrowingOrOverflow',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testDuplicateAndConflictingFindingOwnerAndRelationshipIdentitiesReject',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCanonicalOrderingIsUTF8AndRelationshipOwnerTupleOrder',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testDigestsRejectMalformedValuesAndSelectionTampering',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testExactRecheckOwnerKindRevisionAndDigestAreRequired',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testTypedFindingC14AndRecheckBindingsRejectIndependentlyValidWrongFacts',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testOriginalAndSelectedProvenanceRemainDistinctWithoutAuthenticityClaims',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testConflictingAcceptanceAndSourceIdentitiesCannotBeMerged',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCanonicalCodecRejectsDuplicateWireKeysNoncanonicalBytesAndOversizeInput',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCompleteSelectionByteLimitAppliesBeforePublication',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNilAndCrossWorkspaceSourceC14AndFrontierIdentitiesReject',
        'FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testMappedSourceAndC14PairsKeepExactFieldsAndSeparateAcceptances',
    )),
    ('finding-owner-record', (
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testBothOwnerKindsRoundTripWithIndependentGoldenDigests',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testSemanticReferencesStayDistinctFromTransportHashesAndBindConsumers',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testHumanAndImportedSourcesNeedNoFabricatedActivityBinding',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testOwnerRevisionAdvancesWithoutChangingFindingRevision',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testHistoricalValueClassificationDoesNotGrantRetryAcceptance',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testSuccessorCannotRewriteDropOrReplaceOldFacts',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testLifecycleTransitionPreservesOriginalFieldsAndRevisionLaw',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testWorkspaceOwnerAndKernelIdentityCensusRejectsConflicts',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testC14SupportRequiresOriginalGenuineActionAndRetainsUnlinkedHistory',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testDirectFindingEndpointsAllowRevisionZeroWithoutCorrection',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testRealC14NonFindingSourceAndMixedEndpointsAreSupported',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testRelationshipHistoryPreservesConfirmationAndExplicitRemoval',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testRelationshipBasisRolesKindsAndSingleOwnershipAreClosed',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testAffectedClosureRejectsCrossStreamReversePairsCyclesAndDomainAmbiguity',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testEndpointOwnerTokensAndAcceptanceIdentitiesCannotConflict',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testPredecessorOriginActorAndTimeAreExact',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testHistoryRejectsReusedMutationAndSkippedOwnerRevision',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testUInt64AndIntEdgesRejectWithoutInvokingUnsafeLegacyArithmetic',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testRecordAndEndpointUnionKeysNullsAndDigestsAreClosed',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testCanonicalTransportRejectsUnknownNestedFieldsDuplicateKeysAndOversize',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testCompleteRecordByteBoundIncludesRetainedSupportReferences',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testAppendOnlyRetentionUsesExactBytesAndGroupedEventIdentity',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2OwnerRevisionFactsAcrossRelationshipsIncludeBothReferenceSides',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActualRecordAndPredecessorReferencesJoinFactCensus',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2RetainedC14ActionRevisionRejectsChangedEventAndDigestOnBothSides',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2RetainedC14EventIdentityRejectsRevisionReuseAndAllowsDifferentEvents',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2C14EndpointEventActionConflictsReachRelationshipAndCombinedHeads',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActivityRevisionFactsRejectKindAndDigestConflictsOnBothSides',
        'FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActivityScopesReceiptsRevisionsAndWorkspacesStayIndependent',
    )),
    ('finding-owner-persistence', (
        'FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testBothKindsBindCanonicalBytesAndDistinctRowIdentity',
        'FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testEveryDuplicatedColumnRejectsMismatchForBothKinds',
        'FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testPredecessorDigestCannotBeDroppedOrReplaced',
        'FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testMalformedAndValidDivergentCanonicalPayloadsAreRejected',
        'FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testFileBackedSwiftDataReopenRetainsBothKindsAndRevisions',
    )),
    ('finding-owner-mutation', (
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testFreshHumanCreationDerivesOnlyItsOriginalFacts',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCanonicalCreationMatchesIndependentCommandAndRecordExpectations',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testLegalKernelStringsAndUnicodeTextBytesRemainExact',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCreationOptionalClassificationAndActivityNeverBecomeUniversalIDGates',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCreationRejectsSubstitutedScaleSubjectWorkspaceAndAttribution',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testTransitionDerivesOneRevisionWithoutReplacingAnyOtherFact',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCorrectiveLinkAndRemovalPreserveFindingRevisionAndOriginalSupport',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCorrectiveOperationsRejectWrongRolesRevisionsMissingReadsAndStaleBasis',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testExactPredecessorAndMutationMetadataCannotBeSubstituted',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testVerifiedResolutionRequiresTheExactRetainedPassedRecheck',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCanonicalCommandBindsDependenciesAndAttributionWithoutClaimingAuthenticity',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testClosedCommandAndOperationWireRejectReplacementSourceAndProofFields',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testNestedUnknownFieldsAndNoncanonicalBytesRejectThroughActualCodec',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testRevisionBoundsRejectBeforeLegacyIncrementAndPreserveAssetZero',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testFrontierDuplicateConflictsUnknownIdentitiesAndMissingDependencyFailClosed',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testWholeWorkspaceFrontierExceedsRegistryCountAndRetainsCanonicalByteLimit',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCommandAcceptanceCensusRejectsEveryPredecessorAndSupportOverlap',
        'FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCommandAcceptanceCensusAllowsExactOverlapAndDistinctKeysThroughDerivation',
    )),
    ('shop-profile-open-handoff', (
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testOpenEvidenceManifestCanonicalRoundTripNormalizesArtifactsAndRejectsTampering',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testHandoffPresentationRequiresExactSavedProfileAndRemainsDefaultOff',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04G01DeterministicProfilePresetAndConfirmationBytes',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04A01CustomerSafePackagingAndAccessibleOutputs',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04H01RejectsCorruptStaleUnsafeAndSecondRendererInputs',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04I01InterruptionLeavesZeroOrRecoverableCanonicalEffect',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04R01RestoreCloneForkAndHistoricExportImmutability',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveExactRetryReturnsOriginalReceipt',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveHistoricExactRetryAfterSuccessorReturnsOriginalReceipt',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveDivergentMutationReuseRejectsWithoutChanges',
        'FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveNewStaleMutationRejectsWithoutChanges',
    )),
    ('advanced-recurrence-workflow', (
        'FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38G01PatternsOverridesAndHistoryProjectDeterministically',
        'FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38A01LeapMonthEndLastWeekdayAndScopesPreview',
        'FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38H01InvalidRulesStalePreviewAndIdentityDriftHaveNoEffects',
        'FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38I01DSTClockReminderAndEffectBeforeReceiptRetryExactlyOnce',
        'FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38R01CompletionScheduleChangeReplayAndRestoreRemainStable',
    )),
)
FINDING_PROFILE_FIXTURES_SELECTORS = tuple(
    member for _, members in FINDING_PROFILE_FIXTURES_GROUPS for member in members
)
SAVED_REVIEW_FIELDS_SELECTION_ID = 'c36-saved-review-fields-no-index-build30m'
SAVED_REVIEW_FIELDS_PARENT = '392e4072ee4a2af13c00adf5274fe0cc85b7611a'
SAVED_REVIEW_FIELDS_TREES = {'FieldEvidenceApp': 'ceec35dfeb8f25e34455206977f31d0c3f67bf6f', 'FieldEvidenceAppTests': '1e29182844d0d652b896adf11cb32a6a0d9c5543', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
FIELD_EDIT_SELECTORS = ('FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditsPersistIncompleteValuesAndColdReopenWithoutEffects', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditCASPreservesBeginAndPhotoSlotsAndRejectsFrozenOrForeignState', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditAcknowledgementLossRecoversOriginalBeforeNewerEdits', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldFlushDrainsEditsArrivingDuringAwaitAndAuthenticatesReadback')
SAVED_REVIEW_FIELDS_SELECTORS = ('FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionFreezesOneChoiceAndRecoversOriginalWithoutNewIDs', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionRejectsStaleTargetAndRetiredOwnerWithoutEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardRequiresConfirmationThenReplaysOriginalWithoutConfirmationOrEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardCanCompleteReviewWithoutOperationalRoundAndRejectsRetirement', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceAuthenticatesCurrentPendingAndTerminalOriginalsWithoutReadEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsEverySubstitutedFieldAndNonDraftWithoutEffects', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceReturnsUnsupportedOnlyAfterAuthenticCurrentReceipt', 'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsDirtyCorruptQuarantinedAndRetiredHistoryWithoutEffects', 'FieldEvidenceAppTests/V23ProductionFourRootShellTests/testPhysicalRestoredReviewDiscardUsesProductionAccessAndColdOriginalReadback', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditsPersistIncompleteValuesAndColdReopenWithoutEffects', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditCASPreservesBeginAndPhotoSlotsAndRejectsFrozenOrForeignState', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditAcknowledgementLossRecoversOriginalBeforeNewerEdits', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt', 'FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldFlushDrainsEditsArrivingDuringAwaitAndAuthenticatesReadback')
FIELD_AUTOSAVE_SELECTION_ID = 'c36-field-autosave-no-index-build30m'
FIELD_AUTOSAVE_PARENT = '147da0541cfd6d93dc890fa95b8dd08b2bd4712e'
FIELD_AUTOSAVE_TREES = {'FieldEvidenceApp': '8d3040a6ad649679ece18553ac4226369c075a6a', 'FieldEvidenceAppTests': '86c04f43bb49d5f41c4e3d1385a63087aeeb12f7', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
FIELD_AUTOSAVE_SELECTORS = ('FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt',)
LIVE_HOST_SELECTION_ID = 'c36-live-host-no-index-build30m'
LIVE_HOST_PARENT = '94e9b4f6ef1861079b34fc08009a1063bbfc24cc'
LIVE_HOST_TREES = {'FieldEvidenceApp': '57781115fb9333da7da89a811d2d9a961bf4a38f', 'FieldEvidenceAppTests': '86c04f43bb49d5f41c4e3d1385a63087aeeb12f7', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
ROUND_ITEM_MOUNT_SELECTION_ID = 'c36-round-item-mount-no-index-build30m'
STARTUP_RETIREMENT_SELECTION_ID = 'c36-startup-retirement-no-index-build30m'
STARTUP_RETIREMENT_SELECTORS = (
    'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans',
    'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds',
    'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission',
)
ROUND_ITEM_MOUNT_PARENT = '31126e929bd87545719fd58d355a4d719dcf52ba'
ROUND_ITEM_MOUNT_TREES = {'FieldEvidenceApp': '4b793df000270c23e7392ccd72b99eaef356011a', 'FieldEvidenceAppTests': 'b14500156edef141f1e82242afec7cb65c33f63b', 'FieldEvidenceAppUITests': '978eced2587c6ed6cb280aa6cea7d4e3fa6e4190', 'FieldEvidenceApp.xcodeproj': '4689b1e68b6e5ab1c60c7546fe49a0ff7d1e85d0'}
ROUND_ITEM_COMPLETION_SELECTION_ID = 'c36-round-item-completion-no-index-build30m'
D50_SELECTION_IDS = (LIVE_HOST_SELECTION_ID, ROUND_ITEM_MOUNT_SELECTION_ID, STARTUP_RETIREMENT_SELECTION_ID)
NO_INDEX_ROUTES = {
    LIVE_HOST_SELECTION_ID: (LIVE_HOST_PARENT, "D50"),
    ROUND_ITEM_MOUNT_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, "D50"),
    STARTUP_RETIREMENT_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, "D50"),
    ROUND_ITEM_COMPLETION_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, "D30"),
    FIELD_AUTOSAVE_SELECTION_ID: (FIELD_AUTOSAVE_PARENT, "D30"),
    NOTIFICATION_INTERRUPTION_SELECTION_ID: (NOTIFICATION_INTERRUPTION_PARENT, "D30"),
    SAVED_REVIEW_FIELDS_SELECTION_ID: (SAVED_REVIEW_FIELDS_PARENT, "D30"),
    FINDING_PROFILE_FIXTURES_SELECTION_ID: (FINDING_PROFILE_FIXTURES_PARENT, "D30"),
    NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID: (NOTIFICATION_SCHEDULE_ERASE_BUILD30_PARENT, "D30"),
    ACTIVITY_COMPLETED_SOURCE_SELECTION_ID: (ACTIVITY_COMPLETED_SOURCE_PARENT, "D30"),
    ACTIVITY_CODEC_PUNCH_SELECTION_ID: (REPLACEMENT_UNION_PARENT, "D30"),
    ACTIVITY_BUILD30_SELECTION_ID: (REPLACEMENT_UNION_PARENT, "D30"),
    REPLACEMENT_UNION_SELECTION_ID: (REPLACEMENT_UNION_PARENT, "D30"),
    **{key: (REPLACEMENT_UNION_PARENT, "D30") for key, _ in REPLACEMENT_DIAGNOSTIC_PARTITIONS},
    ERASE_DRAIN_SELECTION_ID: (ERASE_PARTITION_PARENT, "D30"),
    ERASE_REMAINDER_SELECTION_ID: (ERASE_PARTITION_PARENT, "D30"),
    ERASE_BUILD_WATCHDOG_SELECTION_ID: (ERASE_BUILD_WATCHDOG_PARENT, "D30"),
    RESTORE_HISTORY_SELECTION_ID: (RESTORE_HISTORY_PARENT, "D30"),
    NO_INDEX_SELECTION_ID: (NO_INDEX_PARENT, "N8"),
    RESTORE_BUILD_WATCHDOG_SELECTION_ID: (RESTORE_BUILD_WATCHDOG_PARENT, "D30"),
    REMINDER_BUILD_WATCHDOG_SELECTION_ID: (REMINDER_BUILD_WATCHDOG_PARENT, "D30"),
}
# Reusable development-only D50 no-index route. Its exact ordered unit methods come
# only from one committed file at the dispatched head, so a new development question
# needs no selector, parent/tree pin or manifest change. It pins no parent or trees:
# the selected evidence binds the file digest and ordered list, and the admission
# binds the head. Never acceptance, provider qualification, coverage or merge credit.
DEV_BATCH_SELECTION_ID = "v23-dev-batch-no-index-d50"
DEV_BATCH_PATH = "Scripts/v23-dev-batch.json"
DEV_BATCH_SCHEMA = "v23-dev-batch.v1"
DEV_BATCH_KEY = "devBatch"
DEV_BATCH_TIER = "D50"
DEV_BATCH_MAX_TESTS = 150
DEV_BATCH_MAX_QUESTION = 500
DEV_BATCH_MAX_BYTES = 128 * 1024
DEV_BATCH_TEST = re.compile(r"FieldEvidenceAppTests/([A-Za-z_][A-Za-z0-9_]*)/(test[A-Za-z0-9_]*)")
DEV_BATCH_BINDING_KEYS = {"path", "schema", "sha256", "question", "developmentOnly", "acceptance"}
# Owner-approved development-only shared coverage route (2026-09-25): one no-index
# build-for-testing producer seals its products once; test-only consumers restore the
# exact bytes and run one closed partition each. The partitions file must cover every
# direct runnable XCTest method at the checkout. Never acceptance or merge credit.
SHARED_SELECTION_ID = "v23-shared-coverage-d50x"
SHARED_PARTITIONS_PATH = "Scripts/v23-coverage-partitions.json"
SHARED_PARTITIONS_SCHEMA = "v23-coverage-partitions.v2"
SHARED_KEY = "sharedCoverage"
SHARED_PRODUCER_TIER = "D40P"
SHARED_CONSUMER_TIER = "D50C"
# A solo consumer partition (exactly one selector) of a known-slow method; every other
# consumer partition keeps the D50C test budget. Each partition names its tier.
SHARED_SOLO_TIER = "D90S"
SHARED_CONSUMER_TIERS = (SHARED_CONSUMER_TIER, SHARED_SOLO_TIER)
SHARED_ROLES = ("producer", "consumer")
SHARED_MAX_PARTITIONS = 60
SHARED_MAX_PARTITION_METHODS = 500
SHARED_MAX_PARTITIONS_BYTES = 4 * 1024 * 1024
SHARED_PARTITION_ID = re.compile(r"S[0-9]{2}")
SHARED_BINDING_KEYS = {"partitionsPath", "partitionsSHA256", "partitionIDs", "partitionID",
                       "developmentOnly", "acceptance"}
SHARED_PAYLOAD_KERNEL = "Scripts/s10-4-build-payload.py"
SHARED_PAYLOAD_SCHEMA = "v23-shared-payload.v1"
SHARED_PAYLOAD_METADATA = "v23-shared-payload.json"
SHARED_PAYLOAD_RECEIPT = "v23-shared-payload-receipt.json"
SHARED_RESTORE_RECEIPT = "v23-shared-restore.json"
SHARED_FINGERPRINT_PHASES = ("before", "after")
SHARED_PAYLOAD_DIRECTORY = "V23SharedPayload"
SHARED_TRANSPORT_DIRECTORY = "V23SharedPayloadTransport"
SHARED_DOWNLOAD_DIRECTORY = "V23SharedPayloadDownload"
SHARED_EXTRACTED_DIRECTORY = "V23SharedPayloadExtracted"
SHARED_TAR = "FieldEvidencePayload.tar"
SHARED_TAR_DIGEST = "FieldEvidencePayload.tar.sha256"
# The route runs in its own small reusable worker (GitHub counts every called template
# once per calling job); its sources are bound into the route's checkpoint evidence.
SHARED_WORKER_SOURCES = (".github/workflows/ios-ci-shared-worker.yml", "Scripts/v23-shared-worker.sh")
# After tests, the scheme command may leave build bookkeeping (Logs, XCBuildData, PIFCache)
# in DerivedData without compiling; only compiler or linker evidence fails a consumer, and
# every other new DerivedData entry is listed in the delta record.
SHARED_DERIVED_DATA_DELTA = "v23-shared-deriveddata-delta.json"
SHARED_COMPILE_OUTPUT_SUFFIXES = (".o", ".swiftmodule", ".swiftdeps", ".dia")
SHARED_COMPILE_STEPS = ("CompileSwift", "CompileSwiftSources", "SwiftCompile", "SwiftDriver",
                        "SwiftDriverJobDiscovery", "SwiftEmitModule", "CompileC", "Ld", "Libtool")
# An .xcactivitylog is gzip-compressed SLF text whose step signatures are plain strings.
SHARED_ACTIVITY_COMPILE_STEP = re.compile(
    rb"(?<![A-Za-z0-9_])(" + b"|".join(step.encode() for step in SHARED_COMPILE_STEPS) + rb") ")
SHARED_LOG_COMPILE_STEP = re.compile(r"(?:" + "|".join(SHARED_COMPILE_STEPS) + r") ")
SHARED_LOG_BUILD_RESULT = re.compile(r"\*\* (?:TEST )?BUILD (?:SUCCEEDED|FAILED|INTERRUPTED) \*\*")
SHARED_LOG_BUILTINS = ("builtin-SwiftDriver", "builtin-swiftTaskExecution")
SHARED_LOG_TOOLS = ("swiftc", "swift-frontend", "clang", "clang++", "ld", "libtool")
SHARED_MAX_ACTIVITY_LOG_BYTES = 1024 * 1024 * 1024
SHARED_MAX_TEST_LOG_BYTES = 256 * 1024 * 1024
SHARED_MAX_LISTED_EVIDENCE = 20
SHARED_MAX_DELTA_ENTRIES = 20000


def no_index_source_trees(selection_id):
    require(selection_id in NO_INDEX_ROUTES, "no-index closed source binding")
    if selection_id == LIVE_HOST_SELECTION_ID:
        return LIVE_HOST_TREES
    if selection_id in (ROUND_ITEM_MOUNT_SELECTION_ID, STARTUP_RETIREMENT_SELECTION_ID,
                        ROUND_ITEM_COMPLETION_SELECTION_ID):
        return ROUND_ITEM_MOUNT_TREES
    if selection_id == FIELD_AUTOSAVE_SELECTION_ID:
        return FIELD_AUTOSAVE_TREES
    if selection_id == NOTIFICATION_INTERRUPTION_SELECTION_ID:
        return NOTIFICATION_INTERRUPTION_TREES
    if selection_id == SAVED_REVIEW_FIELDS_SELECTION_ID:
        return SAVED_REVIEW_FIELDS_TREES
    if selection_id == FINDING_PROFILE_FIXTURES_SELECTION_ID:
        return FINDING_PROFILE_FIXTURES_TREES
    if selection_id == NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID:
        return NOTIFICATION_SCHEDULE_ERASE_BUILD30_TREES
    if selection_id == ACTIVITY_COMPLETED_SOURCE_SELECTION_ID:
        return ACTIVITY_COMPLETED_SOURCE_TREES
    if selection_id in (ACTIVITY_CODEC_PUNCH_SELECTION_ID, ACTIVITY_BUILD30_SELECTION_ID, REPLACEMENT_UNION_SELECTION_ID, *(key for key, _ in REPLACEMENT_DIAGNOSTIC_PARTITIONS)):
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
PRE_SAVED_REVIEW_PROFILE = 'finding-profile-fixtures-v1'
PRE_SAVED_REVIEW_POOL_SHA256 = 'CDD7411107440470C44C2AA29AC2C8139B44BBF1D7DD7F9A55D06221FE9D517E'
PRE_SAVED_REVIEW_MAP_SHA256 = '316967E3CF0BF31ED1F1DFE05A118D041A61C7E3FA756C35637E226506008D5B'
SAVED_REVIEW_PROFILE = 'saved-review-discard-v1'
GENERATED_SELECTION_PROFILE = 'saved-review-fields-v1'
SAVED_REVIEW_POOL_SHA256 = 'A45F6BA826036252B8FFAE2C1B94FB599CA59FCAAA75CF5ACA09F1A5277A9DE1'
GENERATED_SELECTION_POOL_SHA256 = '157EAC0BDF9CC6CA18CDA479CC504B2577BF9E59A6FFEECA53A05A55DF8A3A5B'
SAVED_REVIEW_MAP_SHA256 = 'C4CC0CE51ECE1A2920E9B809ECA1210A4507D341579255FE8A7C998024DEF43F'
GENERATED_SELECTION_MAP_SHA256 = 'FB051F042006598DF8C07FA8F7125AA7BA4916626C1B7DAF10824ED1FC691758'
SAVED_REVIEW_SELECTION_ID = 'c36-saved-review-discard'
SAVED_REVIEW_NEW_SELECTORS = (
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceAuthenticatesCurrentPendingAndTerminalOriginalsWithoutReadEffects',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsEverySubstitutedFieldAndNonDraftWithoutEffects',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceReturnsUnsupportedOnlyAfterAuthenticCurrentReceipt',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsDirtyCorruptQuarantinedAndRetiredHistoryWithoutEffects',
    'FieldEvidenceAppTests/V23ProductionFourRootShellTests/testPhysicalRestoredReviewDiscardUsesProductionAccessAndColdOriginalReadback',
)
SAVED_REVIEW_REGRESSION_SELECTORS = (
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionFreezesOneChoiceAndRecoversOriginalWithoutNewIDs',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionRejectsStaleTargetAndRetiredOwnerWithoutEffects',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardRequiresConfirmationThenReplaysOriginalWithoutConfirmationOrEffects',
    'FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardCanCompleteReviewWithoutOperationalRoundAndRejectsRetirement',
)
SAVED_REVIEW_SELECTORS = SAVED_REVIEW_REGRESSION_SELECTORS + SAVED_REVIEW_NEW_SELECTORS
LIVE_HOST_PROFILE = 'live-host-v1'
LIVE_HOST_POOL_SHA256 = '5B672136EC763EABF8C478751B43AD95EC9691491B001B1C11B67B0B23BC133C'
LIVE_HOST_MAP_SHA256 = '173827019D64F5D1940C09D5D2571DD13B0E74C31D27E32D15E1E6D31297D551'
LIVE_HOST_NEW_SELECTORS = ('FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldOperationAuthoritySurvivesSuspensionAndRecoversOriginalReceipt', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardPreparationReopensOriginalPendingReceipt', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardValuesRetainOriginalStagesAndRejectCommit', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testDurablePreflightSubmitsConfirmedEnteredTimeZoneWithoutRewritingSavedInput', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveFinalizationUsesOriginalReceiptAndRejectsRetiredOperation', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLivePhotoRejectsRetiredPublicationAndRecoversOriginalCommitReceipt', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveItemFactoryAndEditorKeepOriginalPublicationWithoutCreatingStaging', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalPublishesOnceAndRetainsAuthenticRetryReceipt', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsTargetAppearingAfterPreparation', 'FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsSubstitutionAndCancellation')
LIVE_HOST_RUNTIME_SELECTORS = LIVE_HOST_NEW_SELECTORS + ('FieldEvidenceAppTests/S8_2GoldenAccessibilityTests/testGoldenFlowAccessibilitySpineAndControlMetricsAreExact',)
LIVE_HOST_SELECTORS = ('FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardPreparationReopensOriginalPendingReceipt', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardValuesRetainOriginalStagesAndRejectCommit', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testDurablePreflightSubmitsConfirmedEnteredTimeZoneWithoutRewritingSavedInput', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveFinalizationUsesOriginalReceiptAndRejectsRetiredOperation', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLivePhotoRejectsRetiredPublicationAndRecoversOriginalCommitReceipt', 'FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveItemFactoryAndEditorKeepOriginalPublicationWithoutCreatingStaging')
ROUND_ITEM_MOUNT_PROFILE = 'round-item-mount-v1'
ROUND_ITEM_MOUNT_POOL_SHA256 = 'ED9EFF3F8C8EAA5EB51FF765787473A8F915F7A5D6D6020D6C851FE764921965'
ROUND_ITEM_MOUNT_MAP_SHA256 = '7C9E12972AF8926C455328E1BD0DB4059220BD35A024645CDCAE51448186948C'
ROUND_ITEM_MOUNT_SELECTORS = tuple('FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/' + method
    for method in (
        'testContinueLaunchesEntersOnceOpensDurableHostAndColdReopenAddsNoWrites',
        'testContinueDeniesDraftPausedAndCompetingSourcesWithoutEffects',
        'testForeignCanonicalDraftDeniesEntryBeforeAnyWrite',
        'testContinueRecoversSourceAndEntryAcknowledgementLossWithOneOfEach',
        'testPendingEffectForAnotherItemIsNotSettledByAnOutOfOrderTap',
        'testRevisionPinnedRouteRetargetsThenReusesEntryAndBegunParentReopens',
        'testInterruptedPreparedBeginReopensForExplicitRecoveryAndCompletesOnce',
    ))
ROUND_ITEM_COMPLETION_PROFILE = 'round-item-completion-v1'
ROUND_ITEM_COMPLETION_POOL_SHA256 = 'AA6FED058B963A5110857E98FD68573DCA72F20FD8D0BD19B7A50B252E957A7B'
ROUND_ITEM_COMPLETION_MAP_SHA256 = '2872B03CDC17B8C001CA351411FBF10954063B09F052146BECAC81BE8E831FB0'
ROUND_ITEM_COMPLETION_SELECTORS = tuple('FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/' + method
    for method in (
        'testCouldNotVerifyFinishRecordsOneReportAndOneCompleteThenShowsNextItem',
        'testLostFinalizationAndCompleteAcknowledgementsResumeOriginalsOnce',
        'testDeferAndKeepOpenRetainParentsAndAdvanceOnce',
        'testRetiredSceneDeniesFinishAndAdvanceWithoutEffects',
        'testTwoPhotoJourneyCommitsEachSlotOnceRecoversAndFinishes',
        'testStoragePublicationAcceptsFreeByteDriftOnlyWithTheSameVerdict',
    ))
ROUND_READINESS_SELECTORS = tuple('FieldEvidenceAppTests/V23ProductionRoundReadinessTests/' + method
    for method in (
        'testActualRoundRoutesReadEveryWriterFrontierWithoutStartingOrResuming',
        'testActualRoundReadinessPublishesExactSessionAndRejectsWriterAndFinalCoverRaces',
        'testActualRoundFinalPublicationRejectsChangedNilRevisionFrontier',
        'testActualNativeRoundRouteAndBackPreserveReportsWithoutAutomaticWork',
        'testActualRoundOldPublicationCannotReadAfterFreshSceneActivation',
        'testReadinessPreFinalHookRejectionDoesNotCarryHookOrWriteIntoNextOperation',
    ))
ROUND_ITEM_COMPLETION_QUESTION_SELECTORS = ROUND_ITEM_COMPLETION_SELECTORS + ROUND_READINESS_SELECTORS
GENERATED_PROFILE_PINS = {
    ROUND_ITEM_COMPLETION_POOL_SHA256: (ROUND_ITEM_COMPLETION_PROFILE, ROUND_ITEM_COMPLETION_MAP_SHA256),
    ROUND_ITEM_MOUNT_POOL_SHA256: (ROUND_ITEM_MOUNT_PROFILE, ROUND_ITEM_MOUNT_MAP_SHA256),
    LIVE_HOST_POOL_SHA256: (LIVE_HOST_PROFILE, LIVE_HOST_MAP_SHA256),
    SAVED_REVIEW_POOL_SHA256: (SAVED_REVIEW_PROFILE, SAVED_REVIEW_MAP_SHA256),
    GENERATED_SELECTION_POOL_SHA256: (GENERATED_SELECTION_PROFILE, GENERATED_SELECTION_MAP_SHA256),
    PRE_SAVED_REVIEW_POOL_SHA256: (PRE_SAVED_REVIEW_PROFILE, PRE_SAVED_REVIEW_MAP_SHA256),
}
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
SIMULATOR_DIAGNOSTIC_SOURCE_SHA256 = "831C0FB85219183E7CA694F4F260BBB4765FFD929EBCCAE814CE7CC3D231C5B7"
# The original owner-approved allowance source remains admissible for historical replays;
# the current source adds only development timing aggregates (2026-09-24).
# 2026-09-25: the Simulator strict pre-check no longer throws, catches and logs the expected
# mismatch on every call; the fallback predicate, journal and evidence are unchanged.
# 2026-09-25 (owner decision 15): repeats of a kind are journaled as per-kind summaries after
# its exact first event; the fallback predicate and every verification are unchanged. The pin
# is SHA-256 over the committed ProtectedFilePolicy.swift bytes; D18D48D5... joins the history.
SIMULATOR_DIAGNOSTIC_HISTORICAL_SOURCE_SHA256S = ("FCFF658FCE118760EAC50B13A3941470EA86ED6FB40E78D17E6A573A10DFA5DB",
                                                 "A8B18FFF49DE387183EA9B8B2377669BF1EE9E73A6DB11992178503070EDE139",
                                                 "D18D48D5DB47DD61AD7D979414BD62A1A6798639EDA00B537DB5D6F1D517700E")
SIMULATOR_DIAGNOSTIC_PREFIX = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_V2"
# Owner decision 15 (2026-09-25): after the first exact event of a kind in a process, later
# identical events of that kind are journaled as bounded per-kind summaries carrying a count.
# The V2 payload is a pure function of the kind, so a summary loses only call order and time.
SIMULATOR_DIAGNOSTIC_SUMMARY_PREFIX = "V23_SIMULATOR_FILE_PROTECTION_DIAGNOSTIC_SUMMARY_V1"
SIMULATOR_DIAGNOSTIC_MAX_SUMMARY_OCCURRENCES = 1_000_000_000
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
    require(sha256(source_bytes) in (SIMULATOR_DIAGNOSTIC_SOURCE_SHA256,
                                     *SIMULATOR_DIAGNOSTIC_HISTORICAL_SOURCE_SHA256S),
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
    return _parse_simulator_diagnostic(line, SIMULATOR_DIAGNOSTIC_PREFIX, SIMULATOR_DIAGNOSTIC_FIELDS)[0]


def parse_simulator_diagnostic_summary_line(line):
    """One per-kind summary: the exact V2 facts of that kind plus how many more calls had them."""
    event, values = _parse_simulator_diagnostic(
        line, SIMULATOR_DIAGNOSTIC_SUMMARY_PREFIX, SIMULATOR_DIAGNOSTIC_FIELDS + ("occurrences",))
    count = values["occurrences"]
    require(re.fullmatch(r"[1-9][0-9]{0,9}", count) is not None
            and int(count) <= SIMULATOR_DIAGNOSTIC_MAX_SUMMARY_OCCURRENCES,
            "simulator diagnostic summary occurrences")
    return event, int(count)


def _parse_simulator_diagnostic(line, prefix, fields):
    stripped = line.strip()
    require(stripped.startswith(prefix + " "),
            "malformed simulator diagnostic marker")
    require(stripped.count(prefix) == 1 and stripped.count(SIMULATOR_DIAGNOSTIC_MARKER_STEM) == 1,
            "duplicate simulator diagnostic marker")
    tokens = stripped.split()
    require(tokens[0] == prefix and len(tokens) == 1 + len(fields),
            "simulator diagnostic field count")
    pairs = []
    for token in tokens[1:]:
        key, separator, value = token.partition("=")
        require(bool(separator) and bool(key) and bool(value), "simulator diagnostic field")
        pairs.append((key, value))
    values = unique_pairs(pairs)
    require(tuple(values) == fields, "simulator diagnostic field order")
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
    }, values


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
    text = payload.decode("utf-8")
    if text.startswith(SIMULATOR_DIAGNOSTIC_SUMMARY_PREFIX + " "):
        event, occurrences = parse_simulator_diagnostic_summary_line(text)
        return value, payload, event, occurrences
    return value, payload, parse_simulator_diagnostic_line(text), None


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
        "summaries": [],
        "occurrenceCount": 0,
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
            summaries = []
            raw_records = []
        else:
            require(files and transport_dir.is_dir() and not transport_dir.is_symlink(),
                    "diagnostic transport directory")
            require(sorted(value.name for value in transport_dir.iterdir())
                    == [value["name"] for value in files], "diagnostic transport members")
            events, summaries, raw_records, seen_streams = [], [], [], set()
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
                        and len(raw_records) + len(lines) <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_EVENTS,
                        "diagnostic event count")
                stream_id = name[:-6]
                require(stream_id not in seen_streams, "duplicate diagnostic stream")
                seen_streams.add(stream_id)
                for expected_sequence, line in enumerate(lines, 1):
                    frame, payload, event, occurrences = _strict_frame(line)
                    require(frame["streamID"] == stream_id
                            and frame["sequence"] == expected_sequence,
                            "diagnostic stream sequence")
                    if occurrences is None:
                        events.append(event)
                    else:
                        summaries.append({**event, "occurrences": occurrences})
                    raw_records.append({
                        "streamID": stream_id, "sequence": expected_sequence,
                        "payloadByteCount": len(payload), "payloadSHA256": sha256(payload),
                    })
                expected_names.append(name)
            require(expected_names == sorted(expected_names), "diagnostic inventory order")
            # A summary only counts further calls of a kind whose first exact event was journaled
            # durably. Streams are named by random identifiers, so this binding is order-free.
            exact_kinds = {event["kind"] for event in events}
            require(all(summary["kind"] in exact_kinds for summary in summaries),
                    "diagnostic summary without exact first event")
        evidence["parseStatus"] = "PASS"
        evidence["events"] = events
        evidence["rawRecords"] = raw_records
        evidence["eventCount"] = len(events)
        evidence["summaries"] = summaries
        evidence["occurrenceCount"] = len(events) + sum(value["occurrences"] for value in summaries)
        evidence["zeroUseObserved"] = status["status"] == "ZERO_USE"
    except (UnicodeDecodeError, json.JSONDecodeError, OSError, TypeError, ValueError) as error:
        evidence["parseStatus"] = "INVALID"
        evidence["events"] = events if "events" in locals() else []
        evidence["rawRecords"] = raw_records if "raw_records" in locals() else []
        evidence["eventCount"] = len(evidence["events"])
        evidence["summaries"] = summaries if "summaries" in locals() else []
        evidence["occurrenceCount"] = len(evidence["events"]) + sum(
            value["occurrences"] for value in evidence["summaries"])
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


def development_batch_question(value):
    return (type(value) is str and bool(value.strip()) and len(value) <= DEV_BATCH_MAX_QUESTION
            and re.search(r"[\x00-\x1f\x7f]", value) is None)


def validate_development_batch_binding(binding, selectors):
    require(type(binding) is dict and set(binding) == DEV_BATCH_BINDING_KEYS,
            "development batch binding keys")
    require(binding["path"] == DEV_BATCH_PATH and binding["schema"] == DEV_BATCH_SCHEMA,
            "development batch binding identity")
    require(isinstance(binding["sha256"], str) and re.fullmatch(r"[0-9A-F]{64}", binding["sha256"]),
            "development batch file digest")
    require(development_batch_question(binding["question"]), "development batch question")
    require(binding["developmentOnly"] is True and binding["acceptance"] is False,
            "development batch classification")
    require(1 <= len(selectors) <= DEV_BATCH_MAX_TESTS, "development batch test count")


def validate_shared_binding(selection):
    binding = selection[SHARED_KEY]
    require(type(binding) is dict and set(binding) == SHARED_BINDING_KEYS, "shared coverage binding keys")
    require(binding["partitionsPath"] == SHARED_PARTITIONS_PATH
            and isinstance(binding["partitionsSHA256"], str)
            and re.fullmatch(r"[0-9A-F]{64}", binding["partitionsSHA256"]),
            "shared coverage partitions identity")
    identifiers = binding["partitionIDs"]
    require(type(identifiers) is list and 1 <= len(identifiers) <= SHARED_MAX_PARTITIONS
            and all(isinstance(item, str) and SHARED_PARTITION_ID.fullmatch(item) for item in identifiers)
            and len(set(identifiers)) == len(identifiers), "shared coverage partition IDs")
    require(binding["developmentOnly"] is True and binding["acceptance"] is False,
            "shared coverage classification")
    if selection["tier"] == SHARED_PRODUCER_TIER:
        require(binding["partitionID"] is None, "shared coverage producer has no partition")
    else:
        require(selection["tier"] in SHARED_CONSUMER_TIERS and binding["partitionID"] in identifiers
                and 1 <= len(selection["unitTestSelectors"]) <= SHARED_MAX_PARTITION_METHODS,
                "shared coverage consumer partition")
        require(selection["tier"] != SHARED_SOLO_TIER or len(selection["unitTestSelectors"]) == 1,
                "shared coverage solo tier needs exactly one method")


def validate_selection(selection):
    require(isinstance(selection, dict), "selection object")
    development_batch = DEV_BATCH_KEY in selection
    shared = SHARED_KEY in selection
    keys = {"schemaVersion", "taskID", "tier", "runUISmoke",
            "unitTestSelectors", "uiTestSelectors", *BUDGET_KEYS}
    require(set(selection) == ((keys | {DEV_BATCH_KEY}) if development_batch
                               else (keys | {SHARED_KEY}) if shared else keys), "selection keys")
    require(type(selection["schemaVersion"]) is int and selection["schemaVersion"] == 1, "schema")
    require(selection["taskID"] == TASK and selection["tier"] in TIERS, "task/tier")
    require(all(type(selection[key]) is int for key in BUDGET_KEYS), "integer budgets")
    require(tuple(selection[key] for key in BUDGET_KEYS) == TIERS[selection["tier"]], "budgets")
    ui = selection["tier"] not in NO_UI_TIERS
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
    if development_batch:
        # Shape only; admission binds this list to the committed file at the head.
        require(selection["tier"] == DEV_BATCH_TIER, "development batch tier")
        validate_development_batch_binding(selection[DEV_BATCH_KEY], selection["unitTestSelectors"])
    elif shared:
        # Shape only; admission binds the plan or partition to the checked-in file.
        validate_shared_binding(selection)
    elif selection["tier"] == "D50":
        require(tuple(selection["unitTestSelectors"]) in (LIVE_HOST_RUNTIME_SELECTORS,
                ROUND_ITEM_MOUNT_SELECTORS, STARTUP_RETIREMENT_SELECTORS),
                "development D50 exact closed methods")
    require(shared or selection["tier"] not in (SHARED_PRODUCER_TIER,) + SHARED_CONSUMER_TIERS,
            "shared coverage tier outside the shared route")
    if selection["tier"] == "D30":
        require(tuple(selection["unitTestSelectors"]) in (
            PARENT_FINALIZATION_METHOD_PARTITIONS[0][1], RESTORE_BUILD_WATCHDOG_SELECTORS,
            REMINDER_BUILD_WATCHDOG_SELECTORS, RESTORE_HISTORY_SELECTORS, REPLACEMENT_UNION_SELECTORS, ERASE_RECOVERY_SELECTORS, ACTIVITY_CONTRACT_SELECTORS, ACTIVITY_CODEC_PUNCH_SELECTORS, ACTIVITY_COMPLETED_SOURCE_SELECTORS,
            NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTORS, NOTIFICATION_INTERRUPTION_SELECTORS, FINDING_PROFILE_FIXTURES_SELECTORS, SAVED_REVIEW_FIELDS_SELECTORS, FIELD_AUTOSAVE_SELECTORS, LIVE_HOST_RUNTIME_SELECTORS,
            ROUND_ITEM_COMPLETION_QUESTION_SELECTORS,
            *(members for _, members in ERASE_DIAGNOSTIC_PARTITIONS),
            *(members for _, members in REPLACEMENT_DIAGNOSTIC_PARTITIONS)),
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
        isinstance(groups, list) and len(groups) in (68, 69, 70, 71, 72)
        and (sha256(canonical(default)), sha256(canonical(selection_map))) in (
            (SAVED_REVIEW_POOL_SHA256, SAVED_REVIEW_MAP_SHA256),
            (GENERATED_SELECTION_POOL_SHA256, GENERATED_SELECTION_MAP_SHA256),
            (LIVE_HOST_POOL_SHA256, LIVE_HOST_MAP_SHA256),
            (ROUND_ITEM_MOUNT_POOL_SHA256, ROUND_ITEM_MOUNT_MAP_SHA256),
            (ROUND_ITEM_COMPLETION_POOL_SHA256, ROUND_ITEM_COMPLETION_MAP_SHA256),
            (PRE_SAVED_REVIEW_POOL_SHA256, PRE_SAVED_REVIEW_MAP_SHA256))
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
                    (GENERATED_SELECTION_POOL_SHA256, GENERATED_SELECTION_MAP_SHA256),
                    (LIVE_HOST_POOL_SHA256, LIVE_HOST_MAP_SHA256),
                    (ROUND_ITEM_MOUNT_POOL_SHA256, ROUND_ITEM_MOUNT_MAP_SHA256),
                    (ROUND_ITEM_COMPLETION_POOL_SHA256, ROUND_ITEM_COMPLETION_MAP_SHA256),
                    (PRE_SAVED_REVIEW_POOL_SHA256, PRE_SAVED_REVIEW_MAP_SHA256),
                    (SAVED_REVIEW_POOL_SHA256, SAVED_REVIEW_MAP_SHA256)),
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
    if generated_profile_shape:
        members = tuple(resolved["notification-schedule-erase"]["unitTestSelectors"])
        require(members == NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTORS
                and len(members) == len(set(members)) == 28,
                "notification schedule erase exact ordered complete family")
        require(NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID not in resolved,
                "notification schedule erase distinct selection")
        diagnostic = dict(resolved["notification-schedule-erase"])
        diagnostic.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(diagnostic)
        resolved[NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID] = diagnostic
        interruption_members = tuple(member for member in members
                                     if member in NOTIFICATION_INTERRUPTION_SELECTORS)
        require(interruption_members == NOTIFICATION_INTERRUPTION_SELECTORS
                and len(interruption_members) == len(set(interruption_members)) == 2,
                "notification interruption exact ordered existing subset")
        require(NOTIFICATION_INTERRUPTION_SELECTION_ID not in resolved,
                "notification interruption distinct selection")
        interruption = dict(diagnostic, unitTestSelectors=list(interruption_members))
        validate_selection(interruption)
        resolved[NOTIFICATION_INTERRUPTION_SELECTION_ID] = interruption
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
        if generated_profile_shape:
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
            for partition_id, partition_members in REPLACEMENT_DIAGNOSTIC_PARTITIONS:
                require(partition_id not in resolved, "replacement partition distinct selection")
                partition = dict(replacement, unitTestSelectors=list(partition_members))
                validate_selection(partition)
                resolved[partition_id] = partition
            require(tuple(resolved["activity-contracts"]["unitTestSelectors"]) == ACTIVITY_CONTRACT_SELECTORS,
                    "activity exact existing H01 method")
            require(ACTIVITY_BUILD30_SELECTION_ID not in resolved, "activity D30 distinct selection")
            activity = dict(replacement, unitTestSelectors=list(ACTIVITY_CONTRACT_SELECTORS))
            validate_selection(activity)
            resolved[ACTIVITY_BUILD30_SELECTION_ID] = activity
            require(tuple(resolved["activity-codec-evolution"]["unitTestSelectors"]) == ACTIVITY_CODEC_SELECTORS
                    and tuple(item for item in default["unitTestSelectors"] if item in PUNCH_CONTEXT_SELECTORS)
                    == PUNCH_CONTEXT_SELECTORS
                    and len(ACTIVITY_CODEC_PUNCH_SELECTORS) == len(set(ACTIVITY_CODEC_PUNCH_SELECTORS)) == 16
                    and set(ACTIVITY_CODEC_PUNCH_SELECTORS) <= defaults,
                    "activity codec Punch exact ordered enrolled union")
            require(ACTIVITY_CODEC_PUNCH_SELECTION_ID not in resolved, "activity codec Punch distinct selection")
            combined = dict(activity, unitTestSelectors=list(ACTIVITY_CODEC_PUNCH_SELECTORS))
            validate_selection(combined)
            resolved[ACTIVITY_CODEC_PUNCH_SELECTION_ID] = combined
            require(all(tuple(resolved[group]["unitTestSelectors"]) == members
                        for group, members in ACTIVITY_COMPLETED_SOURCE_GROUPS)
                    and len(ACTIVITY_COMPLETED_SOURCE_SELECTORS) == len(set(ACTIVITY_COMPLETED_SOURCE_SELECTORS)) == 63
                    and set(ACTIVITY_COMPLETED_SOURCE_SELECTORS) <= defaults,
                    "activity completed source exact ordered enrolled union")
            require(ACTIVITY_COMPLETED_SOURCE_SELECTION_ID not in resolved,
                    "activity completed source distinct selection")
            completed = dict(activity, unitTestSelectors=list(ACTIVITY_COMPLETED_SOURCE_SELECTORS))
            validate_selection(completed)
            resolved[ACTIVITY_COMPLETED_SOURCE_SELECTION_ID] = completed
    if generated_profile_shape:
        require(all(tuple(resolved[group]["unitTestSelectors"]) == members
                    for group, members in FINDING_PROFILE_FIXTURES_GROUPS)
                and len(FINDING_PROFILE_FIXTURES_SELECTORS) == len(set(FINDING_PROFILE_FIXTURES_SELECTORS)) == 86
                and tuple(default["unitTestSelectors"][968:1054]) == FINDING_PROFILE_FIXTURES_SELECTORS,
                "finding/profile fixtures exact ordered enrolled union")
        require(FINDING_PROFILE_FIXTURES_SELECTION_ID not in resolved,
                "finding/profile fixtures distinct selection")
        finding = dict(default, unitTestSelectors=list(FINDING_PROFILE_FIXTURES_SELECTORS))
        finding.update(tier="D30", **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(finding)
        resolved[FINDING_PROFILE_FIXTURES_SELECTION_ID] = finding
    if generated_profile_shape and sha256(canonical(default)) in (SAVED_REVIEW_POOL_SHA256, GENERATED_SELECTION_POOL_SHA256, LIVE_HOST_POOL_SHA256,
                                                                   ROUND_ITEM_MOUNT_POOL_SHA256,
                                                                   ROUND_ITEM_COMPLETION_POOL_SHA256):
        require(tuple(default["unitTestSelectors"][1054:1059]) == SAVED_REVIEW_NEW_SELECTORS
                and tuple(default["unitTestSelectors"][773:777]) == SAVED_REVIEW_REGRESSION_SELECTORS
                and tuple(resolved["c36-production-destination"]["unitTestSelectors"])
                    == SAVED_REVIEW_REGRESSION_SELECTORS + SAVED_REVIEW_NEW_SELECTORS[:4]
                and SAVED_REVIEW_NEW_SELECTORS[4] in resolved["app-myday-production"]["unitTestSelectors"]
                and len(SAVED_REVIEW_SELECTORS) == len(set(SAVED_REVIEW_SELECTORS)) == 9,
                "saved review exact ordered enrolled union")
        require(SAVED_REVIEW_SELECTION_ID not in resolved, "saved review distinct selection")
        saved_review = dict(default, unitTestSelectors=list(SAVED_REVIEW_SELECTORS))
        validate_selection(saved_review)
        resolved[SAVED_REVIEW_SELECTION_ID] = saved_review
    if generated_profile_shape and sha256(canonical(default)) in (GENERATED_SELECTION_POOL_SHA256, LIVE_HOST_POOL_SHA256,
                                                                   ROUND_ITEM_MOUNT_POOL_SHA256,
                                                                   ROUND_ITEM_COMPLETION_POOL_SHA256):
        round_item_completion = sha256(canonical(default)) == ROUND_ITEM_COMPLETION_POOL_SHA256
        round_item_mount = round_item_completion or sha256(canonical(default)) == ROUND_ITEM_MOUNT_POOL_SHA256
        live_host = round_item_mount or sha256(canonical(default)) == LIVE_HOST_POOL_SHA256
        expected_fields = FIELD_EDIT_SELECTORS + ((LIVE_HOST_NEW_SELECTORS[0],) if live_host else ())
        require(tuple(default["unitTestSelectors"][1059:1064]) == FIELD_EDIT_SELECTORS
                and tuple(resolved["c36-field-edit"]["unitTestSelectors"]) == expected_fields
                and SAVED_REVIEW_FIELDS_SELECTORS == SAVED_REVIEW_SELECTORS + FIELD_EDIT_SELECTORS
                and len(SAVED_REVIEW_FIELDS_SELECTORS) == len(set(SAVED_REVIEW_FIELDS_SELECTORS)) == 14,
                "saved review fields exact ordered disjoint enrolled union")
        require(SAVED_REVIEW_FIELDS_SELECTION_ID not in resolved, "saved review fields distinct selection")
        combined = dict(default, unitTestSelectors=list(SAVED_REVIEW_FIELDS_SELECTORS), tier="D30",
                        **dict(zip(BUDGET_KEYS, TIERS["D30"])))
        validate_selection(combined)
        resolved[SAVED_REVIEW_FIELDS_SELECTION_ID] = combined
        require(FIELD_AUTOSAVE_SELECTORS == (FIELD_EDIT_SELECTORS[3],)
                and FIELD_AUTOSAVE_SELECTION_ID not in resolved,
                "field autosave exact existing method")
        autosave = dict(combined, unitTestSelectors=list(FIELD_AUTOSAVE_SELECTORS))
        validate_selection(autosave)
        resolved[FIELD_AUTOSAVE_SELECTION_ID] = autosave
        if live_host:
            require(tuple(default["unitTestSelectors"][1064:1078]) == LIVE_HOST_RUNTIME_SELECTORS
                    and len(default["unitTestSelectors"]) == (1091 if round_item_completion
                                                              else 1085 if round_item_mount else 1078)
                    and tuple(resolved["c36-live-host"]["unitTestSelectors"]) == LIVE_HOST_SELECTORS,
                    "live host exact appended methods and class group")
            require(len(LIVE_HOST_RUNTIME_SELECTORS) == len(set(LIVE_HOST_RUNTIME_SELECTORS)) == 14
                    and LIVE_HOST_SELECTION_ID not in resolved, "live host distinct exact14 question")
            # Owner-approved 2026-09-24: development-only longer test watchdog for this question.
            live_question = dict(combined, unitTestSelectors=list(LIVE_HOST_RUNTIME_SELECTORS),
                                 tier="D50", **dict(zip(BUDGET_KEYS, TIERS["D50"])))
            validate_selection(live_question)
            resolved[LIVE_HOST_SELECTION_ID] = live_question
            require(len(set(STARTUP_RETIREMENT_SELECTORS)) == 3
                    and set(STARTUP_RETIREMENT_SELECTORS) <= set(LIVE_HOST_SELECTORS)
                    and STARTUP_RETIREMENT_SELECTION_ID not in resolved, "startup retirement exact3 question")
            startup_question = dict(combined, unitTestSelectors=list(STARTUP_RETIREMENT_SELECTORS),
                                    tier="D50", **dict(zip(BUDGET_KEYS, TIERS["D50"])))
            validate_selection(startup_question)
            resolved[STARTUP_RETIREMENT_SELECTION_ID] = startup_question
        if round_item_mount:
            require(tuple(default["unitTestSelectors"][1078:1085]) == ROUND_ITEM_MOUNT_SELECTORS
                    and tuple(resolved["c36-round-item-mount"]["unitTestSelectors"]) == ROUND_ITEM_MOUNT_SELECTORS
                    and len(set(ROUND_ITEM_MOUNT_SELECTORS)) == 7
                    and ROUND_ITEM_MOUNT_SELECTION_ID not in resolved, "round item mount exact appended class")
            mount_question = dict(combined, unitTestSelectors=list(ROUND_ITEM_MOUNT_SELECTORS),
                                  tier="D50", **dict(zip(BUDGET_KEYS, TIERS["D50"])))
            validate_selection(mount_question)
            resolved[ROUND_ITEM_MOUNT_SELECTION_ID] = mount_question
        if round_item_completion:
            require(tuple(default["unitTestSelectors"][1085:]) == ROUND_ITEM_COMPLETION_SELECTORS
                    and tuple(resolved["c36-round-item-completion"]["unitTestSelectors"]) == ROUND_ITEM_COMPLETION_SELECTORS
                    and len(set(ROUND_ITEM_COMPLETION_SELECTORS)) == 6
                    and set(ROUND_READINESS_SELECTORS) <= defaults
                    and len(set(ROUND_ITEM_COMPLETION_QUESTION_SELECTORS)) == 12
                    and ROUND_ITEM_COMPLETION_SELECTION_ID not in resolved,
                    "round item completion exact appended class and readiness question")
            completion_question = dict(combined, unitTestSelectors=list(ROUND_ITEM_COMPLETION_QUESTION_SELECTORS))
            validate_selection(completion_question)
            resolved[ROUND_ITEM_COMPLETION_SELECTION_ID] = completion_question
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


def load_selection_generator(root):
    source = root / "Scripts/v23-selection-generator.py"
    require(source.is_file() and not source.is_symlink(), "selection generator source")
    spec = importlib.util.spec_from_file_location("v23_selection_generator", source)
    require(spec is not None and spec.loader is not None, "selection generator module")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    return generator


def verify_generated_selection(root, default, selection_map):
    """The current pinned output must still equal its closed manifest/source."""
    generator = load_selection_generator(root)
    manifest = generator.load_json(root / "Scripts/v23-selection-manifest.json")
    pool_digest = sha256(canonical(default))
    require(pool_digest in GENERATED_PROFILE_PINS, "generated selection known profile digest")
    profile, map_digest = GENERATED_PROFILE_PINS[pool_digest]
    expected, expected_map, report = generator.generate(manifest, profile, root)
    expected_partitions = {"schemaVersion": 1, "families": [{
        "parentID": ERASE_RECOVERY_SELECTION_ID,
        "parentSelectors": list(ERASE_RECOVERY_SELECTORS),
        "partitions": [{"id": key, "selectors": list(members)}
                       for key, members in ERASE_DIAGNOSTIC_PARTITIONS],
    }]}
    expected_partitions["families"].append({
        "parentID": "replacement-packet-union",
        "parentSelectors": list(REPLACEMENT_UNION_SELECTORS),
        "partitions": [{"id": key, "selectors": list(members)}
                       for key, members in REPLACEMENT_DIAGNOSTIC_PARTITIONS],
    })
    require(manifest.get("diagnosticPartitions") == expected_partitions,
            "diagnostic manifest exact closed partition binding")
    require(canonical(default) == canonical(expected) and canonical(selection_map) == canonical(expected_map),
            "generated selection differs from manifest/source")
    require(report["selectionSHA256"] == pool_digest
            and report["selectionMapSHA256"] == map_digest,
            "generated selection profile digest")
    return report


def development_batch_selection(root):
    """Return the D50 selection named by the committed development batch at root.

    The file supplies only the question and exact ordered methods. Every method must
    be a direct runnable XCTest instance method of its unit class file, verified by
    the same parser that admits the generated selector pool. Nothing is inferred.
    """
    path = root / DEV_BATCH_PATH
    require(path.is_file() and not path.is_symlink(), "development batch file")
    raw = path.read_bytes()
    require(0 < len(raw) <= DEV_BATCH_MAX_BYTES, "development batch size")
    # Git stores JSON with LF; a CR would give one list two platform digests.
    require(b"\r" not in raw, "development batch LF line endings")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("invalid V23 native evidence: development batch UTF-8 JSON") from error
    require(type(value) is dict and set(value) == {"schema", "question", "tests"},
            "development batch keys")
    require(value["schema"] == DEV_BATCH_SCHEMA, "development batch schema")
    require(development_batch_question(value["question"]), "development batch question")
    tests = value["tests"]
    require(type(tests) is list and 1 <= len(tests) <= DEV_BATCH_MAX_TESTS,
            "development batch test count")
    require(all(type(item) is str and DEV_BATCH_TEST.fullmatch(item) is not None for item in tests),
            "development batch test selector")
    require(len(set(tests)) == len(tests), "duplicate development batch test")
    unit_root = root / "FieldEvidenceAppTests"
    require(unit_root.is_dir() and not unit_root.is_symlink(), "development batch unit test source root")
    generator = load_selection_generator(root)
    try:
        for class_name in dict.fromkeys(selection_class(item) for item in tests):
            source = unit_root / (class_name + ".swift")
            require(source.is_file() and not source.is_symlink()
                    and source.resolve().parent == unit_root.resolve(),
                    "development batch unit class file: " + class_name)
            require(not (root / "FieldEvidenceAppUITests" / (class_name + ".swift")).exists(),
                    "development batch UI test class: " + class_name)
            code = generator._active_swift(generator._mask_swift_noncode(source.read_text(encoding="utf-8")))
            require(re.search(r"\bXCUI[A-Za-z]*\b", code) is None,
                    "development batch UI test class: " + class_name)
        verified = generator.verify_source_declarations(
            {"sourceRoot": "FieldEvidenceAppTests", "selectorPool": list(tests)}, root)
    except (generator.ManifestError, UnicodeDecodeError) as error:
        raise ValueError("invalid V23 native evidence: development batch runnable method: "
                         + str(error)) from error
    require(verified == len(tests), "development batch runnable method count")
    selection = {
        "schemaVersion": 1, "taskID": TASK, "tier": DEV_BATCH_TIER, "runUISmoke": False,
        **dict(zip(BUDGET_KEYS, TIERS[DEV_BATCH_TIER])),
        "unitTestSelectors": list(tests), "uiTestSelectors": [],
        DEV_BATCH_KEY: {"path": DEV_BATCH_PATH, "schema": DEV_BATCH_SCHEMA, "sha256": sha256(raw),
                        "question": value["question"], "developmentOnly": True, "acceptance": False},
    }
    validate_selection(selection)
    return selection


_UNIT_DISCOVERY_CACHE = {}
UNIT_SELECTOR = re.compile(r"FieldEvidenceAppTests/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+")
UNIT_PROJECT_PATH = "FieldEvidenceApp.xcodeproj/project.pbxproj"
UNIT_PROJECT_MAX_BYTES = 4 * 1024 * 1024
OPENSTEP_TOKEN = re.compile(r"[A-Za-z0-9_$+/:.\-]+")


def parse_openstep_plist(text):
    """Minimal old-style property list parser for project.pbxproj; anything unusual fails closed."""
    position = 0
    length = len(text)

    def skip():
        nonlocal position
        while position < length:
            if text[position].isspace():
                position += 1
            elif text.startswith("/*", position):
                end = text.find("*/", position + 2)
                require(end >= 0, "unit test project comment")
                position = end + 2
            elif text.startswith("//", position):
                end = text.find("\n", position)
                position = length if end < 0 else end + 1
            else:
                return

    def expect(character):
        nonlocal position
        skip()
        require(text.startswith(character, position), "unit test project syntax near offset %d" % position)
        position += 1

    def value():
        nonlocal position
        skip()
        require(position < length, "unit test project value")
        character = text[position]
        if character == "{":
            position += 1
            result = {}
            while True:
                skip()
                if text.startswith("}", position):
                    position += 1
                    return result
                key = value()
                require(isinstance(key, str) and key not in result, "unit test project dictionary key")
                expect("=")
                result[key] = value()
                expect(";")
        if character == "(":
            position += 1
            result = []
            while True:
                skip()
                if text.startswith(")", position):
                    position += 1
                    return result
                result.append(value())
                skip()
                if text.startswith(",", position):
                    position += 1
                else:
                    require(text.startswith(")", position), "unit test project array")
        if character == '"':
            position += 1
            characters = []
            while True:
                require(position < length, "unit test project string")
                if text[position] == "\\":
                    require(position + 1 < length, "unit test project string escape")
                    characters.append(text[position:position + 2])
                    position += 2
                elif text[position] == '"':
                    position += 1
                    return "".join(characters)
                else:
                    characters.append(text[position])
                    position += 1
        match = OPENSTEP_TOKEN.match(text, position)
        require(match is not None, "unit test project token near offset %d" % position)
        position = match.end()
        return match.group(0)

    result = value()
    skip()
    require(position == length and isinstance(result, dict), "unit test project trailing content")
    return result


def require_plain_unit_test_membership(root):
    """Discovery reads every Swift file under FieldEvidenceAppTests, so the unit target must
    compile exactly that one synchronized folder: no membership exception set (on any group)
    and no explicit source file may add or remove a unit test file."""
    path = root / UNIT_PROJECT_PATH
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= UNIT_PROJECT_MAX_BYTES,
            "unit test target project file")
    try:
        text = path.read_bytes().decode("utf-8")
    except UnicodeDecodeError as error:
        raise ValueError("invalid V23 native evidence: unit test target project UTF-8") from error
    objects = parse_openstep_plist(text).get("objects")
    require(isinstance(objects, dict) and all(isinstance(item, dict) for item in objects.values()),
            "unit test target project objects")
    targets = [key for key, item in objects.items()
               if item.get("isa") == "PBXNativeTarget" and item.get("name") == "FieldEvidenceAppTests"]
    require(len(targets) == 1, "unit test target")
    target = objects[targets[0]]
    groups = target.get("fileSystemSynchronizedGroups")
    require(isinstance(groups, list) and len(groups) == 1, "unit test target synchronized groups")
    group = objects.get(groups[0])
    require(isinstance(group, dict) and group.get("isa") == "PBXFileSystemSynchronizedRootGroup"
            and group.get("path") == "FieldEvidenceAppTests" and group.get("sourceTree") == "<group>",
            "unit test synchronized root group")
    require(group.get("exceptions", []) == [], "unit test synchronized group has membership exceptions")
    phases = target.get("buildPhases")
    require(isinstance(phases, list) and all(phase in objects for phase in phases), "unit test target build phases")
    for key, item in objects.items():
        if "ExceptionSet" in str(item.get("isa")):
            require(item.get("target") != targets[0] and item.get("buildPhase") not in phases,
                    "membership exception set applies to the unit test target: " + key)
    for phase in phases:
        if objects[phase].get("isa") == "PBXSourcesBuildPhase":
            require(objects[phase].get("files") == [], "unit test target has explicit source files")


def unit_test_source_files(root):
    """Every Swift file the file-system-synchronized unit target compiles."""
    require_plain_unit_test_membership(root)
    unit_root = root / "FieldEvidenceAppTests"
    require(unit_root.is_dir() and not unit_root.is_symlink(), "unit test source root")
    files = []
    for directory, directories, names in os.walk(unit_root, followlinks=False):
        directories.sort()
        names.sort()
        for name in directories:
            require(not (Path(directory) / name).is_symlink(), "symlinked unit test source directory")
        for name in names:
            path = Path(directory) / name
            if name.endswith(".swift"):
                require(path.is_file() and not path.is_symlink(), "unsafe unit test source file")
                files.append(path)
    require(bool(files), "no unit test source files")
    return sorted(files, key=lambda item: item.relative_to(unit_root).as_posix())


def method_modifiers(body, start):
    """Same-line modifiers plus directly preceding attribute/modifier-only lines."""
    beginning = body.rfind("\n", 0, start) + 1
    prefix = body[beginning:start]
    word = r"(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^\n]*\))?|private|fileprivate|static|class|final|public|internal|override|nonisolated|open)"
    while beginning > 0:
        previous = body.rfind("\n", 0, beginning - 1) + 1
        line = body[previous:beginning].strip()
        if not line or re.fullmatch(word + r"(?:\s+" + word + r")*", line) is None:
            break
        prefix = line + " " + prefix
        beginning = previous
    return prefix


def discover_unit_test_methods(root):
    """Return every direct runnable XCTest instance method in FieldEvidenceAppTests.

    Uses the selection generator's closed Debug-Simulator parser (comments, strings
    and inactive branches are masked). A method counts when it is a depth-0
    `func test*()` without private/fileprivate/static/class in the body or a
    top-level extension of an XCTestCase-descendant class; inherited test methods
    run for each subclass. Every counted method is then held to the generator's
    strict runnable-declaration rules, so an unusual declaration fails closed.
    """
    generator = load_selection_generator(root)
    files = unit_test_source_files(root)
    digest = hashlib.sha256((root / "Scripts/v23-selection-generator.py").read_bytes())
    sources = []
    for path in files:
        raw = path.read_bytes()
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode("utf-8") + b"\0" + raw + b"\0")
        sources.append((relative, raw))
    key = (str(root), digest.hexdigest())
    if key in _UNIT_DISCOVERY_CACHE:
        return list(_UNIT_DISCOVERY_CACHE[key])
    declarations = []
    nested = []
    classes = {}
    try:
        for relative, raw in sources:
            masked = generator._active_swift(generator._mask_swift_noncode(raw.decode("utf-8")))
            depths = generator._brace_depths(masked)
            for match in re.finditer(r"\b(class|extension)\s+([A-Za-z_][A-Za-z0-9_]*)\b([^{};]{0,1000})\{", masked):
                kind, name, header = match.group(1), match.group(2), match.group(3)
                superclass = re.match(r"\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)", header)
                superclass = superclass.group(1) if superclass else None
                if depths[match.start()] != 0:
                    if kind == "class" and superclass is not None:
                        nested.append((relative, name, superclass))
                    continue
                entry = {"kind": kind, "name": name, "superclass": superclass, "file": relative,
                         "masked": masked, "match": match,
                         "body": generator._body_at(masked, match.end() - 1, name)}
                declarations.append(entry)
                if kind == "class":
                    require(name not in classes, "duplicate unit test class declaration: " + name)
                    classes[name] = entry

        def xctest(name, seen=()):
            if name in ("XCTestCase", "XCTest.XCTestCase"):
                return True
            require(name not in seen, "cyclic unit test class inheritance: " + name)
            entry = classes.get(name)
            return bool(entry and entry["superclass"]) and xctest(entry["superclass"], seen + (name,))

        for relative, name, superclass in nested:
            require(not xctest(superclass), "nested XCTestCase subclass is not supported: " + relative + "/" + name)
        # A private or fileprivate class gets a private-discriminator Objective-C name that
        # -only-testing never matches, so its methods would be selected but never executed.
        hidden = sorted(entry["file"] + "/" + entry["name"] for entry in declarations
                        if entry["kind"] == "class" and xctest(entry["name"])
                        and re.search(r"\b(?:private|fileprivate)\b",
                                      method_modifiers(entry["masked"], entry["match"].start())))
        require(not hidden, "unselectable private XCTestCase: %s%s"
                % (", ".join(hidden[:10]), "" if len(hidden) <= 10 else " and %d more" % (len(hidden) - 10)))
        direct = {}
        for entry in declarations:
            if entry["name"] not in classes or not xctest(entry["name"]):
                continue
            body = entry["body"]
            body_depths = generator._brace_depths(body)
            found = []
            for method in re.finditer(r"\bfunc\s+(test[A-Za-z0-9_]*)\s*\(\s*\)", body):
                if body_depths[method.start()] != 0:
                    continue
                if re.search(r"\b(?:private|fileprivate|static|class)\b", method_modifiers(body, method.start())):
                    continue
                found.append(method.group(1))
            if not found:
                continue
            record = direct.setdefault(entry["name"], {"bodies": [], "methods": []})
            record["bodies"].append(body)
            record["methods"].extend(found)
        for name, record in direct.items():
            methods = sorted(set(record["methods"]))
            generator._verify_methods(record["bodies"], name, methods)
            record["methods"] = methods
        selectors = set()
        for name in classes:
            if not xctest(name):
                continue
            ancestor = name
            while ancestor in classes:
                for method in direct.get(ancestor, {}).get("methods", []):
                    selectors.add("FieldEvidenceAppTests/" + name + "/" + method)
                ancestor = classes[ancestor]["superclass"]
    except (generator.ManifestError, UnicodeDecodeError) as error:
        raise ValueError("invalid V23 native evidence: unit test discovery: " + str(error)) from error
    require(all(UNIT_SELECTOR.fullmatch(item) for item in selectors), "unit test selector grammar")
    result = sorted(selectors, key=lambda item: tuple(item.split("/")[1:]))
    _UNIT_DISCOVERY_CACHE[key] = tuple(result)
    return result


def validate_coverage_partitions(value, discovered):
    """Closed partition file: disjoint, bounded, and exactly every discovered method.

    sourceCensusHead is the commit whose timing census seeded the assignments and
    estimates; generatedAtHead is the checkout HEAD the file was last regenerated at.
    Each partition names its consumer tier: D50C, or D90S for exactly one method, and
    its estimate must fit that tier's test budget. Coverage itself is always proven
    against the checkout being admitted."""
    require(type(value) is dict
            and set(value) == {"schema", "sourceCensusHead", "generatedAtHead", "partitions", "sweepOrder"},
            "coverage partitions keys")
    require(value["schema"] == SHARED_PARTITIONS_SCHEMA, "coverage partitions schema")
    for key in ("sourceCensusHead", "generatedAtHead"):
        require(isinstance(value[key], str) and re.fullmatch(r"[0-9a-f]{40}", value[key]),
                "coverage partitions head: " + key)
    partitions = value["partitions"]
    require(type(partitions) is list and 1 <= len(partitions) <= SHARED_MAX_PARTITIONS,
            "coverage partition count must be 1-%d" % SHARED_MAX_PARTITIONS)
    identifiers = []
    owner = {}
    for partition in partitions:
        require(type(partition) is dict and set(partition) == {"id", "tier", "estimatedSeconds", "selectors"},
                "coverage partition keys")
        identifier = partition["id"]
        require(isinstance(identifier, str) and SHARED_PARTITION_ID.fullmatch(identifier) is not None
                and identifier not in identifiers, "coverage partition ID")
        identifiers.append(identifier)
        tier = partition["tier"]
        require(isinstance(tier, str) and tier in SHARED_CONSUMER_TIERS, "coverage partition tier: " + identifier)
        estimate = partition["estimatedSeconds"]
        require(type(estimate) in (int, float) and math.isfinite(estimate)
                and 0 < estimate <= TIERS[tier][2],
                "coverage partition estimate must fit the test budget: " + identifier)
        selectors = partition["selectors"]
        require(type(selectors) is list and 1 <= len(selectors) <= SHARED_MAX_PARTITION_METHODS,
                "coverage partition method count: " + identifier)
        require(tier != SHARED_SOLO_TIER or len(selectors) == 1,
                "coverage partition solo tier needs exactly one method: " + identifier)
        for selector in selectors:
            require(isinstance(selector, str) and UNIT_SELECTOR.fullmatch(selector) is not None,
                    "coverage partition selector: " + identifier)
            require(selector not in owner, "coverage partitions overlap: %s in %s and %s"
                    % (selector, owner.get(selector), identifier))
            owner[selector] = identifier
    order = value["sweepOrder"]
    require(type(order) is list and len(order) == len(identifiers) and set(order) == set(identifiers),
            "coverage sweep order must list every partition once")
    missing = sorted(set(discovered) - set(owner))
    extra = sorted(set(owner) - set(discovered))
    require(not missing and not extra,
            "coverage partitions are stale for this checkout: %d missing %s; %d extra %s"
            % (len(missing), missing[:10], len(extra), extra[:10]))
    return value


def load_coverage_partitions(root):
    path = root / SHARED_PARTITIONS_PATH
    require(path.is_file() and not path.is_symlink(), "coverage partitions file")
    raw = path.read_bytes()
    require(0 < len(raw) <= SHARED_MAX_PARTITIONS_BYTES, "coverage partitions size")
    require(b"\r" not in raw, "coverage partitions LF line endings")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError("invalid V23 native evidence: coverage partitions UTF-8 JSON") from error
    return validate_coverage_partitions(value, discover_unit_test_methods(root)), sha256(raw)


def shared_selection(root, partition_id=None):
    """The producer plan (every method, sweep order) or one consumer partition."""
    value, digest = load_coverage_partitions(root)
    by_id = {partition["id"]: partition for partition in value["partitions"]}
    order = list(value["sweepOrder"])
    if partition_id is None:
        tier = SHARED_PRODUCER_TIER
        selectors = [selector for identifier in order for selector in by_id[identifier]["selectors"]]
    else:
        require(partition_id in by_id, "unknown coverage partition: " + str(partition_id))
        tier = by_id[partition_id]["tier"]
        selectors = list(by_id[partition_id]["selectors"])
    selection = {
        "schemaVersion": 1, "taskID": TASK, "tier": tier, "runUISmoke": False,
        **dict(zip(BUDGET_KEYS, TIERS[tier])), "unitTestSelectors": selectors, "uiTestSelectors": [],
        SHARED_KEY: {"partitionsPath": SHARED_PARTITIONS_PATH, "partitionsSHA256": digest,
                     "partitionIDs": order, "partitionID": partition_id,
                     "developmentOnly": True, "acceptance": False},
    }
    validate_selection(selection)
    return selection


def shared_partition_tiers(root):
    """{partition ID: consumer tier} in sweep order, for the dispatch matrix outputs."""
    value, _ = load_coverage_partitions(root)
    by_id = {partition["id"]: partition["tier"] for partition in value["partitions"]}
    return {identifier: by_id[identifier] for identifier in value["sweepOrder"]}


def shared_route_environment(environment):
    return (environment.get("V23_SHARED_ROLE", "none"), environment.get("V23_PARTITION_ID", ""),
            environment.get("V23_PAYLOAD_ARTIFACT_NAME", ""))


def shared_payload_artifact_name(environment, head):
    return "v23-shared-payload-%s-%s-%s" % (environment.get("GITHUB_RUN_ID", ""),
                                             environment.get("GITHUB_RUN_ATTEMPT", ""), head)


def shared_record_binding(root, environment, plan=None):
    role, partition, payload = shared_route_environment(environment)
    plan = shared_selection(root) if plan is None else plan
    return {"role": role, "partitionID": partition or None, "payloadArtifactName": payload or None,
            "planSHA256": sha256(canonical(plan)), "partitionsSHA256": plan[SHARED_KEY]["partitionsSHA256"]}


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
    role, partition, payload = shared_route_environment(environment)
    shared_binding = None
    if selection_id == DEV_BATCH_SELECTION_ID:
        # The checked-in pool and map keep every existing check; only the exact
        # ordered methods come from the committed development batch at this head.
        require((role, partition, payload) == ("none", "", ""), "V23 shared inputs outside the shared route")
        resolve_selection(default, selection_map, DEFAULT_SELECTION_ID)
        selected = development_batch_selection(root)
    elif selection_id == SHARED_SELECTION_ID:
        # One plan per head: the producer builds for it; each consumer runs one
        # closed partition of it. Dispatch (no role) resolves the plan itself.
        resolve_selection(default, selection_map, DEFAULT_SELECTION_ID)
        require(role in ("none",) + SHARED_ROLES, "shared coverage role")
        require((role == "consumer") == bool(partition), "shared coverage role/partition")
        require((role == "none") == (payload == ""), "shared coverage payload input")
        plan = shared_selection(root)
        selected = shared_selection(root, partition) if role == "consumer" else plan
        shared_binding = shared_record_binding(root, environment, plan)
    else:
        require((role, partition, payload) == ("none", "", ""), "V23 shared inputs outside the shared route")
        selected = resolve_selection(default, selection_map, selection_id)
    if sha256(canonical(default)) in GENERATED_PROFILE_PINS:
        verify_generated_selection(root, default, selection_map)
    record = {"selectionID": selection_id, "selectionSHA256": sha256(canonical(selected)),
              "selectionMapSHA256": sha256((root / SELECTION_MAP_PATH).read_bytes())}
    if shared_binding is not None:
        record[SHARED_KEY] = shared_binding
    return selected, record


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
        dispatched_selection_sha256 = selection_record["selectionSHA256"]
        if selection_record["selectionID"] == SHARED_SELECTION_ID:
            # Dispatch binds the one plan; each worker's own selection derives from it.
            require(isinstance(selection_record.get(SHARED_KEY), dict), "shared coverage record binding")
            dispatched_selection_sha256 = selection_record[SHARED_KEY].get("planSHA256")
        require(e.get("DISPATCH_NATIVE_SELECTION_SHA256") == dispatched_selection_sha256,
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
        FIELD_AUTOSAVE_SELECTION_ID: (FIELD_AUTOSAVE_PARENT, FIELD_AUTOSAVE_SELECTORS),
        LIVE_HOST_SELECTION_ID: (LIVE_HOST_PARENT, LIVE_HOST_RUNTIME_SELECTORS),
        ROUND_ITEM_MOUNT_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, ROUND_ITEM_MOUNT_SELECTORS),
        STARTUP_RETIREMENT_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, STARTUP_RETIREMENT_SELECTORS),
        ROUND_ITEM_COMPLETION_SELECTION_ID: (ROUND_ITEM_MOUNT_PARENT, ROUND_ITEM_COMPLETION_QUESTION_SELECTORS),
        NOTIFICATION_INTERRUPTION_SELECTION_ID: (NOTIFICATION_INTERRUPTION_PARENT, NOTIFICATION_INTERRUPTION_SELECTORS),
        SAVED_REVIEW_FIELDS_SELECTION_ID: (SAVED_REVIEW_FIELDS_PARENT, SAVED_REVIEW_FIELDS_SELECTORS),
        FINDING_PROFILE_FIXTURES_SELECTION_ID: (FINDING_PROFILE_FIXTURES_PARENT, FINDING_PROFILE_FIXTURES_SELECTORS),
        NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTION_ID: (NOTIFICATION_SCHEDULE_ERASE_BUILD30_PARENT, NOTIFICATION_SCHEDULE_ERASE_BUILD30_SELECTORS),
        ACTIVITY_COMPLETED_SOURCE_SELECTION_ID: (ACTIVITY_COMPLETED_SOURCE_PARENT, ACTIVITY_COMPLETED_SOURCE_SELECTORS),
        ACTIVITY_CODEC_PUNCH_SELECTION_ID: (REPLACEMENT_UNION_PARENT, ACTIVITY_CODEC_PUNCH_SELECTORS),
        ACTIVITY_BUILD30_SELECTION_ID: (REPLACEMENT_UNION_PARENT, ACTIVITY_CONTRACT_SELECTORS),
        REPLACEMENT_UNION_SELECTION_ID: (REPLACEMENT_UNION_PARENT, REPLACEMENT_UNION_SELECTORS),
        **{key: (REPLACEMENT_UNION_PARENT, members)
           for key, members in REPLACEMENT_DIAGNOSTIC_PARTITIONS},
        BUILD_WATCHDOG_SELECTION_ID: (BUILD_WATCHDOG_PARENT, PARENT_FINALIZATION_METHOD_PARTITIONS[0][1]),
        RESTORE_BUILD_WATCHDOG_SELECTION_ID: (RESTORE_BUILD_WATCHDOG_PARENT, RESTORE_BUILD_WATCHDOG_SELECTORS),
        REMINDER_BUILD_WATCHDOG_SELECTION_ID: (REMINDER_BUILD_WATCHDOG_PARENT, REMINDER_BUILD_WATCHDOG_SELECTORS),
        RESTORE_HISTORY_SELECTION_ID: (RESTORE_HISTORY_PARENT, RESTORE_HISTORY_SELECTORS),
        ERASE_BUILD_WATCHDOG_SELECTION_ID: (ERASE_BUILD_WATCHDOG_PARENT, ERASE_RECOVERY_SELECTORS),
        **{key: (ERASE_PARTITION_PARENT, members)
           for key, members in ERASE_DIAGNOSTIC_PARTITIONS},
    }
    development_batch = (selection_record["selectionID"] == DEV_BATCH_SELECTION_ID
                         or DEV_BATCH_KEY in selection)
    shared = (selection_record["selectionID"] == SHARED_SELECTION_ID or SHARED_KEY in selection
              or SHARED_KEY in selection_record)
    if not shared:
        require(shared_route_environment(e) == ("none", "", ""), "V23 shared inputs outside the shared route")
    if development_batch:
        # No parent/tree pin: the exact list is recomputed from the committed file
        # at this checkout and must equal the dispatched selection byte for byte.
        require(selection_record["selectionID"] == DEV_BATCH_SELECTION_ID
                and selection == development_batch_selection(root),
                "development batch selector/committed list binding")
        require(provider == "github" and label == "macos-26", "development batch GitHub route only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "development batch original attempt only")
    elif shared:
        # No parent/tree pin: the plan and partition are recomputed from the checked-in
        # partition file, whose union must equal every runnable method at this checkout.
        require(selection_record["selectionID"] == SHARED_SELECTION_ID, "shared coverage selector binding")
        role, partition, payload = shared_route_environment(e)
        plan = shared_selection(root)
        require(selection_record.get(SHARED_KEY) == shared_record_binding(root, e, plan),
                "shared coverage record binding")
        if stage == "dispatch":
            require((role, partition, payload) == ("none", "", "") and selection == plan,
                    "shared coverage dispatch plan")
        else:
            require(role in SHARED_ROLES, "shared coverage worker role")
            require(selection == (plan if role == "producer" else shared_selection(root, partition)),
                    "shared coverage role/partition selection binding")
            require(payload == shared_payload_artifact_name(e, head), "shared coverage payload artifact name")
        require(provider == "github" and label == "macos-26", "shared coverage GitHub route only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "shared coverage original attempt only")
    elif selection["tier"] in ("D30", "D50") or selection_record["selectionID"] in watchdog_routes:
        require(selection["tier"] == ("D50" if selection_record["selectionID"] in D50_SELECTION_IDS else "D30")
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


def build_order_limits(selection_id):
    """Closed historical and current diagnostic limits; no runtime override."""
    if selection_id == BUILD_ORDER_SELECTION_ID:
        return 1200, 24
    require(selection_id == NOTIFICATION_INTERRUPTION_SELECTION_ID,
            "build order command admission")
    return 1800, 34


def observe_build_before_boot(root, artifact, record, environment):
    """Run the unchanged build under the incumbent outer watchdog; never boot.

    The child and simctl samples inherit that watchdog's process group. A timeout
    retains the append-only prefix, which cannot pass completed-evidence checks.
    No signal handler or new session can detach build descendants from the owner.
    """
    watchdog, sample_cap = build_order_limits(record["selectionID"])
    require(read_json(artifact / "native-admission.json") == record, "build order admission changed")
    require(environment.get("CI_BUILD_TIMEOUT_SECONDS") == str(watchdog), "build order unchanged watchdog")
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
                "selectedUDID": udid, "command": list(BUILD_ORDER_COMMAND), "watchdogSeconds": watchdog})
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
                # The selected source-defined watchdog bounds the process. This additional
                # cap bounds observer work even if its caller is misconfigured.
                if samples < sample_cap:
                    sample("during")
                    samples += 1
        sample("after")
        append({"kind": "completed", "returnCode": code})
    return code if code >= 0 else 128 - code


def build_order_observations(artifact, record, selected_udid):
    watchdog, sample_cap = build_order_limits(record["selectionID"])
    path = artifact / BUILD_ORDER_OBSERVATIONS
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 4 * 1024 * 1024,
            "bounded build order evidence")
    raw = path.read_bytes()
    require(raw.endswith(b"\n"), "complete build order observation line")
    events = [json.loads(line, object_pairs_hook=unique_pairs) for line in raw.splitlines()]
    require(5 <= len(events) <= sample_cap + 5 and all(isinstance(event, dict) for event in events),
            "build order event count")
    times = [event.get("elapsedSeconds") for event in events]
    require(all(type(value) in (int, float) and math.isfinite(value) and value >= 0 for value in times)
            and times == sorted(times) and times[-1] <= watchdog, "build order event timing")
    header = dict(events[0]); header.pop("elapsedSeconds")
    require(header == {"kind": "header", "schemaVersion": 1,
                       "admissionSHA256": sha256(canonical(record)), "selectedUDID": selected_udid,
                       "command": list(BUILD_ORDER_COMMAND), "watchdogSeconds": watchdog},
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
    development_batch = record["selectionID"] == DEV_BATCH_SELECTION_ID
    shared = record["selectionID"] == SHARED_SELECTION_ID
    if shared:
        require(shared_role(record) == "producer", "shared coverage build is producer-only")
    unpinned = development_batch or shared
    require(record["selectionID"] in NO_INDEX_ROUTES or unpinned, "no-index admitted selection")
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
    # The development batch and shared producer pin no parent or trees; their admission
    # record (bound by admissionSHA256) carries the exact head, head tree and list digest.
    return {"schemaVersion": 1, "selectionID": record["selectionID"],
            "head": record["head"],
            "parent": None if unpinned else NO_INDEX_ROUTES[record["selectionID"]][0],
            "runID": record["runID"],
            "runAttempt": record["runAttempt"], "admissionSHA256": sha256(canonical(record)),
            "buildScriptSHA256": sha256((root / "Scripts/build-smoke.sh").read_bytes()),
            "sourceTrees": None if unpinned else no_index_source_trees(record["selectionID"]),
            "argv": arguments, "diagnosticOnly": True, "acceptance": False}


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
            "compilerIndexEmissionDisabled": True, "unchangedSourceTrees": expected["sourceTrees"],
            "speedupEstablished": False, "acceptance": False}


def shared_worker_sources(root):
    sources = {}
    for relative in SHARED_WORKER_SOURCES:
        path = root / relative
        require(path.is_file() and not path.is_symlink(), "shared coverage worker source")
        sources[relative] = sha256(path.read_bytes())
    return sources


def shared_role(record):
    binding = record.get(SHARED_KEY) if record.get("selectionID") == SHARED_SELECTION_ID else None
    require(isinstance(binding, dict) and binding.get("role") in SHARED_ROLES, "shared coverage admitted role")
    return binding["role"]


def load_payload_kernel(root):
    """The tested S10.4 product-tree helpers, loaded the way that file's own driver loads them."""
    source = root / SHARED_PAYLOAD_KERNEL
    require(source.is_file() and not source.is_symlink(), "shared payload kernel source")
    return runpy.run_path(str(source))


def shared_products_binding(kernel, payload_root):
    """One exact product closure: tree digest, single relocatable .xctestrun, arm64/SDK facts."""
    products = payload_root / kernel["ROOT_LABEL"]
    entries, relative = kernel["collect"](products)
    require(entries == kernel["inventory"](products), "shared payload product inventory disagreement")
    xctestrun = products / relative
    return {"treeSHA256": kernel["object_sha"](entries), "entryCount": len(entries),
            "fileBytes": sum(entry.get("size", 0) for entry in entries),
            "xctestrunPath": relative, "xctestrunSHA256": kernel["sha256_file"](xctestrun),
            "compatibility": kernel["product_compatibility"](products, xctestrun)}


def shared_toolchain(artifact, environment):
    require((artifact / "xcode-version.txt").read_text(encoding="utf-8").splitlines()
            == ["Xcode 26.6", "Build version 17F113"], "shared coverage Xcode")
    require(key_values(artifact / "native-sdk.txt") == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"},
            "shared coverage SDK")
    require(environment.get("CONFIGURATION") == "Debug", "shared coverage Debug configuration")
    architecture = platform.machine()
    require(architecture == "arm64", "shared coverage arm64 runner")
    return {"xcodeVersion": "Xcode 26.6", "xcodeBuild": "17F113", "sdkName": "iphonesimulator26.5",
            "sdkBuild": "23F81a", "architecture": architecture, "configuration": "Debug"}


def shared_payload_archive(kernel, payload_root, path):
    """Deterministic tar (sorted members, zero mtime/owners) that the kernel extractor admits."""
    entries = kernel["inventory"](payload_root)
    with tarfile.open(path, "x", format=tarfile.PAX_FORMAT) as archive:
        for entry in entries:
            info = tarfile.TarInfo("FieldEvidencePayload/" + entry["path"])
            info.mode = entry["mode"]
            info.mtime = 0
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            if entry["type"] == "directory":
                info.type = tarfile.DIRTYPE
                archive.addfile(info)
            else:
                info.type = tarfile.REGTYPE
                info.size = entry["size"]
                with (payload_root / entry["path"]).open("rb") as stream:
                    archive.addfile(info, stream)
    require(kernel["inventory"](payload_root) == entries, "shared payload changed while archiving")
    size = path.stat().st_size
    require(0 < size <= kernel["MAX_ARCHIVE_BYTES"], "shared payload archive exceeds the kernel bound")
    return {"name": SHARED_TAR, "bytes": size, "sha256": kernel["sha256_file"](path)}


def shared_local_build_artifacts(artifact):
    return [name for name in ("Build.xcresult", "build-smoke.log", NO_INDEX_RECEIPT)
            if (artifact / name).exists() or (artifact / name).is_symlink()]


def shared_build_evidence(artifact, temp):
    """Before tests: a consumer holds only restored products, with no build tree at all."""
    present = shared_local_build_artifacts(artifact)
    derived = temp / "FieldEvidenceDerivedData"
    present += ["DerivedData/" + name for name in ("Logs/Build", "Build/Intermediates.noindex")
                if (derived / name).exists() or (derived / name).is_symlink()]
    return present


def bounded_evidence(found):
    if len(found) <= SHARED_MAX_LISTED_EVIDENCE:
        return found
    return found[:SHARED_MAX_LISTED_EVIDENCE] + ["... %d more" % (len(found) - SHARED_MAX_LISTED_EVIDENCE)]


def walk_entries(top, skip=None):
    """(path, is_directory) for every entry below top, sorted, never following a symbolic
    link; the one directory `skip` (if given) is neither listed nor entered."""
    for directory, directories, names in os.walk(top, followlinks=False):
        directories[:] = sorted(name for name in directories if Path(directory) / name != skip)
        names.sort()
        for name in directories + names:
            path = Path(directory) / name
            yield path, name in directories and not path.is_symlink()


def shared_activity_log_compile_step(path):
    """The first compile or link step signature in one gunzipped build activity log, if any."""
    try:
        with gzip.open(path, "rb") as stream:
            tail = b""
            total = 0
            while True:
                chunk = stream.read(1024 * 1024)
                if not chunk:
                    return None
                total += len(chunk)
                if total > SHARED_MAX_ACTIVITY_LOG_BYTES:
                    return "oversized activity log"
                window = tail + chunk
                match = SHARED_ACTIVITY_COMPILE_STEP.search(window)
                if match is not None:
                    return match.group(1).decode("ascii") + " step"
                tail = window[-64:]
    except (OSError, EOFError, zlib.error) as error:
        return "unreadable activity log (%s)" % type(error).__name__


def shared_test_log_compile_lines(path):
    """Compile or link task lines, compiler/linker command lines or a build result in the test log."""
    if not path.is_file() or path.is_symlink() or path.stat().st_size > SHARED_MAX_TEST_LOG_BYTES:
        return [path.name + ": unavailable for the compile scan"]
    found = []
    for number, line in enumerate(path.read_bytes().decode("utf-8", "replace").splitlines(), 1):
        stripped = line.strip()
        words = stripped.split()
        tool = words[0] if words else ""
        if (SHARED_LOG_COMPILE_STEP.match(line) or SHARED_LOG_BUILD_RESULT.fullmatch(stripped)
                or tool in SHARED_LOG_BUILTINS
                or ("/" in tool and tool.rsplit("/", 1)[1] in SHARED_LOG_TOOLS)):
            found.append("%s:%d: %s" % (path.name, number, stripped[:200]))
    return found


def shared_compile_evidence(artifact, temp):
    """After tests: only real compile or link evidence fails; build bookkeeping may exist.

    Fails on local build artifacts; object, module, dependency or diagnostic files under
    Build/Intermediates*; a compile or link step in any Logs/Build activity log (gunzipped
    and scanned, unreadable fails closed); or a compile/link line or build result in the
    consumer's test log."""
    found = shared_local_build_artifacts(artifact)
    derived = temp / "FieldEvidenceDerivedData"
    build = derived / "Build"
    if build.is_dir() and not build.is_symlink():
        for child in sorted(build.iterdir()):
            if not child.name.startswith("Intermediates"):
                continue
            relative = "DerivedData/Build/" + child.name
            if child.is_symlink():
                found.append(relative + ": symbolic link")
                continue
            if child.is_dir():
                found += ["DerivedData/" + path.relative_to(derived).as_posix()
                          for path, _ in walk_entries(child) if path.name.endswith(SHARED_COMPILE_OUTPUT_SUFFIXES)]
    logs = derived / "Logs" / "Build"
    if logs.is_symlink():
        found.append("DerivedData/Logs/Build: symbolic link")
    elif logs.is_dir():
        for path, is_directory in walk_entries(logs):
            if is_directory or not path.name.endswith(".xcactivitylog"):
                continue
            relative = "DerivedData/" + path.relative_to(derived).as_posix()
            if path.is_symlink() or not path.is_file():
                found.append(relative + ": not a regular file")
                continue
            step = shared_activity_log_compile_step(path)
            if step is not None:
                found.append(relative + ": " + step)
    found += shared_test_log_compile_lines(artifact / "test-smoke.log")
    return bounded_evidence(found)


def shared_derived_inventory(derived):
    """Every DerivedData entry outside Build/Products, which the products fingerprint covers."""
    entries = {}
    if not derived.is_dir() or derived.is_symlink():
        return entries
    for path, is_directory in walk_entries(derived, skip=derived / "Build" / "Products"):
        relative = path.relative_to(derived).as_posix()
        if path.is_symlink():
            entries[relative] = {"type": "symlink", "target": os.readlink(path)}
        elif is_directory:
            entries[relative] = {"type": "directory"}
        elif path.is_file():
            entries[relative] = {"type": "file", "size": path.stat().st_size, "sha256": sha256_path(path)}
        else:
            entries[relative] = {"type": "other"}
    return entries


def shared_derived_delta(before, after):
    """Added, changed and removed DerivedData entries; each list bounded, with exact counts."""
    added = [dict(after[path], path=path) for path in sorted(set(after) - set(before))]
    removed = [dict(before[path], path=path) for path in sorted(set(before) - set(after))]
    changed = [{"path": path, "before": before[path], "after": after[path]}
               for path in sorted(set(before) & set(after)) if before[path] != after[path]]
    return {"added": added[:SHARED_MAX_DELTA_ENTRIES], "addedCount": len(added),
            "changed": changed[:SHARED_MAX_DELTA_ENTRIES], "changedCount": len(changed),
            "removed": removed[:SHARED_MAX_DELTA_ENTRIES], "removedCount": len(removed)}


def shared_metadata_identity(root, record, artifact, environment):
    binding = record[SHARED_KEY]
    return {"schema": SHARED_PAYLOAD_SCHEMA, "routeID": SHARED_SELECTION_ID,
            "repository": record["repository"], "ref": record["ref"], "head": record["head"],
            "gitTree": record["gitTree"], "workspace": str(root),
            "runID": record["runID"], "runAttempt": record["runAttempt"],
            "payloadArtifactName": binding["payloadArtifactName"], "planSHA256": binding["planSHA256"],
            "partitionsSHA256": binding["partitionsSHA256"],
            "toolchain": shared_toolchain(artifact, environment),
            "developmentOnly": True, "acceptance": False}


def write_new_evidence(path, raw):
    with path.open("xb") as stream:
        stream.write(raw)


def shared_seal(root, artifact, record, environment, kernel=None):
    """Producer only: seal the exact no-index build products once; it never runs tests."""
    require(shared_role(record) == "producer", "shared seal is producer-only")
    require(read_json(artifact / "native-admission.json") == record, "shared seal admission changed")
    kernel = load_payload_kernel(root) if kernel is None else kernel
    build = verify_no_index_build(root, artifact, record, environment)
    require(not any((artifact / name).exists() for name in ("UnitTests.xcresult", "test-smoke.log",
                                                             "unit-test-results.json")),
            "shared producer has no test evidence")
    temp = Path(environment["RUNNER_TEMP"])
    source_products = temp / "FieldEvidenceDerivedData" / "Build" / "Products"
    payload_root = temp / SHARED_PAYLOAD_DIRECTORY
    transport = temp / SHARED_TRANSPORT_DIRECTORY
    require(not any(path.exists() or path.is_symlink() for path in (payload_root, transport)),
            "shared payload directories must be new")
    staged = payload_root / kernel["ROOT_LABEL"]
    staged.parent.mkdir(parents=True)
    kernel["copy_tree"](source_products, staged)
    kernel["normalize_xctestrun"](staged, source_products)
    products = shared_products_binding(kernel, payload_root)
    metadata = dict(shared_metadata_identity(root, record, artifact, environment),
                    buildCommandReceiptSHA256=build["commandReceiptSHA256"],
                    buildLogSHA256=sha256((artifact / "build-smoke.log").read_bytes()), products=products)
    metadata_bytes = canonical(metadata)
    (payload_root / SHARED_PAYLOAD_METADATA).write_bytes(metadata_bytes)
    transport.mkdir(mode=0o700)
    archive = shared_payload_archive(kernel, payload_root, transport / SHARED_TAR)
    (transport / SHARED_TAR_DIGEST).write_bytes(
        ("%s %d %s\n" % (archive["sha256"], archive["bytes"], SHARED_TAR)).encode("ascii"))
    receipt = {"schema": "v23-shared-payload-receipt.v1", "role": "producer",
               "payloadArtifactName": metadata["payloadArtifactName"], "archive": archive,
               "metadataSHA256": sha256(metadata_bytes), "productsTreeSHA256": products["treeSHA256"],
               "xctestrunSHA256": products["xctestrunSHA256"], "head": record["head"],
               "gitTree": record["gitTree"], "workspace": str(root), "runID": record["runID"],
               "runAttempt": record["runAttempt"], "developmentOnly": True, "acceptance": False}
    write_new_evidence(artifact / SHARED_PAYLOAD_METADATA, metadata_bytes)
    write_new_evidence(artifact / SHARED_PAYLOAD_RECEIPT, canonical(receipt))
    return receipt


def shared_restore(root, artifact, record, environment, kernel=None):
    """Consumer only: verify, safely extract and restore the producer's exact products."""
    require(shared_role(record) == "consumer", "shared restore is consumer-only")
    require(read_json(artifact / "native-admission.json") == record, "shared restore admission changed")
    kernel = load_payload_kernel(root) if kernel is None else kernel
    started = time.monotonic()
    temp = Path(environment["RUNNER_TEMP"])
    derived = temp / "FieldEvidenceDerivedData"
    require(shared_build_evidence(artifact, temp) == [] and not derived.exists() and not derived.is_symlink(),
            "shared consumer products must be restored, never built")
    download = temp / SHARED_DOWNLOAD_DIRECTORY
    require(download.is_dir() and not download.is_symlink()
            and sorted(item.name for item in download.iterdir()) == sorted([SHARED_TAR, SHARED_TAR_DIGEST]),
            "shared payload download members")
    tar, digest_path = download / SHARED_TAR, download / SHARED_TAR_DIGEST
    require(all(path.is_file() and not path.is_symlink() for path in (tar, digest_path)), "shared payload download files")
    match = re.fullmatch(r"([0-9A-F]{64}) ([0-9]+) FieldEvidencePayload\.tar\n",
                         digest_path.read_bytes().decode("ascii", "replace"))
    require(match is not None and int(match.group(2)) == tar.stat().st_size
            and int(match.group(2)) <= kernel["MAX_ARCHIVE_BYTES"]
            and kernel["sha256_file"](tar) == match.group(1), "shared payload archive digest or size")
    extracted = temp / SHARED_EXTRACTED_DIRECTORY
    kernel["extract_tar"](tar, extracted)
    require(sorted(item.name for item in extracted.iterdir())
            == sorted(["FieldEvidenceDerivedData", SHARED_PAYLOAD_METADATA]), "shared payload root members")
    metadata_bytes = (extracted / SHARED_PAYLOAD_METADATA).read_bytes()
    metadata = json.loads(metadata_bytes.decode("utf-8"), object_pairs_hook=unique_pairs)
    require(type(metadata) is dict and metadata_bytes == canonical(metadata), "shared payload metadata bytes")
    expected = shared_metadata_identity(root, record, artifact, environment)
    require(set(metadata) == set(expected) | {"buildCommandReceiptSHA256", "buildLogSHA256", "products"},
            "shared payload metadata keys")
    for key, value in expected.items():
        require(metadata[key] == value, "shared payload binding differs: " + key)
    (derived / "Build").mkdir(parents=True)
    os.rename(extracted / kernel["ROOT_LABEL"], derived / "Build" / "Products")
    restored = shared_products_binding(kernel, temp)
    require(restored == metadata["products"], "restored shared products differ from the producer's")
    receipt = {"schema": "v23-shared-restore.v1", "role": "consumer",
               "partitionID": record[SHARED_KEY]["partitionID"],
               "payloadArtifactName": metadata["payloadArtifactName"],
               "archive": {"name": SHARED_TAR, "bytes": int(match.group(2)), "sha256": match.group(1)},
               "metadataSHA256": sha256(metadata_bytes), "productsTreeSHA256": restored["treeSHA256"],
               "xctestrunSHA256": restored["xctestrunSHA256"],
               "restoredProductsRoot": str(derived / "Build" / "Products"),
               "restoreSeconds": round(time.monotonic() - started, 3),
               "head": record["head"], "gitTree": record["gitTree"], "workspace": str(root),
               "simulatorUDID": environment.get("CI_SIMULATOR_UDID"),
               "developmentOnly": True, "acceptance": False}
    write_new_evidence(artifact / SHARED_PAYLOAD_METADATA, metadata_bytes)
    write_new_evidence(artifact / SHARED_RESTORE_RECEIPT, canonical(receipt))
    return receipt


SHARED_FINGERPRINT_PRODUCT_KEYS = ("productsTreeSHA256", "xctestrunSHA256", "entryCount")


def shared_fingerprint(root, artifact, record, environment, phase, kernel=None):
    """Consumer only: the tested products equal the producer's before and after the tests.

    Before: no build tree may exist (restore-only DerivedData), and the DerivedData
    inventory outside the products is recorded. After: the products fingerprint must be
    unchanged, only compile/link evidence fails, and every DerivedData entry added,
    changed or removed by the tests is listed in the delta record."""
    require(shared_role(record) == "consumer", "shared fingerprint is consumer-only")
    require(phase in SHARED_FINGERPRINT_PHASES, "shared fingerprint phase")
    require(read_json(artifact / "native-admission.json") == record, "shared fingerprint admission changed")
    kernel = load_payload_kernel(root) if kernel is None else kernel
    temp = Path(environment["RUNNER_TEMP"])
    derived = temp / "FieldEvidenceDerivedData"
    metadata = read_json(artifact / SHARED_PAYLOAD_METADATA)
    require((artifact / SHARED_RESTORE_RECEIPT).is_file(), "shared fingerprint requires the restore receipt")
    output = artifact / ("v23-shared-fingerprint-%s.json" % phase)
    require(not output.exists() and not output.is_symlink(), "shared fingerprint already recorded")
    before = None
    if phase == "after":
        before = read_json(artifact / "v23-shared-fingerprint-before.json")
        require(type(before) is dict and before.get("phase") == "before"
                and type(before.get("derivedDataEntries")) is list, "shared fingerprint after requires the before record")
        delta_path = artifact / SHARED_DERIVED_DATA_DELTA
        require(not delta_path.exists() and not delta_path.is_symlink(), "shared DerivedData delta already recorded")
    build_evidence = (shared_build_evidence if phase == "before" else shared_compile_evidence)(artifact, temp)
    try:
        products, error = shared_products_binding(kernel, temp), None
    except (OSError, ValueError) as caught:
        products, error = None, str(caught)[:2000]
    inventory = shared_derived_inventory(derived)
    value = {"schema": "v23-shared-fingerprint.v1", "phase": phase,
             "partitionID": record[SHARED_KEY]["partitionID"],
             "productsTreeSHA256": products and products["treeSHA256"],
             "xctestrunSHA256": products and products["xctestrunSHA256"],
             "entryCount": products and products["entryCount"],
             "matchesProducer": products == metadata.get("products"),
             "buildEvidence": build_evidence, "error": error}
    if phase == "before":
        value["derivedDataEntries"] = [dict(inventory[path], path=path) for path in sorted(inventory)]
    else:
        prior = {}
        for item in before["derivedDataEntries"]:
            require(type(item) is dict and isinstance(item.get("path"), str) and item["path"] not in prior,
                    "shared fingerprint before inventory")
            prior[item["path"]] = {key: entry for key, entry in item.items() if key != "path"}
        delta = dict(shared_derived_delta(prior, inventory), schema="v23-shared-deriveddata-delta.v1",
                     partitionID=record[SHARED_KEY]["partitionID"], derivedDataRoot=str(derived),
                     excludedSubtree="Build/Products", beforeEntryCount=len(prior),
                     afterEntryCount=len(inventory), compileEvidence=build_evidence,
                     developmentOnly=True, acceptance=False)
        delta_bytes = canonical(delta)
        write_new_evidence(delta_path, delta_bytes)
        value["matchesBefore"] = all(value[key] == before.get(key) for key in SHARED_FINGERPRINT_PRODUCT_KEYS)
        value["derivedDataDelta"] = {"path": SHARED_DERIVED_DATA_DELTA, "sha256": sha256(delta_bytes),
                                     "addedCount": delta["addedCount"], "changedCount": delta["changedCount"],
                                     "removedCount": delta["removedCount"]}
    write_new_evidence(output, canonical(value))
    require(error is None, "shared products unreadable: " + str(error))
    require(not build_evidence, "shared consumer build evidence present: " + ", ".join(build_evidence))
    require(value["matchesProducer"], "shared products differ from the producer's")
    require(phase == "before" or value["matchesBefore"], "shared products changed during the tests")
    return value


def verify_shared_producer(root, artifact, record, environment):
    metadata_bytes = (artifact / SHARED_PAYLOAD_METADATA).read_bytes()
    metadata = json.loads(metadata_bytes.decode("utf-8"), object_pairs_hook=unique_pairs)
    receipt = read_json(artifact / SHARED_PAYLOAD_RECEIPT)
    temp = Path(environment["RUNNER_TEMP"])
    tar = temp / SHARED_TRANSPORT_DIRECTORY / SHARED_TAR
    require((temp / SHARED_PAYLOAD_DIRECTORY / SHARED_PAYLOAD_METADATA).read_bytes() == metadata_bytes,
            "sealed payload metadata changed")
    expected = shared_metadata_identity(root, record, artifact, environment)
    require(all(metadata.get(key) == value for key, value in expected.items()), "sealed payload identity")
    require(tar.is_file() and not tar.is_symlink() and receipt["archive"]
            == {"name": SHARED_TAR, "bytes": tar.stat().st_size, "sha256": sha256_path(tar)},
            "sealed payload archive changed")
    require((temp / SHARED_TRANSPORT_DIRECTORY / SHARED_TAR_DIGEST).read_bytes()
            == ("%s %d %s\n" % (receipt["archive"]["sha256"], receipt["archive"]["bytes"], SHARED_TAR)).encode(),
            "sealed payload digest record")
    require(receipt["metadataSHA256"] == sha256(metadata_bytes)
            and receipt["productsTreeSHA256"] == metadata["products"]["treeSHA256"]
            and receipt["payloadArtifactName"] == record[SHARED_KEY]["payloadArtifactName"]
            and (receipt["developmentOnly"], receipt["acceptance"]) == (True, False), "sealed payload receipt")
    return {"role": "producer", "payloadArtifactName": receipt["payloadArtifactName"],
            "archive": receipt["archive"], "metadataSHA256": receipt["metadataSHA256"],
            "productsTreeSHA256": receipt["productsTreeSHA256"], "xctestrunSHA256": receipt["xctestrunSHA256"],
            "planSHA256": record[SHARED_KEY]["planSHA256"], "testsExecuted": 0,
            "workerSources": shared_worker_sources(root)}


def verify_shared_consumer(root, artifact, record, selection, environment):
    metadata_bytes = (artifact / SHARED_PAYLOAD_METADATA).read_bytes()
    metadata = json.loads(metadata_bytes.decode("utf-8"), object_pairs_hook=unique_pairs)
    receipt = read_json(artifact / SHARED_RESTORE_RECEIPT)
    temp = Path(environment["RUNNER_TEMP"])
    binding = record[SHARED_KEY]
    require(selection[SHARED_KEY]["partitionID"] == binding["partitionID"], "shared partition binding")
    require(receipt["metadataSHA256"] == sha256(metadata_bytes)
            and receipt["productsTreeSHA256"] == metadata["products"]["treeSHA256"]
            and receipt["payloadArtifactName"] == binding["payloadArtifactName"]
            and receipt["partitionID"] == binding["partitionID"]
            and (receipt["head"], receipt["gitTree"], receipt["workspace"])
            == (record["head"], record["gitTree"], str(root))
            and receipt["simulatorUDID"] == environment.get("CI_NATIVE_CREATED_SIMULATOR_UDID")
            and (receipt["developmentOnly"], receipt["acceptance"]) == (True, False), "shared restore receipt")
    fingerprints = {}
    for phase in SHARED_FINGERPRINT_PHASES:
        value = read_json(artifact / ("v23-shared-fingerprint-%s.json" % phase))
        require(value.get("phase") == phase and value.get("matchesProducer") is True
                and value.get("buildEvidence") == [] and value.get("error") is None
                and value.get("partitionID") == binding["partitionID"]
                and value.get("productsTreeSHA256") == metadata["products"]["treeSHA256"],
                "shared products fingerprint " + phase)
        fingerprints[phase] = value
    after = fingerprints["after"]
    require(after.get("matchesBefore") is True
            and all(after[key] == fingerprints["before"].get(key) for key in SHARED_FINGERPRINT_PRODUCT_KEYS),
            "shared products changed during the tests")
    delta_bytes = (artifact / SHARED_DERIVED_DATA_DELTA).read_bytes()
    delta = json.loads(delta_bytes.decode("utf-8"), object_pairs_hook=unique_pairs)
    summary = after.get("derivedDataDelta")
    require(type(summary) is dict and summary.get("path") == SHARED_DERIVED_DATA_DELTA
            and summary.get("sha256") == sha256(delta_bytes) and delta_bytes == canonical(delta)
            and delta.get("compileEvidence") == [] and delta.get("partitionID") == binding["partitionID"]
            and (delta.get("developmentOnly"), delta.get("acceptance")) == (True, False),
            "shared DerivedData delta record")
    compile_evidence = shared_compile_evidence(artifact, temp)
    require(not compile_evidence, "shared consumer build evidence present: " + ", ".join(compile_evidence))
    return {"role": "consumer", "partitionID": binding["partitionID"],
            "partitionSelectorsSHA256": sha256(canonical(selection["unitTestSelectors"])),
            "payloadArtifactName": receipt["payloadArtifactName"], "archive": receipt["archive"],
            "metadataSHA256": receipt["metadataSHA256"], "restoreSeconds": receipt["restoreSeconds"],
            "productsTreeSHA256Before": fingerprints["before"]["productsTreeSHA256"],
            "productsTreeSHA256After": after["productsTreeSHA256"],
            "derivedDataDelta": summary, "planSHA256": binding["planSHA256"], "buildEvidence": [],
            "workerSources": shared_worker_sources(root)}


def sha256_path(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def verify_checkpoint(root, artifact, record, selection, environment):
    role = shared_role(record) if record["selectionID"] == SHARED_SELECTION_ID else None
    if role == "producer":
        # A build-only producer runs no tests, so it has no diagnostic stream to retain.
        require(environment.get("NATIVE_PRIOR_JOB_STATUS") == "success", "earlier job failure")
        require(not any((artifact / name).exists() for name in (
                    "test-smoke.log", "UnitTests.xcresult", "unit-test-results.json",
                    SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS, SIMULATOR_DIAGNOSTIC_OUTPUT)),
                "shared producer test evidence")
        diagnostic_evidence = None
    else:
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
    if (record["selectionID"] in NO_INDEX_ROUTES or record["selectionID"] == DEV_BATCH_SELECTION_ID
            or role == "producer"):
        build_order["noIndexBuildDiagnostic"] = verify_no_index_build(root, artifact, record, environment)
    if record["selectionID"] in (BUILD_ORDER_SELECTION_ID, NOTIFICATION_INTERRUPTION_SELECTION_ID):
        build_order["buildOrderDiagnostic"] = build_order_observations(artifact, record, simulator["udid"])
    if role == "producer":
        build_order["sharedCoverageEvidence"] = verify_shared_producer(root, artifact, record, environment)
        units = []
    else:
        if role == "consumer":
            build_order["sharedCoverageEvidence"] = verify_shared_consumer(
                root, artifact, record, selection, environment)
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
    parser.add_argument("command", choices=("admit", "verify", "select", "collect-diagnostics", "observe-build-before-boot", "record-no-index-build",
                                            "shared-seal", "shared-restore", "shared-fingerprint"))
    parser.add_argument("--stage", choices=("dispatch", "worker"), default="worker")
    parser.add_argument("--output")
    parser.add_argument("--interrupted", action="store_true")
    parser.add_argument("--phase", choices=SHARED_FINGERPRINT_PHASES)
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
                if record["selectionID"] == SHARED_SELECTION_ID:
                    # The ordered consumer matrix; each entry is one closed partition.
                    stream.write("native_shared_partitions=" + json.dumps(
                        selection[SHARED_KEY]["partitionIDs"], separators=(",", ":")) + "\n")
                    # Each consumer's tier sets its job timeout; the worker admission
                    # refuses a tier that differs from its partition's.
                    tiers = shared_partition_tiers(root)
                    require(list(tiers) == selection[SHARED_KEY]["partitionIDs"], "shared coverage tier matrix")
                    stream.write("native_shared_partition_tiers=" + json.dumps(
                        tiers, separators=(",", ":")) + "\n")
        return
    if args.command in ("observe-build-before-boot", "record-no-index-build",
                        "shared-seal", "shared-restore", "shared-fingerprint"):
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
    if args.command == "shared-seal":
        shared_seal(root, artifact, record, os.environ)
        return
    if args.command == "shared-restore":
        shared_restore(root, artifact, record, os.environ)
        return
    if args.command == "shared-fingerprint":
        require(args.phase is not None, "shared fingerprint phase")
        shared_fingerprint(root, artifact, record, os.environ, args.phase)
        return
    name = "native-admission.json"
    if args.command == "verify":
        record = verify_checkpoint(root, artifact, record, selection, os.environ)
        name = "native-checkpoint.json"
    with (artifact / name).open("xb") as stream:
        stream.write(canonical(record))


if __name__ == "__main__":
    main()
