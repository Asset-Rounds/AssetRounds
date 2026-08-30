import CryptoKit
import Foundation

enum MyDayFailureV1: Error, Equatable, Sendable {
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case duplicateReference
    case limitExceeded
    case staleRevision
    case divergentMutation
    case missingSource
    case invalidCarryover
}

protocol MyDayCanonicalValidatingV1 {
    func validate() throws
}

enum MyDayLimitsV1 {
    static let maximumItems = 50
    static let minimumEstimateMinutes = 1
    static let maximumEstimateMinutes = 720
    static let maximumCanonicalBytes = 1_048_576
    static let maximumTimeZoneBytes = 255
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zeroUUID else { throw MyDayFailureV1.invalidValue }
    }

    static func workspace(_ value: WorkspaceID) throws { try id(value.rawValue) }

    static func revision(_ value: UInt64) throws {
        guard value > 0 else { throw MyDayFailureV1.invalidValue }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw MyDayFailureV1.invalidDigest }
    }

    static func timeZone(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= maximumTimeZoneBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              TimeZone(identifier: value)?.identifier == value else { throw MyDayFailureV1.invalidValue }
    }

    static func millisecondInstant(_ value: Date) throws {
        let seconds = value.timeIntervalSince1970
        let milliseconds = seconds * 1_000
        let integralMilliseconds = milliseconds.rounded(.toNearestOrAwayFromZero)
        let maximumExactInteger = 9_007_199_254_740_991.0
        guard seconds.isFinite, milliseconds.isFinite,
              abs(integralMilliseconds) <= maximumExactInteger,
              Date(timeIntervalSince1970: integralMilliseconds / 1_000) == value else { throw MyDayFailureV1.invalidValue }
    }
}

struct MyDayKeyV1: Codable, Equatable, Hashable, Comparable, Sendable, MyDayCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let civilDate: ScheduleLocalDateV1
    let ianaTimeZoneIdentifier: String
    let keySHA256: String

    init(workspaceID: WorkspaceID, civilDate: ScheduleLocalDateV1, ianaTimeZoneIdentifier: String) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.civilDate = civilDate
        self.ianaTimeZoneIdentifier = ianaTimeZoneIdentifier
        keySHA256 = try MyDayCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID, civilDate: civilDate, ianaTimeZoneIdentifier: ianaTimeZoneIdentifier))
        try validate()
    }

    var stableKey: String { "\(workspaceID.rawValue.uuidString.lowercased())|\(civilDate.canonicalString)|\(ianaTimeZoneIdentifier)" }

    func validate() throws {
        try MyDayLimitsV1.workspace(workspaceID); try civilDate.validate(); try MyDayLimitsV1.timeZone(ianaTimeZoneIdentifier)
        guard schemaVersion == Self.schemaVersion,
              keySHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidDigest }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableKey < rhs.stableKey }
    func rebound(to workspaceID: WorkspaceID) throws -> Self { try .init(workspaceID: workspaceID, civilDate: civilDate, ianaTimeZoneIdentifier: ianaTimeZoneIdentifier) }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID, civilDate: civilDate, ianaTimeZoneIdentifier: ianaTimeZoneIdentifier) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let civilDate: ScheduleLocalDateV1; let ianaTimeZoneIdentifier: String }
}

struct MyDayEstimateV1: Codable, Equatable, Hashable, Comparable, Sendable, MyDayCanonicalValidatingV1 {
    let wholeMinutes: Int
    init(wholeMinutes: Int) throws { self.wholeMinutes = wholeMinutes; try validate() }
    func validate() throws { guard (MyDayLimitsV1.minimumEstimateMinutes...MyDayLimitsV1.maximumEstimateMinutes).contains(wholeMinutes) else { throw MyDayFailureV1.limitExceeded } }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.wholeMinutes < rhs.wholeMinutes }
}

