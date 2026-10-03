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
TIERS = {"RUI1": (300, 1800, 900, 900, 3900), "N8": (300, 1200, 900, 0, 2400), "P12": (300, 600, 900, 900, 3300),
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
UI_BATCH_SELECTION_ID = "v23-ui-batch-rui1"
UI_BATCH_KEY = "uiBatch"
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
COLD_SELECTION_ID = "v23-cold-shared-original-v1"
SHARED_SELECTION_IDS = (SHARED_SELECTION_ID, COLD_SELECTION_ID)
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
SIMULATOR_DIAGNOSTIC_SOURCE_SHA256 = "724DB61680A9BB673E522E3971B6382CC777D3BFFF99972844DCC120CC413D36"
# The original owner-approved allowance source remains admissible for historical replays;
# the current source adds only development timing aggregates (2026-09-24).
# 2026-09-25: the Simulator strict pre-check no longer throws, catches and logs the expected
# mismatch on every call; the fallback predicate, journal and evidence are unchanged.
# 2026-09-25 (owner decision 15): repeats of a kind are journaled as per-kind summaries after
# its exact first event; the fallback predicate and every verification are unchanged. The pin
# is SHA-256 over the committed ProtectedFilePolicy.swift bytes; D18D48D5... joins the history.
# 2026-09-27: reviewed FIFO-race defense adds O_NONBLOCK and a DEBUG boundary witness.
# The exact fallback predicate is unchanged; retain the prior committed source for replays.
# 2026-09-27: reviewed M2 read-only temporal observations append to the exact prior source.
# Recompute the current SHA-256 from those bytes; preserve the prior source for replays.
# 2026-09-27: reviewed idempotent backup exclusion preserves complete requests and all
# final protection predicates; SHA-256 is recomputed from exact approved af9304fd bytes.
# 2026-09-28: recomputed from exact reviewed checkpoint ProtectedFilePolicy.swift;
# checked read-only/owned-effect paths preserve all final predicates. Prior published
# af9304fd source stays available only under the historical replay rules.
# 2026-09-29: exact a67 ProtectedFilePolicy bytes add pre-request witness reproof
# and the typed caller boundary; final protection predicates remain unchanged.
# Preserve the de779 source digest for historical replay.
# 2026-09-29: exact independently reviewed callback20abe makes the synchronous checked
# request boundary nonescaping; verification/policy predicates remain unchanged.
# Recomputed SHA-256 from actual source bytes; retain EE62 as historical replay only.
# 2026-09-30: exact reviewed a154 checked-policy helpers preserve strict/fallback
# predicates; SHA-256 uses real source bytes. Prior20abe remains historical only.
# Prospective PFP724 source-only successor: current raw SHA-256 is recomputed
# from the exact candidate bytes. Prior published a154 is retained for historical
# replay; this private draft supplies no future commit or execution provenance.
SIMULATOR_DIAGNOSTIC_HISTORICAL_SOURCE_SHA256S = ("7391B39F40D4C5DDE3B39AFCCB8A3F0D95037F7FDF0C1333F5D623A40F551A38",
                                                 "FCFF658FCE118760EAC50B13A3941470EA86ED6FB40E78D17E6A573A10DFA5DB",
                                                 "A8B18FFF49DE387183EA9B8B2377669BF1EE9E73A6DB11992178503070EDE139",
                                                 "D18D48D5DB47DD61AD7D979414BD62A1A6798639EDA00B537DB5D6F1D517700E",
                                                 "831C0FB85219183E7CA694F4F260BBB4765FFD929EBCCAE814CE7CC3D231C5B7",
                                                 "4B102F6297E2AF1D02B926E79FEBDDB0362154EBD594FBD56BD929408B135D71",
                                                 "AF9304FDB44AA61638253EF1EFC8AAE4617F2439ECE6C959D2DEE6C06AB7F1A0",
                                                 "755870276940DA63430F323ADE00D7CD6820BB3FC4DC84BDBBA076350D48AB31",
                                                 "EE62E3C5A306D9C60D3210143894EAB94D1CBC19AB82BEE7933AD781E1051DED",
                                                 "20ABE423C0B06B4084B6B5B8EDF6F89EECCA625F97407F1A3637F6A1FB966B41",
                                                 "A154FD5A2D7EE9A9F1FC486237259F2A1D5C829CE3BFA1E0EC569260E3D94CB5")
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



PHASE1_DIAGNOSTIC_INTERVAL = "phase1-diagnostic-copy-interval.json"
PHASE1_DIAGNOSTIC_INTERVAL_SCHEMA = "v23-phase1-diagnostic-copy-interval.v1"


def phase1_diagnostic_mode(root, artifact, environment, admission_artifact, remaining):
    """Read actual event/admission under the incumbent deadline; never accept a mode flag."""
    parent = artifact if admission_artifact is None else Path(admission_artifact)
    admission_path = parent / "native-admission.json"
    event_path = environment.get("GITHUB_EVENT_PATH")
    if event_path is None and not admission_path.exists() and not admission_path.is_symlink() and admission_artifact is None:
        return None
    gate = load_phase1_gates(root)
    raw = gate.regular_bytes(Path(event_path), limit=gate.MAX_EVENT_BYTES) if event_path is not None else None
    plan, _ = gate.plan_from_event(raw) if raw is not None else (None, None)
    record = (gate.decode(gate.regular_bytes(admission_path, limit=PHASE1_WITNESS_BYTES), limit=PHASE1_WITNESS_BYTES)
              if admission_path.exists() or admission_path.is_symlink() else None)
    marked = type(record) is dict and "phase1Gate" in record
    if plan is None:
        require(not marked and admission_artifact is None, "Phase1 diagnostic event/admission missing")
        return None
    require(type(record) is dict and marked, "Phase1 diagnostic gate admission missing")
    require(environment.get("CI_ARTIFACT_DIR") == str(parent)
            and parent.is_dir() and not parent.is_symlink(), "Phase1 diagnostic admitted artifact owner")
    phase = "unit" if admission_artifact is None else "ui"
    require(phase == "unit" or artifact == parent / "phase1-ui-diagnostics", "Phase1 diagnostic UI snapshot owner")
    binding, event_raw, _, selection_record = phase1_worker_context(root, environment, remaining=remaining)
    require(all(record.get(key) == value for key, value in selection_record.items()), "Phase1 diagnostic selected admission")
    require(record["phase1Gate"] == binding and event_raw == raw
            and (phase != "ui" or record.get("selectionID") == UI_BATCH_SELECTION_ID), "Phase1 diagnostic original event/admission")
    for name, expected in (("phase1-original-event.json", event_raw), ("phase1-gate-plan.json", gate.canonical(plan)),
                           ("phase1-event-binding.json", gate.canonical(binding))):
        require(gate.regular_bytes(parent / name, limit=gate.MAX_EVENT_BYTES) == expected,
                "Phase1 diagnostic retained event changed")
    require(all(record.get(key) == value for key, value in source_binding(root).items()), "Phase1 diagnostic protocol source")
    identity = phase1_observation_identity(root, parent, record)
    require(remaining() > 0, "Phase1 diagnostic binding deadline")
    return {"identity": identity, "phase": phase, "before": None, "after": None, "error": None}


def phase1_diagnostic_stat(info, *, file=False):
    require(stat.S_ISREG(info.st_mode) if file else stat.S_ISDIR(info.st_mode), "Phase1 diagnostic source type")
    value = {"device": info.st_dev, "inode": info.st_ino, "mode": info.st_mode, "links": info.st_nlink}
    if file:
        require(info.st_nlink == 1 and 0 <= info.st_size <= SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES,
                "Phase1 diagnostic source file links/size")
        value.update(bytes=info.st_size, modifiedNS=info.st_mtime_ns, changedNS=info.st_ctime_ns)
    return value


def phase1_diagnostic_census(container, check):
    """Bounded exact source snapshot. No scan/read/stat failure can omit a stream."""
    check()
    require(container.is_absolute() and container.resolve(strict=True) == container, "Phase1 diagnostic physical container")
    container_id = phase1_diagnostic_stat(container.lstat())
    leaf = container / SIMULATOR_DIAGNOSTIC_APP_DIRECTORY
    def names():
        check()
        entries = []
        with os.scandir(leaf) as scan:
            for entry in scan:
                check()
                entries.append(entry.name)
                require(len(entries) <= SIMULATOR_DIAGNOSTIC_MAX_FILES, "Phase1 diagnostic source census bound")
        return sorted(entries)
    def directory_identity():
        # exists()/is_dir() may suppress permission and other lookup errors.
        # Only actual ENOENT in the validated plain directory chain means absent.
        current = container
        for component in Path(SIMULATOR_DIAGNOSTIC_APP_DIRECTORY).parts:
            check()
            current = current / component
            try:
                info = current.lstat()
            except FileNotFoundError:
                return None
            phase1_diagnostic_stat(info)
        require(leaf.resolve(strict=True) == leaf, "Phase1 diagnostic physical journal directory")
        return phase1_diagnostic_stat(info)
    leaf_id = directory_identity()
    listed = names() if leaf_id is not None else []
    files, total = [], 0
    for name in listed:
        check()
        require(re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl", name), "Phase1 diagnostic source name")
        path = leaf / name
        identity = phase1_diagnostic_stat(path.lstat(), file=True)
        total += identity["bytes"]
        require(total <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES, "Phase1 diagnostic source total bytes")
        digest, count = hashlib.sha256(), 0
        with path.open("rb", buffering=0) as stream:
            require(phase1_diagnostic_stat(os.fstat(stream.fileno()), file=True) == identity,
                    "Phase1 diagnostic opened source changed")
            while True:
                check()
                chunk = stream.read(SIMULATOR_DIAGNOSTIC_COPY_CHUNK_BYTES)
                if not chunk:
                    break
                count += len(chunk)
                require(count <= identity["bytes"], "Phase1 diagnostic source grew during census")
                digest.update(chunk)
            require(phase1_diagnostic_stat(os.fstat(stream.fileno()), file=True) == identity,
                    "Phase1 diagnostic source changed during census")
        require(count == identity["bytes"] and phase1_diagnostic_stat(path.lstat(), file=True) == identity,
                "Phase1 diagnostic named source changed")
        files.append({"name": name, "identity": identity, "sha256": digest.hexdigest().upper()})
    check()
    require(phase1_diagnostic_stat(container.lstat()) == container_id, "Phase1 diagnostic container changed during census")
    if leaf_id is None:
        require(directory_identity() is None, "Phase1 diagnostic directory appeared during census")
    else:
        require(directory_identity() == leaf_id and names() == listed,
                "Phase1 diagnostic directory changed during census")
        require(all(phase1_diagnostic_stat((leaf / item["name"]).lstat(), file=True) == item["identity"] for item in files),
                "Phase1 diagnostic census file changed")
    check()
    return {"containerPath": str(container), "containerIdentity": container_id,
            "directoryPath": str(leaf), "directoryIdentity": leaf_id, "files": files}


def phase1_diagnostic_lookup(environment, run, remaining, lookup_seconds):
    result = run(["xcrun", "simctl", "get_app_container", environment["CI_SIMULATOR_UDID"],
                  SIMULATOR_DIAGNOSTIC_APP_BUNDLE_ID, "data"], capture_output=True, text=True,
                 timeout=min(lookup_seconds, remaining()), check=False)
    require(remaining() > 0 and result.returncode == 0 and result.stderr == ""
            and result.stdout.endswith("\n") and result.stdout.count("\n") == 1, "Phase1 diagnostic final container lookup")
    return Path(result.stdout[:-1])


def collect_simulator_diagnostic_transport(root, artifact, environment, interrupted=False,
                                           run=None, monotonic=time.monotonic, read_chunk=None,
                                           phase1_admission_artifact=None, _started=None):
    """Select actual gate provenance within the same collection clock, never by a bool."""
    require(type(interrupted) is bool, "diagnostic interruption mode")
    started = monotonic() if _started is None else _started
    require(type(started) in (int, float) and math.isfinite(started) and started <= monotonic(), "diagnostic original start")
    work = SIMULATOR_DIAGNOSTIC_INTERRUPTED_WORK_SECONDS if interrupted else SIMULATOR_DIAGNOSTIC_WORK_SECONDS
    def remaining():
        _require_collection_time(started, monotonic, work)
        return work - (monotonic() - started)
    session = None
    try:
        with _diagnostic_real_time_limit(remaining()):
            session = phase1_diagnostic_mode(root, artifact, environment, phase1_admission_artifact, remaining)
    except (_DiagnosticCollectionDeadline, OSError, subprocess.SubprocessError, ValueError, TypeError, KeyError) as error:
        session = {"identity": None, "phase": "ui" if phase1_admission_artifact is not None else "unit",
                   "before": None, "after": None, "error": "Phase1 diagnostic binding incomplete: " + str(error)[:1000]}
    return _collect_simulator_diagnostic_transport(root, artifact, environment, interrupted=interrupted,
        run=run or subprocess.run, monotonic=monotonic, read_chunk=read_chunk,
        _phase1=session, _started=started if session is not None else None)


def _collect_simulator_diagnostic_transport(root, artifact, environment, interrupted=False,
                                           run=subprocess.run, monotonic=time.monotonic,
                                           read_chunk=None, _phase1=None, _started=None):
    """Collect closed app-container originals; never parse, repair, or infer a PASS."""
    require(type(interrupted) is bool, "diagnostic interruption mode")
    collection_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_COLLECTION_SECONDS if interrupted
                          else SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS)
    work_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_WORK_SECONDS if interrupted
                    else SIMULATOR_DIAGNOSTIC_WORK_SECONDS)
    lookup_seconds = (SIMULATOR_DIAGNOSTIC_INTERRUPTED_LOOKUP_SECONDS if interrupted
                      else SIMULATOR_DIAGNOSTIC_LOOKUP_SECONDS)
    started = monotonic() if _started is None else _started
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
    if _phase1 is None:
        _write_transport_status(artifact, base)
    else:
        with _diagnostic_real_time_limit(collection_seconds - (monotonic() - started)):
            _write_transport_status(artifact, base)
            _require_collection_time(started, monotonic, collection_seconds)
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
            if _phase1 is None:
                if leaf.exists() or leaf.is_symlink():
                    require(leaf.is_dir() and not leaf.is_symlink() and leaf.resolve(strict=True) == leaf,
                            "unsafe diagnostic app directory")
                    entries = sorted(leaf.iterdir(), key=lambda value: value.name)
                else:
                    entries = []
                require(len(entries) <= SIMULATOR_DIAGNOSTIC_MAX_FILES, "diagnostic transport file count")
            else:
                # Even an unresolved gate session must enumerate with the bound.
                # Never materialize the legacy directory list before this census.
                _phase1["before"] = phase1_diagnostic_census(container,
                    lambda: _require_collection_time(started, monotonic, work_seconds))
                entries = [leaf / item["name"] for item in _phase1["before"]["files"]]
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
                    if _phase1 is not None:
                        require(phase1_diagnostic_stat(os.fstat(incoming.fileno()), file=True)
                                == phase1_diagnostic_stat(info, file=True), "Phase1 diagnostic opened copy source changed")
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
            if _phase1 is not None:
                require(_phase1["error"] is None, _phase1["error"] or "Phase1 diagnostic binding")
                def remaining():
                    _require_collection_time(started, monotonic, work_seconds)
                    return work_seconds - (monotonic() - started)
                final_container = phase1_diagnostic_lookup(environment, run, remaining, lookup_seconds)
                _phase1["after"] = phase1_diagnostic_census(final_container,
                    lambda: _require_collection_time(started, monotonic, work_seconds))
                require(_phase1["before"] == _phase1["after"], "Phase1 diagnostic source/container changed during copy")
                expected = [{"name": item["name"], "bytes": item["identity"]["bytes"], "sha256": item["sha256"]}
                            for item in _phase1["before"]["files"]]
                require(expected == originals, "Phase1 diagnostic retained copy differs from source census")
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
        if _phase1 is not None:
            _phase1["error"] = str(error)[:1000]
        base["files"] = originals
        base["fileCount"] = len(originals)
        base["totalBytes"] = sum(value["bytes"] for value in originals)
        base["inventorySHA256"] = sha256(canonical(originals))
    if _phase1 is None:
        _write_transport_status(artifact, base, replace=True)
    else:
        # This uses only the incumbent reserved margin, never a fresh deadline.
        with _diagnostic_real_time_limit(collection_seconds - (monotonic() - started)):
            _require_collection_time(started, monotonic, collection_seconds)
            _write_transport_status(artifact, base, replace=True)
            value = {"schema": PHASE1_DIAGNOSTIC_INTERVAL_SCHEMA, **_phase1,
                "status": "COPY_INTERVAL_OBSERVED" if not interrupted and _phase1["error"] is None else "INCOMPLETE",
                "interrupted": interrupted, "collectionBoundSeconds": collection_seconds, "workBoundSeconds": work_seconds,
                "preReceiptElapsedSeconds": monotonic() - started,
                "transportSHA256": sha256(canonical(base)), "copyIntervalOnly": True, "allLifetimesProven": False}
            load_phase1_gates(root).write_immutable(artifact / PHASE1_DIAGNOSTIC_INTERVAL, canonical(value))
            _require_collection_time(started, monotonic, collection_seconds)
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


