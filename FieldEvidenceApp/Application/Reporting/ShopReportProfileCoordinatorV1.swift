import Foundation

@MainActor
protocol ShopReportProfileCurrentReadingV1: AnyObject {
    func shopReportProfileHistory(
        workspaceID: WorkspaceID,
        profileID: UUID
    ) throws -> [ShopReportProfileV1]
}

@MainActor
protocol ShopReportProfileCanonicalWritingV1: AnyObject {
    func commitShopReportProfile(
        _ mutation: ShopReportProfileMutationV1
    ) throws -> ShopReportProfileMutationReceiptV1
}

struct ShopOpenEvidencePreparationV1: Sendable {
    let finalizedBinding: FinalizedReportProfileBindingV1
    let detailReceipt: EvidenceDetailCardRenderReceiptV1
    let confirmation: FinalAudiencePrivacyConfirmationV1
    let artifacts: [ShopOpenEvidenceArtifactV1]
    let media: [OutputScopedContentReferenceV1]
    let packaging: ShopOpenEvidencePackagingV1
    let confirmedFormat: ReportProjectionFormatV1
    let accessibleAssessment:AccessibleDocumentAssessmentReceiptV1
    let accessibleOutput: AccessibleDocumentRenderOutputV1
}

@MainActor
final class ShopReportProfileCoordinatorV1 {
    private let workspaceID: WorkspaceID
    private let sectionRegistry: ReportSectionRegistryV1
    private let reader: any ShopReportProfileCurrentReadingV1
    private let writer: any ShopReportProfileCanonicalWritingV1

    init(
        workspaceID: WorkspaceID,
        sectionRegistry: ReportSectionRegistryV1,
        reader: any ShopReportProfileCurrentReadingV1,
        writer: any ShopReportProfileCanonicalWritingV1
    ) throws {
        try sectionRegistry.validate()
        self.workspaceID = workspaceID
        self.sectionRegistry = sectionRegistry
        self.reader = reader
        self.writer = writer
    }

    func current(profileID: UUID) throws -> ShopReportProfileV1? {
        let history = try validatedHistory(profileID: profileID)
        return history.last
    }

    func save(_ mutation: ShopReportProfileMutationV1) throws -> ShopReportProfileMutationReceiptV1 {
        try mutation.validate()
        try mutation.profile.validate(sectionRegistry: sectionRegistry)
        guard mutation.workspaceID == workspaceID else { throw ShopReportProfileFailureV1.profileMismatch }
        let prior = try current(profileID: mutation.profile.profileID)
        if let prior {
            try mutation.profile.validateSuccessor(of: prior, sectionRegistry: sectionRegistry)
            guard mutation.expectedRevision == prior.revision else { throw ShopReportProfileFailureV1.staleRevision }
        } else {
            guard mutation.expectedRevision == 0, mutation.profile.revision == 1,
                  mutation.profile.predecessor == nil else { throw ShopReportProfileFailureV1.staleRevision }
        }
        let receipt = try writer.commitShopReportProfile(mutation)
        guard receipt.profileFrontier == (try mutation.profile.reference) else {
            throw ShopReportProfileFailureV1.profileMismatch
        }
        return receipt
    }

    func prepareOpenEvidenceHandoff(
        profileID: UUID,
        input: ShopOpenEvidencePreparationV1
    ) throws -> ShopOpenEvidenceHandoffReceiptV1 {
        guard let profile = try current(profileID: profileID), profile.activation == .on else {
            throw ShopReportProfileFailureV1.profileMismatch
        }
        try profile.validate(sectionRegistry: sectionRegistry)
        return try ShopOpenEvidenceHandoffReceiptV1(
            profile: profile,
            finalizedBinding: input.finalizedBinding,
            detailReceipt: input.detailReceipt,
            confirmation: input.confirmation,
            artifacts: input.artifacts,
            media: input.media,
            packaging: input.packaging,
            confirmedFormat: input.confirmedFormat,
            accessibleAssessment:input.accessibleAssessment,
            accessibleOutput: input.accessibleOutput
        )
    }

    private func validatedHistory(profileID: UUID) throws -> [ShopReportProfileV1] {
        let history = try reader.shopReportProfileHistory(workspaceID: workspaceID, profileID: profileID)
        guard history.count <= ShopReportProfileLimitsV1.maximumHistoryRevisions,
              history == history.sorted(by: { $0.revision < $1.revision }),
              Set(history.map(\.revision)).count == history.count,
              Set(history.map(\.profileSHA256)).count == history.count else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        for (index, value) in history.enumerated() {
            try value.validate(sectionRegistry: sectionRegistry)
            guard value.workspaceID == workspaceID, value.profileID == profileID,
                  value.revision == UInt64(index + 1) else { throw ShopReportProfileFailureV1.staleRevision }
            if index == 0 {
                guard value.predecessor == nil else { throw ShopReportProfileFailureV1.staleRevision }
            } else {
                try value.validateSuccessor(of: history[index - 1], sectionRegistry: sectionRegistry)
            }
        }
        return history
    }
}

extension WorkspaceWriterV1: ShopReportProfileCanonicalWritingV1 {}
