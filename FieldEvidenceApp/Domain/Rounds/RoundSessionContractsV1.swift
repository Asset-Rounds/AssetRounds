import Foundation

enum RoundSessionFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, limitExceeded, digestMismatch
    case staleRevision, illegalTransition, itemMismatch, authorityMismatch, incompleteCloseout
}

enum RoundSessionLimitsV1 {
    static let maximumItems = 512
    static let maximumHistoryRevisions = 16_384
    static let maximumRequiredContent = 256
    static let maximumLabelBytes = 512
    static let maximumCanonicalBytes = 8 * 1_024 * 1_024
}

private let roundSessionNilUUIDV1 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

enum RoundSessionStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case draft = "DRAFT", active = "ACTIVE", paused = "PAUSED"
    case completed = "COMPLETED", archived = "ARCHIVED"
}

enum RoundSessionTransitionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case create = "CREATE", reviseSelection = "REVISE_SELECTION", start = "START"
    case visitItem = "VISIT_ITEM", completeItem = "COMPLETE_ITEM"
    case markInaccessible = "MARK_INACCESSIBLE", skipItem = "SKIP_ITEM"
    case deferItem = "DEFER_ITEM", retryItem = "RETRY_ITEM"
    case pause = "PAUSE", resume = "RESUME", close = "CLOSE", archive = "ARCHIVE"
}

enum RoundItemDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case pending = "PENDING", visited = "VISITED", completed = "COMPLETED"
    case inaccessible = "INACCESSIBLE", skipped = "SKIPPED", deferred = "DEFERRED"
    var isTerminal: Bool { self == .completed || self == .inaccessible || self == .skipped || self == .deferred }
}

enum RoundItemReasonV1: String, Codable, CaseIterable, Hashable, Sendable {
    case physicalAccessUnavailable = "PHYSICAL_ACCESS_UNAVAILABLE"
    case permissionUnavailable = "PERMISSION_UNAVAILABLE"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case requiredPackageUnavailable = "REQUIRED_PACKAGE_UNAVAILABLE"
    case requiredContentUnavailable = "REQUIRED_CONTENT_UNAVAILABLE"
    case assetDeletedDuringSession = "ASSET_DELETED_DURING_SESSION"
    case assetRetiredOrReplaced = "ASSET_RETIRED_OR_REPLACED"
    case explicitlyOutOfScope = "EXPLICITLY_OUT_OF_SCOPE"
    case duplicateSelection = "DUPLICATE_SELECTION"
    case notRequired = "NOT_REQUIRED"
    case userDeferred = "USER_DEFERRED"
    case interruption = "INTERRUPTION"
    case followUpRequired = "FOLLOW_UP_REQUIRED"

    func isAllowed(for disposition: RoundItemDispositionV1) -> Bool {
        switch disposition {
        case .inaccessible:
            return [.physicalAccessUnavailable, .permissionUnavailable, .protectedDataUnavailable,
                    .requiredPackageUnavailable, .requiredContentUnavailable, .assetDeletedDuringSession,
                    .assetRetiredOrReplaced].contains(self)
        case .skipped:
            return [.explicitlyOutOfScope, .duplicateSelection, .notRequired].contains(self)
        case .deferred:
            return [.userDeferred, .interruption, .requiredContentUnavailable,
                    .protectedDataUnavailable, .followUpRequired].contains(self)
        default: return false
        }
    }
}

struct RoundSessionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let sessionID: UUID
    let revision: UInt64
    let sessionSHA256: String

    init(workspaceID: WorkspaceID, sessionID: UUID, revision: UInt64, sessionSHA256: String) throws {
        guard sessionID != roundSessionNilUUIDV1, revision > 0,
              KernelCanonicalHashV1.validSHA256(sessionSHA256) else { throw RoundSessionFailureV1.invalidValue }
        self.workspaceID = workspaceID; self.sessionID = sessionID
        self.revision = revision; self.sessionSHA256 = sessionSHA256
    }
    func validate() throws { _ = try Self(workspaceID: workspaceID, sessionID: sessionID, revision: revision, sessionSHA256: sessionSHA256) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case workspaceID, sessionID, revision, sessionSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(workspaceID: c.decode(WorkspaceID.self, forKey: .workspaceID), sessionID: c.decode(UUID.self, forKey: .sessionID), revision: c.decode(UInt64.self, forKey: .revision), sessionSHA256: c.decode(String.self, forKey: .sessionSHA256))
    }
}

