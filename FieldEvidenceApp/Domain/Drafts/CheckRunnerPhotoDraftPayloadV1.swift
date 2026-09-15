import Foundation

private enum CheckRunnerPhotoValueValidationV1 {
    static func instant(_ value: Date) throws {
        let seconds = value.timeIntervalSince1970
        guard seconds.isFinite, seconds >= 0 else { throw FieldDraftFailureV1.invalidValue }
    }

    static func sourcePixelCount(width: Int, height: Int) throws -> Int64 {
        guard (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(width),
              (MediaContractV1.sourceAxisMinimum...MediaContractV1.sourceAxisMaximum).contains(height),
              let width64 = Int64(exactly: width), let height64 = Int64(exactly: height) else {
            throw FieldDraftFailureV1.invalidValue
        }
        let result = width64.multipliedReportingOverflow(by: height64)
        guard !result.overflow, result.partialValue <= Int64(MediaContractV1.decodedPixelCountMaximum) else {
            throw FieldDraftFailureV1.limitExceeded
        }
        return result.partialValue
    }

    static func sourceCount(_ value: Int64) throws {
        guard value > 0, value <= Int64(MediaContractV1.sourceByteCountMaximum) else {
            throw FieldDraftFailureV1.limitExceeded
        }
    }

    static func sha256(_ digest: ContentDigestV1) throws {
        _ = try ContentDigestV1(algorithm: digest.algorithm, hexadecimalValue: digest.hexadecimalValue)
        guard digest.algorithm == .sha256 else { throw FieldDraftFailureV1.invalidValue }
    }
}

/// Frozen ownership before any durable raw stage is claimed. The timestamps
/// are logical inputs, and must be reused unchanged after an interruption.
struct CheckRunnerPhotoRawStageIntentV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let stageID: UUID
    let stageMutationID: MutationIDV1
    let stageCreatedAt: Date
    let expectedSourceByteCount: Int64
    let provenanceID: String
    let evidenceID: UUID
    let evidenceCreatedAt: Date

    init(stageID: UUID, stageMutationID: MutationIDV1, stageCreatedAt: Date,
         expectedSourceByteCount: Int64, provenanceID: String, evidenceID: UUID,
         evidenceCreatedAt: Date) throws {
        self.stageID = stageID; self.stageMutationID = stageMutationID
        self.stageCreatedAt = stageCreatedAt; self.expectedSourceByteCount = expectedSourceByteCount
        self.provenanceID = provenanceID; self.evidenceID = evidenceID
        self.evidenceCreatedAt = evidenceCreatedAt
        try validate()
    }

    func validate() throws {
        try [stageID, stageMutationID.rawValue, evidenceID].forEach(FieldDraftValidationV1.id)
        try CheckRunnerPhotoValueValidationV1.sourceCount(expectedSourceByteCount)
        try CheckRunnerPhotoValueValidationV1.instant(stageCreatedAt)
        try CheckRunnerPhotoValueValidationV1.instant(evidenceCreatedAt)
        guard ContentContractValidationV1.validID(provenanceID), evidenceCreatedAt <= stageCreatedAt,
              stageMutationID.rawValue != evidenceID else { throw FieldDraftFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case stageID, stageMutationID, stageCreatedAt, expectedSourceByteCount, provenanceID
        case evidenceID, evidenceCreatedAt
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(stageID: c.decode(UUID.self, forKey: .stageID),
            stageMutationID: c.decode(MutationIDV1.self, forKey: .stageMutationID),
            stageCreatedAt: c.decode(Date.self, forKey: .stageCreatedAt),
            expectedSourceByteCount: c.decode(Int64.self, forKey: .expectedSourceByteCount),
            provenanceID: c.decode(String.self, forKey: .provenanceID),
            evidenceID: c.decode(UUID.self, forKey: .evidenceID),
            evidenceCreatedAt: c.decode(Date.self, forKey: .evidenceCreatedAt))
    }
}

/// Inspected facts retained with the exact raw digest. Construction and decode
/// check their relation; the raw-file owner must still authenticate the bytes.
struct CheckRunnerPhotoSourceInspectionV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let sourceByteCount: Int64
    let sourceSHA256: ContentDigestV1
    let detectedUTI: String
    let sourceMediaType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let decodedPixelCount: Int64
    let frameCount: Int
    let rawContentID: String
    let provenanceID: String

    init(sourceByteCount: Int64, sourceSHA256: ContentDigestV1, detectedUTI: String,
         sourceMediaType: String, pixelWidth: Int, pixelHeight: Int, decodedPixelCount: Int64,
         frameCount: Int, rawContentID: String, provenanceID: String) throws {
        self.sourceByteCount = sourceByteCount; self.sourceSHA256 = sourceSHA256
        self.detectedUTI = detectedUTI; self.sourceMediaType = sourceMediaType
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.decodedPixelCount = decodedPixelCount; self.frameCount = frameCount
        self.rawContentID = rawContentID; self.provenanceID = provenanceID
        try validate()
    }

