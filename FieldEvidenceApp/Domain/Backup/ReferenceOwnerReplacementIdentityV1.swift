import Foundation

extension RestoreIdentityV1 {
    func destinationWorkPacketMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        try referenceOwnerReplacementMutationID(for: sourceID, family: .workPacket)
    }

    func destinationSurveySessionMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        try referenceOwnerReplacementMutationID(for: sourceID, family: .guidedSurvey)
    }

    func destinationRoundSessionMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        try referenceOwnerReplacementMutationID(for: sourceID, family: .roundSession)
    }

    func destinationScheduleMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        try referenceOwnerReplacementMutationID(for: sourceID, family: .schedule)
    }

    func destinationFieldDraftMutationID(for sourceID: MutationIDV1) throws -> MutationIDV1 {
        try referenceOwnerReplacementMutationID(for: sourceID, family: .fieldDraft)
    }
}

private extension RestoreIdentityV1 {
    enum ReferenceOwnerReplacementFamilyV1: String {
        case workPacket = "work-packet"
        case guidedSurvey = "guided-survey"
        case roundSession = "round-session"
        case schedule
        case fieldDraft = "field-draft"
    }

    /// Namespaces coordinate reissued replacement commands only. They never
    /// rewrite original receipts, record IDs, or immutable result attribution.
    func referenceOwnerReplacementMutationID(
        for sourceID: MutationIDV1,
        family: ReferenceOwnerReplacementFamilyV1
    ) throws -> MutationIDV1 {
        guard mode == .replaceExisting else { throw RestoreIdentityDecisionErrorV1.invalidMode }
        guard let sourceWorkspaceID = source.workspaceID else {
            throw RestoreIdentityDecisionErrorV1.missingSourceIdentity
        }
        let components = [
            "reference-owner-replacement-v1", family.rawValue,
            sourceWorkspaceID.uuidString.lowercased(), sourceID.rawValue.uuidString.lowercased(),
            targetPointer.workspaceID.uuidString.lowercased(),
            targetPointer.generationID.uuidString.lowercased(),
        ]
        let digest = CanonicalJSONV1.sha256(Data(components.joined(separator: "\u{0}").utf8))
        var bytes = stride(from: 0, to: 32, by: 2).map {
            UInt8(digest.dropFirst($0).prefix(2), radix: 16)!
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let target = try MutationIDV1(rawValue: UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )))
        guard target != sourceID else { throw WorkspaceMutationFailureV1.sequenceCollision }
        return target
    }
}