struct RoundPackageReleaseReferenceV1: Codable, Equatable, Hashable, Sendable {
    let packageReleaseID: String; let packageID: String; let packageContentVersion: Int
    let packageSHA256: String; let workflowSHA256: String

    init(_ release: InspectionPackageReleaseV1) throws {
        try release.validate(); guard release.state == .published else { throw RoundSessionFailureV1.authorityMismatch }
        packageReleaseID = release.packageReleaseID; packageID = release.packageID
        packageContentVersion = release.packageContentVersion; packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256; try validate()
    }
    init(packageReleaseID: String, packageID: String, packageContentVersion: Int, packageSHA256: String, workflowSHA256: String) throws {
        self.packageReleaseID = packageReleaseID; self.packageID = packageID; self.packageContentVersion = packageContentVersion
        self.packageSHA256 = packageSHA256; self.workflowSHA256 = workflowSHA256; try validate()
    }
    func validate() throws {
        guard KernelCanonicalHashV1.validSHA256(packageReleaseID), WorkflowGrammarValidationV1.validID(packageID),
              packageContentVersion > 0, KernelCanonicalHashV1.validSHA256(packageSHA256),
              KernelCanonicalHashV1.validSHA256(workflowSHA256) else { throw RoundSessionFailureV1.invalidValue }
    }
    func validate(against release: InspectionPackageReleaseV1) throws {
        try release.validate(); guard release.state == .published, self == (try Self(release)) else { throw RoundSessionFailureV1.authorityMismatch }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case packageReleaseID, packageID, packageContentVersion, packageSHA256, workflowSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(packageReleaseID: c.decode(String.self, forKey: .packageReleaseID), packageID: c.decode(String.self, forKey: .packageID), packageContentVersion: c.decode(Int.self, forKey: .packageContentVersion), packageSHA256: c.decode(String.self, forKey: .packageSHA256), workflowSHA256: c.decode(String.self, forKey: .workflowSHA256))
    }
}

struct RoundPackageContentRequirementV1: Codable, Equatable, Hashable, Sendable {
    let packageRelease: RoundPackageReleaseReferenceV1
    let requiredContent: [ContentReferenceV1]
    let requirementSHA256: String

    init(packageRelease: RoundPackageReleaseReferenceV1, requiredContent: [ContentReferenceV1]) throws {
        try packageRelease.validate()
        guard requiredContent.count <= RoundSessionLimitsV1.maximumRequiredContent,
              requiredContent == requiredContent.sorted(by: { $0.id < $1.id }),
              Set(requiredContent.map(\.id)).count == requiredContent.count else { throw RoundSessionFailureV1.limitExceeded }
        self.packageRelease = packageRelease; self.requiredContent = requiredContent
        requirementSHA256 = try RoundSessionCanonicalCodecV1.sha256(Basis(packageRelease: packageRelease, requiredContent: requiredContent))
        try validate()
    }
    func validate() throws {
        try packageRelease.validate()
        guard requiredContent.count <= RoundSessionLimitsV1.maximumRequiredContent,
              requiredContent == requiredContent.sorted(by: { $0.id < $1.id }),
              Set(requiredContent.map(\.id)).count == requiredContent.count,
              requirementSHA256 == (try RoundSessionCanonicalCodecV1.sha256(Basis(packageRelease: packageRelease, requiredContent: requiredContent))) else { throw RoundSessionFailureV1.digestMismatch }
    }
    private struct Basis: Codable { let packageRelease: RoundPackageReleaseReferenceV1; let requiredContent: [ContentReferenceV1] }
    private enum CodingKeys: String, CodingKey, CaseIterable { case packageRelease, requiredContent, requirementSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        packageRelease = try c.decode(RoundPackageReleaseReferenceV1.self, forKey: .packageRelease)
        requiredContent = try c.decode([ContentReferenceV1].self, forKey: .requiredContent)
        requirementSHA256 = try c.decode(String.self, forKey: .requirementSHA256); try validate()
    }
}

