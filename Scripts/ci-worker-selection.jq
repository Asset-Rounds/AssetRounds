
            # Only the reusable development batch route carries its file binding.
            def dev_batch_route:
              ($ENV.NATIVE_SELECTION_ID // "") == "v23-dev-batch-no-index-d50";
            def shared_route:
              ($ENV.NATIVE_SELECTION_ID // "") == "v23-shared-coverage-d50x";
            def exact_keys:
              (([
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
              ] + (if dev_batch_route then ["devBatch"] elif shared_route then ["sharedCoverage"] else [] end)) | sort) == (keys | sort);
            # The shared coverage route: a build-only producer plan or one consumer partition.
            def shared_values($role):
              (.unitTestSelectors | length) as $count
              | ($ENV.V23_SHARED_ROLE // "") == $role
                and all(.unitTestSelectors[];
                  type == "string"
                  and test("\\AFieldEvidenceAppTests/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+\\z"))
                and (.sharedCoverage | type == "object")
                and ((.sharedCoverage | keys) == ["acceptance", "developmentOnly", "partitionID", "partitionIDs", "partitionsPath", "partitionsSHA256"])
                and .sharedCoverage.partitionsPath == "Scripts/v23-coverage-partitions.json"
                and (.sharedCoverage.partitionsSHA256 | type == "string" and test("\\A[0-9A-F]{64}\\z"))
                and (.sharedCoverage.partitionIDs | type == "array" and length >= 1 and length <= 60
                     and all(.[]; type == "string" and test("\\AS[0-9]{2}\\z"))
                     and (unique | length) == length)
                and .sharedCoverage.developmentOnly == true
                and .sharedCoverage.acceptance == false
                and (if $role == "producer" then
                       .sharedCoverage.partitionID == null
                       and ($ENV.V23_PARTITION_ID // "") == ""
                     else
                       (.sharedCoverage.partitionID | type == "string")
                       and .sharedCoverage.partitionID == ($ENV.V23_PARTITION_ID // "")
                       and (.sharedCoverage.partitionID as $id | .sharedCoverage.partitionIDs | index($id) != null)
                       and $count >= 1 and $count <= 500
                     end);
            def dev_batch_values:
              (.unitTestSelectors | length) as $count
              | ($count >= 1 and $count <= 150)
                and all(.unitTestSelectors[];
                  type == "string"
                  and test("\\AFieldEvidenceAppTests/[A-Za-z_][A-Za-z0-9_]*/test[A-Za-z0-9_]+\\z"))
                and (.devBatch | type == "object")
                and ((.devBatch | keys) == ["acceptance", "developmentOnly", "path", "question", "schema", "sha256"])
                and .devBatch.path == "Scripts/v23-dev-batch.json"
                and .devBatch.schema == "v23-dev-batch.v1"
                and (.devBatch.sha256 | type == "string" and test("\\A[0-9A-F]{64}\\z"))
                and (.devBatch.question | type == "string" and test("\\S") and length <= 500
                     and all(explode[]; . >= 32 and . != 127))
                and .devBatch.developmentOnly == true
                and .devBatch.acceptance == false;
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
              elif .tier == "D50" then
                .taskID == "V23-INTEGRATION-20260910"
                and [.setupArtifactTimeoutSeconds, .buildTimeoutSeconds,
                     .testTimeoutSeconds, .uiTimeoutSeconds, .totalBudgetSeconds]
                    == [300, 1800, 3000, 0, 5100]
                and (if dev_batch_route then dev_batch_values else (.unitTestSelectors == [
    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldOperationAuthoritySurvivesSuspensionAndRecoversOriginalReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardPreparationReopensOriginalPendingReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardValuesRetainOriginalStagesAndRejectCommit",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testDurablePreflightSubmitsConfirmedEnteredTimeZoneWithoutRewritingSavedInput",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveFinalizationUsesOriginalReceiptAndRejectsRetiredOperation",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLivePhotoRejectsRetiredPublicationAndRecoversOriginalCommitReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveItemFactoryAndEditorKeepOriginalPublicationWithoutCreatingStaging",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalPublishesOnceAndRetainsAuthenticRetryReceipt",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsTargetAppearingAfterPreparation",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsSubstitutionAndCancellation",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests/testGoldenFlowAccessibilitySpineAndControlMetricsAreExact"
                ] or .unitTestSelectors == [
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testContinueLaunchesEntersOnceOpensDurableHostAndColdReopenAddsNoWrites",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testContinueDeniesDraftPausedAndCompetingSourcesWithoutEffects",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testForeignCanonicalDraftDeniesEntryBeforeAnyWrite",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testContinueRecoversSourceAndEntryAcknowledgementLossWithOneOfEach",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testPendingEffectForAnotherItemIsNotSettledByAnOutOfOrderTap",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testRevisionPinnedRouteRetargetsThenReusesEntryAndBegunParentReopens",
    "FieldEvidenceAppTests/V23ProductionRoundItemMountingTests/testInterruptedPreparedBeginReopensForExplicitRecoveryAndCompletesOnce"
                ] or .unitTestSelectors == [
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission"
                ]) end)
              elif .tier == "D30" then
                .taskID == "V23-INTEGRATION-20260910"
                and [.setupArtifactTimeoutSeconds, .buildTimeoutSeconds,
                     .testTimeoutSeconds, .uiTimeoutSeconds, .totalBudgetSeconds]
                    == [300, 1800, 900, 0, 3000]
                and (.unitTestSelectors == [
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testCouldNotVerifyFinishRecordsOneReportAndOneCompleteThenShowsNextItem",
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testLostFinalizationAndCompleteAcknowledgementsResumeOriginalsOnce",
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testDeferAndKeepOpenRetainParentsAndAdvanceOnce",
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testRetiredSceneDeniesFinishAndAdvanceWithoutEffects",
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testTwoPhotoJourneyCommitsEachSlotOnceRecoversAndFinishes",
    "FieldEvidenceAppTests/V23ProductionRoundItemCompletionTests/testStoragePublicationAcceptsFreeByteDriftOnlyWithTheSameVerdict",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testActualRoundRoutesReadEveryWriterFrontierWithoutStartingOrResuming",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testActualRoundReadinessPublishesExactSessionAndRejectsWriterAndFinalCoverRaces",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testActualRoundFinalPublicationRejectsChangedNilRevisionFrontier",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testActualNativeRoundRouteAndBackPreserveReportsWithoutAutomaticWork",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testActualRoundOldPublicationCannotReadAfterFreshSceneActivation",
    "FieldEvidenceAppTests/V23ProductionRoundReadinessTests/testReadinessPreFinalHookRejectionDoesNotCarryHookOrWriteIntoNextOperation"
] or .unitTestSelectors == [
    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldOperationAuthoritySurvivesSuspensionAndRecoversOriginalReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardPreparationReopensOriginalPendingReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testPhotoDiscardValuesRetainOriginalStagesAndRejectCommit",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testDurablePreflightSubmitsConfirmedEnteredTimeZoneWithoutRewritingSavedInput",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesCanonicalNamesAndRejectsStaleOrReplacedPlans",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementRejectsMalformedNamesAndUnsafeFileKinds",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testStartupPrivateRetirementPreservesInterruptedFinalizationAndReachesEraseAdmission",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveFinalizationUsesOriginalReceiptAndRejectsRetiredOperation",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLivePhotoRejectsRetiredPublicationAndRecoversOriginalCommitReceipt",
    "FieldEvidenceAppTests/V23ProductionCheckRunnerItemHostTests/testLiveItemFactoryAndEditorKeepOriginalPublicationWithoutCreatingStaging",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalPublishesOnceAndRetainsAuthenticRetryReceipt",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsTargetAppearingAfterPreparation",
    "FieldEvidenceAppTests/S3_2MediaPipelineTests/testPreparedImmutableOriginalRejectsSubstitutionAndCancellation",
    "FieldEvidenceAppTests/S8_2GoldenAccessibilityTests/testGoldenFlowAccessibilitySpineAndControlMetricsAreExact"
] or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt"
                ] or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testRetainedLiveContextDefersCleanupUntilColdRecovery",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEveryInterruptionRecoversOldOrFullyErasedNew"
                ] or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionFreezesOneChoiceAndRecoversOriginalWithoutNewIDs",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionResolutionRejectsStaleTargetAndRetiredOwnerWithoutEffects",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardRequiresConfirmationThenReplaysOriginalWithoutConfirmationOrEffects",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testProductionDiscardCanCompleteReviewWithoutOperationalRoundAndRejectsRetirement",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceAuthenticatesCurrentPendingAndTerminalOriginalsWithoutReadEffects",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsEverySubstitutedFieldAndNonDraftWithoutEffects",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceReturnsUnsupportedOnlyAfterAuthenticCurrentReceipt",
                    "FieldEvidenceAppTests/V23ProductionDestinationReviewTests/testSavedReviewReferenceRejectsDirtyCorruptQuarantinedAndRetiredHistoryWithoutEffects",
                    "FieldEvidenceAppTests/V23ProductionFourRootShellTests/testPhysicalRestoredReviewDiscardUsesProductionAccessAndColdOriginalReadback",
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditsPersistIncompleteValuesAndColdReopenWithoutEffects",
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditCASPreservesBeginAndPhotoSlotsAndRejectsFrozenOrForeignState",
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldEditAcknowledgementLossRecoversOriginalBeforeNewerEdits",
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldAutosaveUsesTrailingMaximumAndRetainsFailedAttempt",
                    "FieldEvidenceAppTests/V23CheckRunnerItemFieldEditingTests/testFieldFlushDrainsEditsArrivingDuringAwaitAndAuthenticatesReadback"
]
                or .unitTestSelectors == [
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNineValuesRoundTripAndExposeExactClosedFields",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testLegalNonUUIDStringsStayExactAndIncumbentIDGrammarIsNotBroadened",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testOptionalFieldsMustBeAbsentRatherThanExplicitNull",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testWrongVersionKindWorkspaceAndNilIdentitiesAreRejected",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testEmptySelectionMatchesIndependentLiteralBytesAndHash",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNestedLegacyValueGroupsAreClosedOnlyAtTheNewBoundary",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testRevisionBoundariesPreserveUInt64AndIntWithoutNarrowingOrOverflow",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testDuplicateAndConflictingFindingOwnerAndRelationshipIdentitiesReject",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCanonicalOrderingIsUTF8AndRelationshipOwnerTupleOrder",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testDigestsRejectMalformedValuesAndSelectionTampering",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testExactRecheckOwnerKindRevisionAndDigestAreRequired",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testTypedFindingC14AndRecheckBindingsRejectIndependentlyValidWrongFacts",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testOriginalAndSelectedProvenanceRemainDistinctWithoutAuthenticityClaims",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testConflictingAcceptanceAndSourceIdentitiesCannotBeMerged",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCanonicalCodecRejectsDuplicateWireKeysNoncanonicalBytesAndOversizeInput",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testCompleteSelectionByteLimitAppliesBeforePublication",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testNilAndCrossWorkspaceSourceC14AndFrontierIdentitiesReject",
                    "FieldEvidenceAppTests/V23FindingOwnerSelectionContractsTests/testMappedSourceAndC14PairsKeepExactFieldsAndSeparateAcceptances",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testBothOwnerKindsRoundTripWithIndependentGoldenDigests",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testSemanticReferencesStayDistinctFromTransportHashesAndBindConsumers",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testHumanAndImportedSourcesNeedNoFabricatedActivityBinding",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testOwnerRevisionAdvancesWithoutChangingFindingRevision",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testHistoricalValueClassificationDoesNotGrantRetryAcceptance",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testSuccessorCannotRewriteDropOrReplaceOldFacts",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testLifecycleTransitionPreservesOriginalFieldsAndRevisionLaw",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testWorkspaceOwnerAndKernelIdentityCensusRejectsConflicts",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testC14SupportRequiresOriginalGenuineActionAndRetainsUnlinkedHistory",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testDirectFindingEndpointsAllowRevisionZeroWithoutCorrection",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testRealC14NonFindingSourceAndMixedEndpointsAreSupported",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testRelationshipHistoryPreservesConfirmationAndExplicitRemoval",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testRelationshipBasisRolesKindsAndSingleOwnershipAreClosed",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testAffectedClosureRejectsCrossStreamReversePairsCyclesAndDomainAmbiguity",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testEndpointOwnerTokensAndAcceptanceIdentitiesCannotConflict",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testPredecessorOriginActorAndTimeAreExact",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testHistoryRejectsReusedMutationAndSkippedOwnerRevision",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testUInt64AndIntEdgesRejectWithoutInvokingUnsafeLegacyArithmetic",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testRecordAndEndpointUnionKeysNullsAndDigestsAreClosed",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testCanonicalTransportRejectsUnknownNestedFieldsDuplicateKeysAndOversize",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testCompleteRecordByteBoundIncludesRetainedSupportReferences",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testAppendOnlyRetentionUsesExactBytesAndGroupedEventIdentity",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2OwnerRevisionFactsAcrossRelationshipsIncludeBothReferenceSides",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActualRecordAndPredecessorReferencesJoinFactCensus",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2RetainedC14ActionRevisionRejectsChangedEventAndDigestOnBothSides",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2RetainedC14EventIdentityRejectsRevisionReuseAndAllowsDifferentEvents",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2C14EndpointEventActionConflictsReachRelationshipAndCombinedHeads",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActivityRevisionFactsRejectKindAndDigestConflictsOnBothSides",
                    "FieldEvidenceAppTests/V23FindingOwnerContractTests/testR2ActivityScopesReceiptsRevisionsAndWorkspacesStayIndependent",
                    "FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testBothKindsBindCanonicalBytesAndDistinctRowIdentity",
                    "FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testEveryDuplicatedColumnRejectsMismatchForBothKinds",
                    "FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testPredecessorDigestCannotBeDroppedOrReplaced",
                    "FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testMalformedAndValidDivergentCanonicalPayloadsAreRejected",
                    "FieldEvidenceAppTests/V23FindingOwnerPersistenceTests/testFileBackedSwiftDataReopenRetainsBothKindsAndRevisions",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testFreshHumanCreationDerivesOnlyItsOriginalFacts",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCanonicalCreationMatchesIndependentCommandAndRecordExpectations",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testLegalKernelStringsAndUnicodeTextBytesRemainExact",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCreationOptionalClassificationAndActivityNeverBecomeUniversalIDGates",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCreationRejectsSubstitutedScaleSubjectWorkspaceAndAttribution",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testTransitionDerivesOneRevisionWithoutReplacingAnyOtherFact",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCorrectiveLinkAndRemovalPreserveFindingRevisionAndOriginalSupport",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCorrectiveOperationsRejectWrongRolesRevisionsMissingReadsAndStaleBasis",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testExactPredecessorAndMutationMetadataCannotBeSubstituted",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testVerifiedResolutionRequiresTheExactRetainedPassedRecheck",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCanonicalCommandBindsDependenciesAndAttributionWithoutClaimingAuthenticity",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testClosedCommandAndOperationWireRejectReplacementSourceAndProofFields",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testNestedUnknownFieldsAndNoncanonicalBytesRejectThroughActualCodec",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testRevisionBoundsRejectBeforeLegacyIncrementAndPreserveAssetZero",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testFrontierDuplicateConflictsUnknownIdentitiesAndMissingDependencyFailClosed",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testWholeWorkspaceFrontierExceedsRegistryCountAndRetainsCanonicalByteLimit",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCommandAcceptanceCensusRejectsEveryPredecessorAndSupportOverlap",
                    "FieldEvidenceAppTests/V23FindingOwnerMutationContractTests/testCommandAcceptanceCensusAllowsExactOverlapAndDistinctKeysThroughDerivation",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testOpenEvidenceManifestCanonicalRoundTripNormalizesArtifactsAndRejectsTampering",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testHandoffPresentationRequiresExactSavedProfileAndRemainsDefaultOff",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04G01DeterministicProfilePresetAndConfirmationBytes",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04A01CustomerSafePackagingAndAccessibleOutputs",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04H01RejectsCorruptStaleUnsafeAndSecondRendererInputs",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04I01InterruptionLeavesZeroOrRecoverableCanonicalEffect",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testV23P04C04R01RestoreCloneForkAndHistoricExportImmutability",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveExactRetryReturnsOriginalReceipt",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveHistoricExactRetryAfterSuccessorReturnsOriginalReceipt",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveDivergentMutationReuseRejectsWithoutChanges",
                    "FieldEvidenceAppTests/V9_69ShopProfileOpenHandoffTests/testShopProfileSaveNewStaleMutationRejectsWithoutChanges",
                    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38G01PatternsOverridesAndHistoryProjectDeterministically",
                    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38A01LeapMonthEndLastWeekdayAndScopesPreview",
                    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38H01InvalidRulesStalePreviewAndIdentityDriftHaveNoEffects",
                    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38I01DSTClockReminderAndEffectBeforeReceiptRetryExactlyOnce",
                    "FieldEvidenceAppTests/V9_101AdvancedRecurrenceWorkflowTests/testV23P04C38R01CompletionScheduleChangeReplayAndRestoreRemainStable"
                  ]
                  or .unitTestSelectors == [
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testNotificationPreferenceEraseFencePreservesExactCooldownAndRejectsHeldSettingAuthority",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testAbsentApplicationSupportHasNoEraseAuthority",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testGoldenEraseActivatesEmptyGenerationAndClearsFrozenState",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testRetainedLiveContextDefersCleanupUntilColdRecovery",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEveryInterruptionRecoversOldOrFullyErasedNew",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testCancelAndDirtyContextChangeNothingBeforeMarker",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testLiveCleanupWaitsForOldContextReferenceDrain",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSystemNotificationReadbackRejectsAlteredContentAndCalendarComponents",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testConcreteReminderOwnerRejectsCallerProjectionAndUsesPrivateOpaqueSystemIDs",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testConcreteReminderEraseAcrossOwnersDrainsLateAddBeforeDeletingMapping",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22G01FixedCompletionRelativeEditorDueAndStartOnce",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22A01ReminderDenialEvictionStableIDReconcileKeepsDueTruth",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22H01DSTTimeZoneActiveEditHorizonRetiredPartialPacketFailClosed",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22I01InterruptedWritesAndSameMutationIDRecoverIdempotently",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testV23P04C22R01BackupReplaceCloneForkRebuildAndHistoryRemainImmutable",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testActualEraseRetainsGenerationAndPreferencesUntilNotificationAbsenceIsVerified",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testC22RecoverabilityVerificationAnchor",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testSeededEraseFixtureRejectsLaterDirectMutationWithoutCheckpointAdoption",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedDetailedPolicyUsesAuthenticatedKindsAndReplacesChangedPayloads",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testAppLockEnableProjectsGenericAndDisableUsesCurrentDetailedConsent",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredDetailedRequestIsRemovedOnPrivacyDowngradeWithoutReadding",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testExpiredUnobservedGenericReminderStillFailsWithoutEffects",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testPermissionDenialStillRemovesForbiddenDetailWithoutClaimingDelivery",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testSavedReconciliationCannotRenewRevokedOriginalProof",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testNotificationCopySourcesBindExactReleaseAndEffectiveBasis",
                    "FieldEvidenceAppTests/V9_85RecurringRoundExperienceTests/testGenericPolicyRejectsDetailedDurableMappingWithoutSystemEffects",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEraseManifestHandoffPreservesExactInodeAndSupportsRepeatedConstructorRecovery",
                    "FieldEvidenceAppTests/S6_6EraseRecoveryTests/testEraseManifestHandoffRejectsHostileSidecarsTargetsAndChangedPointerWithoutConsumption"
                  ]
                  or .unitTestSelectors == [
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
              elif .tier == "D40P" then
                shared_route
                and .taskID == "V23-INTEGRATION-20260910"
                and [.setupArtifactTimeoutSeconds, .buildTimeoutSeconds,
                     .testTimeoutSeconds, .uiTimeoutSeconds, .totalBudgetSeconds]
                    == [300, 2400, 0, 0, 3000]
                and shared_values("producer")
              elif .tier == "D50C" then
                shared_route
                and .taskID == "V23-INTEGRATION-20260910"
                and [.setupArtifactTimeoutSeconds, .buildTimeoutSeconds,
                     .testTimeoutSeconds, .uiTimeoutSeconds, .totalBudgetSeconds]
                    == [300, 0, 3000, 0, 3600]
                and shared_values("consumer")
              else false
              end;
            exact_keys
            and (.schemaVersion == 1)
            and (.taskID | nonempty_string)
            and (.tier | type == "string" and IN("N8", "D30", "D50", "P12", "F25", "D40P", "D50C"))
            and (if dev_batch_route then .tier == "D50" else true end)
            and (if shared_route then (.tier == "D40P" or .tier == "D50C") else true end)
            and (.runUISmoke | type == "boolean")
            and tier_values_match
            and (.unitTestSelectors | selectors("FieldEvidenceAppTests/"; 1))
            and (
              if .tier == "N8" or .tier == "D30" or .tier == "D50" or .tier == "D40P" or .tier == "D50C" then
                (.runUISmoke == false)
                and (.uiTestSelectors | type == "array" and length == 0)
              else
                (.runUISmoke == true)
                and (.uiTestSelectors | selectors("FieldEvidenceAppUITests/"; 1) and length == 1)
              end
            )