def phase1_collect_ui_snapshot(root, artifact, record, environment, *, exit_status, interrupted):
    """Second immutable phase; all setup/binding/copy/fsync shares the existing budget."""
    started = time.monotonic()
    require(type(interrupted) is bool, "Phase1 UI interruption mode")
    bound = SIMULATOR_DIAGNOSTIC_INTERRUPTED_COLLECTION_SECONDS if interrupted else SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS
    work = SIMULATOR_DIAGNOSTIC_INTERRUPTED_WORK_SECONDS if interrupted else SIMULATOR_DIAGNOSTIC_WORK_SECONDS
    with _diagnostic_real_time_limit(work - (time.monotonic() - started)):
        identity = phase1_observation_identity(root, artifact, record)
        require(record.get("selectionID") == UI_BATCH_SELECTION_ID
                and (exit_status is None or type(exit_status) is int), "Phase1 UI finalization identity")
        snapshot = artifact / "phase1-ui-diagnostics"
        snapshot.mkdir(mode=0o700)
        gate = load_phase1_gates(root)
        write_new_evidence(snapshot / "simulator-selection.txt", gate.regular_bytes(artifact / "simulator-selection.txt"))
        _require_collection_time(started, time.monotonic, work)
    transport = collect_simulator_diagnostic_transport(root, snapshot, environment, interrupted=interrupted,
        phase1_admission_artifact=artifact, _started=started)
    with _diagnostic_real_time_limit(bound - (time.monotonic() - started)):
        value = {"schema": "v23-phase1-ui-finalization.v1", **identity,
                 "phase": "ui", "nativeExitStatus": exit_status, "interrupted": interrupted,
                 "transportSHA256": sha256(gate.regular_bytes(snapshot / SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS,
                                                              limit=PHASE1_WITNESS_BYTES)),
                 "transportStatus": transport["status"], "allLifetimesProven": False,
                 "countsAreTotalInvocations": False, "trailingRepeatCountsMayBeUnobserved": True}
        gate.write_immutable(snapshot / "phase1-ui-finalization.json", canonical(value))
        _require_collection_time(started, time.monotonic, bound)
    if exit_status == 0 and not interrupted:
        require(transport["status"] in ("AVAILABLE", "ZERO_USE"), "Phase1 UI diagnostic transport incomplete")
    return value


def phase1_seal_ui_log(root, artifact, record):
    """Called after the outer tee exits, never seal a live partial console log."""
    gate = load_phase1_gates(root)
    snapshot = artifact / "phase1-ui-diagnostics"
    require(snapshot.is_dir() and not snapshot.is_symlink(), "Phase1 UI final snapshot")
    write_new_evidence(snapshot / "test-smoke.log",
                       gate.regular_bytes(artifact / "ui-smoke.log", limit=SHARED_MAX_TEST_LOG_BYTES))
    return persist_simulator_diagnostic_observations(root, snapshot, record)



def phase1_retained_diagnostic_interval(root, artifact, snapshot, record, phase, transport):
    """Recompute a bound copy interval, never reopen the original app container."""
    gate = load_phase1_gates(root)
    raw = gate.regular_bytes(snapshot / PHASE1_DIAGNOSTIC_INTERVAL, limit=PHASE1_WITNESS_BYTES)
    value = gate.decode(raw, limit=PHASE1_WITNESS_BYTES)
    require(type(value) is dict and set(value) == {"schema", "identity", "phase", "before", "after", "error",
        "status", "interrupted", "collectionBoundSeconds", "workBoundSeconds", "preReceiptElapsedSeconds",
        "transportSHA256", "copyIntervalOnly", "allLifetimesProven"}, "Phase1 closed diagnostic interval")
    gate.exact({key: value[key] for key in ("schema", "identity", "phase", "error", "status", "interrupted",
               "collectionBoundSeconds", "workBoundSeconds", "transportSHA256", "copyIntervalOnly", "allLifetimesProven")},
        {"schema": PHASE1_DIAGNOSTIC_INTERVAL_SCHEMA, "identity": phase1_observation_identity(root, artifact, record),
         "phase": phase, "error": None, "status": "COPY_INTERVAL_OBSERVED", "interrupted": False,
         "collectionBoundSeconds": SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS, "workBoundSeconds": SIMULATOR_DIAGNOSTIC_WORK_SECONDS,
         "transportSHA256": sha256(canonical(transport)), "copyIntervalOnly": True, "allLifetimesProven": False},
         "Phase1 diagnostic interval identity/status/budget")
    elapsed = value["preReceiptElapsedSeconds"]
    require(type(elapsed) in (int, float) and math.isfinite(elapsed)
            and 0 <= elapsed < SIMULATOR_DIAGNOSTIC_COLLECTION_SECONDS, "Phase1 diagnostic measured interval")
    gate.exact(value["before"], value["after"], "Phase1 diagnostic source interval changed")
    census = value["before"]
    require(type(census) is dict and set(census) == {"containerPath", "containerIdentity", "directoryPath", "directoryIdentity", "files"},
            "Phase1 closed source census")
    for key in ("containerPath", "directoryPath"):
        path = census[key]
        require(type(path) is str and path.startswith("/") and "\x00" not in path
                and all(p not in (".", "..") for p in path.split("/")), "Phase1 source census path")
    require(census["directoryPath"] == census["containerPath"].rstrip("/") + "/" + SIMULATOR_DIAGNOSTIC_APP_DIRECTORY,
            "Phase1 source journal owner")
    def identity(item, file=False):
        keys = {"device", "inode", "mode", "links"} | ({"bytes", "modifiedNS", "changedNS"} if file else set())
        require(type(item) is dict and set(item) == keys and all(type(v) is int and v >= 0 for v in item.values())
                and item["inode"] > 0 and item["links"] > 0
                and (stat.S_ISREG(item["mode"]) if file else stat.S_ISDIR(item["mode"])), "Phase1 retained source identity")
        if file:
            require(item["links"] == 1 and item["bytes"] <= SIMULATOR_DIAGNOSTIC_MAX_FILE_BYTES,
                    "Phase1 retained source links/size")
    identity(census["containerIdentity"])
    if census["directoryIdentity"] is not None:
        identity(census["directoryIdentity"])
    files = census["files"]
    require(type(files) is list and len(files) <= SIMULATOR_DIAGNOSTIC_MAX_FILES
            and (census["directoryIdentity"] is not None or not files), "Phase1 retained source census bound")
    expected, names = [], []
    for item in files:
        require(type(item) is dict and set(item) == {"name", "identity", "sha256"}
                and type(item["name"]) is str
                and re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\.jsonl", item["name"])
                and gate.digest(item["sha256"]), "Phase1 retained stream census")
        identity(item["identity"], file=True)
        expected.append({"name": item["name"], "bytes": item["identity"]["bytes"], "sha256": item["sha256"]})
        names.append(item["name"])
    require(names == sorted(set(names)) and sum(i["bytes"] for i in expected) <= SIMULATOR_DIAGNOSTIC_MAX_TOTAL_BYTES,
            "Phase1 retained complete stream census")
    gate.exact(expected, transport["files"], "Phase1 retained copy/source census")
    # The existing strict transport parser checks the actual copied files and
    # their complete framed bytes, not just this observation's inventory hash.
    return {"observationSHA256": sha256(raw), "copyIntervalOnly": True, "allLifetimesProven": False}