struct RoundAssetSelectionV1: Codable, Equatable, Hashable, Sendable {
    let assetID: UUID; let siteID: UUID; let labelAtSelection: String
    init(assetID: UUID, siteID: UUID, labelAtSelection: String) throws {
        guard assetID != roundSessionNilUUIDV1, siteID != roundSessionNilUUIDV1,
              !labelAtSelection.isEmpty, labelAtSelection == labelAtSelection.trimmingCharacters(in: .whitespacesAndNewlines),
              labelAtSelection == labelAtSelection.precomposedStringWithCanonicalMapping,
              labelAtSelection.utf8.count <= RoundSessionLimitsV1.maximumLabelBytes else { throw RoundSessionFailureV1.invalidValue }
        self.assetID = assetID; self.siteID = siteID; self.labelAtSelection = labelAtSelection
    }
    func validate() throws { _ = try Self(assetID: assetID, siteID: siteID, labelAtSelection: labelAtSelection) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case assetID, siteID, labelAtSelection }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(assetID: c.decode(UUID.self, forKey: .assetID), siteID: c.decode(UUID.self, forKey: .siteID), labelAtSelection: c.decode(String.self, forKey: .labelAtSelection))
    }
}

struct RoundItemVisitV1: Codable, Equatable, Hashable, Sendable {
    let visitedAt: Date; let recordedBy: ActorSnapshotV1
    init(visitedAt: Date, recordedBy: ActorSnapshotV1) throws {
        try recordedBy.validate(); guard visitedAt.timeIntervalSinceReferenceDate.isFinite,
              visitedAt >= recordedBy.capturedAt else { throw RoundSessionFailureV1.invalidValue }
        self.visitedAt = visitedAt; self.recordedBy = recordedBy
    }
    func validate(workspaceID: WorkspaceID) throws { try recordedBy.validate(); guard recordedBy.workspaceID == workspaceID, visitedAt >= recordedBy.capturedAt else { throw RoundSessionFailureV1.authorityMismatch } }
    private enum CodingKeys: String, CodingKey, CaseIterable { case visitedAt, recordedBy }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(visitedAt: c.decode(Date.self, forKey: .visitedAt), recordedBy: c.decode(ActorSnapshotV1.self, forKey: .recordedBy))
    }
}

struct RoundItemCompletionReferenceV1: Codable, Equatable, Hashable, Sendable {
    let completionID: UUID; let revision: UInt64; let completionSHA256: String
    init(completionID: UUID, revision: UInt64, completionSHA256: String) throws {
        guard completionID != roundSessionNilUUIDV1, revision > 0, KernelCanonicalHashV1.validSHA256(completionSHA256) else { throw RoundSessionFailureV1.invalidValue }
        self.completionID = completionID; self.revision = revision; self.completionSHA256 = completionSHA256
    }
    func validate() throws { _ = try Self(completionID: completionID, revision: revision, completionSHA256: completionSHA256) }
    private enum CodingKeys: String, CodingKey, CaseIterable { case completionID, revision, completionSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(completionID: c.decode(UUID.self, forKey: .completionID), revision: c.decode(UInt64.self, forKey: .revision), completionSHA256: c.decode(String.self, forKey: .completionSHA256))
    }
}

struct RoundItemV1: Codable, Equatable, Sendable {
    let itemID: UUID; let order: Int; let selection: RoundAssetSelectionV1
    let requirement: RoundPackageContentRequirementV1
    let disposition: RoundItemDispositionV1; let visit: RoundItemVisitV1?
    let reason: RoundItemReasonV1?; let completion: RoundItemCompletionReferenceV1?

