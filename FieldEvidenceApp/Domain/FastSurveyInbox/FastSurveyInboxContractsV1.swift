import Foundation

enum FastSurveyInboxFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case incompatibleVersion
    case corruptDigest
    case duplicateIdentity
    case staleRevision
    case wrongWorkspace
    case missingContent
    case arithmeticOverflow
    case invalidSupersession
    case invalidPromotion
    case receiptMismatch
    case storagePressure
    case captureBudgetExceeded
    case protectedDataUnavailable
}

enum FastSurveyInboxLimitsV1 {
    static let maximumInboxTextBytes = 8_192
    static let maximumSnippetTitleBytes = 160
    static let maximumSnippetBodyBytes = 8_192
    static let maximumTagBytes = 64
    static let maximumTags = 16
    static let maximumQueryResults = 256
    static let maximumReviewSelectionCount = 100
    static let maximumContentBytes: Int64 = 268_435_456
    static let maximumWorkspaceInboxBytes: Int64 = 2_147_483_648
    static let maximumCaptureTapCount = 2
    static let maximumRecordedCaptureTapCount = 64
    static let maximumCaptureElapsedMilliseconds: UInt64 = 5_000
    static let maximumRecordedCaptureElapsedMilliseconds: UInt64 = 60_000
}

enum FastSurveyInboxLifecycleV1 {
    static let canonicalWriter = "WorkspaceWriterV1"
    static let writersPerWorkspaceGeneration = 1
    static let createsSecondStore = false
    static let canonicalPersistence = true
    static let unpromotedItemsAffectCompletedInspection = false
    static let unpromotedItemsAffectFindingsOrReports = false
    static let snippetAutomaticallyAnswers = false
    static let snippetCreatesDirectObservation = false
}

private enum FastSurveyInboxValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw FastSurveyInboxFailureV1.invalidValue } }
    static func revision(_ value: UInt64) throws { guard value > 0 else { throw FastSurveyInboxFailureV1.staleRevision } }
    static func digest(_ value: String) throws {
        guard value == value.lowercased(), KernelCanonicalHashV1.validSHA256(value) else { throw FastSurveyInboxFailureV1.corruptDigest }
    }
    static func text(_ value: String, maximumBytes: Int) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumBytes else { throw FastSurveyInboxFailureV1.invalidValue }
    }
    static func token(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= FastSurveyInboxLimitsV1.maximumTagBytes,
              value.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
    }
    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw FastSurveyInboxFailureV1.invalidValue }
    }
    static func workspace(_ value: WorkspaceID, content: ContentReferenceV1) throws {
        guard value.rawValue.uuidString.lowercased() == content.workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
    }
    static func original(_ content: ContentReferenceV1, provenance: ContentOriginalProvenanceV1,
                         workspaceID: WorkspaceID) throws {
        try workspace(workspaceID, content: content)
        guard content.byteRole == .immutableOriginal, content.byteLength > 0,
              content.byteLength <= FastSurveyInboxLimitsV1.maximumContentBytes,
              provenance.workspaceID == content.workspaceID,
              provenance.contentID == content.contentID,
              provenance.contentDigest == content.digests.digest(for: .sha256) else {
            throw FastSurveyInboxFailureV1.missingContent
        }
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
}

enum CaptureInboxMediaKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case photo = "PHOTO"
    case text = "TEXT"
    case photoWithText = "PHOTO_WITH_TEXT"
}

enum CaptureInboxRoleV1: String, CaseIterable, Codable, Hashable, Sendable {
    case context = "CONTEXT"
    case detail = "DETAIL"
    case closeup = "CLOSEUP"
    case textNote = "TEXT_NOTE"
}

enum CaptureInboxStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case unassigned = "UNASSIGNED"
    case promoted = "PROMOTED"
}

struct CaptureInboxItemV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let inboxEventID: UUID
    let inboxItemID: UUID
    let workspaceID: WorkspaceID
    let mediaKind: CaptureInboxMediaKindV1
    let captureRole: CaptureInboxRoleV1
    let content: ContentReferenceV1
    let originalProvenance: ContentOriginalProvenanceV1
    let text: String?
    let observationBasis: ObservationBasisV1
    let temporalContext: TemporalContextV1
    let capturedBy: ActorSnapshotV1
    let state: CaptureInboxStateV1
    let promotionID: UUID?
    let supersedesInboxEventID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let itemSHA256: String

    init(inboxEventID: UUID, inboxItemID: UUID, workspaceID: WorkspaceID,
         mediaKind: CaptureInboxMediaKindV1, content: ContentReferenceV1,
         captureRole: CaptureInboxRoleV1? = nil,
         originalProvenance: ContentOriginalProvenanceV1, text: String? = nil,
         observationBasis: ObservationBasisV1, temporalContext: TemporalContextV1,
         capturedBy: ActorSnapshotV1, state: CaptureInboxStateV1 = .unassigned,
         promotionID: UUID? = nil, predecessor: CaptureInboxItemV1? = nil,
         revision: UInt64, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.inboxEventID = inboxEventID; self.inboxItemID = inboxItemID
        let resolvedRole: CaptureInboxRoleV1
        if let captureRole {
            resolvedRole = captureRole
        } else if mediaKind == .text {
            resolvedRole = .textNote
        } else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        self.workspaceID = workspaceID; self.mediaKind = mediaKind; self.captureRole = resolvedRole; self.content = content
        self.originalProvenance = originalProvenance; self.text = text
        self.observationBasis = observationBasis; self.temporalContext = temporalContext
        self.capturedBy = capturedBy; self.state = state; self.promotionID = promotionID
        supersedesInboxEventID = predecessor?.inboxEventID; predecessorSHA256 = predecessor?.itemSHA256
        self.revision = revision; self.mutationID = mutationID
        itemSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            inboxEventID: inboxEventID, inboxItemID: inboxItemID, workspaceID: workspaceID,
            mediaKind: mediaKind, captureRole: resolvedRole, content: content, originalProvenance: originalProvenance,
            text: text, observationBasis: observationBasis, temporalContext: temporalContext,
            capturedBy: capturedBy, state: state, promotionID: promotionID,
            supersedesInboxEventID: predecessor?.inboxEventID, predecessorSHA256: predecessor?.itemSHA256,
            revision: revision, mutationID: mutationID))
        try validate()
        if let predecessor { try predecessor.validate(); try validateSuccessor(of: predecessor) }
    }

    func validate() throws {
        try FastSurveyInboxValidationV1.id(inboxEventID); try FastSurveyInboxValidationV1.id(inboxItemID)
        try FastSurveyInboxValidationV1.revision(revision); try promotionID.map(FastSurveyInboxValidationV1.id)
        try predecessorSHA256.map(FastSurveyInboxValidationV1.digest)
        try FastSurveyInboxValidationV1.original(content, provenance: originalProvenance, workspaceID: workspaceID)
        try observationBasis.validate(); try temporalContext.validate(); try capturedBy.validate()
        if let text { try FastSurveyInboxValidationV1.text(text, maximumBytes: FastSurveyInboxLimitsV1.maximumInboxTextBytes) }
        let mediaMatches = (mediaKind == .photo && content.mediaType.hasPrefix("image/") && text == nil)
            || (mediaKind == .text && content.mediaType == "text/plain" && text != nil)
            || (mediaKind == .photoWithText && content.mediaType.hasPrefix("image/") && text != nil)
        let roleMatches = (captureRole == .textNote && mediaKind == .text)
            || (captureRole != .textNote && mediaKind != .text)
        let isInitial = revision == 1 && state == .unassigned && promotionID == nil
            && supersedesInboxEventID == nil && predecessorSHA256 == nil
        let isPromoted = revision == 2 && state == .promoted && promotionID != nil
            && supersedesInboxEventID != nil && predecessorSHA256 != nil
        guard schemaVersion == Self.schemaVersion, mediaMatches, roleMatches,
              capturedBy.workspaceID == workspaceID, capturedBy.responsibility == .recordedBy,
              temporalContext.recordedAtUTC >= capturedBy.capturedAt,
              isInitial || isPromoted,
              itemSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
    }

    func validateSuccessor(of predecessor: Self) throws {
        guard predecessor.revision == 1, predecessor.state == .unassigned,
              revision == 2, state == .promoted,
              workspaceID == predecessor.workspaceID, inboxItemID == predecessor.inboxItemID,
              inboxEventID != predecessor.inboxEventID,
              mediaKind == predecessor.mediaKind, captureRole == predecessor.captureRole, content == predecessor.content,
              originalProvenance == predecessor.originalProvenance, text == predecessor.text,
              observationBasis == predecessor.observationBasis, temporalContext == predecessor.temporalContext,
              capturedBy == predecessor.capturedBy,
              supersedesInboxEventID == predecessor.inboxEventID,
              predecessorSHA256 == predecessor.itemSHA256,
              mutationID != predecessor.mutationID else { throw FastSurveyInboxFailureV1.invalidSupersession }
    }
    var isUnassigned: Bool { state == .unassigned }
    private var basis: Basis { .init(schemaVersion: schemaVersion, inboxEventID: inboxEventID, inboxItemID: inboxItemID,
        workspaceID: workspaceID, mediaKind: mediaKind, captureRole: captureRole, content: content, originalProvenance: originalProvenance,
        text: text, observationBasis: observationBasis, temporalContext: temporalContext, capturedBy: capturedBy,
        state: state, promotionID: promotionID, supersedesInboxEventID: supersedesInboxEventID,
        predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID) }
    private struct Basis: Codable { let schemaVersion: Int; let inboxEventID: UUID; let inboxItemID: UUID; let workspaceID: WorkspaceID; let mediaKind: CaptureInboxMediaKindV1; let captureRole: CaptureInboxRoleV1; let content: ContentReferenceV1; let originalProvenance: ContentOriginalProvenanceV1; let text: String?; let observationBasis: ObservationBasisV1; let temporalContext: TemporalContextV1; let capturedBy: ActorSnapshotV1; let state: CaptureInboxStateV1; let promotionID: UUID?; let supersedesInboxEventID: UUID?; let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1 }
}