def phase1_retained_diagnostic_facts(root, artifact, record, expected_binding):
    """Pure retained facts, never functional qualification or invocation totals.

    The caller must first authenticate expected_binding against the original
    event, root attempt and API identity. Complete worker/collector activation is
    deliberately disabled. This primitive cannot prove unobserved app lifetimes
    or replace the independently reviewed cold execution/retention proof.
    """
    gate = load_phase1_gates(root)
    require(type(expected_binding) is dict and expected_binding.get("schema") == gate.EVENT_SCHEMA,
            "Phase1 expected event binding")
    plan = gate.validate_plan(expected_binding.get("plan"))
    require(record.get("phase1Gate") == expected_binding
            and expected_binding.get("planSHA256") == gate.sha(gate.canonical(plan))
            and (record.get("head"), record.get("ref"), record.get("runID"), record.get("runAttempt"))
            == (plan["head"], plan["ref"], expected_binding.get("runID"), "1")
            and expected_binding.get("functionalQualification") == gate.PENDING,
            "Phase1 diagnostic original binding")
    require(record.get("selectionID") == plan["selection"], "Phase1 diagnostic selection")
    role = shared_role(record) if plan["selection"] == SHARED_SELECTION_ID else "rui1"
    if role == "producer":
        require(not any((artifact / name).exists() or (artifact / name).is_symlink() for name in (
            "test-smoke.log", "UnitTests.xcresult", "unit-test-results.json",
            SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS, SIMULATOR_DIAGNOSTIC_OUTPUT, "phase1-ui-diagnostics")),
            "Phase1 producer has no test diagnostics")
        return {"schema": "v23-phase1-retained-diagnostics.v1", "planSHA256": expected_binding["planSHA256"],
                "status": "NOT_APPLICABLE_BUILD_ONLY", "phases": {}, "uniqueRetainedFrames": 0,
                "countsAsPerKindProtectionSuccess": False, "functionalQualification": gate.PENDING,
                "simulatorProtection": "UNSUPPORTED", "physicalProtection": "UNVERIFIED/DEFERRED",
                "physicalProtectionReleaseBlocker": True, "providerQualification": False,
                "acceptance": False, "releaseReady": False}
    phases = [("unit", artifact, "test-smoke.log")]
    if role == "rui1":
        phases.append(("ui", artifact / "phase1-ui-diagnostics", "ui-smoke.log"))
    else:
        require(not (artifact / "phase1-ui-diagnostics").exists()
                and not (artifact / "phase1-ui-diagnostics").is_symlink(), "unexpected Phase1 UI diagnostics")
    facts, frames, streams_by_phase = {}, {}, {}
    for phase, snapshot, original_log in phases:
        require(snapshot.is_dir() and not snapshot.is_symlink(), "Phase1 " + phase + " diagnostic snapshot")
        raw_log = gate.regular_bytes(artifact / original_log, limit=SHARED_MAX_TEST_LOG_BYTES)
        require(b"V23_PROTECTED_FILE_DIAGNOSTIC_JOURNAL_FAILURE" not in raw_log,
                "Phase1 " + phase + " diagnostic writer failure/poison")
        if phase == "ui":
            final_raw = gate.regular_bytes(snapshot / "phase1-ui-finalization.json", limit=PHASE1_WITNESS_BYTES)
            final = gate.decode(final_raw, limit=PHASE1_WITNESS_BYTES)
            identity = phase1_observation_identity(root, artifact, record)
            expected_final = {"schema": "v23-phase1-ui-finalization.v1", **identity,
                "phase": "ui", "nativeExitStatus": 0, "interrupted": False,
                "transportSHA256": sha256(gate.regular_bytes(snapshot / SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS,
                                                             limit=PHASE1_WITNESS_BYTES)),
                "transportStatus": read_json(snapshot / SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS)["status"],
                "allLifetimesProven": False, "countsAreTotalInvocations": False,
                "trailingRepeatCountsMayBeUnobserved": True}
            gate.exact(final, expected_final, "Phase1 completed UI finalization")
            # A sealed byte alias lets the unchanged strict parser read its closed
            # log name. It cannot substitute the earlier unit log for the UI log.
            require(gate.regular_bytes(snapshot / "test-smoke.log", limit=SHARED_MAX_TEST_LOG_BYTES) == raw_log,
                    "Phase1 UI original log alias")
            require(gate.regular_bytes(snapshot / "simulator-selection.txt")
                    == gate.regular_bytes(artifact / "simulator-selection.txt"), "Phase1 UI Simulator binding")
        evidence, error = simulator_diagnostic_observations(root, snapshot, record)
        require(error is None and evidence["parseStatus"] == "PASS"
                and evidence["testLog"]["availability"] == "AVAILABLE",
                "Phase1 " + phase + " complete emitted diagnostic transport")
        require(read_json(snapshot / SIMULATOR_DIAGNOSTIC_OUTPUT) == evidence,
                "Phase1 " + phase + " retained diagnostic recomputation")
        require(evidence["transport"].get("schema") == SIMULATOR_DIAGNOSTIC_TRANSPORT_SCHEMA
                and evidence["transport"].get("collectionMode") == "completed",
                "Phase1 " + phase + " completed original transport")
        interval = phase1_retained_diagnostic_interval(root, artifact, snapshot, record, phase, evidence["transport"])
        phase_frames = {}
        for frame in evidence.get("rawRecords", []):
            key = (frame["streamID"], frame["sequence"])
            require(key not in phase_frames, "Phase1 duplicate diagnostic frame")
            phase_frames[key] = frame
            require(key not in frames or frames[key] == frame, "Phase1 substituted diagnostic prefix")
        streams_by_phase[phase] = {key[0] for key in phase_frames}
        if phase == "ui":
            # Streams absent after an installation/erase remain retained in the
            # immutable unit snapshot. Any stream that survives must retain its
            # complete prior prefix. Cold review must establish lifecycle scope.
            require(all(key in phase_frames for key in frames if key[0] in streams_by_phase[phase]),
                    "Phase1 truncated surviving diagnostic stream")
        frames.update(phase_frames)
        facts[phase] = {"copyInterval": interval, "originalLog": original_log, "originalLogSHA256": sha256(raw_log),
                       "transportSHA256": sha256((snapshot / SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS).read_bytes()),
                       "observationsSHA256": sha256(canonical(evidence)), "retainedFrames": len(phase_frames),
                       "retainedOccurrences": evidence["occurrenceCount"],
                       "zeroUseObserved": evidence["zeroUseObserved"]}
    return {"schema": "v23-phase1-retained-diagnostics.v1", "planSHA256": expected_binding["planSHA256"],
            "status": "COMPLETE_RETAINED_EMITTED_TRANSPORT", "phases": facts,
            "uniqueRetainedFrames": len(frames),
            "unitStreamsRetainedOnlyInEarlierSnapshot": sorted(streams_by_phase["unit"] - streams_by_phase.get("ui", set()))
                if role == "rui1" else [],
            "phaseOccurrenceCountsAreAdditive": False, "countsAreTotalInvocations": False,
            "trailingRepeatCountsMayBeUnobserved": True, "allLifetimesProven": False,
            "countsAsPerKindProtectionSuccess": False, "simulatorProtection": "UNSUPPORTED",
            "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True,
            "providerQualification": False, "acceptance": False, "releaseReady": False,
            "functionalQualification": gate.PENDING}


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
    ui_batch = UI_BATCH_KEY in selection
    development_batch = DEV_BATCH_KEY in selection
    shared = SHARED_KEY in selection
    keys = {"schemaVersion", "taskID", "tier", "runUISmoke",
            "unitTestSelectors", "uiTestSelectors", *BUDGET_KEYS}
    require(set(selection) == ((keys | {UI_BATCH_KEY}) if ui_batch else (keys | {DEV_BATCH_KEY}) if development_batch
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
    require(len(selection["uiTestSelectors"]) == (3 if ui_batch else int(ui)), "UI method count")
    require(ui_batch == (selection["tier"] == "RUI1"), "RUI1 closed tier")
    if ui_batch:
        module = load_ui_evidence(Path(__file__).resolve().parents[1])
        module.validate_binding(selection[UI_BATCH_KEY])
        require(tuple(selection["unitTestSelectors"]) == module.UNITS
                and tuple(selection["uiTestSelectors"]) == module.UI, "RUI1 exact methods")
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


def load_ui_evidence(root):
    source = root / "Scripts/v23-ui-evidence.py"
    require(source.is_file() and not source.is_symlink(), "RUI1 verifier source")
    spec = importlib.util.spec_from_file_location("v23_ui_evidence", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
    if selection_id == UI_BATCH_SELECTION_ID:
        require((role, partition, payload) == ("none", "", ""), "RUI1 independent route")
        resolve_selection(default, selection_map, DEFAULT_SELECTION_ID)
        selected = load_ui_evidence(root).selection(root)
    elif selection_id == DEV_BATCH_SELECTION_ID:
        # The checked-in pool and map keep every existing check; only the exact
        # ordered methods come from the committed development batch at this head.
        require((role, partition, payload) == ("none", "", ""), "V23 shared inputs outside the shared route")
        resolve_selection(default, selection_map, DEFAULT_SELECTION_ID)
        selected = development_batch_selection(root)
    elif selection_id in SHARED_SELECTION_IDS:
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


def load_phase1_gates(root):
    path = root / "Scripts/v23-phase1-gates.py"
    require(path.is_file() and not path.is_symlink(), "Phase1 contract source")
    spec = importlib.util.spec_from_file_location("v23_phase1_gates_native", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def refuse_inactive_phase1_event(root, environment):
    """A manual workflow invocation cannot bypass the inactive dispatcher guard.

    Empty/absent plan keeps existing native admission and output unchanged. No
    environment-only plan or protection override can activate this route.
    """
    event_path = environment.get("GITHUB_EVENT_PATH")
    if event_path is None:
        return
    gate = load_phase1_gates(root)
    plan, _ = gate.plan_from_event(gate.regular_bytes(Path(event_path), limit=gate.MAX_EVENT_BYTES))
    if plan is not None:
        binding, _, _, _ = phase1_worker_context(root, environment)
        gate.refuse_dispatch()
        return binding  # Dormant until the independently reviewed activation change.


def phase1_worker_context(root, environment, *, remaining=None):
    """Read actual caller event and checkout facts, not caller-supplied hashes.

    Used by the retained-proof caller as well as the future admitted worker. It
    does not create an original or bypass refuse_inactive_phase1_event.
    """
    gate = load_phase1_gates(root)
    event_path = environment.get("GITHUB_EVENT_PATH")
    require(type(event_path) is str and event_path, "Phase1 actual caller event path")
    raw = gate.regular_bytes(Path(event_path), limit=gate.MAX_EVENT_BYTES)
    plan, _ = gate.plan_from_event(raw)
    require(plan is not None, "Phase1 actual caller plan")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True,
                                   **({"timeout": remaining()} if remaining is not None else {})).strip()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True,
                                   **({"timeout": remaining()} if remaining is not None else {})).strip()
    selected, selection_record = selected_input(root, environment)
    require(selection_record["selectionID"] == plan["selection"], "Phase1 actual worker selection")
    resolved = shared_selection(root) if plan["selection"] == SHARED_SELECTION_ID else selected
    sources = {path: sha256(gate.regular_bytes(root / path, limit=PHASE1_WITNESS_BYTES)) for path in gate.SOURCES}
    binding = gate.bind_original_event(raw, environment, head=head, tree=tree,
                                      resolved_bytes=canonical(resolved), sources=sources)
    return binding, raw, selected, selection_record


def cold_worker_context(root, environment, *, remaining=None):
    """Bind the real development event, checkout and full shared census; never a gate."""
    gate = load_phase1_gates(root)
    require(not environment.get("V23_COLD_ORIGINAL_PLAN") and not environment.get(gate.COLD_PLAN_INPUT),
            "environment-only cold intent is refused")
    event_path = environment.get("GITHUB_EVENT_PATH")
    require(type(event_path) is str and event_path, "cold actual caller event path")
    raw = gate.regular_bytes(Path(event_path), limit=gate.MAX_EVENT_BYTES)
    plan, _ = gate.cold_plan_from_event(raw)
    require(plan is not None, "cold actual caller intent")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True,
                                   **({"timeout": remaining()} if remaining is not None else {})).strip()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True,
                                   **({"timeout": remaining()} if remaining is not None else {})).strip()
    selected, selection_record = selected_input(root, environment)
    require(selection_record["selectionID"] == COLD_SELECTION_ID, "cold actual worker selection")
    sources = {path: sha256(gate.regular_bytes(root / path, limit=PHASE1_WITNESS_BYTES)) for path in gate.SOURCES}
    binding = gate.bind_cold_original_event(raw, environment, head=head, tree=tree,
                    resolved_bytes=canonical(shared_selection(root)), sources=sources)
    return binding, raw, selected, selection_record


def cold_event_admission(root, environment, selection_record):
    if (environment.get("GITHUB_EVENT_PATH") is None and selection_record["selectionID"] != COLD_SELECTION_ID
            and not environment.get("V23_COLD_ORIGINAL_PLAN") and not environment.get("v23_cold_original_plan")):
        return None
    gate = load_phase1_gates(root)
    require(not environment.get("V23_COLD_ORIGINAL_PLAN") and not environment.get(gate.COLD_PLAN_INPUT),
            "environment-only cold intent is refused")
    path = environment.get("GITHUB_EVENT_PATH")
    plan = None
    if path is not None:
        plan, _ = gate.cold_plan_from_event(gate.regular_bytes(Path(path), limit=gate.MAX_EVENT_BYTES))
    if plan is None and selection_record["selectionID"] != COLD_SELECTION_ID:
        return None
    require(plan is not None and selection_record["selectionID"] == COLD_SELECTION_ID,
            "cold selection requires its dedicated genuine event")
    return cold_worker_context(root, environment)[0]


def admission(selection, environment, checkout_head, stage, selection_record=None, root=None):
    """Validate actual source inputs. Return None only for unchanged legacy routes."""
    e = environment
    if root is None:
        root = Path(__file__).resolve().parents[1]
    phase1_binding = refuse_inactive_phase1_event(root, e)
    if selection_record is None:
        selection_record = {"selectionID": DEFAULT_SELECTION_ID,
                            "selectionSHA256": sha256(canonical(selection)), "selectionMapSHA256": ""}
    cold_binding = cold_event_admission(root, e, selection_record)
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
        if selection_record["selectionID"] in SHARED_SELECTION_IDS:
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
    shared = (selection_record["selectionID"] in SHARED_SELECTION_IDS or SHARED_KEY in selection
              or SHARED_KEY in selection_record)
    if not shared:
        require(shared_route_environment(e) == ("none", "", ""), "V23 shared inputs outside the shared route")
    if selection_record["selectionID"] == UI_BATCH_SELECTION_ID or UI_BATCH_KEY in selection:
        require(selection_record["selectionID"] == UI_BATCH_SELECTION_ID
                and selection == load_ui_evidence(root).selection(root), "RUI1 committed input binding")
        require(provider == "github" and label == "macos-26", "RUI1 GitHub only")
        require(e["GITHUB_RUN_ATTEMPT"] == "1", "RUI1 original only")
    elif development_batch:
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
        require(selection_record["selectionID"] in SHARED_SELECTION_IDS, "shared coverage selector binding")
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
            **({"phase1Gate": phase1_binding} if phase1_binding is not None else {}),
            **({"coldOriginal": cold_binding} if cold_binding is not None else {}),
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