enum MyDayEligibleReferenceV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    case workPacket(WorkPacketManifestReferenceV1)
    case roundSession(workspaceID: WorkspaceID, sessionID: UUID, revision: UInt64, sessionSHA256: String)
    case scheduleOccurrence(C34OccurrenceNavigationAnchorV1, sourceEventSHA256: String)
    case resumableDraft(workspaceID: WorkspaceID, draftID: UUID, revision: UInt64, checkpointSHA256: String, anchor: DraftResumeAnchorV1)

    var workspaceID: WorkspaceID {
        switch self {
        case .workPacket(let value): return value.workspaceID
        case .roundSession(let workspaceID, _, _, _), .resumableDraft(let workspaceID, _, _, _, _): return workspaceID
        case .scheduleOccurrence(let anchor, _): return anchor.schedule.workspaceID
        }
    }

    var stableKey: String {
        switch self {
        case .workPacket(let value): return "WORK_PACKET|\(value.packetID.uuidString.lowercased())"
        case .roundSession(_, let id, _, _): return "ROUND_SESSION|\(id.uuidString.lowercased())"
        case .scheduleOccurrence(let anchor, _): return "SCHEDULE_OCCURRENCE|\(anchor.schedule.scheduleDefinitionID.uuidString.lowercased())|\(anchor.occurrenceID.rawValue)"
        case .resumableDraft(_, let id, _, _, _): return "RESUMABLE_DRAFT|\(id.uuidString.lowercased())"
        }
    }

    var sourceRevision: UInt64 {
        switch self {
        case .workPacket(let value): return value.packetVersion
        case .roundSession(_, _, let revision, _), .resumableDraft(_, _, let revision, _, _): return revision
        case .scheduleOccurrence(let anchor, _): return anchor.expectedOccurrenceRevision
        }
    }

    var sourceSHA256: String {
        switch self {
        case .workPacket(let value): return value.manifestSHA256
        case .roundSession(_, _, _, let digest), .resumableDraft(_, _, _, let digest, _), .scheduleOccurrence(_, let digest): return digest
        }
    }

    func validate() throws {
        try MyDayLimitsV1.workspace(workspaceID); try MyDayLimitsV1.revision(sourceRevision); try MyDayLimitsV1.digest(sourceSHA256)
        switch self {
        case .workPacket(let value): try value.validate()
        case .roundSession(_, let id, _, _): try MyDayLimitsV1.id(id)
        case .scheduleOccurrence(let anchor, _): try anchor.validate()
        case .resumableDraft(_, let id, _, _, let anchor): try MyDayLimitsV1.id(id); try anchor.validate()
        }
    }
}

