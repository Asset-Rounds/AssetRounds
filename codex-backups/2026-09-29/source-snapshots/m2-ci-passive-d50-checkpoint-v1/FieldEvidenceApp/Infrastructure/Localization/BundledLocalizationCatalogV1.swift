import Foundation

enum BundledLocalizationKeyV1: String, CaseIterable, Sendable {
    case feedbackSubject = "feedback.mail.subject"
    case feedbackBodyTemplate = "feedback.mail.body_template"
    case mailComposerTitle = "feedback.mail.composer.title"
    case mailRecipient = "feedback.mail.recipient"
    case mailAttachmentCount = "feedback.mail.attachment_count"
    case mailMessageHeading = "feedback.mail.message.heading"
    case mailMessageLabel = "feedback.mail.message.label"
    case commonDone = "common.done"
    case packageRequiredViews = "package.illuminated_sign.guidance.required_views"
    case packageVisibleConditionsOnly = "package.illuminated_sign.guidance.visible_conditions_only"
    case packageAuthorizedPosition = "package.illuminated_sign.guidance.authorized_position"
    case accountabilityHeading = "accountability.heading"
    case accountabilityParty = "accountability.party"
    case accountabilityRole = "accountability.role"
    case accountabilityActor = "accountability.actor"
    case accountabilityQualification = "accountability.qualification"
    case accountabilitySignoff = "accountability.signoff"
    case assetSemanticIlluminatedSignName = "asset.semantic.sign.illuminated.name"
    case assetSemanticIlluminatedSignDescription = "asset.semantic.sign.illuminated.description"
    case assetSemanticHeading = "asset.semantic.heading"
    case assetSemanticKind = "asset.semantic.kind"
    case assetSemanticProductIdentity = "asset.semantic.product_identity"
    case assetSemanticWorkSubjectScope = "asset.semantic.work_subject_scope"
    case assetSemanticLifecycle = "asset.semantic.lifecycle"
    case assetSemanticState = "asset.semantic.state"
    case assetSemanticUnknownState = "asset.semantic.state.unknown"
    case assetSemanticDuplicateState = "asset.semantic.state.duplicate"
    case assetSemanticRetiredState = "asset.semantic.state.retired"
    case assetSemanticReplacedState = "asset.semantic.state.replaced"
    case assetSemanticRecordedState = "asset.semantic.state.recorded"
    case authorityCriterionHeading = "authority.criterion.heading"
    case authorityCriterionAuthoritySource = "authority.criterion.authority_source"
    case authorityCriterionApplicability = "authority.criterion.applicability"
    case authorityCriterionApplicable = "authority.criterion.applicability.applicable"
    case authorityCriterionNotApplicableWithReason = "authority.criterion.applicability.not_applicable_with_reason"
    case authorityCriterionApplicabilityUnknown = "authority.criterion.applicability.unknown"
    case authorityCriterionConflictReviewRequired = "authority.criterion.applicability.conflict_review_required"
    case authorityCriterionApplicabilityUnsupported = "authority.criterion.applicability.unsupported"
    case authorityCriterionResult = "authority.criterion.result"
    case authorityCriterionMeetsScreeningCriterion = "authority.criterion.result.meets_screening_criterion"
    case authorityCriterionDoesNotMeet = "authority.criterion.result.does_not_meet"
    case authorityCriterionInconclusive = "authority.criterion.result.inconclusive"
    case authorityCriterionNotEvaluated = "authority.criterion.result.not_evaluated"
    case authorityCriterionSeverity = "authority.criterion.severity"
    case authorityCriterionMeasurementProtocol = "authority.criterion.measurement_protocol"
    case authorityCriterionTechnicalBasis = "authority.criterion.technical_basis"
    case authorityCriterionNextStep = "authority.criterion.next_step"
    case authorityCriterionAssessedAgainst = "authority.criterion.assessed_against"
    case functionalRelationshipHeading = "functional.relationship.heading"
    case functionalRelationshipType = "functional.relationship.type"
    case functionalRelationshipDirectedSourceToTarget = "functional.relationship.direction.source_to_target"
    case functionalRelationshipSymmetric = "functional.relationship.direction.symmetric"
    case functionalRelationshipActiveState = "functional.relationship.state.active"
    case functionalRelationshipEndedState = "functional.relationship.state.ended"
    case functionalRelationshipSupersededState = "functional.relationship.state.superseded"
    case functionalRelationshipIncompleteState = "functional.relationship.state.incomplete"
    case functionalRelationshipBlockedState = "functional.relationship.state.blocked"
    case functionalRelationshipMinimumNextRequirement = "functional.relationship.next_step.minimum_requirement"
    case functionalRelationshipDescriptor = "functional.relationship.descriptor"
    case functionalRelationshipBounds = "functional.relationship.bounds"
    case functionalRelationshipSite = "functional.relationship.site"
    case functionalRelationshipCrossSiteState = "functional.relationship.site.cross_site"
    case evidenceVisibilityHeading = "evidence.visibility.heading"
    case evidenceVisibilityAudience = "evidence.visibility.audience"
    case evidenceVisibilityAudienceInternalReview = "evidence.visibility.audience.internal_review"
    case evidenceVisibilityAudienceCustomerReport = "evidence.visibility.audience.customer_report"
    case evidenceVisibilityAudienceExternalCollaborator = "evidence.visibility.audience.external_collaborator"
    case evidenceVisibilitySensitivity = "evidence.visibility.sensitivity"
    case evidenceVisibilitySensitivityRoutine = "evidence.visibility.sensitivity.routine"
    case evidenceVisibilitySensitivityRestricted = "evidence.visibility.sensitivity.restricted"
    case evidenceVisibilitySensitivityHighlyRestricted = "evidence.visibility.sensitivity.highly_restricted"
    case evidenceVisibilityIncluded = "evidence.visibility.state.included"
    case evidenceVisibilityExcluded = "evidence.visibility.state.excluded"
    case evidenceVisibilityOmitted = "evidence.visibility.state.omitted"
    case evidenceVisibilityLimitation = "evidence.visibility.state.limitation"
    case evidenceVisibilityUnknown = "evidence.visibility.state.unknown"
    case evidenceVisibilityPreview = "evidence.visibility.preview"
    case evidenceVisibilityPreviewReady = "evidence.visibility.preview.ready"
    case evidenceVisibilityPreviewStale = "evidence.visibility.preview.stale"
    case evidenceVisibilityManifest = "evidence.visibility.manifest"
    case evidenceVisibilityAttestation = "evidence.visibility.attestation"
    case evidenceVisibilityAttestationPurpose = "evidence.visibility.attestation.purpose"
    case evidenceVisibilityAttestationRecorded = "evidence.visibility.attestation.recorded"
    case evidenceVisibilityAttestationSuperseded = "evidence.visibility.attestation.superseded"
    case evidenceVisibilityAttestationVoid = "evidence.visibility.attestation.void"
    case evidenceVisibilityNextStep = "evidence.visibility.next_step"
    case inspectionReviewHeading = "inspection.review.heading"
    case inspectionReviewState = "inspection.review.state"
    case inspectionReviewDraft = "inspection.review.state.draft"
    case inspectionReviewFieldComplete = "inspection.review.state.field_complete"
    case inspectionReviewReadyForReview = "inspection.review.state.ready_for_review"
    case inspectionReviewChangesRequested = "inspection.review.state.changes_requested"
    case inspectionReviewAccepted = "inspection.review.state.accepted"
    case inspectionReviewFinalized = "inspection.review.state.finalized"
    case inspectionReviewAmended = "inspection.review.state.amended"
    case inspectionReviewSuperseded = "inspection.review.state.superseded"
    case inspectionReviewDisposition = "inspection.review.disposition"
    case inspectionReviewDispositionChangesRequested = "inspection.review.disposition.changes_requested"
    case inspectionReviewDispositionAccepted = "inspection.review.disposition.accepted"
    case inspectionReviewChangeRequest = "inspection.review.change_request"
    case inspectionReviewChangeRequestState = "inspection.review.change_request.state"
    case inspectionReviewChangeRequestOpen = "inspection.review.change_request.state.open"
    case inspectionReviewChangeRequestResolved = "inspection.review.change_request.state.resolved"
    case inspectionReviewChangeRequestWithdrawn = "inspection.review.change_request.state.withdrawn"
    case inspectionReviewChangeRequestSuperseded = "inspection.review.change_request.state.superseded"
    case inspectionReviewChangeRequestResolution = "inspection.review.change_request.resolution"
    case inspectionReviewChangeRequestResolutionFulfilled = "inspection.review.change_request.resolution.fulfilled"
    case inspectionReviewChangeRequestResolutionWithdrawnWithReason = "inspection.review.change_request.resolution.withdrawn_with_reason"
    case inspectionReviewChangeRequestResolutionSuperseded = "inspection.review.change_request.resolution.superseded"
    case inspectionReviewCorrectiveAction = "inspection.review.corrective_action"
    case inspectionReviewCorrectiveActionState = "inspection.review.corrective_action.state"
    case inspectionReviewCorrectiveActionOpen = "inspection.review.corrective_action.state.open"
    case inspectionReviewCorrectiveActionInProgress = "inspection.review.corrective_action.state.in_progress"
    case inspectionReviewCorrectiveActionAwaitingVerification = "inspection.review.corrective_action.state.awaiting_verification"
    case inspectionReviewCorrectiveActionClosed = "inspection.review.corrective_action.state.closed"
    case inspectionReviewCorrectiveActionReopened = "inspection.review.corrective_action.state.reopened"
    case inspectionReviewCorrectiveActionSuperseded = "inspection.review.corrective_action.state.superseded"
    case inspectionReviewNextStep = "inspection.review.next_step"
    case inspectionReviewMinimumNextRequirement = "inspection.review.next_step.minimum_requirement"
    case workPacketHeading = "work.packet.heading"
    case workPacketManifest = "work.packet.manifest"
    case workPacketItem = "work.packet.item"
    case workPacketManifestState = "work.packet.manifest.state"
    case workPacketManifestDraft = "work.packet.manifest.state.draft"
    case workPacketManifestReady = "work.packet.manifest.state.ready"
    case workPacketManifestInvalid = "work.packet.manifest.state.invalid"
    case workPacketManifestReplayed = "work.packet.manifest.state.replayed"
    case workPacketManifestConflicted = "work.packet.manifest.state.conflicted"
    case workPacketManifestSuperseded = "work.packet.manifest.state.superseded"
    case workPacketClaim = "work.packet.claim"
    case workPacketClaimState = "work.packet.claim.state"
    case workPacketClaimUnclaimed = "work.packet.claim.state.unclaimed"
    case workPacketClaimClaimed = "work.packet.claim.state.claimed"
    case workPacketClaimReleased = "work.packet.claim.state.released"
    case workPacketClaimConflicted = "work.packet.claim.state.conflicted"
    case workPacketLease = "work.packet.lease"
    case workPacketLeaseState = "work.packet.lease.state"
    case workPacketLeaseActive = "work.packet.lease.state.active"
    case workPacketLeaseExpiring = "work.packet.lease.state.expiring"
    case workPacketLeaseExpired = "work.packet.lease.state.expired"
    case workPacketLeaseReclaimed = "work.packet.lease.state.reclaimed"
    case workPacketRelease = "work.packet.release"
    case workPacketReleaseState = "work.packet.release.state"
    case workPacketReleaseRecorded = "work.packet.release.state.recorded"
    case workPacketReleaseAvailable = "work.packet.release.state.available"
    case workPacketReleaseSuperseded = "work.packet.release.state.superseded"
    case workPacketHandoff = "work.packet.handoff"
    case workPacketHandoffState = "work.packet.handoff.state"
    case workPacketHandoffPending = "work.packet.handoff.state.pending"
    case workPacketHandoffAccepted = "work.packet.handoff.state.accepted"
    case workPacketHandoffRejected = "work.packet.handoff.state.rejected"
    case workPacketHandoffCompleted = "work.packet.handoff.state.completed"
    case workPacketConflict = "work.packet.conflict"
    case workPacketConflictState = "work.packet.conflict.state"
    case workPacketConflictDetected = "work.packet.conflict.state.detected"
    case workPacketConflictQuarantined = "work.packet.conflict.state.quarantined"
    case workPacketConflictReviewRequired = "work.packet.conflict.state.review_required"
    case workPacketConflictResolved = "work.packet.conflict.state.resolved"
    case workPacketExpiry = "work.packet.expiry"
    case workPacketExpiryState = "work.packet.expiry.state"
    case workPacketExpiryNotExpired = "work.packet.expiry.state.not_expired"
    case workPacketExpiryExpiring = "work.packet.expiry.state.expiring"
    case workPacketExpiryExpired = "work.packet.expiry.state.expired"
    case workPacketReplay = "work.packet.replay"
    case workPacketReplayState = "work.packet.replay.state"
    case workPacketReplayPending = "work.packet.replay.state.pending"
    case workPacketReplayApplied = "work.packet.replay.state.applied"
    case workPacketReplayIdempotent = "work.packet.replay.state.idempotent"
    case workPacketReplayQuarantined = "work.packet.replay.state.quarantined"
    case workPacketNextStep = "work.packet.next_step"
    case workPacketMinimumNextRequirement = "work.packet.next_step.minimum_requirement"

    case fieldDraftScreen = "field.draft.screen"
    case fieldDraftHeading = "field.draft.heading"
    case fieldDraftDurability = "field.draft.durability"
    case fieldDraftDurabilityState = "field.draft.durability.state"
    case fieldDraftNextStep = "field.draft.next_step"
    case fieldDraftMinimumNextRequirement = "field.draft.next_step.minimum_requirement"
    case fieldDraftCheckpoint = "field.draft.checkpoint"
    case fieldDraftCheckpointState = "field.draft.checkpoint.state"
    case fieldDraftAttachment = "field.draft.attachment"
    case fieldDraftAttachmentState = "field.draft.attachment.state"
    case fieldDraftCommitSaga = "field.draft.commit.saga"
    case fieldDraftCommitSagaState = "field.draft.commit.saga.state"
    case fieldDraftRecovery = "field.draft.recovery"
    case fieldDraftRecoveryState = "field.draft.recovery.state"
    case fieldDraftRecoverySafeAction = "field.draft.recovery.safe_action"
    case fieldDraftRecoveryFallback = "field.draft.recovery.fallback"
    case fieldDraftDurabilityUnsavedChanges = "field.draft.durability.state.unsaved_changes"
    case fieldDraftDurabilitySavingOnThisIPhone = "field.draft.durability.state.saving_on_this_iphone"
    case fieldDraftDurabilitySavedOnThisIPhone = "field.draft.durability.state.saved_on_this_iphone"
    case fieldDraftDurabilitySaveBlocked = "field.draft.durability.state.save_blocked"
    case fieldDraftDurabilityCommitting = "field.draft.durability.state.committing"
    case fieldDraftDurabilityConflicted = "field.draft.durability.state.conflicted"
    case fieldDraftDurabilityRecoveryRequired = "field.draft.durability.state.recovery_required"
    case fieldDraftDurabilityCommitted = "field.draft.durability.state.committed"
    case fieldDraftDurabilityDiscarding = "field.draft.durability.state.discarding"
    case fieldDraftDurabilityDiscarded = "field.draft.durability.state.discarded"
    case fieldDraftCheckpointActive = "field.draft.checkpoint.state.active"
    case fieldDraftCheckpointCommitting = "field.draft.checkpoint.state.committing"
    case fieldDraftCheckpointConflicted = "field.draft.checkpoint.state.conflicted"
    case fieldDraftCheckpointRecoveryRequired = "field.draft.checkpoint.state.recovery_required"
    case fieldDraftCheckpointCommitted = "field.draft.checkpoint.state.committed"
    case fieldDraftCheckpointDiscardPending = "field.draft.checkpoint.state.discard_pending"
    case fieldDraftCheckpointDiscarded = "field.draft.checkpoint.state.discarded"
    case fieldDraftAttachmentSelected = "field.draft.attachment.state.selected"
    case fieldDraftAttachmentLoading = "field.draft.attachment.state.loading"
    case fieldDraftAttachmentStagedLocal = "field.draft.attachment.state.staged_local"
    case fieldDraftAttachmentProcessing = "field.draft.attachment.state.processing"
    case fieldDraftAttachmentReady = "field.draft.attachment.state.ready"
    case fieldDraftAttachmentRetryableFailure = "field.draft.attachment.state.retryable_failure"
    case fieldDraftAttachmentBlocked = "field.draft.attachment.state.blocked"
    case fieldDraftAttachmentRemoved = "field.draft.attachment.state.removed"
    case fieldDraftAttachmentPromoted = "field.draft.attachment.state.promoted"
    case fieldDraftAttachmentCapturing = "field.draft.attachment.state.capturing"
    case fieldDraftAttachmentHashing = "field.draft.attachment.state.hashing"
    case fieldDraftAttachmentReadyLocal = "field.draft.attachment.state.ready_local"
    case fieldDraftAttachmentFailedRetryable = "field.draft.attachment.state.failed_retryable"
    case fieldDraftAttachmentFailedFinal = "field.draft.attachment.state.failed_final"
    case fieldDraftAttachmentRemovePending = "field.draft.attachment.state.remove_pending"
    case fieldDraftAttachmentCommitted = "field.draft.attachment.state.committed"
    case fieldDraftAttachmentOrphanQuarantined = "field.draft.attachment.state.orphan_quarantined"
    case fieldDraftSagaPrepared = "field.draft.commit.saga.state.prepared"
    case fieldDraftSagaContentPromotedUnbound = "field.draft.commit.saga.state.content_promoted_unbound"
    case fieldDraftSagaTargetCommitted = "field.draft.commit.saga.state.target_committed"
    case fieldDraftSagaDraftRetirePending = "field.draft.commit.saga.state.draft_retire_pending"
    case fieldDraftSagaDraftRetired = "field.draft.commit.saga.state.draft_retired"
    case fieldDraftSagaConflicted = "field.draft.commit.saga.state.conflicted"
    case fieldDraftSagaRecoveryRequired = "field.draft.commit.saga.state.recovery_required"
    case fieldDraftRecoveryResumeAvailable = "field.draft.recovery.state.resume_available"
    case fieldDraftRecoveryConflict = "field.draft.recovery.state.conflict"
    case fieldDraftRecoveryMissingMedia = "field.draft.recovery.state.missing_media"
    case fieldDraftRecoveryLowStorage = "field.draft.recovery.state.low_storage"
    case fieldDraftRecoveryProtectedData = "field.draft.recovery.state.protected_data"
    case fieldDraftRecoveryUnsupportedCodec = "field.draft.recovery.state.unsupported_codec"
    case fieldDraftRecoveryPartialStage = "field.draft.recovery.state.partial_stage"
    case fieldDraftRecoveryStaleTarget = "field.draft.recovery.state.stale_target"
    case fieldDraftRecoveryRecoveryRequired = "field.draft.recovery.state.recovery_required"

    case measurementIntegrityHeading = "measurement.integrity.heading"
    case measurementIntegrityInstrument = "measurement.integrity.instrument"
    case measurementIntegrityInstrumentKind = "measurement.integrity.instrument.kind"
    case measurementIntegrityInstrumentKindMeasuring = "measurement.integrity.instrument.kind.measuring"
    case measurementIntegrityInstrumentKindReference = "measurement.integrity.instrument.kind.reference"
    case measurementIntegrityInstrumentKindOther = "measurement.integrity.instrument.kind.other"
    case measurementIntegrityInstrumentLifecycle = "measurement.integrity.instrument.lifecycle"
    case measurementIntegrityInstrumentLifecycleActive = "measurement.integrity.instrument.lifecycle.active"
    case measurementIntegrityInstrumentLifecycleOutOfService = "measurement.integrity.instrument.lifecycle.out_of_service"
    case measurementIntegrityInstrumentLifecycleRetired = "measurement.integrity.instrument.lifecycle.retired"
    case measurementIntegrityCalibration = "measurement.integrity.calibration"
    case measurementIntegrityCalibrationStatus = "measurement.integrity.calibration.status"
    case measurementIntegrityCalibrationNotRequired = "measurement.integrity.calibration.status.not_required"
    case measurementIntegrityCalibrationCurrent = "measurement.integrity.calibration.status.current"
    case measurementIntegrityCalibrationExpired = "measurement.integrity.calibration.status.expired"
    case measurementIntegrityCalibrationUnknown = "measurement.integrity.calibration.status.unknown"
    case measurementIntegrityCalibrationOutOfService = "measurement.integrity.calibration.status.out_of_service"
    case measurementIntegrityCalibrationBasis = "measurement.integrity.calibration.basis"
    case measurementIntegrityCalibrationBasisDeclared = "measurement.integrity.calibration.basis.declared_not_required"
    case measurementIntegrityCalibrationBasisEvidence = "measurement.integrity.calibration.basis.referenced_evidence"
    case measurementIntegrityCalibrationBasisLocal = "measurement.integrity.calibration.basis.locally_recorded"
    case measurementIntegrityCalibrationBasisUnknown = "measurement.integrity.calibration.basis.unknown"
    case measurementIntegrityCapture = "measurement.integrity.capture"
    case measurementIntegrityCaptureValue = "measurement.integrity.capture.value"
    case measurementIntegrityCaptureUnit = "measurement.integrity.capture.unit"
    case measurementIntegrityCaptureSource = "measurement.integrity.capture.source"
    case measurementIntegrityCaptureSourceManual = "measurement.integrity.capture.source.manual_entry"
    case measurementIntegrityCaptureSourceLocalObservation = "measurement.integrity.capture.source.local_observation"
    case measurementIntegritySeries = "measurement.integrity.series"
    case measurementIntegritySeriesState = "measurement.integrity.series.state"
    case measurementIntegritySeriesOpen = "measurement.integrity.series.state.open"
    case measurementIntegritySeriesFinalized = "measurement.integrity.series.state.finalized"
    case measurementIntegrityProtocol = "measurement.integrity.protocol"
    case measurementIntegrityQuality = "measurement.integrity.quality"
    case measurementIntegrityQualityResult = "measurement.integrity.quality.result"
    case measurementIntegrityQualityClear = "measurement.integrity.quality.result.clear"
    case measurementIntegrityQualityReviewRequired = "measurement.integrity.quality.result.review_required"
    case measurementIntegrityQualityOverridden = "measurement.integrity.quality.result.overridden"
    case measurementIntegrityQualityReason = "measurement.integrity.quality.reason"
    case measurementIntegrityQualityReasonDeclaredChecksClear = "measurement.integrity.quality.reason.declared_checks_clear"
    case measurementIntegrityQualityReasonCalibrationNotRequired = "measurement.integrity.quality.reason.calibration_not_required"
    case measurementIntegrityQualityReasonCalibrationExpired = "measurement.integrity.quality.reason.calibration_expired"
    case measurementIntegrityQualityReasonCalibrationUnknown = "measurement.integrity.quality.reason.calibration_unknown"
    case measurementIntegrityQualityReasonInstrumentOutOfService = "measurement.integrity.quality.reason.instrument_out_of_service"
    case measurementIntegrityQualityReasonMissingUncertainty = "measurement.integrity.quality.reason.missing_uncertainty"
    case measurementIntegrityQualityReasonUncertaintyCrossesBoundary = "measurement.integrity.quality.reason.uncertainty_crosses_boundary"
    case measurementIntegrityQualityReasonIncompleteSampleSet = "measurement.integrity.quality.reason.incomplete_sample_set"
    case measurementIntegrityQualityReasonDuplicateSample = "measurement.integrity.quality.reason.duplicate_sample"
    case measurementIntegrityQualityReasonRetainedOutlier = "measurement.integrity.quality.reason.retained_outlier"
    case measurementIntegrityQualityReasonObservationLimitation = "measurement.integrity.quality.reason.observation_limitation"
    case measurementIntegrityQualityReasonHumanOverride = "measurement.integrity.quality.reason.human_override"
    case measurementIntegrityNextStep = "measurement.integrity.next_step"

    case privacyTransformHeading = "privacy.transform.heading"
    case privacyTransformRedactionDeclaration = "privacy.transform.redaction.declaration"
    case privacyTransformDerivative = "privacy.transform.derivative"
    case privacyTransformDerivativeOnly = "privacy.transform.derivative.only"
    case privacyTransformReview = "privacy.transform.review"
    case privacyTransformReviewApproved = "privacy.transform.review.approved"
    case privacyTransformReviewRejected = "privacy.transform.review.rejected"
    case privacyTransformFreshness = "privacy.transform.freshness"
    case privacyTransformFreshnessCurrent = "privacy.transform.freshness.current"
    case privacyTransformProjection = "privacy.transform.projection"
    case privacyTransformProjectionAllowed = "privacy.transform.projection.allowed"
    case privacyTransformProjectionDenied = "privacy.transform.projection.denied"
    case privacyTransformDenialMissingReview = "privacy.transform.projection.denial.missing_review"
    case privacyTransformDenialRejected = "privacy.transform.projection.denial.rejected"
    case privacyTransformDenialStale = "privacy.transform.projection.denial.stale"
    case privacyTransformDenialWrongAudience = "privacy.transform.projection.denial.wrong_audience"
    case privacyTransformDenialWrongPolicy = "privacy.transform.projection.denial.wrong_policy"
    case privacyTransformDenialSourceChanged = "privacy.transform.projection.denial.source_changed"
    case privacyTransformDenialDigestMismatch = "privacy.transform.projection.denial.digest_mismatch"
    case privacyTransformDenialMetadataNotSanitized = "privacy.transform.projection.denial.metadata_not_sanitized"
    case privacyTransformOriginalAccessSeparate = "privacy.transform.original.access.separate"
    case privacyTransformNextStep = "privacy.transform.next_step"

    case clientCapabilityHeading = "client.capability.heading"
    case clientCapabilityAdmission = "client.capability.admission"
    case clientCapabilityAdmissionReadWrite = "client.capability.admission.read_write"
    case clientCapabilityAdmissionReadOnly = "client.capability.admission.read_only"
    case clientCapabilityAdmissionMigrationRequired = "client.capability.admission.migration_required"
    case clientCapabilityAdmissionQuarantine = "client.capability.admission.quarantine"
    case clientCapabilityAdmissionReject = "client.capability.admission.reject"
    case clientCapabilityReason = "client.capability.reason"
    case clientCapabilityReasonExactMatch = "client.capability.reason.exact_match"
    case clientCapabilityReasonReadOnlyCompatibility = "client.capability.reason.read_only_compatibility"
    case clientCapabilityReasonMigrationAvailable = "client.capability.reason.migration_available"
    case clientCapabilityReasonUnsupportedRequiredRange = "client.capability.reason.unsupported_required_range"
    case clientCapabilityReasonUnknownCapability = "client.capability.reason.unknown_capability"
    case clientCapabilityReasonPackageWithdrawn = "client.capability.reason.package_withdrawn"
    case clientCapabilityReasonPackageQuarantined = "client.capability.reason.package_quarantined"
    case clientCapabilityReasonPackageSuperseded = "client.capability.reason.package_superseded"
    case clientCapabilityReasonDigestMismatch = "client.capability.reason.digest_mismatch"
    case clientCapabilityReasonStalePolicy = "client.capability.reason.stale_policy"
    case clientCapabilityReasonOperationBlocked = "client.capability.reason.operation_blocked"
    case packageLifecycleHeading = "package.lifecycle.heading"
    case packageLifecycleState = "package.lifecycle.state"
    case packageLifecycleStateActive = "package.lifecycle.state.active"
    case packageLifecycleStateDeprecated = "package.lifecycle.state.deprecated"
    case packageLifecycleStateWithdrawn = "package.lifecycle.state.withdrawn"
    case packageLifecycleStateQuarantined = "package.lifecycle.state.quarantined"
    case packageLifecycleStateSuperseded = "package.lifecycle.state.superseded"
    case packageLifecycleOperation = "package.lifecycle.operation"
    case packageLifecycleOperationStart = "package.lifecycle.operation.start"
    case packageLifecycleOperationResume = "package.lifecycle.operation.resume"
    case packageLifecycleOperationFinalize = "package.lifecycle.operation.finalize"
    case packageLifecycleOperationAmend = "package.lifecycle.operation.amend"
    case packageLifecycleOperationView = "package.lifecycle.operation.view"
    case packageLifecycleOperationExport = "package.lifecycle.operation.export"
    case packageLifecycleOperationRestore = "package.lifecycle.operation.restore"
    case packageLifecycleOperationReplay = "package.lifecycle.operation.replay"
    case packageLifecycleOperationUpgradeDraft = "package.lifecycle.operation.upgrade_draft"
    case packageLifecycleHistoricExport = "package.lifecycle.historic.export"
    case packageLifecycleWithdrawal = "package.lifecycle.withdrawal"
    case packageLifecycleBlocked = "package.lifecycle.blocked"
    case clientCapabilityNextStep = "client.capability.next_step"

    case fieldReferenceHeading = "field.reference.heading"
    case fieldReferenceProvenance = "field.reference.provenance"
    case fieldReferencePack = "field.reference.pack"
    case fieldReferenceKind = "field.reference.kind"
    case fieldReferenceKindSOP = "field.reference.kind.sop"
    case fieldReferenceKindManual = "field.reference.kind.manual"
    case fieldReferenceKindDrawing = "field.reference.kind.drawing"
    case fieldReferenceKindSpecification = "field.reference.kind.specification"
    case fieldReferenceSemanticVersion = "field.reference.semantic-version"
    case fieldReferenceRelease = "field.reference.release"
    case fieldReferenceReleaseActive = "field.reference.release.active"
    case fieldReferenceReleaseRevoked = "field.reference.release.revoked"
    case fieldReferenceBinding = "field.reference.binding"
    case fieldReferenceSubject = "field.reference.subject"
    case fieldReferenceSubjectWorkPacket = "field.reference.subject.work-packet"
    case fieldReferenceSubjectRoundSession = "field.reference.subject.round-session"
    case fieldReferenceSubjectActive = "field.reference.subject.active"
    case fieldReferenceSubjectFinalized = "field.reference.subject.finalized"
    case fieldReferenceProvenanceKind = "field.reference.provenance.kind"
    case fieldReferenceProvenanceLicensed = "field.reference.provenance.licensed"
    case fieldReferenceProvenanceSynthetic = "field.reference.provenance.synthetic"
    case fieldReferenceLicenseScope = "field.reference.provenance.license-scope"
    case fieldReferenceLicenseLocalUseOnly = "field.reference.provenance.license-scope.local-use-only"
    case fieldReferenceLicenseCitationAllowed = "field.reference.provenance.license-scope.citation-allowed"
    case fieldReferenceLicenseCitationAndExportAllowed = "field.reference.provenance.license-scope.citation-and-export-allowed"
    case fieldReferenceLicenseRestricted = "field.reference.provenance.license-scope.restricted"
    case fieldReferenceAvailability = "field.reference.availability"
    case fieldReferenceAvailabilityReadyOffline = "field.reference.availability.ready-offline"
    case fieldReferenceAvailabilityMissingBytes = "field.reference.availability.missing-bytes"
    case fieldReferenceAvailabilityExpired = "field.reference.availability.expired"
    case fieldReferenceAvailabilityRevoked = "field.reference.availability.revoked"
    case fieldReferenceAvailabilitySuperseded = "field.reference.availability.superseded"
    case fieldReferenceAvailabilityStaleBinding = "field.reference.availability.stale-binding"
    case fieldReferenceAvailabilityProtectedDataUnavailable = "field.reference.availability.protected-data-unavailable"
    case fieldReferenceAvailabilityUnavailable = "field.reference.availability.unavailable"
    case fieldReferenceRequiredContent = "field.reference.required-content"
    case fieldReferenceMissingContent = "field.reference.missing-content"
    case fieldReferenceNextStep = "field.reference.next-step"

    case accessibleDocumentScreen = "accessible.document.screen"
    case accessibleDocumentHeading = "accessible.document.heading"
    case accessibleDocumentNode = "accessible.document.node"
    case accessibleDocumentRole = "accessible.document.role"
    case accessibleDocumentRoleDocument = "accessible.document.role.document"
    case accessibleDocumentRoleSection = "accessible.document.role.section"
    case accessibleDocumentRoleHeading = "accessible.document.role.heading"
    case accessibleDocumentRoleParagraph = "accessible.document.role.paragraph"
    case accessibleDocumentRoleList = "accessible.document.role.list"
    case accessibleDocumentRoleListItem = "accessible.document.role.list-item"
    case accessibleDocumentRoleTable = "accessible.document.role.table"
    case accessibleDocumentRoleTableRow = "accessible.document.role.table-row"
    case accessibleDocumentRoleTableHeader = "accessible.document.role.table-header"
    case accessibleDocumentRoleTableCell = "accessible.document.role.table-cell"
    case accessibleDocumentRoleFigure = "accessible.document.role.figure"
    case accessibleDocumentRoleEvidenceLink = "accessible.document.role.evidence-link"
    case accessibleDocumentRoleNote = "accessible.document.role.note"
    case accessibleDocumentAlternateText = "accessible.document.alternate-text"
    case accessibleDocumentAlternateTextProvenance = "accessible.document.alternate-text.provenance"
    case accessibleDocumentAlternateTextAuthoredForSource = "accessible.document.alternate-text.provenance.authored-for-source"
    case accessibleDocumentAlternateTextSourceCaption = "accessible.document.alternate-text.provenance.source-caption"
    case accessibleDocumentAlternateTextNotProvided = "accessible.document.alternate-text.provenance.not-provided"
    case accessibleDocumentDecorativeFigure = "accessible.document.figure.decorative"
    case accessibleDocumentDescribedFigure = "accessible.document.figure.described"
    case accessibleDocumentAssessment = "accessible.document.assessment"
    case accessibleDocumentAssessmentInternalPass = "accessible.document.assessment.internal-pass"
    case accessibleDocumentAssessmentInternalFail = "accessible.document.assessment.internal-fail"
    case accessibleDocumentAssessmentIncomplete = "accessible.document.assessment.incomplete"
    case accessibleDocumentAssessmentExternallyProved = "accessible.document.assessment.external-proof-recorded"
    case accessibleDocumentEvidence = "accessible.document.evidence"
    case accessibleDocumentEvidenceLimited = "accessible.document.evidence.limited"
    case accessibleDocumentClaimBoundary = "accessible.document.claim-boundary"
    case accessibleDocumentNextStep = "accessible.document.next-step"

    case poseHeading = "pose.heading"
    case poseAxis = "pose.axis"
    case poseCurrent = "pose.current"
    case poseHistory = "pose.history"
    case poseReferenceFrame = "pose.reference_frame"
    case poseReferenceTrue = "pose.reference.true"
    case poseReferenceMagnetic = "pose.reference.magnetic"
    case poseReferencePlanRelative = "pose.reference.plan_relative"
    case poseReferenceUnknown = "pose.reference.unknown"
    case poseObservation = "pose.observation"
    case poseObserved = "pose.observation.observed"
    case poseNotObserved = "pose.observation.not_observed"
    case poseManualFallback = "pose.observation.manual_fallback"
    case poseUncertainty = "pose.uncertainty"
    case poseUncertaintyKnown = "pose.uncertainty.known"
    case poseUncertaintyUnknown = "pose.uncertainty.unknown"
    case poseNotObservedReason = "pose.not_observed.reason"
    case poseReasonNotYetObserved = "pose.not_observed.reason.not_yet_observed"
    case poseReasonPhysicalMove = "pose.not_observed.reason.physical_move_reobservation"
    case poseReasonPlanFrameLost = "pose.not_observed.reason.plan_frame_lost_reobservation"
    case poseReasonObscured = "pose.not_observed.reason.obscured_or_unsafe"
    case poseReasonSourceUnavailable = "pose.not_observed.reason.source_unavailable"
    case poseReasonUserDeclined = "pose.not_observed.reason.user_declined"
    case poseCurrentTip = "pose.current_tip"
    case poseHistoryFrozen = "pose.history.frozen"
    case poseRebasePreview = "pose.rebase.preview"
    case posePreviewNotApplied = "pose.rebase.preview.not_applied"
    case poseReviewRequired = "pose.review_required"
    case poseAzimuth = "pose.azimuth"
    case poseElevation = "pose.elevation"
    case poseHorizontalUncertainty = "pose.horizontal_uncertainty"
    case poseVerticalUncertainty = "pose.vertical_uncertainty"
    case poseRecordedSource = "pose.recorded_source"
    case poseClaimBoundary = "pose.claim_boundary"
    case poseNextStep = "pose.next_step"
    case poseMissing = "pose.missing"