def no_index_build_receipt(root, artifact, record, environment, *, command_artifact=None):
    development_batch = record["selectionID"] == DEV_BATCH_SELECTION_ID
    shared = record["selectionID"] in SHARED_SELECTION_IDS
    if shared:
        require(shared_role(record) == "producer", "shared coverage build is producer-only")
    unpinned = development_batch or shared or record["selectionID"] == UI_BATCH_SELECTION_ID
    require(record["selectionID"] in NO_INDEX_ROUTES or unpinned, "no-index admitted selection")
    require(read_json(artifact / "native-admission.json") == record, "no-index admission changed")
    from pathlib import PurePosixPath
    command_root = artifact if command_artifact is None else command_artifact
    e = environment
    require(e.get("PROJECT_PATH") == "FieldEvidenceApp.xcodeproj"
            and e.get("SCHEME") == "FieldEvidenceApp" and e.get("CONFIGURATION") == "Debug"
            and e.get("CODE_SIGNING_ALLOWED") == "NO", "no-index build configuration")
    destination = "platform=iOS Simulator,id=" + e["CI_SIMULATOR_UDID"]
    require(e.get("CI_DESTINATION") == destination, "no-index exact destination")
    require(e.get("CI_ARTIFACT_DIR") == str(command_root), "no-index artifact path")
    runner_temp = Path(e["RUNNER_TEMP"]) if command_artifact is None else PurePosixPath(e["RUNNER_TEMP"])
    arguments = ["xcodebuild", "-project", e["PROJECT_PATH"], "-scheme", e["SCHEME"],
                 "-configuration", e["CONFIGURATION"], "-destination", destination,
                 "-derivedDataPath", str(runner_temp / "FieldEvidenceDerivedData"),
                 "-resultBundlePath", str(command_root / "Build.xcresult"),
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


def verify_no_index_build(root, artifact, record, environment, *, command_artifact=None):
    expected = no_index_build_receipt(root, artifact, record, environment, command_artifact=command_artifact)
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
    binding = record.get(SHARED_KEY) if record.get("selectionID") in SHARED_SELECTION_IDS else None
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
    return {"schema": SHARED_PAYLOAD_SCHEMA, "routeID": record["selectionID"],
            "repository": record["repository"], "ref": record["ref"], "head": record["head"],
            "gitTree": record["gitTree"], "workspace": str(root),
            "runID": record["runID"], "runAttempt": record["runAttempt"],
            "payloadArtifactName": binding["payloadArtifactName"], "planSHA256": binding["planSHA256"],
            "partitionsSHA256": binding["partitionsSHA256"],
            "toolchain": shared_toolchain(artifact, environment),
            "developmentOnly": True, "acceptance": False}


PHASE1_WITNESS_SCHEMA = "v23-phase1-shared-live-observation.v1"
PHASE1_WITNESS_STAGES = ("seal", "restore", "before", "after")
PHASE1_WITNESS_BYTES = 32 * 1024 * 1024
PHASE1_WITNESS_ENTRIES = 100000
PHASE1_ACTIVITY_TOTAL_BYTES = 128 * 1024 * 1024


def phase1_observation_identity(root, artifact, record):
    """Source binding only; root/API authentication remains the collector's duty."""
    gate = load_phase1_gates(root)
    binding = record.get("phase1Gate")
    require(type(binding) is dict and binding.get("schema") == gate.EVENT_SCHEMA,
            "Phase1 live observation event")
    plan = gate.validate_plan(binding.get("plan"))
    require((record.get("head"), record.get("gitTree"), record.get("ref"), record.get("selectionID"))
            == (plan["head"], plan["tree"], plan["ref"], plan["selection"])
            and binding.get("planSHA256") == gate.sha(gate.canonical(plan))
            and binding.get("runID") == record.get("runID")
            and record.get("runAttempt") == binding.get("runAttempt") == "1"
            and binding.get("functionalQualification") == gate.PENDING,
            "Phase1 live observation original identity")
    require(plan["sources"] == {path: sha256(gate.regular_bytes(root / path, limit=PHASE1_WITNESS_BYTES))
                                 for path in gate.SOURCES}, "Phase1 live observation source closure")
    require(gate.regular_bytes(artifact / "native-admission.json", limit=PHASE1_WITNESS_BYTES)
            == canonical(record), "Phase1 live observation admission bytes")
    return {"eventBindingSHA256": sha256(gate.canonical(binding)),
            "admissionSHA256": sha256(canonical(record)), "planSHA256": binding["planSHA256"],
            "head": record["head"], "gitTree": record["gitTree"], "ref": record["ref"],
            "runID": record["runID"], "runAttempt": "1", "sourceSHA256": plan["sources"],
            "functionalQualification": gate.PENDING, "executionScope": "phase1-functional-gate",
            "offlineFilesystemReplay": False, "simulatorProtection": "UNSUPPORTED",
            "physicalProtection": "UNVERIFIED/DEFERRED", "physicalProtectionReleaseBlocker": True,
            "acceptance": False, "providerQualification": False, "releaseReady": False}


def phase1_relative_path(value):
    require(type(value) is str and value and "\\" not in value and "\x00" not in value
            and not value.startswith("/") and all(part not in ("", ".", "..") for part in value.split("/")),
            "Phase1 retained relative path")
    return value


def phase1_inventory(entries, *, products=False):
    """Closed retained census. Never silently truncate or treat links as files."""
    require(type(entries) is list and len(entries) <= PHASE1_WITNESS_ENTRIES,
            "Phase1 complete inventory bound")
    prior, folded = None, set()
    for entry in entries:
        require(type(entry) is dict, "Phase1 inventory entry")
        path = phase1_relative_path(entry.get("path"))
        require((prior is None or prior < path) and path.casefold() not in folded,
                "Phase1 inventory order or duplicate")
        prior = path
        folded.add(path.casefold())
        kind = entry.get("type")
        keys = {"path", "type"} | ({"mode"} if products else set())
        if kind == "file":
            keys |= {"size", "sha256"}
            require(type(entry.get("size")) is int and entry["size"] >= 0
                    and type(entry.get("sha256")) is str
                    and re.fullmatch(r"[0-9A-F]{64}", entry["sha256"]), "Phase1 inventory file")
        else:
            require(kind == "directory", "Phase1 inventory nonregular entry")
        require(set(entry) == keys, "Phase1 inventory closed keys")
        if products:
            require(type(entry["mode"]) is int and 0 <= entry["mode"] <= 0o777,
                    "Phase1 inventory mode")
    require(len(canonical(entries)) <= PHASE1_WITNESS_BYTES, "Phase1 complete inventory byte bound")
    return entries


def phase1_live_inventory(root, kernel, *, products=False, skip=None):
    """Gate-local census: scan/stat/read errors propagate, including denied children.

    Keep the legacy walkers and receipts unchanged. Products use their existing
    kernel schema and limits; DerivedData excludes only the product subtree.
    This witnesses the live tree, not a later offline filesystem replay.
    """
    root_stat = root.lstat()
    require(stat.S_ISDIR(root_stat.st_mode) and root.resolve() == root, "Phase1 census root")
    entries, pending, folded, total = [], [(root, root_stat)], set(), 0
    member_limit = min(PHASE1_WITNESS_ENTRIES, kernel["MAX_MEMBERS"]) if products else PHASE1_WITNESS_ENTRIES
    while pending:
        directory, expected = pending.pop()
        current = directory.lstat()
        require(stat.S_ISDIR(current.st_mode) and (current.st_dev, current.st_ino)
                == (expected.st_dev, expected.st_ino), "Phase1 census directory changed")
        # os.walk/rglob may swallow scandir errors and return a partial tree.
        children = []
        with os.scandir(directory) as scan:
            for child in scan:
                children.append(child)
                require(len(children) + len(entries) <= member_limit + (1 if skip else 0),
                        "Phase1 live census member bound")
        for child in sorted(children, key=lambda item: item.name):
            path = directory / child.name
            info = path.lstat()
            relative = path.relative_to(root).as_posix()
            phase1_relative_path(relative)
            require(relative.casefold() not in folded, "Phase1 live census case collision")
            folded.add(relative.casefold())
            require(stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode),
                    "Phase1 live census nonregular entry")
            if path == skip:
                require(stat.S_ISDIR(info.st_mode), "Phase1 census excluded product root")
                continue
            entry = {"path": relative, "type": "directory"}
            if products:
                kernel["safe_relative"](relative)
                require(not stat.S_IMODE(info.st_mode) & 0o7000, "Phase1 census special permissions")
                entry["mode"] = stat.S_IMODE(info.st_mode)
            if stat.S_ISDIR(info.st_mode):
                pending.append((path, info))
            else:
                total += info.st_size
                require(not products or total <= kernel["MAX_ARCHIVE_BYTES"], "Phase1 live census byte bound")
                digest = hashlib.sha256()
                with path.open("rb") as stream:
                    opened = os.fstat(stream.fileno())
                    require(stat.S_ISREG(opened.st_mode) and
                            (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns)
                            == (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns),
                            "Phase1 census file changed before read")
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        digest.update(chunk)
                    after = os.fstat(stream.fileno())
                    require((after.st_size, after.st_mtime_ns) == (info.st_size, info.st_mtime_ns),
                            "Phase1 census file changed during read")
                entry.update(type="file", size=info.st_size, sha256=digest.hexdigest().upper())
            entries.append(entry)
            require(len(entries) <= member_limit, "Phase1 live census member bound")
    return phase1_inventory(sorted(entries, key=lambda item: item["path"]), products=products)


def phase1_product_inventory(root, kernel):
    entries = phase1_live_inventory(root, kernel, products=True)
    require(entries == kernel["inventory"](root), "Phase1 product census differs from kernel")
    return entries


def phase1_derived_inventory(root, kernel):
    entries = phase1_live_inventory(root, kernel, skip=root / "Build/Products")
    inventory = {item["path"]: {key: value for key, value in item.items() if key != "path"} for item in entries}
    require(inventory == shared_derived_inventory(root), "Phase1 DerivedData census differs from fingerprint")
    return inventory


def phase1_tar_census(path, kernel):
    entries = []
    with tarfile.open(path, "r:") as archive:
        for member in archive:
            require(len(entries) < PHASE1_WITNESS_ENTRIES, "Phase1 archive census bound")
            require(member.name.startswith("FieldEvidencePayload/"), "Phase1 archive root")
            relative = phase1_relative_path(member.name.removeprefix("FieldEvidencePayload/"))
            require(member.isdir() or member.isreg(), "Phase1 archive nonregular member")
            require(member.size == 0 if member.isdir() else member.size >= 0, "Phase1 archive member size")
            entries.append({"path": relative, "type": "directory" if member.isdir() else "file",
                            "size": member.size, "mode": member.mode})
    require(0 < len(entries) <= kernel["MAX_MEMBERS"] and len(canonical(entries)) <= PHASE1_WITNESS_BYTES,
            "Phase1 complete archive census")
    require([item["path"] for item in entries] == sorted({item["path"] for item in entries}),
            "Phase1 archive census order or duplicate")
    return entries


def phase1_shared_live_observation(root, artifact, record, environment, stage, kernel,
                                   *, source_before=None):
    """Bounded live witness at an existing successful kernel/checkpoint boundary.

    Raw payloads retain their existing retention policy. These observations name
    live checks; their hashes cannot substitute for authenticated artifact origin.
    Legacy development receipts are retained as protocol facts, never relabelled.
    """
    require(stage in PHASE1_WITNESS_STAGES, "Phase1 live observation stage")
    identity = phase1_observation_identity(root, artifact, record)
    role = shared_role(record)
    require((stage == "seal") == (role == "producer"), "Phase1 live observation role")
    temp = Path(environment["RUNNER_TEMP"])
    payload = temp / SHARED_PAYLOAD_DIRECTORY if stage == "seal" else temp
    entries = phase1_product_inventory(payload / kernel["ROOT_LABEL"], kernel)
    products = shared_products_binding(kernel, payload)
    require(kernel["object_sha"](entries) == products["treeSHA256"], "Phase1 live product inventory changed")
    metadata = read_json(artifact / SHARED_PAYLOAD_METADATA)
    require(products == metadata["products"], "Phase1 live products differ from producer")
    value = {"schema": PHASE1_WITNESS_SCHEMA, **identity, "stage": stage, "role": role,
             "partitionID": record[SHARED_KEY].get("partitionID"), "workspace": str(root),
             "runnerTemp": str(temp), "artifactDirectory": str(artifact),
             "payloadArtifactName": record[SHARED_KEY]["payloadArtifactName"],
             "metadataSHA256": sha256((artifact / SHARED_PAYLOAD_METADATA).read_bytes()),
             "products": products, "productInventory": entries}
    if stage in ("seal", "restore"):
        receipt_name = SHARED_PAYLOAD_RECEIPT if stage == "seal" else SHARED_RESTORE_RECEIPT
        receipt = read_json(artifact / receipt_name)
        tar = temp / (SHARED_TRANSPORT_DIRECTORY if stage == "seal" else SHARED_DOWNLOAD_DIRECTORY) / SHARED_TAR
        require(receipt["archive"] == {"name": SHARED_TAR, "bytes": tar.stat().st_size,
                                       "sha256": kernel["sha256_file"](tar)}, "Phase1 observed payload archive")
        value.update(archive=receipt["archive"], archiveMemberCensus=phase1_tar_census(tar, kernel),
                     receiptSHA256=sha256((artifact / receipt_name).read_bytes()))
        if stage == "seal":
            after = phase1_product_inventory(temp / "FieldEvidenceDerivedData/Build/Products", kernel)
            require(source_before == after, "Phase1 original products changed while sealing")
            value.update(sourceProductInventory=after, sourceUnchangedDuringSeal=True,
                         testsExecuted=0, diagnostics="NOT_APPLICABLE_BUILD_ONLY")
        else:
            value.update(safeExtractionObserved=True, extractionKernelSHA256=identity["sourceSHA256"][SHARED_PAYLOAD_KERNEL])
    else:
        inventory = phase1_derived_inventory(temp / "FieldEvidenceDerivedData", kernel)
        value["derivedDataInventory"] = phase1_inventory([dict(inventory[p], path=p) for p in sorted(inventory)])
        value["fingerprintSHA256"] = sha256((artifact / ("v23-shared-fingerprint-" + stage + ".json")).read_bytes())
        value["activityLogs"] = []
        if stage == "after":
            directory = artifact / "phase1-activity-logs"
            directory.mkdir(mode=0o700)
            total = 0
            gate = load_phase1_gates(root)
            for entry in value["derivedDataInventory"]:
                if not (entry["path"].startswith("Logs/Build/") and entry["path"].endswith(".xcactivitylog")
                        and entry["type"] == "file"):
                    continue
                total += entry["size"]
                require(total <= PHASE1_ACTIVITY_TOTAL_BYTES, "Phase1 activity log retention bound")
                raw = gate.regular_bytes(temp / "FieldEvidenceDerivedData" / entry["path"],
                                         limit=PHASE1_ACTIVITY_TOTAL_BYTES)
                require(len(raw) == entry["size"] and sha256(raw) == entry["sha256"],
                        "Phase1 activity log changed during retention")
                name = "%06d.xcactivitylog" % len(value["activityLogs"])
                write_new_evidence(directory / name, raw)
                require(shared_activity_log_compile_step(directory / name) is None,
                        "Phase1 retained activity log compile evidence")
                value["activityLogs"].append({"sourcePath": entry["path"], "retainedPath": name,
                                              "bytes": len(raw), "sha256": sha256(raw)})
            require(inventory == phase1_derived_inventory(temp / "FieldEvidenceDerivedData", kernel),
                    "Phase1 DerivedData changed during retention")
    raw = canonical(value)
    require(len(raw) <= PHASE1_WITNESS_BYTES, "Phase1 complete live observation byte bound")
    with (artifact / ("phase1-shared-live-" + stage + ".json")).open("xb") as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    return value


