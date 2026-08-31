import Foundation

/// Deterministic nonpersistent field-index projection failures.
enum FieldSectionIndexProjectionFailureV1: Error, Equatable, Sendable { case invalidValue, limitExceeded, foreignAnchor, inconsistentCounts, digestMismatch }
enum FieldSectionIndexAnchorStateV1: String, Equatable, Sendable { case current = "CURRENT", staleRequirementFallback = "STALE_REQUIREMENT_FALLBACK" }

struct FieldSectionIndexRequirementBindingV1: Equatable, Hashable, Sendable {
    let itemID: UUID; let requirementSHA256: String
    init(itemID: UUID, requirementSHA256: String) throws { guard KernelCanonicalHashV1.validSHA256(requirementSHA256) else { throw FieldSectionIndexProjectionFailureV1.invalidValue }; self.itemID = itemID; self.requirementSHA256 = requirementSHA256 }
}

struct FieldSectionIndexDraftAnchorV1: Equatable, Hashable, Sendable {
    let itemID: UUID; let draftID: UUID; let anchor: DraftResumeAnchorV1
    init(itemID: UUID, draftID: UUID, anchor: DraftResumeAnchorV1) throws { try anchor.validate(); self.itemID = itemID; self.draftID = draftID; self.anchor = anchor }
}

/// One exact, closed package-policy observation per session item. A Boolean
/// alone is never a navigation authority.
struct FieldSectionIndexOutOfOrderPermissionV1: Equatable, Hashable, Sendable {
    let itemID: UUID; let packageReleaseID: String; let packageSHA256: String; let workflowSHA256: String; let permitsOutOfOrderNavigation: Bool
    init(itemID: UUID, packageReleaseID: String, packageSHA256: String, workflowSHA256: String, permitsOutOfOrderNavigation: Bool) throws {
        guard KernelCanonicalHashV1.validSHA256(packageReleaseID), KernelCanonicalHashV1.validSHA256(packageSHA256), KernelCanonicalHashV1.validSHA256(workflowSHA256) else { throw FieldSectionIndexProjectionFailureV1.invalidValue }
        self.itemID = itemID; self.packageReleaseID = packageReleaseID; self.packageSHA256 = packageSHA256; self.workflowSHA256 = workflowSHA256; self.permitsOutOfOrderNavigation = permitsOutOfOrderNavigation
    }
}

struct FieldSectionIndexFieldV1: Equatable, Sendable {
    let itemID: UUID; let assetID: UUID; let siteID: UUID; let order: Int; let disposition: RoundItemDispositionV1; let requirementSHA256: String
    let anchor: FieldPositionAnchorV1; let anchorState: FieldSectionIndexAnchorStateV1; let draftAnchor: DraftResumeAnchorV1?; let packagePermitsOutOfOrderNavigation: Bool
    var incomplete: Bool { !disposition.isTerminal }; var flagged: Bool { disposition == .deferred || disposition == .inaccessible }
    fileprivate init(itemID: UUID, assetID: UUID, siteID: UUID, order: Int, disposition: RoundItemDispositionV1, requirementSHA256: String, anchor: FieldPositionAnchorV1, anchorState: FieldSectionIndexAnchorStateV1, draftAnchor: DraftResumeAnchorV1?, packagePermitsOutOfOrderNavigation: Bool) { self.itemID = itemID; self.assetID = assetID; self.siteID = siteID; self.order = order; self.disposition = disposition; self.requirementSHA256 = requirementSHA256; self.anchor = anchor; self.anchorState = anchorState; self.draftAnchor = draftAnchor; self.packagePermitsOutOfOrderNavigation = packagePermitsOutOfOrderNavigation }
}

struct FieldSectionIndexSectionV1: Equatable, Sendable {
    let sectionID: String; let siteID: UUID; let anchor: FieldPositionAnchorV1; let fields: [FieldSectionIndexFieldV1]; let completeCount: Int; let incompleteCount: Int; let flaggedCount: Int
    fileprivate init(sectionID: String, siteID: UUID, anchor: FieldPositionAnchorV1, fields: [FieldSectionIndexFieldV1], completeCount: Int, incompleteCount: Int, flaggedCount: Int) { self.sectionID = sectionID; self.siteID = siteID; self.anchor = anchor; self.fields = fields; self.completeCount = completeCount; self.incompleteCount = incompleteCount; self.flaggedCount = flaggedCount }
}

/// DERIVED_ONLY/NONPERSISTENT: only this initializer can construct its result.
struct FieldSectionIndexProjectionV1: Equatable, Sendable {
    static let persistenceMode = "NONPERSISTENT_DERIVED_ONLY"
    let session: RoundSessionReferenceV1; let sections: [FieldSectionIndexSectionV1]; let completeCount: Int; let incompleteCount: Int; let flaggedCount: Int; let projectionSHA256: String
    private let requirementBindings: [FieldSectionIndexRequirementBindingV1]; private let draftAnchors: [FieldSectionIndexDraftAnchorV1]; private let permissions: [FieldSectionIndexOutOfOrderPermissionV1]
    var nextIncomplete: FieldSectionIndexFieldV1? { sections.flatMap(\.fields).first(where: \.incomplete) }
    var nextFlagged: FieldSectionIndexFieldV1? { sections.flatMap(\.fields).first(where: \.flagged) }