    case lightingSystemHeading = "lighting.system.heading"
    case lightingTopology = "lighting.system.topology"
    case lightingZones = "lighting.system.zones"
    case lightingControlGroups = "lighting.system.control_groups"
    case lightingLuminaires = "lighting.system.luminaires"
    case lightingObservationHeading = "lighting.observation.heading"
    case lightingObservationRecorded = "lighting.observation.recorded"
    case lightingIssueRecorded = "lighting.issue.recorded"
    case lightingIssueOpen = "lighting.issue.open"
    case lightingIssueResolved = "lighting.issue.resolved"
    case lightingIssueSuperseded = "lighting.issue.superseded"
    case lightingMeasurementHeading = "lighting.measurement.heading"
    case lightingIlluminance = "lighting.measurement.illuminance"
    case lightingCalibration = "lighting.measurement.calibration"
    case lightingClaimObserved = "lighting.claim.observed"
    case lightingClaimMeasured = "lighting.claim.measured"
    case lightingClaimDerived = "lighting.claim.derived"
    case lightingClaimCriterion = "lighting.claim.criterion"
    case lightingClaimExternal = "lighting.claim.external_reference"
    case lightingClaimUnavailable = "lighting.claim.unavailable"
    case lightingSafetyStop = "lighting.safety.stop"
    case lightingSafetyNextStep = "lighting.safety.next_step"
    case lightingClaimBoundary = "lighting.claim.boundary"
    case lightingHistoryFrozen = "lighting.history.frozen"
    case lightingManualOffline = "lighting.manual_offline"

    case operationalContactDirections = "operational_contact.action.directions"
    case operationalContactCall = "operational_contact.action.call"
    case operationalContactText = "operational_contact.action.text"
    case operationalContactEmail = "operational_contact.action.email"
    case operationalContactOpensSystemApp = "operational_contact.handoff.opens_system_app"
    case operationalContactHandedOff = "operational_contact.handoff.handed_off"
    case operationalContactTargetMissing = "operational_contact.handoff.target_missing"
    case operationalContactTargetStale = "operational_contact.handoff.target_stale"
    case operationalContactTargetInvalid = "operational_contact.handoff.target_invalid"
    case operationalContactSystemUnavailable = "operational_contact.handoff.system_unavailable"
    case operationalContactSystemRejected = "operational_contact.handoff.system_rejected"
    case operationalContactCancelled = "operational_contact.handoff.cancelled"
    case operationalContactClaimBoundary = "operational_contact.handoff.claim_boundary"

    static var functionalRelationshipDirected: Self { .functionalRelationshipDirectedSourceToTarget }
    static var functionalRelationshipActive: Self { .functionalRelationshipActiveState }
    static var functionalRelationshipEnded: Self { .functionalRelationshipEndedState }
    static var functionalRelationshipSuperseded: Self { .functionalRelationshipSupersededState }
    static var functionalRelationshipIncomplete: Self { .functionalRelationshipIncompleteState }
    static var functionalRelationshipBlocked: Self { .functionalRelationshipBlockedState }
    static var functionalRelationshipMinimumNextStepRequirement: Self {
        .functionalRelationshipMinimumNextRequirement
    }
    static var functionalRelationshipCardinalityBounds: Self { .functionalRelationshipBounds }
    static var functionalRelationshipSitePolicy: Self { .functionalRelationshipSite }
    static var functionalRelationshipCrossSite: Self { .functionalRelationshipCrossSiteState }

    static var evidenceAssuranceHeading: Self { .evidenceVisibilityHeading }
    static var evidenceAssuranceAudience: Self { .evidenceVisibilityAudience }
    static var evidenceAssuranceSensitivity: Self { .evidenceVisibilitySensitivity }
    static var evidenceAssuranceIncluded: Self { .evidenceVisibilityIncluded }
    static var evidenceAssuranceExcluded: Self { .evidenceVisibilityExcluded }
    static var evidenceAssuranceOmitted: Self { .evidenceVisibilityOmitted }
    static var evidenceAssuranceLimitation: Self { .evidenceVisibilityLimitation }
    static var evidenceAssuranceUnknown: Self { .evidenceVisibilityUnknown }
    static var evidenceAssurancePreview: Self { .evidenceVisibilityPreview }
    static var evidenceAssurancePreviewReady: Self { .evidenceVisibilityPreviewReady }
    static var evidenceAssurancePreviewStale: Self { .evidenceVisibilityPreviewStale }
    static var evidenceAssuranceManifest: Self { .evidenceVisibilityManifest }
    static var evidenceAssuranceAttestation: Self { .evidenceVisibilityAttestation }
    static var evidenceAssuranceAttestationPurpose: Self { .evidenceVisibilityAttestationPurpose }
    static var evidenceAssuranceAttestationRecorded: Self { .evidenceVisibilityAttestationRecorded }
    static var evidenceAssuranceAttestationSuperseded: Self { .evidenceVisibilityAttestationSuperseded }
    static var evidenceAssuranceAttestationVoid: Self { .evidenceVisibilityAttestationVoid }
    static var evidenceAssuranceNextStep: Self { .evidenceVisibilityNextStep }

    static var reviewHeading: Self { .inspectionReviewHeading }
    static var reviewState: Self { .inspectionReviewState }
    static var reviewDraft: Self { .inspectionReviewDraft }
    static var reviewFieldComplete: Self { .inspectionReviewFieldComplete }
    static var reviewReadyForReview: Self { .inspectionReviewReadyForReview }
    static var reviewChangesRequested: Self { .inspectionReviewChangesRequested }
    static var reviewAccepted: Self { .inspectionReviewAccepted }
    static var reviewFinalized: Self { .inspectionReviewFinalized }
    static var reviewAmended: Self { .inspectionReviewAmended }
    static var reviewSuperseded: Self { .inspectionReviewSuperseded }
    static var changeRequestHeading: Self { .inspectionReviewChangeRequest }
    static var correctiveActionHeading: Self { .inspectionReviewCorrectiveAction }
    static var reviewNextStep: Self { .inspectionReviewNextStep }

    static var packetHeading: Self { .workPacketHeading }
    static var packetManifest: Self { .workPacketManifest }
    static var packetItem: Self { .workPacketItem }
    static var packetClaim: Self { .workPacketClaim }
    static var packetLease: Self { .workPacketLease }
    static var packetRelease: Self { .workPacketRelease }
    static var packetHandoff: Self { .workPacketHandoff }
    static var packetConflict: Self { .workPacketConflict }
    static var packetExpiry: Self { .workPacketExpiry }
    static var packetReplay: Self { .workPacketReplay }
    static var packetNextStep: Self { .workPacketNextStep }

    static var fieldDraftHeadingKey: Self { .fieldDraftHeading }
    static var fieldDraftDurabilityKey: Self { .fieldDraftDurability }
    static var fieldDraftNextStepKey: Self { .fieldDraftNextStep }
}

// MARK: - V23 P04 C17 exterior-lighting day inventory

enum C17LightingDayLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case title = "lighting.day_inventory.title"
    case daylightObservation = "lighting.day_inventory.daylight_observation"
    case daylightCaution = "lighting.day_inventory.daylight_caution"
    case safetyStop = "lighting.day_inventory.safety_stop"
    case safetyStopDetail = "lighting.day_inventory.safety_stop_detail"
    case unknown = "lighting.day_inventory.state.unknown"
    case notObserved = "lighting.day_inventory.state.not_observed"
    case notApplicable = "lighting.day_inventory.state.not_applicable"
    case offlineReady = "lighting.day_inventory.offline.ready"
    case offlineBlocked = "lighting.day_inventory.offline.blocked"
    case nightFollowup = "lighting.day_inventory.night_followup"
    case claimBoundary = "lighting.day_inventory.claim_boundary"

    var englishDefaultValue: String {
        switch self {
        case .title: return "Day lighting inventory"
        case .daylightObservation: return "Observed energized during daylight"
        case .daylightCaution: return "This daylight observation does not determine schedule, control operation, failure, or night performance."
        case .safetyStop: return "Stop here"
        case .safetyStopDetail: return "Do not climb, open, touch, probe, repair, or enter traffic exposure. Follow the recorded authorized procedure."
        case .unknown: return "Unknown"
        case .notObserved: return "Not observed"
        case .notApplicable: return "Not applicable"
        case .offlineReady: return "Required local material is available for this visit."
        case .offlineBlocked: return "Required local material is unavailable or out of date. Do not start until readiness is rebuilt."
        case .nightFollowup: return "Linked night follow-up"
        case .claimBoundary: return "This inventory records visible conditions only. It is not photometry, an electrical diagnosis, an adequacy or commissioning determination, or proof of night performance."
        }
    }
}