    init(itemID: UUID, order: Int, selection: RoundAssetSelectionV1,
         requirement: RoundPackageContentRequirementV1, disposition: RoundItemDispositionV1 = .pending,
         visit: RoundItemVisitV1? = nil, reason: RoundItemReasonV1? = nil,
         completion: RoundItemCompletionReferenceV1? = nil) throws {
        self.itemID = itemID; self.order = order; self.selection = selection; self.requirement = requirement
        self.disposition = disposition; self.visit = visit; self.reason = reason; self.completion = completion
        try validateIntrinsic()
    }
    func validateIntrinsic() throws {
        try selection.validate(); try requirement.validate(); try completion?.validate()
        guard itemID != roundSessionNilUUIDV1, order >= 0 else { throw RoundSessionFailureV1.invalidValue }
        switch disposition {
        case .pending: guard visit == nil, reason == nil, completion == nil else { throw RoundSessionFailureV1.itemMismatch }
        case .visited: guard visit != nil, reason == nil, completion == nil else { throw RoundSessionFailureV1.itemMismatch }
        case .completed: guard visit != nil, reason == nil, completion != nil else { throw RoundSessionFailureV1.itemMismatch }
        case .inaccessible, .skipped, .deferred:
            guard let reason, reason.isAllowed(for: disposition), completion == nil else { throw RoundSessionFailureV1.itemMismatch }
        }
    }
    func validate(workspaceID: WorkspaceID) throws {
        try validateIntrinsic(); try visit?.validate(workspaceID: workspaceID)
        guard requirement.requiredContent.allSatisfy({ $0.workspaceID == workspaceID.rawValue.uuidString.lowercased() }) else { throw RoundSessionFailureV1.authorityMismatch }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case itemID, order, selection, requirement, disposition, visit, reason, completion }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(itemID: c.decode(UUID.self, forKey: .itemID), order: c.decode(Int.self, forKey: .order), selection: c.decode(RoundAssetSelectionV1.self, forKey: .selection), requirement: c.decode(RoundPackageContentRequirementV1.self, forKey: .requirement), disposition: c.decode(RoundItemDispositionV1.self, forKey: .disposition), visit: c.decodeIfPresent(RoundItemVisitV1.self, forKey: .visit), reason: c.decodeIfPresent(RoundItemReasonV1.self, forKey: .reason), completion: c.decodeIfPresent(RoundItemCompletionReferenceV1.self, forKey: .completion))
    }
}

struct RoundSessionCountsV1: Codable, Equatable, Hashable, Sendable {
    let expected: Int; let visited: Int; let completed: Int
    let inaccessible: Int; let skipped: Int; let deferred: Int; let undispositioned: Int
    init(items: [RoundItemV1]) {
        expected = items.count; visited = items.filter { $0.visit != nil }.count
        completed = items.filter { $0.disposition == .completed }.count
        inaccessible = items.filter { $0.disposition == .inaccessible }.count
        skipped = items.filter { $0.disposition == .skipped }.count
        deferred = items.filter { $0.disposition == .deferred }.count
        undispositioned = items.filter { !$0.disposition.isTerminal }.count
    }
    func validate(items: [RoundItemV1]) throws { guard self == Self(items: items), expected == completed + inaccessible + skipped + deferred + undispositioned else { throw RoundSessionFailureV1.itemMismatch } }
    private enum CodingKeys: String, CodingKey, CaseIterable { case expected, visited, completed, inaccessible, skipped, deferred, undispositioned }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
        expected = try c.decode(Int.self, forKey: .expected); visited = try c.decode(Int.self, forKey: .visited); completed = try c.decode(Int.self, forKey: .completed); inaccessible = try c.decode(Int.self, forKey: .inaccessible); skipped = try c.decode(Int.self, forKey: .skipped); deferred = try c.decode(Int.self, forKey: .deferred); undispositioned = try c.decode(Int.self, forKey: .undispositioned)
        guard [expected, visited, completed, inaccessible, skipped, deferred, undispositioned].allSatisfy({ $0 >= 0 }) else { throw RoundSessionFailureV1.invalidValue }
    }
}