def phase1_retained_shared_facts(root, artifact, record, expected_binding):
    """Recompute retained facts, without opening original runner temp/payload paths.

    The caller first authenticates expected_binding, artifact digests and the sole
    root attempt. This function is not that authentication or cold qualification.
    """
    gate = load_phase1_gates(root)
    require(record.get("phase1Gate") == expected_binding, "Phase1 shared expected original")
    identity = phase1_observation_identity(root, artifact, record)
    kernel = load_payload_kernel(root)
    role = shared_role(record)
    stages = ("seal",) if role == "producer" else ("restore", "before", "after")
    metadata_raw = gate.regular_bytes(artifact / SHARED_PAYLOAD_METADATA, limit=PHASE1_WITNESS_BYTES)
    metadata = gate.decode(metadata_raw, limit=PHASE1_WITNESS_BYTES)
    require(all(metadata.get(key) == record.get(key) for key in ("repository", "ref", "head", "gitTree", "runID", "runAttempt"))
            and metadata.get("payloadArtifactName") == record[SHARED_KEY]["payloadArtifactName"]
            and metadata.get("planSHA256") == record[SHARED_KEY]["planSHA256"]
            and metadata.get("partitionsSHA256") == record[SHARED_KEY]["partitionsSHA256"],
            "Phase1 retained payload original identity")
    observations = {}
    for stage in stages:
        raw = gate.regular_bytes(artifact / ("phase1-shared-live-" + stage + ".json"), limit=PHASE1_WITNESS_BYTES)
        value = gate.decode(raw, limit=PHASE1_WITNESS_BYTES)
        keys = {"schema", *identity, "stage", "role", "partitionID", "workspace", "runnerTemp",
                "artifactDirectory", "payloadArtifactName", "metadataSHA256", "products", "productInventory"}
        keys |= ({"archive", "archiveMemberCensus", "receiptSHA256"} if stage in ("seal", "restore")
                 else {"derivedDataInventory", "fingerprintSHA256", "activityLogs"})
        keys |= ({"sourceProductInventory", "sourceUnchangedDuringSeal", "testsExecuted", "diagnostics"}
                 if stage == "seal" else {"safeExtractionObserved", "extractionKernelSHA256"}
                 if stage == "restore" else set())
        require(type(value) is dict and set(value) == keys and value["schema"] == PHASE1_WITNESS_SCHEMA,
                "Phase1 closed live observation")
        gate.exact({key: value[key] for key in identity}, identity, "Phase1 live observation identity")
        require((value["stage"], value["role"], value["partitionID"], value["payloadArtifactName"])
                == (stage, role, record[SHARED_KEY].get("partitionID"), record[SHARED_KEY]["payloadArtifactName"])
                and value["metadataSHA256"] == sha256(metadata_raw), "Phase1 observation payload/role")
        for name in ("workspace", "runnerTemp", "artifactDirectory"):
            require(type(value[name]) is str and value[name].startswith("/") and "\x00" not in value[name]
                    and all(part not in (".", "..") for part in value[name].split("/")),
                    "Phase1 original runner path spelling")
        require(value["workspace"] == metadata.get("workspace"), "Phase1 original workspace binding")
        if observations:
            require(all(value[key] == observations[stages[0]][key]
                        for key in ("workspace", "runnerTemp", "artifactDirectory")),
                    "Phase1 inconsistent live runner paths")
        entries = phase1_inventory(value["productInventory"], products=True)
        products = value["products"]
        require(products == metadata["products"] and kernel["object_sha"](entries) == products["treeSHA256"]
                and len(entries) == products["entryCount"]
                and sum(item.get("size", 0) for item in entries) == products["fileBytes"],
                "Phase1 retained product inventory binding")
        xctestruns = [entry for entry in entries if entry["path"].endswith(".xctestrun") and entry["type"] == "file"]
        require(len(xctestruns) == 1 and (xctestruns[0]["path"], xctestruns[0]["sha256"])
                == (products["xctestrunPath"], products["xctestrunSHA256"]), "Phase1 retained xctestrun binding")
        if stage in ("seal", "restore"):
            receipt_name = SHARED_PAYLOAD_RECEIPT if stage == "seal" else SHARED_RESTORE_RECEIPT
            receipt_raw = gate.regular_bytes(artifact / receipt_name, limit=PHASE1_WITNESS_BYTES)
            receipt = gate.decode(receipt_raw, limit=PHASE1_WITNESS_BYTES)
            require(value["receiptSHA256"] == sha256(receipt_raw) and value["archive"] == receipt["archive"]
                    and receipt["metadataSHA256"] == value["metadataSHA256"]
                    and receipt["productsTreeSHA256"] == products["treeSHA256"], "Phase1 retained payload receipt")
            census = value["archiveMemberCensus"]
            require(type(census) is list and 0 < len(census) <= PHASE1_WITNESS_ENTRIES,
                    "Phase1 retained archive census bound")
            paths = []
            for item in census:
                require(type(item) is dict and set(item) == {"path", "type", "size", "mode"}
                        and item["type"] in ("file", "directory")
                        and type(item["size"]) is int and item["size"] >= 0
                        and (item["type"] != "directory" or item["size"] == 0)
                        and type(item["mode"]) is int and 0 <= item["mode"] <= 0o777,
                        "Phase1 retained archive member")
                paths.append(phase1_relative_path(item["path"]))
            require(paths == sorted(set(paths)) and len({p.casefold() for p in paths}) == len(paths),
                    "Phase1 retained archive order/duplicate")
            by_path = {item["path"]: item for item in census}
            expected_paths = {"FieldEvidenceDerivedData", "FieldEvidenceDerivedData/Build", kernel["ROOT_LABEL"],
                              SHARED_PAYLOAD_METADATA}
            for item in entries:
                path = kernel["ROOT_LABEL"] + "/" + item["path"]
                expected_paths.add(path)
                require(by_path.get(path) == {"path": path, "type": item["type"], "mode": item["mode"],
                                               "size": item.get("size", 0)}, "Phase1 archive/product census")
            require(set(paths) == expected_paths
                    and by_path[SHARED_PAYLOAD_METADATA]["type"] == "file"
                    and by_path[SHARED_PAYLOAD_METADATA]["size"] == len(metadata_raw)
                    and all(by_path[p]["type"] == "directory" for p in
                            ("FieldEvidenceDerivedData", "FieldEvidenceDerivedData/Build", kernel["ROOT_LABEL"])),
                    "Phase1 complete payload root census")
            if stage == "seal":
                phase1_inventory(value["sourceProductInventory"], products=True)
                require(value["sourceUnchangedDuringSeal"] is True and type(value["testsExecuted"]) is int
                        and value["testsExecuted"] == 0 and value["diagnostics"] == "NOT_APPLICABLE_BUILD_ONLY",
                        "Phase1 build-only seal observation")
            else:
                require(value["safeExtractionObserved"] is True
                        and value["extractionKernelSHA256"] == identity["sourceSHA256"][SHARED_PAYLOAD_KERNEL],
                        "Phase1 observed extraction kernel")
        else:
            inventory = phase1_inventory(value["derivedDataInventory"])
            fingerprint_raw = gate.regular_bytes(artifact / ("v23-shared-fingerprint-" + stage + ".json"),
                                                 limit=PHASE1_WITNESS_BYTES)
            fingerprint = gate.decode(fingerprint_raw, limit=PHASE1_WITNESS_BYTES)
            require(value["fingerprintSHA256"] == sha256(fingerprint_raw)
                    and fingerprint.get("phase") == stage and fingerprint.get("matchesProducer") is True
                    and fingerprint.get("buildEvidence") == [] and fingerprint.get("error") is None
                    and fingerprint.get("productsTreeSHA256") == products["treeSHA256"]
                    and fingerprint.get("xctestrunSHA256") == products["xctestrunSHA256"]
                    and fingerprint.get("entryCount") == len(entries), "Phase1 retained fingerprint")
            if stage == "before":
                require(fingerprint.get("derivedDataEntries") == inventory and value["activityLogs"] == [],
                        "Phase1 retained before inventory")
                require(not any(item["path"] == prefix or item["path"].startswith(prefix + "/")
                                for item in inventory for prefix in ("Logs/Build", "Build/Intermediates.noindex")),
                        "Phase1 retained before build tree")
            else:
                require(fingerprint.get("matchesBefore") is True, "Phase1 retained products changed")
                before = {item["path"]: {k: v for k, v in item.items() if k != "path"}
                          for item in observations["before"]["derivedDataInventory"]}
                after = {item["path"]: {k: v for k, v in item.items() if k != "path"} for item in inventory}
                delta_raw = gate.regular_bytes(artifact / SHARED_DERIVED_DATA_DELTA, limit=PHASE1_WITNESS_BYTES)
                delta = gate.decode(delta_raw, limit=PHASE1_WITNESS_BYTES)
                expected_delta = shared_derived_delta(before, after)
                require(all(delta.get(k) == v for k, v in expected_delta.items())
                        and delta.get("beforeEntryCount") == len(before) and delta.get("afterEntryCount") == len(after)
                        and delta.get("compileEvidence") == []
                        and fingerprint["derivedDataDelta"]["sha256"] == sha256(delta_raw),
                        "Phase1 complete retained DerivedData delta")
                # Lists in the legacy delta can be capped. Full retained inventories
                # above are authoritative for this recomputation, not capped lists.
                require(not any(item["path"].startswith("Build/Intermediates")
                                and item["path"].endswith(SHARED_COMPILE_OUTPUT_SUFFIXES) for item in inventory),
                        "Phase1 retained compile output")
                logs = [item for item in inventory if item["path"].startswith("Logs/Build/")
                        and item["path"].endswith(".xcactivitylog") and item["type"] == "file"]
                require(type(value["activityLogs"]) is list and len(value["activityLogs"]) == len(logs),
                        "Phase1 complete retained activity logs")
                total = 0
                for index, (entry, retained) in enumerate(zip(logs, value["activityLogs"])):
                    name = "%06d.xcactivitylog" % index
                    require(retained == {"sourcePath": entry["path"], "retainedPath": name,
                                         "bytes": entry["size"], "sha256": entry["sha256"]},
                            "Phase1 activity log identity")
                    total += entry["size"]
                    require(total <= PHASE1_ACTIVITY_TOTAL_BYTES, "Phase1 retained activity byte bound")
                    path = artifact / "phase1-activity-logs" / name
                    log_raw = gate.regular_bytes(path, limit=PHASE1_ACTIVITY_TOTAL_BYTES)
                    require(len(log_raw) == entry["size"] and sha256(log_raw) == entry["sha256"]
                            and shared_activity_log_compile_step(path) is None, "Phase1 retained activity scan")
                directory = artifact / "phase1-activity-logs"
                require(directory.is_dir() and not directory.is_symlink()
                        and sorted(p.name for p in directory.iterdir()) == ["%06d.xcactivitylog" % i for i in range(len(logs))],
                        "Phase1 activity log directory census")
                require(shared_test_log_compile_lines(artifact / "test-smoke.log") == []
                        and not shared_local_build_artifacts(artifact), "Phase1 retained no-rebuild log/artifact scan")
        observations[stage] = value
    require(all(value["products"] == observations[stages[0]]["products"] for value in observations.values()),
            "Phase1 products changed between observations")
    return {"schema": "v23-phase1-retained-shared-facts.v1", **identity, "role": role,
            "status": "COMPLETE_RETAINED_SHARED_OBSERVATIONS",
            "liveObservationSHA256": {stage: sha256(canonical(value)) for stage, value in observations.items()},
            "payloadArchiveRetained": False, "liveChecksIndependentlyReexecuted": False}


def write_new_evidence(path, raw):
    with path.open("xb") as stream:
        stream.write(raw)