enum C17LightingDayLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocales = ["en"]
    static let pseudoLocales = ["en-XA", "ar-XB"]
    static let runtimeDownloadsAllowed = false
    static let uiAdoptionClaimed = false
    static let requiresAcceptedS10_6Reconciliation = true

    static func validate() throws {
        let keys = C17LightingDayLocalizationKeyV1.allCases.map(\.rawValue)
        guard keys.count == Set(keys).count,
              keys.allSatisfy({ !$0.isEmpty }),
              sourceLocale == "en",
              shippingLocales == ["en"],
              pseudoLocales == ["en-XA", "ar-XB"],
              !runtimeDownloadsAllowed,
              !uiAdoptionClaimed,
              requiresAcceptedS10_6Reconciliation else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

extension BundledLocalizationCatalogV1 {
    static func c17LightingDayEnglish(_ key: C17LightingDayLocalizationKeyV1) -> String {
        key.englishDefaultValue
    }

    static func c17LightingDayLocalized(
        _ key: C17LightingDayLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: locale,
            comment: "C17 cautious day-lighting inventory copy; no photometry, diagnosis, adequacy, commissioning, safety-clearance, or night-pass claim."
        )
    }

    static func c17LightingDayRegistry() throws -> LocalizationKeyRegistryV1 {
        try C17LightingDayLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = try C17LightingDayLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C17 cautious day-lighting inventory copy; all unknown states remain explicit and no shipping UI adoption is claimed."),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - V23 P04 C18 exterior-lighting night workflow

enum C18LightingNightLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case title = "lighting.night_workflow.title"
    case expectedState = "lighting.night_workflow.expected_state"
    case observedState = "lighting.night_workflow.observed_state"
    case unknown = "lighting.night_workflow.state.unknown"
    case inconclusive = "lighting.night_workflow.state.inconclusive"
    case issueOpen = "lighting.night_workflow.issue.open"
    case issueReopened = "lighting.night_workflow.issue.reopened"
    case issueResolved = "lighting.night_workflow.issue.resolved"
    case groupRetainsChildren = "lighting.night_workflow.group.retains_children"
    case offlineReady = "lighting.night_workflow.offline.ready"
    case offlineBlocked = "lighting.night_workflow.offline.blocked"
    case claimBoundary = "lighting.night_workflow.claim_boundary"

    var englishDefaultValue: String {
        switch self {
        case .title: return "Night lighting follow-up"
        case .expectedState: return "Expected control state"
        case .observedState: return "Observed state"
        case .unknown: return "Unknown"
        case .inconclusive: return "Inconclusive"
        case .issueOpen: return "Open issue"
        case .issueReopened: return "Issue reopened"
        case .issueResolved: return "Resolved for recorded scope"
        case .groupRetainsChildren: return "Grouped issues keep their individual history and closure requirements."
        case .offlineReady: return "Required local material is available for this night visit."
        case .offlineBlocked: return "Required local material is unavailable or out of date. Rebuild readiness before starting."
        case .claimBoundary: return "This report records field observations and attributed measurements. It is not an app-originated safety, compliance, code, ADA, IES, electrical diagnosis, adequacy, or commissioning determination."
        }
    }
}

enum C18LightingNightLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocales = ["en"]
    static let pseudoLocales = ["en-XA", "ar-XB"]
    static let runtimeDownloadsAllowed = false
    static let uiAdoptionClaimed = false
    static let requiresAcceptedS10_6Reconciliation = true

    static func validate() throws {
        let keys = C18LightingNightLocalizationKeyV1.allCases.map(\.rawValue)
        guard keys.count == Set(keys).count, keys.allSatisfy({ !$0.isEmpty }),
              sourceLocale == "en", shippingLocales == ["en"],
              pseudoLocales == ["en-XA", "ar-XB"], !runtimeDownloadsAllowed,
              !uiAdoptionClaimed, requiresAcceptedS10_6Reconciliation else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

extension BundledLocalizationCatalogV1 {
    static func c18LightingNightEnglish(_ key: C18LightingNightLocalizationKeyV1) -> String {
        key.englishDefaultValue
    }

    static func c18LightingNightLocalized(
        _ key: C18LightingNightLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: locale,
            comment: "C18 cautious night-lighting copy; unknown, inconclusive, reopen, and child closure states remain explicit."
        )
    }

    static func c18LightingNightRegistry() throws -> LocalizationKeyRegistryV1 {
        try C18LightingNightLocalizationPolicyV1.validate()
        let base = try c17LightingDayRegistry()
        let additions = try C18LightingNightLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue), meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C18 cautious night-workflow copy; no safety, compliance, code, diagnosis, adequacy, or commissioning claim."),
                englishDefaultValue: key.englishDefaultValue, arguments: [],
                requiredEnglishPluralCategories: [], state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

enum LocalizationCatalogPublicationBoundaryV1: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
    case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
}

struct LocalizationCatalogPublicationReceiptV1: Codable, Equatable, Sendable {
    let release: LocalizationCatalogReleaseV1
    let semanticRegistrySHA256: String
    let legacyBaselineSHA256: String
    let packageBindingSHA256s: [String]
    let persistentWriteOccurred: Bool
}

enum LocalizationCatalogPublicationV1: Equatable, Sendable {
    case zero
    case complete(
        registry: LocalizationKeyRegistryV1,
        accessibility: SemanticAccessibilityIDRegistryV1,
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        packageBindings: [PackageLocalizationReleaseBindingV1],
        receipt: LocalizationCatalogPublicationReceiptV1
    )
}

enum BundledLocalizationCatalogV1 {
    typealias Interruption = @Sendable (LocalizationCatalogPublicationBoundaryV1) throws -> Void

    static let runtimeLanguage = "en"
    static let appStorePrimaryMetadataLocale = "en-US"
    static let runtimeDownloadsAllowed = false

    /// Dynamic registry keys cannot use the compile-time `String(localized:)`
    /// overload. Resolve the caller's locale explicitly and retain the
    /// registry's English value as the deterministic fallback.
    static func localizedRegistryText(
        key: String,
        defaultValue: String,
        bundle: Bundle,
        locale: Locale,
        comment: String
    ) -> String {
        let preferredLocalizations = Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: [locale.identifier]
        )
        let candidates = preferredLocalizations + [
            bundle.developmentLocalization,
            runtimeLanguage,
        ].compactMap { $0 }

        var visited: Set<String> = []
        for candidate in candidates {
            guard visited.insert(candidate).inserted else { continue }
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path) else { continue }
            return NSLocalizedString(
                key,
                tableName: nil,
                bundle: localizedBundle,
                value: defaultValue,
                comment: comment
            )
        }

        return defaultValue
    }

    static func registry() throws -> LocalizationKeyRegistryV1 {
        try LocalizationKeyRegistryV1(definitions: [
            try definition(.commonDone, "common.action.done", "Done", "Completes and closes the current task."),
            try definition(.feedbackBodyTemplate, "feedback.mail.body.template", "App version: %@ (%@)\nDevice: %@\nOS: iOS %@\n\nFeedback:\n", "Editable support-email body. Arguments are app version, build, device model, and OS version."),
            try definition(.feedbackSubject, "feedback.mail.subject", "App feedback", "Subject of the support email."),
            try definition(.mailAttachmentCount, "feedback.mail.attachment.count", "Diagnostic attachments: %lld", "Number of diagnostic files attached to the support email.", arguments: [.init(name: "count", shape: .integerPlural)], plurals: ["one", "other"]),
            try definition(.mailComposerTitle, "feedback.mail.composer.title", "Feedback composer", "Heading of the deterministic feedback composer used by UI tests."),
            try definition(.mailMessageHeading, "feedback.mail.message.heading", "Editable message", "Heading above the editable feedback message."),
            try definition(.mailMessageLabel, "feedback.mail.message.label", "Feedback message", "Accessibility label for the editable feedback message."),
            try definition(.mailRecipient, "feedback.mail.recipient", "To: %@", "Support-email recipient summary. Argument is the recipient list."),
            try definition(.packageRequiredViews, "package.guidance.required_views", "Capture the required views.", "Shipping illuminated-sign package guidance for required evidence views."),
            try definition(.packageVisibleConditionsOnly, "package.guidance.visible_conditions_only", "Record only conditions visible in the evidence.", "Shipping illuminated-sign package limitation guidance."),
            try definition(.packageAuthorizedPosition, "package.guidance.authorized_position", "Stand in an authorized position before taking a photo.", "Shipping illuminated-sign package safety guidance."),
        ])
    }

    /// C38's additive key surface.  The legacy `registry()` remains frozen so
    /// S8.4 mail callers retain their exact V1 key/ID contract.
    static func accountabilityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry()
        let additions = [
            try definition(
                .accountabilityHeading, "report.accountability.heading", "Accountability",
                "Heading for the localized accountability projection in a report."
            ),
            try definition(
                .accountabilityParty, "report.accountability.party", "Party",
                "Localized label for a service party in the accountability projection."
            ),
            try definition(
                .accountabilityRole, "report.accountability.role", "Site role",
                "Localized label for a historical site role event."
            ),
            try definition(
                .accountabilityActor, "report.accountability.actor", "Responsible actor",
                "Localized label for a locally captured responsible actor."
            ),
            try definition(
                .accountabilityQualification, "report.accountability.qualification", "Declared qualification",
                "Localized label for a declared qualification snapshot."
            ),
            try definition(
                .accountabilitySignoff, "report.accountability.signoff", "Local response",
                "Localized label for a local signoff assertion or disposition."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    /// C39's additive key surface.  The C16 and C38 registries remain
    /// available as frozen compatibility projections; this registry is the
    /// first one that exposes semantic kind, product, lifecycle, and subject
    /// scope labels.
    static func assetSemanticRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try accountabilityRegistry()
        let additions = [
            try definition(
                .assetSemanticIlluminatedSignName, "asset.semantic.sign.illuminated.name", "Illuminated sign",
                "Localized name for the bundled illuminated-sign semantic kind."
            ),
            try definition(
                .assetSemanticIlluminatedSignDescription, "asset.semantic.sign.illuminated.description",
                "Illuminated sign semantic kind",
                "Localized description for the bundled illuminated-sign semantic kind."
            ),
            try definition(
                .assetSemanticHeading, "asset.semantic.heading", "Asset semantics",
                "Heading for the local asset semantic and lifecycle projection."
            ),
            try definition(
                .assetSemanticKind, "asset.semantic.kind", "Semantic kind",
                "Localized label for an accepted asset semantic kind."
            ),
            try definition(
                .assetSemanticProductIdentity, "asset.semantic.product_identity", "Product identity",
                "Localized label for progressively disclosed product identifier attributes."
            ),
            try definition(
                .assetSemanticWorkSubjectScope, "asset.semantic.work_subject_scope", "Work subject scope",
                "Localized label for the immutable subject scope captured by completed work."
            ),
            try definition(
                .assetSemanticLifecycle, "asset.semantic.lifecycle", "Lifecycle",
                "Localized label for a human-recorded asset lifecycle history."
            ),
            try definition(
                .assetSemanticState, "asset.semantic.state", "Recorded state",
                "Accessible label for an asset semantic state without operational claims."
            ),
            try definition(
                .assetSemanticUnknownState, "asset.semantic.state.unknown", "Unknown",
                "Accessible text for an unknown or not-recorded semantic value."
            ),
            try definition(
                .assetSemanticDuplicateState, "asset.semantic.state.duplicate", "Duplicate value",
                "Accessible text for a duplicate product identifier value."
            ),
            try definition(
                .assetSemanticRetiredState, "asset.semantic.state.retired", "Retired",
                "Accessible text for a human-recorded retired lifecycle event."
            ),
            try definition(
                .assetSemanticReplacedState, "asset.semantic.state.replaced", "Replaced",
                "Accessible text for a human-recorded replaced lifecycle event."
            ),
            try definition(
                .assetSemanticRecordedState, "asset.semantic.state.recorded", "Recorded",
                "Accessible text for a fact explicitly recorded by a local actor."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    /// C40's additive key surface.  The source catalog remains one English
    /// String Catalog, while this registry exposes the typed basis,
    /// disposition, and non-color status vocabulary to authority consumers.
    static func authorityCriterionRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try assetSemanticRegistry()
        let additions = [
            try definition(
                .authorityCriterionHeading, "authority.criterion.heading", "Authority and criteria",
                "Heading for recorded authority and criterion facts."
            ),
            try definition(
                .authorityCriterionAuthoritySource, "authority.criterion.authority_source", "Authority source",
                "Localized label for an authority source metadata record."
            ),
            try definition(
                .authorityCriterionApplicability, "authority.criterion.applicability", "Applicability",
                "Localized label for a selected applicability disposition."
            ),
            try definition(
                .authorityCriterionApplicable, "authority.criterion.applicability.applicable", "Applicable",
                "Accessible text for an applicable recorded context."
            ),
            try definition(
                .authorityCriterionNotApplicableWithReason,
                "authority.criterion.applicability.not_applicable_with_reason",
                "Not applicable with reason",
                "Accessible text for a not-applicable disposition with its recorded reason."
            ),
            try definition(
                .authorityCriterionApplicabilityUnknown, "authority.criterion.applicability.unknown", "Unknown",
                "Accessible text for an applicability disposition that remains unknown."
            ),
            try definition(
                .authorityCriterionConflictReviewRequired,
                "authority.criterion.applicability.conflict_review_required",
                "Conflict requires review",
                "Accessible text for conflicting applicability sources awaiting review."
            ),
            try definition(
                .authorityCriterionApplicabilityUnsupported,
                "authority.criterion.applicability.unsupported",
                "Unsupported",
                "Accessible text for an applicability context that is not supported."
            ),
            try definition(
                .authorityCriterionResult, "authority.criterion.result", "Screening result",
                "Localized label for a recorded screening result."
            ),
            try definition(
                .authorityCriterionMeetsScreeningCriterion,
                "authority.criterion.result.meets_screening_criterion",
                "Meets screening criterion",
                "Accessible text for a screening result that meets its stated criterion."
            ),
            try definition(
                .authorityCriterionDoesNotMeet,
                "authority.criterion.result.does_not_meet",
                "Does not meet screening criterion",
                "Accessible text for a screening result that does not meet its stated criterion."
            ),
            try definition(
                .authorityCriterionInconclusive, "authority.criterion.result.inconclusive", "Inconclusive",
                "Accessible text for a screening result that cannot be concluded."
            ),
            try definition(
                .authorityCriterionNotEvaluated, "authority.criterion.result.not_evaluated", "Not evaluated",
                "Accessible text for a criterion that was not evaluated."
            ),
            try definition(
                .authorityCriterionSeverity, "authority.criterion.severity", "Severity",
                "Localized label for a severity level within its recorded scale."
            ),
            try definition(
                .authorityCriterionMeasurementProtocol,
                "authority.criterion.measurement_protocol",
                "Measurement protocol",
                "Localized label for the protocol governing a recorded measurement."
            ),
            try definition(
                .authorityCriterionTechnicalBasis, "authority.criterion.technical_basis", "Technical basis",
                "Localized label for the technical basis disclosed with a recorded result."
            ),
            try definition(
                .authorityCriterionNextStep, "authority.criterion.next_step", "Next step",
                "Localized label for the actionable next step accompanying an unresolved state."
            ),
            try definition(
                .authorityCriterionAssessedAgainst, "authority.criterion.assessed_against", "Assessed against",
                "Localized wording for a report that states which basis was assessed against."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func authorityCriteriaRegistry() throws -> LocalizationKeyRegistryV1 {
        try authorityCriterionRegistry()
    }

    /// C41's additive key surface.  Relationship values remain typed facts
    /// owned by the functional-relationship contracts; this catalog supplies
    /// only their English display vocabulary.
    static func functionalRelationshipRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try authorityCriterionRegistry()
        let additions = [
            try definition(
                .functionalRelationshipHeading, "functional.relationship.heading",
                "Functional relationships",
                "Heading for recorded functional relationship facts."
            ),
            try definition(
                .functionalRelationshipType, "functional.relationship.type",
                "Relationship type",
                "Localized label for the package-declared relationship type."
            ),
            try definition(
                .functionalRelationshipDirectedSourceToTarget,
                "functional.relationship.direction.source_to_target",
                "Source to target",
                "Text label for a directed relationship from source to target."
            ),
            try definition(
                .functionalRelationshipSymmetric,
                "functional.relationship.direction.symmetric",
                "Symmetric",
                "Text label for a symmetric relationship."
            ),
            try definition(
                .functionalRelationshipActiveState,
                "functional.relationship.state.active",
                "Active",
                "Text label for an active relationship record."
            ),
            try definition(
                .functionalRelationshipEndedState,
                "functional.relationship.state.ended",
                "Ended",
                "Text label for an ended relationship record."
            ),
            try definition(
                .functionalRelationshipSupersededState,
                "functional.relationship.state.superseded",
                "Superseded",
                "Text label for a superseded relationship record."
            ),
            try definition(
                .functionalRelationshipIncompleteState,
                "functional.relationship.state.incomplete",
                "Incomplete",
                "Text label for an incomplete relationship readiness state."
            ),
            try definition(
                .functionalRelationshipBlockedState,
                "functional.relationship.state.blocked",
                "Blocked",
                "Text label for a blocked relationship state."
            ),
            try definition(
                .functionalRelationshipMinimumNextRequirement,
                "functional.relationship.next_step.minimum_requirement",
                "Minimum requirement",
                "Actionable label for the minimum next requirement for an incomplete record."
            ),
            try definition(
                .functionalRelationshipDescriptor,
                "functional.relationship.descriptor",
                "Descriptor",
                "Localized label for a package relationship descriptor."
            ),
            try definition(
                .functionalRelationshipBounds,
                "functional.relationship.bounds",
                "Cardinality bounds",
                "Localized label for source and target cardinality bounds."
            ),
            try definition(
                .functionalRelationshipSite,
                "functional.relationship.site",
                "Same-site policy",
                "Localized label for the descriptor's Site policy."
            ),
            try definition(
                .functionalRelationshipCrossSiteState,
                "functional.relationship.site.cross_site",
                "Cross-site local",
                "Text label for a recorded cross-Site relationship state."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func functionalRelationshipsRegistry() throws -> LocalizationKeyRegistryV1 {
        try functionalRelationshipRegistry()
    }

    /// C13's additive key surface.  The assurance contracts own audience,
    /// sensitivity, inclusion, preview, manifest, and attestation facts; this
    /// registry supplies their English display labels and deny-by-default
    /// accessibility bindings.
    static func evidenceVisibilityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try functionalRelationshipRegistry()
        let additions = [
            try definition(
                .evidenceVisibilityHeading, "evidence.visibility.heading", "Evidence visibility",
                "Heading for recorded evidence visibility facts."
            ),
            try definition(
                .evidenceVisibilityAudience, "evidence.visibility.audience", "Audience",
                "Localized label for the declared evidence audience."
            ),
            try definition(
                .evidenceVisibilityAudienceInternalReview,
                "evidence.visibility.audience.internal_review", "Internal review",
                "Accessible text for the internal review audience."
            ),
            try definition(
                .evidenceVisibilityAudienceCustomerReport,
                "evidence.visibility.audience.customer_report", "Customer report",
                "Accessible text for the customer report audience."
            ),
            try definition(
                .evidenceVisibilityAudienceExternalCollaborator,
                "evidence.visibility.audience.external_collaborator", "External collaborator",
                "Accessible text for the external collaborator audience."
            ),
            try definition(
                .evidenceVisibilitySensitivity, "evidence.visibility.sensitivity", "Sensitivity",
                "Localized label for the recorded evidence sensitivity."
            ),
            try definition(
                .evidenceVisibilitySensitivityRoutine,
                "evidence.visibility.sensitivity.routine", "Routine",
                "Accessible text for routine evidence sensitivity."
            ),
            try definition(
                .evidenceVisibilitySensitivityRestricted,
                "evidence.visibility.sensitivity.restricted", "Restricted",
                "Accessible text for restricted evidence sensitivity."
            ),
            try definition(
                .evidenceVisibilitySensitivityHighlyRestricted,
                "evidence.visibility.sensitivity.highly_restricted", "Highly restricted",
                "Accessible text for highly restricted evidence sensitivity."
            ),
            try definition(
                .evidenceVisibilityIncluded, "evidence.visibility.state.included", "Included",
                "Accessible text for evidence included in the audience projection."
            ),
            try definition(
                .evidenceVisibilityExcluded, "evidence.visibility.state.excluded", "Excluded",
                "Accessible text for evidence excluded from the audience projection."
            ),
            try definition(
                .evidenceVisibilityOmitted, "evidence.visibility.state.omitted", "Omitted",
                "Accessible text for evidence omitted from the audience projection."
            ),
            try definition(
                .evidenceVisibilityLimitation, "evidence.visibility.state.limitation", "Limitation",
                "Accessible text for a recorded visibility limitation."
            ),
            try definition(
                .evidenceVisibilityUnknown, "evidence.visibility.state.unknown", "Unknown",
                "Accessible text for an unknown visibility value."
            ),
            try definition(
                .evidenceVisibilityPreview, "evidence.visibility.preview", "Preview",
                "Localized label for the mutable evidence projection preview."
            ),
            try definition(
                .evidenceVisibilityPreviewReady, "evidence.visibility.preview.ready", "Ready",
                "Accessible text for a preview matching its recorded source."
            ),
            try definition(
                .evidenceVisibilityPreviewStale, "evidence.visibility.preview.stale", "Stale preview",
                "Accessible text for a preview that no longer matches its recorded source."
            ),
            try definition(
                .evidenceVisibilityManifest, "evidence.visibility.manifest", "Assurance manifest",
                "Localized label for the recorded claim and evidence manifest."
            ),
            try definition(
                .evidenceVisibilityAttestation, "evidence.visibility.attestation", "Attestation",
                "Localized label for a purpose-bound local attestation record."
            ),
            try definition(
                .evidenceVisibilityAttestationPurpose,
                "evidence.visibility.attestation.purpose", "Purpose",
                "Accessible text for the recorded attestation purpose."
            ),
            try definition(
                .evidenceVisibilityAttestationRecorded,
                "evidence.visibility.attestation.recorded", "Recorded",
                "Accessible text for an attestation record that is current."
            ),
            try definition(
                .evidenceVisibilityAttestationSuperseded,
                "evidence.visibility.attestation.superseded", "Superseded",
                "Accessible text for an attestation replaced by a later record."
            ),
            try definition(
                .evidenceVisibilityAttestationVoid,
                "evidence.visibility.attestation.void", "Void",
                "Accessible text for an attestation marked void in the local record."
            ),
            try definition(
                .evidenceVisibilityNextStep, "evidence.visibility.next_step", "Next step",
                "Actionable label for the next step accompanying a limited projection."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func evidenceAssuranceRegistry() throws -> LocalizationKeyRegistryV1 {
        try evidenceVisibilityRegistry()
    }

    /// C14's additive key surface.  Review, change-request, and corrective
    /// action values remain recorded domain facts; this registry only supplies
    /// their closed English display labels and accessibility bindings.
    static func inspectionReviewRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try evidenceVisibilityRegistry()
        let additions = [
            try definition(
                .inspectionReviewHeading, "inspection.review.heading", "Inspection review",
                "Heading for recorded inspection review facts."
            ),
            try definition(
                .inspectionReviewState, "inspection.review.state", "Review state",
                "Localized label for the recorded inspection review state."
            ),
            try definition(
                .inspectionReviewDraft, "inspection.review.state.draft", "Draft",
                "Accessible text for a review still in draft state."
            ),
            try definition(
                .inspectionReviewFieldComplete, "inspection.review.state.field_complete", "Field complete",
                "Accessible text for a review with its field record complete."
            ),
            try definition(
                .inspectionReviewReadyForReview, "inspection.review.state.ready_for_review", "Ready for review",
                "Accessible text for a review ready for a recorded review decision."
            ),
            try definition(
                .inspectionReviewChangesRequested, "inspection.review.state.changes_requested", "Changes requested",
                "Accessible text for a review with recorded changes requested."
            ),
            try definition(
                .inspectionReviewAccepted, "inspection.review.state.accepted", "Accepted",
                "Accessible text for a review with an accepted recorded disposition."
            ),
            try definition(
                .inspectionReviewFinalized, "inspection.review.state.finalized", "Finalized",
                "Accessible text for a review with a recorded final state."
            ),
            try definition(
                .inspectionReviewAmended, "inspection.review.state.amended", "Amended",
                "Accessible text for a review amended in a later recorded revision."
            ),
            try definition(
                .inspectionReviewSuperseded, "inspection.review.state.superseded", "Superseded",
                "Accessible text for a review superseded by a later recorded subject."
            ),
            try definition(
                .inspectionReviewDisposition, "inspection.review.disposition", "Review disposition",
                "Localized label for a recorded review disposition."
            ),
            try definition(
                .inspectionReviewDispositionChangesRequested,
                "inspection.review.disposition.changes_requested", "Changes requested",
                "Accessible text for a disposition that records requested changes."
            ),
            try definition(
                .inspectionReviewDispositionAccepted,
                "inspection.review.disposition.accepted", "Accepted",
                "Accessible text for an accepted recorded review disposition."
            ),
            try definition(
                .inspectionReviewChangeRequest, "inspection.review.change_request", "Change request",
                "Localized label for an immutable recorded change request."
            ),
            try definition(
                .inspectionReviewChangeRequestState, "inspection.review.change_request.state", "Change request state",
                "Localized label for the recorded change request state."
            ),
            try definition(
                .inspectionReviewChangeRequestOpen,
                "inspection.review.change_request.state.open", "Open",
                "Accessible text for an open recorded change request."
            ),
            try definition(
                .inspectionReviewChangeRequestResolved,
                "inspection.review.change_request.state.resolved", "Resolved",
                "Accessible text for a resolved recorded change request."
            ),
            try definition(
                .inspectionReviewChangeRequestWithdrawn,
                "inspection.review.change_request.state.withdrawn", "Withdrawn",
                "Accessible text for a withdrawn recorded change request."
            ),
            try definition(
                .inspectionReviewChangeRequestSuperseded,
                "inspection.review.change_request.state.superseded", "Superseded",
                "Accessible text for a change request superseded by a later record."
            ),
            try definition(
                .inspectionReviewChangeRequestResolution,
                "inspection.review.change_request.resolution", "Change request resolution",
                "Localized label for the recorded resolution of a change request."
            ),
            try definition(
                .inspectionReviewChangeRequestResolutionFulfilled,
                "inspection.review.change_request.resolution.fulfilled", "Fulfilled",
                "Accessible text for a fulfilled recorded change request."
            ),
            try definition(
                .inspectionReviewChangeRequestResolutionWithdrawnWithReason,
                "inspection.review.change_request.resolution.withdrawn_with_reason", "Withdrawn with reason",
                "Accessible text for a change request withdrawn with a recorded reason."
            ),
            try definition(
                .inspectionReviewChangeRequestResolutionSuperseded,
                "inspection.review.change_request.resolution.superseded", "Superseded",
                "Accessible text for a resolution superseded by a later record."
            ),
            try definition(
                .inspectionReviewCorrectiveAction,
                "inspection.review.corrective_action", "Corrective action",
                "Localized label for a recorded corrective action."
            ),
            try definition(
                .inspectionReviewCorrectiveActionState,
                "inspection.review.corrective_action.state", "Corrective action state",
                "Localized label for the recorded corrective action state."
            ),
            try definition(
                .inspectionReviewCorrectiveActionOpen,
                "inspection.review.corrective_action.state.open", "Open",
                "Accessible text for an open recorded corrective action."
            ),
            try definition(
                .inspectionReviewCorrectiveActionInProgress,
                "inspection.review.corrective_action.state.in_progress", "In progress",
                "Accessible text for a corrective action in progress."
            ),
            try definition(
                .inspectionReviewCorrectiveActionAwaitingVerification,
                "inspection.review.corrective_action.state.awaiting_verification", "Awaiting recorded check",
                "Accessible text for a corrective action awaiting a recorded check."
            ),
            try definition(
                .inspectionReviewCorrectiveActionClosed,
                "inspection.review.corrective_action.state.closed", "Closed",
                "Accessible text for a corrective action closed with its recorded evidence."
            ),
            try definition(
                .inspectionReviewCorrectiveActionReopened,
                "inspection.review.corrective_action.state.reopened", "Reopened",
                "Accessible text for a corrective action reopened by a recorded trigger."
            ),
            try definition(
                .inspectionReviewCorrectiveActionSuperseded,
                "inspection.review.corrective_action.state.superseded", "Superseded",
                "Accessible text for a corrective action superseded by a later record."
            ),
            try definition(
                .inspectionReviewNextStep, "inspection.review.next_step", "Next step",
                "Actionable label for the next recorded step accompanying a review state."
            ),
            try definition(
                .inspectionReviewMinimumNextRequirement,
                "inspection.review.next_step.minimum_requirement", "Minimum requirement",
                "Actionable label for the minimum recorded requirement before the next review step."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func reviewCorrectiveActionRegistry() throws -> LocalizationKeyRegistryV1 {
        try inspectionReviewRegistry()
    }

    static func reviewAndCorrectiveActionRegistry() throws -> LocalizationKeyRegistryV1 {
        try inspectionReviewRegistry()
    }

    /// C15's additive key surface.  Packet coordination values remain local
    /// recorded facts; this registry supplies only their closed English
    /// labels and never persists or renders packet contents.
    static func workPacketRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try inspectionReviewRegistry()
        let additions = [
            try definition(
                .workPacketHeading, "work.packet.heading", "Work packet",
                "Heading for recorded local packet coordination facts."
            ),
            try definition(
                .workPacketManifest, "work.packet.manifest", "Packet manifest",
                "Localized label for an immutable bounded packet manifest."
            ),
            try definition(
                .workPacketItem, "work.packet.item", "Work item",
                "Localized label for one bounded packet item."
            ),
            try definition(
                .workPacketManifestState, "work.packet.manifest.state", "Manifest state",
                "Localized label for the recorded packet manifest state."
            ),
            try definition(
                .workPacketManifestDraft, "work.packet.manifest.state.draft", "Draft",
                "Accessible text for a packet manifest in draft state."
            ),
            try definition(
                .workPacketManifestReady, "work.packet.manifest.state.ready", "Ready",
                "Accessible text for a packet manifest ready for local work."
            ),
            try definition(
                .workPacketManifestInvalid, "work.packet.manifest.state.invalid", "Invalid",
                "Accessible text for a packet manifest that failed recorded validation."
            ),
            try definition(
                .workPacketManifestReplayed, "work.packet.manifest.state.replayed", "Replayed",
                "Accessible text for a packet manifest with a recorded replay."
            ),
            try definition(
                .workPacketManifestConflicted,
                "work.packet.manifest.state.conflicted", "Conflict recorded",
                "Accessible text for a packet manifest with a recorded conflict."
            ),
            try definition(
                .workPacketManifestSuperseded,
                "work.packet.manifest.state.superseded", "Superseded",
                "Accessible text for a packet manifest superseded by a later record."
            ),
            try definition(
                .workPacketClaim, "work.packet.claim", "Item claim",
                "Localized label for a recorded local item claim."
            ),
            try definition(
                .workPacketClaimState, "work.packet.claim.state", "Claim state",
                "Localized label for the recorded item claim state."
            ),
            try definition(
                .workPacketClaimUnclaimed, "work.packet.claim.state.unclaimed", "Unclaimed",
                "Accessible text for an item with no recorded claim."
            ),
            try definition(
                .workPacketClaimClaimed, "work.packet.claim.state.claimed", "Claimed",
                "Accessible text for an item with a recorded claim."
            ),
            try definition(
                .workPacketClaimReleased, "work.packet.claim.state.released", "Released",
                "Accessible text for an item with a recorded claim release."
            ),
            try definition(
                .workPacketClaimConflicted,
                "work.packet.claim.state.conflicted", "Conflict recorded",
                "Accessible text for an item claim with a recorded conflict."
            ),
            try definition(
                .workPacketLease, "work.packet.lease", "Work lease",
                "Localized label for a recorded local work lease."
            ),
            try definition(
                .workPacketLeaseState, "work.packet.lease.state", "Lease state",
                "Localized label for the recorded work lease state."
            ),
            try definition(
                .workPacketLeaseActive, "work.packet.lease.state.active", "Active",
                "Accessible text for an active recorded work lease."
            ),
            try definition(
                .workPacketLeaseExpiring, "work.packet.lease.state.expiring", "Expiring",
                "Accessible text for a work lease approaching its recorded expiry."
            ),
            try definition(
                .workPacketLeaseExpired, "work.packet.lease.state.expired", "Expired",
                "Accessible text for a work lease past its recorded expiry."
            ),
            try definition(
                .workPacketLeaseReclaimed, "work.packet.lease.state.reclaimed", "Reclaimed",
                "Accessible text for a work lease reclaimed by a recorded local action."
            ),
            try definition(
                .workPacketRelease, "work.packet.release", "Item release",
                "Localized label for a recorded local item release."
            ),
            try definition(
                .workPacketReleaseState, "work.packet.release.state", "Release state",
                "Localized label for the recorded item release state."
            ),
            try definition(
                .workPacketReleaseRecorded, "work.packet.release.state.recorded", "Recorded",
                "Accessible text for an item release recorded in the local history."
            ),
            try definition(
                .workPacketReleaseAvailable, "work.packet.release.state.available", "Available",
                "Accessible text for an item available after a recorded release."
            ),
            try definition(
                .workPacketReleaseSuperseded,
                "work.packet.release.state.superseded", "Superseded",
                "Accessible text for an item release superseded by a later record."
            ),
            try definition(
                .workPacketHandoff, "work.packet.handoff", "Packet handoff",
                "Localized label for a recorded local packet handoff."
            ),
            try definition(
                .workPacketHandoffState, "work.packet.handoff.state", "Handoff state",
                "Localized label for the recorded packet handoff state."
            ),
            try definition(
                .workPacketHandoffPending, "work.packet.handoff.state.pending", "Pending",
                "Accessible text for a packet handoff awaiting a recorded result."
            ),
            try definition(
                .workPacketHandoffAccepted, "work.packet.handoff.state.accepted", "Accepted",
                "Accessible text for a packet handoff with an accepted recorded result."
            ),
            try definition(
                .workPacketHandoffRejected, "work.packet.handoff.state.rejected", "Rejected",
                "Accessible text for a packet handoff with a rejected recorded result."
            ),
            try definition(
                .workPacketHandoffCompleted, "work.packet.handoff.state.completed", "Completed",
                "Accessible text for a packet handoff with a completed recorded result."
            ),
            try definition(
                .workPacketConflict, "work.packet.conflict", "Packet conflict",
                "Localized label for a recorded packet coordination conflict."
            ),
            try definition(
                .workPacketConflictState, "work.packet.conflict.state", "Conflict state",
                "Localized label for the recorded packet conflict state."
            ),
            try definition(
                .workPacketConflictDetected,
                "work.packet.conflict.state.detected", "Detected",
                "Accessible text for a packet conflict detected in the local record."
            ),
            try definition(
                .workPacketConflictQuarantined,
                "work.packet.conflict.state.quarantined", "Quarantined",
                "Accessible text for a conflicting packet result held for review."
            ),
            try definition(
                .workPacketConflictReviewRequired,
                "work.packet.conflict.state.review_required", "Review required",
                "Accessible text for a packet conflict requiring a recorded review."
            ),
            try definition(
                .workPacketConflictResolved,
                "work.packet.conflict.state.resolved", "Resolved",
                "Accessible text for a packet conflict with a recorded resolution."
            ),
            try definition(
                .workPacketExpiry, "work.packet.expiry", "Lease expiry",
                "Localized label for the recorded lease expiry condition."
            ),
            try definition(
                .workPacketExpiryState, "work.packet.expiry.state", "Expiry state",
                "Localized label for the recorded packet expiry state."
            ),
            try definition(
                .workPacketExpiryNotExpired,
                "work.packet.expiry.state.not_expired", "Not expired",
                "Accessible text for a lease whose recorded expiry has not passed."
            ),
            try definition(
                .workPacketExpiryExpiring,
                "work.packet.expiry.state.expiring", "Expiring",
                "Accessible text for a lease approaching its recorded expiry."
            ),
            try definition(
                .workPacketExpiryExpired,
                "work.packet.expiry.state.expired", "Expired",
                "Accessible text for a lease past its recorded expiry."
            ),
            try definition(
                .workPacketReplay, "work.packet.replay", "Packet replay",
                "Localized label for a recorded local packet replay."
            ),
            try definition(
                .workPacketReplayState, "work.packet.replay.state", "Replay state",
                "Localized label for the recorded packet replay state."
            ),
            try definition(
                .workPacketReplayPending, "work.packet.replay.state.pending", "Pending",
                "Accessible text for a packet replay awaiting a recorded result."
            ),
            try definition(
                .workPacketReplayApplied, "work.packet.replay.state.applied", "Applied",
                "Accessible text for a packet replay with a recorded application."
            ),
            try definition(
                .workPacketReplayIdempotent,
                "work.packet.replay.state.idempotent", "Already applied",
                "Accessible text for a packet replay recognized as already applied."
            ),
            try definition(
                .workPacketReplayQuarantined,
                "work.packet.replay.state.quarantined", "Quarantined",
                "Accessible text for a packet replay held for recorded review."
            ),
            try definition(
                .workPacketNextStep, "work.packet.next_step", "Next step",
                "Actionable label for the next recorded packet-coordination step."
            ),
            try definition(
                .workPacketMinimumNextRequirement,
                "work.packet.next_step.minimum_requirement", "Minimum requirement",
                "Actionable label for the minimum recorded requirement before the next step."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func workPacketManifestRegistry() throws -> LocalizationKeyRegistryV1 {
        try workPacketRegistry()
    }

    static func packetCoordinationRegistry() throws -> LocalizationKeyRegistryV1 {
        try workPacketRegistry()
    }

    /// C36's additive key surface.  Existing C16/C38/C39/C40/C41 and C15
    /// registries remain available as compatibility projections; this registry
    /// is selected only for the durable field-draft presentation contract.
    static func fieldDraftRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try workPacketRegistry()
        let additions = try FieldDraftLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func fieldDraftResilienceRegistry() throws -> LocalizationKeyRegistryV1 {
        try fieldDraftRegistry()
    }

    static func draftDurabilityRegistry() throws -> LocalizationKeyRegistryV1 {
        try fieldDraftRegistry()
    }

    /// C19's additive key surface.  Measurement values and unit identifiers
    /// remain exact recorded facts; this registry contributes labels only and
    /// does not create a second unit system or a second catalog.
    static func measurementIntegrityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try fieldDraftRegistry()
        let additions = try MeasurementIntegrityLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func measurementRegistry() throws -> LocalizationKeyRegistryV1 {
        try measurementIntegrityRegistry()
    }

    static func accessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let values: [(id: FeedbackMailAccessibilityIDV1, label: BundledLocalizationKeyV1)] = [
            (.screen, .mailComposerTitle),
            (.recipient, .mailRecipient),
            (.attachmentCount, .mailAttachmentCount),
            (.body, .mailMessageLabel),
            (.done, .commonDone),
        ]
        let entries = try values.map { value in
            AccessibilityContractV1(
                semanticID: value.id.rawValue, role: value.id.role, reachability: .always,
                labelKey: try LocalizationKeyV1(value.label.rawValue), hintKey: nil,
                valueKey: nil, dynamicSuffixPolicy: .none, deprecatedAliases: []
            )
        }
        return try SemanticAccessibilityIDRegistryV1(
            entries: entries, localization: localization
        )
    }

    static func accountabilityAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try accessibilityRegistry(localization: localization)
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: "accountability.party", role: .group,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityParty.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.site-role", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityRole.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.actor", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityActor.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.qualification", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityQualification.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff.disclosure", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff.history", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func assetSemanticAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try accountabilityAccessibilityRegistry(localization: localization)
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.screen.rawValue, role: .screen,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticHeading.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.heading.rawValue, role: .heading,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticHeading.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.kind.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticKind.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.productIdentity.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticProductIdentity.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.lifecycle.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticLifecycle.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.workSubjectScope.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticWorkSubjectScope.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.state.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.unknownState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticUnknownState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.duplicateState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticDuplicateState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.retiredState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticRetiredState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.replacedState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticReplacedState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.recordedState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticRecordedState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func authorityCriterionAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try assetSemanticAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            AuthorityCriterionLocalizationKeyV1.nextStep.rawValue
        )
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.screen.rawValue,
                role: .screen, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.heading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.heading.rawValue,
                role: .heading, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.heading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.authoritySource.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.authoritySource.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.applicability.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicability.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.applicable.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicabilityApplicable.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.notApplicableWithReason.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicabilityNotApplicableWithReason.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.unknownApplicability.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicabilityUnknown.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.conflictReviewRequired.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicabilityConflictReviewRequired.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.unsupportedApplicability.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.applicabilityUnsupported.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.criterionResult.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.criterionResult.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.meetsScreeningCriterion.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.resultMeetsScreeningCriterion.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.doesNotMeet.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.resultDoesNotMeet.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.inconclusive.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.resultInconclusive.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.notEvaluated.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.resultNotEvaluated.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.severity.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.severity.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.measurementProtocol.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.measurementProtocol.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.technicalBasis.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.technicalBasis.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.nextStep.rawValue,
                role: .button, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.nextStep.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AuthorityCriterionAccessibilityIDV1.assessedAgainst.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    AuthorityCriterionLocalizationKeyV1.assessedAgainst.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func authorityCriteriaAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try authorityCriterionAccessibilityRegistry(localization: localization)
    }

    /// C41's additive semantic IDs inherit the C16/C38/C39/C40 IDs and bind
    /// every relationship label to the sole typed localization registry.
    static func functionalRelationshipAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try authorityCriterionAccessibilityRegistry(localization: localization)
        let minimumNextRequirement = try LocalizationKeyV1(
            BundledLocalizationKeyV1.functionalRelationshipMinimumNextRequirement.rawValue
        )
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.screen.rawValue,
                role: .screen, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipHeading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.heading.rawValue,
                role: .heading, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipHeading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.type.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipType.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.directedSourceToTarget.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipDirectedSourceToTarget.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.symmetric.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipSymmetric.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.activeState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipActiveState.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.endedState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipEndedState.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.supersededState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipSupersededState.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.incompleteState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipIncompleteState.rawValue
                ), hintKey: minimumNextRequirement, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.blockedState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipBlockedState.rawValue
                ), hintKey: minimumNextRequirement, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.minimumNextRequirement.rawValue,
                role: .button, reachability: .whenAvailable,
                labelKey: minimumNextRequirement, hintKey: nil, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.descriptor.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipDescriptor.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.bounds.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipBounds.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.site.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipSite.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: FunctionalRelationshipAccessibilityIDV1.crossSiteState.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.functionalRelationshipCrossSiteState.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func functionalRelationshipsAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try functionalRelationshipAccessibilityRegistry(localization: localization)
    }

    /// C13's semantic IDs inherit every earlier catalog binding and add the
    /// evidence-assurance audience, sensitivity, preview, manifest, and
    /// attestation states.  Limited states carry the localized next-step key
    /// so text and action remain available without color or icon inference.
    static func evidenceVisibilityAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try functionalRelationshipAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            BundledLocalizationKeyV1.evidenceVisibilityNextStep.rawValue
        )
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.screen.rawValue,
                role: .screen, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityHeading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.heading.rawValue,
                role: .heading, reachability: .always,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityHeading.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.audience.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAudience.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.audienceInternalReview.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAudienceInternalReview.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.audienceCustomerReport.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAudienceCustomerReport.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.audienceExternalCollaborator.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAudienceExternalCollaborator.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.sensitivity.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilitySensitivity.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.sensitivityRoutine.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilitySensitivityRoutine.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.sensitivityRestricted.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilitySensitivityRestricted.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.sensitivityHighlyRestricted.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilitySensitivityHighlyRestricted.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.included.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityIncluded.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.excluded.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityExcluded.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.omitted.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityOmitted.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.limitation.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityLimitation.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.unknown.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityUnknown.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.preview.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityPreview.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.previewReady.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityPreviewReady.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.previewStale.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityPreviewStale.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.manifest.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityManifest.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.attestation.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAttestation.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.attestationPurpose.rawValue,
                role: .group, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAttestationPurpose.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.attestationRecorded.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAttestationRecorded.rawValue
                ), hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.attestationSuperseded.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAttestationSuperseded.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.attestationVoid.rawValue,
                role: .status, reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(
                    BundledLocalizationKeyV1.evidenceVisibilityAttestationVoid.rawValue
                ), hintKey: nextStep, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: EvidenceVisibilityAccessibilityIDV1.nextStep.rawValue,
                role: .button, reachability: .whenAvailable,
                labelKey: nextStep, hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func evidenceAssuranceAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try evidenceVisibilityAccessibilityRegistry(localization: localization)
    }

    /// C14's semantic IDs inherit the earlier catalog bindings and add the
    /// recorded review, request, resolution, and corrective-action states.
    /// Indeterminate states carry the localized next-step hint so their
    /// meaning remains available without color or icon inference.
    static func inspectionReviewAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try evidenceVisibilityAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            BundledLocalizationKeyV1.inspectionReviewNextStep.rawValue
        )
        let values: [
            (InspectionReviewAccessibilityIDV1, SemanticAccessibilityRoleV1, BundledLocalizationKeyV1)
        ] = [
            (.screen, .screen, .inspectionReviewHeading),
            (.heading, .heading, .inspectionReviewHeading),
            (.state, .group, .inspectionReviewState),
            (.draft, .status, .inspectionReviewDraft),
            (.fieldComplete, .status, .inspectionReviewFieldComplete),
            (.readyForReview, .status, .inspectionReviewReadyForReview),
            (.changesRequested, .status, .inspectionReviewChangesRequested),
            (.accepted, .status, .inspectionReviewAccepted),
            (.finalized, .status, .inspectionReviewFinalized),
            (.amended, .status, .inspectionReviewAmended),
            (.superseded, .status, .inspectionReviewSuperseded),
            (.disposition, .group, .inspectionReviewDisposition),
            (.dispositionChangesRequested, .status, .inspectionReviewDispositionChangesRequested),
            (.dispositionAccepted, .status, .inspectionReviewDispositionAccepted),
            (.changeRequest, .group, .inspectionReviewChangeRequest),
            (.changeRequestState, .group, .inspectionReviewChangeRequestState),
            (.changeRequestOpen, .status, .inspectionReviewChangeRequestOpen),
            (.changeRequestResolved, .status, .inspectionReviewChangeRequestResolved),
            (.changeRequestWithdrawn, .status, .inspectionReviewChangeRequestWithdrawn),
            (.changeRequestSuperseded, .status, .inspectionReviewChangeRequestSuperseded),
            (.changeRequestResolution, .group, .inspectionReviewChangeRequestResolution),
            (.changeRequestResolutionFulfilled, .status, .inspectionReviewChangeRequestResolutionFulfilled),
            (.changeRequestResolutionWithdrawnWithReason, .status, .inspectionReviewChangeRequestResolutionWithdrawnWithReason),
            (.changeRequestResolutionSuperseded, .status, .inspectionReviewChangeRequestResolutionSuperseded),
            (.correctiveAction, .group, .inspectionReviewCorrectiveAction),
            (.correctiveActionState, .group, .inspectionReviewCorrectiveActionState),
            (.correctiveActionOpen, .status, .inspectionReviewCorrectiveActionOpen),
            (.correctiveActionInProgress, .status, .inspectionReviewCorrectiveActionInProgress),
            (.correctiveActionAwaitingVerification, .status, .inspectionReviewCorrectiveActionAwaitingVerification),
            (.correctiveActionClosed, .status, .inspectionReviewCorrectiveActionClosed),
            (.correctiveActionReopened, .status, .inspectionReviewCorrectiveActionReopened),
            (.correctiveActionSuperseded, .status, .inspectionReviewCorrectiveActionSuperseded),
            (.nextStep, .button, .inspectionReviewNextStep),
            (.minimumNextRequirement, .button, .inspectionReviewMinimumNextRequirement),
        ]
        let entries = try values.map { id, role, key in
            AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(key.rawValue),
                hintKey: InspectionReviewAccessibilityPolicyV1
                    .indeterminateSemanticIDs.contains(id.rawValue) ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func reviewCorrectiveActionAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try inspectionReviewAccessibilityRegistry(localization: localization)
    }

    static func reviewAndCorrectiveActionAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try inspectionReviewAccessibilityRegistry(localization: localization)
    }

    /// C15 semantic IDs inherit the earlier catalog bindings and add packet,
    /// claim, lease, release, handoff, conflict, expiry, and replay states.
    /// Indeterminate states carry the localized next-step hint so their meaning
    /// remains available without color or icon inference.
    static func workPacketAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try inspectionReviewAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            BundledLocalizationKeyV1.workPacketNextStep.rawValue
        )
        let values: [
            (WorkPacketAccessibilityIDV1, SemanticAccessibilityRoleV1, BundledLocalizationKeyV1)
        ] = [
            (.screen, .screen, .workPacketHeading),
            (.heading, .heading, .workPacketHeading),
            (.manifest, .group, .workPacketManifest),
            (.item, .group, .workPacketItem),
            (.manifestState, .group, .workPacketManifestState),
            (.manifestDraft, .status, .workPacketManifestDraft),
            (.manifestReady, .status, .workPacketManifestReady),
            (.manifestInvalid, .status, .workPacketManifestInvalid),
            (.manifestReplayed, .status, .workPacketManifestReplayed),
            (.manifestConflicted, .status, .workPacketManifestConflicted),
            (.manifestSuperseded, .status, .workPacketManifestSuperseded),
            (.claim, .group, .workPacketClaim),
            (.claimState, .group, .workPacketClaimState),
            (.claimUnclaimed, .status, .workPacketClaimUnclaimed),
            (.claimClaimed, .status, .workPacketClaimClaimed),
            (.claimReleased, .status, .workPacketClaimReleased),
            (.claimConflicted, .status, .workPacketClaimConflicted),
            (.lease, .group, .workPacketLease),
            (.leaseState, .group, .workPacketLeaseState),
            (.leaseActive, .status, .workPacketLeaseActive),
            (.leaseExpiring, .status, .workPacketLeaseExpiring),
            (.leaseExpired, .status, .workPacketLeaseExpired),
            (.leaseReclaimed, .status, .workPacketLeaseReclaimed),
            (.release, .group, .workPacketRelease),
            (.releaseState, .group, .workPacketReleaseState),
            (.releaseRecorded, .status, .workPacketReleaseRecorded),
            (.releaseAvailable, .status, .workPacketReleaseAvailable),
            (.releaseSuperseded, .status, .workPacketReleaseSuperseded),
            (.handoff, .group, .workPacketHandoff),
            (.handoffState, .group, .workPacketHandoffState),
            (.handoffPending, .status, .workPacketHandoffPending),
            (.handoffAccepted, .status, .workPacketHandoffAccepted),
            (.handoffRejected, .status, .workPacketHandoffRejected),
            (.handoffCompleted, .status, .workPacketHandoffCompleted),
            (.conflict, .group, .workPacketConflict),
            (.conflictState, .group, .workPacketConflictState),
            (.conflictDetected, .status, .workPacketConflictDetected),
            (.conflictQuarantined, .status, .workPacketConflictQuarantined),
            (.conflictReviewRequired, .status, .workPacketConflictReviewRequired),
            (.conflictResolved, .status, .workPacketConflictResolved),
            (.expiry, .group, .workPacketExpiry),
            (.expiryState, .group, .workPacketExpiryState),
            (.expiryNotExpired, .status, .workPacketExpiryNotExpired),
            (.expiryExpiring, .status, .workPacketExpiryExpiring),
            (.expiryExpired, .status, .workPacketExpiryExpired),
            (.replay, .group, .workPacketReplay),
            (.replayState, .group, .workPacketReplayState),
            (.replayPending, .status, .workPacketReplayPending),
            (.replayApplied, .status, .workPacketReplayApplied),
            (.replayIdempotent, .status, .workPacketReplayIdempotent),
            (.replayQuarantined, .status, .workPacketReplayQuarantined),
            (.nextStep, .button, .workPacketNextStep),
            (.minimumNextRequirement, .button, .workPacketMinimumNextRequirement),
        ]
        let entries = try values.map { id, role, key in
            AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(key.rawValue),
                hintKey: WorkPacketAccessibilityPolicyV1
                    .indeterminateSemanticIDs.contains(id.rawValue) ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func workPacketManifestAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try workPacketAccessibilityRegistry(localization: localization)
    }

    static func packetCoordinationAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try workPacketAccessibilityRegistry(localization: localization)
    }

    /// C36 accessibility is a reusable status projection.  Per-item callers
    /// may append an opaque suffix at their presentation boundary, while the
    /// registry itself remains a closed set of stable semantic IDs.
    static func fieldDraftAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try workPacketAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            FieldDraftLocalizationKeyV1.nextStep.rawValue
        )
        let entries = try FieldDraftAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep, .minimumNextRequirement, .recoverySafeAction:
                role = .button
            default:
                role = FieldDraftAccessibilityPolicyV1.stateSemanticIDs.contains(id.rawValue)
                    ? .status : .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey.localizationKey,
                hintKey: FieldDraftAccessibilityPolicyV1
                    .indeterminateSemanticIDs.contains(id.rawValue) ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func fieldDraftResilienceAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try fieldDraftAccessibilityRegistry(localization: localization)
    }

    /// C19 adds semantic labels for the exact measurement, instrument,
    /// calibration, series, and quality projections.  Every indeterminate
    /// state receives the same actionable next-step hint; no icon or color is
    /// treated as the source of meaning.
    static func measurementIntegrityAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try fieldDraftAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(
            MeasurementIntegrityLocalizationKeyV1.nextStep.rawValue
        )
        let entries = try MeasurementIntegrityAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            default:
                role = MeasurementIntegrityAccessibilityPolicyV1.statusSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            let labelKey: LocalizationKeyV1
            if id == .screen {
                labelKey = try LocalizationKeyV1(
                    MeasurementIntegrityLocalizationKeyV1.heading.rawValue
                )
            } else {
                labelKey = try LocalizationKeyV1(id.rawValue)
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: labelKey,
                hintKey: MeasurementIntegrityAccessibilityPolicyV1
                    .requiresActionableNextStep(for: id.rawValue) ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func measurementAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try measurementIntegrityAccessibilityRegistry(localization: localization)
    }

    static func publish(
        sourceCatalogBytes: Data,
        packagePublications: [InspectionPackagePublishedReleaseV1] = [],
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        previousRegistry: LocalizationKeyRegistryV1? = nil,
        previousLegacy: LegacyLocalizationAccessibilityAllowlistV1? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriteria: Bool = false,
        includeFunctionalRelationships: Bool = false,
        includeEvidenceVisibility: Bool = false,
        includeEvidenceAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeReviewCorrectiveAction: Bool = false,
        includeReviewAndCorrectiveAction: Bool = false,
        includeWorkPacket: Bool = false,
        includeWorkPacketManifest: Bool = false,
        includePacketCoordination: Bool = false,
        includeFieldDraft: Bool = false,
        includeMeasurementIntegrity: Bool = false,
        includePrivacyTransform: Bool = false,
        includeClientCapability: Bool = false,
        includeFieldReference: Bool = false,
        includeAccessibleDocument: Bool = false,
        includeSurveyDefinition: Bool = false,
        interruption: Interruption = { _ in }
    ) throws -> LocalizationCatalogPublicationV1 {
        try interruption(.beforeValidation)
        try legacy.validate()
        let locales = LocalizationLocaleManifestV1.shippingV1()
        try locales.validate()
        let keys: LocalizationKeyRegistryV1
        if includeSurveyDefinition {
            keys = try surveyDefinitionRegistry()
        } else if includeAccessibleDocument {
            keys = try accessibleDocumentRegistry()
        } else if includeFieldReference {
            keys = try fieldReferenceRegistry()
        } else if includeClientCapability {
            keys = try clientCapabilityRegistry()
        } else if includePrivacyTransform {
            keys = try privacyTransformRegistry()
        } else if includeMeasurementIntegrity {
            keys = try measurementIntegrityRegistry()
        } else if includeFieldDraft {
            keys = try fieldDraftRegistry()
        } else if includeWorkPacket || includeWorkPacketManifest || includePacketCoordination {
            keys = try workPacketRegistry()
        } else if includeInspectionReview || includeReviewCorrectiveAction || includeReviewAndCorrectiveAction {
            keys = try inspectionReviewRegistry()
        } else if includeEvidenceVisibility || includeEvidenceAssurance {
            keys = try evidenceVisibilityRegistry()
        } else if includeFunctionalRelationships {
            keys = try functionalRelationshipRegistry()
        } else if includeAuthorityCriteria {
            keys = try authorityCriterionRegistry()
        } else if includeAssetSemantics {
            keys = try assetSemanticRegistry()
        } else if includeAccountability {
            keys = try accountabilityRegistry()
        } else {
            keys = try registry()
        }
        try validateSourceCatalog(sourceCatalogBytes, registry: keys)
        if let previousRegistry { try keys.validateSuccessor(of: previousRegistry) }
        let requiredMailLegacy = try LegacyLocalizationAccessibilityAllowlistV1(entries: [])
        guard legacy == requiredMailLegacy else {
            throw LocalizationContractFailureV1.legacyAllowlistGrowth
        }
        if let previousLegacy { try previousLegacy.validateObserved(legacy.entries) }
        let accessibility: SemanticAccessibilityIDRegistryV1
        if includeSurveyDefinition {
            accessibility = try surveyDefinitionAccessibilityRegistry(localization: keys)
        } else if includeAccessibleDocument {
            accessibility = try accessibleDocumentAccessibilityRegistry(localization: keys)
        } else if includeFieldReference {
            accessibility = try fieldReferenceAccessibilityRegistry(localization: keys)
        } else if includeClientCapability {
            accessibility = try clientCapabilityAccessibilityRegistry(localization: keys)
        } else if includePrivacyTransform {
            accessibility = try privacyTransformAccessibilityRegistry(localization: keys)
        } else if includeMeasurementIntegrity {
            accessibility = try measurementIntegrityAccessibilityRegistry(localization: keys)
        } else if includeFieldDraft {
            accessibility = try fieldDraftAccessibilityRegistry(localization: keys)
        } else if includeWorkPacket || includeWorkPacketManifest || includePacketCoordination {
            accessibility = try workPacketAccessibilityRegistry(localization: keys)
        } else if includeInspectionReview || includeReviewCorrectiveAction || includeReviewAndCorrectiveAction {
            accessibility = try inspectionReviewAccessibilityRegistry(localization: keys)
        } else if includeEvidenceVisibility || includeEvidenceAssurance {
            accessibility = try evidenceVisibilityAccessibilityRegistry(localization: keys)
        } else if includeFunctionalRelationships {
            accessibility = try functionalRelationshipAccessibilityRegistry(localization: keys)
        } else if includeAuthorityCriteria {
            accessibility = try authorityCriterionAccessibilityRegistry(localization: keys)
        } else if includeAssetSemantics {
            accessibility = try assetSemanticAccessibilityRegistry(localization: keys)
        } else if includeAccountability {
            accessibility = try accountabilityAccessibilityRegistry(localization: keys)
        } else {
            accessibility = try accessibilityRegistry(localization: keys)
        }
        let registryBytes = try LocalizationContractCanonicalCodecV1.encode(keys)
        let localeBytes = try LocalizationContractCanonicalCodecV1.encode(locales)
        let release = try LocalizationCatalogReleaseV1.make(
            sourceCatalog: sourceCatalogBytes, registry: registryBytes,
            localeManifest: localeBytes
        )
        let packageBindings = try packagePublications.map {
            try PackageLocalizationReleaseBindingV1(
                publication: $0, localizationRelease: release,
                slotBindings: try BundledInspectionPackageRegistryV2.shippingLocalizationSlotBindings(),
                registry: keys
            )
        }.sorted { $0.packageReleaseID < $1.packageReleaseID }
        try interruption(.afterValidationBeforePublication)
        let accessibilityBytes = try LocalizationContractCanonicalCodecV1.encode(accessibility)
        let legacyBytes = try LocalizationContractCanonicalCodecV1.encode(legacy)
        let bindingBytes = try packageBindings.map {
            try LocalizationContractCanonicalCodecV1.encode($0)
        }
        let receipt = LocalizationCatalogPublicationReceiptV1(
            release: release,
            semanticRegistrySHA256: KernelCanonicalHashV1.sha256(accessibilityBytes),
            legacyBaselineSHA256: KernelCanonicalHashV1.sha256(legacyBytes),
            packageBindingSHA256s: bindingBytes.map(KernelCanonicalHashV1.sha256),
            persistentWriteOccurred: false
        )
        try interruption(.afterPublicationBeforeReceipt)
        return .complete(
            registry: keys, accessibility: accessibility, legacy: legacy,
            packageBindings: packageBindings, receipt: receipt
        )
    }

    static func recover(
        sourceCatalogBytes: Data?,
        receipt: LocalizationCatalogPublicationReceiptV1?,
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        packagePublications: [InspectionPackagePublishedReleaseV1] = [],
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        includeAuthorityCriteria: Bool = false,
        includeFunctionalRelationships: Bool = false,
        includeEvidenceVisibility: Bool = false,
        includeEvidenceAssurance: Bool = false,
        includeInspectionReview: Bool = false,
        includeReviewCorrectiveAction: Bool = false,
        includeReviewAndCorrectiveAction: Bool = false,
        includeWorkPacket: Bool = false,
        includeWorkPacketManifest: Bool = false,
        includePacketCoordination: Bool = false,
        includeFieldDraft: Bool = false,
        includeMeasurementIntegrity: Bool = false,
        includePrivacyTransform: Bool = false,
        includeClientCapability: Bool = false,
        includeFieldReference: Bool = false,
        includeAccessibleDocument: Bool = false,
        includeSurveyDefinition: Bool = false
    ) throws -> LocalizationCatalogPublicationV1 {
        switch (sourceCatalogBytes, receipt) {
        case (nil, nil): return .zero
        case let (.some(bytes), .some(expected)):
            let publication = try publish(
                sourceCatalogBytes: bytes,
                packagePublications: packagePublications,
                legacy: legacy,
                includeAccountability: includeAccountability,
                includeAssetSemantics: includeAssetSemantics,
                includeAuthorityCriteria: includeAuthorityCriteria,
                includeFunctionalRelationships: includeFunctionalRelationships,
                includeEvidenceVisibility: includeEvidenceVisibility,
                includeEvidenceAssurance: includeEvidenceAssurance,
                includeInspectionReview: includeInspectionReview,
                includeReviewCorrectiveAction: includeReviewCorrectiveAction,
                includeReviewAndCorrectiveAction: includeReviewAndCorrectiveAction,
                includeWorkPacket: includeWorkPacket,
                includeWorkPacketManifest: includeWorkPacketManifest,
                includePacketCoordination: includePacketCoordination,
                includeFieldDraft: includeFieldDraft,
                includeMeasurementIntegrity: includeMeasurementIntegrity,
                includePrivacyTransform: includePrivacyTransform,
                includeClientCapability: includeClientCapability,
                includeFieldReference: includeFieldReference,
                includeAccessibleDocument: includeAccessibleDocument,
                includeSurveyDefinition: includeSurveyDefinition
            )
            guard case let .complete(_, _, _, _, actual) = publication,
                  actual == expected else { throw LocalizationContractFailureV1.digestMismatch }
            return publication
        default: throw LocalizationContractFailureV1.partialPublication
        }
    }

    static func localized(_ key: BundledLocalizationKeyV1, bundle: Bundle = .main) -> String {
        let locale = Locale(identifier: runtimeLanguage)
        switch key {
        case .fieldDraftScreen,
             .fieldDraftHeading,
             .fieldDraftDurability,
             .fieldDraftDurabilityState,
             .fieldDraftNextStep,
             .fieldDraftMinimumNextRequirement,
             .fieldDraftCheckpoint,
             .fieldDraftCheckpointState,
             .fieldDraftAttachment,
             .fieldDraftAttachmentState,
             .fieldDraftCommitSaga,
             .fieldDraftCommitSagaState,
             .fieldDraftRecovery,
             .fieldDraftRecoveryState,
             .fieldDraftRecoverySafeAction,
             .fieldDraftRecoveryFallback,
             .fieldDraftDurabilityUnsavedChanges,
             .fieldDraftDurabilitySavingOnThisIPhone,
             .fieldDraftDurabilitySavedOnThisIPhone,
             .fieldDraftDurabilitySaveBlocked,
             .fieldDraftDurabilityCommitting,
             .fieldDraftDurabilityConflicted,
             .fieldDraftDurabilityRecoveryRequired,
             .fieldDraftDurabilityCommitted,
             .fieldDraftDurabilityDiscarding,
             .fieldDraftDurabilityDiscarded,
             .fieldDraftCheckpointActive,
             .fieldDraftCheckpointCommitting,
             .fieldDraftCheckpointConflicted,
             .fieldDraftCheckpointRecoveryRequired,
             .fieldDraftCheckpointCommitted,
             .fieldDraftCheckpointDiscardPending,
             .fieldDraftCheckpointDiscarded,
             .fieldDraftAttachmentSelected,
             .fieldDraftAttachmentLoading,
             .fieldDraftAttachmentStagedLocal,
             .fieldDraftAttachmentProcessing,
             .fieldDraftAttachmentReady,
             .fieldDraftAttachmentRetryableFailure,
             .fieldDraftAttachmentBlocked,
             .fieldDraftAttachmentRemoved,
             .fieldDraftAttachmentPromoted,
             .fieldDraftAttachmentCapturing,
             .fieldDraftAttachmentHashing,
             .fieldDraftAttachmentReadyLocal,
             .fieldDraftAttachmentFailedRetryable,
             .fieldDraftAttachmentFailedFinal,
             .fieldDraftAttachmentRemovePending,
             .fieldDraftAttachmentCommitted,
             .fieldDraftAttachmentOrphanQuarantined,
             .fieldDraftSagaPrepared,
             .fieldDraftSagaContentPromotedUnbound,
             .fieldDraftSagaTargetCommitted,
             .fieldDraftSagaDraftRetirePending,
             .fieldDraftSagaDraftRetired,
             .fieldDraftSagaConflicted,
             .fieldDraftSagaRecoveryRequired,
             .fieldDraftRecoveryResumeAvailable,
             .fieldDraftRecoveryConflict,
             .fieldDraftRecoveryMissingMedia,
             .fieldDraftRecoveryLowStorage,
             .fieldDraftRecoveryProtectedData,
             .fieldDraftRecoveryUnsupportedCodec,
             .fieldDraftRecoveryPartialStage,
             .fieldDraftRecoveryStaleTarget,
             .fieldDraftRecoveryRecoveryRequired:
            guard let fieldDraftKey = FieldDraftLocalizationKeyV1(rawValue: key.rawValue) else {
                preconditionFailure("Declared FieldDraft localization mapping is incomplete.")
            }
            return fieldDraftKey.englishDefaultValue
        case .feedbackSubject:
            return String(localized: "feedback.mail.subject", defaultValue: "App feedback", bundle: bundle, locale: locale, comment: "Subject of the support email.")
        case .feedbackBodyTemplate:
            return String(localized: "feedback.mail.body_template", defaultValue: "App version: %@ (%@)\nDevice: %@\nOS: iOS %@\n\nFeedback:\n", bundle: bundle, locale: locale, comment: "Editable support-email body. Arguments are app version, build, device model, and OS version.")
        case .mailComposerTitle:
            return String(localized: "feedback.mail.composer.title", defaultValue: "Feedback composer", bundle: bundle, locale: locale, comment: "Heading of the deterministic feedback composer used by UI tests.")
        case .mailRecipient:
            return String(localized: "feedback.mail.recipient", defaultValue: "To: %@", bundle: bundle, locale: locale, comment: "Support-email recipient summary. Argument is the recipient list.")
        case .mailAttachmentCount:
            return String(localized: "feedback.mail.attachment_count", defaultValue: "Diagnostic attachments: %lld", bundle: bundle, locale: locale, comment: "Number of diagnostic files attached to the support email.")
        case .mailMessageHeading:
            return String(localized: "feedback.mail.message.heading", defaultValue: "Editable message", bundle: bundle, locale: locale, comment: "Heading above the editable feedback message.")
        case .mailMessageLabel:
            return String(localized: "feedback.mail.message.label", defaultValue: "Feedback message", bundle: bundle, locale: locale, comment: "Accessibility label for the editable feedback message.")
        case .commonDone:
            return String(localized: "common.done", defaultValue: "Done", bundle: bundle, locale: locale, comment: "Completes and closes the current task.")
        case .packageRequiredViews:
            return String(localized: "package.illuminated_sign.guidance.required_views", defaultValue: "Capture the required views.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package guidance for required evidence views.")
        case .packageVisibleConditionsOnly:
            return String(localized: "package.illuminated_sign.guidance.visible_conditions_only", defaultValue: "Record only conditions visible in the evidence.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package limitation guidance.")
        case .packageAuthorizedPosition:
            return String(localized: "package.illuminated_sign.guidance.authorized_position", defaultValue: "Stand in an authorized position before taking a photo.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package safety guidance.")
        case .accountabilityHeading:
            return String(localized: "accountability.heading", defaultValue: "Accountability", bundle: bundle, locale: locale, comment: "Heading for the localized accountability projection in a report.")
        case .accountabilityParty:
            return String(localized: "accountability.party", defaultValue: "Party", bundle: bundle, locale: locale, comment: "Localized label for a service party in the accountability projection.")
        case .accountabilityRole:
            return String(localized: "accountability.role", defaultValue: "Site role", bundle: bundle, locale: locale, comment: "Localized label for a historical site role event.")
        case .accountabilityActor:
            return String(localized: "accountability.actor", defaultValue: "Responsible actor", bundle: bundle, locale: locale, comment: "Localized label for a locally captured responsible actor.")
        case .accountabilityQualification:
            return String(localized: "accountability.qualification", defaultValue: "Declared qualification", bundle: bundle, locale: locale, comment: "Localized label for a declared qualification snapshot.")
        case .accountabilitySignoff:
            return String(localized: "accountability.signoff", defaultValue: "Local response", bundle: bundle, locale: locale, comment: "Localized label for a local signoff assertion or disposition.")
        case .assetSemanticIlluminatedSignName:
            return String(localized: "asset.semantic.sign.illuminated.name", defaultValue: "Illuminated sign", bundle: bundle, locale: locale, comment: "Localized name for the bundled illuminated-sign semantic kind.")
        case .assetSemanticIlluminatedSignDescription:
            return String(localized: "asset.semantic.sign.illuminated.description", defaultValue: "Illuminated sign semantic kind", bundle: bundle, locale: locale, comment: "Localized description for the bundled illuminated-sign semantic kind.")
        case .assetSemanticHeading:
            return String(localized: "asset.semantic.heading", defaultValue: "Asset semantics", bundle: bundle, locale: locale, comment: "Heading for the local asset semantic and lifecycle projection.")
        case .assetSemanticKind:
            return String(localized: "asset.semantic.kind", defaultValue: "Semantic kind", bundle: bundle, locale: locale, comment: "Localized label for an accepted asset semantic kind.")
        case .assetSemanticProductIdentity:
            return String(localized: "asset.semantic.product_identity", defaultValue: "Product identity", bundle: bundle, locale: locale, comment: "Localized label for progressively disclosed product identifier attributes.")
        case .assetSemanticWorkSubjectScope:
            return String(localized: "asset.semantic.work_subject_scope", defaultValue: "Work subject scope", bundle: bundle, locale: locale, comment: "Localized label for the immutable subject scope captured by completed work.")
        case .assetSemanticLifecycle:
            return String(localized: "asset.semantic.lifecycle", defaultValue: "Lifecycle", bundle: bundle, locale: locale, comment: "Localized label for a human-recorded asset lifecycle history.")
        case .assetSemanticState:
            return String(localized: "asset.semantic.state", defaultValue: "Recorded state", bundle: bundle, locale: locale, comment: "Accessible label for an asset semantic state without operational claims.")
        case .assetSemanticUnknownState:
            return String(localized: "asset.semantic.state.unknown", defaultValue: "Unknown", bundle: bundle, locale: locale, comment: "Accessible text for an unknown or not-recorded semantic value.")
        case .assetSemanticDuplicateState:
            return String(localized: "asset.semantic.state.duplicate", defaultValue: "Duplicate value", bundle: bundle, locale: locale, comment: "Accessible text for a duplicate product identifier value.")
        case .assetSemanticRetiredState:
            return String(localized: "asset.semantic.state.retired", defaultValue: "Retired", bundle: bundle, locale: locale, comment: "Accessible text for a human-recorded retired lifecycle event.")
        case .assetSemanticReplacedState:
            return String(localized: "asset.semantic.state.replaced", defaultValue: "Replaced", bundle: bundle, locale: locale, comment: "Accessible text for a human-recorded replaced lifecycle event.")
        case .assetSemanticRecordedState:
            return String(localized: "asset.semantic.state.recorded", defaultValue: "Recorded", bundle: bundle, locale: locale, comment: "Accessible text for a fact explicitly recorded by a local actor.")
        case .authorityCriterionHeading:
            return String(localized: "authority.criterion.heading", defaultValue: "Authority and criteria", bundle: bundle, locale: locale, comment: "Heading for recorded authority and criterion facts.")
        case .authorityCriterionAuthoritySource:
            return String(localized: "authority.criterion.authority_source", defaultValue: "Authority source", bundle: bundle, locale: locale, comment: "Localized label for an authority source metadata record.")
        case .authorityCriterionApplicability:
            return String(localized: "authority.criterion.applicability", defaultValue: "Applicability", bundle: bundle, locale: locale, comment: "Localized label for a selected applicability disposition.")
        case .authorityCriterionApplicable:
            return String(localized: "authority.criterion.applicability.applicable", defaultValue: "Applicable", bundle: bundle, locale: locale, comment: "Accessible text for an applicable recorded context.")
        case .authorityCriterionNotApplicableWithReason:
            return String(localized: "authority.criterion.applicability.not_applicable_with_reason", defaultValue: "Not applicable with reason", bundle: bundle, locale: locale, comment: "Accessible text for a not-applicable disposition with its recorded reason.")
        case .authorityCriterionApplicabilityUnknown:
            return String(localized: "authority.criterion.applicability.unknown", defaultValue: "Unknown", bundle: bundle, locale: locale, comment: "Accessible text for an applicability disposition that remains unknown.")
        case .authorityCriterionConflictReviewRequired:
            return String(localized: "authority.criterion.applicability.conflict_review_required", defaultValue: "Conflict requires review", bundle: bundle, locale: locale, comment: "Accessible text for conflicting applicability sources awaiting review.")
        case .authorityCriterionApplicabilityUnsupported:
            return String(localized: "authority.criterion.applicability.unsupported", defaultValue: "Unsupported", bundle: bundle, locale: locale, comment: "Accessible text for an applicability context that is not supported.")
        case .authorityCriterionResult:
            return String(localized: "authority.criterion.result", defaultValue: "Screening result", bundle: bundle, locale: locale, comment: "Localized label for a recorded screening result.")
        case .authorityCriterionMeetsScreeningCriterion:
            return String(localized: "authority.criterion.result.meets_screening_criterion", defaultValue: "Meets screening criterion", bundle: bundle, locale: locale, comment: "Accessible text for a screening result that meets its stated criterion.")
        case .authorityCriterionDoesNotMeet:
            return String(localized: "authority.criterion.result.does_not_meet", defaultValue: "Does not meet screening criterion", bundle: bundle, locale: locale, comment: "Accessible text for a screening result that does not meet its stated criterion.")
        case .authorityCriterionInconclusive:
            return String(localized: "authority.criterion.result.inconclusive", defaultValue: "Inconclusive", bundle: bundle, locale: locale, comment: "Accessible text for a screening result that cannot be concluded.")
        case .authorityCriterionNotEvaluated:
            return String(localized: "authority.criterion.result.not_evaluated", defaultValue: "Not evaluated", bundle: bundle, locale: locale, comment: "Accessible text for a criterion that was not evaluated.")
        case .authorityCriterionSeverity:
            return String(localized: "authority.criterion.severity", defaultValue: "Severity", bundle: bundle, locale: locale, comment: "Localized label for a severity level within its recorded scale.")
        case .authorityCriterionMeasurementProtocol:
            return String(localized: "authority.criterion.measurement_protocol", defaultValue: "Measurement protocol", bundle: bundle, locale: locale, comment: "Localized label for the protocol governing a recorded measurement.")
        case .authorityCriterionTechnicalBasis:
            return String(localized: "authority.criterion.technical_basis", defaultValue: "Technical basis", bundle: bundle, locale: locale, comment: "Localized label for the technical basis disclosed with a recorded result.")
        case .authorityCriterionNextStep:
            return String(localized: "authority.criterion.next_step", defaultValue: "Next step", bundle: bundle, locale: locale, comment: "Localized label for the actionable next step accompanying an unresolved state.")
        case .authorityCriterionAssessedAgainst:
            return String(localized: "authority.criterion.assessed_against", defaultValue: "Assessed against", bundle: bundle, locale: locale, comment: "Localized wording for a report that states which basis was assessed against.")
        case .functionalRelationshipHeading:
            return String(localized: "functional.relationship.heading", defaultValue: "Functional relationships", bundle: bundle, locale: locale, comment: "Heading for recorded functional relationship facts.")
        case .functionalRelationshipType:
            return String(localized: "functional.relationship.type", defaultValue: "Relationship type", bundle: bundle, locale: locale, comment: "Localized label for the package-declared relationship type.")
        case .functionalRelationshipDirectedSourceToTarget:
            return String(localized: "functional.relationship.direction.source_to_target", defaultValue: "Source to target", bundle: bundle, locale: locale, comment: "Text label for a directed relationship from source to target.")
        case .functionalRelationshipSymmetric:
            return String(localized: "functional.relationship.direction.symmetric", defaultValue: "Symmetric", bundle: bundle, locale: locale, comment: "Text label for a symmetric relationship.")
        case .functionalRelationshipActiveState:
            return String(localized: "functional.relationship.state.active", defaultValue: "Active", bundle: bundle, locale: locale, comment: "Text label for an active relationship record.")
        case .functionalRelationshipEndedState:
            return String(localized: "functional.relationship.state.ended", defaultValue: "Ended", bundle: bundle, locale: locale, comment: "Text label for an ended relationship record.")
        case .functionalRelationshipSupersededState:
            return String(localized: "functional.relationship.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Text label for a superseded relationship record.")
        case .functionalRelationshipIncompleteState:
            return String(localized: "functional.relationship.state.incomplete", defaultValue: "Incomplete", bundle: bundle, locale: locale, comment: "Text label for an incomplete relationship readiness state.")
        case .functionalRelationshipBlockedState:
            return String(localized: "functional.relationship.state.blocked", defaultValue: "Blocked", bundle: bundle, locale: locale, comment: "Text label for a blocked relationship state.")
        case .functionalRelationshipMinimumNextRequirement:
            return String(localized: "functional.relationship.next_step.minimum_requirement", defaultValue: "Minimum requirement", bundle: bundle, locale: locale, comment: "Actionable label for the minimum next requirement for an incomplete record.")
        case .functionalRelationshipDescriptor:
            return String(localized: "functional.relationship.descriptor", defaultValue: "Descriptor", bundle: bundle, locale: locale, comment: "Localized label for a package relationship descriptor.")
        case .functionalRelationshipBounds:
            return String(localized: "functional.relationship.bounds", defaultValue: "Cardinality bounds", bundle: bundle, locale: locale, comment: "Localized label for source and target cardinality bounds.")
        case .functionalRelationshipSite:
            return String(localized: "functional.relationship.site", defaultValue: "Same-site policy", bundle: bundle, locale: locale, comment: "Localized label for the descriptor's Site policy.")
        case .functionalRelationshipCrossSiteState:
            return String(localized: "functional.relationship.site.cross_site", defaultValue: "Cross-site local", bundle: bundle, locale: locale, comment: "Text label for a recorded cross-Site relationship state.")
        case .evidenceVisibilityHeading:
            return String(localized: "evidence.visibility.heading", defaultValue: "Evidence visibility", bundle: bundle, locale: locale, comment: "Heading for recorded evidence visibility facts.")
        case .evidenceVisibilityAudience:
            return String(localized: "evidence.visibility.audience", defaultValue: "Audience", bundle: bundle, locale: locale, comment: "Localized label for the declared evidence audience.")
        case .evidenceVisibilityAudienceInternalReview:
            return String(localized: "evidence.visibility.audience.internal_review", defaultValue: "Internal review", bundle: bundle, locale: locale, comment: "Accessible text for the internal review audience.")
        case .evidenceVisibilityAudienceCustomerReport:
            return String(localized: "evidence.visibility.audience.customer_report", defaultValue: "Customer report", bundle: bundle, locale: locale, comment: "Accessible text for the customer report audience.")
        case .evidenceVisibilityAudienceExternalCollaborator:
            return String(localized: "evidence.visibility.audience.external_collaborator", defaultValue: "External collaborator", bundle: bundle, locale: locale, comment: "Accessible text for the external collaborator audience.")
        case .evidenceVisibilitySensitivity:
            return String(localized: "evidence.visibility.sensitivity", defaultValue: "Sensitivity", bundle: bundle, locale: locale, comment: "Localized label for the recorded evidence sensitivity.")
        case .evidenceVisibilitySensitivityRoutine:
            return String(localized: "evidence.visibility.sensitivity.routine", defaultValue: "Routine", bundle: bundle, locale: locale, comment: "Accessible text for routine evidence sensitivity.")
        case .evidenceVisibilitySensitivityRestricted:
            return String(localized: "evidence.visibility.sensitivity.restricted", defaultValue: "Restricted", bundle: bundle, locale: locale, comment: "Accessible text for restricted evidence sensitivity.")
        case .evidenceVisibilitySensitivityHighlyRestricted:
            return String(localized: "evidence.visibility.sensitivity.highly_restricted", defaultValue: "Highly restricted", bundle: bundle, locale: locale, comment: "Accessible text for highly restricted evidence sensitivity.")
        case .evidenceVisibilityIncluded:
            return String(localized: "evidence.visibility.state.included", defaultValue: "Included", bundle: bundle, locale: locale, comment: "Accessible text for evidence included in the audience projection.")
        case .evidenceVisibilityExcluded:
            return String(localized: "evidence.visibility.state.excluded", defaultValue: "Excluded", bundle: bundle, locale: locale, comment: "Accessible text for evidence excluded from the audience projection.")
        case .evidenceVisibilityOmitted:
            return String(localized: "evidence.visibility.state.omitted", defaultValue: "Omitted", bundle: bundle, locale: locale, comment: "Accessible text for evidence omitted from the audience projection.")
        case .evidenceVisibilityLimitation:
            return String(localized: "evidence.visibility.state.limitation", defaultValue: "Limitation", bundle: bundle, locale: locale, comment: "Accessible text for a recorded visibility limitation.")
        case .evidenceVisibilityUnknown:
            return String(localized: "evidence.visibility.state.unknown", defaultValue: "Unknown", bundle: bundle, locale: locale, comment: "Accessible text for an unknown visibility value.")
        case .evidenceVisibilityPreview:
            return String(localized: "evidence.visibility.preview", defaultValue: "Preview", bundle: bundle, locale: locale, comment: "Localized label for the mutable evidence projection preview.")
        case .evidenceVisibilityPreviewReady:
            return String(localized: "evidence.visibility.preview.ready", defaultValue: "Ready", bundle: bundle, locale: locale, comment: "Accessible text for a preview matching its recorded source.")
        case .evidenceVisibilityPreviewStale:
            return String(localized: "evidence.visibility.preview.stale", defaultValue: "Stale preview", bundle: bundle, locale: locale, comment: "Accessible text for a preview that no longer matches its recorded source.")
        case .evidenceVisibilityManifest:
            return String(localized: "evidence.visibility.manifest", defaultValue: "Assurance manifest", bundle: bundle, locale: locale, comment: "Localized label for the recorded claim and evidence manifest.")
        case .evidenceVisibilityAttestation:
            return String(localized: "evidence.visibility.attestation", defaultValue: "Attestation", bundle: bundle, locale: locale, comment: "Localized label for a purpose-bound local attestation record.")
        case .evidenceVisibilityAttestationPurpose:
            return String(localized: "evidence.visibility.attestation.purpose", defaultValue: "Purpose", bundle: bundle, locale: locale, comment: "Accessible text for the recorded attestation purpose.")
        case .evidenceVisibilityAttestationRecorded:
            return String(localized: "evidence.visibility.attestation.recorded", defaultValue: "Recorded", bundle: bundle, locale: locale, comment: "Accessible text for an attestation record that is current.")
        case .evidenceVisibilityAttestationSuperseded:
            return String(localized: "evidence.visibility.attestation.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for an attestation replaced by a later record.")
        case .evidenceVisibilityAttestationVoid:
            return String(localized: "evidence.visibility.attestation.void", defaultValue: "Void", bundle: bundle, locale: locale, comment: "Accessible text for an attestation marked void in the local record.")
        case .evidenceVisibilityNextStep:
            return String(localized: "evidence.visibility.next_step", defaultValue: "Next step", bundle: bundle, locale: locale, comment: "Actionable label for the next step accompanying a limited projection.")
        case .inspectionReviewHeading:
            return String(localized: "inspection.review.heading", defaultValue: "Inspection review", bundle: bundle, locale: locale, comment: "Heading for recorded inspection review facts.")
        case .inspectionReviewState:
            return String(localized: "inspection.review.state", defaultValue: "Review state", bundle: bundle, locale: locale, comment: "Localized label for the recorded inspection review state.")
        case .inspectionReviewDraft:
            return String(localized: "inspection.review.state.draft", defaultValue: "Draft", bundle: bundle, locale: locale, comment: "Accessible text for a review still in draft state.")
        case .inspectionReviewFieldComplete:
            return String(localized: "inspection.review.state.field_complete", defaultValue: "Field complete", bundle: bundle, locale: locale, comment: "Accessible text for a review with its field record complete.")
        case .inspectionReviewReadyForReview:
            return String(localized: "inspection.review.state.ready_for_review", defaultValue: "Ready for review", bundle: bundle, locale: locale, comment: "Accessible text for a review ready for a recorded review decision.")
        case .inspectionReviewChangesRequested:
            return String(localized: "inspection.review.state.changes_requested", defaultValue: "Changes requested", bundle: bundle, locale: locale, comment: "Accessible text for a review with recorded changes requested.")
        case .inspectionReviewAccepted:
            return String(localized: "inspection.review.state.accepted", defaultValue: "Accepted", bundle: bundle, locale: locale, comment: "Accessible text for a review with an accepted recorded disposition.")
        case .inspectionReviewFinalized:
            return String(localized: "inspection.review.state.finalized", defaultValue: "Finalized", bundle: bundle, locale: locale, comment: "Accessible text for a review with a recorded final state.")
        case .inspectionReviewAmended:
            return String(localized: "inspection.review.state.amended", defaultValue: "Amended", bundle: bundle, locale: locale, comment: "Accessible text for a review amended in a later recorded revision.")
        case .inspectionReviewSuperseded:
            return String(localized: "inspection.review.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for a review superseded by a later recorded subject.")
        case .inspectionReviewDisposition:
            return String(localized: "inspection.review.disposition", defaultValue: "Review disposition", bundle: bundle, locale: locale, comment: "Localized label for a recorded review disposition.")
        case .inspectionReviewDispositionChangesRequested:
            return String(localized: "inspection.review.disposition.changes_requested", defaultValue: "Changes requested", bundle: bundle, locale: locale, comment: "Accessible text for a disposition that records requested changes.")
        case .inspectionReviewDispositionAccepted:
            return String(localized: "inspection.review.disposition.accepted", defaultValue: "Accepted", bundle: bundle, locale: locale, comment: "Accessible text for an accepted recorded review disposition.")
        case .inspectionReviewChangeRequest:
            return String(localized: "inspection.review.change_request", defaultValue: "Change request", bundle: bundle, locale: locale, comment: "Localized label for an immutable recorded change request.")
        case .inspectionReviewChangeRequestState:
            return String(localized: "inspection.review.change_request.state", defaultValue: "Change request state", bundle: bundle, locale: locale, comment: "Localized label for the recorded change request state.")
        case .inspectionReviewChangeRequestOpen:
            return String(localized: "inspection.review.change_request.state.open", defaultValue: "Open", bundle: bundle, locale: locale, comment: "Accessible text for an open recorded change request.")
        case .inspectionReviewChangeRequestResolved:
            return String(localized: "inspection.review.change_request.state.resolved", defaultValue: "Resolved", bundle: bundle, locale: locale, comment: "Accessible text for a resolved recorded change request.")
        case .inspectionReviewChangeRequestWithdrawn:
            return String(localized: "inspection.review.change_request.state.withdrawn", defaultValue: "Withdrawn", bundle: bundle, locale: locale, comment: "Accessible text for a withdrawn recorded change request.")
        case .inspectionReviewChangeRequestSuperseded:
            return String(localized: "inspection.review.change_request.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for a change request superseded by a later record.")
        case .inspectionReviewChangeRequestResolution:
            return String(localized: "inspection.review.change_request.resolution", defaultValue: "Change request resolution", bundle: bundle, locale: locale, comment: "Localized label for the recorded resolution of a change request.")
        case .inspectionReviewChangeRequestResolutionFulfilled:
            return String(localized: "inspection.review.change_request.resolution.fulfilled", defaultValue: "Fulfilled", bundle: bundle, locale: locale, comment: "Accessible text for a fulfilled recorded change request.")
        case .inspectionReviewChangeRequestResolutionWithdrawnWithReason:
            return String(localized: "inspection.review.change_request.resolution.withdrawn_with_reason", defaultValue: "Withdrawn with reason", bundle: bundle, locale: locale, comment: "Accessible text for a change request withdrawn with a recorded reason.")
        case .inspectionReviewChangeRequestResolutionSuperseded:
            return String(localized: "inspection.review.change_request.resolution.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for a resolution superseded by a later record.")
        case .inspectionReviewCorrectiveAction:
            return String(localized: "inspection.review.corrective_action", defaultValue: "Corrective action", bundle: bundle, locale: locale, comment: "Localized label for a recorded corrective action.")
        case .inspectionReviewCorrectiveActionState:
            return String(localized: "inspection.review.corrective_action.state", defaultValue: "Corrective action state", bundle: bundle, locale: locale, comment: "Localized label for the recorded corrective action state.")
        case .inspectionReviewCorrectiveActionOpen:
            return String(localized: "inspection.review.corrective_action.state.open", defaultValue: "Open", bundle: bundle, locale: locale, comment: "Accessible text for an open recorded corrective action.")
        case .inspectionReviewCorrectiveActionInProgress:
            return String(localized: "inspection.review.corrective_action.state.in_progress", defaultValue: "In progress", bundle: bundle, locale: locale, comment: "Accessible text for a corrective action in progress.")
        case .inspectionReviewCorrectiveActionAwaitingVerification:
            return String(localized: "inspection.review.corrective_action.state.awaiting_verification", defaultValue: "Awaiting recorded check", bundle: bundle, locale: locale, comment: "Accessible text for a corrective action awaiting a recorded check.")
        case .inspectionReviewCorrectiveActionClosed:
            return String(localized: "inspection.review.corrective_action.state.closed", defaultValue: "Closed", bundle: bundle, locale: locale, comment: "Accessible text for a corrective action closed with its recorded evidence.")
        case .inspectionReviewCorrectiveActionReopened:
            return String(localized: "inspection.review.corrective_action.state.reopened", defaultValue: "Reopened", bundle: bundle, locale: locale, comment: "Accessible text for a corrective action reopened by a recorded trigger.")
        case .inspectionReviewCorrectiveActionSuperseded:
            return String(localized: "inspection.review.corrective_action.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for a corrective action superseded by a later record.")
        case .inspectionReviewNextStep:
            return String(localized: "inspection.review.next_step", defaultValue: "Next step", bundle: bundle, locale: locale, comment: "Actionable label for the next recorded step accompanying a review state.")
        case .inspectionReviewMinimumNextRequirement:
            return String(localized: "inspection.review.next_step.minimum_requirement", defaultValue: "Minimum requirement", bundle: bundle, locale: locale, comment: "Actionable label for the minimum recorded requirement before the next review step.")
        case .workPacketHeading:
            return String(localized: "work.packet.heading", defaultValue: "Work packet", bundle: bundle, locale: locale, comment: "Heading for recorded local packet coordination facts.")
        case .workPacketManifest:
            return String(localized: "work.packet.manifest", defaultValue: "Packet manifest", bundle: bundle, locale: locale, comment: "Localized label for an immutable bounded packet manifest.")
        case .workPacketItem:
            return String(localized: "work.packet.item", defaultValue: "Work item", bundle: bundle, locale: locale, comment: "Localized label for one bounded packet item.")
        case .workPacketManifestState:
            return String(localized: "work.packet.manifest.state", defaultValue: "Manifest state", bundle: bundle, locale: locale, comment: "Localized label for the recorded packet manifest state.")
        case .workPacketManifestDraft:
            return String(localized: "work.packet.manifest.state.draft", defaultValue: "Draft", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest in draft state.")
        case .workPacketManifestReady:
            return String(localized: "work.packet.manifest.state.ready", defaultValue: "Ready", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest ready for local work.")
        case .workPacketManifestInvalid:
            return String(localized: "work.packet.manifest.state.invalid", defaultValue: "Invalid", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest that failed recorded validation.")
        case .workPacketManifestReplayed:
            return String(localized: "work.packet.manifest.state.replayed", defaultValue: "Replayed", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest with a recorded replay.")
        case .workPacketManifestConflicted:
            return String(localized: "work.packet.manifest.state.conflicted", defaultValue: "Conflict recorded", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest with a recorded conflict.")
        case .workPacketManifestSuperseded:
            return String(localized: "work.packet.manifest.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for a packet manifest superseded by a later record.")
        case .workPacketClaim:
            return String(localized: "work.packet.claim", defaultValue: "Item claim", bundle: bundle, locale: locale, comment: "Localized label for a recorded local item claim.")
        case .workPacketClaimState:
            return String(localized: "work.packet.claim.state", defaultValue: "Claim state", bundle: bundle, locale: locale, comment: "Localized label for the recorded item claim state.")
        case .workPacketClaimUnclaimed:
            return String(localized: "work.packet.claim.state.unclaimed", defaultValue: "Unclaimed", bundle: bundle, locale: locale, comment: "Accessible text for an item with no recorded claim.")
        case .workPacketClaimClaimed:
            return String(localized: "work.packet.claim.state.claimed", defaultValue: "Claimed", bundle: bundle, locale: locale, comment: "Accessible text for an item with a recorded claim.")
        case .workPacketClaimReleased:
            return String(localized: "work.packet.claim.state.released", defaultValue: "Released", bundle: bundle, locale: locale, comment: "Accessible text for an item with a recorded claim release.")
        case .workPacketClaimConflicted:
            return String(localized: "work.packet.claim.state.conflicted", defaultValue: "Conflict recorded", bundle: bundle, locale: locale, comment: "Accessible text for an item claim with a recorded conflict.")
        case .workPacketLease:
            return String(localized: "work.packet.lease", defaultValue: "Work lease", bundle: bundle, locale: locale, comment: "Localized label for a recorded local work lease.")
        case .workPacketLeaseState:
            return String(localized: "work.packet.lease.state", defaultValue: "Lease state", bundle: bundle, locale: locale, comment: "Localized label for the recorded work lease state.")
        case .workPacketLeaseActive:
            return String(localized: "work.packet.lease.state.active", defaultValue: "Active", bundle: bundle, locale: locale, comment: "Accessible text for an active recorded work lease.")
        case .workPacketLeaseExpiring:
            return String(localized: "work.packet.lease.state.expiring", defaultValue: "Expiring", bundle: bundle, locale: locale, comment: "Accessible text for a work lease approaching its recorded expiry.")
        case .workPacketLeaseExpired:
            return String(localized: "work.packet.lease.state.expired", defaultValue: "Expired", bundle: bundle, locale: locale, comment: "Accessible text for a work lease past its recorded expiry.")
        case .workPacketLeaseReclaimed:
            return String(localized: "work.packet.lease.state.reclaimed", defaultValue: "Reclaimed", bundle: bundle, locale: locale, comment: "Accessible text for a work lease reclaimed by a recorded local action.")
        case .workPacketRelease:
            return String(localized: "work.packet.release", defaultValue: "Item release", bundle: bundle, locale: locale, comment: "Localized label for a recorded local item release.")
        case .workPacketReleaseState:
            return String(localized: "work.packet.release.state", defaultValue: "Release state", bundle: bundle, locale: locale, comment: "Localized label for the recorded item release state.")
        case .workPacketReleaseRecorded:
            return String(localized: "work.packet.release.state.recorded", defaultValue: "Recorded", bundle: bundle, locale: locale, comment: "Accessible text for an item release recorded in the local history.")
        case .workPacketReleaseAvailable:
            return String(localized: "work.packet.release.state.available", defaultValue: "Available", bundle: bundle, locale: locale, comment: "Accessible text for an item available after a recorded release.")
        case .workPacketReleaseSuperseded:
            return String(localized: "work.packet.release.state.superseded", defaultValue: "Superseded", bundle: bundle, locale: locale, comment: "Accessible text for an item release superseded by a later record.")
        case .workPacketHandoff:
            return String(localized: "work.packet.handoff", defaultValue: "Packet handoff", bundle: bundle, locale: locale, comment: "Localized label for a recorded local packet handoff.")
        case .workPacketHandoffState:
            return String(localized: "work.packet.handoff.state", defaultValue: "Handoff state", bundle: bundle, locale: locale, comment: "Localized label for the recorded packet handoff state.")
        case .workPacketHandoffPending:
            return String(localized: "work.packet.handoff.state.pending", defaultValue: "Pending", bundle: bundle, locale: locale, comment: "Accessible text for a packet handoff awaiting a recorded result.")
        case .workPacketHandoffAccepted:
            return String(localized: "work.packet.handoff.state.accepted", defaultValue: "Accepted", bundle: bundle, locale: locale, comment: "Accessible text for a packet handoff with an accepted recorded result.")
        case .workPacketHandoffRejected:
            return String(localized: "work.packet.handoff.state.rejected", defaultValue: "Rejected", bundle: bundle, locale: locale, comment: "Accessible text for a packet handoff with a rejected recorded result.")
        case .workPacketHandoffCompleted:
            return String(localized: "work.packet.handoff.state.completed", defaultValue: "Completed", bundle: bundle, locale: locale, comment: "Accessible text for a packet handoff with a completed recorded result.")
        case .workPacketConflict:
            return String(localized: "work.packet.conflict", defaultValue: "Packet conflict", bundle: bundle, locale: locale, comment: "Localized label for a recorded packet coordination conflict.")
        case .workPacketConflictState:
            return String(localized: "work.packet.conflict.state", defaultValue: "Conflict state", bundle: bundle, locale: locale, comment: "Localized label for the recorded packet conflict state.")
        case .workPacketConflictDetected:
            return String(localized: "work.packet.conflict.state.detected", defaultValue: "Detected", bundle: bundle, locale: locale, comment: "Accessible text for a packet conflict detected in the local record.")
        case .workPacketConflictQuarantined:
            return String(localized: "work.packet.conflict.state.quarantined", defaultValue: "Quarantined", bundle: bundle, locale: locale, comment: "Accessible text for a conflicting packet result held for review.")
        case .workPacketConflictReviewRequired:
            return String(localized: "work.packet.conflict.state.review_required", defaultValue: "Review required", bundle: bundle, locale: locale, comment: "Accessible text for a packet conflict requiring a recorded review.")
        case .workPacketConflictResolved:
            return String(localized: "work.packet.conflict.state.resolved", defaultValue: "Resolved", bundle: bundle, locale: locale, comment: "Accessible text for a packet conflict with a recorded resolution.")
        case .workPacketExpiry:
            return String(localized: "work.packet.expiry", defaultValue: "Lease expiry", bundle: bundle, locale: locale, comment: "Localized label for the recorded lease expiry condition.")
        case .workPacketExpiryState:
            return String(localized: "work.packet.expiry.state", defaultValue: "Expiry state", bundle: bundle, locale: locale, comment: "Localized label for the recorded packet expiry state.")
        case .workPacketExpiryNotExpired:
            return String(localized: "work.packet.expiry.state.not_expired", defaultValue: "Not expired", bundle: bundle, locale: locale, comment: "Accessible text for a lease whose recorded expiry has not passed.")
        case .workPacketExpiryExpiring:
            return String(localized: "work.packet.expiry.state.expiring", defaultValue: "Expiring", bundle: bundle, locale: locale, comment: "Accessible text for a lease approaching its recorded expiry.")
        case .workPacketExpiryExpired:
            return String(localized: "work.packet.expiry.state.expired", defaultValue: "Expired", bundle: bundle, locale: locale, comment: "Accessible text for a lease past its recorded expiry.")
        case .workPacketReplay:
            return String(localized: "work.packet.replay", defaultValue: "Packet replay", bundle: bundle, locale: locale, comment: "Localized label for a recorded local packet replay.")
        case .workPacketReplayState:
            return String(localized: "work.packet.replay.state", defaultValue: "Replay state", bundle: bundle, locale: locale, comment: "Localized label for the recorded packet replay state.")
        case .workPacketReplayPending:
            return String(localized: "work.packet.replay.state.pending", defaultValue: "Pending", bundle: bundle, locale: locale, comment: "Accessible text for a packet replay awaiting a recorded result.")
        case .workPacketReplayApplied:
            return String(localized: "work.packet.replay.state.applied", defaultValue: "Applied", bundle: bundle, locale: locale, comment: "Accessible text for a packet replay with a recorded application.")
        case .workPacketReplayIdempotent:
            return String(localized: "work.packet.replay.state.idempotent", defaultValue: "Already applied", bundle: bundle, locale: locale, comment: "Accessible text for a packet replay recognized as already applied.")
        case .workPacketReplayQuarantined:
            return String(localized: "work.packet.replay.state.quarantined", defaultValue: "Quarantined", bundle: bundle, locale: locale, comment: "Accessible text for a packet replay held for recorded review.")
        case .workPacketNextStep:
            return String(localized: "work.packet.next_step", defaultValue: "Next step", bundle: bundle, locale: locale, comment: "Actionable label for the next recorded packet-coordination step.")
        case .workPacketMinimumNextRequirement:
            return String(localized: "work.packet.next_step.minimum_requirement", defaultValue: "Minimum requirement", bundle: bundle, locale: locale, comment: "Actionable label for the minimum recorded requirement before the next step.")
        case .measurementIntegrityHeading:
            return MeasurementIntegrityLocalizationKeyV1.heading.englishDefaultValue
        case .measurementIntegrityInstrument:
            return MeasurementIntegrityLocalizationKeyV1.instrument.englishDefaultValue
        case .measurementIntegrityInstrumentKind:
            return MeasurementIntegrityLocalizationKeyV1.instrumentKind.englishDefaultValue
        case .measurementIntegrityInstrumentKindMeasuring:
            return MeasurementIntegrityLocalizationKeyV1.instrumentKindMeasuring.englishDefaultValue
        case .measurementIntegrityInstrumentKindReference:
            return MeasurementIntegrityLocalizationKeyV1.instrumentKindReference.englishDefaultValue
        case .measurementIntegrityInstrumentKindOther:
            return MeasurementIntegrityLocalizationKeyV1.instrumentKindOther.englishDefaultValue
        case .measurementIntegrityInstrumentLifecycle:
            return MeasurementIntegrityLocalizationKeyV1.instrumentLifecycle.englishDefaultValue
        case .measurementIntegrityInstrumentLifecycleActive:
            return MeasurementIntegrityLocalizationKeyV1.instrumentLifecycleActive.englishDefaultValue
        case .measurementIntegrityInstrumentLifecycleOutOfService:
            return MeasurementIntegrityLocalizationKeyV1.instrumentLifecycleOutOfService.englishDefaultValue
        case .measurementIntegrityInstrumentLifecycleRetired:
            return MeasurementIntegrityLocalizationKeyV1.instrumentLifecycleRetired.englishDefaultValue
        case .measurementIntegrityCalibration:
            return MeasurementIntegrityLocalizationKeyV1.calibration.englishDefaultValue
        case .measurementIntegrityCalibrationStatus:
            return MeasurementIntegrityLocalizationKeyV1.calibrationStatus.englishDefaultValue
        case .measurementIntegrityCalibrationNotRequired:
            return MeasurementIntegrityLocalizationKeyV1.calibrationNotRequired.englishDefaultValue
        case .measurementIntegrityCalibrationCurrent:
            return MeasurementIntegrityLocalizationKeyV1.calibrationCurrent.englishDefaultValue
        case .measurementIntegrityCalibrationExpired:
            return MeasurementIntegrityLocalizationKeyV1.calibrationExpired.englishDefaultValue
        case .measurementIntegrityCalibrationUnknown:
            return MeasurementIntegrityLocalizationKeyV1.calibrationUnknown.englishDefaultValue
        case .measurementIntegrityCalibrationOutOfService:
            return MeasurementIntegrityLocalizationKeyV1.calibrationOutOfService.englishDefaultValue
        case .measurementIntegrityCalibrationBasis:
            return MeasurementIntegrityLocalizationKeyV1.calibrationBasis.englishDefaultValue
        case .measurementIntegrityCalibrationBasisDeclared:
            return MeasurementIntegrityLocalizationKeyV1.calibrationBasisDeclared.englishDefaultValue
        case .measurementIntegrityCalibrationBasisEvidence:
            return MeasurementIntegrityLocalizationKeyV1.calibrationBasisEvidence.englishDefaultValue
        case .measurementIntegrityCalibrationBasisLocal:
            return MeasurementIntegrityLocalizationKeyV1.calibrationBasisLocal.englishDefaultValue
        case .measurementIntegrityCalibrationBasisUnknown:
            return MeasurementIntegrityLocalizationKeyV1.calibrationBasisUnknown.englishDefaultValue
        case .measurementIntegrityCapture:
            return MeasurementIntegrityLocalizationKeyV1.capture.englishDefaultValue
        case .measurementIntegrityCaptureValue:
            return MeasurementIntegrityLocalizationKeyV1.captureValue.englishDefaultValue
        case .measurementIntegrityCaptureUnit:
            return MeasurementIntegrityLocalizationKeyV1.captureUnit.englishDefaultValue
        case .measurementIntegrityCaptureSource:
            return MeasurementIntegrityLocalizationKeyV1.captureSource.englishDefaultValue
        case .measurementIntegrityCaptureSourceManual:
            return MeasurementIntegrityLocalizationKeyV1.captureSourceManual.englishDefaultValue
        case .measurementIntegrityCaptureSourceLocalObservation:
            return MeasurementIntegrityLocalizationKeyV1.captureSourceLocalObservation.englishDefaultValue
        case .measurementIntegritySeries:
            return MeasurementIntegrityLocalizationKeyV1.series.englishDefaultValue
        case .measurementIntegritySeriesState:
            return MeasurementIntegrityLocalizationKeyV1.seriesState.englishDefaultValue
        case .measurementIntegritySeriesOpen:
            return MeasurementIntegrityLocalizationKeyV1.seriesOpen.englishDefaultValue
        case .measurementIntegritySeriesFinalized:
            return MeasurementIntegrityLocalizationKeyV1.seriesFinalized.englishDefaultValue
        case .measurementIntegrityProtocol:
            return MeasurementIntegrityLocalizationKeyV1.`protocol`.englishDefaultValue
        case .measurementIntegrityQuality:
            return MeasurementIntegrityLocalizationKeyV1.quality.englishDefaultValue
        case .measurementIntegrityQualityResult:
            return MeasurementIntegrityLocalizationKeyV1.qualityResult.englishDefaultValue
        case .measurementIntegrityQualityClear:
            return MeasurementIntegrityLocalizationKeyV1.qualityClear.englishDefaultValue
        case .measurementIntegrityQualityReviewRequired:
            return MeasurementIntegrityLocalizationKeyV1.qualityReviewRequired.englishDefaultValue
        case .measurementIntegrityQualityOverridden:
            return MeasurementIntegrityLocalizationKeyV1.qualityOverridden.englishDefaultValue
        case .measurementIntegrityQualityReason:
            return MeasurementIntegrityLocalizationKeyV1.qualityReason.englishDefaultValue
        case .measurementIntegrityQualityReasonDeclaredChecksClear:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonDeclaredChecksClear.englishDefaultValue
        case .measurementIntegrityQualityReasonCalibrationNotRequired:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonCalibrationNotRequired.englishDefaultValue
        case .measurementIntegrityQualityReasonCalibrationExpired:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonCalibrationExpired.englishDefaultValue
        case .measurementIntegrityQualityReasonCalibrationUnknown:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonCalibrationUnknown.englishDefaultValue
        case .measurementIntegrityQualityReasonInstrumentOutOfService:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonInstrumentOutOfService.englishDefaultValue
        case .measurementIntegrityQualityReasonMissingUncertainty:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonMissingUncertainty.englishDefaultValue
        case .measurementIntegrityQualityReasonUncertaintyCrossesBoundary:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonUncertaintyCrossesBoundary.englishDefaultValue
        case .measurementIntegrityQualityReasonIncompleteSampleSet:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonIncompleteSampleSet.englishDefaultValue
        case .measurementIntegrityQualityReasonDuplicateSample:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonDuplicateSample.englishDefaultValue
        case .measurementIntegrityQualityReasonRetainedOutlier:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonRetainedOutlier.englishDefaultValue
        case .measurementIntegrityQualityReasonObservationLimitation:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonObservationLimitation.englishDefaultValue
        case .measurementIntegrityQualityReasonHumanOverride:
            return MeasurementIntegrityLocalizationKeyV1.qualityReasonHumanOverride.englishDefaultValue
        case .measurementIntegrityNextStep:
            return MeasurementIntegrityLocalizationKeyV1.nextStep.englishDefaultValue
        case .privacyTransformHeading,
             .privacyTransformRedactionDeclaration,
             .privacyTransformDerivative,
             .privacyTransformDerivativeOnly,
             .privacyTransformReview,
             .privacyTransformReviewApproved,
             .privacyTransformReviewRejected,
             .privacyTransformFreshness,
             .privacyTransformFreshnessCurrent,
             .privacyTransformProjection,
             .privacyTransformProjectionAllowed,
             .privacyTransformProjectionDenied,
             .privacyTransformDenialMissingReview,
             .privacyTransformDenialRejected,
             .privacyTransformDenialStale,
             .privacyTransformDenialWrongAudience,
             .privacyTransformDenialWrongPolicy,
             .privacyTransformDenialSourceChanged,
             .privacyTransformDenialDigestMismatch,
             .privacyTransformDenialMetadataNotSanitized,
             .privacyTransformOriginalAccessSeparate,
             .privacyTransformNextStep:
            guard let privacyTransformKey = PrivacyTransformLocalizationKeyV1(
                rawValue: key.rawValue
            ) else {
                preconditionFailure("Declared privacy-transform localization mapping is incomplete.")
            }
            return privacyTransformKey.englishDefaultValue
        case .clientCapabilityHeading,
             .clientCapabilityAdmission,
             .clientCapabilityAdmissionReadWrite,
             .clientCapabilityAdmissionReadOnly,
             .clientCapabilityAdmissionMigrationRequired,
             .clientCapabilityAdmissionQuarantine,
             .clientCapabilityAdmissionReject,
             .clientCapabilityReason,
             .clientCapabilityReasonExactMatch,
             .clientCapabilityReasonReadOnlyCompatibility,
             .clientCapabilityReasonMigrationAvailable,
             .clientCapabilityReasonUnsupportedRequiredRange,
             .clientCapabilityReasonUnknownCapability,
             .clientCapabilityReasonPackageWithdrawn,
             .clientCapabilityReasonPackageQuarantined,
             .clientCapabilityReasonPackageSuperseded,
             .clientCapabilityReasonDigestMismatch,
             .clientCapabilityReasonStalePolicy,
             .clientCapabilityReasonOperationBlocked,
             .packageLifecycleHeading,
             .packageLifecycleState,
             .packageLifecycleStateActive,
             .packageLifecycleStateDeprecated,
             .packageLifecycleStateWithdrawn,
             .packageLifecycleStateQuarantined,
             .packageLifecycleStateSuperseded,
             .packageLifecycleOperation,
             .packageLifecycleOperationStart,
             .packageLifecycleOperationResume,
             .packageLifecycleOperationFinalize,
             .packageLifecycleOperationAmend,
             .packageLifecycleOperationView,
             .packageLifecycleOperationExport,
             .packageLifecycleOperationRestore,
             .packageLifecycleOperationReplay,
             .packageLifecycleOperationUpgradeDraft,
             .packageLifecycleHistoricExport,
             .packageLifecycleWithdrawal,
             .packageLifecycleBlocked,
             .clientCapabilityNextStep:
            guard let clientCapabilityKey = ClientCapabilityLocalizationKeyV1(
                rawValue: key.rawValue
            ) else {
                preconditionFailure("Declared client-capability localization mapping is incomplete.")
            }
            return clientCapabilityKey.englishDefaultValue
        case .fieldReferenceHeading,
             .fieldReferenceProvenance,
             .fieldReferencePack,
             .fieldReferenceKind,
             .fieldReferenceKindSOP,
             .fieldReferenceKindManual,
             .fieldReferenceKindDrawing,
             .fieldReferenceKindSpecification,
             .fieldReferenceSemanticVersion,
             .fieldReferenceRelease,
             .fieldReferenceReleaseActive,
             .fieldReferenceReleaseRevoked,
             .fieldReferenceBinding,
             .fieldReferenceSubject,
             .fieldReferenceSubjectWorkPacket,
             .fieldReferenceSubjectRoundSession,
             .fieldReferenceSubjectActive,
             .fieldReferenceSubjectFinalized,
             .fieldReferenceProvenanceKind,
             .fieldReferenceProvenanceLicensed,
             .fieldReferenceProvenanceSynthetic,
             .fieldReferenceLicenseScope,
             .fieldReferenceLicenseLocalUseOnly,
             .fieldReferenceLicenseCitationAllowed,
             .fieldReferenceLicenseCitationAndExportAllowed,
             .fieldReferenceLicenseRestricted,
             .fieldReferenceAvailability,
             .fieldReferenceAvailabilityReadyOffline,
             .fieldReferenceAvailabilityMissingBytes,
             .fieldReferenceAvailabilityExpired,
             .fieldReferenceAvailabilityRevoked,
             .fieldReferenceAvailabilitySuperseded,
             .fieldReferenceAvailabilityStaleBinding,
             .fieldReferenceAvailabilityProtectedDataUnavailable,
             .fieldReferenceAvailabilityUnavailable,
             .fieldReferenceRequiredContent,
             .fieldReferenceMissingContent,
             .fieldReferenceNextStep:
            guard let fieldReferenceKey = FieldReferenceLocalizationKeyV1(
                rawValue: key.rawValue
            ) else {
                preconditionFailure("Declared field-reference localization mapping is incomplete.")
            }
            return fieldReferenceKey.englishDefaultValue
        case .accessibleDocumentScreen,
             .accessibleDocumentHeading,
             .accessibleDocumentNode,
             .accessibleDocumentRole,
             .accessibleDocumentRoleDocument,
             .accessibleDocumentRoleSection,
             .accessibleDocumentRoleHeading,
             .accessibleDocumentRoleParagraph,
             .accessibleDocumentRoleList,
             .accessibleDocumentRoleListItem,
             .accessibleDocumentRoleTable,
             .accessibleDocumentRoleTableRow,
             .accessibleDocumentRoleTableHeader,
             .accessibleDocumentRoleTableCell,
             .accessibleDocumentRoleFigure,
             .accessibleDocumentRoleEvidenceLink,
             .accessibleDocumentRoleNote,
             .accessibleDocumentAlternateText,
             .accessibleDocumentAlternateTextProvenance,
             .accessibleDocumentAlternateTextAuthoredForSource,
             .accessibleDocumentAlternateTextSourceCaption,
             .accessibleDocumentAlternateTextNotProvided,
             .accessibleDocumentDecorativeFigure,
             .accessibleDocumentDescribedFigure,
             .accessibleDocumentAssessment,
             .accessibleDocumentAssessmentInternalPass,
             .accessibleDocumentAssessmentInternalFail,
             .accessibleDocumentAssessmentIncomplete,
             .accessibleDocumentAssessmentExternallyProved,
             .accessibleDocumentEvidence,
             .accessibleDocumentEvidenceLimited,
             .accessibleDocumentClaimBoundary,
             .accessibleDocumentNextStep:
            guard let accessibleDocumentKey = AccessibleDocumentLocalizationKeyV1(
                rawValue: key.rawValue
            ) else {
                preconditionFailure("Declared accessible-document localization mapping is incomplete.")
            }
            return accessibleDocumentKey.englishDefaultValue
        case .poseHeading,
             .poseAxis,
             .poseCurrent,
             .poseHistory,
             .poseReferenceFrame,
             .poseReferenceTrue,
             .poseReferenceMagnetic,
             .poseReferencePlanRelative,
             .poseReferenceUnknown,
             .poseObservation,
             .poseObserved,
             .poseNotObserved,
             .poseManualFallback,
             .poseUncertainty,
             .poseUncertaintyKnown,
             .poseUncertaintyUnknown,
             .poseNotObservedReason,
             .poseReasonNotYetObserved,
             .poseReasonPhysicalMove,
             .poseReasonPlanFrameLost,
             .poseReasonObscured,
             .poseReasonSourceUnavailable,
             .poseReasonUserDeclined,
             .poseCurrentTip,
             .poseHistoryFrozen,
             .poseRebasePreview,
             .posePreviewNotApplied,
             .poseReviewRequired,
             .poseAzimuth,
             .poseElevation,
             .poseHorizontalUncertainty,
             .poseVerticalUncertainty,
             .poseRecordedSource,
             .poseClaimBoundary,
             .poseNextStep,
             .poseMissing:
            guard let poseKey = C37PoseLocalizationKeyV1(rawValue: key.rawValue) else {
                preconditionFailure("Declared pose localization mapping is incomplete.")
            }
            return poseKey.englishDefaultValue
        case .lightingSystemHeading,
             .lightingTopology,
             .lightingZones,
             .lightingControlGroups,
             .lightingLuminaires,
             .lightingObservationHeading,
             .lightingObservationRecorded,
             .lightingIssueRecorded,
             .lightingIssueOpen,
             .lightingIssueResolved,
             .lightingIssueSuperseded,
             .lightingMeasurementHeading,
             .lightingIlluminance,
             .lightingCalibration,
             .lightingClaimObserved,
             .lightingClaimMeasured,
             .lightingClaimDerived,
             .lightingClaimCriterion,
             .lightingClaimExternal,
             .lightingClaimUnavailable,
             .lightingSafetyStop,
             .lightingSafetyNextStep,
             .lightingClaimBoundary,
             .lightingHistoryFrozen,
             .lightingManualOffline:
            guard let lightingKey = C31LightingLocalizationKeyV1(rawValue: key.rawValue) else {
                preconditionFailure("Declared lighting localization mapping is incomplete.")
            }
            return lightingKey.englishDefaultValue
        case .operationalContactDirections,
             .operationalContactCall,
             .operationalContactText,
             .operationalContactEmail,
             .operationalContactOpensSystemApp,
             .operationalContactHandedOff,
             .operationalContactTargetMissing,
             .operationalContactTargetStale,
             .operationalContactTargetInvalid,
             .operationalContactSystemUnavailable,
             .operationalContactSystemRejected,
             .operationalContactCancelled,
             .operationalContactClaimBoundary:
            guard let operationalContactKey = OperationalContactLocalizationKeyV1(
                rawValue: key.rawValue
            ) else {
                preconditionFailure("Declared operational-contact localization mapping is incomplete.")
            }
            return operationalContactLocalized(operationalContactKey, bundle: bundle)
        }
    }

    static func formattedInteger(_ value: Int, regionSource: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = englishPresentationLocale(regionSource)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formattedLength(
        _ measurement: Measurement<UnitLength>, regionSource: Locale = .current
    ) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = englishPresentationLocale(regionSource)
        formatter.unitOptions = .naturalScale
        return formatter.string(from: measurement)
    }

    static func formattedDate(
        _ value: Date,
        timeZone: TimeZone,
        regionSource: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = englishPresentationLocale(regionSource)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }

    private static func englishPresentationLocale(_ source: Locale) -> Locale {
        Locale(identifier: "en-" + (source.region?.identifier ?? "US"))
    }

    private static func validateSourceCatalog(
        _ data: Data,
        registry: LocalizationKeyRegistryV1
    ) throws {
        guard data.count <= 2_097_152,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["sourceLanguage"] as? String == "en",
              root["version"] as? String == "1.0",
              let strings = root["strings"] as? [String: Any] else {
            throw LocalizationContractFailureV1.invalidValue
        }
        let registeredKeys = Set(registry.definitions.map(\.key.rawValue))
        let sourceRegistry = try completeSourceRegistry()
        let supportedKeys = Set(sourceRegistry.definitions.map(\.key.rawValue))
        guard registeredKeys.isSubset(of: Set(strings.keys)),
              Set(strings.keys).isSubset(of: supportedKeys) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        for definition in registry.definitions {
            guard try sourceRegistry.definition(for: definition.key) == definition else {
                throw LocalizationContractFailureV1.incompatibleKeyReuse
            }
        }
        for definition in sourceRegistry.definitions where strings[definition.key.rawValue] != nil {
            let rawKey = definition.key.rawValue
            guard let rawEntry = strings[rawKey],
                  let entry = rawEntry as? [String: Any],
                  let comment = entry["comment"] as? String,
                  !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let localizations = entry["localizations"] as? [String: Any],
                  Set(localizations.keys) == Set(["en"]),
                  (try? sourceRegistry.definition(for: LocalizationKeyV1(rawKey))) != nil else {
                throw LocalizationContractFailureV1.missingComment
            }
            guard comment == definition.translatorComment,
                  let english = localizations["en"] as? [String: Any] else {
                throw LocalizationContractFailureV1.invalidValue
            }
            if definition.requiredEnglishPluralCategories == ["one", "other"] {
                guard let variations = english["variations"] as? [String: Any],
                      let plural = variations["plural"] as? [String: Any],
                      Set(plural.keys) == Set(["one", "other"]),
                      let one = plural["one"] as? [String: Any],
                      let oneUnit = one["stringUnit"] as? [String: Any],
                      let oneValue = oneUnit["value"] as? String, !oneValue.isEmpty,
                      let other = plural["other"] as? [String: Any],
                      let unit = other["stringUnit"] as? [String: Any],
                      unit["value"] as? String == definition.englishDefaultValue else {
                    throw LocalizationContractFailureV1.invalidValue
                }
            } else {
                guard let unit = english["stringUnit"] as? [String: Any],
                      unit["value"] as? String == definition.englishDefaultValue else {
                    throw LocalizationContractFailureV1.invalidValue
                }
            }
        }
    }

    private static func definition(
        _ key: BundledLocalizationKeyV1, _ meaning: String, _ value: String,
        _ comment: String, arguments: [LocalizationArgumentV1] = [],
        plurals: [String] = []
    ) throws -> LocalizationKeyDefinitionV1 {
        LocalizationKeyDefinitionV1(
            key: try LocalizationKeyV1(key.rawValue), meaningID: meaning,
            translatorComment: comment, englishDefaultValue: value,
            arguments: arguments, requiredEnglishPluralCategories: plurals,
            state: .active, deprecatedFallbackKey: nil
        )
    }
}

extension FrozenDisplaySnapshotV1 {
    init(reportSnapshot: ReportSnapshotV1) throws {
        let encoded = try ReportSnapshotEncoderV1().encode(reportSnapshot)
        try self.init(canonicalBytes: encoded.data, sha256: encoded.sha256)
    }

    func validateUnchanged(reportSnapshot: ReportSnapshotV1) throws {
        let encoded = try ReportSnapshotEncoderV1().encode(reportSnapshot)
        try validateUnchanged(canonicalBytes: encoded.data, sha256: encoded.sha256)
    }
}

extension BundledLocalizationCatalogV1 {
    /// C18 package labels are English-only presentation values. Package
    /// identity and lifecycle comparisons use the typed key/release binding,
    /// never these labels.
    static let packageEvolutionSourceLocale = "en"
    static let packageEvolutionShippingLocales = ["en"]
    static let packageEvolutionPseudoLocalesAreTestOnly = true
    static let packageEvolutionLabelsParticipateInIdentity = false
    static let packageEvolutionBrandStateValues = [
        "PREVIEW", "PROMOTED", "ROLLED_BACK", "FORWARD_FIX_REQUIRED", "FAILED_CLOSED",
    ]

    static func packageEvolutionLocalizationBinding(
        _ metadata: PackageEvolutionConsumerMetadataV1,
        keyIDs: [String] = []
    ) throws -> PackageEvolutionLocalizationBindingV1 {
        try PackageEvolutionLocalizationPolicyV1.binding(
            metadata: metadata,
            keyIDs: keyIDs
        )
    }

    static func packageEvolutionDisplayLabel(
        for status: PackageEvolutionConsumerStatusV1
    ) -> String {
        switch status {
        case .preview: return "Preview"
        case .promoted: return "Promoted"
        case .rolledBack: return "Rolled back"
        case .forwardFixRequired: return "Forward fix required"
        case .void: return "Void"
        }
    }

    static func packageEvolutionDisplayLabel(
        for classification: PackageSemanticDiffClassificationV1
    ) -> String {
        switch classification {
        case .noChange: return "No change"
        case .additiveDraftSafe: return "Additive draft safe"
        case .draftMigrationRequired: return "Draft migration required"
        case .activeSessionIncompatible: return "Active session incompatible"
        case .invalid: return "Invalid"
        }
    }

    static func packageEvolutionBrandStateDisplayLabel(for rawValue: String) -> String {
        switch rawValue {
        case "PREVIEW": return "Preview"
        case "PROMOTED": return "Promoted"
        case "ROLLED_BACK": return "Rolled back"
        case "FORWARD_FIX_REQUIRED": return "Forward fix required"
        case "FAILED_CLOSED": return "Failed closed"
        default: return "Unavailable"
        }
    }

    static func packageEvolutionAccessibilityContracts()
        -> [PackageEvolutionAccessibilityContractV1] {
        PackageEvolutionAccessibilityPolicyV1.contracts
    }
}

// MARK: - V23 P04 C16 provisional task-first shell localization

enum C16ShellLocalizationKeyV1: String, CaseIterable, Codable, Hashable, Sendable {
    case todayTitle = "shell.root.today.title"
    case todayHint = "shell.root.today.hint"
    case workTitle = "shell.root.work.title"
    case workHint = "shell.root.work.hint"
    case assetsTitle = "shell.root.assets.title"
    case assetsHint = "shell.root.assets.hint"
    case reportsTitle = "shell.root.reports.title"
    case reportsHint = "shell.root.reports.hint"
    case practiceWatermark = "shell.practice.watermark"
    case practiceShareTitle = "shell.practice.share.title"
    case practiceShareMessage = "shell.practice.share.message"
    case practiceShareConfirm = "shell.practice.share.confirm"
    case practiceShareCancel = "shell.practice.share.cancel"
    case availabilityHeading = "shell.availability.heading"
    case availabilityAvailable = "shell.availability.available"
    case availabilityUnavailable = "shell.availability.unavailable"
    case availabilityReason = "shell.availability.reason"
    case availabilityReasonAvailable = "shell.availability.reason.available"
    case availabilityDisabledByPolicy = "shell.availability.reason.disabled-by-policy"
    case availabilityAppLocked = "shell.availability.reason.app-locked"
    case availabilityProtectedDataUnavailable = "shell.availability.reason.protected-data-unavailable"
    case availabilityRealWorkspaceRequired = "shell.availability.reason.real-workspace-required"
    case availabilityPracticeWorkspaceRequired = "shell.availability.reason.practice-workspace-required"
    case availabilitySourceUnavailable = "shell.availability.reason.source-unavailable"
    case availabilityStaleSource = "shell.availability.reason.stale-source"
    case availabilityPermissionNotGranted = "shell.availability.reason.permission-not-granted"
    case availabilityUnsupported = "shell.availability.reason.unsupported"
    case availabilityReconciliationPending = "shell.availability.reason.reconciliation-pending"
    case starterWorkspaceTitle = "shell.starter-workspace.title"
    case starterWorkspaceAction = "shell.starter-workspace.action"
    case resumeTitle = "shell.resume.title"
    case resumeAction = "shell.resume.action"
    case productChangesTitle = "shell.product-changes.title"
    case productChangesBody = "shell.product-changes.body"
    case helpTitle = "shell.help.title"
    case helpBody = "shell.help.body"
    case helpAction = "shell.help.action"

    var englishDefaultValue: String {
        switch self {
        case .todayTitle: return "Today"
        case .todayHint: return "Review ready and due work."
        case .workTitle: return "Work"
        case .workHint: return "Open work in the selected workspace."
        case .assetsTitle: return "Assets"
        case .assetsHint: return "Browse assets in the selected workspace."
        case .reportsTitle: return "Reports"
        case .reportsHint: return "Review reports in the selected workspace."
        case .practiceWatermark: return "PRACTICE — NOT FOR FIELD USE"
        case .practiceShareTitle: return "Share practice content?"
        case .practiceShareMessage: return "This content is marked as practice and is not field evidence."
        case .practiceShareConfirm: return "Share practice content"
        case .practiceShareCancel: return "Cancel"
        case .availabilityHeading: return "Availability"
        case .availabilityAvailable: return "Available"
        case .availabilityUnavailable: return "Unavailable"
        case .availabilityReason: return "Reason"
        case .availabilityReasonAvailable: return "This feature is available."
        case .availabilityDisabledByPolicy: return "This feature is disabled by policy."
        case .availabilityAppLocked: return "Unlock the app to continue."
        case .availabilityProtectedDataUnavailable: return "Protected data is unavailable."
        case .availabilityRealWorkspaceRequired: return "Select a real workspace to continue."
        case .availabilityPracticeWorkspaceRequired: return "Open a practice workspace to continue."
        case .availabilitySourceUnavailable: return "Required local content is unavailable."
        case .availabilityStaleSource: return "Required local content is out of date."
        case .availabilityPermissionNotGranted: return "Required permission has not been granted."
        case .availabilityUnsupported: return "This feature is not supported."
        case .availabilityReconciliationPending: return "This surface is pending app-shell reconciliation."
        case .starterWorkspaceTitle: return "Starter workspace"
        case .starterWorkspaceAction: return "Create starter workspace"
        case .resumeTitle: return "Resume"
        case .resumeAction: return "Resume saved work"
        case .productChangesTitle: return "Product changes"
        case .productChangesBody: return "Review changes included with this version."
        case .helpTitle: return "Help"
        case .helpBody: return "Review guidance for the current task."
        case .helpAction: return "Open help"
        }
    }

    static func availabilityReason(
        _ reason: WorkspaceExperienceAvailabilityReasonV1
    ) -> C16ShellLocalizationKeyV1 {
        switch reason {
        case .available: return .availabilityReasonAvailable
        case .disabledByPolicy: return .availabilityDisabledByPolicy
        case .appLocked: return .availabilityAppLocked
        case .protectedDataUnavailable: return .availabilityProtectedDataUnavailable
        case .realWorkspaceRequired: return .availabilityRealWorkspaceRequired
        case .practiceWorkspaceRequired: return .availabilityPracticeWorkspaceRequired
        case .sourceUnavailable: return .availabilitySourceUnavailable
        case .staleSource: return .availabilityStaleSource
        case .permissionNotGranted: return .availabilityPermissionNotGranted
        case .unsupported: return .availabilityUnsupported
        }
    }
}

enum C16ShellLocalizationPolicyV1 {
    static let sourceLocale = "en"
    static let shippingLocales = ["en"]
    static let pseudoLocales = ["en-XA", "ar-XB"]
    static let runtimeDownloadsAllowed = false
    static let uiAdoptionClaimed = false
    static let requiresAcceptedS10_6Reconciliation = true

    static func validate() throws {
        let keys = C16ShellLocalizationKeyV1.allCases.map(\.rawValue)
        guard keys.count == Set(keys).count,
              keys.allSatisfy({ !$0.isEmpty }),
              sourceLocale == "en",
              shippingLocales == ["en"],
              pseudoLocales == ["en-XA", "ar-XB"],
              !runtimeDownloadsAllowed,
              !uiAdoptionClaimed,
              requiresAcceptedS10_6Reconciliation else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

extension BundledLocalizationCatalogV1 {
    static func c16ShellEnglish(_ key: C16ShellLocalizationKeyV1) -> String {
        key.englishDefaultValue
    }

    static func c16ShellLocalized(
        _ key: C16ShellLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: locale,
            comment: "C16 provisional task-first shell copy; UI adoption remains pending accepted S10.6 reconciliation."
        )
    }

    static func c16ShellRegistry() throws -> LocalizationKeyRegistryV1 {
        try C16ShellLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = try C16ShellLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C16 provisional task-first shell copy; no shipping UI or S10.6 adoption claim."),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C14 private system discovery catalog

extension BundledLocalizationCatalogV1 {
    static func privateSystemDiscoveryEnglish(
        _ key: PrivateSystemDiscoveryLocalizationKeyV1
    ) -> String {
        PrivateSystemDiscoveryLocalizationPolicyV1.english(key)
    }

    static func privateSystemDiscoveryLocalized(
        _ key: PrivateSystemDiscoveryLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: privateSystemDiscoveryEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C14 private on-device discovery state; generic protected outcomes do not disclose private record existence."
        )
    }

    static func privateSystemDiscoveryRegistry() throws -> LocalizationKeyRegistryV1 {
        try PrivateSystemDiscoveryLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = try PrivateSystemDiscoveryLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C14 private on-device discovery state; generic protected outcomes do not disclose private record existence."),
                englishDefaultValue: privateSystemDiscoveryEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

extension BundledLocalizationCatalogV1 { static func fastSurveyInboxLocalized(_ key: FastSurveyInboxLocalizationKeyV1, bundle: Bundle = .main, locale: Locale = .current) -> String { localizedRegistryText(key: key.rawValue, defaultValue: key.english, bundle: bundle, locale: locale, comment: "C11 contained local inbox presentation; no completion, truth, route, or acceptance claim.") } }
extension BundledLocalizationCatalogV1 { static func c12Localized(_ key: C12LocalizationKeyV1, bundle: Bundle = .main, locale: Locale = .current) -> String { localizedRegistryText(key: key.rawValue, defaultValue: key.english, bundle: bundle, locale: locale, comment: "C12 contained local reinspection and exception-queue presentation; no source-resolution, evidence-freshness, adoption, acceptance, or release claim.") } }
extension BundledLocalizationCatalogV1 { static func c13Localized(_ key: C13LocalizationKeyV1, bundle: Bundle = .main, locale: Locale = .current) -> String { localizedRegistryText(key: key.rawValue, defaultValue: key.english, bundle: bundle, locale: locale, comment: "C13 contained identity review; no automatic mutation, route, root, adoption, acceptance, or release claim.") } }

// MARK: - C10 evidence quality coach catalog

extension BundledLocalizationCatalogV1 {
    static func evidenceQualityCoachEnglish(_ key: EvidenceQualityCoachLocalizationKeyV1) -> String {
        EvidenceQualityCoachLocalizationPolicyV1.english(key)
    }

    static func evidenceQualityCoachLocalized(
        _ key: EvidenceQualityCoachLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: evidenceQualityCoachEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C10 contained evidence-quality coach system copy; describes recorded warnings without an automatic requirement judgment."
        )
    }

    static func evidenceQualityCoachRegistry() throws -> LocalizationKeyRegistryV1 {
        try EvidenceQualityCoachLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = EvidenceQualityCoachLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C10 contained evidence-quality coach system copy; describes recorded warnings without an automatic requirement judgment."),
                englishDefaultValue: evidenceQualityCoachEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

extension BundledLocalizationCatalogV1 { static func importBulkPreviewLocalized(_ key: ImportBulkPreviewLocalizationKeyV1, bundle: Bundle = .main, locale: Locale = .current) -> String { localizedRegistryText(key: key.rawValue, defaultValue: key.english, bundle: bundle, locale: locale, comment: "C08 preview-only presentation; no write claim.") } }

extension BundledLocalizationCatalogV1 {
    static func roundSessionLocalized(_ key: RoundSessionLocalizationKeyV1, bundle: Bundle = .main, locale: Locale = .current) -> String {
        localizedRegistryText(key: key.rawValue, defaultValue: RoundSessionLocalizationPolicyV1.english(key), bundle: bundle, locale: locale, comment: "C07 local RoundSession presentation; no sync, upload, account, or delivery claim.")
    }
    static func roundSessionRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry(); let additions = try RoundSessionLocalizationKeyV1.allCases.map { key in LocalizationKeyDefinitionV1(key: key.localizationKey, meaningID: key.rawValue, translatorComment: "C07 local RoundSession presentation; no sync, upload, account, or delivery claim.", englishDefaultValue: RoundSessionLocalizationPolicyV1.english(key), arguments: [], requiredEnglishPluralCategories: [], state: .active, deprecatedFallbackKey: nil) }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C06 round offline-readiness preflight catalog

extension BundledLocalizationCatalogV1 {
    static func offlineReadinessPreflightEnglish(
        _ key: OfflineReadinessPreflightLocalizationKeyV1
    ) -> String {
        OfflineReadinessPreflightLocalizationPolicyV1.english(key)
    }

    static func offlineReadinessPreflightLocalized(
        _ key: OfflineReadinessPreflightLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: offlineReadinessPreflightEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C06 local-only offline readiness presentation. It never claims sync, upload, network, account, or remote delivery status."
        )
    }

    static func offlineReadinessPreflightRegistry() throws -> LocalizationKeyRegistryV1 {
        try OfflineReadinessPreflightLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = OfflineReadinessPreflightLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C06 local-only offline readiness presentation. It never claims sync, upload, network, account, or remote delivery status."),
                englishDefaultValue: offlineReadinessPreflightEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C03 illuminated-sign playbook catalog

extension BundledLocalizationCatalogV1 {
    static func illuminatedSignPlaybookEnglish(
        _ key: IlluminatedSignPlaybookLocalizationKeyV1
    ) -> String {
        IlluminatedSignPlaybookLocalizationPolicyV1.english(key)
    }

    static func illuminatedSignPlaybookLocalized(
        _ key: IlluminatedSignPlaybookLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: illuminatedSignPlaybookEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C03 illuminated-sign playbook presentation; visible-condition-only facts, required capture traceability, and no certification claim."
        )
    }

    static func illuminatedSignPlaybookRegistry() throws -> LocalizationKeyRegistryV1 {
        try IlluminatedSignPlaybookLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = IlluminatedSignPlaybookLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C03 illuminated-sign playbook presentation; visible-condition-only facts, required capture traceability, and no certification claim."),
                englishDefaultValue: illuminatedSignPlaybookEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C04 shop-profile open-evidence handoff catalog

extension BundledLocalizationCatalogV1 {
    static func shopReportProfileEnglish(
        _ key: ShopReportProfileLocalizationKeyV1
    ) -> String {
        ShopReportProfileLocalizationPolicyV1.english(key)
    }

    static func shopReportProfileLocalized(
        _ key: ShopReportProfileLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: shopReportProfileEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C04 shop-profile open-evidence handoff presentation; exact-byte privacy confirmation and no delivery or certification claim."
        )
    }

    static func shopReportProfileRegistry() throws -> LocalizationKeyRegistryV1 {
        try ShopReportProfileLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = ShopReportProfileLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C04 shop-profile open-evidence handoff presentation; exact-byte privacy confirmation and no delivery or certification claim."),
                englishDefaultValue: shopReportProfileEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

extension BundledLocalizationCatalogV1 {
    static func operationalContactEnglish(
        _ key: OperationalContactLocalizationKeyV1
    ) -> String {
        switch key {
        case .directions: "Directions"
        case .call: "Call"
        case .text: "Text"
        case .email: "Email"
        case .opensSystemApp: "Opens the corresponding system app"
        case .handedOff: "Handed off to the system"
        case .targetMissing: "The selected destination is no longer available"
        case .targetStale: "The selected destination changed. Review it again."
        case .targetInvalid: "The selected destination cannot be used"
        case .systemUnavailable: "The system app is unavailable right now"
        case .systemRejected: "The system did not accept the handoff"
        case .cancelled: "Handoff cancelled before opening the system app"
        case .claimBoundary:
            "Handoff does not confirm a call connected, a message or email was sent or delivered, or that anyone arrived."
        }
    }

    static func operationalContactLocalized(
        _ key: OperationalContactLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        let value = NSLocalizedString(
            key.rawValue,
            tableName: nil,
            bundle: bundle,
            value: operationalContactEnglish(key),
            comment: "C46 explicit user-directed system handoff"
        )
        return value.isEmpty ? operationalContactEnglish(key) : value
    }
}

// MARK: - C30 operating-context labels

extension BundledLocalizationCatalogV1 {
    /// C30 adds closed English-only labels to the sole source catalog.  The
    /// registry carries typed core values and never localizes a raw digest,
    /// actor, location, sensor, or control result.
    static func operatingContextRegistry() throws -> LocalizationKeyRegistryV1 {
        try C30OperatingContextLocalizationPolicyV1.validate()
        let base = try accessibleDocumentRegistry()
        let additions = C30OperatingContextLocalizationKeyV1.allCases.map {
            LocalizationKeyDefinitionV1(
                key: $0.localizationKey,
                meaningID: $0.rawValue,
                translatorComment: $0.translatorComment,
                englishDefaultValue: $0.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func operatingContextAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try C30OperatingContextAccessibilityPolicyV1.validate()
        let base = try accessibleDocumentAccessibilityRegistry(localization: localization)
        let entries = try C30OperatingContextAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            default:
                role = C30OperatingContextAccessibilityPolicyV1.stateSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            let hintKey: LocalizationKeyV1? =
                C30OperatingContextAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                ) ? C30OperatingContextLocalizationKeyV1.nextStep.localizationKey : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func operatingContextDisplayLabel(
        for key: C30OperatingContextLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func operatingContextConditionDisplayLabel(
        _ condition: EvidenceLightingConditionV1,
        bundle: Bundle = .main
    ) -> String {
        operatingContextDisplayLabel(
            for: C30OperatingContextLocalizationKeyV1.conditionKey(condition),
            bundle: bundle
        )
    }

    static func operatingContextExpectedControlDisplayLabel(
        _ state: ExpectedControlStateV1?,
        bundle: Bundle = .main
    ) -> String {
        operatingContextDisplayLabel(
            for: C30OperatingContextLocalizationKeyV1.expectedControlKey(state),
            bundle: bundle
        )
    }
}

// MARK: - C29 versioned plan and rebase labels

extension BundledLocalizationCatalogV1 {
    static func planRegistry() throws -> LocalizationKeyRegistryV1 {
        try PlanLocalizationPolicyV1.validate()
        let base = try scheduleRegistry()
        let additions = try PlanLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: key.translatorComment),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(
            definitions: base.definitions + additions
        )
    }

    static func localized(
        _ key: PlanLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func planDocumentStateDisplayLabel(
        _ state: PlanDocumentStateV1,
        bundle: Bundle = .main
    ) -> String {
        localized(PlanLocalizationKeyV1.documentStateKey(state), bundle: bundle)
    }

    static func planRevisionStateDisplayLabel(
        _ state: PlanRevisionStateV1,
        bundle: Bundle = .main
    ) -> String {
        localized(PlanLocalizationKeyV1.revisionStateKey(state), bundle: bundle)
    }

    static func planPlacementDispositionDisplayLabel(
        _ disposition: PlanPlacementDispositionV1,
        bundle: Bundle = .main
    ) -> String {
        localized(
            PlanLocalizationKeyV1.placementDispositionKey(disposition),
            bundle: bundle
        )
    }

    static func planRebaseDecisionDisplayLabel(
        _ decision: PlanRebaseDecisionV1,
        bundle: Bundle = .main
    ) -> String {
        localized(PlanLocalizationKeyV1.decisionKey(decision), bundle: bundle)
    }

    static func planRebaseWarningDisplayLabel(
        _ warning: PlanRebaseWarningCodeV1,
        bundle: Bundle = .main
    ) -> String {
        localized(PlanLocalizationKeyV1.warningKey(warning), bundle: bundle)
    }

    static func planAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try scheduleAccessibilityRegistry(localization: localization)
        let nextStep = PlanLocalizationKeyV1.planNextStep.localizationKey
        let entries = try PlanAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading, .document, .revision, .revisionState, .placement,
                 .placementDisposition, .coordinate, .reference, .contentBinding,
                 .spatialFrame, .rebasePreview, .rebaseReceipt, .rebaseDecision,
                 .rebaseWarning, .rebaseComponent, .residual, .expectedRevision,
                 .historyImmutable, .previewNotApplied, .placementList,
                 .pageNavigation, .thumbnailNavigation, .rebaseReview: role = .heading
            case .nextStep, .assetsRoute, .workRoute, .placementCreate,
                 .placementMove, .placementLink, .resumeWork, .rebaseApprove,
                 .rebaseReject, .openOriginalRevision: role = .button
            case .documentActive, .documentRetired, .revisionDraft,
                 .revisionReleased, .revisionWithdrawn, .placementAccepted,
                 .placementReviewRequired, .placementOrphaned,
                 .placementOutOfBounds, .decisionApplyRecorded,
                 .decisionRejectRecorded, .warningPageMissing,
                 .warningPageReordered, .warningOutOfBounds,
                 .warningOrphanedAnchor, .warningResidualExceeded,
                 .warningCalibrationUnavailable,
                 .warningComponentReviewRequired, .errorStalePreview,
                 .errorWrongReference, .errorComponentConflict,
                 .errorReviewRequired, .errorInvalidDigest, .offlineReady,
                 .offlineNotApplicable,
                 .offlineMissingPlan, .offlineMissingReference,
                 .offlineReferenceUnavailable, .offlineStorageInsufficient,
                 .offlineOpenabilityFailed, .offlineProtectedDataUnavailable,
                 .offlineHistoricReadOnly: role = .status
            case .claimBoundary, .placementRow,
                 .viewportDirectionBoundary: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: PlanAccessibilityPolicyV1
                    .requiresActionableNextStep(for: id.rawValue)
                    ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }
}

// MARK: - C28 schedule and occurrence labels

extension BundledLocalizationCatalogV1 {
    /// Extends the one English source catalog with schedule labels. The
    /// canonical release/history records remain the only schedule writer;
    /// these definitions are presentation metadata only.
    static func scheduleRegistry() throws -> LocalizationKeyRegistryV1 {
        try ScheduleLocalizationPolicyV1.validate()
        let base = try assetLocatorRegistry()
        let additions = try ScheduleLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: key.translatorComment),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(
            definitions: base.definitions + additions
        )
    }

    static func localized(
        _ key: ScheduleLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func scheduleDisplayLabel(
        for state: OccurrenceStateV1,
        bundle: Bundle = .main
    ) -> String {
        localized(ScheduleLocalizationKeyV1.key(for: state), bundle: bundle)
    }

    static func scheduleAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try ScheduleAccessibilityPolicyV1.validateExperienceRequirements()
        let base = try assetLocatorAccessibilityRegistry(
            localization: localization
        )
        let nextStep = ScheduleLocalizationKeyV1.nextStep.localizationKey
        let entries = try ScheduleAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading, .definition, .occurrenceState, .timeBasis,
                 .history, .dueQueue, .reminder, .advancedRecurrence,
                 .exceptionCalendar, .calendarRelease, .businessDayAdjustment,
                 .completionGap, .nominalBasis, .effectiveBasis,
                 .occurrenceLineage, .scheduleOverride, .overridePrecedence,
                 .changePreview, .recovery, .editor, .editorReview,
                 .timeZone, .summary, .horizon: role = .heading
            case .nextStep, .save, .pause, .resume, .end,
                 .startOnce: role = .button
            case .stateUpcoming, .stateReady, .stateDue, .stateOverdue,
                 .stateDeferred, .stateMissed, .stateSkipped, .stateCancelled,
                 .stateStarted, .stateCompleted, .previewNotApplied,
                 .changeConflict, .manualResolutionRequired,
                 .recoveryRebuilt, .todayReason, .offlineReadiness,
                 .reminderPermission, .reminderStatus, .interruption,
                 .error: role = .status
            case .occurrence, .claimBoundary: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: ScheduleAccessibilityPolicyV1
                    .requiresActionableNextStep(for: id.rawValue)
                    ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }
}

// MARK: - C27 asset-locator labels and accessibility registry

extension BundledLocalizationCatalogV1 {
    /// C27 extends the sole English source catalog with bounded locator
    /// metadata and offline-resolution labels.  No opaque input or key
    /// material is ever looked up as localized text.
    static func assetLocatorRegistry() throws -> LocalizationKeyRegistryV1 {
        try AssetLocatorLocalizationPolicyV1.validate()
        let base = try surveySessionRegistry()
        let additions = try AssetLocatorLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: key.translatorComment,
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func localized(
        _ key: AssetLocatorLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func assetLocatorAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try privacyTransformAccessibilityRegistry(localization: localization)
        let entries = try AssetLocatorAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading, .resolution, .lifecycle: role = .heading
            case .nextStep: role = .button
            default:
                role = AssetLocatorAccessibilityPolicyV1.statusSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            let hintKey: LocalizationKeyV1? =
                AssetLocatorAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                )
                ? AssetLocatorLocalizationKeyV1.nextStep.localizationKey
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func assetLocatorDisplayLabel(
        for key: AssetLocatorLocalizationKeyV1
    ) -> String {
        localized(key)
    }
}

// MARK: - C26 guided-survey session labels

extension BundledLocalizationCatalogV1 {
    /// C26 is an additive English-only presentation registry.  The durable
    /// session, fact, subject, and publication records remain the sole source
    /// of truth; this registry only supplies stable labels for their recorded
    /// states.
    static func surveySessionRegistry() throws -> LocalizationKeyRegistryV1 {
        try SurveySessionLocalizationPolicyV1.validate()
        let base = try surveyDefinitionRegistry()
        let additions = try SurveySessionLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: key.translatorComment,
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func localized(
        _ key: SurveySessionLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func surveySessionDisplayLabel(
        for key: SurveySessionLocalizationKeyV1
    ) -> String {
        localized(key)
    }
}

// MARK: - C25 guided-survey labels and accessibility registry

extension BundledLocalizationCatalogV1 {
    /// Extends the sole bundled catalog with C25's closed English-only
    /// vocabulary.  The core release stores localization keys and a catalog
    /// release digest; it never stores localized answers or actor values here.
    static func surveyDefinitionRegistry() throws -> LocalizationKeyRegistryV1 {
        try SurveyDefinitionLocalizationPolicyV1.validate()
        let base = try accessibleDocumentRegistry()
        let additions = try SurveyDefinitionLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: key.translatorComment),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func localized(
        _ key: SurveyDefinitionLocalizationKeyV1,
        bundle: Bundle = .main
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: Locale(identifier: runtimeLanguage),
            comment: key.translatorComment
        )
    }

    static func surveyDefinitionAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try SurveyDefinitionAccessibilityPolicyV1.validate()
        let base = try accessibleDocumentAccessibilityRegistry(
            localization: localization
        )
        let entries = try SurveyDefinitionAccessibilityIDV1.allCases.map { id
            -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading, .library, .semanticPreview: role = .heading
            case .nextStep, .browse, .search, .favorites, .recents,
                 .duplicate, .publish, .retire, .export,
                 .importAsDraft: role = .button
            case .lifecycle, .notObserved, .claimBoundary,
                 .compatibilityNoChange, .compatibilityAdditiveDraftSafe,
                 .compatibilityDraftMigrationRequired,
                 .compatibilityActiveWorkPinned,
                 .compatibilityBlocked: role = .status
            default: role = .group
            }
            let labelKey = try LocalizationKeyV1(id.localizationKey.rawValue)
            let hintKey: LocalizationKeyV1? =
                SurveyDefinitionAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                )
                ? try LocalizationKeyV1(
                    SurveyDefinitionLocalizationKeyV1.nextStepReviewRecordedFacts.rawValue
                )
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: labelKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        try GuidedSurveyFlowAccessibilityPolicyV1.validate()
        let flowEntries = try GuidedSurveyFlowAccessibilityIDV1.allCases.map { id
            -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .run, .resume, .review, .report, .primaryAction: role = .button
            case .interruption, .frozenReport, .reviewConflict,
                 .promotionConflict, .claimBoundary: role = .status
            case .manualPath: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(id.localizationKey.rawValue),
                hintKey: nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries + flowEntries, localization: localization)
    }

    static func surveyDefinitionDisplayLabel(
        for key: SurveyDefinitionLocalizationKeyV1
    ) -> String {
        localized(key)
    }
}

// MARK: - C23 version-bound field-reference labels

extension BundledLocalizationCatalogV1 {
    /// Publishes the closed C23 field-reference vocabulary as an additive
    /// English-only registry.  Release/binding identity is compared by the
    /// canonical projection and digest fields, never by a localized label.
    static func fieldReferenceRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try clientCapabilityRegistry()
        let additions = try FieldReferenceLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func fieldReferenceAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try clientCapabilityAccessibilityRegistry(localization: localization)
        let nextStep = try LocalizationKeyV1(FieldReferenceLocalizationKeyV1.nextStep.rawValue)
        let entries = try FieldReferenceAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            default:
                role = FieldReferenceAccessibilityPolicyV1.stateSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: FieldReferenceAccessibilityPolicyV1
                    .requiresActionableNextStep(for: id.rawValue) ? nextStep : nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func fieldReferenceDisplayLabel(
        for key: FieldReferenceLocalizationKeyV1
    ) -> String {
        guard let bundled = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            return key.englishDefaultValue
        }
        return localized(bundled)
    }
}

// MARK: - C24 accessible-document labels

extension BundledLocalizationCatalogV1 {
    /// C24 adds only the closed English accessible-document vocabulary to the
    /// existing catalog.  Tree values, evidence locators, and assessor
    /// identity remain outside the localization registry.
    static func accessibleDocumentRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try fieldReferenceRegistry()
        let additions = try AccessibleDocumentLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func accessibleDocumentAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try fieldReferenceAccessibilityRegistry(localization: localization)
        let entries = try AccessibleDocumentAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            default:
                role = AccessibleDocumentAccessibilityPolicyV1.stateSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            let hintKey: LocalizationKeyV1? =
                AccessibleDocumentAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                )
                ? AccessibleDocumentLocalizationKeyV1.nextStep.localizationKey
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }

    static func accessibleDocumentDisplayLabel(
        for key: AccessibleDocumentLocalizationKeyV1
    ) -> String {
        guard let bundled = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            return key.englishDefaultValue
        }
        return localized(bundled)
    }
}

// MARK: - C21 client capability and package lifecycle labels

extension BundledLocalizationCatalogV1 {
    /// C21 extends the already published English-only registry with the
    /// closed admission, lifecycle-state, and lifecycle-operation vocabulary.
    /// No device, user, account, endpoint, provider, or delivery value is
    /// accepted as a localized label.
    static func clientCapabilityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try privacyTransformRegistry()
        let additions = try ClientCapabilityLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func clientCapabilityAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try privacyTransformAccessibilityRegistry(localization: localization)
        let entries = try ClientCapabilityAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let labelKey: LocalizationKeyV1
            if id == .screen {
                labelKey = try LocalizationKeyV1(
                    BundledLocalizationKeyV1.clientCapabilityHeading.rawValue
                )
            } else {
                labelKey = try LocalizationKeyV1(id.rawValue)
            }
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading, .lifecycleHeading: role = .heading
            case .nextStep: role = .button
            default:
                role = ClientCapabilityAccessibilityPolicyV1.statusSemanticIDs
                    .contains(id.rawValue) ? .status : .group
            }
            let hintKey: LocalizationKeyV1? =
                ClientCapabilityAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                )
                ? try LocalizationKeyV1(
                    BundledLocalizationKeyV1.clientCapabilityNextStep.rawValue
                )
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: labelKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }
}

// MARK: - C20 privacy-transform consumer labels

extension BundledLocalizationCatalogV1 {
    /// Additive C20 registry.  The source catalog remains English-only and
    /// the existing mail allowlist/registry is deliberately not enlarged by
    /// any runtime content or reviewer-facing value.
    static func privacyTransformRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try measurementIntegrityRegistry()
        let additions = try PrivacyTransformLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func privacyTransformAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let entries = try PrivacyTransformAccessibilityIDV1.allCases.map { id
            -> AccessibilityContractV1 in
            let bundledKey: BundledLocalizationKeyV1
            if id == .screen {
                bundledKey = .privacyTransformHeading
            } else if let value = BundledLocalizationKeyV1(rawValue: id.rawValue) {
                bundledKey = value
            } else {
                throw LocalizationContractFailureV1.missingKey
            }
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            case .reviewApproved, .reviewRejected, .freshnessCurrent,
                 .projectionAllowed, .projectionDenied, .denialMissingReview,
                 .denialRejected, .denialStale, .denialWrongAudience,
                 .denialWrongPolicy, .denialSourceChanged,
                 .denialDigestMismatch, .denialMetadataNotSanitized:
                role = .status
            default: role = .group
            }
            let hintKey: LocalizationKeyV1? =
                PrivacyTransformAccessibilityPolicyV1.requiresActionableNextStep(
                    for: id.rawValue
                )
                ? try LocalizationKeyV1(BundledLocalizationKeyV1.privacyTransformNextStep.rawValue)
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(bundledKey.rawValue),
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try SemanticAccessibilityIDRegistryV1(
            entries: entries,
            localization: localization
        )
    }
}

// MARK: - C37 reference-framed pose labels

extension BundledLocalizationCatalogV1 {
    static func poseRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try privacyTransformRegistry()
        let additions = try C37PoseLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                key.translatorComment
            )
        }
        try C37PoseLocalizationPolicyV1.validate()
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func poseAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try privacyTransformAccessibilityRegistry(localization: localization)
        let entries = try C37PlacementPoseAccessibilityIDV1.allCases.map {
            id -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            default:
                role = C37PoseAccessibilityPolicyV1.stateSemanticIDs.contains(id.rawValue)
                    ? .status : .group
            }
            let hintKey: LocalizationKeyV1? =
                C37PoseAccessibilityPolicyV1.requiresActionableNextStep(for: id.rawValue)
                    ? try LocalizationKeyV1(C37PoseLocalizationKeyV1.nextStep.rawValue)
                    : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(id.localizationKey.rawValue),
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try SemanticAccessibilityIDRegistryV1(
            entries: base.entries + entries,
            localization: localization
        )
    }

    static func localized(_ key: C37PoseLocalizationKeyV1) -> String {
        guard let bundled = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            return key.englishDefaultValue
        }
        return localized(bundled)
    }

    static func poseDisplayLabel(
        for key: C37PoseLocalizationKeyV1
    ) -> String {
        localized(key)
    }

    static func poseReferenceFrameDisplayLabel(
        for value: C37PoseReferenceFrameProjectionV1
    ) -> String {
        localized(C37PoseLocalizationKeyV1.referenceFrameKey(value))
    }

    static func poseObservationStateDisplayLabel(
        for value: C37PoseObservationStateV1
    ) -> String {
        localized(C37PoseLocalizationKeyV1.observationStateKey(value))
    }

    static func poseNotObservedReasonDisplayLabel(
        for value: PoseNotObservedReasonV1
    ) -> String {
        localized(C37PoseLocalizationKeyV1.notObservedReasonKey(value))
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Infrastructure_Localization_BundledLocalizationCatalogV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", role: .localization)
}

// MARK: - C31 exterior/parking-lighting labels

extension BundledLocalizationCatalogV1 {
    static func lightingRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try poseRegistry()
        let additions = try C31LightingLocalizationKeyV1.allCases.map { key in
            guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
                throw LocalizationContractFailureV1.missingKey
            }
            return try definition(
                bundledKey,
                key.rawValue,
                key.englishDefaultValue,
                sourceOwnedTranslatorComment(key.rawValue, family: key.translatorComment)
            )
        }
        let registry = try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
        try C31LightingLocalizationPolicyV1.validate()
        return registry
    }

    static func lightingAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let entries = try C31LightingAccessibilityIDV1.allCases.map { id
            -> AccessibilityContractV1 in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .heading: role = .heading
            case .nextStep: role = .button
            case .issue, .claim, .claimBoundary, .safetyStop,
                 .historyFrozen, .manualOffline: role = .status
            default: role = .group
            }
            let hintKey: LocalizationKeyV1? =
                C31LightingAccessibilityPolicyV1.requiresActionableNextStep(for: id.rawValue)
                ? C31LightingLocalizationKeyV1.safetyNextStep.localizationKey
                : nil
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey,
                hintKey: hintKey,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        try C31LightingAccessibilityPolicyV1.validate()
        return try SemanticAccessibilityIDRegistryV1(
            entries: entries,
            localization: localization
        )
    }

    static func lightingDisplayLabel(
        for key: C31LightingLocalizationKeyV1
    ) -> String {
        guard let bundledKey = BundledLocalizationKeyV1(rawValue: key.rawValue) else {
            return key.englishDefaultValue
        }
        return localized(bundledKey)
    }

    static func lightingClaimLabel(
        for value: LightingClaimTierV1
    ) -> String {
        lightingDisplayLabel(for: C31LightingLocalizationKeyV1.claimKey(value))
    }

    static func lightingIssueLabel(
        for value: LightingIssueDispositionV1
    ) -> String {
        lightingDisplayLabel(for: C31LightingLocalizationKeyV1.issueKey(value))
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Localization_BundledLocalizationCatalogV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

extension BundledLocalizationCatalogV1 {
    static func ocrProposalRegistry() throws -> LocalizationKeyRegistryV1 {
        try C32AssistanceLocalizationPolicyV1.validate()
        let base = try scanToWorkRegistry()
        let additions = C32AssistanceLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey, meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C23 on-device OCR proposal text; proposals remain unverified until explicit field review and acceptance."),
                englishDefaultValue: C32AssistanceLocalizationPolicyV1.english(key),
                arguments: [], requiredEnglishPluralCategories: [], state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func ocrProposalAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try C32AssistanceAccessibilityPolicyV1.validate()
        let base = try scanToWorkAccessibilityRegistry(localization: localization)
        let entries = try C32AssistanceAccessibilityIDV1.allCases.map { id in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .ocrScreen: role = .screen
            case .review, .accept, .reject, .manualAvailable, .extract,
                 .acceptField, .editField, .rejectField, .manualEntry: role = .button
            case .unverified, .expired, .permissionDenied, .interrupted,
                 .confidenceWarning, .conflict, .scratchCleanup, .error: role = .status
            case .sourceCrop, .language, .proposal: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue, role: role, reachability: .whenAvailable,
                labelKey: id.localizationKey, hintKey: nil, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }
}

extension BundledLocalizationCatalogV1 {
    static func dictationLocationProposalRegistry() throws -> LocalizationKeyRegistryV1 {
        try C24DictationLocationLocalizationPolicyV1.validate()
        let base = try ocrProposalRegistry()
        let additions = C24DictationLocationLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C24 on-device dictation or one-shot location proposal; unverified until explicit review and acceptance."),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [], requiredEnglishPluralCategories: [], state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func dictationLocationProposalAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try C24DictationLocationAccessibilityPolicyV1.validate()
        let base = try ocrProposalAccessibilityRegistry(localization: localization)
        let additions = try C24DictationLocationAccessibilityIDV1.allCases.map { id in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .startDictation, .editTranscript, .acceptTranscript, .cancelDictation,
                 .captureLocation, .reviewLocation, .acceptLocation, .rejectLocation,
                 .manualEntry: role = .button
            case .dictationStatus, .locationStatus, .scratchCleanup, .error: role = .status
            case .dictationGroup, .transcript, .locationGroup, .locationProposal: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue, role: role, reachability: .whenAvailable,
                labelKey: id.localizationKey, hintKey: nil, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            )
        }
        return try base.appending(additions, localization: localization)
    }
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_Localization_BundledLocalizationCatalogV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

extension BundledLocalizationCatalogV1 {
    static func temporalEvidenceCaptureRegistry() throws -> LocalizationKeyRegistryV1 {
        try TemporalEvidenceLocalizationPolicyV1.validate()
        let base = try dictationLocationProposalRegistry()
        let existing = Set(base.definitions.map(\.key))
        let additions = TemporalEvidenceLocalizationKeyV1.allCases.compactMap { key in
            existing.contains(key.localizationKey) ? nil : LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C25 bounded offline temporal evidence capture; recording is explicit, foreground-only, reviewed, and never uploaded or automatically transcribed."),
                englishDefaultValue: TemporalEvidenceLocalizationPolicyV1.english(key),
                arguments: [], requiredEnglishPluralCategories: [], state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func temporalEvidenceCaptureAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try TemporalEvidenceAccessibilityPolicyV1.validate()
        let base = try dictationLocationProposalAccessibilityRegistry(localization: localization)
        let additions = try TemporalEvidenceAccessibilityIDV1.allCases.map { id in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .recordAudio, .recordVideo, .play, .pause, .stop, .delete, .retake,
                 .useRecording, .manualImport, .recovery, .reportLink: role = .button
            case .reviewRequired, .recording, .stoppedAtLimit, .permissionDenied,
                 .permissionRevoked, .interrupted, .error: role = .status
            case .scrub: role = .group
            case .consent, .microphonePurpose, .cameraPurpose, .playback, .duration,
                 .size, .count, .codec, .resolution, .anchor, .caption, .description,
                 .purpose, .transcript, .poster, .waveform: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue, role: role, reachability: .whenAvailable,
                labelKey: id.localizationKey, hintKey: nil, valueKey: nil,
                dynamicSuffixPolicy: .none, deprecatedAliases: []
            )
        }
        return try base.appending(additions, localization: localization)
    }
}

extension BundledLocalizationCatalogV1 {
    static func assetLabelEnglish(_ key: AssetLabelLocalizationKeyV1) -> String {
        switch key {
        case .preview: return "Label preview"
        case .explicitStart: return "Start label generation"
        case .manualShortCode: return "Enter short code manually"
        case .activeExactReprint: return "Exact current reprint"
        case .historicExportOnly: return "Historic export only"
        case .blockedMissingRelease: return "Required renderer or template release is unavailable"
        case .generated: return "Generated on this device"
        case .handedOff: return "Handed off to the system"
        case .claimBoundary: return "This does not confirm printing, delivery, or physical scanning"
        }
    }
}

extension BundledLocalizationCatalogV1 {
    static func activityContractEnglish(_ key: ActivityContractLocalizationKeyV2) -> String {
        switch key {
        case .installation: return "Installation"
        case .punchReview: return "Punch review"
        case .noPlanFallback: return "No plan is linked. Select the subject manually. Scanning is not required."
        case .deferred: return "Deferred"
        case .unableToComplete: return "Unable to complete"
        case .fieldComplete: return "Field complete"
        case .readyForReview: return "Ready for review"
        case .claimBoundary: return "Completion does not claim approval, certification, compliance, commissioning, or safety clearance."
        }
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Infrastructure_Localization_BundledLocalizationCatalogV1_swift {
    static let integrationRole = "BUNDLED_LOCALIZATION"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

// MARK: - C48 portable-review derived-consumer localization

extension BundledLocalizationCatalogV1 {
    static func portableReviewEnglish(
        _ key: C48PortableReviewLocalizationKeyV1
    ) -> String {
        switch key {
        case .responseRecorded:
            return "Response recorded"
        case .responseNotVerified:
            return "Not verified by AssetRounds"
        case .responseAcknowledged:
            return "Acknowledged"
        case .responseApproved:
            return "Approval response recorded"
        case .responseChangesRequested:
            return "Changes requested"
        case .historyOnly:
            return "History only"
        case .capabilityWarning:
            return "Anyone who can open or copy this file can respond"
        }
    }
}

enum C48PortableReviewLocalizationCatalogBoundaryV1 {
    static let sourceLocale = C48PortableReviewLocalizationPolicyV1.sourceLocale
    static let usesExistingBundledCatalog = true
    static let capabilityBytesLocalized = false
    static let capabilityProofLocalized = false
    static let responseBodyLocalized = false
    static let rawRequestResponseBytesLocalized = false
    static let verifiedIdentityLocalized = false
    static let deliveryOrSecureClaimLocalized = false

    static func validate() throws {
        try C48PortableReviewLocalizationPolicyV1.validate()
        let values = C48PortableReviewLocalizationKeyV1.allCases.map {
            BundledLocalizationCatalogV1.portableReviewEnglish($0)
        }
        guard values.allSatisfy({ !$0.isEmpty }),
              values.contains("Not verified by AssetRounds"),
              values.contains("Response recorded"),
              usesExistingBundledCatalog,
              !capabilityBytesLocalized,
              !capabilityProofLocalized,
              !responseBodyLocalized,
              !rawRequestResponseBytesLocalized,
              !verifiedIdentityLocalized,
              !deliveryOrSecureClaimLocalized else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C49 work-resource localization

extension C49WorkResourceLocalizationKeyV1 {
    var englishDefaultValue: String {
        C49WorkResourceLocalizationPolicyV1.english(self)
    }
}

extension BundledLocalizationCatalogV1 {
    static func workResourceEnglish(_ key: C49WorkResourceLocalizationKeyV1) -> String {
        key.englishDefaultValue
    }

    /// C49 is additive and English-only until a later localized UI card.
    static func workResourceRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry()
        let additions = try C49WorkResourceLocalizationKeyV1.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { key in
            LocalizationKeyDefinitionV1(
                key: try LocalizationKeyV1(key.rawValue),
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C49 bounded manual work-resource label; direct cost remains internal by default."),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

enum C49WorkResourceLocalizationBoundaryV1 {
    static let sourceLocale = "en"
    static let usesExistingBundledCatalog = true
    static let directCostDefaultIsInternal = true
    static let customerSafeCostRequiresExplicitPreview = true
    static let localPartReferenceIsSnapshotOnly = true
    static let liveInventoryLookup = false

    static func validate() throws {
        try C49WorkResourceLocalizationPolicyV1.validate()
        let values = C49WorkResourceLocalizationKeyV1.allCases.map(\.englishDefaultValue)
        guard usesExistingBundledCatalog,
              sourceLocale == C49WorkResourceLocalizationPolicyV1.sourceLocale,
              directCostDefaultIsInternal,
              customerSafeCostRequiresExplicitPreview,
              localPartReferenceIsSnapshotOnly,
              !liveInventoryLookup,
              values.allSatisfy({ !$0.isEmpty }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C50 incumbent file-exchange truth boundary

enum C50IncumbentFileExchangeLocalizationKeyV1: String, CaseIterable, Sendable {
    case disabled = "incumbent_file_exchange.disabled"
    case previewZeroWrite = "incumbent_file_exchange.preview_zero_write"
    case quarantined = "incumbent_file_exchange.quarantined"
    case fileCreated = "incumbent_file_exchange.file_created"
    case availabilityUnknown = "incumbent_file_exchange.availability_unknown"
}

extension BundledLocalizationCatalogV1 {
    static func incumbentFileExchangeEnglish(
        _ key: C50IncumbentFileExchangeLocalizationKeyV1
    ) -> String {
        switch key {
        case .disabled:
            return "No file profile is selected"
        case .previewZeroWrite:
            return "Preview only — no records were changed"
        case .quarantined:
            return "The file could not be accepted. No records were changed."
        case .fileCreated:
            return "File created locally"
        case .availabilityUnknown:
            return "The app could not confirm whether the file was saved"
        }
    }
}

enum C50IncumbentFileExchangeLocalizationBoundaryV1 {
    static let sourceLocale = "en"
    static let namesAProvider = false
    static let claimsSyncDeliveryOrAcceptance = false
    static let unknownAvailabilityIsExplicit = true

    static func validate() -> Bool {
        let values = C50IncumbentFileExchangeLocalizationKeyV1.allCases.map {
            BundledLocalizationCatalogV1.incumbentFileExchangeEnglish($0)
        }
        return sourceLocale == "en"
            && !namesAProvider
            && !claimsSyncDeliveryOrAcceptance
            && unknownAvailabilityIsExplicit
            && values.allSatisfy { !$0.isEmpty }
            && values.contains("The app could not confirm whether the file was saved")
    }
}

// MARK: - C52 portable service-request localization

extension BundledLocalizationCatalogV1 {
    static func serviceRequestEnglish(
        _ key: C52ServiceRequestLocalizationKeyV1
    ) -> String {
        C52ServiceRequestLocalizationPolicyV1.english(key)
    }

    /// C52 is English-only and additive.  These labels describe local
    /// recorded state and never claim delivery, emergency handling, identity,
    /// urgency verification, or an SLA.
    static func serviceRequestRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry()
        let additions = try C52ServiceRequestLocalizationKeyV1.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { key in
                LocalizationKeyDefinitionV1(
                    key: try LocalizationKeyV1(key.rawValue),
                    meaningID: key.rawValue,
                    translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C52 local service-request state; no delivery, emergency, identity, urgency, or SLA claim."),
                    englishDefaultValue: key.englishDefaultValue,
                    arguments: [],
                    requiredEnglishPluralCategories: [],
                    state: .active,
                    deprecatedFallbackKey: nil
                )
            }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

extension C52ServiceRequestLocalizationKeyV1 {
    var englishDefaultValue: String {
        C52ServiceRequestLocalizationPolicyV1.english(self)
    }
}

enum C52ServiceRequestLocalizationBoundaryV1 {
    static let sourceLocale = "en"
    static let usesExistingBundledCatalog = true
    static let rawCapabilityLocalized = false
    static let rawSubmissionBytesLocalized = false
    static let requesterIdentityVerified = false
    static let urgencyVerified = false
    static let deliveryClaimed = false
    static let emergencyHandlingClaimed = false
    static let serviceLevelAgreementClaimed = false

    static func validate() throws {
        try C52ServiceRequestLocalizationPolicyV1.validate()
        let values = C52ServiceRequestLocalizationKeyV1.allCases.map {
            BundledLocalizationCatalogV1.serviceRequestEnglish($0)
        }
        guard usesExistingBundledCatalog,
              sourceLocale == "en",
              values.allSatisfy({ !$0.isEmpty }),
              !rawCapabilityLocalized,
              !rawSubmissionBytesLocalized,
              !requesterIdentityVerified,
              !urgencyVerified,
              !deliveryClaimed,
              !emergencyHandlingClaimed,
              !serviceLevelAgreementClaimed else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C34 route restoration catalog

enum C34RouteBundledLocalizationCatalogV1 {
    static func safeFallbackHeading(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        String(localized: "navigation.route.fallback.heading",
               defaultValue: "This destination is unavailable",
               bundle: bundle, locale: locale,
               comment: "Heading shown when a restored route safely falls back.")
    }

    static func safeFallbackAction(
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        String(localized: "navigation.route.fallback.action",
               defaultValue: "Go to safe destination",
               bundle: bundle, locale: locale,
               comment: "Action that opens the validated safe route destination.")
    }

    static func reason(
        _ reason: RouteFallbackReasonV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        switch reason {
        case .wrongWorkspace:
            return String(localized: "navigation.route.fallback.reason.wrong_workspace", defaultValue: "That destination belongs to a different workspace.", bundle: bundle, locale: locale)
        case .staleRevision:
            return String(localized: "navigation.route.fallback.reason.stale_revision", defaultValue: "That item changed since it was last opened.", bundle: bundle, locale: locale)
        case .deletedOrTombstoned:
            return String(localized: "navigation.route.fallback.reason.deleted_or_tombstoned", defaultValue: "That item is no longer available.", bundle: bundle, locale: locale)
        case .retiredOrMissingPackage:
            return String(localized: "navigation.route.fallback.reason.retired_or_missing_package", defaultValue: "That feature is no longer available.", bundle: bundle, locale: locale)
        case .revokedAvailability:
            return String(localized: "navigation.route.fallback.reason.revoked_availability", defaultValue: "Access to that destination is no longer available.", bundle: bundle, locale: locale)
        case .protectedDataUnavailable:
            return String(localized: "navigation.route.fallback.reason.protected_data_unavailable", defaultValue: "Unlock this device to continue.", bundle: bundle, locale: locale)
        case .corruptSnapshot:
            return String(localized: "navigation.route.fallback.reason.corrupt_snapshot", defaultValue: "Saved navigation could not be read.", bundle: bundle, locale: locale)
        case .unsupportedSnapshotVersion:
            return String(localized: "navigation.route.fallback.reason.unsupported_snapshot_version", defaultValue: "Saved navigation came from an unsupported version.", bundle: bundle, locale: locale)
        case .invalidTarget:
            return String(localized: "navigation.route.fallback.reason.invalid_target", defaultValue: "That destination is not available.", bundle: bundle, locale: locale)
        }
    }

    static func validate() throws {
        try C34RouteLocalizationContractV1.validate()
        guard RouteFallbackReasonV1.wrongWorkspace.c34LocalizationKey == .wrongWorkspace,
              !safeFallbackHeading().isEmpty,
              !safeFallbackAction().isEmpty else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C53 asset-service reliability localization

extension BundledLocalizationCatalogV1 {
    static func assetServiceReliabilityEnglish(
        _ key: C53AssetServiceReliabilityLocalizationKeyV1
    ) -> String {
        C53AssetServiceReliabilityLocalizationPolicyV1.english(key)
    }

    static func assetServiceReliabilityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry()
        let additions = try C53AssetServiceReliabilityLocalizationKeyV1.allCases
            .sorted { $0.rawValue < $1.rawValue }
            .map { key in
                LocalizationKeyDefinitionV1(
                    key: try LocalizationKeyV1(key.rawValue),
                    meaningID: key.rawValue,
                    translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C53 recorded reliability state; no verified identity, uptime, safety, compliance, or release-to-service claim."),
                    englishDefaultValue: key.englishDefaultValue,
                    arguments: [],
                    requiredEnglishPluralCategories: [],
                    state: .active,
                    deprecatedFallbackKey: nil
                )
            }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

extension C53AssetServiceReliabilityLocalizationKeyV1 {
    var englishDefaultValue: String {
        C53AssetServiceReliabilityLocalizationPolicyV1.english(self)
    }
}

enum C53AssetServiceReliabilityLocalizationBoundaryV1 {
    static let sourceLocale = "en"
    static let usesExistingBundledCatalog = true
    static let rawSourceBytesLocalized = false
    static let rawCapabilityLocalized = false
    static let verifiedIdentityLocalized = false
    static let releaseToServiceLocalized = false

    static func validate() throws {
        try C53AssetServiceReliabilityLocalizationPolicyV1.validate()
        let values = C53AssetServiceReliabilityLocalizationKeyV1.allCases.map {
            BundledLocalizationCatalogV1.assetServiceReliabilityEnglish($0)
        }
        guard sourceLocale == "en",
              usesExistingBundledCatalog,
              values.allSatisfy({ !$0.isEmpty }),
              !rawSourceBytesLocalized,
              !rawCapabilityLocalized,
              !verifiedIdentityLocalized,
              !releaseToServiceLocalized else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C09 operations dashboard localization

extension BundledLocalizationCatalogV1 {
    static func operationsDashboardEnglish(
        _ key: C09OperationsDashboardLocalizationKeyV1
    ) -> String {
        C09OperationsDashboardLocalizationPolicyV1.english(key)
    }

    static func operationsDashboardLocalized(
        _ key: C09OperationsDashboardLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: operationsDashboardEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C09 display-safe operations dashboard text; no internal identity, raw reason, uptime, safety, compliance, or release-to-service claim."
        )
    }

    static func operationsDashboardRegistry() throws -> LocalizationKeyRegistryV1 {
        try C09OperationsDashboardLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = C09OperationsDashboardLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C09 display-safe operations dashboard text; no internal identity, raw reason, uptime, safety, compliance, or release-to-service claim."),
                englishDefaultValue: operationsDashboardEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

enum C09OperationsDashboardLocalizationBoundaryV1 {
    static let sourceLocale = "en"
    static let usesExistingBundledCatalog = true
    static let rawIdentityLocalized = false
    static let rawReasonLocalized = false
    static let operationalAvailabilityClaimed = false
    static let routeAdoptionClaimed = false

    static func validate() throws {
        try C09OperationsDashboardLocalizationPolicyV1.validate()
        let values = C09OperationsDashboardLocalizationKeyV1.allCases.map {
            BundledLocalizationCatalogV1.operationsDashboardEnglish($0)
        }
        guard sourceLocale == "en", usesExistingBundledCatalog,
              !rawIdentityLocalized, !rawReasonLocalized,
              !operationalAvailabilityClaimed, !routeAdoptionClaimed,
              values.allSatisfy({ !$0.isEmpty }) else {
            throw LocalizationContractFailureV1.invalidValue
        }
    }
}

// MARK: - C01 Support & Recovery Center localization

extension BundledLocalizationCatalogV1 {
    static func recoveryCenterEnglish(
        _ key: RecoveryCenterLocalizationKeyV1
    ) -> String {
        RecoveryCenterLocalizationPolicyV1.english(key)
    }

    static func recoveryCenterLocalized(
        _ key: RecoveryCenterLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: recoveryCenterEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C01 typed local recovery and support-center presentation text; no customer, work, secret, legal, delivery, or capability claim."
        )
    }

    /// C01's keys are additive. The frozen base registry remains available to
    /// inherited callers while this registry supplies the typed feature set.
    static func recoveryCenterRegistry() throws -> LocalizationKeyRegistryV1 {
        try RecoveryCenterLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = RecoveryCenterLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: "C01 typed local recovery and support-center presentation text; no customer, work, secret, legal, delivery, or capability claim.",
                englishDefaultValue: recoveryCenterEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C02 evidence curation catalog

extension BundledLocalizationCatalogV1 {
    static func evidenceCurationEnglish(
        _ key: EvidenceCurationLocalizationKeyV1
    ) -> String {
        EvidenceCurationLocalizationPolicyV1.english(key)
    }

    static func evidenceCurationLocalized(
        _ key: EvidenceCurationLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: evidenceCurationEnglish(key),
            bundle: bundle,
            locale: locale,
            comment: "C02 evidence curation presentation text; immutable originals, reversible derivatives, and no causal or compliance claim."
        )
    }

    static func evidenceCurationRegistry() throws -> LocalizationKeyRegistryV1 {
        try EvidenceCurationLocalizationPolicyV1.validate()
        let base = try registry()
        let additions = EvidenceCurationLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C02 evidence curation presentation text; immutable originals, reversible derivatives, and no causal or compliance claim."),
                englishDefaultValue: evidenceCurationEnglish(key),
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }
}

// MARK: - C21 scan-to-work localization and accessibility

extension BundledLocalizationCatalogV1 {
    static func scanToWorkLocalized(
        _ key: ScanToWorkLocalizationKeyV1,
        bundle: Bundle = .main,
        locale: Locale = .current
    ) -> String {
        localizedRegistryText(
            key: key.rawValue,
            defaultValue: key.englishDefaultValue,
            bundle: bundle,
            locale: locale,
            comment: "C21 scan-to-work state; scan is optional, preview is zero-write, and manual recovery remains complete."
        )
    }

    static func scanToWorkRegistry() throws -> LocalizationKeyRegistryV1 {
        try ScanToWorkLocalizationPolicyV1.validate()
        let base = try surveyDefinitionRegistry()
        let additions = ScanToWorkLocalizationKeyV1.allCases.map { key in
            LocalizationKeyDefinitionV1(
                key: key.localizationKey,
                meaningID: key.rawValue,
                translatorComment: sourceOwnedTranslatorComment(key.rawValue, family: "C21 scan-to-work state; do not imply authorization, automatic start, saved work, pose direction, or camera-only availability."),
                englishDefaultValue: key.englishDefaultValue,
                arguments: [],
                requiredEnglishPluralCategories: [],
                state: .active,
                deprecatedFallbackKey: nil
            )
        }
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    static func scanToWorkAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        try ScanToWorkAccessibilityPolicyV1.validate()
        let base = try surveyDefinitionAccessibilityRegistry(localization: localization)
        let entries = try ScanToWorkAccessibilityIDV1.allCases.map { id in
            let role: SemanticAccessibilityRoleV1
            switch id {
            case .screen: role = .screen
            case .scan, .manualEntry, .search, .start, .completeAndNext,
                 .deferAndNext, .keepOpenAndNext, .resume: role = .button
            case .permission, .warning, .counts, .error: role = .status
            case .resolution, .preview, .requiredWork, .poseContext, .batch: role = .group
            }
            return AccessibilityContractV1(
                semanticID: id.rawValue,
                role: role,
                reachability: .whenAvailable,
                labelKey: id.localizationKey.localizationKey,
                hintKey: nil,
                valueKey: nil,
                dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            )
        }
        return try base.appending(entries, localization: localization)
    }
}

extension BundledLocalizationCatalogV1 {
    /// Complete source-owned vocabulary. Compatibility publication still returns
    /// its selected predecessor registry; every catalog entry is validated against
    /// its owning full definition, never admitted from the resource being checked.
    static func completeSourceRegistry() throws -> LocalizationKeyRegistryV1 {
        let registries = try [
            c18LightingNightRegistry(),
            c16ShellRegistry(),
            privateSystemDiscoveryRegistry(),
            evidenceQualityCoachRegistry(),
            roundSessionRegistry(),
            offlineReadinessPreflightRegistry(),
            illuminatedSignPlaybookRegistry(),
            shopReportProfileRegistry(),
            operatingContextRegistry(),
            planRegistry(),
            lightingRegistry(),
            temporalEvidenceCaptureRegistry(),
            workResourceRegistry(),
            serviceRequestRegistry(),
            assetServiceReliabilityRegistry(),
            operationsDashboardRegistry(),
            recoveryCenterRegistry(),
            evidenceCurationRegistry(),
        ]
        return try composeSourceDefinitions(registries.map(\.definitions) + [supplementalSourceDefinitions()])
    }

    /// Identical inherited definitions may recur across additive branches.
    /// Any disagreement, including meaning, comments or defaults, fails closed.
    static func composeSourceDefinitions(_ groups: [[LocalizationKeyDefinitionV1]]) throws -> LocalizationKeyRegistryV1 {
        var definitions: [LocalizationKeyV1: LocalizationKeyDefinitionV1] = [:]
        for group in groups {
            for definition in group {
                try definition.validate()
                if let previous = definitions[definition.key] {
                    guard previous == definition else {
                        throw LocalizationContractFailureV1.incompatibleKeyReuse
                    }
                } else {
                    definitions[definition.key] = definition
                }
            }
        }
        return try LocalizationKeyRegistryV1(definitions: Array(definitions.values))
    }

    private static func supplementalSourceDefinitions() throws -> [LocalizationKeyDefinitionV1] {
        try C34RouteLocalizationContractV1.validate()
        try FastSurveyInboxLocalizationPolicyV1.validate()
        var definitions: [LocalizationKeyDefinitionV1] = []
        definitions += try ActivityContractLocalizationKeyV2.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: activityContractEnglish(key))
        }
        definitions += try AssetLabelLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: assetLabelEnglish(key))
        }
        definitions += try C12LocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: key.english)
        }
        definitions += try C13LocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: key.english)
        }
        definitions += try C34RouteLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: C34RouteLocalizationContractV1.english(key))
        }
        definitions += try C48PortableReviewLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: portableReviewEnglish(key))
        }
        definitions += try C50IncumbentFileExchangeLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: incumbentFileExchangeEnglish(key))
        }
        definitions += try FastSurveyInboxLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: key.english)
        }
        definitions += try ImportBulkPreviewLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: key.english)
        }
        definitions += try OperationalContactLocalizationKeyV1.allCases.map { key in
            try supplementalSourceDefinition(key.rawValue, english: operationalContactEnglish(key))
        }
        return definitions
    }

    private static func supplementalSourceDefinition(_ rawKey: String, english: String) throws -> LocalizationKeyDefinitionV1 {
        guard let comment = supplementalSourceComments[rawKey] else {
            throw LocalizationContractFailureV1.missingComment
        }
        return LocalizationKeyDefinitionV1(key: try LocalizationKeyV1(rawKey),
            meaningID: rawKey, translatorComment: comment, englishDefaultValue: english,
            arguments: [], requiredEnglishPluralCategories: [], state: .active, deprecatedFallbackKey: nil)
    }

    // Fixed owner-reviewed translator guidance; this table never supplies English
    // values or key admission. Each closed owning enum above supplies both.
    private static let supplementalSourceComments: [String: String] = [
        "activity.contract.claim_boundary": "C47 truthful completion boundary.",
        "activity.contract.deferred": "C47 truthful deferred state.",
        "activity.contract.field_complete": "C47 field work state; not an approval claim.",
        "activity.contract.installation": "C47 independent installation activity family name.",
        "activity.contract.no_plan_fallback": "C47 complete no-plan fallback; manual selection is required and scanning is not.",
        "activity.contract.punch_review": "C47 standalone punch-review activity family name.",
        "activity.contract.ready_for_review": "C47 review readiness state; not approved or certified.",
        "activity.contract.unable_to_complete": "C47 truthful unable-to-complete state.",
        "asset_label.active_exact_reprint": "C45 exact-current binding state.",
        "asset_label.blocked_missing_release": "C45 fail-closed state when immutable rendering inputs are unavailable.",
        "asset_label.claim_boundary": "C45 truthful output boundary.",
        "asset_label.explicit_start": "C45 explicit Start action required after preview.",
        "asset_label.generated": "C45 local generation state; no print or delivery claim.",
        "asset_label.handed_off": "C45 system handoff state; no print or delivery claim.",
        "asset_label.historic_export_only": "C45 historic state after identity or locator drift.",
        "asset_label.manual_short_code": "C45 manual entry remains available beside camera resolution.",
        "asset_label.preview": "C45 accessible preview heading; preview does not start generation.",
        "c12.queue.acknowledge": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.acknowledged": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.deduplicated": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.disclosure": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.heading": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.not_acknowledged": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.preview": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.severity": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.queue.unavailable": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.reduced_motion": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.reinspection.disclosure": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.reinspection.fresh": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.reinspection.heading": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.reinspection.unchanged": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.empty": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.error": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.interrupted": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.offline": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.protected": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c12.state.storage": "C12 recorded reinspection and attention-queue presentation; previews do not mutate facts and acknowledgement requires explicit action.",
        "c13.identity.accepted": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.ambiguity": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.confirm_consolidation": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.confirmation": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.handoff": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.heading": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.historic_alias": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.interrupted": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.no_automatic_mutation": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.reduced_motion": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "c13.identity.stale_conflict": "C13 local identity review; ambiguity and historic aliases remain explicit and consolidation requires user confirmation.",
        "fast.inbox.capture": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.heading": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.local_only": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.no_acceptance": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.not_promoted": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.preview_only": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.promoted": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.reduced_motion": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.review": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.snippet": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.collision": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.inbox": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.protected": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.recovery": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.storage": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "fast.inbox.state.unassigned": "C11 local fast-inbox capture and review; captured snippets are not accepted field facts or completion.",
        "import.preview.all_or_nothing": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.ambiguous": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.chunked": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.conflict": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.create": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.duplicate": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.heading": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.identity_disclosure": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.interrupted": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.invalid": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.mapping": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.no_receipt_claim": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.no_write": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.partial": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.plan": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.schema": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.skipped": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.source": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.stale": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.unchanged": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.unsupported": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "import.preview.update": "C08 import preview and reviewed bulk-mutation state; previews are zero-write and do not establish identity or receipts.",
        "incumbent_file_exchange.availability_unknown": "C50 truthful callback-loss result; external file availability is unknown.",
        "incumbent_file_exchange.disabled": "C50 truthful zero-profile state; no provider is named or implied.",
        "incumbent_file_exchange.file_created": "C50 local file callback result; never means synced, delivered, or provider-accepted.",
        "incumbent_file_exchange.preview_zero_write": "C50 preview state explicitly promises zero canonical writes.",
        "incumbent_file_exchange.quarantined": "C50 fail-closed file result; quarantine is scratch-only and no canonical effect occurred.",
        "navigation.route.fallback.action": "C34 action that opens the validated safe route destination.",
        "navigation.route.fallback.heading": "C34 heading shown when a restored route safely falls back.",
        "navigation.route.fallback.reason.corrupt_snapshot": "C34 safe fallback reason for unreadable device-operational route state.",
        "navigation.route.fallback.reason.deleted_or_tombstoned": "C34 safe fallback reason for an unavailable stable target.",
        "navigation.route.fallback.reason.invalid_target": "C34 safe fallback reason for an invalid typed target.",
        "navigation.route.fallback.reason.protected_data_unavailable": "C34 safe fallback reason while protected data is unavailable.",
        "navigation.route.fallback.reason.retired_or_missing_package": "C34 safe fallback reason for a retired or missing package surface.",
        "navigation.route.fallback.reason.revoked_availability": "C34 safe fallback reason for revoked feature availability.",
        "navigation.route.fallback.reason.stale_revision": "C34 safe fallback reason for stale revision-bound navigation.",
        "navigation.route.fallback.reason.unsupported_snapshot_version": "C34 safe fallback reason for a future device-operational route-state version.",
        "navigation.route.fallback.reason.wrong_workspace": "C34 safe fallback reason for a route bound to another workspace.",
        "operational_contact.action.call": "C46 explicit action for the selected operational phone contact.",
        "operational_contact.action.directions": "C46 explicit action; opens system directions for the reviewed site.",
        "operational_contact.action.email": "C46 explicit action for the selected operational email contact; no subject or body is prefilled.",
        "operational_contact.action.text": "C46 explicit action for the selected operational phone contact.",
        "operational_contact.handoff.cancelled": "C46 cancellation before the OS handoff.",
        "operational_contact.handoff.claim_boundary": "C46 truthful platform-outcome boundary.",
        "operational_contact.handoff.handed_off": "C46 OS presentation result only; does not mean sent, delivered, connected, or arrived.",
        "operational_contact.handoff.opens_system_app": "C46 accessibility hint; no outcome claim.",
        "operational_contact.handoff.system_rejected": "C46 one-call OS rejection result; no alternate target or retry is implied.",
        "operational_contact.handoff.system_unavailable": "C46 foreground/system availability result; no retry is implied.",
        "operational_contact.handoff.target_invalid": "C46 fail-closed target result.",
        "operational_contact.handoff.target_missing": "C46 live requery result.",
        "operational_contact.handoff.target_stale": "C46 exact-revision requery result requiring fresh review.",
        "portable_review.capability.forwardable_warning": "C48 cleartext capability warning; possession proves no identity or delivery.",
        "portable_review.response.acknowledged": "C48 recorded acknowledgment disposition; it does not finalize work.",
        "portable_review.response.approved": "C48 self-asserted approval response; no verified customer approval claim.",
        "portable_review.response.changes_requested": "C48 recorded changes-requested disposition.",
        "portable_review.response.history_only": "C48 immutable response history; it cannot reopen or rewrite current work.",
        "portable_review.response.not_verified": "C48 explicit trust boundary for a self-asserted external response.",
        "portable_review.response.recorded": "C48 recorded response state; does not claim delivery, identity, or approval.",
    ]
}


extension BundledLocalizationCatalogV1 {
    /// Carry material per-key guidance forward alongside the owning family's
    /// restrictions. Neither comments nor this table admit catalog keys.
    private static func sourceOwnedTranslatorComment(_ rawKey: String, family: String) -> String {
        guard let detail = sourceOwnedTranslatorDetails[rawKey] else { return family }
        return family + " " + detail
    }

    private static let sourceOwnedTranslatorDetails: [String: String] = [
        "assistance.dictation.action.accept": "C24 explicit reviewed transcript acceptance.",
        "assistance.dictation.action.cancel": "C24 explicit dictation cancellation.",
        "assistance.dictation.action.edit": "C24 explicit transcript edit action.",
        "assistance.dictation.action.start": "C24 explicit on-device dictation action.",
        "assistance.dictation.audio_interrupted": "C24 interrupted dictation state.",
        "assistance.dictation.heading": "C24 dictation heading.",
        "assistance.dictation.listening": "C24 on-device listening status.",
        "assistance.dictation.manual_entry": "C24 complete manual dictation fallback.",
        "assistance.dictation.permission_denied": "C24 dictation permission fallback.",
        "assistance.dictation.scratch_cleanup": "C24 audio/transcript scratch cleanup.",
        "assistance.dictation.transcript.unverified": "C24 unverified transcript label.",
        "assistance.dictation.unsupported_locale": "C24 unsupported locale fallback.",
        "assistance.dictation_location.accepted_reviewed_fact": "C24 accepted reviewed fact label.",
        "assistance.dictation_location.access_locked": "C24 app access lock state.",
        "assistance.dictation_location.error_focus": "C24 deterministic error focus label.",
        "assistance.dictation_location.heading": "C24 assistance heading.",
        "assistance.dictation_location.manual_fallback": "C24 shared complete manual fallback.",
        "assistance.dictation_location.no_automatic_write": "C24 no automatic write boundary.",
        "assistance.location.action.accept": "C24 reviewed location acceptance.",
        "assistance.location.action.capture_once": "C24 explicit one-shot location action.",
        "assistance.location.action.reject": "C24 location proposal rejection.",
        "assistance.location.action.review": "C24 location review action.",
        "assistance.location.heading": "C24 one-shot location heading.",
        "assistance.location.locating": "C24 location capture status.",
        "assistance.location.permission_denied": "C24 location permission fallback.",
        "assistance.location.poor_accuracy": "C24 poor accuracy fallback.",
        "assistance.location.proposal.unverified": "C24 unverified location proposal label.",
        "assistance.location.services_unavailable": "C24 disabled location services fallback.",
        "assistance.location.stale_target": "C24 stale location target recovery.",
        "assistance.location.timeout": "C24 one-shot location timeout.",
        "assistance.manual.available": "C32 truthful fallback label used when optional assistance is disabled, unavailable, denied, revoked, or interrupted.",
        "assistance.ocr.accepted_reviewed_fact": "C23 accepted reviewed fact label.",
        "assistance.ocr.access_locked": "C23 app access lock state.",
        "assistance.ocr.action.extract": "C23 explicit OCR request action.",
        "assistance.ocr.cancelled": "C23 cancellation state without partial acceptance.",
        "assistance.ocr.capability_unavailable": "C23 capability-disabled state.",
        "assistance.ocr.conflict": "C23 field conflict warning.",
        "assistance.ocr.custom_words_nontruth": "C23 customWords limitation.",
        "assistance.ocr.error_focus": "C23 deterministic error focus label.",
        "assistance.ocr.field.accept": "C23 explicit per-field accept action.",
        "assistance.ocr.field.edit": "C23 explicit per-field edit action.",
        "assistance.ocr.field.reject": "C23 explicit per-field reject action.",
        "assistance.ocr.heading": "C23 OCR proposal heading.",
        "assistance.ocr.language": "C23 requested recognition language label.",
        "assistance.ocr.low_confidence": "C23 low-confidence review warning; confidence is not truth.",
        "assistance.ocr.manual_entry": "C23 complete manual field path.",
        "assistance.ocr.memory_pressure": "C23 memory pressure fallback.",
        "assistance.ocr.no_automatic_write": "C23 zero automatic-write boundary.",
        "assistance.ocr.scratch_cleanup": "C23 scratch cleanup status.",
        "assistance.ocr.source_crop": "C23 bounded source crop label.",
        "assistance.ocr.stale_target": "C23 stale target recovery.",
        "assistance.ocr.supported": "C23 supported on-device OCR state.",
        "assistance.ocr.unsupported_device": "C23 unsupported device state.",
        "assistance.ocr.unsupported_language": "C23 unsupported language with manual fallback.",
        "assistance.permission.denied": "C32 non-color permission state; optional assistance is unavailable and manual entry remains available.",
        "assistance.proposal.accept": "C32 action that accepts a reviewed value through the canonical expected-revision writer.",
        "assistance.proposal.expired": "C32 status shown when a proposal can no longer be accepted because its reviewed context changed.",
        "assistance.proposal.reject": "C32 action that discards an ephemeral proposal and its scratch data without retaining a rejected-suggestion corpus.",
        "assistance.proposal.review": "C32 action that opens explicit review without writing the proposed value.",
        "assistance.proposal.unverified": "C32 status for an ephemeral assistance value that has not been reviewed or accepted as a canonical fact.",
        "evidence.curation.item.move_earlier": "C02 accessible explicit-order control.",
        "evidence.curation.item.move_later": "C02 accessible explicit-order control.",
        "evidence.curation.item.retake": "C02 reviewed evidence retake action; stages a new immutable original and never overwrites history.",
        "evidence.quality.coach.heading": "C10 contained coach heading.",
        "evidence.quality.coach.introduction": "C10 truthful review scope.",
        "illuminated.playbook.capture.close_detail": "C03 released capture purpose.",
        "illuminated.playbook.capture.complete": "C03 capture status.",
        "illuminated.playbook.capture.heading": "C03 capture traceability presentation.",
        "illuminated.playbook.capture.missing": "C03 capture status.",
        "illuminated.playbook.capture.required": "C03 capture status.",
        "illuminated.playbook.capture.wide_context": "C03 released capture purpose.",
        "illuminated.playbook.capture.work_context": "C03 optional capture purpose, shown only when the released pack supplies it.",
        "illuminated.playbook.color_mismatch": "C03 exact released playbook label.",
        "illuminated.playbook.dark_section": "C03 exact released playbook label.",
        "illuminated.playbook.dim_or_uneven": "C03 exact released playbook label.",
        "illuminated.playbook.disclaimer": "C03 exact visible-condition, non-certification disclaimer.",
        "illuminated.playbook.facts.checked_time": "C03 structured report fact label.",
        "illuminated.playbook.facts.could_not_verify_reason": "C03 structured report fact label.",
        "illuminated.playbook.facts.heading": "C03 structured report-fact presentation.",
        "illuminated.playbook.facts.outcome": "C03 structured report fact label.",
        "illuminated.playbook.facts.outcome.could_not_verify": "C03 released outcome label.",
        "illuminated.playbook.facts.outcome.no_visible_issue": "C03 released outcome label.",
        "illuminated.playbook.facts.outcome.visible_issue": "C03 released outcome label.",
        "illuminated.playbook.facts.report_trace": "C03 traceability presentation.",
        "illuminated.playbook.facts.selected_condition": "C03 structured report fact label.",
        "illuminated.playbook.facts.stage": "C03 structured report fact label.",
        "illuminated.playbook.facts.stage.check": "C03 released stage label.",
        "illuminated.playbook.facts.stage.recheck": "C03 released stage label.",
        "illuminated.playbook.facts.visible_conditions_only": "C03 claims boundary.",
        "illuminated.playbook.flicker_or_intermittent": "C03 exact released playbook label.",
        "illuminated.playbook.general_visible_condition": "C03 exact released playbook label.",
        "illuminated.playbook.heading": "C03 illuminated-sign playbook presentation; visible-condition-only facts and no certification claim.",
        "illuminated.playbook.list.heading": "C03 illuminated-sign playbook presentation; visible-condition-only facts and no certification claim.",
        "illuminated.playbook.list.selected": "C03 selected-playbook state; this is not capture completion.",
        "illuminated.playbook.other_visible_condition": "C03 exact released playbook label.",
        "illuminated.playbook.physical_damage": "C03 exact released playbook label.",
        "illuminated.playbook.pose.heading": "C03 typed pose-editor heading.",
        "illuminated.playbook.pose.review_required": "C03 typed pose completion boundary.",
        "illuminated.playbook.pose.reviewed": "C03 typed pose state; no bare direction is displayed.",
        "illuminated.playbook.pose.unavailable": "C03 fail-closed pose state.",
        "illuminated.playbook.preflight.after_dark": "C03 preflight guidance; it does not claim system verification or an accepted acknowledgement.",
        "illuminated.playbook.preflight.heading": "C03 preflight presentation.",
        "illuminated.playbook.preflight.safe_authorized_position": "C03 preflight guidance; it does not claim system verification or an accepted acknowledgement.",
        "illuminated.playbook.retake.disclosure": "C03 immutable history disclosure.",
        "illuminated.playbook.state.blocked": "C03 fail-closed state.",
        "illuminated.playbook.state.cancelled": "C03 cancellation state; no completed result is claimed.",
        "illuminated.playbook.state.low_storage": "C03 storage failure state.",
        "illuminated.playbook.state.offline_ready": "C03 local readiness state.",
        "illuminated.playbook.state.permission_denied": "C03 permission failure state.",
        "illuminated.playbook.state.protected_data_unavailable": "C03 protected-data failure state.",
        "illuminated.playbook.state.recovered": "C03 recovered checkpoint presentation; it does not claim completion.",
        "illuminated.playbook.state.recovery_required": "C03 deterministic recovery state.",
        "lighting.day_inventory.claim_boundary": "C17 observation-only claim boundary.",
        "lighting.day_inventory.daylight_caution": "C17 cautious daylight observation boundary.",
        "lighting.day_inventory.daylight_observation": "C17 records daylight energized state as observation only.",
        "lighting.day_inventory.night_followup": "C17 stable day-to-night follow-up label.",
        "lighting.day_inventory.offline.blocked": "C17 derived local readiness failure with explicit safe action.",
        "lighting.day_inventory.offline.ready": "C17 derived local readiness state; no safety or completion claim.",
        "lighting.day_inventory.safety_stop": "C17 reason-bearing safety stop heading; no authorization claim.",
        "lighting.day_inventory.safety_stop_detail": "C17 hard-stop copy precedes unsafe or energized work.",
        "lighting.day_inventory.state.not_applicable": "C17 explicit not-applicable condition; never rendered as pass.",
        "lighting.day_inventory.state.not_observed": "C17 explicit not-observed condition; never rendered as pass.",
        "lighting.day_inventory.state.unknown": "C17 explicit unknown condition; never rendered as pass.",
        "lighting.day_inventory.title": "C17 exterior-lighting daylight inventory title.",
        "lighting.night_workflow.claim_boundary": "C18 cautious report limitation.",
        "lighting.night_workflow.expected_state": "C18 expected state remains separate from observation.",
        "lighting.night_workflow.group.retains_children": "C18 group never removes child history or closure obligations.",
        "lighting.night_workflow.issue.open": "C18 open issue state.",
        "lighting.night_workflow.issue.reopened": "C18 recurrence appends a reopen state.",
        "lighting.night_workflow.issue.resolved": "C18 recorded-scope resolution; not a safety or compliance conclusion.",
        "lighting.night_workflow.observed_state": "C18 observed state does not imply diagnosis.",
        "lighting.night_workflow.offline.blocked": "C18 derived readiness failure.",
        "lighting.night_workflow.offline.ready": "C18 derived readiness; no safety claim.",
        "lighting.night_workflow.state.inconclusive": "C18 explicit inconclusive result.",
        "lighting.night_workflow.state.unknown": "C18 explicit unknown result.",
        "lighting.night_workflow.title": "C18 night workflow title.",
        "operations_dashboard.asset_name": "Label that isolates optional user-authored asset content from system state copy.",
        "operations_dashboard.correct_exposure": "Action that delegates an exposure or coverage correction to the C09 coordinator.",
        "operations_dashboard.correct_exposure.hint": "Accessibility hint for the exposure correction action.",
        "operations_dashboard.definition_version": "Label for the deterministic metric-definition version.",
        "operations_dashboard.exposure.heading": "Heading for recorded exposure and coverage review.",
        "operations_dashboard.exposure.qualified": "Qualified recorded exposure status.",
        "operations_dashboard.exposure.unavailable": "Unqualified recorded exposure status.",
        "operations_dashboard.heading": "Heading for the non-adopted local operations dashboard.",
        "operations_dashboard.introduction": "Explains that values need recorded qualifying evidence.",
        "operations_dashboard.metric.full_interruption_availability": "Display name for the typed full-interruption availability metric.",
        "operations_dashboard.metric.mtbf": "Display name for the typed mean-time-between-failures metric.",
        "operations_dashboard.metric.unavailable": "Truthful unavailable status for an unqualified reliability metric.",
        "operations_dashboard.metrics.heading": "Heading for qualified local reliability projections.",
        "operations_dashboard.provenance.corrected": "Typed timeline provenance for a correction.",
        "operations_dashboard.provenance.recorded": "Typed timeline provenance for a recorded source event.",
        "operations_dashboard.provenance.superseded": "Typed timeline provenance for a superseded event.",
        "operations_dashboard.review_exposure": "Action that opens read-only exposure and coverage review.",
        "operations_dashboard.review_exposure.hint": "Accessibility hint for exposure review.",
        "operations_dashboard.review_metric_details": "Action that asks the coordinator to present metric-definition detail.",
        "operations_dashboard.review_metric_details.hint": "Accessibility hint for metric detail.",
        "operations_dashboard.timeline.corrective_work": "Typed timeline event for canonical corrective work.",
        "operations_dashboard.timeline.empty": "Truthful empty state for the display-safe service timeline.",
        "operations_dashboard.timeline.evidence_association": "Typed timeline event for canonical evidence association.",
        "operations_dashboard.timeline.explicit_asset_change": "Typed timeline event for a canonical asset change.",
        "operations_dashboard.timeline.finding": "Typed timeline event for a canonical finding.",
        "operations_dashboard.timeline.heading": "Heading for asset service history and provenance.",
        "operations_dashboard.timeline.impact_segment": "Typed timeline event for a C53 service-impact segment.",
        "operations_dashboard.timeline.incident": "Typed timeline event for a C53 asset-service incident.",
        "operations_dashboard.timeline.inspection": "Typed timeline event for a canonical inspection.",
        "operations_dashboard.timeline.placement_change": "Typed timeline event for a C37 placement change.",
        "operations_dashboard.timeline.qualified_exposure": "Typed timeline event for C53 qualified service exposure.",
        "operations_dashboard.timeline.recheck": "Typed timeline event for a canonical recheck.",
        "operations_dashboard.timeline.report": "Typed timeline event for a canonical report.",
        "operations_dashboard.unavailable.cancelled": "Truthful unavailable reason after cancellation.",
        "operations_dashboard.unavailable.data": "Truthful unavailable reason for unavailable recorded data.",
        "operations_dashboard.unavailable.missing_coverage": "Truthful unavailable reason for incomplete coverage.",
        "operations_dashboard.unavailable.missing_qualified_exposure": "Truthful unavailable reason for missing qualified exposure.",
        "operations_dashboard.unavailable.no_qualifying_failure_start": "Truthful unavailable reason for no qualifying failure start.",
        "operations_dashboard.unavailable.no_reason": "Fallback when the projection did not provide a display-safe unavailable reason.",
        "operations_dashboard.unavailable.protected_data": "Truthful unavailable reason for protected data lock.",
        "private.system.discovery.intent.manual-fallback": "Generic C14 manual fallback without record disclosure.",
        "private.system.discovery.intent.open-assets": "C14 read-only foreground App Intent title.",
        "private.system.discovery.intent.open-reports": "C14 read-only foreground App Intent title.",
        "private.system.discovery.intent.open-today": "C14 read-only foreground App Intent title.",
        "private.system.discovery.intent.unavailable": "Generic C14 unavailable outcome that intentionally reveals no record existence.",
        "private.system.discovery.intent.unlock-required": "Generic C14 protected-data outcome that intentionally reveals no record existence.",
        "private.system.discovery.settings.disabled": "C14 default-off discovery state.",
        "private.system.discovery.settings.disclosure": "C14 disclosure that discovery is private, opt-in, and restricted to selected real workspaces.",
        "private.system.discovery.settings.heading": "C14 private on-device system discovery settings heading.",
        "private.system.discovery.settings.indexing-toggle": "C14 opt-in private on-device discovery setting.",
        "private.system.discovery.settings.practice-excluded": "C14 policy disclosure that Practice is excluded.",
        "private.system.discovery.settings.unavailable": "C14 capability-unavailable discovery state.",
        "round.offline_readiness.cancel": "C06 cancel action.",
        "round.offline_readiness.fallback.approved_manual_procedure": "C06 local-only fallback.",
        "round.offline_readiness.fallback.contact_supervisor": "C06 local-only fallback.",
        "round.offline_readiness.fallback.defer_field_work": "C06 local-only fallback.",
        "round.offline_readiness.fallback.do_not_start": "C06 local-only fallback.",
        "round.offline_readiness.heading": "C06 local-only offline-readiness heading.",
        "round.offline_readiness.loading": "C06 local-only loading state.",
        "round.offline_readiness.local_only_disclosure": "C06 no sync/upload/network/account claim.",
        "round.offline_readiness.manual_fallback": "C06 manual fallback label.",
        "round.offline_readiness.not_safe_to_start_or_close": "C06 non-ready safety boundary.",
        "round.offline_readiness.optional": "C06 optional requirement label.",
        "round.offline_readiness.reason.clock_or_time_zone_changed": "C06 clock drift reason.",
        "round.offline_readiness.reason.clock_uncheckable": "C06 clock reason.",
        "round.offline_readiness.reason.corrupt_mandatory_content": "C06 required corrupt content reason.",
        "round.offline_readiness.reason.corrupt_optional_content": "C06 optional corrupt content reason.",
        "round.offline_readiness.reason.field_reference_unavailable": "C06 field-reference reason.",
        "round.offline_readiness.reason.guidance_reference_mismatch": "C06 guidance mismatch reason.",
        "round.offline_readiness.reason.insufficient_storage": "C06 storage reason.",
        "round.offline_readiness.reason.missing_mandatory_content": "C06 required content reason.",
        "round.offline_readiness.reason.missing_optional_content": "C06 optional content reason.",
        "round.offline_readiness.reason.package_mismatch": "C06 exact package mismatch reason.",
        "round.offline_readiness.reason.partial_mandatory_content": "C06 required partial content reason.",
        "round.offline_readiness.reason.partial_optional_content": "C06 optional partial content reason.",
        "round.offline_readiness.reason.protected_data_unavailable": "C06 protected-data reason.",
        "round.offline_readiness.reason.selected_asset_mismatch": "C06 asset mismatch reason.",
        "round.offline_readiness.reason.source_binding_drift": "C06 source drift reason.",
        "round.offline_readiness.reason.storage_arithmetic_overflow": "C06 storage reason.",
        "round.offline_readiness.reason.storage_uncheckable": "C06 storage reason.",
        "round.offline_readiness.reason.wrong_workspace_content": "C06 wrong-workspace reason.",
        "round.offline_readiness.reasons.heading": "C06 exact reason label.",
        "round.offline_readiness.rebuild": "C06 rebuild action.",
        "round.offline_readiness.rebuild_unavailable": "C06 no-coordinator action boundary.",
        "round.offline_readiness.remediation": "C06 remediation label.",
        "round.offline_readiness.remediation.check_clock": "C06 remediation.",
        "round.offline_readiness.remediation.check_storage": "C06 remediation.",
        "round.offline_readiness.remediation.free_storage": "C06 remediation.",
        "round.offline_readiness.remediation.rebuild": "C06 remediation.",
        "round.offline_readiness.remediation.reselect_assets": "C06 remediation.",
        "round.offline_readiness.remediation.restore_content": "C06 remediation.",
        "round.offline_readiness.remediation.restore_field_reference": "C06 remediation.",
        "round.offline_readiness.remediation.restore_guidance": "C06 remediation.",
        "round.offline_readiness.remediation.restore_package": "C06 remediation.",
        "round.offline_readiness.remediation.unlock": "C06 remediation.",
        "round.offline_readiness.required": "C06 required requirement label.",
        "round.offline_readiness.requirements.heading": "C06 requirements heading.",
        "round.offline_readiness.safe_to_close": "C06 ready-only local close claim.",
        "round.offline_readiness.safe_to_start": "C06 ready-only local start claim.",
        "round.offline_readiness.state.blocked": "C06 blocked local-only state.",
        "round.offline_readiness.state.ready": "C06 ready local-only state.",
        "round.offline_readiness.state.stale": "C06 stale local-only state.",
        "round.offline_readiness.state.warning": "C06 warning local-only state.",
        "round.offline_readiness.unavailable": "C06 unavailable state; no safety claim.",
        "scan.work.accessibility.error_focus": "C21 error focus announcement.",
        "scan.work.accessibility.reduced_motion": "C21 Reduce Motion state remains textual.",
        "scan.work.action.manual": "C21 complete manual fallback action.",
        "scan.work.action.resume": "C21 exact recorded resume action.",
        "scan.work.action.scan": "C21 optional camera scan action.",
        "scan.work.action.search": "C21 local asset search fallback action.",
        "scan.work.action.start": "C21 sole explicit start action.",
        "scan.work.batch.counts": "C21 textual batch counts.",
        "scan.work.batch.review": "C21 explicit batch review before mutation.",
        "scan.work.camera.unavailable": "C21 unsupported or unavailable camera state.",
        "scan.work.heading": "C21 scan-to-work heading.",
        "scan.work.input.damaged": "C21 damaged code with manual recovery.",
        "scan.work.input.revoked": "C21 revoked locator state.",
        "scan.work.next.complete": "C21 atomic Complete and Next action.",
        "scan.work.next.defer": "C21 atomic Defer and Next action.",
        "scan.work.next.keep_open": "C21 atomic Keep open and Next action.",
        "scan.work.outcome.already_in_round": "C21 ALREADY_IN_ROUND resolver outcome.",
        "scan.work.outcome.ambiguous": "C21 AMBIGUOUS resolver outcome.",
        "scan.work.outcome.duplicate_in_selection": "C21 DUPLICATE_IN_SELECTION resolver outcome.",
        "scan.work.outcome.foreign": "C21 FOREIGN resolver outcome without exposing foreign data.",
        "scan.work.outcome.not_found": "C21 NOT_FOUND local resolver outcome.",
        "scan.work.outcome.not_offline_ready": "C21 NOT_OFFLINE_READY resolver outcome.",
        "scan.work.outcome.ready": "C21 READY resolver outcome.",
        "scan.work.outcome.retired_or_replaced": "C21 RETIRED_OR_REPLACED resolver outcome.",
        "scan.work.outcome.stale": "C21 STALE resolver outcome.",
        "scan.work.permission.denied": "C21 camera denial with complete fallback.",
        "scan.work.permission.purpose": "C21 camera purpose and complete fallback disclosure.",
        "scan.work.pose.no_mutation": "C21 scan and preview never infer or mutate pose.",
        "scan.work.pose.preserved": "C21 qualified pose parity disclosure.",
        "scan.work.preview.asset": "C21 stable resolved asset label.",
        "scan.work.preview.asset_changed": "C21 stale preview after asset revision change.",
        "scan.work.preview.multiple_work_items": "C21 two-or-more matching work item choice.",
        "scan.work.preview.only": "C21 preview is explicitly zero-write.",
        "scan.work.preview.packet_incomplete": "C21 incomplete offline packet state.",
        "scan.work.preview.required_work": "C21 required available work label.",
        "scan.work.preview.site_context": "C21 site and context label.",
        "scan.work.readiness.blocked": "C21 blocked local readiness text, not color-only.",
        "scan.work.readiness.ready": "C21 local readiness text, not color-only.",
        "scan.work.setup.nonsemantic_only": "C21 same-setup restriction forbids semantic copying.",
        "scan.work.state.interrupted": "C21 exact next-item interruption recovery state.",
        "scan.work.state.start_failed": "C21 failed explicit start with no success claim.",
        "service_reliability.cause.unverified": "C53 cause assessment is recorded provenance only; it does not verify identity, diagnosis, or responsibility.",
        "service_reliability.exposure.qualified": "C53 qualified exposure is an explicit interval input and does not claim uptime or release to service.",
        "service_reliability.incident.recorded": "C53 records an observed operational-impact incident without inferring cause, safety, compliance, or service release.",
        "service_reliability.metric.unavailable": "C53 reliability metrics remain unavailable when exposure, coverage, intervals, origin, or exclusions do not qualify.",
        "service_reliability.restoration.recorded": "C53 restoration is recorded evidence only and does not imply safety, compliance, approval, or release to service.",
        "service_request.contact.unverified": "C52 requester contact is a self-asserted, unverified value.",
        "service_request.duplicate.suggestion": "C52 duplicate projection is suggestion-only and requires explicit review.",
        "service_request.intake.manual": "C52 local manual intake label; it does not claim delivery or emergency handling.",
        "service_request.state.accepted": "C52 local disposition state after explicit acceptance.",
        "service_request.state.declined": "C52 local disposition state after an explicit decline reason.",
        "service_request.state.history_only": "C52 history-only state; it does not imply current work or delivery.",
        "service_request.state.untriaged": "C52 local state awaiting explicit review and disposition.",
        "service_request.status.no_delivery_claim": "C52 status wording records local state without claiming delivery confirmation.",
        "service_request.urgency.self_asserted": "C52 urgency is supplied by the requester and is not verified by AssetRounds.",
        "shell.availability.available": "C16 textual available state.",
        "shell.availability.heading": "C16 reason-bearing availability heading.",
        "shell.availability.reason": "C16 reason label; availability never relies on color alone.",
        "shell.availability.reason.app-locked": "C16 app-lock reason without content disclosure.",
        "shell.availability.reason.available": "C16 explicit available reason.",
        "shell.availability.reason.disabled-by-policy": "C16 disabled-by-policy reason.",
        "shell.availability.reason.permission-not-granted": "C16 permission denial reason.",
        "shell.availability.reason.practice-workspace-required": "C16 practice-workspace requirement.",
        "shell.availability.reason.protected-data-unavailable": "C16 protected-data reason without content disclosure.",
        "shell.availability.reason.real-workspace-required": "C16 real-workspace requirement.",
        "shell.availability.reason.reconciliation-pending": "C16 provisional shell state pending accepted S10.6 reconciliation.",
        "shell.availability.reason.source-unavailable": "C16 local source unavailable reason.",
        "shell.availability.reason.stale-source": "C16 stale local source reason.",
        "shell.availability.reason.unsupported": "C16 unsupported capability reason.",
        "shell.availability.unavailable": "C16 textual unavailable state.",
        "shell.help.action": "C16 contextual help action.",
        "shell.help.body": "C16 contextual help body.",
        "shell.help.title": "C16 contextual help entry title.",
        "shell.practice.share.cancel": "C16 Practice sharing cancellation action.",
        "shell.practice.share.confirm": "C16 explicit Practice sharing action.",
        "shell.practice.share.message": "C16 Practice sharing limitation.",
        "shell.practice.share.title": "C16 explicit Practice sharing confirmation title.",
        "shell.practice.watermark": "C16 required visible and spoken Practice watermark.",
        "shell.product-changes.body": "C16 product changes entry body.",
        "shell.product-changes.title": "C16 product changes entry title.",
        "shell.resume.action": "C16 durable resume action.",
        "shell.resume.title": "C16 durable resume title.",
        "shell.root.assets.hint": "C16 Assets root accessibility hint.",
        "shell.root.assets.title": "C16 provisional third task-first shell root.",
        "shell.root.reports.hint": "C16 Reports root accessibility hint.",
        "shell.root.reports.title": "C16 provisional fourth task-first shell root.",
        "shell.root.today.hint": "C16 Today root accessibility hint.",
        "shell.root.today.title": "C16 provisional first task-first shell root.",
        "shell.root.work.hint": "C16 Work root accessibility hint.",
        "shell.root.work.title": "C16 provisional second task-first shell root.",
        "shell.starter-workspace.action": "C16 explicit starter workspace creation action.",
        "shell.starter-workspace.title": "C16 starter workspace title.",
        "shop.profile.activation.heading": "C04 activation label.",
        "shop.profile.activation.off": "C04 activation state.",
        "shop.profile.activation.on": "C04 activation state.",
        "shop.profile.audience.heading": "C04 audience label.",
        "shop.profile.confirmation.heading": "C04 final confirmation heading.",
        "shop.profile.confirmation.recorded": "C04 confirmation state.",
        "shop.profile.confirmation.required": "C04 confirmation gate.",
        "shop.profile.default_off": "C04 default-off presentation.",
        "shop.profile.detector.blocked": "C04 blocking detector state.",
        "shop.profile.detector.heading": "C04 audience privacy detector heading.",
        "shop.profile.detector.pass": "C04 passing detector state.",
        "shop.profile.handoff.available": "C04 typed receipt state.",
        "shop.profile.handoff.heading": "C04 handoff heading.",
        "shop.profile.heading": "C04 shop-profile open-evidence handoff presentation.",
        "shop.profile.limitations": "C04 no-certification limitation.",
        "shop.profile.no_delivery_claim": "C04 no delivery claim boundary.",
        "shop.profile.packaging.combined": "C04 packaging disposition.",
        "shop.profile.packaging.heading": "C04 packaging label.",
        "shop.profile.packaging.separate": "C04 packaging disposition.",
        "shop.profile.preset.heading": "C04 preset label.",
        "shop.profile.preview.digest": "C04 digest value label.",
        "shop.profile.preview.exact_bytes": "C04 exact-byte value label.",
        "shop.profile.preview.heading": "C04 exact-byte preview heading.",
        "shop.profile.profile.heading": "C04 profile presentation.",
        "shop.profile.recovery.required": "C04 recovery state.",
        "shop.profile.retry": "C04 retry action.",
        "shop.profile.semantic_text.heading": "C04 semantic text alternative heading.",
        "shop.profile.status.cancelled": "C04 cancellation state.",
        "shop.profile.status.low_storage": "C04 storage state.",
        "shop.profile.status.protected_data": "C04 protected-data state.",
        "shop.profile.status.stale": "C04 stale preview state.",
        "shop.profile.status.unavailable": "C04 failed preparation state.",
        "temporal_evidence.action.delete": "C25 explicit review delete action.",
        "temporal_evidence.action.pause": "C25 review pause action.",
        "temporal_evidence.action.play": "C25 review playback action.",
        "temporal_evidence.action.record_audio": "C25 explicit foreground audio capture action.",
        "temporal_evidence.action.record_video": "C25 explicit foreground video capture action.",
        "temporal_evidence.action.retake": "C25 explicit retake action; the prior accepted original remains immutable.",
        "temporal_evidence.action.scrub": "C25 named time-position control.",
        "temporal_evidence.action.stop": "C25 recording stop action.",
        "temporal_evidence.action.use_recording": "C25 sole explicit action that may request canonical acceptance after review.",
        "temporal_evidence.backgrounded": "C25 foreground-only boundary.",
        "temporal_evidence.caption": "C25 human-authored recording caption.",
        "temporal_evidence.codec.unavailable": "C25 unavailable codec with manual fallback.",
        "temporal_evidence.consent.explicit": "C25 consent boundary; capture never starts implicitly.",
        "temporal_evidence.description": "C25 human-authored accessible recording description.",
        "temporal_evidence.description.required": "C33 accessible-description review requirement.",
        "temporal_evidence.disk_full": "C25 disk-full failure with no partial canonical clip.",
        "temporal_evidence.kind.audio": "C33 non-color media-kind label.",
        "temporal_evidence.kind.video": "C33 non-color media-kind label.",
        "temporal_evidence.limit.bytes": "C33 truthful hard-stop reason.",
        "temporal_evidence.limit.codec": "C25 unsupported codec state without a compatibility claim.",
        "temporal_evidence.limit.count": "C25 deterministic package or session recording-count stop.",
        "temporal_evidence.limit.duration": "C33 truthful hard-stop reason.",
        "temporal_evidence.limit.resolution": "C25 bounded video resolution state.",
        "temporal_evidence.limit.storage": "C33 low-storage state that does not claim a partial save.",
        "temporal_evidence.manual_import": "C33 manual/offline fallback while live recording remains deferred.",
        "temporal_evidence.permission.camera.purpose": "C25 purpose copy for the independent video permission matrix.",
        "temporal_evidence.permission.microphone.purpose": "C25 purpose copy for the independent microphone permission.",
        "temporal_evidence.permission.revoked": "C25 mid-recording permission revocation with no partial-save claim.",
        "temporal_evidence.protected_data.unavailable": "C25 protected-data lock state.",
        "temporal_evidence.purpose": "C25 purpose-bound evidence field.",
        "temporal_evidence.recovery": "C25 interruption recovery action.",
        "temporal_evidence.report.link": "C25 report link to separately stored bounded media.",
        "temporal_evidence.report.poster": "C25 accessible poster-image label; original media is not embedded by default.",
        "temporal_evidence.report.waveform": "C25 accessible audio waveform label; original audio is not embedded by default.",
        "temporal_evidence.review_required": "C33 status before a bounded clip can be accepted into canonical evidence.",
        "temporal_evidence.state.recording": "C25 visible and spoken non-color recording state.",
        "temporal_evidence.state.stopped": "C25 visible and spoken stopped state.",
        "temporal_evidence.time_anchor": "C25 time-coded anchor action.",
        "temporal_evidence.transcript.required": "C33 human-authored transcript review requirement; no automatic transcription claim.",
        "work_resource.internal_only": "C49 direct cost is internal by default and must not leak into customer-safe output.",
        "temporal_evidence.cancelled": "C33 cancellation state with truthful canonical-save status. Use only after successful terminal cancellation of the current unaccepted review; do not describe prior evidence or an unresolved acceptance outcome as unsaved.",
        "temporal_evidence.permission.denied": "C33 permission-denial fallback without initiating a capture runtime. Name a manual alternative only when the pinned rule permits that path; denied capture does not grant arbitrary file-import permission.",
        "lighting.claim.boundary": "English-only C31 claim boundary; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.criterion": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.derived": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.external_reference": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.measured": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.observed": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.claim.unavailable": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.history.frozen": "English-only C31 historic display label; final report interpretation remains immutable.",
        "lighting.issue.open": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.issue.recorded": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.issue.resolved": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.issue.superseded": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.manual_offline": "English-only C31 manual/offline path label; no sensor, network, or remote-delivery claim.",
        "lighting.measurement.calibration": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.measurement.heading": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.measurement.illuminance": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.observation.heading": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.observation.recorded": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.safety.next_step": "English-only C31 actionable label for reviewing recorded references; it does not grant authority or claim delivery.",
        "lighting.safety.stop": "English-only C31 label for a recorded stop state; it does not grant authority or make a safety conclusion.",
        "lighting.system.control_groups": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.system.heading": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.system.luminaires": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.system.topology": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "lighting.system.zones": "English-only C31 label for recorded lighting facts; no operational, safety, security, ADA, IES, or compliance conclusion.",
        "plan.history.open_original_revision": "C19 historic report action bound to its original revision, never latest.",
        "plan.offline.historic_read_only": "C19 historic plan revision is readable but never substituted for current work.",
        "plan.offline.missing_plan": "C19 reason-bearing readiness failure for an absent exact plan revision.",
        "plan.offline.missing_reference": "C19 reason-bearing readiness failure for missing reference bytes.",
        "plan.offline.not_applicable": "C19 explicit absence: the package rule does not require a plan for this work item.",
        "plan.offline.openability_failed": "C19 reason-bearing readiness failure after local openability validation.",
        "plan.offline.protected_data_unavailable": "C19 reason-bearing readiness failure while protected local data is unavailable.",
        "plan.offline.ready": "C19 derived readiness; not a durable ready flag.",
        "plan.offline.reference_unavailable": "C19 reason-bearing readiness failure for stale lifecycle state.",
        "plan.offline.storage_insufficient": "C19 reason-bearing readiness failure for local capacity.",
        "plan.page.navigation": "C19 accessible page navigation heading.",
        "plan.placement.create": "C19 plan placement creation action.",
        "plan.placement.item": "C19 exact label key carried by each ordered accessible placement.",
        "plan.placement.link": "C19 action linking recorded work to an exact placement.",
        "plan.placement.list": "C19 accessible ordered placement list heading.",
        "plan.placement.move": "C19 plan placement move action.",
        "plan.placement.row": "C19 accessible placement row label.",
        "plan.rebase.approve": "C19 explicit rebase approval action.",
        "plan.rebase.reject": "C19 explicit rebase rejection action.",
        "plan.rebase.review": "C19 explicit rebase review heading; preview remains unapplied.",
        "plan.thumbnail.navigation": "C19 accessible thumbnail navigation heading.",
        "plan.viewport.not_physical_direction": "C19 non-visual boundary: viewport and display rotation are presentation only.",
        "plan.work_surface.resume": "C19 contextual resume action.",
        "plan.work_surface.route.assets": "C19 contextual route to the plan list under Assets.",
        "plan.work_surface.route.work": "C19 contextual plan route for the selected work item.",
        "schedule.accessibility.error_focus": "C22 deterministic error-focus label.",
        "schedule.accessibility.reduced_motion": "C22 Reduce Motion state remains textual.",
        "schedule.action.end": "C22 explicit schedule end action.",
        "schedule.action.pause": "C22 explicit schedule pause action.",
        "schedule.action.resume": "C22 explicit schedule resume action.",
        "schedule.action.save": "C22 explicit schedule save action.",
        "schedule.action.start_once": "C22 occurrence start-once action.",
        "schedule.duration_window": "C22 schedule duration and due-window label.",
        "schedule.editor": "C22 recurring schedule editor heading.",
        "schedule.editor.review": "C22 explicit review before schedule save.",
        "schedule.exception_behavior": "C22 exception behavior label.",
        "schedule.horizon.bounded": "C22 bounded occurrence generation disclosure.",
        "schedule.interruption": "C22 interrupted canonical update state.",
        "schedule.offline.partial": "C22 partial local packet state.",
        "schedule.offline.ready": "C22 exact local readiness state.",
        "schedule.offline.reason": "C22 actionable offline readiness reason.",
        "schedule.recovery.same_mutation": "C22 idempotent same-MutationID recovery action.",
        "schedule.reminder.denied": "C22 reminder denial preserves complete Today queue.",
        "schedule.reminder.evicted": "C22 OS reminder eviction does not change due truth.",
        "schedule.reminder.opt_in": "C22 optional local reminder permission action.",
        "schedule.reminder.reconciled": "C22 derived reminder reconciliation state.",
        "schedule.scope": "C22 schedule scope label.",
        "schedule.time_zone.visible": "C22 visible schedule time-zone label.",
        "schedule.today.reason": "C22 reason-bearing Today queue label.",
        "schedule.work.current": "C22 current scheduled work heading.",
        "schedule.work.upcoming": "C22 upcoming scheduled work heading.",
        "survey.template.action.duplicate": "C20 duplicate action always creates a new draft identity.",
        "survey.template.action.export": "C20 bounded template archive export action.",
        "survey.template.action.import_as_draft": "C20 quarantined import always creates a new draft identity.",
        "survey.template.action.publish": "C20 explicit atomic template publication action.",
        "survey.template.action.report": "C20 immutable publication report action.",
        "survey.template.action.resume": "C20 exact-context survey resume action.",
        "survey.template.action.retire": "C20 explicit immutable template retirement action.",
        "survey.template.action.review": "C20 recorded-fact review action.",
        "survey.template.action.run": "C20 explicit survey start action.",
        "survey.template.claim_boundary": "C20 survey output is typed fact collection, never pass/fail.",
        "survey.template.compatibility.active_work_pinned": "C20 in-flight work retains exact recorded release authority.",
        "survey.template.compatibility.additive_draft_safe": "C20 additive draft-only adoption state.",
        "survey.template.compatibility.blocked": "C20 incompatible or invalid semantic change state.",
        "survey.template.compatibility.draft_migration_required": "C20 review-required draft migration state.",
        "survey.template.compatibility.no_change": "C20 exact semantic-preview compatibility state.",
        "survey.template.interruption": "C20 interruption guidance makes no partial success claim.",
        "survey.template.library.browse": "C20 browse action over bounded survey templates.",
        "survey.template.library.favorites": "C20 device-local favorite template list.",
        "survey.template.library.heading": "C20 guided-survey template library heading.",
        "survey.template.library.recents": "C20 device-local recent template list.",
        "survey.template.library.search": "C20 local derived template search action.",
        "survey.template.manual_path": "C20 complete manual path remains available when optional proposals are absent.",
        "survey.template.primary_action": "C20 exactly one primary next action label.",
        "survey.template.promotion.conflict": "C20 provisional-subject promotion conflict requires explicit review.",
        "survey.template.report.frozen": "C20 finalized report remains bound to its exact source release.",
        "survey.template.review.conflict": "C20 factual review conflict requires explicit review without implying pass or fail.",
        "survey.template.semantic_preview": "C20 semantic change preview; it is not applied automatically.",
        "assistance.interrupted": "C32 interruption state; no proposed value was saved and the manual path remains available. Use only for interrupted text extraction before acceptance; never for an interrupted accept operation or receipt recovery.",
        "evidence.curation.derivative.manifest_ready": "C02 evidence curation presentation text; a manifest is not presented as visual output.",
        "evidence.curation.derivative.visual_ready": "C02 evidence curation presentation text; only a completed typed visual derivative receipt may use this state.",
        "evidence.curation.derivative.visual_unavailable": "C02 evidence curation presentation text; no completed typed visual derivative is available.",
        "evidence.curation.item.remove_from_work": "C02 successor-sequence action; it removes an item from current work/report use without deleting evidence history.",
        "evidence.curation.item.remove_history_disclosure": "C02 truthful disclosure for removal from current work/report use.",
        "evidence.curation.item.retake.review_required": "C02 retake disclosure requiring renewed review for media-dependent descriptive text.",
        "evidence.curation.metadata.unavailable": "C02 evidence curation presentation text; fail-closed when no validated C05 metadata sequence binds this preview.",
        "evidence.curation.role.after": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "evidence.curation.role.before": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "evidence.curation.role.context": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "evidence.curation.role.detail": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "evidence.curation.role.heading": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "evidence.curation.role.other": "C02 evidence curation presentation text; released C05 evidence role, never a legal or causal label.",
        "service_reliability.segment.impact": "C53 impact kind remains explicit; degraded and intermittent segments receive no invented availability weight.",
        "service_request.intake.portable": "C52 cleartext portable intake label; it does not claim delivery or authentication.",
        "temporal_evidence.interrupted": "C33 interruption state with truthful canonical-save status. A complete pending review may remain recoverable; reconcile any interrupted acceptance against its canonical receipt before claiming an outcome.",
        "work_resource.customer_safe": "C49 customer-safe cost wording is available only after explicit preview selection and validation.",
        "work_resource.direct_cost.internal": "C49 direct cost is entered manually and internal by default; no tax, rates, markup, or invoice calculation.",
        "work_resource.direct_cost_preview": "C49 direct cost preview requires explicit selection; it is not a tax, rate, markup, or invoice calculation.",
        "work_resource.duration": "C49 manually entered duration; no live or background timer.",
        "work_resource.duration.manual": "C49 duration is entered manually in whole minutes; no live or background timer.",
        "work_resource.material": "C49 manually entered material; not a catalog or live inventory balance.",
        "work_resource.no_live_inventory_claim": "C49 manual entries are not inventory balances or a live inventory claim.",
    ]
}