struct FastSurveyInboxReviewSelectionEntryV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let inboxItemID: UUID
    let inboxItemRevision: UInt64
    let inboxItemSHA256: String

    init(item: CaptureInboxItemV1) throws {
        try item.validate()
        guard item.state == .unassigned else { throw FastSurveyInboxFailureV1.invalidPromotion }
        workspaceID = item.workspaceID
        inboxItemID = item.inboxItemID
        inboxItemRevision = item.revision
        inboxItemSHA256 = item.itemSHA256
    }

    func validate() throws {
        try FastSurveyInboxValidationV1.id(inboxItemID)
        try FastSurveyInboxValidationV1.revision(inboxItemRevision)
        try FastSurveyInboxValidationV1.digest(inboxItemSHA256)
        guard inboxItemRevision == 1 else { throw FastSurveyInboxFailureV1.invalidValue }
    }
}

enum FastSurveyInboxReviewSelectionActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case reviewIndividually = "REVIEW_INDIVIDUALLY"
    case retainUnassigned = "RETAIN_UNASSIGNED"
    case exportOriginals = "EXPORT_ORIGINALS"
}

enum FastSurveyInboxReviewSelectionDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case requiresPerItemValidation = "REQUIRES_PER_ITEM_VALIDATION"
    case noMutation = "NO_MUTATION"
    case readOnlyExport = "READ_ONLY_EXPORT"
}

struct FastSurveyInboxReviewSelectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let entries: [FastSurveyInboxReviewSelectionEntryV1]
    let action: FastSurveyInboxReviewSelectionActionV1
    let disposition: FastSurveyInboxReviewSelectionDispositionV1
    let maximumCount: Int

    init(workspaceID: WorkspaceID, items: [CaptureInboxItemV1],
         action: FastSurveyInboxReviewSelectionActionV1) throws {
        guard !items.isEmpty, items.count <= FastSurveyInboxLimitsV1.maximumReviewSelectionCount else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        guard items.allSatisfy({ $0.workspaceID == workspaceID }) else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        self.workspaceID = workspaceID
        entries = try items.map(FastSurveyInboxReviewSelectionEntryV1.init(item:))
        self.action = action
        switch action {
        case .reviewIndividually: disposition = .requiresPerItemValidation
        case .retainUnassigned: disposition = .noMutation
        case .exportOriginals: disposition = .readOnlyExport
        }
        maximumCount = FastSurveyInboxLimitsV1.maximumReviewSelectionCount
        try validate()
    }

    func validate() throws {
        guard !entries.isEmpty, entries.count <= maximumCount,
              maximumCount == FastSurveyInboxLimitsV1.maximumReviewSelectionCount else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        guard entries.allSatisfy({ $0.workspaceID == workspaceID }) else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        guard Set(entries.map(\.inboxItemID)).count == entries.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
        try entries.forEach { try $0.validate() }
        let expected: FastSurveyInboxReviewSelectionDispositionV1
        switch action {
        case .reviewIndividually: expected = .requiresPerItemValidation
        case .retainUnassigned: expected = .noMutation
        case .exportOriginals: expected = .readOnlyExport
        }
        guard disposition == expected else { throw FastSurveyInboxFailureV1.invalidValue }
    }

    func validate(items: [CaptureInboxItemV1]) throws {
        try validate()
        let exactOrderedMatch = try zip(entries, items).allSatisfy { pair in
            let (entry, item) = pair
            try item.validate()
            return entry == (try FastSurveyInboxReviewSelectionEntryV1(item: item))
        }
        guard items.count == entries.count,
              items.allSatisfy({ $0.workspaceID == workspaceID && $0.state == .unassigned }),
              exactOrderedMatch else { throw FastSurveyInboxFailureV1.staleRevision }
    }

    static let permitsBulkPromotion = false
    static let permitsBulkDeletion = false
    static let isPersistent = false
}

enum CapturePromotionDestinationKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case assetEvidence = "ASSET_EVIDENCE"
    case responseEvidence = "RESPONSE_EVIDENCE"
    case findingEvidence = "FINDING_EVIDENCE"
    case correctiveWorkEvidence = "CORRECTIVE_WORK_EVIDENCE"
}

struct CapturePromotionDestinationV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let kind: CapturePromotionDestinationKindV1
    let destinationID: UUID
    let destinationRevision: UInt64
    let destinationSHA256: String
    init(workspaceID: WorkspaceID, kind: CapturePromotionDestinationKindV1, destinationID: UUID,
         destinationRevision: UInt64, destinationSHA256: String) throws {
        try FastSurveyInboxValidationV1.id(destinationID); try FastSurveyInboxValidationV1.revision(destinationRevision)
        try FastSurveyInboxValidationV1.digest(destinationSHA256)
        self.workspaceID = workspaceID; self.kind = kind; self.destinationID = destinationID
        self.destinationRevision = destinationRevision; self.destinationSHA256 = destinationSHA256
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, kind: kind, destinationID: destinationID, destinationRevision: destinationRevision, destinationSHA256: destinationSHA256) }
    func validate(resolver: any CapturePromotionDestinationResolvingV1) throws {
        try validate()
        let resolved = try resolver.resolveCapturePromotionDestination(
            workspaceID: workspaceID, kind: kind, destinationID: destinationID)
        try resolved.validate()
        guard resolved == self else { throw FastSurveyInboxFailureV1.staleRevision }
    }
}

protocol CapturePromotionDestinationResolvingV1 {
    func resolveCapturePromotionDestination(workspaceID: WorkspaceID,
        kind: CapturePromotionDestinationKindV1, destinationID: UUID) throws -> CapturePromotionDestinationV1
}