struct MyDayRebindContextV1: Sendable {
    let sourceWorkspaceID: WorkspaceID
    let targetWorkspaceID: WorkspaceID
    let operationID: UUID
    let targetReferencesByStableKey: [String: MyDayEligibleReferenceV1]
    init(sourceWorkspaceID: WorkspaceID, targetWorkspaceID: WorkspaceID, operationID: UUID, targetReferences: [MyDayEligibleReferenceV1]) throws {
        try MyDayLimitsV1.workspace(sourceWorkspaceID); try MyDayLimitsV1.workspace(targetWorkspaceID); try MyDayLimitsV1.id(operationID)
        guard sourceWorkspaceID != targetWorkspaceID, targetReferences.allSatisfy({ $0.workspaceID == targetWorkspaceID }), Set(targetReferences.map(\.stableKey)).count == targetReferences.count else { throw MyDayFailureV1.wrongWorkspace }
        try targetReferences.forEach { try $0.validate() }
        self.sourceWorkspaceID=sourceWorkspaceID;self.targetWorkspaceID=targetWorkspaceID;self.operationID=operationID
        targetReferencesByStableKey=Dictionary(uniqueKeysWithValues:targetReferences.map{($0.stableKey,$0)})
    }
    func reference(rebinding source:MyDayEligibleReferenceV1)throws->MyDayEligibleReferenceV1{try source.validate();guard source.workspaceID==sourceWorkspaceID,let target=targetReferencesByStableKey[source.stableKey],target.workspaceID==targetWorkspaceID,target.sourceSHA256 != source.sourceSHA256 || target.sourceRevision != source.sourceRevision else{throw MyDayFailureV1.missingSource};return target}
    func actor(rebinding source:ActorSnapshotV1)throws->ActorSnapshotV1{try source.validate();guard source.workspaceID==sourceWorkspaceID else{throw MyDayFailureV1.wrongWorkspace};let actor=try LocalActorReferenceV1(actorReferenceID:source.actor.actorReferenceID,workspaceID:targetWorkspaceID,partyID:source.actor.partyID,displayName:source.actor.displayName);return try ActorSnapshotV1(snapshotID:source.snapshotID,workspaceID:targetWorkspaceID,actor:actor,responsibility:source.responsibility,displayNameAtTime:source.displayNameAtTime,capturedAt:source.capturedAt)}
    func mutationID(planID:UUID,revision:UInt64)throws->MutationIDV1{try MyDayLimitsV1.id(planID);try MyDayLimitsV1.revision(revision);let basis="\(operationID.uuidString.lowercased())|\(planID.uuidString.lowercased())|\(revision)";var bytes=Array(SHA256.hash(data:Data(basis.utf8)).prefix(16));bytes[6]=(bytes[6]&0x0f)|0x50;bytes[8]=(bytes[8]&0x3f)|0x80;return try MutationIDV1(rawValue:UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])))}
}

struct MyDayItemV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let membershipID: UUID
    let reference: MyDayEligibleReferenceV1
    let manualOrder: Int
    let estimate: MyDayEstimateV1?

    init(membershipID: UUID, reference: MyDayEligibleReferenceV1, manualOrder: Int, estimate: MyDayEstimateV1? = nil) throws {
        self.membershipID = membershipID; self.reference = reference; self.manualOrder = manualOrder; self.estimate = estimate
        try validate()
    }

    func validate() throws {
        try MyDayLimitsV1.id(membershipID); try reference.validate(); try estimate?.validate()
        guard manualOrder >= 0, manualOrder < MyDayLimitsV1.maximumItems else { throw MyDayFailureV1.limitExceeded }
    }
    func rebound(using context:MyDayRebindContextV1)throws->Self{try .init(membershipID:membershipID,reference:context.reference(rebinding:reference),manualOrder:manualOrder,estimate:estimate)}
}

struct MyDayPlanReferenceV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let planID: UUID; let key: MyDayKeyV1; let revision: UInt64; let planSHA256: String
    init(_ value: MyDayPlanV1) throws { try value.validate(); planID = value.planID; key = value.key; revision = value.revision; planSHA256 = value.planSHA256 }
    func validate() throws { try MyDayLimitsV1.id(planID); try key.validate(); try MyDayLimitsV1.revision(revision); try MyDayLimitsV1.digest(planSHA256) }
}