def cold_shared_observation(root, artifact, record, environment, stage, kernel, *, source_before=None):
    require(stage in PHASE1_WITNESS_STAGES and "phase1Gate" not in record, "cold shared observation scope")
    binding, raw, _, _ = cold_worker_context(root, environment)
    require(record.get("coldOriginal") == binding and read_json(artifact / "native-admission.json") == record,
            "cold live observation original admission")
    require((stage == "seal") == (shared_role(record) == "producer"), "cold observation role/stage")
    products_root = Path(environment["RUNNER_TEMP"]) / "FieldEvidenceDerivedData" / "Build" / "Products"
    products = phase1_product_inventory(products_root, kernel)
    if source_before is not None:
        require(products == source_before, "cold source Products changed during seal")
    facts = {}
    for name in (SHARED_PAYLOAD_METADATA, SHARED_PAYLOAD_RECEIPT, SHARED_RESTORE_RECEIPT,
                 "v23-shared-fingerprint-before.json", "v23-shared-fingerprint-after.json", SHARED_DERIVED_DATA_DELTA):
        path = artifact / name
        if path.exists() or path.is_symlink():
            facts[name] = sha256(load_phase1_gates(root).regular_bytes(path, limit=PHASE1_WITNESS_BYTES))
    value = {"schema": "v23-cold-shared-live-observation.v1", "stage": stage,
             "eventBindingSHA256": sha256(canonical(binding)), "originalEventSHA256": sha256(raw),
             "admissionSHA256": sha256(canonical(record)), "planSHA256": binding["planSHA256"],
             "selectionSHA256": record[SHARED_KEY]["planSHA256"], "head": record["head"], "tree": record["gitTree"],
             "runID": record["runID"], "runAttempt": "1", "role": shared_role(record),
             "partitionID": record[SHARED_KEY]["partitionID"], "products": products, "receiptSHA256": facts,
             "status": "INCOMPLETE", "functionalQualification": "PENDING", "processLifetimes": "PENDING",
             "executionScope": "cold-shared-route-development-v1", "developmentOnly": True,
             "providerQualification": False, "acceptance": False, "releaseReady": False}
    require(len(canonical(value)) <= PHASE1_WITNESS_BYTES, "bounded cold live observation")
    write_new_evidence(artifact / ("cold-shared-observation-%s.json" % stage), canonical(value))
    return value


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
    phase1_source_before = (phase1_product_inventory(source_products, kernel)
                           if "phase1Gate" in record else None)
    cold_source_before = (phase1_product_inventory(source_products, kernel) if "coldOriginal" in record else None)
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
    if "phase1Gate" in record:
        phase1_shared_live_observation(root, artifact, record, environment, "seal", kernel,
                                       source_before=phase1_source_before)
    if "coldOriginal" in record:
        cold_shared_observation(root, artifact, record, environment, "seal", kernel, source_before=cold_source_before)
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
    if "phase1Gate" in record:
        phase1_shared_live_observation(root, artifact, record, environment, "restore", kernel)
    if "coldOriginal" in record:
        cold_shared_observation(root, artifact, record, environment, "restore", kernel)
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
    if "phase1Gate" in record:
        phase1_shared_live_observation(root, artifact, record, environment, phase, kernel)
    if "coldOriginal" in record:
        cold_shared_observation(root, artifact, record, environment, phase, kernel)
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


def verify_checkpoint(root, artifact, record, selection, environment, *, retained_command_artifact=None):
    # Collection reads relocated originals. Only command paths retain their
    # runner spelling; every fact is read from artifact, with no writes.
    if retained_command_artifact is not None:
        require(record["selectionID"] == UI_BATCH_SELECTION_ID, "retained RUI1 verification only")
    role = shared_role(record) if record["selectionID"] in SHARED_SELECTION_IDS else None
    if role == "producer":
        # A build-only producer runs no tests, so it has no diagnostic stream to retain.
        require(environment.get("NATIVE_PRIOR_JOB_STATUS") == "success", "earlier job failure")
        require(not any((artifact / name).exists() for name in (
                    "test-smoke.log", "UnitTests.xcresult", "unit-test-results.json",
                    SIMULATOR_DIAGNOSTIC_TRANSPORT_STATUS, SIMULATOR_DIAGNOSTIC_OUTPUT)),
                "shared producer test evidence")
        diagnostic_evidence = None
    else:
        if retained_command_artifact is None:
            diagnostic_evidence = persist_simulator_diagnostic_observations(root, artifact, record)
        else:
            diagnostic_evidence, parse_error = simulator_diagnostic_observations(root, artifact, record)
            require(parse_error is None and read_json(artifact / SIMULATOR_DIAGNOSTIC_OUTPUT) == diagnostic_evidence,
                    "retained simulator diagnostic observations")
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
    if (record["selectionID"] in NO_INDEX_ROUTES or record["selectionID"] in (DEV_BATCH_SELECTION_ID, UI_BATCH_SELECTION_ID)
            or role == "producer"):
        build_order["noIndexBuildDiagnostic"] = verify_no_index_build(
            root, artifact, record, environment, command_artifact=retained_command_artifact)
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
        if record["selectionID"] == UI_BATCH_SELECTION_ID:
            from types import SimpleNamespace
            evidence = load_ui_evidence(root)
            proof = evidence.verify(root, artifact, record, selection,
                    SimpleNamespace(executed_methods=executed_methods, canonical=canonical), environment,
                    command_artifact=retained_command_artifact)
            require(read_json(artifact / "rui1-review.json") == proof, "RUI1 review proof")
            require(evidence.regular(artifact / "rui1-review.html") == evidence.review_page(root, artifact, proof),
                    "RUI1 owner review presentation")
            build_order["rui1Evidence"] = proof
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
    if "phase1Gate" in record:
        if record["selectionID"] == UI_BATCH_SELECTION_ID and retained_command_artifact is None:
            phase1_seal_ui_log(root, artifact, record)
        build_order["phase1DiagnosticFacts"] = phase1_retained_diagnostic_facts(
            root, artifact, record, record["phase1Gate"])
        if role in ("producer", "consumer"):
            build_order["phase1SharedFacts"] = phase1_retained_shared_facts(root, artifact, record, record["phase1Gate"])
    if "coldOriginal" in record:
        required_stages = ("seal",) if role == "producer" else ("restore", "before", "after")
        cold_facts = {}
        for stage in required_stages:
            value = read_json(artifact / ("cold-shared-observation-%s.json" % stage))
            require(value.get("schema") == "v23-cold-shared-live-observation.v1"
                    and value.get("eventBindingSHA256") == sha256(canonical(record["coldOriginal"]))
                    and value.get("admissionSHA256") == sha256(canonical(record))
                    and value.get("stage") == stage and value.get("status") == "INCOMPLETE"
                    and value.get("functionalQualification") == "PENDING"
                    and all(value.get(key) is False for key in ("providerQualification", "acceptance", "releaseReady")),
                    "cold retained live observation binding")
            cold_facts[stage] = value
        build_order["coldSharedObservations"] = cold_facts
    return {**record, **build_order, "recordType": "validated-native-checkpoint", "executedUnitMethods": units,
            "executedUIMethods": ui, "simulator": simulator, "provider": provider, "sdk": sdk,
            "simulatorFileProtectionDiagnostics": diagnostic_evidence,
            "wholeAppAcceptance": False, "humanReviewComplete": False,
            "diagnosticOnly": True, "providerQualification": False,
            "acceptance": False, "releaseReady": False}


def phase1_workflow_steps(root, relative, job="verify"):
    """Read the closed source layout, not a general YAML/expression interpreter."""
    text = (root / relative).read_text(encoding="utf-8")
    jobs = re.split(r"(?m)^  ([a-zA-Z0-9_-]+):\n", text.split("\njobs:\n", 1)[1])
    blocks = dict(zip(jobs[1::2], jobs[2::2]))
    require(job in blocks, "Phase1 source job")
    block = blocks[job]
    require("continue-on-error:" not in block, "Phase1 source permits ignored failure")
    parts = re.split(r"(?m)^      - name: (.+)\n", block)
    require(len(parts) > 1, "Phase1 source steps")
    steps = []
    for name, body in zip(parts[1::2], parts[2::2]):
        command = re.search(r"(?m)^        run: (.+)\n", body)
        script = None
        if command:
            if command[1] == "|":
                lines = []
                for line in body[command.end():].splitlines():
                    if line and not line.startswith("          "):
                        break
                    lines.append(line[10:] if line else "")
                script = "\n".join(lines).rstrip()
            else:
                script = command[1]
            require(script, "Phase1 empty source command")
        action = re.search(r"(?m)^        uses: ([^\s]+)", body)
        steps.append({"name": name, "script": script, "action": action[1] if action else None,
                      "bodySHA256": sha256(body.encode()), "body": body})
    require(len({s["name"] for s in steps}) == len(steps), "Phase1 source duplicate step")
    return steps


def phase1_job_names(root, plan, resolved):
    source = (root / ".github/workflows/ios-ci.yml").read_text(encoding="utf-8")
    def name(job):
        found = re.findall(r"(?m)^  " + re.escape(job) + r":\n    name: (.+)$", source)
        require(len(found) == 1, "Phase1 source caller name")
        return found[0]
    names = {"selection": name("shared-selection")}
    if plan["selection"] == SHARED_SELECTION_ID:
        names["producer"] = name("v23-shared-producer") + " / verify"
        for partition in resolved[SHARED_KEY]["partitionIDs"]:
            names[partition] = name("v23-shared-consumer").replace("${{ matrix.partition_id }}", partition) + " / verify"
    else:
        names["rui1"] = name("github-shard").replace("${{ inputs.s10_4_shard_id }}", "none").replace(
            "${{ inputs.s10_4_shared_segment_id }}", "none") + " / verify"
    require(all("${{" not in n for n in names.values()), "Phase1 unresolved caller name")
    return names


def phase1_job_execution_facts(root, directory, plan, resolved, run_id):
    """Recompute execution facts from the sole collector's authenticated job logs.

    Only collect_phase1 fetches these fixed repository/job endpoints. This local
    verifier checks retained facts; a dictionary/hash alone is not API authority.
    """
    gate = load_phase1_gates(root)
    jobs = gate.decode(gate.regular_bytes(directory / "jobs.json", limit=PHASE1_WITNESS_BYTES),
                       limit=PHASE1_WITNESS_BYTES)["jobs"]
    names = phase1_job_names(root, plan, resolved)
    require(type(jobs) is list and len(jobs) <= 500 and all(type(j) is dict for j in jobs)
            and len({j.get("id") for j in jobs}) == len(jobs)
            and len({j.get("name") for j in jobs}) == len(jobs), "Phase1 unique job census")
    by_name = {job["name"]: job for job in jobs}
    require(set(names.values()) <= set(by_name), "Phase1 complete source-derived active job census")
    for job in jobs:
        require(type(job.get("id")) is int and job["id"] > 0
                and type(job.get("run_id")) is int and job["run_id"] == run_id
                and type(job.get("run_attempt")) is int and job["run_attempt"] == 1
                and job.get("head_sha") == plan["head"] and job.get("status") == "completed",
                "Phase1 original job identity")
        if job["name"] not in names.values():
            require(job.get("conclusion") == "skipped" and not job.get("steps"),
                    "Phase1 unexpected executed job")
    rui_required = {"Prepare evidence directory", "Check out the exact revision", "Validate task selection and timeout tier",
        "Verify pinned toolchain, shared scheme, and simulator", "Verify setup budget before build",
        "Boot selected Simulator", "Await selected Simulator boot", "Build unsigned simulator app", "Run targeted tests",
        "Run task-authorized UI smoke", "Begin evidence-finalization budget", "Validate required build and test evidence",
        "Validate exact ordinary integration native checkpoint", "Remove owned isolated Simulator", "Hash collected evidence",
        "Recheck evidence-finalization budget", "Verify selected total budget before upload", "Upload build evidence"}
    facts = {}
    for label, name in names.items():
        job = by_name[name]
        require(job.get("conclusion") == "success", "Phase1 required job failed/interrupted")
        relative = (".github/workflows/ios-ci.yml" if label == "selection" else
                    ".github/workflows/ios-ci-worker.yml" if label == "rui1" else ".github/workflows/ios-ci-shared-worker.yml")
        source_steps = phase1_workflow_steps(root, relative, "shared-selection" if label == "selection" else "verify")
        required = set()
        for step in source_steps:
            if label == "selection":
                active = step["name"] in {"Check out the exact revision", "Validate ordinary V23 native acceptance selection",
                                          "Validate closed shared selection and original dependencies"}
            elif label == "rui1":
                active = step["name"] in rui_required
            else:
                condition = re.search(r"(?m)^        if: (.+)$", step["body"])
                active = (not condition or "inputs.v23_shared_role" not in condition[1]
                          or ("'producer'" if label == "producer" else "'consumer'") in condition[1])
            if active:
                required.add(step["name"])
        if label == "rui1":
            require(required == rui_required, "Phase1 RUI1 source step census changed")
        observed = job.get("steps")
        require(type(observed) is list and all(type(s) is dict for s in observed)
                and len({s.get("name") for s in observed}) == len(observed)
                and all(type(s.get("number")) is int and s["number"] > 0 for s in observed)
                and [s["number"] for s in observed] == sorted({s["number"] for s in observed}),
                "Phase1 unique ordered step census")
        by_step = {s["name"]: s for s in observed}
        source_names = [s["name"] for s in source_steps]
        require(set(source_names) <= set(by_step), "Phase1 missing source step outcome")
        require([s["name"] for s in observed if s["name"] in source_names] == source_names,
                "Phase1 source step order")
        framework = {"Set up job", "Complete job"} | {"Post " + s["name"] for s in source_steps if s["action"]}
        active_framework = {"Set up job", "Complete job"} | {
            "Post " + s["name"] for s in source_steps if s["action"] and s["name"] in required}
        require(set(by_step) <= set(source_names) | framework
                and {"Set up job", "Complete job"} <= set(by_step), "Phase1 unexpected/missing framework step")
        for step in observed:
            require(step.get("status") == "completed" and step.get("conclusion") ==
                    ("success" if step["name"] in required | active_framework else "skipped"),
                    "Phase1 failed/interrupted/bypassed/unexpected step " + step["name"])
        log = gate.regular_bytes(directory / "phase1-job-logs" / (str(job["id"]) + ".log"), limit=256 * 1024 * 1024)
        text = log.decode("utf-8-sig")
        text = re.sub(r"(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z ", "", text)
        text = re.sub(r"\x1b\[[0-9;]*m", "", text)
        commands, cursor = [], 0
        for step in source_steps:
            if step["name"] not in required:
                continue
            if step["script"]:
                require("${{" not in step["script"], "Phase1 active source command requires unsupported interpolation")
                pattern = "##[group]Run " + step["script"].splitlines()[0] + "\n" + step["script"] + "\n"
                require(text.count(pattern) == 1, "Phase1 exact executed source command " + step["name"])
                position = text.index(pattern)
                require(position >= cursor, "Phase1 executed command order")
                end = text.find("##[endgroup]", position + len(pattern))
                envelope = text[position + len(pattern):end]
                require(end >= 0 and "shell: /bin/bash --noprofile --norc -e -o pipefail {0}" in envelope
                        and "##[group]" not in envelope, "Phase1 incomplete command envelope")
                cursor = end
                wanted_env = {"CI_ARTIFACT_DIR", "CI_DESTINATION", "CI_SIMULATOR_UDID", "CI_SETUP_ARTIFACT_TIMEOUT_SECONDS",
                              "CI_BUILD_TIMEOUT_SECONDS", "CI_TEST_TIMEOUT_SECONDS", "CI_UI_TIMEOUT_SECONDS",
                              "CI_TOTAL_BUDGET_SECONDS", "NATIVE_SELECTION_ID", "CONFIGURATION", "DEVELOPER_DIR"}
                pairs = re.findall(r"(?m)^  ([A-Z_]+): (.*)$", text[position + len(pattern):end])
                env = unique_pairs([(key, value) for key, value in pairs if key in wanted_env])
                numeric = {}
                if step["name"] == "Verify selected total budget before upload":
                    output_end = text.find("##[group]Run ", end + 1)
                    output = text[end:output_end if output_end >= 0 else len(text)]
                    numeric = unique_pairs(re.findall(r"(?m)^(elapsed_seconds|total_budget_seconds)=([0-9]+)$", output))
                    require(set(numeric) == {"elapsed_seconds", "total_budget_seconds"}, "Phase1 complete total budget output")
                commands.append({"step": step["name"], "bodySHA256": step["bodySHA256"],
                                 "scriptSHA256": sha256(step["script"].encode()), "environment": env, "numericFacts": numeric})
            elif step["action"]:
                pattern = "##[group]Run " + step["action"] + "\n"
                count = sum(s["name"] in required and s["action"] == step["action"] for s in source_steps)
                position = text.find(pattern, cursor)
                end = text.find("##[endgroup]", position + len(pattern)) if position >= 0 else -1
                require(text.count(pattern) == count and position >= cursor and end >= 0
                        and "##[group]" not in text[position + len(pattern):end],
                        "Phase1 exact executed action " + step["name"])
                cursor = end
        facts[label] = {"jobID": job["id"], "name": name, "workflowSourceSHA256": sha256((root / relative).read_bytes()),
                        "jobLogSHA256": sha256(log), "commands": commands, "requiredSteps": sorted(required),
                        "finalizationBudgetPredicatePassed": label != "selection", "finalizationNumericElapsedAvailable": False}
    return facts