struct CapturePromotionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let promotionID: UUID
    let workspaceID: WorkspaceID
    let sourceInboxItemID: UUID
    let sourceInboxRevision: UInt64
    let sourceInboxSHA256: String
    let promotedInboxRevision: UInt64
    let promotedInboxSHA256: String
    let destination: CapturePromotionDestinationV1
    let originalContent: ContentReferenceV1
    let originalProvenance: ContentOriginalProvenanceV1
    let idempotencySHA256: String
    let promotedBy: ActorSnapshotV1
    let promotedAt: Date
    let revision: UInt64
    let mutationID: MutationIDV1
    let promotionSHA256: String

    init(promotionID: UUID, source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1,
         destination: CapturePromotionDestinationV1, promotedBy: ActorSnapshotV1,
         promotedAt: Date, revision: UInt64 = 1, mutationID: MutationIDV1) throws {
        schemaVersion = Self.schemaVersion; self.promotionID = promotionID; workspaceID = source.workspaceID
        sourceInboxItemID = source.inboxItemID; sourceInboxRevision = source.revision
        sourceInboxSHA256 = source.itemSHA256; promotedInboxRevision = promotedItem.revision
        promotedInboxSHA256 = promotedItem.itemSHA256; self.destination = destination
        originalContent = source.content; originalProvenance = source.originalProvenance
        self.promotedBy = promotedBy; self.promotedAt = promotedAt; self.revision = revision; self.mutationID = mutationID
        idempotencySHA256 = try FastSurveyInboxValidationV1.sha256(IdempotencyBasis(workspaceID: source.workspaceID,
            sourceInboxItemID: source.inboxItemID, sourceInboxRevision: source.revision,
            sourceInboxSHA256: source.itemSHA256, destination: destination))
        promotionSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            promotionID: promotionID, workspaceID: source.workspaceID, sourceInboxItemID: source.inboxItemID,
            sourceInboxRevision: source.revision, sourceInboxSHA256: source.itemSHA256,
            promotedInboxRevision: promotedItem.revision, promotedInboxSHA256: promotedItem.itemSHA256,
            destination: destination, originalContent: source.content, originalProvenance: source.originalProvenance,
            idempotencySHA256: idempotencySHA256, promotedBy: promotedBy, promotedAt: promotedAt,
            revision: revision, mutationID: mutationID))
        try validate(source: source, promotedItem: promotedItem)
    }

    func validate(source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1) throws {
        try validateIntrinsic(promotedItem: promotedItem)
        try source.validate(); try promotedItem.validate(); try promotedItem.validateSuccessor(of: source)
        guard schemaVersion == Self.schemaVersion, revision == 1, destination.workspaceID == workspaceID,
              source.state == .unassigned, promotedItem.state == .promoted,
              promotedItem.promotionID == promotionID, workspaceID == source.workspaceID,
              promotedItem.workspaceID == workspaceID, sourceInboxItemID == source.inboxItemID,
              sourceInboxRevision == source.revision, sourceInboxSHA256 == source.itemSHA256,
              promotedInboxRevision == promotedItem.revision, promotedInboxSHA256 == promotedItem.itemSHA256,
              originalContent == source.content, originalProvenance == source.originalProvenance,
              mutationID == promotedItem.mutationID, promotedBy.workspaceID == workspaceID,
              promotedBy.responsibility == .recordedBy,
              promotedAt >= source.temporalContext.recordedAtUTC else {
            throw FastSurveyInboxFailureV1.invalidPromotion
        }
    }
    func validate(source: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1,
                  resolver: any CapturePromotionDestinationResolvingV1) throws {
        try validate(source: source, promotedItem: promotedItem)
        try destination.validate(resolver: resolver)
    }
    func validateIntrinsic(promotedItem: CaptureInboxItemV1) throws {
        try FastSurveyInboxValidationV1.id(promotionID); try FastSurveyInboxValidationV1.revision(revision)
        try FastSurveyInboxValidationV1.digest(sourceInboxSHA256); try FastSurveyInboxValidationV1.digest(promotedInboxSHA256)
        try destination.validate(); try promotedBy.validate(); try FastSurveyInboxValidationV1.instant(promotedAt)
        try FastSurveyInboxValidationV1.original(originalContent, provenance: originalProvenance, workspaceID: workspaceID)
        let expectedIdempotency = try FastSurveyInboxValidationV1.sha256(IdempotencyBasis(workspaceID: workspaceID,
            sourceInboxItemID: sourceInboxItemID, sourceInboxRevision: sourceInboxRevision,
            sourceInboxSHA256: sourceInboxSHA256, destination: destination))
        guard schemaVersion == Self.schemaVersion, revision == 1, sourceInboxRevision == 1,
              destination.workspaceID == workspaceID,
              promotedInboxRevision == 2, promotedItem.state == .promoted,
              promotedItem.workspaceID == workspaceID, promotedItem.inboxItemID == sourceInboxItemID,
              promotedItem.revision == promotedInboxRevision, promotedItem.itemSHA256 == promotedInboxSHA256,
              promotedItem.predecessorSHA256 == sourceInboxSHA256, promotedItem.promotionID == promotionID,
              promotedItem.content == originalContent, promotedItem.originalProvenance == originalProvenance,
              promotedItem.mutationID == mutationID, promotedBy.workspaceID == workspaceID,
              promotedBy.responsibility == .recordedBy, idempotencySHA256 == expectedIdempotency,
              promotionSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else {
            throw FastSurveyInboxFailureV1.invalidPromotion
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, promotionID: promotionID, workspaceID: workspaceID,
        sourceInboxItemID: sourceInboxItemID, sourceInboxRevision: sourceInboxRevision,
        sourceInboxSHA256: sourceInboxSHA256, promotedInboxRevision: promotedInboxRevision,
        promotedInboxSHA256: promotedInboxSHA256, destination: destination, originalContent: originalContent,
        originalProvenance: originalProvenance, idempotencySHA256: idempotencySHA256,
        promotedBy: promotedBy, promotedAt: promotedAt, revision: revision, mutationID: mutationID) }
    private struct IdempotencyBasis: Codable { let workspaceID: WorkspaceID; let sourceInboxItemID: UUID; let sourceInboxRevision: UInt64; let sourceInboxSHA256: String; let destination: CapturePromotionDestinationV1 }
    private struct Basis: Codable { let schemaVersion: Int; let promotionID: UUID; let workspaceID: WorkspaceID; let sourceInboxItemID: UUID; let sourceInboxRevision: UInt64; let sourceInboxSHA256: String; let promotedInboxRevision: UInt64; let promotedInboxSHA256: String; let destination: CapturePromotionDestinationV1; let originalContent: ContentReferenceV1; let originalProvenance: ContentOriginalProvenanceV1; let idempotencySHA256: String; let promotedBy: ActorSnapshotV1; let promotedAt: Date; let revision: UInt64; let mutationID: MutationIDV1 }
}

enum SnippetApplicabilityScopeV1: String, CaseIterable, Codable, Hashable, Sendable {
    case allLocalSurveys = "ALL_LOCAL_SURVEYS"
    case surveyDefinition = "SURVEY_DEFINITION"
    case question = "QUESTION"
}

struct SnippetApplicabilityV1: Codable, Equatable, Hashable, Sendable {
    let scope: SnippetApplicabilityScopeV1
    let targetID: String?
    init(scope: SnippetApplicabilityScopeV1, targetID: String? = nil) throws {
        if let targetID { try FastSurveyInboxValidationV1.token(targetID) }
        guard (scope == .allLocalSurveys) == (targetID == nil) else { throw FastSurveyInboxFailureV1.invalidValue }
        self.scope = scope; self.targetID = targetID
    }
    func validate() throws { _ = try Self(scope: scope, targetID: targetID) }
}

enum SnippetStateV1: String, CaseIterable, Codable, Hashable, Sendable { case active = "ACTIVE"; case retired = "RETIRED" }