struct RoundSessionV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1; static let persistentKind = "ROUND_SESSION_V1"
    let schemaVersion: Int; let persistentKind: String
    let workspaceID: WorkspaceID; let sessionID: UUID; let revision: UInt64
    let predecessor: RoundSessionReferenceV1?; let mutationID: MutationIDV1
    let state: RoundSessionStateV1; let transition: RoundSessionTransitionV1
    let transitionItemID: UUID?; let items: [RoundItemV1]; let counts: RoundSessionCountsV1
    let recordedBy: ActorSnapshotV1; let recordedAt: Date; let sessionSHA256: String

    var reference: RoundSessionReferenceV1 { get throws { try .init(workspaceID: workspaceID, sessionID: sessionID, revision: revision, sessionSHA256: sessionSHA256) } }
    init(workspaceID: WorkspaceID, sessionID: UUID, predecessor: RoundSessionV1? = nil,
         revision: UInt64, mutationID: MutationIDV1, state: RoundSessionStateV1,
         transition: RoundSessionTransitionV1, transitionItemID: UUID? = nil,
         items: [RoundItemV1], recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; persistentKind = Self.persistentKind
        self.workspaceID = workspaceID; self.sessionID = sessionID; self.revision = revision
        self.predecessor = try predecessor?.reference; self.mutationID = mutationID; self.state = state
        self.transition = transition; self.transitionItemID = transitionItemID; self.items = items
        counts = .init(items: items); self.recordedBy = recordedBy; self.recordedAt = recordedAt
        sessionSHA256 = try RoundSessionCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, persistentKind: Self.persistentKind, workspaceID: workspaceID, sessionID: sessionID, revision: revision, predecessor: try predecessor?.reference, mutationID: mutationID, state: state, transition: transition, transitionItemID: transitionItemID, items: items, counts: counts, recordedBy: recordedBy, recordedAt: recordedAt))
        try validateIntrinsic()
    }
    func validateIntrinsic() throws {
        try predecessor?.validate(); try recordedBy.validate(); try counts.validate(items: items)
        let completionIDs = items.compactMap { $0.completion?.completionID }
        guard schemaVersion == Self.schemaVersion, persistentKind == Self.persistentKind,
              workspaceID == recordedBy.workspaceID, sessionID != roundSessionNilUUIDV1,
              revision > 0, (predecessor == nil) == (revision == 1),
              predecessor.map({ $0.workspaceID == workspaceID && $0.sessionID == sessionID && $0.revision < UInt64.max && $0.revision + 1 == revision }) ?? true,
              items.count > 0, items.count <= RoundSessionLimitsV1.maximumItems,
              items.map(\.order) == Array(0..<items.count), Set(items.map(\.itemID)).count == items.count,
              Set(items.map { $0.selection.assetID }).count == items.count,
              Set(completionIDs).count == completionIDs.count,
              recordedAt.timeIntervalSinceReferenceDate.isFinite, recordedAt >= recordedBy.capturedAt,
              sessionSHA256 == (try RoundSessionCanonicalCodecV1.sha256(basis)) else { throw RoundSessionFailureV1.digestMismatch }
        try items.forEach { try $0.validate(workspaceID: workspaceID) }
        if revision == 1 { guard transition == .create, state == .draft, transitionItemID == nil, items.allSatisfy({ $0.disposition == .pending }) else { throw RoundSessionFailureV1.illegalTransition } }
        if state == .draft { guard items.allSatisfy({ $0.disposition == .pending }) else { throw RoundSessionFailureV1.illegalTransition } }
        if transition.requiresItem { guard transitionItemID != nil else { throw RoundSessionFailureV1.illegalTransition } }
        else { guard transitionItemID == nil else { throw RoundSessionFailureV1.illegalTransition } }
        if state == .completed || state == .archived { guard counts.undispositioned == 0 else { throw RoundSessionFailureV1.incompleteCloseout } }
    }
    func validateSuccessor(of prior: Self) throws {
        try prior.validateIntrinsic(); try validateIntrinsic()
        guard predecessor == (try prior.reference), workspaceID == prior.workspaceID, sessionID == prior.sessionID,
              prior.revision < UInt64.max, revision == prior.revision + 1,
              mutationID != prior.mutationID, recordedAt >= prior.recordedAt,
              Self.allowed(transition: transition, from: prior.state, to: state) else { throw RoundSessionFailureV1.staleRevision }
        switch transition {
        case .reviseSelection:
            guard state == .draft else { throw RoundSessionFailureV1.illegalTransition }
        case .start, .pause, .resume, .close, .archive:
            guard items == prior.items else { throw RoundSessionFailureV1.itemMismatch }
        case .visitItem, .completeItem, .markInaccessible, .skipItem, .deferItem, .retryItem:
            try validateSingleItemSuccessor(of: prior)
        case .create: throw RoundSessionFailureV1.illegalTransition
        }
        if prior.state != .draft { guard items.map(\.itemID) == prior.items.map(\.itemID), items.map(\.order) == prior.items.map(\.order), items.map(\.selection) == prior.items.map(\.selection), items.map(\.requirement) == prior.items.map(\.requirement) else { throw RoundSessionFailureV1.itemMismatch } }
        if transition == .close { guard counts.undispositioned == 0 else { throw RoundSessionFailureV1.incompleteCloseout } }
    }
    func rebindingWorkspaceID(_ target: WorkspaceID, rebasedPredecessor: RoundSessionV1?, recordedBy: ActorSnapshotV1, visitActors: [UUID: ActorSnapshotV1]) throws -> Self {
        try validateIntrinsic(); guard recordedBy.workspaceID == target,
              (revision == 1 && rebasedPredecessor == nil) || (rebasedPredecessor?.workspaceID == target && rebasedPredecessor?.sessionID == sessionID && rebasedPredecessor.map({ $0.revision < UInt64.max && $0.revision + 1 == revision }) == true) else { throw RoundSessionFailureV1.staleRevision }
        let reboundItems = try items.map { item -> RoundItemV1 in
            var visit: RoundItemVisitV1?
            if let old = item.visit { guard let actor = visitActors[old.recordedBy.snapshotID], actor.workspaceID == target else { throw RoundSessionFailureV1.authorityMismatch }; visit = try .init(visitedAt: old.visitedAt, recordedBy: actor) } else { visit = nil }
            let refs = try item.requirement.requiredContent.map { ref in
                try ContentReferenceV1(workspaceID: target.rawValue.uuidString.lowercased(), contentID: ref.contentID, byteLength: ref.byteLength, mediaType: ref.mediaType, digests: ref.digests, byteRole: ref.byteRole, createdAt: ref.createdAt)
            }
            return try RoundItemV1(itemID: item.itemID, order: item.order, selection: item.selection, requirement: .init(packageRelease: item.requirement.packageRelease, requiredContent: refs), disposition: item.disposition, visit: visit, reason: item.reason, completion: item.completion)
        }
        return try Self(workspaceID: target, sessionID: sessionID, predecessor: rebasedPredecessor, revision: revision, mutationID: mutationID, state: state, transition: transition, transitionItemID: transitionItemID, items: reboundItems, recordedBy: recordedBy, recordedAt: recordedAt)
    }
    private func validateSingleItemSuccessor(of prior: Self) throws {
        guard items.count == prior.items.count, let id = transitionItemID, let index = items.firstIndex(where: { $0.itemID == id }),
              prior.items[index].itemID == id, items.enumerated().allSatisfy({ $0.offset == index || $0.element == prior.items[$0.offset] }) else { throw RoundSessionFailureV1.itemMismatch }
        let old = prior.items[index], new = items[index]
        switch transition {
        case .visitItem: guard old.disposition == .pending, new.disposition == .visited, new.visit != nil else { throw RoundSessionFailureV1.illegalTransition }
        case .completeItem: guard old.disposition == .visited, new.disposition == .completed, new.visit == old.visit, new.completion != nil else { throw RoundSessionFailureV1.illegalTransition }
        case .markInaccessible: guard [.pending, .visited].contains(old.disposition), new.disposition == .inaccessible, new.visit == old.visit else { throw RoundSessionFailureV1.illegalTransition }
        case .skipItem: guard [.pending, .visited].contains(old.disposition), new.disposition == .skipped, new.visit == old.visit else { throw RoundSessionFailureV1.illegalTransition }
        case .deferItem: guard [.pending, .visited].contains(old.disposition), new.disposition == .deferred, new.visit == old.visit else { throw RoundSessionFailureV1.illegalTransition }
        case .retryItem: guard [.inaccessible, .deferred].contains(old.disposition), new.disposition == (old.visit == nil ? .pending : .visited), new.visit == old.visit else { throw RoundSessionFailureV1.illegalTransition }
        default: throw RoundSessionFailureV1.illegalTransition
        }
    }
    private static func allowed(transition: RoundSessionTransitionV1, from: RoundSessionStateV1, to: RoundSessionStateV1) -> Bool {
        switch transition {
        case .create: return false
        case .reviseSelection: return from == .draft && to == .draft
        case .start: return from == .draft && to == .active
        case .visitItem, .completeItem, .markInaccessible, .skipItem, .deferItem, .retryItem: return from == .active && to == .active
        case .pause: return from == .active && to == .paused
        case .resume: return from == .paused && to == .active
        case .close: return from == .active && to == .completed
        case .archive: return from == .completed && to == .archived
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, persistentKind: persistentKind, workspaceID: workspaceID, sessionID: sessionID, revision: revision, predecessor: predecessor, mutationID: mutationID, state: state, transition: transition, transitionItemID: transitionItemID, items: items, counts: counts, recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let persistentKind: String; let workspaceID: WorkspaceID; let sessionID: UUID; let revision: UInt64; let predecessor: RoundSessionReferenceV1?; let mutationID: MutationIDV1; let state: RoundSessionStateV1; let transition: RoundSessionTransitionV1; let transitionItemID: UUID?; let items: [RoundItemV1]; let counts: RoundSessionCountsV1; let recordedBy: ActorSnapshotV1; let recordedAt: Date }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, persistentKind, workspaceID, sessionID, revision, predecessor, mutationID, state, transition, transitionItemID, items, counts, recordedBy, recordedAt, sessionSHA256 }
    init(from decoder: Decoder) throws {
        try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion); persistentKind = try c.decode(String.self, forKey: .persistentKind); workspaceID = try c.decode(WorkspaceID.self, forKey: .workspaceID); sessionID = try c.decode(UUID.self, forKey: .sessionID); revision = try c.decode(UInt64.self, forKey: .revision); predecessor = try c.decodeIfPresent(RoundSessionReferenceV1.self, forKey: .predecessor); mutationID = try c.decode(MutationIDV1.self, forKey: .mutationID); state = try c.decode(RoundSessionStateV1.self, forKey: .state); transition = try c.decode(RoundSessionTransitionV1.self, forKey: .transition); transitionItemID = try c.decodeIfPresent(UUID.self, forKey: .transitionItemID); items = try c.decode([RoundItemV1].self, forKey: .items); counts = try c.decode(RoundSessionCountsV1.self, forKey: .counts); recordedBy = try c.decode(ActorSnapshotV1.self, forKey: .recordedBy); recordedAt = try c.decode(Date.self, forKey: .recordedAt); sessionSHA256 = try c.decode(String.self, forKey: .sessionSHA256); try validateIntrinsic()
    }
}