def phase1_worker_execution_facts(root, artifact, record, selected, label, job):
    """Retained execution/command facts, never a local native execution replay."""
    from pathlib import PurePosixPath
    gate = load_phase1_gates(root)
    for name in ("runner-provider.txt", "native-sdk.txt", "xcode-version.txt", "simulator-selection.txt"):
        gate.regular_bytes(artifact / name, limit=32768)
    provider = key_values(artifact / "runner-provider.txt")
    require(provider.get("provider") == record.get("runnerProvider") == "github"
            and provider.get("label") == record.get("runnerLabel") == "macos-26"
            and provider.get("runner_architecture") == "ARM64" and provider.get("uname_architecture") == "arm64"
            and provider.get("developer_dir") == "/Applications/Xcode_26.6.app/Contents/Developer",
            "Phase1 observed runner/toolchain")
    require((artifact / "xcode-version.txt").read_text().splitlines() == ["Xcode 26.6", "Build version 17F113"],
            "Phase1 observed Xcode")
    sdk = key_values(artifact / "native-sdk.txt")
    require(sdk == {"sdk": "iphonesimulator", "version": "26.5", "build": "23F81a"}, "Phase1 observed SDK")
    simulator = key_values(artifact / "simulator-selection.txt")
    require((simulator.get("runtime"), simulator.get("runtime_build"), simulator.get("name"), simulator.get("initial_state"))
            == ("iOS 26.2", "23C54", "iPhone 17", "Shutdown")
            and re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", simulator.get("udid", "")),
            "Phase1 observed owned Simulator")
    if label == "rui1":
        environment, original_artifact = load_ui_evidence(root).retained_environment(read_json(artifact / "rui1-command.json")["argv"])
    else:
        witness = read_json(artifact / ("phase1-shared-live-seal.json" if label == "producer" else "phase1-shared-live-restore.json"))
        original_artifact = PurePosixPath(witness["artifactDirectory"])
        environment = {"PROJECT_PATH": "FieldEvidenceApp.xcodeproj", "SCHEME": "FieldEvidenceApp", "CONFIGURATION": "Debug",
                       "CODE_SIGNING_ALLOWED": "NO", "CI_SIMULATOR_UDID": simulator["udid"],
                       "CI_DESTINATION": "platform=iOS Simulator,id=" + simulator["udid"],
                       "CI_ARTIFACT_DIR": str(original_artifact), "RUNNER_TEMP": witness["runnerTemp"]}
    require(environment["CI_SIMULATOR_UDID"] == simulator["udid"], "Phase1 original command Simulator identity")
    timeout_env = dict(zip(("CI_SETUP_ARTIFACT_TIMEOUT_SECONDS", "CI_BUILD_TIMEOUT_SECONDS", "CI_TEST_TIMEOUT_SECONDS",
                           "CI_UI_TIMEOUT_SECONDS", "CI_TOTAL_BUDGET_SECONDS"),
                          (str(selected[key]) for key in BUDGET_KEYS)))
    commands = {item["step"]: item for item in job["commands"]}
    checked_steps = ["Recheck evidence-finalization budget", "Verify selected total budget before upload",
                     "Validate required build and test evidence", "Validate exact ordinary integration native checkpoint"]
    if label != "producer":
        checked_steps.append("Run targeted tests")
    if label in ("producer", "rui1"):
        checked_steps.append("Build unsigned simulator app")
    if label == "rui1":
        checked_steps.append("Run task-authorized UI smoke")
    for name in checked_steps:
        require(name in commands, "Phase1 source command proof missing " + name)
        observed = commands[name]["environment"]
        require(all(observed.get(k) == v for k, v in timeout_env.items())
                and observed.get("CI_ARTIFACT_DIR") == str(original_artifact)
                and observed.get("NATIVE_SELECTION_ID") == record["selectionID"]
                and observed.get("CONFIGURATION") == "Debug"
                and observed.get("DEVELOPER_DIR") == provider["developer_dir"], "Phase1 actual command budget/configuration inputs")
    def numbers(name, keys):
        gate.regular_bytes(artifact / name, limit=4096)
        value = key_values(artifact / name)
        require(set(value) == set(keys) and all(re.fullmatch(r"[0-9]+", v) for v in value.values()),
                "Phase1 complete numeric budget " + name)
        return {key: int(v) for key, v in value.items()}
    limit = selected["setupArtifactTimeoutSeconds"]
    setup = numbers("setup-budget.txt", ("setup_elapsed_seconds", "setup_budget_seconds"))
    require(setup["setup_elapsed_seconds"] <= setup["setup_budget_seconds"] == limit, "Phase1 setup budget")
    setup_elapsed = setup["setup_elapsed_seconds"]
    restore = None
    if label not in ("producer", "rui1"):
        restore = numbers("v23-shared-restore-budget.txt", ("shared_restore_setup_elapsed_seconds",))
        require(setup_elapsed <= restore["shared_restore_setup_elapsed_seconds"] <= limit, "Phase1 restore setup budget")
        setup_elapsed = restore["shared_restore_setup_elapsed_seconds"]
    artifact_budget = numbers("artifact-budget.txt", ("setup_elapsed_seconds", "artifact_elapsed_seconds",
                                                     "setup_artifact_elapsed_seconds", "setup_artifact_budget_seconds"))
    require(artifact_budget["setup_elapsed_seconds"] == setup_elapsed
            and artifact_budget["setup_artifact_budget_seconds"] == limit
            and setup_elapsed + artifact_budget["artifact_elapsed_seconds"] == artifact_budget["setup_artifact_elapsed_seconds"] <= limit,
            "Phase1 artifact finalization budget")
    total = {k: int(v) for k, v in commands["Verify selected total budget before upload"]["numericFacts"].items()}
    require(total.get("total_budget_seconds") == selected["totalBudgetSeconds"]
            and total.get("elapsed_seconds", -1) >= setup_elapsed
            and total["elapsed_seconds"] <= total["total_budget_seconds"], "Phase1 total budget")
    build = None
    if label in ("producer", "rui1"):
        build = verify_no_index_build(root, artifact, record, environment, command_artifact=original_artifact)
    unit_command = None
    if label != "producer":
        expected = [provider["developer_dir"] + "/usr/bin/xcodebuild", "-project", "FieldEvidenceApp.xcodeproj",
                    "-scheme", "FieldEvidenceApp", "-configuration", "Debug", "-destination", environment["CI_DESTINATION"],
                    "-derivedDataPath", str(PurePosixPath(environment["RUNNER_TEMP"]) / "FieldEvidenceDerivedData"),
                    "-resultBundlePath", str(original_artifact / "UnitTests.xcresult"),
                    *["-only-testing:" + value for value in selected["unitTestSelectors"]],
                    "CODE_SIGNING_ALLOWED=NO", "test-without-building"]
        raw_log = gate.regular_bytes(artifact / "test-smoke.log", limit=SHARED_MAX_TEST_LOG_BYTES)
        log = raw_log.decode("utf-8")
        lines = log.splitlines()
        invocations = [i for i, line in enumerate(lines) if line.strip() == "Command line invocation:"]
        require(len(invocations) == 1 and invocations[0] + 1 < len(lines)
                and shlex.split(lines[invocations[0] + 1].strip()) == expected
                and sum(line.strip() == "** TEST EXECUTE SUCCEEDED **" for line in lines) == 1
                and not shared_test_log_compile_lines(artifact / "test-smoke.log"),
                "Phase1 exact successful no-rebuild unit invocation")
        unit_command = {"argv": expected, "logSHA256": sha256(raw_log),
                        "exporterSourceSHA256": sha256((root / "Scripts/validate-required-evidence.sh").read_bytes()),
                        "structuredResultSHA256": sha256((artifact / "unit-test-results.json").read_bytes()),
                        "exportReexecutedOffline": False}
    checkpoint = read_json(artifact / "native-checkpoint.json")
    require(checkpoint.get("recordType") == "validated-native-checkpoint"
            and all(checkpoint.get(k) == v for k, v in record.items())
            and checkpoint.get("provider") == provider and checkpoint.get("simulator") == simulator and checkpoint.get("sdk") == sdk
            and checkpoint.get("releaseReady") is False and checkpoint.get("acceptance") is False,
            "Phase1 original live checkpoint binding")
    require(checkpoint.get("executedUnitMethods") == ([] if label == "producer" else sorted(selected["unitTestSelectors"]))
            and checkpoint.get("executedUIMethods") == sorted(selected["uiTestSelectors"]),
            "Phase1 live checkpoint complete method census")
    forbidden = (("test-smoke.log", "UnitTests.xcresult", "unit-test-results.json") if label == "producer" else
                 ("build-smoke.log", "Build.xcresult", NO_INDEX_RECEIPT) if label != "rui1" else ())
    require(not any((artifact / name).exists() or (artifact / name).is_symlink() for name in forbidden),
            "Phase1 unexpected role execution evidence")
    return {"jobID": job["jobID"], "jobLogSHA256": job["jobLogSHA256"], "build": build, "unitCommand": unit_command,
            "budgets": {"setup": setup, "restore": restore, "artifact": artifact_budget, "total": total,
                        "finalizationPredicatePassed": True, "finalizationNumericElapsedAvailable": False},
            "simulator": simulator, "checkpointSHA256": sha256((artifact / "native-checkpoint.json").read_bytes()),
            "offlineNativeExecution": False}