struct SnippetV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let snippetEventID: UUID
    let snippetID: UUID
    let workspaceID: WorkspaceID
    let title: String
    let body: String
    let tags: [String]
    let applicability: SnippetApplicabilityV1
    let state: SnippetStateV1
    let supersedesSnippetEventID: UUID?
    let predecessorSHA256: String?
    let revision: UInt64
    let mutationID: MutationIDV1
    let editedBy: ActorSnapshotV1
    let editedAt: Date
    let snippetSHA256: String

    init(snippetEventID: UUID, snippetID: UUID, workspaceID: WorkspaceID,
         title: String, body: String, tags: [String], applicability: SnippetApplicabilityV1,
         state: SnippetStateV1 = .active, predecessor: SnippetV1? = nil,
         revision: UInt64, mutationID: MutationIDV1, editedBy: ActorSnapshotV1, editedAt: Date) throws {
        let tags = tags.map { $0.lowercased() }.sorted()
        schemaVersion = Self.schemaVersion; self.snippetEventID = snippetEventID; self.snippetID = snippetID
        self.workspaceID = workspaceID; self.title = title; self.body = body; self.tags = tags
        self.applicability = applicability; self.state = state
        supersedesSnippetEventID = predecessor?.snippetEventID; predecessorSHA256 = predecessor?.snippetSHA256
        self.revision = revision; self.mutationID = mutationID; self.editedBy = editedBy; self.editedAt = editedAt
        snippetSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            snippetEventID: snippetEventID, snippetID: snippetID, workspaceID: workspaceID,
            title: title, body: body, tags: tags, applicability: applicability, state: state,
            supersedesSnippetEventID: predecessor?.snippetEventID, predecessorSHA256: predecessor?.snippetSHA256,
            revision: revision, mutationID: mutationID, editedBy: editedBy, editedAt: editedAt))
        try validate(); if let predecessor { try predecessor.validate(); try validateSuccessor(of: predecessor) }
    }
    func validate() throws {
        try FastSurveyInboxValidationV1.id(snippetEventID); try FastSurveyInboxValidationV1.id(snippetID)
        try FastSurveyInboxValidationV1.revision(revision); try FastSurveyInboxValidationV1.text(title, maximumBytes: FastSurveyInboxLimitsV1.maximumSnippetTitleBytes)
        try FastSurveyInboxValidationV1.text(body, maximumBytes: FastSurveyInboxLimitsV1.maximumSnippetBodyBytes)
        try tags.forEach(FastSurveyInboxValidationV1.token); try applicability.validate(); try editedBy.validate()
        try FastSurveyInboxValidationV1.instant(editedAt); try predecessorSHA256.map(FastSurveyInboxValidationV1.digest)
        guard schemaVersion == Self.schemaVersion, tags.count <= FastSurveyInboxLimitsV1.maximumTags,
              tags == tags.sorted(), Set(tags).count == tags.count,
              editedBy.workspaceID == workspaceID, editedBy.responsibility == .recordedBy,
              (revision == 1) == (supersedesSnippetEventID == nil && predecessorSHA256 == nil),
              snippetSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else { throw FastSurveyInboxFailureV1.invalidValue }
    }
    func validateSuccessor(of predecessor: Self) throws {
        let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
        guard !overflow else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
        guard predecessor.state == .active, workspaceID == predecessor.workspaceID,
              snippetID == predecessor.snippetID, snippetEventID != predecessor.snippetEventID,
              supersedesSnippetEventID == predecessor.snippetEventID,
              predecessorSHA256 == predecessor.snippetSHA256, revision == next,
              mutationID != predecessor.mutationID, editedAt >= predecessor.editedAt else {
            throw FastSurveyInboxFailureV1.invalidSupersession
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, snippetEventID: snippetEventID,
        snippetID: snippetID, workspaceID: workspaceID, title: title, body: body, tags: tags,
        applicability: applicability, state: state, supersedesSnippetEventID: supersedesSnippetEventID,
        predecessorSHA256: predecessorSHA256, revision: revision, mutationID: mutationID,
        editedBy: editedBy, editedAt: editedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let snippetEventID: UUID; let snippetID: UUID; let workspaceID: WorkspaceID; let title: String; let body: String; let tags: [String]; let applicability: SnippetApplicabilityV1; let state: SnippetStateV1; let supersedesSnippetEventID: UUID?; let predecessorSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let editedBy: ActorSnapshotV1; let editedAt: Date }
}

struct SnippetInsertionPreviewV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let snippetID: UUID
    let snippetRevision: UInt64
    let snippetSHA256: String
    let targetDraftID: UUID
    let targetDraftRevision: UInt64
    let insertionText: String
    let automaticallyAnswers: Bool
    let createsDirectObservation: Bool
    let requiresExplicitBasisAndSave: Bool
    let previewSHA256: String
    init(snippet: SnippetV1, targetDraftID: UUID, targetDraftRevision: UInt64) throws {
        try snippet.validate(); try FastSurveyInboxValidationV1.id(targetDraftID)
        try FastSurveyInboxValidationV1.revision(targetDraftRevision)
        workspaceID = snippet.workspaceID; snippetID = snippet.snippetID; snippetRevision = snippet.revision
        snippetSHA256 = snippet.snippetSHA256; self.targetDraftID = targetDraftID
        self.targetDraftRevision = targetDraftRevision; insertionText = snippet.body
        automaticallyAnswers = false; createsDirectObservation = false; requiresExplicitBasisAndSave = true
        previewSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(workspaceID: snippet.workspaceID,
            snippetID: snippet.snippetID, snippetRevision: snippet.revision, snippetSHA256: snippet.snippetSHA256,
            targetDraftID: targetDraftID, targetDraftRevision: targetDraftRevision,
            insertionText: snippet.body, automaticallyAnswers: false,
            createsDirectObservation: false, requiresExplicitBasisAndSave: true))
    }
    func validate() throws {
        try FastSurveyInboxValidationV1.id(snippetID); try FastSurveyInboxValidationV1.revision(snippetRevision)
        try FastSurveyInboxValidationV1.digest(snippetSHA256); try FastSurveyInboxValidationV1.id(targetDraftID)
        try FastSurveyInboxValidationV1.revision(targetDraftRevision)
        try FastSurveyInboxValidationV1.text(insertionText, maximumBytes: FastSurveyInboxLimitsV1.maximumSnippetBodyBytes)
        guard !automaticallyAnswers, !createsDirectObservation, requiresExplicitBasisAndSave,
              previewSHA256 == (try FastSurveyInboxValidationV1.sha256(Basis(workspaceID: workspaceID,
                snippetID: snippetID, snippetRevision: snippetRevision, snippetSHA256: snippetSHA256,
                targetDraftID: targetDraftID, targetDraftRevision: targetDraftRevision,
                insertionText: insertionText, automaticallyAnswers: automaticallyAnswers,
                createsDirectObservation: createsDirectObservation,
                requiresExplicitBasisAndSave: requiresExplicitBasisAndSave))) else {
            throw FastSurveyInboxFailureV1.corruptDigest
        }
    }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let snippetID: UUID; let snippetRevision: UInt64; let snippetSHA256: String; let targetDraftID: UUID; let targetDraftRevision: UInt64; let insertionText: String; let automaticallyAnswers: Bool; let createsDirectObservation: Bool; let requiresExplicitBasisAndSave: Bool }
}

enum SnippetInsertionTargetKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case assetNoteDraft = "ASSET_NOTE_DRAFT"
    case responseDraft = "RESPONSE_DRAFT"
    case findingDraft = "FINDING_DRAFT"
    case correctiveWorkDraft = "CORRECTIVE_WORK_DRAFT"
}

struct SnippetInsertionTargetV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let kind: SnippetInsertionTargetKindV1
    let targetID: UUID
    let targetRevision: UInt64
    let targetSHA256: String

    init(workspaceID: WorkspaceID, kind: SnippetInsertionTargetKindV1, targetID: UUID,
         targetRevision: UInt64, targetSHA256: String) throws {
        try FastSurveyInboxValidationV1.id(targetID); try FastSurveyInboxValidationV1.revision(targetRevision)
        try FastSurveyInboxValidationV1.digest(targetSHA256)
        self.workspaceID = workspaceID; self.kind = kind; self.targetID = targetID
        self.targetRevision = targetRevision; self.targetSHA256 = targetSHA256
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, kind: kind, targetID: targetID, targetRevision: targetRevision, targetSHA256: targetSHA256) }
}

enum SnippetInsertionSaveIntentV1: String, CaseIterable, Codable, Hashable, Sendable {
    case explicitUserSave = "EXPLICIT_USER_SAVE"
}

