
            def exact_keys:
              ([
                "schemaVersion",
                "taskID",
                "tier",
                "runUISmoke",
                "setupArtifactTimeoutSeconds",
                "buildTimeoutSeconds",
                "testTimeoutSeconds",
                "uiTimeoutSeconds",
                "totalBudgetSeconds",
                "unitTestSelectors",
                "uiTestSelectors"
              ] | sort) == (keys | sort);
            def nonempty_string:
              type == "string" and test("\\S");
            def selectors($prefix; $minimum):
              . as $values
              | ($values | type == "array")
                and (($values | length) >= $minimum)
                and (all($values[];
                  type == "string"
                  and startswith($prefix)
                  and (length > ($prefix | length))))
                and (($values | unique | length) == ($values | length));
            def tier_values_match:
              if .tier == "N8" then
                [
                  .setupArtifactTimeoutSeconds,
                  .buildTimeoutSeconds,
                  .testTimeoutSeconds,
                  .uiTimeoutSeconds,
                  .totalBudgetSeconds
                ] == (if .taskID == "V23-INTEGRATION-20260910"
                      then [300, 1200, 900, 0, 2400]
                      else [300, 600, 900, 0, 2400]
                      end)
              elif .tier == "D30" then
                .taskID == "V23-INTEGRATION-20260910"
                and [.setupArtifactTimeoutSeconds, .buildTimeoutSeconds,
                     .testTimeoutSeconds, .uiTimeoutSeconds, .totalBudgetSeconds]
                    == [300, 1800, 900, 0, 3000]
                and (.unitTestSelectors == [
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testPublishedV1ManifestRoundTripPreservesCanonicalBytesAndOmitsExtensions",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testUnsignedBoundsRoundTripPreservesEntireUInt64Domain",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testSignedDomainAndMixedWrongKindOrInvertedBounds",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestVersionsRequireMatchingCodecAndReader",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testExtendedScalarAndArrayKindsRequireManifestTwo",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestDecoderRejectsInvalidNumericBoundsWithoutRounding",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testManifestDecoderRejectsUnknownMalformedAndExplicitNullFields",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testCodecTwoKeepsExistingRulesAndClosesVersionSpecificTimeMetadata",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testPreservedStringAndStringMapMetadataRoundTripWithoutInventedCountLimit",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testStringMapMetadataRejectsInvalidBoundsShapesAndArrayUse",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testNumericEnumMetadataPreservesExactSourceRotationWireValues",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testNumericEnumMetadataRejectsMixedMalformedAndLegacyDefinitions",
                    "FieldEvidenceAppTests/V23ActivityCompletedManifestEvolutionTests/testClosedEmptyObjectMetadataRequiresSchemaTwoAndMatchesPoseWire",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testClosedCompletedFileRoundTripPreservesRealNestedV2AndSeparateHashes",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureUsesActivityRevisionsAndKeepsWorkspaceFrontierPortable",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureRejectsStaleActivityRevisionAndInvalidTransitionOrderingOrStateChain",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCaptureRejectsOverflowAndNonfiniteOrResampledTime",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testFileRejectsWrongFamilyVersionOutputAndUnknownFields",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testTypedPayloadTamperFailsEvenWithRecomputedWholeFileHash",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testWholeFileTamperFailsEvenWhenNestedSnapshotIsUnchanged",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCapturedAbsenceRequiresEveryClosedQueryAtExactFrontier",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testFullFrozenProfileAndManifestAreBoundToSnapshot",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testExplicitSelectionUsesCanonicalObjectsAndClosedKeys",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testStandalonePunchDoesNotManufactureInstallationOrAccountabilityAbsence",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testLegacyPredecessorOwnerKeepsUUIDPathAndWholeFileDigestDistinct",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testCrossActivityCorrectionOwnsNewOriginalForLegacyAndClosedPredecessors",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testUnfinishedAmendmentRetainsActualPriorWithoutInventingCompletedOutput",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testApprovedMediaRequiresExactBytesLengthWorkspaceAndOutputScope",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testPlacementSourcesRetainExactPoseAndPhysicalAncestors",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testPlacementSourcesRejectMissingForeignAndUnselectedValues",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testReviewedEvidenceFreezesPlanProjectionAndSeparateFieldMediaHashes",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testReviewedEvidenceRejectsMissingTamperedAndForeignSources",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testNewProvenanceArraysAreRequiredClosedWireFields",
                    "FieldEvidenceAppTests/V23ActivityCompletedFileTests/testLegacy32CorpusPreservesLiteralBytesAndBareV2Codec",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testRealWriterReadsPopulatedInstallationAndEntireSelectedProfileWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCaptureFreezesExactPromotedPackageAndSourceWorkflow",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testHistoricalCompletionRetainsRecordedPackageWithoutCurrentStartPointer",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testMissingRecordedPackageRejectsCaptureAndOldFrameWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCaptureUsesActualActivityRevisionTransitionsIncludingTaskAndAsBuiltGaps",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testWrongWorkspaceMissingActivityAndUnavailableSelectedProfileRejectWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testCommittedProfileChangeRejectsOldSelectionAndFrameWithoutAdoptingNewProfile",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testWriterInvalidationAndGenerationChangeRejectPreviouslyReadFrameWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameFrontierTaskReplacementAndFamilyInsertionOrRemovalRejectWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameFrontierAcceptedReceiptTamperRejectsWithoutEffects",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testSameRevisionRehashedProfileCannotReplaceAcceptedBytesEvenWhenSelectedByNewReference",
                    "FieldEvidenceAppTests/V23ActivityCompletedProductionTests/testQuarantinedActivityOrProfileReceiptCannotAuthorizeSourceRead",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionAcceptsDistinctFieldAndApprovedMediaDigests",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsUnapprovedAndMixedMedia",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsOriginalAndMissingOutputReferences",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsWrongWorkspaceAndAudience",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsMissingRejectedStaleAndChangedSource",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRejectsSemanticCardTampering",
                    "FieldEvidenceAppTests/V23ActivityEvidenceProjectionTests/testV23P03C20CompletedProjectionRebuildsMarkupWithoutChangingReviewedPlan",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testActualAppBundleAdmitsExactCompleteManifestAndBothSchemas",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testPublishedDefinitionsAndSevenSectionRegistryRemainExactButOldReleaseIsExcluded",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testActualBundleLookupSupportsFlattenedAndPreservedResourceLayouts",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testMissingAndRenamedResourcesCannotFallBackToAnotherBundle",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testDuplicateResourceIdentityFailsEvenWhenBothCopiesAreAuthentic",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testTruncatedOversizedAndSameSizeTamperedResourcesFailAtRealLoader",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testSchemaResourceIdentityCannotBeSwappedAndManifestIdentityCannotBeRewritten",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testSymlinkedResourceIsNotAnAppOwnedResource",
                    "FieldEvidenceAppTests/V23ActivityCompletedReportReleaseTests/testFrozenReadbackRejectsWrongIdentityVersionReaderRegistryAndIncompleteCatalog",
                    "FieldEvidenceAppTests/V9_54ActivityContractFamiliesTests/testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed"]
                  or .unitTestSelectors == ["FieldEvidenceAppTests/V9_18PackLifecycleIntegrationTests/testParentFinalizationCheckNoIssueUsesOriginalFiveSagaHistory"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPureRuleCreatesOnlyCurrentOnlyTombstonesAndRejectsCollisions",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testCancelRemovesOnlyOwnedStageAndDirtyCurrentFailsClosed",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPacketCollisionFailsBeforeGenerationOrJournalMutation",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRecoveryPreservesReplacementUnionAcrossEveryJournalPhase",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRestoreIntentTimestampUsesOneCanonicalMillisecondDomain",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C18RegistryPointerBindsPromotionReceiptIdentity",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C05Records42ReplacementUnionsPredecessorClosedMetadata",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C36ReplacementRecordRetainsCanonicalOperationalIdentity",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testC21ClientCapabilityLifecycleAnchor",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C34PackageRouteUsesOneShellAndNoWriter",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testFinalizedReportBytesAndReceiptsSurviveRepeatedForkAndColdReadback"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPureRuleCreatesOnlyCurrentOnlyTombstonesAndRejectsCollisions",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testCancelRemovesOnlyOwnedStageAndDirtyCurrentFailsClosed",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testPacketCollisionFailsBeforeGenerationOrJournalMutation",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRecoveryPreservesReplacementUnionAcrossEveryJournalPhase",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testRestoreIntentTimestampUsesOneCanonicalMillisecondDomain",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C18RegistryPointerBindsPromotionReceiptIdentity",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C05Records42ReplacementUnionsPredecessorClosedMetadata",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C36ReplacementRecordRetainsCanonicalOperationalIdentity",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testC21ClientCapabilityLifecycleAnchor",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testV23P03C34PackageRouteUsesOneShellAndNoWriter"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testFinalizedReportBytesAndReceiptsSurviveRepeatedForkAndColdReadback"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkCreatesReviewReceiptAndSecondHopSurvivesOriginalPackageRemoval",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPopulatedCrossWorkspaceReplacementCreatesOnlyReviewAndRetainsOriginalHistory",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPrepublicationInterruptionReconcilesToUnchangedPopulatedGeneration",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkKeepsTerminalHistoryAndUnrelatedDraftOwners",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testReviewPlanRejectsMissingOrChangedOwnedRowsWithoutConsumingUnrelatedDrafts"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkCreatesReviewReceiptAndSecondHopSurvivesOriginalPackageRemoval",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPopulatedCrossWorkspaceReplacementCreatesOnlyReviewAndRetainsOriginalHistory",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testSameWorkspaceReplacementPreservesCheckpointAndOriginalReceiptBytes",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPrepublicationInterruptionReconcilesToUnchangedPopulatedGeneration",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testPhysicalForkKeepsTerminalHistoryAndUnrelatedDraftOwners",
                    "FieldEvidenceAppTests/V23RepetitiveCaptureRestoreReviewTests/testReviewPlanRejectsMissingOrChangedOwnedRowsWithoutConsumingUnrelatedDrafts",
                    "FieldEvidenceAppTests/S6_5ReplacementUnionTests/testGoldenReplacementKeepsIncomingLiveAndUnionsCurrentRoot"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testUnboundAndRetiredOwnersCannotMintOrRebind",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testDisabledForegroundEditAndFreshAuthorityReplayPreserveExactBytes",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testEnabledPolicyRequiresUnlockAndOldCommandCannotSurviveRelock",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testCommandsCannotTransferAcrossAdaptersOrGateIssuers",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testReplacementOwnerAcceptsOnlyFreshCommandsAndRetirementIsMonotonic",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testProtectedDataAndConfigurationTransitionsRevokeHeldEditsWithoutEffects",
                    "FieldEvidenceAppTests/V23ReminderPolicyEditTests/testActualPreferenceWriteSerializesWithRevocationAndRetirement",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionReconciliationRetryKeepsSavedRevisionAndNeverPrompts",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionSettingsReadDoesNotPromptAndDeniedEnablePersistsExplicitChoice",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionDetailChoiceWhileDisabledDoesNotPromptAndRejectsStaleEdit",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionAppLockRequiresUnlockAndOldSettingsPublicationStaysRevoked",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionPermissionReplyAfterBackgroundCannotSaveConsent",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReadNeverPromptsAndExplicitRequestNeverWritesConsent",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testInactiveDisabledAndLockedEnabledStatesCannotPrompt",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testRevocationDuringAuthorizationReadPreventsPrompt",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testPermissionReplyAfterRevocationCannotRenewForegroundOrConsent",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testGenericEncodingAndReadbackRetainExactLegacyShape",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testBothKindsUseApprovedCopyAndTokenOnlySystemPayload",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenZoneAndEffectiveInstantDistinguishDSTFold",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testDetailedReadbackRejectsUnapprovedCopyAndAncillaryFields",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testNumericZoneFallbackUsesExplicitOffsetWithoutDeviceDefaults",
                    "FieldEvidenceAppTests/V23DetailedReminderDeliveryTests/testFrozenOffsetCopyDoesNotResolveCurrentTimeZoneRules",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testIncompleteEnableAndDisableRemainAvailableForAuthenticatedRecovery",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testEnabledAndCompletedDisabledEditsReopenWithoutReplayingPolicyOrOSEffects",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testSecondEditRollsContinuationAndRejectsOldOperationAndAuthenticationSubject",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPreferenceAndPendingPublicationRecoverMetadataExactlyOnce",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testInterruptedPolicyEditRejectsOldSubjectBeforeNewToggleSourceOrOSEffects",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testDivergentPendingBlocksSettlementAndSecondPolicyWriteWithoutDiscardingEvidence",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testUnstampedResetEraseAndChangedStampCannotRepairControl",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testForeignPreferencesControlBindingAndChangedSettingDenyBeforePolicyWrite",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testMissingDisabledControlWithStampOrPendingIsNotReady",
                    "FieldEvidenceAppTests/V23ReminderControlContinuationTests/testNilContinuationPreservesLegacyCanonicalControlAndSubjectBytes"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testDeferredEraseRetainsLiveOldContextAcrossAppAccessResumeUntilDrain",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testSuspendedRestoredActivationCannotReleaseANewerBindingInTheSameCoordinator",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testRepeatedLifecyclePausesRetainPostAdoptionActivationForExactRetry",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testPostAdoptionExecutionRevokedAtFirstAwaitCannotInstallAStaleTokenOrRead",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testSupersededPostAdoptionCatchCannotOverwriteNewReadyExecution",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupReleaseFailureRetainsOriginalOwnerAndRetries",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupInterruptionAfterRetirementResumesOriginalTicket",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testImmediateEraseCleanupReplacesRetiredWriterBeforePublication",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testErasedActivationMismatchAndRepeatedBeginReleaseOnlyTheAcquiredWriter",
                    "FieldEvidenceAppTests/V23ProductionAppAccessTests/testPresentationDeferredEraseRetainsDrainAcrossPauseAndResumesWithFreshService",
                    "FieldEvidenceAppTests/V23ProductionAppAccessTests/testProductionEraseAdoptsFreshSettingOwnerAndNextToggleCommits",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testDeferredEraseRetainsLiveOldContextAcrossAppAccessResumeUntilDrain"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testSuspendedRestoredActivationCannotReleaseANewerBindingInTheSameCoordinator",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testRepeatedLifecyclePausesRetainPostAdoptionActivationForExactRetry",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testPostAdoptionExecutionRevokedAtFirstAwaitCannotInstallAStaleTokenOrRead",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testSupersededPostAdoptionCatchCannotOverwriteNewReadyExecution",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupReleaseFailureRetainsOriginalOwnerAndRetries",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testEraseCleanupInterruptionAfterRetirementResumesOriginalTicket",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testImmediateEraseCleanupReplacesRetiredWriterBeforePublication",
                    "FieldEvidenceAppTests/S2PersistenceLedgerTests/testErasedActivationMismatchAndRepeatedBeginReleaseOnlyTheAcquiredWriter",
                    "FieldEvidenceAppTests/V23ProductionAppAccessTests/testPresentationDeferredEraseRetainsDrainAcrossPauseAndResumesWithFreshService",
                    "FieldEvidenceAppTests/V23ProductionAppAccessTests/testProductionEraseAdoptsFreshSettingOwnerAndNextToggleCommits",
                    "FieldEvidenceAppTests/V23ReminderProductionSettingsTests/testProductionCompletedEraseReplacesOwnersAndRejectsPendingPermissionEdit",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState"]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyEnvelopeArchiveSnapshotBytesRemainExact",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyMutationCommandRequestBytesRemainExact",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyEnvelopeRowsRejectCorruptMirrorsAndBytes",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testSchema3RoundTripBindsSeparateTypedAndFileDigests",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testClosedFileReferenceRejectsUnknownFieldsVersionsAndNoncanonicalIdentity",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testEnvelopeRejectsUnknownSchemasReservedLegacyFieldAndIncompleteSchema3",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testOnlyUnfinishedSchema2CanFinalizeIntoSchema3",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testSchema3SupersessionRetainsWholeReferenceAndRejectsDowngrade",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyMutationAndGenericCommandRejectSchema3EvenWithRecomputedMutationHash",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyAndSchema3ForkRepeatForkPreserveSourceAndFileIdentity",
                    "FieldEvidenceAppTests/V23ActivityEnvelopeCodecEvolutionTests/testLegacyUnknownKindRemainsReadableButNotWritable",
                    "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34G01StandalonePreparationDecisionCorrectionRecheckCloseoutAndReport",
                    "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34H01StaleWrongAssetConflictingRecheckAndUnresolvedCountFailWithoutEffect",
                    "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34I01EffectBeforeReceiptInterruptionRecoversExactlyOnce",
                    "FieldEvidenceAppTests/V9_97PunchReviewWorkflowTests/testV23P04C34R01ReopenRetryImmutableHistoryAndDeterministicReportReconstruction",
                    "FieldEvidenceAppTests/V9_54ActivityContractFamiliesTests/testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed"
                  ]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V9_54ActivityContractFamiliesTests/testV23P03C47H01CrossFamilyClaimsInvalidTransitionsAndStaleInputsFailClosed"
                  ])
              elif .tier == "P12" then
                [
                  .setupArtifactTimeoutSeconds,
                  .buildTimeoutSeconds,
                  .testTimeoutSeconds,
                  .uiTimeoutSeconds,
                  .totalBudgetSeconds
                ] == [300, 600, 900, 900, 3300]
              elif .tier == "F25" then
                [
                  .setupArtifactTimeoutSeconds,
                  .buildTimeoutSeconds,
                  .testTimeoutSeconds,
                  .uiTimeoutSeconds,
                  .totalBudgetSeconds
                ] == (if .taskID == "S10.4"
                      then [420, 900, 1200, 2520, 4500]
                      else [300, 900, 1200, 1800, 4500]
                      end)
              else false
              end;
            exact_keys
            and (.schemaVersion == 1)
            and (.taskID | nonempty_string)
            and (.tier | type == "string" and IN("N8", "D30", "P12", "F25"))
            and (.runUISmoke | type == "boolean")
            and tier_values_match
            and (.unitTestSelectors | selectors("FieldEvidenceAppTests/"; 1))
            and (
              if .tier == "N8" or .tier == "D30" then
                (.runUISmoke == false)
                and (.uiTestSelectors | type == "array" and length == 0)
              else
                (.runUISmoke == true)
                and (.uiTestSelectors | selectors("FieldEvidenceAppUITests/"; 1) and length == 1)
              end
            )