    init(facts: MediaSourceFactsV1, sourceSHA256: ContentDigestV1,
         workspaceID: WorkspaceID, provenanceID: String) throws {
        try FieldDraftValidationV1.workspace(workspaceID)
        guard let count = Int64(exactly: facts.byteCount) else { throw FieldDraftFailureV1.limitExceeded }
        try self.init(sourceByteCount: count, sourceSHA256: sourceSHA256,
            detectedUTI: facts.sourceTypeIdentifier,
            sourceMediaType: CheckRunnerPhotoSourceMetadataProfileV1.mediaType(for: facts.sourceTypeIdentifier),
            pixelWidth: facts.pixelWidth, pixelHeight: facts.pixelHeight,
            decodedPixelCount: CheckRunnerPhotoValueValidationV1.sourcePixelCount(
                width: facts.pixelWidth, height: facts.pixelHeight),
            frameCount: 1,
            rawContentID: DraftAttachmentStagingAdapterV1.contentID(workspaceID: workspaceID, digest: sourceSHA256),
            provenanceID: provenanceID)
    }

    func validate() throws {
        try CheckRunnerPhotoValueValidationV1.sourceCount(sourceByteCount)
        try CheckRunnerPhotoValueValidationV1.sha256(sourceSHA256)
        let expectedPixels = try CheckRunnerPhotoValueValidationV1.sourcePixelCount(width: pixelWidth, height: pixelHeight)
        guard decodedPixelCount == expectedPixels, frameCount == 1,
              sourceMediaType == (try CheckRunnerPhotoSourceMetadataProfileV1.mediaType(for: detectedUTI)),
              ContentContractValidationV1.validID(rawContentID),
              ContentContractValidationV1.validID(provenanceID) else { throw FieldDraftFailureV1.invalidValue }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceByteCount, sourceSHA256, detectedUTI, sourceMediaType, pixelWidth, pixelHeight
        case decodedPixelCount, frameCount, rawContentID, provenanceID
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sourceByteCount: c.decode(Int64.self, forKey: .sourceByteCount),
            sourceSHA256: c.decode(ContentDigestV1.self, forKey: .sourceSHA256),
            detectedUTI: c.decode(String.self, forKey: .detectedUTI),
            sourceMediaType: c.decode(String.self, forKey: .sourceMediaType),
            pixelWidth: c.decode(Int.self, forKey: .pixelWidth), pixelHeight: c.decode(Int.self, forKey: .pixelHeight),
            decodedPixelCount: c.decode(Int64.self, forKey: .decodedPixelCount),
            frameCount: c.decode(Int.self, forKey: .frameCount),
            rawContentID: c.decode(String.self, forKey: .rawContentID),
            provenanceID: c.decode(String.self, forKey: .provenanceID))
    }
}

/// Immutable READY_LOCAL witness. A live stage can later be its authenticated
/// COMMITTED successor; this value does not require that live state stay ready.
struct CheckRunnerPhotoRawReadyV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let intent: CheckRunnerPhotoRawStageIntentV1
    let inspection: CheckRunnerPhotoSourceInspectionV1
    let readyItem: AttachmentStagingItemV1
    let stagePublicationMutationID: MutationIDV1
    let originalProvenance: ContentOriginalProvenanceV1

    init(intent: CheckRunnerPhotoRawStageIntentV1, inspection: CheckRunnerPhotoSourceInspectionV1,
         readyItem: AttachmentStagingItemV1, stagePublicationMutationID: MutationIDV1,
         originalProvenance: ContentOriginalProvenanceV1) throws {
        self.intent = intent; self.inspection = inspection; self.readyItem = readyItem
        self.stagePublicationMutationID = stagePublicationMutationID
        self.originalProvenance = originalProvenance
        try validate()
    }

    func validate() throws {
        try intent.validate(); try inspection.validate(); try readyItem.validate()
        let expectedItem = try AttachmentStagingItemV1(stageID: intent.stageID, draftID: readyItem.draftID,
            workspaceID: readyItem.workspaceID, attachmentKind: .photo, scratchLeaseID: intent.stageID,
            expectedByteCount: intent.expectedSourceByteCount, actualByteCount: inspection.sourceByteCount,
            contentDigest: inspection.sourceSHA256, contentReference: nil, processingJobID: nil,
            retryClass: .none, state: .readyLocal, protectionState: .available, revision: 1,
            mutationID: intent.stageMutationID)
        let expectedProvenance = try ContentOriginalProvenanceV1(provenanceID: intent.provenanceID,
            workspaceID: readyItem.workspaceID.rawValue.uuidString.lowercased(),
            contentID: inspection.rawContentID, contentDigest: inspection.sourceSHA256,
            origin: originalProvenance.origin, recordedAt: Self.formatOriginalRecordedAt(intent.stageCreatedAt))
        guard readyItem == expectedItem, stagePublicationMutationID == intent.stageMutationID,
              inspection.sourceByteCount == intent.expectedSourceByteCount,
              inspection.provenanceID == intent.provenanceID,
              inspection.rawContentID == DraftAttachmentStagingAdapterV1.contentID(
                workspaceID: readyItem.workspaceID, digest: inspection.sourceSHA256),
              originalProvenance == expectedProvenance else { throw FieldDraftFailureV1.digestMismatch }
    }

    static func formatOriginalRecordedAt(_ date: Date) throws -> String {
        try CheckRunnerPhotoValueValidationV1.instant(date)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case intent, inspection, readyItem, stagePublicationMutationID, originalProvenance
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let readyDecoder = try c.superDecoder(forKey: .readyItem)
        try ClosedContractDecodingV1.rejectUnknownKeys(readyDecoder, allowed: [
            "schemaVersion", "stageID", "draftID", "workspaceID", "attachmentKind", "scratchLeaseID",
            "expectedByteCount", "actualByteCount", "contentDigest", "contentReference", "processingJobID",
            "retryClass", "protectionState", "state", "revision", "mutationID", "stageSHA256"
        ])
        try self.init(intent: c.decode(CheckRunnerPhotoRawStageIntentV1.self, forKey: .intent),
            inspection: c.decode(CheckRunnerPhotoSourceInspectionV1.self, forKey: .inspection),
            readyItem: AttachmentStagingItemV1(from: readyDecoder),
            stagePublicationMutationID: c.decode(MutationIDV1.self, forKey: .stagePublicationMutationID),
            originalProvenance: c.decode(ContentOriginalProvenanceV1.self, forKey: .originalProvenance))
    }
}