extension RoundSessionV1 {
    /// C21 consumes only the existing immutable selection carried by round
    /// items.  It is a deterministic view, not another round-selection row.
    var selectedAssets: [RoundAssetSelectionV1] {
        items.map(\.selection).sorted { lhs, rhs in
            lhs.assetID.uuidString < rhs.assetID.uuidString
        }
    }
}

/// Binds C21's explicit start to the existing append-only round successor.
/// The workflow contributes no second receipt, occurrence, or selection store.
enum C21RoundSessionStartBoundaryV1 {
    static func validate(_ request: ScanToWorkStartRequestV1) throws {
        try request.flow.validateIntrinsic()
        try request.policy.validateIntrinsic()
        try request.roundMutation.validate()
        guard let predecessor = request.roundMutation.session.predecessor,
              request.explicitUserConfirmation,
              request.policy.startAllowed,
              request.flow.preview.outcome == .ready,
              let asset = request.flow.preview.asset,
              request.roundMutation.workspaceID == asset.workspaceID,
              request.roundMutation.expectedRevision == asset.readiness.session.revision,
              request.roundMutation.session.sessionID == asset.readiness.session.sessionID,
              predecessor == asset.readiness.session,
              request.roundMutation.session.transition == .start,
              request.roundMutation.session.selectedAssets.contains(where: {
                  $0.assetID == asset.assetID && $0.siteID == asset.siteID
              }) else {
            throw ScanToWorkFailureV1.notReady
        }
    }
}