struct MyDayPlanV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    static let schemaVersion = 1
    let schemaVersion: Int; let planID: UUID; let key: MyDayKeyV1; let items: [MyDayItemV1]
    let predecessorPlanSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1
    let authoredBy: ActorSnapshotV1; let authoredAt: Date; let planSHA256: String

    init(planID: UUID, key: MyDayKeyV1, items: [MyDayItemV1], predecessor: MyDayPlanV1? = nil,
         revision: UInt64, mutationID: MutationIDV1, authoredBy: ActorSnapshotV1, authoredAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.planID = planID; self.key = key; self.items = items
        predecessorPlanSHA256 = predecessor?.planSHA256; self.revision = revision; self.mutationID = mutationID
        self.authoredBy = authoredBy; self.authoredAt = authoredAt
        planSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, planID: planID, key: key, items: items, predecessorPlanSHA256: predecessor?.planSHA256, revision: revision, mutationID: mutationID, authoredBy: authoredBy, authoredAt: authoredAt))
        try validate(predecessor: predecessor)
    }

    func validate() throws { try validateIntrinsic() }
    func validateIntrinsic() throws {
        try MyDayLimitsV1.id(planID); try key.validate(); try items.forEach { try $0.validate() }
        try MyDayLimitsV1.revision(revision); try authoredBy.validate(); try MyDayLimitsV1.millisecondInstant(authoredAt); try MyDayLimitsV1.millisecondInstant(authoredBy.capturedAt)
        if let predecessorPlanSHA256 { try MyDayLimitsV1.digest(predecessorPlanSHA256) }
        let orders = items.map(\.manualOrder)
        guard schemaVersion == Self.schemaVersion, items.count <= MyDayLimitsV1.maximumItems,
              items.allSatisfy({ $0.reference.workspaceID == key.workspaceID }),
              Set(items.map(\.membershipID)).count == items.count,
              Set(items.map { $0.reference.stableKey }).count == items.count,
              orders == Array(0..<items.count), authoredBy.workspaceID == key.workspaceID,
              authoredBy.responsibility == .recordedBy,
              (revision == 1) == (predecessorPlanSHA256 == nil),
              planSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidValue }
    }

    func validate(predecessor: Self?) throws {
        try validateIntrinsic()
        guard predecessorPlanSHA256 == predecessor?.planSHA256 else { throw MyDayFailureV1.staleRevision }
        if let predecessor {
            try predecessor.validateIntrinsic()
            let (next, overflow) = predecessor.revision.addingReportingOverflow(1)
            guard !overflow, revision == next, planID == predecessor.planID, key == predecessor.key,
                  mutationID != predecessor.mutationID, authoredAt >= predecessor.authoredAt else { throw MyDayFailureV1.staleRevision }
        } else { guard revision == 1 else { throw MyDayFailureV1.staleRevision } }
    }
    func rebound(using context:MyDayRebindContextV1,predecessor:Self?)throws->Self{try validateIntrinsic();guard key.workspaceID==context.sourceWorkspaceID else{throw MyDayFailureV1.wrongWorkspace};return try .init(planID:planID,key:key.rebound(to:context.targetWorkspaceID),items:items.map{try $0.rebound(using:context)},predecessor:predecessor,revision:revision,mutationID:context.mutationID(planID:planID,revision:revision),authoredBy:context.actor(rebinding:authoredBy),authoredAt:authoredAt)}

    private var basis: Basis { .init(schemaVersion: schemaVersion, planID: planID, key: key, items: items, predecessorPlanSHA256: predecessorPlanSHA256, revision: revision, mutationID: mutationID, authoredBy: authoredBy, authoredAt: authoredAt) }
    private struct Basis: Codable { let schemaVersion: Int; let planID: UUID; let key: MyDayKeyV1; let items: [MyDayItemV1]; let predecessorPlanSHA256: String?; let revision: UInt64; let mutationID: MutationIDV1; let authoredBy: ActorSnapshotV1; let authoredAt: Date }
}