struct SnippetInsertionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let insertionEventID: UUID
    let workspaceID: WorkspaceID
    let snippetID: UUID
    let snippetRevision: UInt64
    let snippetSHA256: String
    let target: SnippetInsertionTargetV1
    let observationBasis: ObservationBasisV1
    let saveIntent: SnippetInsertionSaveIntentV1
    let insertedText: String
    let insertedTextSHA256: String
    let insertedBy: ActorSnapshotV1
    let insertedAt: Date
    let mutationID: MutationIDV1
    let insertionSHA256: String

    init(insertionEventID: UUID, snippet: SnippetV1, target: SnippetInsertionTargetV1,
         observationBasis: ObservationBasisV1, saveIntent: SnippetInsertionSaveIntentV1,
         insertedBy: ActorSnapshotV1, insertedAt: Date, mutationID: MutationIDV1) throws {
        try snippet.validate(); try target.validate(); try observationBasis.validate(); try insertedBy.validate()
        schemaVersion = Self.schemaVersion; self.insertionEventID = insertionEventID
        workspaceID = snippet.workspaceID; snippetID = snippet.snippetID; snippetRevision = snippet.revision
        snippetSHA256 = snippet.snippetSHA256; self.target = target; self.observationBasis = observationBasis
        self.saveIntent = saveIntent; insertedText = snippet.body
        insertedTextSHA256 = try FastSurveyInboxValidationV1.sha256(FrozenTextBasis(text: snippet.body))
        self.insertedBy = insertedBy; self.insertedAt = insertedAt; self.mutationID = mutationID
        insertionSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            insertionEventID: insertionEventID, workspaceID: snippet.workspaceID, snippetID: snippet.snippetID,
            snippetRevision: snippet.revision, snippetSHA256: snippet.snippetSHA256, target: target,
            observationBasis: observationBasis, saveIntent: saveIntent, insertedText: snippet.body,
            insertedTextSHA256: insertedTextSHA256, insertedBy: insertedBy, insertedAt: insertedAt,
            mutationID: mutationID))
        try validate(snippet: snippet)
    }

    func validate() throws {
        try FastSurveyInboxValidationV1.id(insertionEventID); try FastSurveyInboxValidationV1.id(snippetID)
        try FastSurveyInboxValidationV1.revision(snippetRevision); try FastSurveyInboxValidationV1.digest(snippetSHA256)
        try target.validate(); try observationBasis.validate(); try insertedBy.validate()
        try FastSurveyInboxValidationV1.instant(insertedAt)
        try FastSurveyInboxValidationV1.text(insertedText, maximumBytes: FastSurveyInboxLimitsV1.maximumSnippetBodyBytes)
        guard schemaVersion == Self.schemaVersion, target.workspaceID == workspaceID,
              insertedBy.workspaceID == workspaceID, insertedBy.responsibility == .recordedBy,
              saveIntent == .explicitUserSave,
              insertedTextSHA256 == (try FastSurveyInboxValidationV1.sha256(FrozenTextBasis(text: insertedText))),
              insertionSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
    }

    func validate(snippet: SnippetV1) throws {
        try validate(); try snippet.validate()
        guard snippet.state == .active, snippet.workspaceID == workspaceID, snippet.snippetID == snippetID,
              snippet.revision == snippetRevision, snippet.snippetSHA256 == snippetSHA256,
              snippet.body == insertedText else { throw FastSurveyInboxFailureV1.staleRevision }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, insertionEventID: insertionEventID,
        workspaceID: workspaceID, snippetID: snippetID, snippetRevision: snippetRevision,
        snippetSHA256: snippetSHA256, target: target, observationBasis: observationBasis,
        saveIntent: saveIntent, insertedText: insertedText, insertedTextSHA256: insertedTextSHA256,
        insertedBy: insertedBy, insertedAt: insertedAt, mutationID: mutationID) }
    private struct FrozenTextBasis: Codable { let text: String }
    private struct Basis: Codable { let schemaVersion: Int; let insertionEventID: UUID; let workspaceID: WorkspaceID; let snippetID: UUID; let snippetRevision: UInt64; let snippetSHA256: String; let target: SnippetInsertionTargetV1; let observationBasis: ObservationBasisV1; let saveIntent: SnippetInsertionSaveIntentV1; let insertedText: String; let insertedTextSHA256: String; let insertedBy: ActorSnapshotV1; let insertedAt: Date; let mutationID: MutationIDV1 }
}

struct SnippetInsertionProjectionV1: Codable, Equatable, Sendable {
    let insertion: SnippetInsertionV1
    let textIsFrozen: Bool
    let laterSnippetChangesAffectInsertion: Bool
    init(insertion: SnippetInsertionV1) throws {
        try insertion.validate(); self.insertion = insertion
        textIsFrozen = true; laterSnippetChangesAffectInsertion = false
    }
    func validate() throws {
        try insertion.validate()
        guard textIsFrozen, !laterSnippetChangesAffectInsertion else { throw FastSurveyInboxFailureV1.invalidValue }
    }
}

enum FastSurveyInboxMutationPayloadV1: Codable, Equatable, Sendable {
    case putInboxItem(CaptureInboxItemV1)
    case promote(CapturePromotionV1, CaptureInboxItemV1)
    case putSnippet(SnippetV1)
    case insertSnippet(SnippetInsertionV1, SnippetV1)
    var workspaceID: WorkspaceID { switch self { case let .putInboxItem(v): return v.workspaceID; case let .promote(v, _): return v.workspaceID; case let .putSnippet(v): return v.workspaceID; case let .insertSnippet(v, _): return v.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case let .putInboxItem(v): return v.mutationID; case let .promote(v, _): return v.mutationID; case let .putSnippet(v): return v.mutationID; case let .insertSnippet(v, _): return v.mutationID } }
    var semanticSHA256s: [String] { switch self { case let .putInboxItem(v): return [v.itemSHA256]; case let .promote(v, item): return [item.itemSHA256, v.promotionSHA256].sorted(); case let .putSnippet(v): return [v.snippetSHA256]; case let .insertSnippet(v, _): return [v.insertionSHA256] } }
    func validate() throws {
        switch self {
        case let .putInboxItem(value):
            try value.validate(); guard value.state == .unassigned else { throw FastSurveyInboxFailureV1.invalidPromotion }
        case let .promote(promotion, promotedItem):
            try promotedItem.validate(); try promotion.validateIntrinsic(promotedItem: promotedItem)
        case let .putSnippet(value):
            try value.validate()
        case let .insertSnippet(insertion, snippet):
            try insertion.validate(snippet: snippet)
        }
    }
}

struct FastSurveyInboxCaptureBudgetV1: Codable, Equatable, Sendable {
    let tapCount: Int
    let elapsedMilliseconds: UInt64
    let maximumTapCount: Int
    let maximumElapsedMilliseconds: UInt64
    let isWithinBudget: Bool

    init(tapCount: Int, elapsedMilliseconds: UInt64) throws {
        guard (0...FastSurveyInboxLimitsV1.maximumRecordedCaptureTapCount).contains(tapCount),
              elapsedMilliseconds <= FastSurveyInboxLimitsV1.maximumRecordedCaptureElapsedMilliseconds else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        self.tapCount = tapCount
        self.elapsedMilliseconds = elapsedMilliseconds
        maximumTapCount = FastSurveyInboxLimitsV1.maximumCaptureTapCount
        maximumElapsedMilliseconds = FastSurveyInboxLimitsV1.maximumCaptureElapsedMilliseconds
        isWithinBudget = tapCount <= maximumTapCount && elapsedMilliseconds <= maximumElapsedMilliseconds
    }

    func validate() throws {
        guard (0...FastSurveyInboxLimitsV1.maximumRecordedCaptureTapCount).contains(tapCount),
              elapsedMilliseconds <= FastSurveyInboxLimitsV1.maximumRecordedCaptureElapsedMilliseconds,
              maximumTapCount == FastSurveyInboxLimitsV1.maximumCaptureTapCount,
              maximumElapsedMilliseconds == FastSurveyInboxLimitsV1.maximumCaptureElapsedMilliseconds,
              isWithinBudget == (tapCount <= maximumTapCount && elapsedMilliseconds <= maximumElapsedMilliseconds) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
    }

