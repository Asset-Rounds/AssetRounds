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
    static let inheritedMailAccessibilityIDs = [
        "s8.4.mail.attachment-count",
        "s8.4.mail.body",
        "s8.4.mail.done",
        "s8.4.mail.recipient",
        "s8.4.mail.screen",
    ]

    static func mailLegacyAllowlist() throws
        -> LegacyLocalizationAccessibilityAllowlistV1 {
        try LegacyLocalizationAccessibilityAllowlistV1(
            entries: inheritedMailAccessibilityIDs.map {
                LegacyLocalizationAccessibilityEntryV1(
                    kind: .phaseAccessibilityID,
                    stableFingerprint: KernelCanonicalHashV1.sha256(Data($0.utf8))
                )
            }
        )
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

    static func accessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let values: [(String, String, SemanticAccessibilityRoleV1, BundledLocalizationKeyV1)] = [
            ("feedback.mail.screen", "s8.4.mail.screen", .screen, .mailComposerTitle),
            ("feedback.mail.recipient", "s8.4.mail.recipient", .group, .mailRecipient),
            ("feedback.mail.attachment-count", "s8.4.mail.attachment-count", .status, .mailAttachmentCount),
            ("feedback.mail.body", "s8.4.mail.body", .textField, .mailMessageLabel),
            ("feedback.mail.done", "s8.4.mail.done", .button, .commonDone),
        ]
        let entries = try values.map {
            AccessibilityContractV1(
                semanticID: $0.0, role: $0.2, reachability: .always,
                labelKey: try LocalizationKeyV1($0.3.rawValue), hintKey: nil,
                valueKey: nil, dynamicSuffixPolicy: .none, deprecatedAliases: [$0.1]
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
        interruption: Interruption = { _ in }
    ) throws -> LocalizationCatalogPublicationV1 {
        try interruption(.beforeValidation)
        try legacy.validate()
        let locales = LocalizationLocaleManifestV1.shippingV1()
        try locales.validate()
        let keys: LocalizationKeyRegistryV1
        if includeWorkPacket || includeWorkPacketManifest || includePacketCoordination {
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
        let requiredMailLegacy = try mailLegacyAllowlist()
        guard legacy == requiredMailLegacy else {
            throw LocalizationContractFailureV1.legacyAllowlistGrowth
        }
        if let previousLegacy { try previousLegacy.validateObserved(legacy.entries) }
        let accessibility: SemanticAccessibilityIDRegistryV1
        if includeWorkPacket || includeWorkPacketManifest || includePacketCoordination {
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
        includePacketCoordination: Bool = false
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
                includePacketCoordination: includePacketCoordination
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
        // The source catalog may be validated against any currently declared
        // additive projection, while the selected registry still controls the
        // required subset.  This keeps C16/C38 compatibility callers frozen
        // and lets each additive typed surface publish atomically.
        let supportedKeys = Set((try? workPacketRegistry())?.definitions.map(\.key.rawValue) ?? [])
        guard registeredKeys.isSubset(of: Set(strings.keys)),
              Set(strings.keys).isSubset(of: supportedKeys) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        for definition in registry.definitions {
            let rawKey = definition.key.rawValue
            guard let rawEntry = strings[rawKey],
                  let entry = rawEntry as? [String: Any],
                  let comment = entry["comment"] as? String,
                  !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let localizations = entry["localizations"] as? [String: Any],
                  Set(localizations.keys) == Set(["en"]),
                  (try? registry.definition(for: LocalizationKeyV1(rawKey))) != nil else {
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