struct MyDayCarryoverPlanV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let sourcePlan: MyDayPlanReferenceV1; let targetKey: MyDayKeyV1
    let selectedSourceItems: [MyDayItemV1]; let expectedTargetPlan: MyDayPlanReferenceV1?; let planSHA256: String

    var membershipIDs: [UUID] { selectedSourceItems.map(\.membershipID) }

    init(sourcePlan: MyDayPlanV1, targetKey: MyDayKeyV1, membershipIDs: [UUID], expectedTargetPlan: MyDayPlanV1? = nil) throws {
        self.sourcePlan = try .init(sourcePlan); self.targetKey = targetKey
        let requested = Set(membershipIDs)
        selectedSourceItems = sourcePlan.items.filter { requested.contains($0.membershipID) }
        self.expectedTargetPlan = try expectedTargetPlan.map(MyDayPlanReferenceV1.init)
        planSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(sourcePlan: self.sourcePlan, targetKey: targetKey, selectedSourceItems: selectedSourceItems, expectedTargetPlan: self.expectedTargetPlan))
        guard selectedSourceItems.map(\.membershipID) == membershipIDs else { throw MyDayFailureV1.invalidCarryover }
        try validate()
    }

    func validate() throws {
        try sourcePlan.validate(); try targetKey.validate(); try expectedTargetPlan?.validate(); try selectedSourceItems.forEach { try $0.validate() }
        guard sourcePlan.key.workspaceID == targetKey.workspaceID, sourcePlan.key != targetKey,
              targetKey.civilDate.stableKey >= sourcePlan.key.civilDate.stableKey,
              !selectedSourceItems.isEmpty, selectedSourceItems.count <= MyDayLimitsV1.maximumItems,
              Set(membershipIDs).count == membershipIDs.count,
              selectedSourceItems.allSatisfy({ $0.reference.workspaceID == sourcePlan.key.workspaceID }),
              expectedTargetPlan.map({ $0.key == targetKey }) ?? true,
              planSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidCarryover }
    }
    private var basis: Basis { .init(sourcePlan: sourcePlan, targetKey: targetKey, selectedSourceItems: selectedSourceItems, expectedTargetPlan: expectedTargetPlan) }
    private struct Basis: Codable { let sourcePlan: MyDayPlanReferenceV1; let targetKey: MyDayKeyV1; let selectedSourceItems: [MyDayItemV1]; let expectedTargetPlan: MyDayPlanReferenceV1? }
}

struct MyDayCarryoverReceiptV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let carryoverPlanSHA256: String; let sourcePlan: MyDayPlanReferenceV1; let targetPlan: MyDayPlanReferenceV1
    let carriedMembershipIDs: [UUID]; let mutationID: MutationIDV1; let committedAt: Date; let receiptSHA256: String

    init(plan: MyDayCarryoverPlanV1, source: MyDayPlanV1, target: MyDayPlanV1, mutationID: MutationIDV1, committedAt: Date) throws {
        try plan.validate(); try source.validate(); try target.validate()
        carryoverPlanSHA256 = plan.planSHA256; sourcePlan = try .init(source); targetPlan = try .init(target)
        carriedMembershipIDs = plan.membershipIDs; self.mutationID = mutationID; self.committedAt = committedAt
        receiptSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(carryoverPlanSHA256: plan.planSHA256, sourcePlan: sourcePlan, targetPlan: targetPlan, carriedMembershipIDs: plan.membershipIDs, mutationID: mutationID, committedAt: committedAt))
        try validate(plan: plan, source: source, target: target)
    }

    func validate() throws {
        try MyDayLimitsV1.digest(carryoverPlanSHA256); try sourcePlan.validate(); try targetPlan.validate()
        try carriedMembershipIDs.forEach(MyDayLimitsV1.id); try MyDayLimitsV1.millisecondInstant(committedAt)
        guard sourcePlan.key.workspaceID == targetPlan.key.workspaceID, sourcePlan.key != targetPlan.key,
              !carriedMembershipIDs.isEmpty, Set(carriedMembershipIDs).count == carriedMembershipIDs.count,
              receiptSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidCarryover }
    }

    func validate(plan: MyDayCarryoverPlanV1, source: MyDayPlanV1, target: MyDayPlanV1) throws {
        try validate(); try plan.validate(); try source.validate(); try target.validate()
        let selected = source.items.filter { plan.membershipIDs.contains($0.membershipID) }
        let targetByMembership = Dictionary(grouping: target.items, by: \.membershipID)
        guard plan.planSHA256 == carryoverPlanSHA256, sourcePlan == (try MyDayPlanReferenceV1(source)), targetPlan == (try MyDayPlanReferenceV1(target)),
              plan.sourcePlan == sourcePlan, plan.targetKey == target.key,
              selected == plan.selectedSourceItems, selected.map(\.membershipID) == carriedMembershipIDs,
              selected.allSatisfy({ sourceItem in
                  guard let targets = targetByMembership[sourceItem.membershipID], targets.count == 1 else { return false }
                  return targets[0].reference == sourceItem.reference && targets[0].estimate == sourceItem.estimate
              }),
              mutationID == target.mutationID else { throw MyDayFailureV1.invalidCarryover }
    }
    private var basis: Basis { .init(carryoverPlanSHA256: carryoverPlanSHA256, sourcePlan: sourcePlan, targetPlan: targetPlan, carriedMembershipIDs: carriedMembershipIDs, mutationID: mutationID, committedAt: committedAt) }
    private struct Basis: Codable { let carryoverPlanSHA256: String; let sourcePlan: MyDayPlanReferenceV1; let targetPlan: MyDayPlanReferenceV1; let carriedMembershipIDs: [UUID]; let mutationID: MutationIDV1; let committedAt: Date }
}