    func requireAdmission() throws {
        try validate()
        guard isWithinBudget else { throw FastSurveyInboxFailureV1.captureBudgetExceeded }
    }
}

enum FastSurveyInboxProtectedDataStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case available = "AVAILABLE"
    case unavailableLocked = "UNAVAILABLE_LOCKED"
    case unavailableTransition = "UNAVAILABLE_TRANSITION"

    var admitsCapture: Bool { self == .available }
}

enum FastSurveyInboxCaptureAdmissionDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case admitted = "ADMITTED"
    case tapBudgetExceeded = "TAP_BUDGET_EXCEEDED"
    case elapsedBudgetExceeded = "ELAPSED_BUDGET_EXCEEDED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case storagePressure = "STORAGE_PRESSURE"
}

struct FastSurveyInboxCaptureAdmissionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let budget: FastSurveyInboxCaptureBudgetV1
    let protectedDataState: FastSurveyInboxProtectedDataStateV1
    let storagePressure: FastSurveyInboxStoragePressureV1
    let disposition: FastSurveyInboxCaptureAdmissionDispositionV1

    init(workspaceID: WorkspaceID, budget: FastSurveyInboxCaptureBudgetV1,
         protectedDataState: FastSurveyInboxProtectedDataStateV1,
         storagePressure: FastSurveyInboxStoragePressureV1) throws {
        try budget.validate(); try storagePressure.validate()
        guard storagePressure.workspaceID == workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        self.workspaceID = workspaceID
        self.budget = budget
        self.protectedDataState = protectedDataState
        self.storagePressure = storagePressure
        if budget.tapCount > budget.maximumTapCount {
            disposition = .tapBudgetExceeded
        } else if budget.elapsedMilliseconds > budget.maximumElapsedMilliseconds {
            disposition = .elapsedBudgetExceeded
        } else if !protectedDataState.admitsCapture {
            disposition = .protectedDataUnavailable
        } else if !storagePressure.admitsCapture {
            disposition = .storagePressure
        } else {
            disposition = .admitted
        }
        try validate()
    }

    func validate() throws {
        try budget.validate(); try storagePressure.validate()
        guard storagePressure.workspaceID == workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        let expected: FastSurveyInboxCaptureAdmissionDispositionV1
        if budget.tapCount > budget.maximumTapCount {
            expected = .tapBudgetExceeded
        } else if budget.elapsedMilliseconds > budget.maximumElapsedMilliseconds {
            expected = .elapsedBudgetExceeded
        } else if !protectedDataState.admitsCapture {
            expected = .protectedDataUnavailable
        } else if !storagePressure.admitsCapture {
            expected = .storagePressure
        } else {
            expected = .admitted
        }
        guard disposition == expected else { throw FastSurveyInboxFailureV1.invalidValue }
    }

    func requireAdmission() throws {
        try validate()
        switch disposition {
        case .admitted: return
        case .tapBudgetExceeded, .elapsedBudgetExceeded: throw FastSurveyInboxFailureV1.captureBudgetExceeded
        case .protectedDataUnavailable: throw FastSurveyInboxFailureV1.protectedDataUnavailable
        case .storagePressure: throw FastSurveyInboxFailureV1.storagePressure
        }
    }

    static let claimsMeasuredDevicePerformance = false
    static let claimsProtectedDataAvailabilityBeyondObservation = false
}

enum FastSurveyInboxMutationAdmissionV1: Codable, Equatable, Sendable {
    case capture(FastSurveyInboxCaptureAdmissionV1)
    case notApplicable

    func validate(payload: FastSurveyInboxMutationPayloadV1) throws {
        switch (payload, self) {
        case let (.putInboxItem(item), .capture(admission)):
            guard admission.workspaceID == item.workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
            try admission.requireAdmission()
        case (.promote(_, _), .notApplicable), (.putSnippet(_), .notApplicable),
             (.insertSnippet(_, _), .notApplicable):
            return
        default:
            throw FastSurveyInboxFailureV1.invalidValue
        }
    }
}

struct FastSurveyInboxMutationCommandV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID
    let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1
    let payload: FastSurveyInboxMutationPayloadV1; let admission: FastSurveyInboxMutationAdmissionV1
    let submittedAt: Date; let commandSHA256: String
    init(commandID: UUID, workspaceID: WorkspaceID, expectedRevision: WorkspaceExpectedRevisionV1,
         mutationID: MutationIDV1, payload: FastSurveyInboxMutationPayloadV1,
         admission: FastSurveyInboxMutationAdmissionV1 = .notApplicable, submittedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.commandID = commandID; self.workspaceID = workspaceID
        self.expectedRevision = expectedRevision; self.mutationID = mutationID; self.payload = payload
        self.admission = admission; self.submittedAt = submittedAt
        commandSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            commandID: commandID, workspaceID: workspaceID, expectedRevision: expectedRevision,
            mutationID: mutationID, payload: payload, admission: admission, submittedAt: submittedAt)); try validate()
    }
    func validate() throws {
        try FastSurveyInboxValidationV1.id(commandID); try FastSurveyInboxValidationV1.instant(submittedAt)
        try payload.validate(); try admission.validate(payload: payload)
        guard schemaVersion == Self.schemaVersion, expectedRevision.workspaceID == workspaceID,
              expectedRevision.generationID != FastSurveyInboxValidationV1.zero,
              expectedRevision.writerInstanceID != FastSurveyInboxValidationV1.zero,
              payload.workspaceID == workspaceID, payload.mutationID == mutationID,
              Set(payload.semanticSHA256s).count == payload.semanticSHA256s.count,
              commandSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else { throw FastSurveyInboxFailureV1.wrongWorkspace }
    }
    func validate(currentRevision: WorkspaceRevisionV1) throws {
        try validate(); guard WorkspaceExpectedRevisionV1(snapshot: currentRevision) == expectedRevision else { throw FastSurveyInboxFailureV1.staleRevision }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, commandID: commandID, workspaceID: workspaceID, expectedRevision: expectedRevision, mutationID: mutationID, payload: payload, admission: admission, submittedAt: submittedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let commandID: UUID; let workspaceID: WorkspaceID; let expectedRevision: WorkspaceExpectedRevisionV1; let mutationID: MutationIDV1; let payload: FastSurveyInboxMutationPayloadV1; let admission: FastSurveyInboxMutationAdmissionV1; let submittedAt: Date }
}

enum FastSurveyInboxQueryTargetV1: Codable, Equatable, Sendable {
    case inboxItem(UUID)
    case unassignedItems
    case promotion(UUID)
    case snippet(UUID)
    case applicableSnippets(SnippetApplicabilityV1)
    case snippetInsertion(UUID)
    case snippetInsertions(SnippetInsertionTargetV1)
}
struct FastSurveyInboxQueryV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let target: FastSurveyInboxQueryTargetV1; let maximumResults: Int
    init(workspaceID: WorkspaceID, target: FastSurveyInboxQueryTargetV1, maximumResults: Int = 100) throws {
        guard (1...FastSurveyInboxLimitsV1.maximumQueryResults).contains(maximumResults) else { throw FastSurveyInboxFailureV1.invalidValue }
        switch target {
        case let .inboxItem(id), let .promotion(id), let .snippet(id), let .snippetInsertion(id):
            try FastSurveyInboxValidationV1.id(id)
        case let .applicableSnippets(v): try v.validate()
        case let .snippetInsertions(v):
            try v.validate(); guard v.workspaceID == workspaceID else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        case .unassignedItems: break
        }
        self.workspaceID = workspaceID; self.target = target; self.maximumResults = maximumResults
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, target: target, maximumResults: maximumResults) }
}