enum C21RoundSessionCheckpointBoundaryV1 {
    static func validate(_ request: RepetitiveCaptureCheckpointRequestV1) throws {
        let exact = try RepetitiveCaptureCheckpointRequestV1(
            plan: request.plan,
            assetID: request.assetID,
            disposition: request.disposition,
            requirementFocus: request.requirementFocus,
            resumeAnchor: request.resumeAnchor,
            roundMutation: request.roundMutation
        )
        guard exact == request else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }
}

private extension RoundSessionTransitionV1 { var requiresItem: Bool { [.visitItem, .completeItem, .markInaccessible, .skipItem, .deferItem, .retryItem].contains(self) } }

enum RoundSessionHistoryValidatorV1 {
    static func validate(_ history: [RoundSessionV1], workspaceID: WorkspaceID, sessionID: UUID) throws -> RoundSessionV1? {
        guard history.count <= RoundSessionLimitsV1.maximumHistoryRevisions,
              history == history.sorted(by: { $0.revision < $1.revision }),
              Set(history.map(\.revision)).count == history.count,
              Set(history.map(\.mutationID)).count == history.count,
              Set(history.map(\.sessionSHA256)).count == history.count else { throw RoundSessionFailureV1.staleRevision }
        for (index, value) in history.enumerated() {
            try value.validateIntrinsic()
            guard value.workspaceID == workspaceID, value.sessionID == sessionID,
                  value.revision == UInt64(index + 1) else { throw RoundSessionFailureV1.staleRevision }
            if index == 0 { guard value.predecessor == nil else { throw RoundSessionFailureV1.staleRevision } }
            else { try value.validateSuccessor(of: history[index - 1]) }
        }
        return history.last
    }
}