struct CheckRunnerPhotoNormalizedPairV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let evidenceID: UUID
    let originalRelativePath: String
    let originalByteCount: Int64
    let originalSHA256: String
    let originalPixelWidth: Int
    let originalPixelHeight: Int
    let thumbnailRelativePath: String
    let thumbnailByteCount: Int64
    let thumbnailSHA256: String
    let thumbnailPixelWidth: Int
    let thumbnailPixelHeight: Int
    let sourceBinding: ContentSourceBindingV1
    let sanitizedDerivative: SanitizedDerivativeV1
    let thumbnailDerivative: ThumbnailDerivativeV1

    init(evidenceID: UUID, originalRelativePath: String, originalByteCount: Int64,
         originalSHA256: String, originalPixelWidth: Int, originalPixelHeight: Int,
         thumbnailRelativePath: String, thumbnailByteCount: Int64, thumbnailSHA256: String,
         thumbnailPixelWidth: Int, thumbnailPixelHeight: Int, sourceBinding: ContentSourceBindingV1,
         sanitizedDerivative: SanitizedDerivativeV1, thumbnailDerivative: ThumbnailDerivativeV1) throws {
        self.evidenceID = evidenceID; self.originalRelativePath = originalRelativePath
        self.originalByteCount = originalByteCount; self.originalSHA256 = originalSHA256
        self.originalPixelWidth = originalPixelWidth; self.originalPixelHeight = originalPixelHeight
        self.thumbnailRelativePath = thumbnailRelativePath; self.thumbnailByteCount = thumbnailByteCount
        self.thumbnailSHA256 = thumbnailSHA256; self.thumbnailPixelWidth = thumbnailPixelWidth
        self.thumbnailPixelHeight = thumbnailPixelHeight; self.sourceBinding = sourceBinding
        self.sanitizedDerivative = sanitizedDerivative; self.thumbnailDerivative = thumbnailDerivative
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.id(evidenceID)
        try FieldDraftValidationV1.digest(originalSHA256); try FieldDraftValidationV1.digest(thumbnailSHA256)
        try CheckRunnerPhotoValueValidationV1.sha256(sourceBinding.digest)
        _ = try ContentSourceBindingV1(contentID: sourceBinding.contentID, digest: sourceBinding.digest)
        try CheckRunnerPhotoSourceMetadataProfileV1.validate()
        let directory = "evidence/\(evidenceID.uuidString.lowercased())"
        guard originalRelativePath == "\(directory)/original.jpg",
              thumbnailRelativePath == "\(directory)/thumbnail.jpg",
              originalByteCount > 0, originalByteCount <= Int64(MediaContractV1.originalByteCountMaximum),
              thumbnailByteCount > 0, thumbnailByteCount <= Int64(MediaContractV1.thumbnailByteCountMaximum),
              (1...MediaContractV1.originalLongestEdgeMaximum).contains(originalPixelWidth),
              (1...MediaContractV1.originalLongestEdgeMaximum).contains(originalPixelHeight),
              (1...MediaContractV1.thumbnailLongestEdgeMaximum).contains(thumbnailPixelWidth),
              (1...MediaContractV1.thumbnailLongestEdgeMaximum).contains(thumbnailPixelHeight),
              sanitizedDerivative == (try CheckRunnerPhotoSourceMetadataProfileV1.sanitizedDerivative()),
              thumbnailDerivative == (try CheckRunnerPhotoSourceMetadataProfileV1.thumbnailDerivative(
                pixelWidth: thumbnailPixelWidth, pixelHeight: thumbnailPixelHeight)) else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case evidenceID, originalRelativePath, originalByteCount, originalSHA256, originalPixelWidth, originalPixelHeight
        case thumbnailRelativePath, thumbnailByteCount, thumbnailSHA256, thumbnailPixelWidth, thumbnailPixelHeight
        case sourceBinding, sanitizedDerivative, thumbnailDerivative
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(evidenceID: c.decode(UUID.self, forKey: .evidenceID),
            originalRelativePath: c.decode(String.self, forKey: .originalRelativePath),
            originalByteCount: c.decode(Int64.self, forKey: .originalByteCount),
            originalSHA256: c.decode(String.self, forKey: .originalSHA256),
            originalPixelWidth: c.decode(Int.self, forKey: .originalPixelWidth),
            originalPixelHeight: c.decode(Int.self, forKey: .originalPixelHeight),
            thumbnailRelativePath: c.decode(String.self, forKey: .thumbnailRelativePath),
            thumbnailByteCount: c.decode(Int64.self, forKey: .thumbnailByteCount),
            thumbnailSHA256: c.decode(String.self, forKey: .thumbnailSHA256),
            thumbnailPixelWidth: c.decode(Int.self, forKey: .thumbnailPixelWidth),
            thumbnailPixelHeight: c.decode(Int.self, forKey: .thumbnailPixelHeight),
            sourceBinding: c.decode(ContentSourceBindingV1.self, forKey: .sourceBinding),
            sanitizedDerivative: c.decode(SanitizedDerivativeV1.self, forKey: .sanitizedDerivative),
            thumbnailDerivative: c.decode(ThumbnailDerivativeV1.self, forKey: .thumbnailDerivative))
    }
}