enum MyDaySourceStateV1: String, Codable, CaseIterable, Hashable, Sendable {
    case active = "ACTIVE"; case completed = "COMPLETED"; case cancelled = "CANCELLED"
    case retired = "RETIRED"; case missing = "MISSING"; case stale = "STALE"; case reopened = "REOPENED"
}

enum MyDayReadinessV1: String, Codable, CaseIterable, Hashable, Sendable {
    case ready = "READY"; case notReady = "NOT_READY"; case blocked = "BLOCKED"; case unavailable = "UNAVAILABLE"
}

struct MyDaySourceFrontierV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let membershipID: UUID; let plannedReference: MyDayEligibleReferenceV1
    let currentReference: MyDayEligibleReferenceV1?; let state: MyDaySourceStateV1
    let readiness: MyDayReadinessV1; let dueAt: Date?; let evaluatedAt: Date; let frontierSHA256: String

    init(membershipID: UUID, plannedReference: MyDayEligibleReferenceV1, currentReference: MyDayEligibleReferenceV1?, state: MyDaySourceStateV1, readiness: MyDayReadinessV1, dueAt: Date?, evaluatedAt: Date) throws {
        self.membershipID = membershipID; self.plannedReference = plannedReference; self.currentReference = currentReference
        self.state = state; self.readiness = readiness; self.dueAt = dueAt; self.evaluatedAt = evaluatedAt
        frontierSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(membershipID: membershipID, plannedReference: plannedReference, currentReference: currentReference, state: state, readiness: readiness, dueAt: dueAt, evaluatedAt: evaluatedAt))
        try validate()
    }

    func validate() throws {
        try MyDayLimitsV1.id(membershipID); try plannedReference.validate(); try currentReference?.validate()
        try dueAt.map(MyDayLimitsV1.millisecondInstant); try MyDayLimitsV1.millisecondInstant(evaluatedAt)
        let unavailable = currentReference == nil
        guard currentReference.map({ $0.workspaceID == plannedReference.workspaceID && $0.stableKey == plannedReference.stableKey }) ?? true,
              unavailable == (state == .missing),
              (!unavailable || readiness == .unavailable),
              frontierSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidValue }
    }
    private var basis: Basis { .init(membershipID: membershipID, plannedReference: plannedReference, currentReference: currentReference, state: state, readiness: readiness, dueAt: dueAt, evaluatedAt: evaluatedAt) }
    private struct Basis: Codable { let membershipID: UUID; let plannedReference: MyDayEligibleReferenceV1; let currentReference: MyDayEligibleReferenceV1?; let state: MyDaySourceStateV1; let readiness: MyDayReadinessV1; let dueAt: Date?; let evaluatedAt: Date }
}