enum CaptureInboxItemProjectionV1: Codable, Equatable, Sendable {
    case unassigned(CaptureInboxItemV1)
    case promoted(CapturePromotionProjectionV1)
    func validate() throws {
        switch self {
        case let .unassigned(item): try item.validate(); guard item.state == .unassigned else { throw FastSurveyInboxFailureV1.invalidValue }
        case let .promoted(value): try value.validate()
        }
    }
}
struct CapturePromotionProjectionV1: Codable, Equatable, Sendable {
    let sourceItem: CaptureInboxItemV1; let promotedItem: CaptureInboxItemV1; let promotion: CapturePromotionV1
    init(sourceItem: CaptureInboxItemV1, promotedItem: CaptureInboxItemV1, promotion: CapturePromotionV1) throws {
        try promotion.validate(source: sourceItem, promotedItem: promotedItem)
        self.sourceItem = sourceItem; self.promotedItem = promotedItem; self.promotion = promotion
    }
    func validate() throws { _ = try Self(sourceItem: sourceItem, promotedItem: promotedItem, promotion: promotion) }
}
enum FastSurveyInboxQueryResultV1: Codable, Equatable, Sendable {
    case inboxItem(CaptureInboxItemProjectionV1)
    case inboxItems([CaptureInboxItemProjectionV1])
    case promotion(CapturePromotionProjectionV1)
    case snippet(SnippetV1)
    case snippets([SnippetV1])
    case snippetInsertion(SnippetInsertionProjectionV1)
    case snippetInsertions([SnippetInsertionProjectionV1])
    case notFound(FastSurveyInboxQueryV1)
    func validate(for query: FastSurveyInboxQueryV1) throws {
        try query.validate()
        switch (query.target, self) {
        case let (.inboxItem(id), .inboxItem(value)):
            try value.validate()
            let actual: CaptureInboxItemV1
            switch value { case let .unassigned(item): actual = item; case let .promoted(p): actual = p.promotedItem }
            guard actual.workspaceID == query.workspaceID, actual.inboxItemID == id else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        case (.unassignedItems, let .inboxItems(values)):
            let ids = values.compactMap { value -> UUID? in
                guard case let .unassigned(item) = value else { return nil }; return item.inboxItemID
            }
            let canonical = values.sorted { left, right in
                guard case let .unassigned(lhs) = left, case let .unassigned(rhs) = right else { return false }
                return (lhs.temporalContext.recordedAtUTC, lhs.inboxItemID.uuidString)
                    < (rhs.temporalContext.recordedAtUTC, rhs.inboxItemID.uuidString)
            }
            guard values.count <= query.maximumResults, ids.count == values.count,
                  values == canonical, Set(ids).count == ids.count else {
                throw FastSurveyInboxFailureV1.duplicateIdentity
            }
            try values.forEach { try $0.validate() }
            guard values.allSatisfy({ if case let .unassigned(item) = $0 { return item.workspaceID == query.workspaceID }; return false }) else { throw FastSurveyInboxFailureV1.invalidPromotion }
        case let (.promotion(id), .promotion(value)):
            try value.validate(); guard value.promotion.workspaceID == query.workspaceID,
                value.promotion.promotionID == id else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        case let (.snippet(id), .snippet(value)):
            try value.validate(); guard value.workspaceID == query.workspaceID, value.snippetID == id else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        case let (.applicableSnippets(applicability), .snippets(values)):
            guard values.count <= query.maximumResults,
                  values == values.sorted(by: { ($0.editedAt, $0.snippetID.uuidString) < ($1.editedAt, $1.snippetID.uuidString) }),
                  Set(values.map(\.snippetID)).count == values.count else { throw FastSurveyInboxFailureV1.duplicateIdentity }
            try values.forEach { try $0.validate() }
            guard values.allSatisfy({ $0.workspaceID == query.workspaceID && $0.state == .active
                && ($0.applicability == applicability || $0.applicability.scope == .allLocalSurveys) }) else {
                throw FastSurveyInboxFailureV1.wrongWorkspace
            }
        case let (.snippetInsertion(id), .snippetInsertion(value)):
            try value.validate()
            guard value.insertion.workspaceID == query.workspaceID,
                  value.insertion.insertionEventID == id else { throw FastSurveyInboxFailureV1.wrongWorkspace }
        case let (.snippetInsertions(target), .snippetInsertions(values)):
            guard values.count <= query.maximumResults,
                  values == values.sorted(by: {
                      ($0.insertion.insertedAt, $0.insertion.insertionEventID.uuidString)
                          < ($1.insertion.insertedAt, $1.insertion.insertionEventID.uuidString)
                  }), Set(values.map { $0.insertion.insertionEventID }).count == values.count else {
                throw FastSurveyInboxFailureV1.duplicateIdentity
            }
            try values.forEach { try $0.validate() }
            guard values.allSatisfy({ $0.insertion.workspaceID == query.workspaceID && $0.insertion.target == target }) else {
                throw FastSurveyInboxFailureV1.wrongWorkspace
            }
        case let (_, .notFound(bound)): guard bound == query else { throw FastSurveyInboxFailureV1.receiptMismatch }
        default: throw FastSurveyInboxFailureV1.invalidValue
        }
    }
}

enum FastSurveyInboxRecoveryStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case effectCommittedAwaitingReceipt = "EFFECT_COMMITTED_AWAITING_RECEIPT"
    case receiptCommitted = "RECEIPT_COMMITTED"
}
struct FastSurveyInboxMutationReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let generationID: UUID
    let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256s: [String]
    let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64
    let recoveryState: FastSurveyInboxRecoveryStateV1; let committedAt: Date; let receiptSHA256: String
    init(receiptID: UUID, command: FastSurveyInboxMutationCommandV1, resultingWorkspaceRevision: UInt64,
         recoveryState: FastSurveyInboxRecoveryStateV1, committedAt: Date) throws {
        try command.validate(); schemaVersion = Self.schemaVersion; self.receiptID = receiptID
        workspaceID = command.workspaceID; generationID = command.expectedRevision.generationID
        mutationID = command.mutationID; commandSHA256 = command.commandSHA256
        semanticSHA256s = command.payload.semanticSHA256s
        priorWorkspaceRevision = command.expectedRevision.workspaceRevision
        self.resultingWorkspaceRevision = resultingWorkspaceRevision; self.recoveryState = recoveryState; self.committedAt = committedAt
        receiptSHA256 = try FastSurveyInboxValidationV1.sha256(Basis(schemaVersion: Self.schemaVersion,
            receiptID: receiptID, workspaceID: command.workspaceID, generationID: command.expectedRevision.generationID,
            mutationID: command.mutationID, commandSHA256: command.commandSHA256,
            semanticSHA256s: command.payload.semanticSHA256s,
            priorWorkspaceRevision: command.expectedRevision.workspaceRevision,
            resultingWorkspaceRevision: resultingWorkspaceRevision, recoveryState: recoveryState, committedAt: committedAt)); try validate(command: command)
    }
    func validate() throws {
        try FastSurveyInboxValidationV1.id(receiptID); try FastSurveyInboxValidationV1.id(generationID)
        try FastSurveyInboxValidationV1.digest(commandSHA256); try semanticSHA256s.forEach(FastSurveyInboxValidationV1.digest)
        try FastSurveyInboxValidationV1.instant(committedAt)
        let (next, overflow) = priorWorkspaceRevision.addingReportingOverflow(1)
        guard !overflow, schemaVersion == Self.schemaVersion, resultingWorkspaceRevision == next,
              !semanticSHA256s.isEmpty, semanticSHA256s == semanticSHA256s.sorted(),
              Set(semanticSHA256s).count == semanticSHA256s.count,
              receiptSHA256 == (try FastSurveyInboxValidationV1.sha256(basis)) else { throw FastSurveyInboxFailureV1.receiptMismatch }
    }
    func validate(command: FastSurveyInboxMutationCommandV1) throws {
        try validate(); try command.validate()
        guard workspaceID == command.workspaceID, generationID == command.expectedRevision.generationID,
              mutationID == command.mutationID, commandSHA256 == command.commandSHA256,
              semanticSHA256s == command.payload.semanticSHA256s,
              priorWorkspaceRevision == command.expectedRevision.workspaceRevision else { throw FastSurveyInboxFailureV1.receiptMismatch }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, receiptID: receiptID, workspaceID: workspaceID,
        generationID: generationID, mutationID: mutationID, commandSHA256: commandSHA256,
        semanticSHA256s: semanticSHA256s, priorWorkspaceRevision: priorWorkspaceRevision,
        resultingWorkspaceRevision: resultingWorkspaceRevision, recoveryState: recoveryState, committedAt: committedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let receiptID: UUID; let workspaceID: WorkspaceID; let generationID: UUID; let mutationID: MutationIDV1; let commandSHA256: String; let semanticSHA256s: [String]; let priorWorkspaceRevision: UInt64; let resultingWorkspaceRevision: UInt64; let recoveryState: FastSurveyInboxRecoveryStateV1; let committedAt: Date }
}