struct CheckRunnerPhotoPairReadyV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let raw: CheckRunnerPhotoRawReadyV1
    let normalizedPair: CheckRunnerPhotoNormalizedPairV1
    let pairPublicationMarkerSHA256: String

    init(raw: CheckRunnerPhotoRawReadyV1, normalizedPair: CheckRunnerPhotoNormalizedPairV1,
         pairPublicationMarkerSHA256: String) throws {
        self.raw = raw; self.normalizedPair = normalizedPair
        self.pairPublicationMarkerSHA256 = pairPublicationMarkerSHA256
        try validate()
    }

    func validate() throws {
        try raw.validate(); try normalizedPair.validate()
        try FieldDraftValidationV1.digest(pairPublicationMarkerSHA256)
        guard normalizedPair.evidenceID == raw.intent.evidenceID,
              normalizedPair.sourceBinding.contentID == raw.inspection.rawContentID,
              normalizedPair.sourceBinding.digest == raw.inspection.sourceSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    func validate(childDraftID: UUID, parentDraftID: UUID) throws {
        try validate()
        guard raw.readyItem.draftID == childDraftID,
              pairPublicationMarkerSHA256 == (try Self.markerSHA256(childDraftID: childDraftID,
                parentDraftID: parentDraftID, raw: raw, normalizedPair: normalizedPair)) else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    /// Acyclic marker basis for the existing pair owner. A matching payload
    /// claim still needs the complete owned marker and exact byte read-back.
    static func markerSHA256(childDraftID: UUID, parentDraftID: UUID, raw: CheckRunnerPhotoRawReadyV1,
                             normalizedPair: CheckRunnerPhotoNormalizedPairV1) throws -> String {
        try [childDraftID, parentDraftID].forEach(FieldDraftValidationV1.id)
        try raw.validate(); try normalizedPair.validate()
        guard childDraftID != parentDraftID, raw.readyItem.draftID == childDraftID,
              normalizedPair.evidenceID == raw.intent.evidenceID,
              normalizedPair.sourceBinding.contentID == raw.inspection.rawContentID,
              normalizedPair.sourceBinding.digest == raw.inspection.sourceSHA256 else {
            throw FieldDraftFailureV1.digestMismatch
        }
        return try FieldDraftCanonicalCodecV1.sha256(MarkerBasis(schemaVersion: 1,
            childDraftID: childDraftID, parentDraftID: parentDraftID, stageID: raw.intent.stageID,
            evidenceID: raw.intent.evidenceID, rawStageSHA256: raw.readyItem.stageSHA256,
            sourceByteCount: raw.inspection.sourceByteCount,
            sourceSHA256: raw.inspection.sourceSHA256.hexadecimalValue,
            detectedUTI: raw.inspection.detectedUTI, sourceMediaType: raw.inspection.sourceMediaType,
            sourcePixelWidth: raw.inspection.pixelWidth, sourcePixelHeight: raw.inspection.pixelHeight,
            profileID: CheckRunnerPhotoSourceMetadataProfileV1.profileID,
            profileVersion: CheckRunnerPhotoSourceMetadataProfileV1.profileVersion,
            normalizedPair: normalizedPair))
    }

    private struct MarkerBasis: Encodable {
        let schemaVersion: Int
        let childDraftID: UUID
        let parentDraftID: UUID
        let stageID: UUID
        let evidenceID: UUID
        let rawStageSHA256: String
        let sourceByteCount: Int64
        let sourceSHA256: String
        let detectedUTI: String
        let sourceMediaType: String
        let sourcePixelWidth: Int
        let sourcePixelHeight: Int
        let profileID: String
        let profileVersion: String
        let normalizedPair: CheckRunnerPhotoNormalizedPairV1
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case raw, normalizedPair, pairPublicationMarkerSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(raw: c.decode(CheckRunnerPhotoRawReadyV1.self, forKey: .raw),
            normalizedPair: c.decode(CheckRunnerPhotoNormalizedPairV1.self, forKey: .normalizedPair),
            pairPublicationMarkerSHA256: c.decode(String.self, forKey: .pairPublicationMarkerSHA256))
    }
}

/// Nondeducible inputs for the incumbent one-stage commit. Receipt digests,
/// the content locator and observed completion times remain effect outputs.
struct CheckRunnerPhotoCommitAttemptV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    let planID: UUID
    let expectedWorkflowRecordRevision: UInt64
    let targetMutationID: MutationIDV1
    let outputKeys: [String]
    let reservationMutationID: MutationIDV1
    let reservationReviewAfter: Date
    let preparedSagaID: UUID
    let preparedSagaMutationID: MutationIDV1
    let preparedUpdatedAt: Date
    let contentPromotedSagaID: UUID
    let contentPromotedSagaMutationID: MutationIDV1
    let contentPromotedUpdatedAt: Date
    let targetCommittedSagaID: UUID
    let targetCommittedSagaMutationID: MutationIDV1
    let targetCommittedUpdatedAt: Date
    let draftRetirePendingSagaID: UUID
    let draftRetirePendingSagaMutationID: MutationIDV1
    let draftRetirePendingUpdatedAt: Date
    let draftRetiredSagaID: UUID
    let draftRetiredUpdatedAt: Date
    let commitReceiptID: UUID
    let terminalBundleMutationID: MutationIDV1
    let terminalCheckpointUpdatedAt: Date
    let promotionAt: Date

    init(planID: UUID, expectedWorkflowRecordRevision: UInt64, targetMutationID: MutationIDV1,
         outputKeys: [String], reservationMutationID: MutationIDV1, reservationReviewAfter: Date,
         preparedSagaID: UUID, preparedSagaMutationID: MutationIDV1, preparedUpdatedAt: Date,
         contentPromotedSagaID: UUID, contentPromotedSagaMutationID: MutationIDV1, contentPromotedUpdatedAt: Date,
         targetCommittedSagaID: UUID, targetCommittedSagaMutationID: MutationIDV1, targetCommittedUpdatedAt: Date,
         draftRetirePendingSagaID: UUID, draftRetirePendingSagaMutationID: MutationIDV1, draftRetirePendingUpdatedAt: Date,
         draftRetiredSagaID: UUID, draftRetiredUpdatedAt: Date, commitReceiptID: UUID,
         terminalBundleMutationID: MutationIDV1, terminalCheckpointUpdatedAt: Date, promotionAt: Date) throws {
        self.planID = planID; self.expectedWorkflowRecordRevision = expectedWorkflowRecordRevision
        self.targetMutationID = targetMutationID; self.outputKeys = outputKeys
        self.reservationMutationID = reservationMutationID; self.reservationReviewAfter = reservationReviewAfter
        self.preparedSagaID = preparedSagaID; self.preparedSagaMutationID = preparedSagaMutationID
        self.preparedUpdatedAt = preparedUpdatedAt; self.contentPromotedSagaID = contentPromotedSagaID
        self.contentPromotedSagaMutationID = contentPromotedSagaMutationID
        self.contentPromotedUpdatedAt = contentPromotedUpdatedAt; self.targetCommittedSagaID = targetCommittedSagaID
        self.targetCommittedSagaMutationID = targetCommittedSagaMutationID
        self.targetCommittedUpdatedAt = targetCommittedUpdatedAt; self.draftRetirePendingSagaID = draftRetirePendingSagaID
        self.draftRetirePendingSagaMutationID = draftRetirePendingSagaMutationID
        self.draftRetirePendingUpdatedAt = draftRetirePendingUpdatedAt; self.draftRetiredSagaID = draftRetiredSagaID
        self.draftRetiredUpdatedAt = draftRetiredUpdatedAt; self.commitReceiptID = commitReceiptID
        self.terminalBundleMutationID = terminalBundleMutationID
        self.terminalCheckpointUpdatedAt = terminalCheckpointUpdatedAt; self.promotionAt = promotionAt
        try validate()
    }

    private var allocatedIDs: [UUID] {
        [planID, preparedSagaID, contentPromotedSagaID, targetCommittedSagaID, draftRetirePendingSagaID,
         draftRetiredSagaID, commitReceiptID, targetMutationID.rawValue, reservationMutationID.rawValue,
         preparedSagaMutationID.rawValue, contentPromotedSagaMutationID.rawValue,
         targetCommittedSagaMutationID.rawValue, draftRetirePendingSagaMutationID.rawValue,
         terminalBundleMutationID.rawValue]
    }

    func validate() throws {
        let ids = allocatedIDs
        try ids.forEach(FieldDraftValidationV1.id)
        try outputKeys.forEach(FieldDraftValidationV1.text)
        let times = [preparedUpdatedAt, promotionAt, contentPromotedUpdatedAt, targetCommittedUpdatedAt,
                     draftRetirePendingUpdatedAt, draftRetiredUpdatedAt, terminalCheckpointUpdatedAt]
        try (times + [reservationReviewAfter]).forEach(CheckRunnerPhotoValueValidationV1.instant)
        guard Set(ids).count == ids.count,
              expectedWorkflowRecordRevision > 0, expectedWorkflowRecordRevision < UInt64.max,
              outputKeys.count == 2, Set(outputKeys).count == 2, outputKeys == outputKeys.sorted(),
              zip(times, times.dropFirst()).allSatisfy({ $0.0 <= $0.1 }),
              reservationReviewAfter >= promotionAt else { throw FieldDraftFailureV1.invalidValue }
    }

    func rowMutationIDs(stageID: UUID) throws -> DraftCommitRowMutationIDsV1 {
        try validate(); try FieldDraftValidationV1.id(stageID)
        let rows = try DraftCommitRowMutationIDsV1(reservationByStageID: [stageID: reservationMutationID],
                                                   terminalBundleMutationID: terminalBundleMutationID)
        // The fifth saga uses terminalBundleMutationID, already checked by the
        // row validator. Its saga argument contains the four earlier operations.
        try rows.validate(stageIDs: [stageID], targetMutationID: targetMutationID,
            sagaMutationIDs: [preparedSagaMutationID, contentPromotedSagaMutationID,
                             targetCommittedSagaMutationID, draftRetirePendingSagaMutationID])
        return rows
    }

    func validate(raw: CheckRunnerPhotoRawReadyV1, recordID: UUID) throws {
        try validate(); try raw.validate(); try FieldDraftValidationV1.id(recordID)
        _ = try rowMutationIDs(stageID: raw.intent.stageID)
        let expectedOutputs = try [WorkspaceEntityIdentityV1(kind: .workflowRecord, id: recordID).stableKey,
            WorkspaceEntityIdentityV1(kind: .evidenceFile, id: raw.intent.evidenceID).stableKey].sorted()
        guard targetMutationID.rawValue == raw.intent.evidenceID, outputKeys == expectedOutputs,
              raw.intent.stageCreatedAt <= preparedUpdatedAt,
              !allocatedIDs.contains(raw.intent.stageMutationID.rawValue) else {
            throw FieldDraftFailureV1.digestMismatch
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case planID, expectedWorkflowRecordRevision, targetMutationID, outputKeys
        case reservationMutationID, reservationReviewAfter, preparedSagaID, preparedSagaMutationID, preparedUpdatedAt
        case contentPromotedSagaID, contentPromotedSagaMutationID, contentPromotedUpdatedAt
        case targetCommittedSagaID, targetCommittedSagaMutationID, targetCommittedUpdatedAt
        case draftRetirePendingSagaID, draftRetirePendingSagaMutationID, draftRetirePendingUpdatedAt
        case draftRetiredSagaID, draftRetiredUpdatedAt, commitReceiptID, terminalBundleMutationID
        case terminalCheckpointUpdatedAt, promotionAt
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(planID: c.decode(UUID.self, forKey: .planID),
            expectedWorkflowRecordRevision: c.decode(UInt64.self, forKey: .expectedWorkflowRecordRevision),
            targetMutationID: c.decode(MutationIDV1.self, forKey: .targetMutationID),
            outputKeys: c.decode([String].self, forKey: .outputKeys),
            reservationMutationID: c.decode(MutationIDV1.self, forKey: .reservationMutationID),
            reservationReviewAfter: c.decode(Date.self, forKey: .reservationReviewAfter),
            preparedSagaID: c.decode(UUID.self, forKey: .preparedSagaID),
            preparedSagaMutationID: c.decode(MutationIDV1.self, forKey: .preparedSagaMutationID),
            preparedUpdatedAt: c.decode(Date.self, forKey: .preparedUpdatedAt),
            contentPromotedSagaID: c.decode(UUID.self, forKey: .contentPromotedSagaID),
            contentPromotedSagaMutationID: c.decode(MutationIDV1.self, forKey: .contentPromotedSagaMutationID),
            contentPromotedUpdatedAt: c.decode(Date.self, forKey: .contentPromotedUpdatedAt),
            targetCommittedSagaID: c.decode(UUID.self, forKey: .targetCommittedSagaID),
            targetCommittedSagaMutationID: c.decode(MutationIDV1.self, forKey: .targetCommittedSagaMutationID),
            targetCommittedUpdatedAt: c.decode(Date.self, forKey: .targetCommittedUpdatedAt),
            draftRetirePendingSagaID: c.decode(UUID.self, forKey: .draftRetirePendingSagaID),
            draftRetirePendingSagaMutationID: c.decode(MutationIDV1.self, forKey: .draftRetirePendingSagaMutationID),
            draftRetirePendingUpdatedAt: c.decode(Date.self, forKey: .draftRetirePendingUpdatedAt),
            draftRetiredSagaID: c.decode(UUID.self, forKey: .draftRetiredSagaID),
            draftRetiredUpdatedAt: c.decode(Date.self, forKey: .draftRetiredUpdatedAt),
            commitReceiptID: c.decode(UUID.self, forKey: .commitReceiptID),
            terminalBundleMutationID: c.decode(MutationIDV1.self, forKey: .terminalBundleMutationID),
            terminalCheckpointUpdatedAt: c.decode(Date.self, forKey: .terminalCheckpointUpdatedAt),
            promotionAt: c.decode(Date.self, forKey: .promotionAt))
    }
}

/// Data availability only. The generic checkpoint remains the lifecycle owner,
/// and no case authorizes automatic normalization, commit or discard.
enum CheckRunnerPhotoDurablePhaseV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    case awaitingRawStage(CheckRunnerPhotoRawStageIntentV1)
    case rawReady(CheckRunnerPhotoRawReadyV1)
    case pairReady(CheckRunnerPhotoPairReadyV1)
    case preparedCommit(CheckRunnerPhotoPairReadyV1, CheckRunnerPhotoCommitAttemptV1)

    var intent: CheckRunnerPhotoRawStageIntentV1 {
        switch self {
        case let .awaitingRawStage(intent): intent
        case let .rawReady(raw): raw.intent
        case let .pairReady(pair), let .preparedCommit(pair, _): pair.raw.intent
        }
    }
    var raw: CheckRunnerPhotoRawReadyV1? {
        switch self {
        case .awaitingRawStage: nil
        case let .rawReady(raw): raw
        case let .pairReady(pair), let .preparedCommit(pair, _): pair.raw
        }
    }
    var pair: CheckRunnerPhotoPairReadyV1? {
        switch self {
        case .awaitingRawStage, .rawReady: nil
        case let .pairReady(pair), let .preparedCommit(pair, _): pair
        }
    }
    var attempt: CheckRunnerPhotoCommitAttemptV1? {
        switch self { case let .preparedCommit(_, attempt): attempt; default: nil }
    }
    var declaredStageIDs: [UUID] {
        switch self { case .awaitingRawStage: []; default: [intent.stageID] }
    }

    func validate() throws {
        switch self {
        case let .awaitingRawStage(intent): try intent.validate()
        case let .rawReady(raw): try raw.validate()
        case let .pairReady(pair): try pair.validate()
        case let .preparedCommit(pair, attempt): try pair.validate(); try attempt.validate()
        }
    }

    private enum CodingKeys: String, CodingKey { case tag, intent, raw, pair, attempt }
    private enum Tag: String, Codable {
        case awaitingRawStage = "AWAITING_RAW_STAGE", rawReady = "RAW_READY"
        case pairReady = "PAIR_READY", preparedCommit = "PREPARED_COMMIT"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .tag)
        let allowed: Set<String>
        switch tag {
        case .awaitingRawStage: allowed = ["tag", "intent"]
        case .rawReady: allowed = ["tag", "raw"]
        case .pairReady: allowed = ["tag", "pair"]
        case .preparedCommit: allowed = ["tag", "pair", "attempt"]
        }
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: allowed)
        switch tag {
        case .awaitingRawStage: self = .awaitingRawStage(try c.decode(CheckRunnerPhotoRawStageIntentV1.self, forKey: .intent))
        case .rawReady: self = .rawReady(try c.decode(CheckRunnerPhotoRawReadyV1.self, forKey: .raw))
        case .pairReady: self = .pairReady(try c.decode(CheckRunnerPhotoPairReadyV1.self, forKey: .pair))
        case .preparedCommit:
            self = .preparedCommit(try c.decode(CheckRunnerPhotoPairReadyV1.self, forKey: .pair),
                                   try c.decode(CheckRunnerPhotoCommitAttemptV1.self, forKey: .attempt))
        }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .awaitingRawStage(intent):
            try c.encode(Tag.awaitingRawStage, forKey: .tag); try c.encode(intent, forKey: .intent)
        case let .rawReady(raw):
            try c.encode(Tag.rawReady, forKey: .tag); try c.encode(raw, forKey: .raw)
        case let .pairReady(pair):
            try c.encode(Tag.pairReady, forKey: .tag); try c.encode(pair, forKey: .pair)
        case let .preparedCommit(pair, attempt):
            try c.encode(Tag.preparedCommit, forKey: .tag); try c.encode(pair, forKey: .pair)
            try c.encode(attempt, forKey: .attempt)
        }
    }
}