struct MyDayReadinessProjectionV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let plan: MyDayPlanReferenceV1; let evaluatedAt: Date; let frontiers: [MyDaySourceFrontierV1]
    let sourceClosureSHA256: String; let projectionSHA256: String

    init(plan: MyDayPlanV1, evaluatedAt: Date, frontiers: [MyDaySourceFrontierV1]) throws {
        self.plan = try .init(plan); self.evaluatedAt = evaluatedAt; self.frontiers = frontiers
        sourceClosureSHA256 = try MyDayCanonicalCodecV1.sha256(frontiers.map(\.frontierSHA256))
        projectionSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(plan: self.plan, evaluatedAt: evaluatedAt, frontiers: frontiers, sourceClosureSHA256: sourceClosureSHA256))
        try validate(plan: plan)
    }

    func validate() throws {
        try plan.validate(); try MyDayLimitsV1.millisecondInstant(evaluatedAt); try frontiers.forEach { try $0.validate() }
        guard Set(frontiers.map(\.membershipID)).count == frontiers.count,
              frontiers.allSatisfy({ $0.evaluatedAt == evaluatedAt && $0.plannedReference.workspaceID == plan.key.workspaceID }),
              sourceClosureSHA256 == (try MyDayCanonicalCodecV1.sha256(frontiers.map(\.frontierSHA256))),
              projectionSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidDigest }
    }

    func validate(plan value: MyDayPlanV1) throws {
        try validate(); try value.validate()
        guard plan == (try MyDayPlanReferenceV1(value)), frontiers.map(\.membershipID) == value.items.map(\.membershipID),
              zip(frontiers, value.items).allSatisfy({ $0.plannedReference == $1.reference }) else { throw MyDayFailureV1.staleRevision }
    }
    private var basis: Basis { .init(plan: plan, evaluatedAt: evaluatedAt, frontiers: frontiers, sourceClosureSHA256: sourceClosureSHA256) }
    private struct Basis: Codable { let plan: MyDayPlanReferenceV1; let evaluatedAt: Date; let frontiers: [MyDaySourceFrontierV1]; let sourceClosureSHA256: String }
}

enum MyDayCommandV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    case save(successor: MyDayPlanV1, predecessor: MyDayPlanV1?)
    case carryover(plan: MyDayCarryoverPlanV1, source: MyDayPlanV1, target: MyDayPlanV1, receipt: MyDayCarryoverReceiptV1)

    var workspaceID: WorkspaceID { switch self { case .save(let value, _): return value.key.workspaceID; case .carryover(_, let source, _, _): return source.key.workspaceID } }
    var mutationID: MutationIDV1 { switch self { case .save(let value, _): return value.mutationID; case .carryover(_, _, let target, _): return target.mutationID } }
    func validate() throws {
        switch self {
        case .save(let successor, let predecessor): try successor.validate(predecessor: predecessor)
        case .carryover(let plan, let source, let target, let receipt): try receipt.validate(plan: plan, source: source, target: target)
        }
    }
    func canonicalSHA256() throws -> String { try validate(); return try MyDayCanonicalCodecV1.sha256(self) }
}

enum MyDayCommandDispositionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case committed = "COMMITTED"; case idempotentReplay = "IDEMPOTENT_REPLAY"
}