    init(session: RoundSessionV1, requirementBindings: [FieldSectionIndexRequirementBindingV1], draftAnchors: [FieldSectionIndexDraftAnchorV1] = [], packagePermissions: [FieldSectionIndexOutOfOrderPermissionV1]) throws {
        try session.validateIntrinsic()
        let itemIDs = Set(session.items.map(\.itemID))
        guard requirementBindings.count == session.items.count, packagePermissions.count == session.items.count, requirementBindings.count <= RoundSessionLimitsV1.maximumItems, draftAnchors.count <= RoundSessionLimitsV1.maximumItems, Set(requirementBindings.map(\.itemID)).count == requirementBindings.count, Set(packagePermissions.map(\.itemID)).count == packagePermissions.count, Set(draftAnchors.map(\.itemID)).count == draftAnchors.count, Set(requirementBindings.map(\.itemID)) == itemIDs, Set(packagePermissions.map(\.itemID)) == itemIDs, Set(draftAnchors.map(\.itemID)).isSubset(of: itemIDs) else { throw FieldSectionIndexProjectionFailureV1.invalidValue }
        let sortedBindings = requirementBindings.sorted { $0.itemID.uuidString < $1.itemID.uuidString }, sortedDrafts = draftAnchors.sorted { $0.itemID.uuidString < $1.itemID.uuidString }, sortedPermissions = packagePermissions.sorted { $0.itemID.uuidString < $1.itemID.uuidString }
        let rebuilt = try Self.rebuild(session: session, bindings: sortedBindings, drafts: sortedDrafts, permissions: sortedPermissions)
        let reference = try session.reference
        let digest = try Self.digest(session: reference, bindings: sortedBindings, drafts: sortedDrafts, permissions: sortedPermissions, sections: rebuilt.sections, complete: rebuilt.complete, incomplete: rebuilt.incomplete, flagged: rebuilt.flagged)
        self.session = reference; self.requirementBindings = sortedBindings; self.draftAnchors = sortedDrafts; self.permissions = sortedPermissions; sections = rebuilt.sections; completeCount = rebuilt.complete; incompleteCount = rebuilt.incomplete; flaggedCount = rebuilt.flagged; projectionSHA256 = digest
    }

    func validate(session canonical: RoundSessionV1) throws {
        try canonical.validateIntrinsic(); guard try canonical.reference == session else { throw FieldSectionIndexProjectionFailureV1.foreignAnchor }
        let rebuilt = try Self(session: canonical, requirementBindings: requirementBindings, draftAnchors: draftAnchors, packagePermissions: permissions)
        guard rebuilt.sections == sections, rebuilt.completeCount == completeCount, rebuilt.incompleteCount == incompleteCount, rebuilt.flaggedCount == flaggedCount, rebuilt.projectionSHA256 == projectionSHA256 else { throw FieldSectionIndexProjectionFailureV1.digestMismatch }
    }

    private static func rebuild(session: RoundSessionV1, bindings: [FieldSectionIndexRequirementBindingV1], drafts: [FieldSectionIndexDraftAnchorV1], permissions: [FieldSectionIndexOutOfOrderPermissionV1]) throws -> (sections: [FieldSectionIndexSectionV1], complete: Int, incomplete: Int, flagged: Int) {
        let binding = Dictionary(uniqueKeysWithValues: bindings.map { ($0.itemID, $0) }); let draft = Dictionary(uniqueKeysWithValues: drafts.map { ($0.itemID, $0) }); let permission = Dictionary(uniqueKeysWithValues: permissions.map { ($0.itemID, $0) }); var grouped: [UUID: [FieldSectionIndexFieldV1]] = [:]
        for item in session.items { guard let b = binding[item.itemID], let p = permission[item.itemID], p.packageReleaseID == item.requirement.packageRelease.packageReleaseID, p.packageSHA256 == item.requirement.packageRelease.packageSHA256, p.workflowSHA256 == item.requirement.packageRelease.workflowSHA256 else { throw FieldSectionIndexProjectionFailureV1.foreignAnchor }; let current = b.requirementSHA256 == item.requirement.requirementSHA256; let sectionID = "site-\(item.selection.siteID.uuidString.lowercased())"; let anchor = try FieldPositionAnchorV1(sectionID: sectionID, fieldID: current ? item.itemID.uuidString.lowercased() : nil, selectedStableID: item.itemID.uuidString.lowercased(), boundedPosition: current ? item.order : nil); grouped[item.selection.siteID, default: []].append(.init(itemID: item.itemID, assetID: item.selection.assetID, siteID: item.selection.siteID, order: item.order, disposition: item.disposition, requirementSHA256: item.requirement.requirementSHA256, anchor: anchor, anchorState: current ? .current : .staleRequirementFallback, draftAnchor: draft[item.itemID]?.anchor, packagePermitsOutOfOrderNavigation: p.permitsOutOfOrderNavigation)) }
        guard grouped.count <= RoundSessionLimitsV1.maximumItems else { throw FieldSectionIndexProjectionFailureV1.limitExceeded }
        let sections = try grouped.map { site, fields -> FieldSectionIndexSectionV1 in let ordered = fields.sorted { $0.order < $1.order }; guard Set(ordered.map(\.order)).count == ordered.count else { throw FieldSectionIndexProjectionFailureV1.invalidValue }; let id = "site-\(site.uuidString.lowercased())"; return .init(sectionID: id, siteID: site, anchor: try .init(sectionID: id, boundedPosition: ordered.first?.order), fields: ordered, completeCount: ordered.filter { $0.disposition.isTerminal }.count, incompleteCount: ordered.filter(\.incomplete).count, flaggedCount: ordered.filter(\.flagged).count) }.sorted { $0.fields[0].order < $1.fields[0].order }
        let complete = sections.reduce(0) { $0 + $1.completeCount }, incomplete = sections.reduce(0) { $0 + $1.incompleteCount }, flagged = sections.reduce(0) { $0 + $1.flaggedCount }
        guard complete + incomplete == session.counts.expected, incomplete == session.counts.undispositioned, complete == session.counts.completed + session.counts.inaccessible + session.counts.skipped + session.counts.deferred, flagged == session.counts.deferred + session.counts.inaccessible else { throw FieldSectionIndexProjectionFailureV1.inconsistentCounts }; return (sections, complete, incomplete, flagged)
    }