struct CheckRunnerPhotoDraftPayloadV1: Codable, Equatable, Sendable, FieldDraftValidatableV1 {
    static let schemaVersion = 1
    static let maximumPayloadBytes = 2 * 1_024 * 1_024
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let childDraftID: UUID
    let parentDraftID: UUID
    let recordID: UUID
    let assetID: UUID
    let sourceBinding: CheckRunnerRoundItemSourceV1
    let workflowStage: WorkflowStage
    let captureStep: WorkflowDraftStep
    let purposeKey: String
    let origin: OriginalContentOriginV1
    let phase: CheckRunnerPhotoDurablePhaseV1

    init(workspaceID: WorkspaceID, childDraftID: UUID, parentDraftID: UUID, recordID: UUID, assetID: UUID,
         sourceBinding: CheckRunnerRoundItemSourceV1, workflowStage: WorkflowStage,
         captureStep: WorkflowDraftStep, purposeKey: String, origin: OriginalContentOriginV1,
         phase: CheckRunnerPhotoDurablePhaseV1) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.childDraftID = childDraftID; self.parentDraftID = parentDraftID; self.recordID = recordID
        self.assetID = assetID; self.sourceBinding = sourceBinding; self.workflowStage = workflowStage
        self.captureStep = captureStep; self.purposeKey = purposeKey; self.origin = origin; self.phase = phase
        try validate()
    }

    func validate() throws {
        try FieldDraftValidationV1.workspace(workspaceID)
        try [childDraftID, parentDraftID, recordID, assetID].forEach(FieldDraftValidationV1.id)
        try sourceBinding.validate(); try phase.validate()
        try CheckRunnerPhotoSlotV1.pending(childDraftID: childDraftID, captureStep: captureStep,
                                          purposeKey: purposeKey).validate()
        guard schemaVersion == Self.schemaVersion, childDraftID != parentDraftID,
              phase.intent.evidenceID != childDraftID,
              workspaceID == sourceBinding.roundAtEntry.workspaceID, assetID == sourceBinding.assetID,
              workflowStage == sourceBinding.requestedEntry.stage else { throw FieldDraftFailureV1.invalidValue }
        if let raw = phase.raw {
            guard raw.readyItem.workspaceID == workspaceID, raw.readyItem.draftID == childDraftID,
                  raw.originalProvenance.origin == origin else { throw FieldDraftFailureV1.digestMismatch }
        }
        if let pair = phase.pair { try pair.validate(childDraftID: childDraftID, parentDraftID: parentDraftID) }
        if let attempt = phase.attempt, let raw = phase.raw { try attempt.validate(raw: raw, recordID: recordID) }
        // The encoder projects stored values without recursively invoking this
        // payload validator. The 80-MiB raw byte bound is a separate contract.
        guard try FieldDraftCanonicalCodecV1.encode(self).count <= Self.maximumPayloadBytes else {
            throw FieldDraftFailureV1.limitExceeded
        }
    }

    /// Value correspondence only. The caller still authenticates the parent
    /// checkpoint, original Begin receipts and phase-appropriate child history.
    func validate(parent: CheckRunnerItemDraftPayloadV1, parentDraftID: UUID) throws {
        try validate(); try parent.validate()
        guard self.parentDraftID == parentDraftID,
              try FieldDraftCanonicalCodecV1.encode(sourceBinding) == FieldDraftCanonicalCodecV1.encode(parent.source),
              case let .bound(begin, workflow, _) = parent.field.begin,
              begin.recordCommand.recordID == recordID,
              begin.recordCommand.startedAt <= phase.intent.evidenceCreatedAt else {
            throw FieldDraftFailureV1.digestMismatch
        }
        let slot = captureStep == .wide ? parent.field.wideContext : parent.field.closeDetail
        guard let slot, slot.childDraftID == childDraftID, slot.captureStep == captureStep,
              slot.purposeKey == purposeKey else { throw FieldDraftFailureV1.digestMismatch }
        if case let .committed(_, _, _, _, _, receiptID, _, evidenceID, _, _) = slot {
            guard let attempt = phase.attempt, evidenceID == phase.intent.evidenceID,
                  receiptID == attempt.commitReceiptID else {
                throw FieldDraftFailureV1.digestMismatch
            }
        }
        if let attempt = phase.attempt {
            guard attempt.expectedWorkflowRecordRevision >= workflow.beginPostimageRevision else {
                throw FieldDraftFailureV1.digestMismatch
            }
        }
    }

    func validateRawStageIntent(parentSlotCheckpointUpdatedAt: Date) throws {
        try validate(); try CheckRunnerPhotoValueValidationV1.instant(parentSlotCheckpointUpdatedAt)
        guard parentSlotCheckpointUpdatedAt <= phase.intent.stageCreatedAt else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    func validateCommitPreparation(pairReadyCheckpointUpdatedAt: Date) throws {
        try validate(); try CheckRunnerPhotoValueValidationV1.instant(pairReadyCheckpointUpdatedAt)
        guard let attempt = phase.attempt,
              phase.intent.stageCreatedAt <= pairReadyCheckpointUpdatedAt,
              pairReadyCheckpointUpdatedAt <= attempt.preparedUpdatedAt else {
            throw FieldDraftFailureV1.invalidValue
        }
    }

    static func encode(_ value: Self) throws -> Data {
        try value.validate()
        let data = try FieldDraftCanonicalCodecV1.encode(value)
        _ = try FieldDraftCanonicalCodecV1.decode(Self.self, from: data)
        return data
    }
    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumPayloadBytes else { throw FieldDraftFailureV1.limitExceeded }
        return try FieldDraftCanonicalCodecV1.decode(Self.self, from: data)
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let a = try? FieldDraftCanonicalCodecV1.encode(lhs),
              let b = try? FieldDraftCanonicalCodecV1.encode(rhs) else { return false }
        return a == b
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, workspaceID, childDraftID, parentDraftID, recordID, assetID, sourceBinding
        case workflowStage, captureStep, purposeKey, origin, phase
    }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw FieldDraftFailureV1.invalidValue
        }
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID),
            childDraftID: c.decode(UUID.self, forKey: .childDraftID),
            parentDraftID: c.decode(UUID.self, forKey: .parentDraftID),
            recordID: c.decode(UUID.self, forKey: .recordID), assetID: c.decode(UUID.self, forKey: .assetID),
            sourceBinding: c.decode(CheckRunnerRoundItemSourceV1.self, forKey: .sourceBinding),
            workflowStage: c.decode(WorkflowStage.self, forKey: .workflowStage),
            captureStep: c.decode(WorkflowDraftStep.self, forKey: .captureStep),
            purposeKey: c.decode(String.self, forKey: .purposeKey),
            origin: c.decode(OriginalContentOriginV1.self, forKey: .origin),
            phase: c.decode(CheckRunnerPhotoDurablePhaseV1.self, forKey: .phase))
    }
}