// MARK: - C23 ephemeral OCR review integration

/// Complete review closure for one OCR request. Every proposal is reviewed
/// exactly once before any accepted/edited field may reach a canonical writer.
/// This value is deliberately not persistence-enrolled.
struct FastSurveyInboxOCRReviewBatchV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let requestSHA256: String
    let evidence: [OCRProposalEvidenceV1]
    let reviews: [OCRFieldReviewV1]

    init(evidence: [OCRProposalEvidenceV1], reviews: [OCRFieldReviewV1]) throws {
        guard let first = evidence.first, !reviews.isEmpty else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        try evidence.forEach { try $0.validate() }
        let orderedEvidence = evidence.sorted { $0.proposal.proposalID.uuidString < $1.proposal.proposalID.uuidString }
        let orderedReviews = reviews.sorted { $0.proposalID.uuidString < $1.proposalID.uuidString }
        for (proposalEvidence, review) in zip(orderedEvidence, orderedReviews) {
            try review.validate(evidence: proposalEvidence)
        }
        guard Set(orderedEvidence.map { $0.proposal.proposalID }).count == orderedEvidence.count,
              Set(orderedReviews.map(\.proposalID)).count == orderedReviews.count,
              orderedEvidence.map({ $0.proposal.proposalID }) == orderedReviews.map(\.proposalID),
              orderedEvidence.allSatisfy({ $0.request == first.request }),
              zip(orderedEvidence, orderedReviews).allSatisfy({ pair in
                  pair.1.evidenceSHA256 == pair.0.evidenceSHA256 &&
                  pair.1.reviewedBy.workspaceID == first.request.workspaceID
              }) else { throw FastSurveyInboxFailureV1.invalidValue }
        workspaceID = first.request.workspaceID
        requestSHA256 = first.request.requestSHA256
        self.evidence = orderedEvidence
        self.reviews = orderedReviews
    }

    func reviewedProposal(at index: Int) throws -> AssistanceProposalV1? {
        guard evidence.indices.contains(index), reviews.indices.contains(index) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        let source = evidence[index].proposal
        let review = reviews[index]
        guard review.evidenceSHA256 == evidence[index].evidenceSHA256,
              review.proposalID == source.proposalID else {
            throw FastSurveyInboxFailureV1.staleRevision
        }
        guard let value = review.reviewedValue else { return nil }
        if review.disposition == .accepted, value != source.value {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        return try source.correctedForOCR(
            proposalID: source.proposalID, value: value,
            createdAt: source.createdAt, expiresAt: source.expiresAt
        )
    }

    static let isPersistent = false
    static let customWordsAreIdentity = false
    static let rejectedOrUnreviewedFieldsAreCanonical = false
}

enum FastSurveyInboxOCRReviewOutcomeV1: Equatable, Sendable {
    case reviewed(receipts: [AssistanceAcceptanceReceiptV1], rejectedProposalIDs: [UUID])
}

enum AssistedCaptureProposalV1: Equatable, Sendable {
    case dictation(OnDeviceDictationProposalV1)
    case location(OneShotLocationProposalV1)

    var proposal: AssistanceProposalV1 { switch self { case .dictation(let v): return v.proposal; case .location(let v): return v.proposal } }
    var evidenceSHA256: String { switch self { case .dictation(let v): return v.proposalEvidenceSHA256; case .location(let v): return v.proposalEvidenceSHA256 } }
    func validate(policy: DictationLocationCapabilityPolicyV1) throws {
        switch self { case .dictation(let value): try value.validate(policy: policy); case .location(let value): try value.validate(policy: policy) }
    }
}

struct AssistedCaptureFieldReviewV1: Equatable, Sendable {
    let source: AssistedCaptureProposalV1
    let review: DictationLocationProposalReviewV1
    var disposition:DictationLocationReviewDispositionV1{review.disposition}
    var reviewedValue:ResponseValueV1?{review.reviewedValue}
    var reviewedBy:ActorSnapshotV1{review.reviewedBy}
    var reviewedAt:Date{review.reviewedAt}

    init(source: AssistedCaptureProposalV1, review:DictationLocationProposalReviewV1,
         policy: DictationLocationCapabilityPolicyV1) throws {
        try source.validate(policy: policy)
        let original = source.proposal
        try review.validate(originalProposalID:original.proposalID,
            evidenceSHA256:source.evidenceSHA256,originalValue:original.value)
        guard review.reviewedBy.workspaceID == original.target.workspaceID,
              review.reviewedBy.responsibility == .reviewedBy,
              review.reviewedAt >= original.createdAt, review.reviewedAt < original.expiresAt else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        self.source=source;self.review=review
    }

    func canonicalProposal() throws -> AssistanceProposalV1? {
        guard let reviewedValue=review.reviewedValue else { return nil }
        let original = source.proposal
        return try original.correctedForOCR(proposalID: original.proposalID, value: reviewedValue,
            createdAt: original.createdAt, expiresAt: original.expiresAt)
    }
}

struct AssistedCaptureReviewBatchV1: Equatable, Sendable {
    let workspaceID: WorkspaceID
    let reviews: [AssistedCaptureFieldReviewV1]
    init(reviews: [AssistedCaptureFieldReviewV1]) throws {
        guard let first=reviews.first,!reviews.isEmpty,
              Set(reviews.map{$0.source.proposal.proposalID}).count==reviews.count,
              reviews.allSatisfy({$0.source.proposal.target.workspaceID==first.source.proposal.target.workspaceID}) else {
            throw FastSurveyInboxFailureV1.invalidValue
        }
        workspaceID=first.source.proposal.target.workspaceID
        self.reviews=reviews.sorted{$0.source.proposal.proposalID.uuidString<$1.source.proposal.proposalID.uuidString}
    }
    static let isPersistent=false
    static let authorizationCreatesIdentityOrDirectionTruth=false
}

struct FastSurveyInboxStoragePressureV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let currentBytes: Int64; let proposedAdditionalBytes: Int64
    let maximumBytes: Int64; let admitsCapture: Bool
    init(workspaceID: WorkspaceID, currentBytes: Int64, proposedAdditionalBytes: Int64) throws {
        guard currentBytes >= 0, proposedAdditionalBytes >= 0 else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
        let (total, overflow) = currentBytes.addingReportingOverflow(proposedAdditionalBytes)
        guard !overflow else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
        self.workspaceID = workspaceID; self.currentBytes = currentBytes
        self.proposedAdditionalBytes = proposedAdditionalBytes
        maximumBytes = FastSurveyInboxLimitsV1.maximumWorkspaceInboxBytes
        admitsCapture = total <= maximumBytes
    }
    func validate() throws {
        guard currentBytes >= 0, proposedAdditionalBytes >= 0 else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
        let (total, overflow) = currentBytes.addingReportingOverflow(proposedAdditionalBytes)
        guard !overflow else { throw FastSurveyInboxFailureV1.arithmeticOverflow }
        guard maximumBytes == FastSurveyInboxLimitsV1.maximumWorkspaceInboxBytes,
              admitsCapture == (total <= maximumBytes) else { throw FastSurveyInboxFailureV1.invalidValue }
    }
    func requireAdmission() throws {
        try validate()
        guard admitsCapture else { throw FastSurveyInboxFailureV1.storagePressure }
    }
}