    private static func digest(session: RoundSessionReferenceV1, bindings: [FieldSectionIndexRequirementBindingV1], drafts: [FieldSectionIndexDraftAnchorV1], permissions: [FieldSectionIndexOutOfOrderPermissionV1], sections: [FieldSectionIndexSectionV1], complete: Int, incomplete: Int, flagged: Int) throws -> String { try WorkspaceMutationCanonicalV1.sha256(Basis(session: session, bindings: bindings.map { .init(itemID: $0.itemID, hash: $0.requirementSHA256) }, drafts: drafts.map { .init(itemID: $0.itemID, draftID: $0.draftID, anchor: .init($0.anchor)) }, permissions: permissions.map { .init(itemID: $0.itemID, releaseID: $0.packageReleaseID, packageSHA: $0.packageSHA256, workflowSHA: $0.workflowSHA256, permitted: $0.permitsOutOfOrderNavigation) }, sections: sections.map { .init($0) }, complete: complete, incomplete: incomplete, flagged: flagged)) }
    private struct Basis: Codable { let session: RoundSessionReferenceV1; let bindings: [Binding]; let drafts: [Draft]; let permissions: [Permission]; let sections: [Section]; let complete: Int; let incomplete: Int; let flagged: Int }
    private struct Binding: Codable { let itemID: UUID; let hash: String }
    private struct Anchor: Codable { let sectionID: String?; let fieldID: String?; let selectedStableID: String?; let boundedPosition: Int?; init(_ value: FieldPositionAnchorV1) { sectionID = value.sectionID; fieldID = value.fieldID; selectedStableID = value.selectedStableID; boundedPosition = value.boundedPosition }; init(_ value: DraftResumeAnchorV1) { sectionID = value.sectionID; fieldID = value.fieldID; selectedStableID = value.selectedStableID; boundedPosition = value.boundedPosition } }
    private struct Draft: Codable { let itemID: UUID; let draftID: UUID; let anchor: Anchor }
    private struct Permission: Codable { let itemID: UUID; let releaseID: String; let packageSHA: String; let workflowSHA: String; let permitted: Bool }
    private struct Field: Codable { let itemID: UUID; let assetID: UUID; let siteID: UUID; let order: Int; let disposition: RoundItemDispositionV1; let requirementSHA: String; let anchor: Anchor; let anchorState: String; let draftAnchor: Anchor?; let permitted: Bool; init(_ value: FieldSectionIndexFieldV1) { itemID = value.itemID; assetID = value.assetID; siteID = value.siteID; order = value.order; disposition = value.disposition; requirementSHA = value.requirementSHA256; anchor = .init(value.anchor); anchorState = value.anchorState.rawValue; draftAnchor = value.draftAnchor.map { Anchor($0) }; permitted = value.packagePermitsOutOfOrderNavigation } }
    private struct Section: Codable { let sectionID: String; let siteID: UUID; let anchor: Anchor; let fields: [Field]; let complete: Int; let incomplete: Int; let flagged: Int; init(_ value: FieldSectionIndexSectionV1) { sectionID = value.sectionID; siteID = value.siteID; anchor = .init(value.anchor); fields = value.fields.map(Field.init); complete = value.completeCount; incomplete = value.incompleteCount; flagged = value.flaggedCount } }
}