/// C22 binds a recurring occurrence start to one already-materialized
/// round-session frontier or one exact work-packet manifest.  It owns no
/// mutation: the sole Schedule `.startOccurrence` mutation remains the
/// effect/receipt authority.
enum RecurringRoundStartFrontierBoundaryV1 {
    static func validate(
        request: RecurringRoundStartRequestV1,
        currentRoundSession: RoundSessionV1? = nil,
        exactWorkPacket: WorkPacketManifestV1? = nil
    ) throws {
        try request.validate()
        guard let workInstance = request.event.workInstance else {
            throw RoundSessionFailureV1.authorityMismatch
        }
        switch workInstance {
        case let .roundSession(sessionID, revision, sessionSHA256):
            guard exactWorkPacket == nil,
                  let currentRoundSession,
                  currentRoundSession.workspaceID == request.event.workspaceID,
                  currentRoundSession.sessionID == sessionID,
                  currentRoundSession.revision == revision,
                  currentRoundSession.sessionSHA256 == sessionSHA256,
                  currentRoundSession.state == .active else {
                throw RoundSessionFailureV1.authorityMismatch
            }
        case let .workPacket(reference):
            guard currentRoundSession == nil,
                  let exactWorkPacket,
                  exactWorkPacket.workspaceID == request.event.workspaceID,
                  try WorkPacketManifestReferenceV1(exactWorkPacket) == reference else {
                throw RoundSessionFailureV1.authorityMismatch
            }
        }
    }
}

enum RoundSessionCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; e.dateEncodingStrategy = .millisecondsSince1970
        let data = try e.encode(value); guard data.count <= RoundSessionLimitsV1.maximumCanonicalBytes else { throw RoundSessionFailureV1.limitExceeded }; return data
    }
    static func decode<T: Decodable & Encodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= RoundSessionLimitsV1.maximumCanonicalBytes else { throw RoundSessionFailureV1.limitExceeded }
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; let value = try d.decode(type, from: data)
        guard try encode(value) == data else { throw RoundSessionFailureV1.digestMismatch }; return value
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String { KernelCanonicalHashV1.sha256(try encode(value)) }
}