def phase1_payload_execution_facts(root, directory, plan, resolved, run_id, jobs):
    """Join the API payload identity to source-bound producer/consumer originals.

    The ZIP digest is distinct from the inner TAR digest. The payload ZIP is
    deliberately not downloaded by this collector or replayed offline.
    """
    gate = load_phase1_gates(root)
    listing = gate.decode(gate.regular_bytes(directory / "artifacts.json", limit=PHASE1_WITNESS_BYTES),
                          limit=PHASE1_WITNESS_BYTES)["artifacts"]
    require(type(listing) is list and all(type(a) is dict for a in listing)
            and len({a.get("name") for a in listing}) == len(listing), "Phase1 API artifact census")
    for item in listing:
        origin = item.get("workflow_run", {})
        require(type(item.get("id")) is int and item["id"] > 0 and item.get("expired") is False
                and type(item.get("digest")) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", item["digest"])
                and type(origin) is dict and type(origin.get("id")) is int and origin["id"] == run_id
                and origin.get("head_sha") == plan["head"]
                and origin.get("head_branch") == plan["ref"].removeprefix("refs/heads/"), "Phase1 original API artifact identity")
    prefix = "ios-ci-native-github-" + plan["selection"]
    if plan["selection"] != SHARED_SELECTION_ID:
        expected = {prefix + "-%d-1" % run_id}
        require({a.get("name") for a in listing} == expected, "Phase1 exact RUI1 artifact census")
        return {"payloadRequired": False}
    payload_name = "v23-shared-payload-%d-1-%s" % (run_id, plan["head"])
    expected = {payload_name, prefix + "-producer-%d-1" % run_id}
    expected.update(prefix + "-consumer-%s-%d-1" % (p, run_id) for p in resolved[SHARED_KEY]["partitionIDs"])
    require({a.get("name") for a in listing} == expected, "Phase1 exact shared artifact census")
    payload = next(a for a in listing if a["name"] == payload_name)
    require(type(payload.get("id")) is int and payload["id"] > 0
            and type(payload.get("digest")) is str and re.fullmatch(r"sha256:[0-9a-f]{64}", payload["digest"])
            and payload.get("expired") is False and type(payload.get("size_in_bytes")) is int and payload["size_in_bytes"] > 0,
            "Phase1 retained payload API identity")
    producer = directory / "artifacts/producer"
    metadata = gate.regular_bytes(producer / SHARED_PAYLOAD_METADATA, limit=PHASE1_WITNESS_BYTES)
    archive = read_json(producer / "phase1-shared-live-seal.json")["archive"]
    for partition in resolved[SHARED_KEY]["partitionIDs"]:
        consumer = directory / "artifacts" / partition
        require(gate.regular_bytes(consumer / SHARED_PAYLOAD_METADATA, limit=PHASE1_WITNESS_BYTES) == metadata
                and read_json(consumer / "phase1-shared-live-restore.json")["archive"] == archive,
                "Phase1 same producer TAR and metadata for every consumer")
        log = gate.regular_bytes(directory / "phase1-job-logs" / (str(jobs[partition]["jobID"]) + ".log"),
                                 limit=256 * 1024 * 1024).decode("utf-8-sig")
        expected_line = "- %s (ID: %d, Size: %d, Expected Digest: %s)" % (
            payload_name, payload["id"], payload["size_in_bytes"], payload["digest"])
        require(log.count(expected_line) == 1
                and log.count("SHA256 digest of downloaded artifact is " + payload["digest"].removeprefix("sha256:")) == 1
                and log.count("Artifact download completed successfully.") == 1,
                "Phase1 actual consumer downloaded exact authenticated payload")
    return {"payloadRequired": True, "payloadArtifactID": payload["id"], "zipSHA256": payload["digest"],
            "downloadedByCollector": False, "archive": archive, "metadataSHA256": sha256(metadata),
            "everyConsumerBound": True, "offlinePayloadReplay": False}


def phase1_retained_worker_chain(root, request_path):
    """Exact-source subprocess entry point used only after authenticated collection.

    Its request carries locations, not authority. The enclosing collector retains
    the fetched API responses and authenticated ZIPs and binds this output in the
    original manifest. Remaining full-proof predicates deliberately stay pending.
    """
    gate = load_phase1_gates(root)
    request = gate.decode(gate.regular_bytes(request_path))
    require(type(request) is dict and set(request) == {"schema", "runID", "planSHA256"}
            and request["schema"] == "v23-phase1-retained-chain-request.v1"
            and type(request["runID"]) is int and request["runID"] > 0, "Phase1 retained chain request")
    directory = request_path.parent
    registration = gate.decode(gate.regular_bytes(directory / "phase1-registration.json"))
    plan = gate.validate_plan(registration.get("plan"))
    require(gate.sha(gate.canonical(plan)) == request["planSHA256"] == registration.get("planSHA256"),
            "Phase1 retained chain registered plan")
    sources = {p: gate.sha(gate.regular_bytes(root / p, limit=PHASE1_WITNESS_BYTES)) for p in gate.SOURCES}
    gate.exact(sources, plan["sources"], "Phase1 exact archived verifier/source closure")
    resolved = shared_selection(root) if plan["selection"] == SHARED_SELECTION_ID else load_ui_evidence(root).selection(root)
    api_run = gate.decode(gate.regular_bytes(directory / "run-attempt-1.json", limit=PHASE1_WITNESS_BYTES),
                          limit=PHASE1_WITNESS_BYTES)
    require(api_run.get("id") == request["runID"], "Phase1 retained chain API run")
    labels = (["producer"] + resolved[SHARED_KEY]["partitionIDs"]
              if plan["selection"] == SHARED_SELECTION_ID else ["rui1"])
    artifacts = directory / "artifacts"
    require(artifacts.is_dir() and not artifacts.is_symlink()
            and sorted(p.name for p in artifacts.iterdir()) == sorted(labels), "Phase1 complete worker artifact census")
    facts, first_event, units = {}, None, []
    execution = {"status": "INCOMPLETE", "jobs": {}, "workers": {}, "problems": []}
    try:
        require(api_run.get("status") == "completed" and api_run.get("conclusion") == "success",
                "Phase1 original execution did not succeed")
        execution["jobs"] = phase1_job_execution_facts(root, directory, plan, resolved, request["runID"])
    except (ValueError, OSError, KeyError, TypeError) as error:
        execution["problems"].append("job/command proof: " + str(error)[:1000])
    for label in labels:
        artifact = artifacts / label
        require(artifact.is_dir() and not artifact.is_symlink(), "Phase1 regular worker artifact")
        record = gate.decode(gate.regular_bytes(artifact / "native-admission.json", limit=PHASE1_WITNESS_BYTES),
                             limit=PHASE1_WITNESS_BYTES)
        binding = gate.decode(gate.regular_bytes(artifact / "phase1-event-binding.json", limit=gate.MAX_EVENT_BYTES),
                              limit=gate.MAX_EVENT_BYTES)
        event = gate.regular_bytes(artifact / "phase1-original-event.json", limit=gate.MAX_EVENT_BYTES)
        require(gate.regular_bytes(artifact / "phase1-gate-plan.json") == gate.canonical(plan)
                and record.get("phase1Gate") == binding, "Phase1 original worker plan/admission")
        gate.verify_collected_event(binding, registered_plan_bytes=gate.canonical(plan), original_event_bytes=event,
            api_run=api_run, tree=plan["tree"], resolved_bytes=canonical(resolved), sources=sources)
        require(first_event is None or event == first_event, "Phase1 workers received different dispatch events")
        first_event = event
        require(all(record.get(k) == v for k, v in source_binding(root).items()), "Phase1 exact native protocol binding")
        selected = shared_selection(root, label) if label not in ("producer", "rui1") else resolved
        require(gate.regular_bytes(artifact / "ci-selection.selected.json", limit=PHASE1_WITNESS_BYTES)
                == canonical(selected) and record.get("selectionSHA256") == sha256(canonical(selected)),
                "Phase1 exact worker selection")
        if label != "rui1":
            require(shared_role(record) == ("producer" if label == "producer" else "consumer")
                    and (label == "producer" or record[SHARED_KEY].get("partitionID") == label),
                    "Phase1 exact worker role/partition")
        diagnostic = phase1_retained_diagnostic_facts(root, artifact, record, binding)
        shared = phase1_retained_shared_facts(root, artifact, record, binding) if label != "rui1" else None
        executed = [] if label == "producer" else executed_methods(read_json(artifact / "unit-test-results.json"),
            selected["unitTestSelectors"], "FieldEvidenceAppTests", "Unit test bundle")
        units.extend(executed)
        if label == "rui1":
            from types import SimpleNamespace
            native = SimpleNamespace(source_binding=source_binding, verify_checkpoint=verify_checkpoint,
                                     executed_methods=executed_methods, canonical=canonical)
            load_ui_evidence(root).collected_review(root, artifact, native, plan["head"], str(request["runID"]))
        # This hashes retained XCResult bytes only; it does not perform an
        # xcresulttool export or pretend to revisit a vanished live filesystem.
        kernel = load_payload_kernel(root)
        result_names = ["Build.xcresult"] if label == "producer" else (["Build.xcresult", "UnitTests.xcresult", "UISmoke.xcresult"]
                                                                     if label == "rui1" else ["UnitTests.xcresult"])
        inventories = {}
        for name in result_names:
            require((artifact / name).is_dir() and not (artifact / name).is_symlink(), "Phase1 raw result directory")
            inventory = phase1_product_inventory((artifact / name).resolve(), kernel)
            require(any(item["type"] == "file" and item["size"] > 0 for item in inventory), "Phase1 nonempty raw result inventory")
            inventories[name] = {"entries": inventory, "inventorySHA256": kernel["object_sha"](inventory)}
        facts[label] = {"eventBindingSHA256": sha256(canonical(binding)), "diagnostics": diagnostic,
                        "shared": shared, "executedUnitMethods": executed, "rawResultInventories": inventories}
        if execution["jobs"]:
            try:
                execution["workers"][label] = phase1_worker_execution_facts(
                    root, artifact, record, selected, label, execution["jobs"][label])
            except (ValueError, OSError, KeyError, TypeError) as error:
                execution["problems"].append(label + " execution proof: " + str(error)[:1000])
        require(len(canonical(facts)) <= PHASE1_WITNESS_BYTES, "Phase1 retained worker facts bound")
    require(len(units) == len(set(units)) and set(units) == set(resolved["unitTestSelectors"]),
            "Phase1 complete every-method unit union")
    if execution["jobs"]:
        try:
            execution["payload"] = phase1_payload_execution_facts(root, directory, plan, resolved,
                                                                 request["runID"], execution["jobs"])
        except (ValueError, OSError, KeyError, TypeError) as error:
            execution["problems"].append("payload/artifact proof: " + str(error)[:1000])
    if not execution["problems"] and set(execution["workers"]) == set(labels):
        execution["status"] = "RETAINED_EXECUTION_FACTS_VERIFIED"
    require(len(canonical(execution)) <= PHASE1_WITNESS_BYTES, "Phase1 execution facts bound")
    return {"schema": "v23-phase1-retained-worker-chain.v1", "status": "INCOMPLETE",
        "runID": request["runID"], "planSHA256": request["planSHA256"], "workers": facts, "executionProof": execution,
        "pendingPredicates": (["complete retained execution facts"] if execution["status"] == "INCOMPLETE" else [])
                             + ["independent cold payload/no-rebuild and emitted-stream retention review", "closed qualification lifecycle"],
        "functionalQualification": gate.PENDING, "acceptance": False, "providerQualification": False,
        "releaseReady": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("admit", "verify", "select", "collect-diagnostics", "observe-build-before-boot", "record-no-index-build",
                                            "shared-seal", "shared-restore", "shared-fingerprint", "phase1-retained-chain"))
    parser.add_argument("--stage", choices=("dispatch", "worker"), default="worker")
    parser.add_argument("--output")
    parser.add_argument("--interrupted", action="store_true")
    parser.add_argument("--phase", choices=SHARED_FINGERPRINT_PHASES)
    parser.add_argument("--phase1-request", type=Path)
    args = parser.parse_args()
    if args.command == "phase1-retained-chain":
        require(args.phase1_request is not None, "Phase1 retained caller request")
        print(json.dumps(phase1_retained_worker_chain(Path(__file__).resolve().parents[1], args.phase1_request), sort_keys=True))
        return
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
                if record["selectionID"] in SHARED_SELECTION_IDS:
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
    if record["selectionID"] == UI_BATCH_SELECTION_ID:
        record["rui1ProtocolSources"] = load_ui_evidence(root).protocol_sources(root)
    record["gitTree"] = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    artifact = Path(os.environ["CI_ARTIFACT_DIR"])
    require(artifact.is_dir() and not artifact.is_symlink(), "artifact directory")
    if "phase1Gate" in record:
        binding, event_raw, _, _ = phase1_worker_context(root, os.environ)
        require(binding == record["phase1Gate"], "Phase1 worker context changed")
        originals = {"phase1-gate-plan.json": canonical(binding["plan"]),
                     "phase1-event-binding.json": canonical(binding), "phase1-original-event.json": event_raw}
        for relative, raw in originals.items():
            if args.command == "admit":
                write_new_evidence(artifact / relative, raw)
            else:
                require(load_phase1_gates(root).regular_bytes(artifact / relative, limit=1024 * 1024) == raw,
                        "Phase1 worker original event changed")
    if "coldOriginal" in record:
        binding, event_raw, _, _ = cold_worker_context(root, os.environ)
        require(binding == record["coldOriginal"], "cold worker context changed")
        originals = {"cold-original-plan.json": canonical(binding["plan"]),
                     "cold-event-binding.json": canonical(binding), "cold-original-event.json": event_raw}
        for relative, raw in originals.items():
            if args.command == "admit":
                write_new_evidence(artifact / relative, raw)
            else:
                require(load_phase1_gates(root).regular_bytes(artifact / relative, limit=1024 * 1024) == raw,
                        "cold worker original event changed")
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