struct MyDayMutationReceiptV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let workspaceID: WorkspaceID; let mutationID: MutationIDV1; let commandSHA256: String
    let resultingPlan: MyDayPlanReferenceV1; let carryoverReceiptSHA256: String?
    let disposition: MyDayCommandDispositionV1; let committedAt: Date; let receiptSHA256: String

    init(command: MyDayCommandV1, resultingPlan: MyDayPlanV1, carryoverReceipt: MyDayCarryoverReceiptV1? = nil,
         disposition: MyDayCommandDispositionV1, committedAt: Date) throws {
        try command.validate(); try resultingPlan.validate(); try carryoverReceipt?.validate()
        workspaceID = command.workspaceID; mutationID = command.mutationID; commandSHA256 = try command.canonicalSHA256()
        self.resultingPlan = try .init(resultingPlan); carryoverReceiptSHA256 = carryoverReceipt?.receiptSHA256
        self.disposition = disposition; self.committedAt = committedAt
        receiptSHA256 = try MyDayCanonicalCodecV1.sha256(Basis(workspaceID: workspaceID, mutationID: mutationID, commandSHA256: commandSHA256, resultingPlan: self.resultingPlan, carryoverReceiptSHA256: carryoverReceiptSHA256, disposition: disposition, committedAt: committedAt))
        try validate(command: command)
    }

    func validate() throws {
        try MyDayLimitsV1.digest(commandSHA256); try resultingPlan.validate(); if let carryoverReceiptSHA256 { try MyDayLimitsV1.digest(carryoverReceiptSHA256) }
        try MyDayLimitsV1.millisecondInstant(committedAt)
        guard disposition == .committed, workspaceID == resultingPlan.key.workspaceID,
              receiptSHA256 == (try MyDayCanonicalCodecV1.sha256(basis)) else { throw MyDayFailureV1.invalidDigest }
    }
    func validate(command: MyDayCommandV1) throws {
        try validate(); try command.validate()
        guard workspaceID == command.workspaceID, mutationID == command.mutationID,
              commandSHA256 == (try command.canonicalSHA256()) else { throw MyDayFailureV1.divergentMutation }
        switch command {
        case .save(let successor, _):
            guard resultingPlan == (try MyDayPlanReferenceV1(successor)), carryoverReceiptSHA256 == nil else { throw MyDayFailureV1.divergentMutation }
        case .carryover(_, _, let target, let carryover):
            guard resultingPlan == (try MyDayPlanReferenceV1(target)), carryoverReceiptSHA256 == carryover.receiptSHA256 else { throw MyDayFailureV1.divergentMutation }
        }
    }
    private var basis: Basis { .init(workspaceID: workspaceID, mutationID: mutationID, commandSHA256: commandSHA256, resultingPlan: resultingPlan, carryoverReceiptSHA256: carryoverReceiptSHA256, disposition: disposition, committedAt: committedAt) }
    private struct Basis: Codable { let workspaceID: WorkspaceID; let mutationID: MutationIDV1; let commandSHA256: String; let resultingPlan: MyDayPlanReferenceV1; let carryoverReceiptSHA256: String?; let disposition: MyDayCommandDispositionV1; let committedAt: Date }
}

struct MyDayCommandResultV1: Codable, Equatable, Hashable, Sendable, MyDayCanonicalValidatingV1 {
    let plan: MyDayPlanV1; let receipt: MyDayMutationReceiptV1
    func validate() throws { try plan.validate(); try receipt.validate(); guard receipt.resultingPlan == (try MyDayPlanReferenceV1(plan)) else { throw MyDayFailureV1.divergentMutation } }
}

struct MyDayCommandReplayResolutionV1: Equatable, Hashable, Sendable {
    let disposition: MyDayCommandDispositionV1
    let receipt: MyDayMutationReceiptV1

    static func resolve(command: MyDayCommandV1, priorReceipt: MyDayMutationReceiptV1) throws -> Self {
        try command.validate(); try priorReceipt.validate()
        guard command.mutationID == priorReceipt.mutationID else { throw MyDayFailureV1.staleRevision }
        try priorReceipt.validate(command: command)
        return .init(disposition: .idempotentReplay, receipt: priorReceipt)
    }
}

enum MyDayCanonicalCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= MyDayLimitsV1.maximumCanonicalBytes else { throw MyDayFailureV1.limitExceeded }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        try (value as? any MyDayCanonicalValidatingV1)?.validate()
        guard try self.data(value) == data else { throw MyDayFailureV1.invalidDigest }
        return value
    }
}

enum C57MyDayLifecycleBoundaryV1 {
    static let canonicalWriterIsIncumbentWorkspaceWriter = true
    static let readinessAndSourceStateAreNonpersistent = true
    static let replaceRestorePreservesExactPlans = true
    static let configurationCloneOmitsPlans = true
    static let workspaceForkRetainsNonactiveHistoryOnly = true
    static let removalMutatesSourceWork = false
    static let automaticallyCarriesAcrossDateOrZone = false
    static let dispatchesOrSchedulesWork = false
    static let storesActualDuration = false
}
