import Foundation
import SwiftData

enum MyDayRestoreDispositionV1: String, Codable, CaseIterable, Sendable {
    case replaceExact = "REPLACE_EXACT"
    case configurationCloneOmit = "CONFIGURATION_CLONE_OMIT"
    case workspaceForkNonactiveHistory = "WORKSPACE_FORK_NONACTIVE_HISTORY"
}

struct MyDayBackupSnapshotV1: Codable, Equatable, Sendable, MyDayCanonicalValidatingV1 {
    let workspaceID: WorkspaceID
    let plans: [MyDayPlanV1]
    let carryoverReceipts: [MyDayCarryoverReceiptV1]
    let nonactivePlanReferences: [MyDayPlanReferenceV1]
    let snapshotSHA256: String

    init(workspaceID: WorkspaceID, plans: [MyDayPlanV1], carryoverReceipts: [MyDayCarryoverReceiptV1], nonactivePlanReferences: [MyDayPlanReferenceV1]) throws {
        self.workspaceID=workspaceID;self.plans=plans.sorted{($0.key.stableKey,$0.revision,$0.planID.uuidString)<($1.key.stableKey,$1.revision,$1.planID.uuidString)}
        self.carryoverReceipts=carryoverReceipts.sorted{$0.receiptSHA256<$1.receiptSHA256};self.nonactivePlanReferences=nonactivePlanReferences.sorted{($0.key.stableKey,$0.revision,$0.planSHA256)<($1.key.stableKey,$1.revision,$1.planSHA256)}
        snapshotSHA256=try MyDayCanonicalCodecV1.sha256(Basis(workspaceID:workspaceID,plans:self.plans,carryoverReceipts:self.carryoverReceipts,nonactivePlanReferences:self.nonactivePlanReferences));try validate()
    }
    func validate()throws{try MyDayLimitsV1.workspace(workspaceID);try plans.forEach{try $0.validate()};try carryoverReceipts.forEach{try $0.validate()};try nonactivePlanReferences.forEach{try $0.validate()};let grouped=Dictionary(grouping:plans,by:\.planID);for values in grouped.values{let ordered=values.sorted{$0.revision<$1.revision};guard ordered.first?.revision==1,Set(ordered.map(\.key)).count==1 else{throw MyDayFailureV1.staleRevision};try ordered[0].validate(predecessor:nil);if ordered.count>1{for index in 1..<ordered.count{try ordered[index].validate(predecessor:ordered[index-1])}}};let references=try Set(plans.map{try MyDayPlanReferenceV1($0)});guard plans.allSatisfy({$0.key.workspaceID==workspaceID}),Set(grouped.values.compactMap{$0.first?.key}).count==grouped.count,carryoverReceipts.allSatisfy({$0.sourcePlan.key.workspaceID==workspaceID&&$0.targetPlan.key.workspaceID==workspaceID}),Set(plans.map{"\($0.planID.uuidString)|\($0.revision)"}).count==plans.count,Set(carryoverReceipts.map(\.receiptSHA256)).count==carryoverReceipts.count,Set(nonactivePlanReferences).isSubset(of:references),plans==plans.sorted(by:{($0.key.stableKey,$0.revision,$0.planID.uuidString)<($1.key.stableKey,$1.revision,$1.planID.uuidString)}),carryoverReceipts==carryoverReceipts.sorted(by:{$0.receiptSHA256<$1.receiptSHA256}),nonactivePlanReferences==nonactivePlanReferences.sorted(by:{($0.key.stableKey,$0.revision,$0.planSHA256)<($1.key.stableKey,$1.revision,$1.planSHA256)}),snapshotSHA256==(try MyDayCanonicalCodecV1.sha256(basis))else{throw MyDayFailureV1.invalidDigest}}
    private var basis:Basis{.init(workspaceID:workspaceID,plans:plans,carryoverReceipts:carryoverReceipts,nonactivePlanReferences:nonactivePlanReferences)}
    private struct Basis:Codable{let workspaceID:WorkspaceID;let plans:[MyDayPlanV1];let carryoverReceipts:[MyDayCarryoverReceiptV1];let nonactivePlanReferences:[MyDayPlanReferenceV1]}
}

@MainActor final class MyDayLifecycleAdapterV1 {
    private let modelContext:ModelContext
    init(modelContext:ModelContext){self.modelContext=modelContext}
    func snapshotForBackup(workspaceID:WorkspaceID,nonactivePlanReferences:[MyDayPlanReferenceV1])throws->MyDayBackupSnapshotV1{try .init(workspaceID:workspaceID,plans:planRows(workspaceID).map{try $0.value()},carryoverReceipts:receiptRows(workspaceID).map{try $0.value()},nonactivePlanReferences:nonactivePlanReferences)}
    static func preparedRestoreSnapshot(
        _ snapshot: MyDayBackupSnapshotV1,
        targetWorkspaceID: WorkspaceID,
        disposition: MyDayRestoreDispositionV1,
        operationID: UUID,
        targetReferences: [MyDayEligibleReferenceV1] = []
    ) throws -> MyDayBackupSnapshotV1 {
        try snapshot.validate()
        let exactSourceNonactive = try C57MyDayBackupEnrollmentV1
            .exactNonactiveReferences(for: snapshot.plans)
        guard snapshot.nonactivePlanReferences == exactSourceNonactive else {
            throw MyDayFailureV1.divergentMutation
        }
        switch disposition {
        case .replaceExact:
            guard snapshot.workspaceID == targetWorkspaceID, targetReferences.isEmpty else {
                throw MyDayFailureV1.wrongWorkspace
            }
            return snapshot
        case .configurationCloneOmit:
            guard targetReferences.isEmpty else { throw MyDayFailureV1.invalidValue }
            return try MyDayBackupSnapshotV1(
                workspaceID: targetWorkspaceID, plans: [], carryoverReceipts: [],
                nonactivePlanReferences: []
            )
        case .workspaceForkNonactiveHistory:
            guard snapshot.workspaceID != targetWorkspaceID else { throw MyDayFailureV1.wrongWorkspace }
            let context = try MyDayRebindContextV1(
                sourceWorkspaceID: snapshot.workspaceID,
                targetWorkspaceID: targetWorkspaceID,
                operationID: operationID,
                targetReferences: targetReferences
            )
            let selected = Set(snapshot.nonactivePlanReferences)
            var reboundBySourceReference: [MyDayPlanReferenceV1: MyDayPlanV1] = [:]
            for values in Dictionary(grouping: snapshot.plans, by: \.planID).values {
                let ordered = values.sorted { $0.revision < $1.revision }
                let references = try ordered.map(MyDayPlanReferenceV1.init)
                guard let tipReference = references.last, !selected.contains(tipReference) else {
                    throw MyDayFailureV1.invalidCarryover
                }
                let retained = zip(ordered, references).filter { selected.contains($0.1) }
                guard retained.map({ $0.0.revision }) == (0..<retained.count).map({ UInt64($0) + 1 }) else {
                    throw MyDayFailureV1.missingSource
                }
                var predecessor: MyDayPlanV1?
                for (source, reference) in retained {
                    let rebound = try source.rebound(using: context, predecessor: predecessor)
                    predecessor = rebound
                    guard reboundBySourceReference.updateValue(rebound, forKey: reference) == nil else {
                        throw MyDayFailureV1.divergentMutation
                    }
                }
            }
            guard reboundBySourceReference.count == selected.count else {
                throw MyDayFailureV1.missingSource
            }
            let plans = reboundBySourceReference.values.sorted {
                ($0.key.stableKey, $0.revision, $0.planID.uuidString)
                    < ($1.key.stableKey, $1.revision, $1.planID.uuidString)
            }
            let receipts = try snapshot.carryoverReceipts.compactMap { source -> MyDayCarryoverReceiptV1? in
                guard let reboundSource = reboundBySourceReference[source.sourcePlan],
                      let reboundTarget = reboundBySourceReference[source.targetPlan] else { return nil }
                let carry = try MyDayCarryoverPlanV1(
                    sourcePlan: reboundSource, targetKey: reboundTarget.key,
                    membershipIDs: source.carriedMembershipIDs
                )
                return try MyDayCarryoverReceiptV1(
                    plan: carry, source: reboundSource, target: reboundTarget,
                    mutationID: reboundTarget.mutationID, committedAt: source.committedAt
                )
            }
            return try MyDayBackupSnapshotV1(
                workspaceID: targetWorkspaceID,
                plans: plans,
                carryoverReceipts: receipts,
                nonactivePlanReferences: C57MyDayBackupEnrollmentV1
                    .exactNonactiveReferences(for: plans)
            )
        }
    }
    func materializeRestoreStaging(_ snapshot:MyDayBackupSnapshotV1,targetWorkspaceID:WorkspaceID,disposition:MyDayRestoreDispositionV1,operationID:UUID,targetReferences:[MyDayEligibleReferenceV1]=[])throws {
        guard try planRows(targetWorkspaceID).isEmpty && receiptRows(targetWorkspaceID).isEmpty else {
            throw MyDayFailureV1.divergentMutation
        }
        let prepared = try Self.preparedRestoreSnapshot(
            snapshot, targetWorkspaceID: targetWorkspaceID, disposition: disposition,
            operationID: operationID, targetReferences: targetReferences
        )
        for value in prepared.plans { modelContext.insert(try MyDayPlanRowV1(value)) }
        for value in prepared.carryoverReceipts {
            modelContext.insert(try MyDayCarryoverReceiptRowV1(value))
        }
        try modelContext.save()
    }
    func erase(workspaceID:WorkspaceID)throws{for row in try planRows(workspaceID){modelContext.delete(row)};for row in try receiptRows(workspaceID){modelContext.delete(row)};try modelContext.save()}
    private func planRows(_ workspaceID:WorkspaceID)throws->[MyDayPlanRowV1]{try modelContext.fetch(FetchDescriptor<MyDayPlanRowV1>()).filter{$0.workspaceID==workspaceID.rawValue}}
    private func receiptRows(_ workspaceID:WorkspaceID)throws->[MyDayCarryoverReceiptRowV1]{try modelContext.fetch(FetchDescriptor<MyDayCarryoverReceiptRowV1>()).filter{$0.workspaceID==workspaceID.rawValue}}
}

enum C57MyDayPersistentLifecycleBoundaryV1{static let persistentSchemaVersion=42;static let persistentModelCount=2;static let recordsSchemaVersion=41;static let readinessIsNonpersistent=true;static let replaceIsExact=true;static let cloneOmitsPlans=true;static let forkRetainsNonactiveHistoryOnly=true;static let eraseRemovesWorkspaceRows=true}

enum C22RecurringRoundMyDayLifecycleBoundaryV1 {
    static let activeVersionIdentifier = PersistentSchemaV53.versionIdentifier
    static let persistentSchemaVersion = RecurringRoundExperiencePersistenceBoundaryV1.schemaVersion
    static let activeModelCount = RecurringRoundExperiencePersistenceBoundaryV1.activeModelCount
    static let addedRowFamilyCount = RecurringRoundExperiencePersistenceBoundaryV1.addedRowFamilyCount
    static let dueQueueIsDerived = true
    static let reminderReconciliationIsDeviceLocal = true
    static let eraseHasAdditionalRows = false

    static func validate(
        experience: MyDayRecurringRoundExperienceV1,
        reminder: LocalReminderReconciliationV1? = nil
    ) throws {
        try experience.validate()
        try reminder?.validate()
        guard reminder.map({ $0.workspaceID == experience.workspaceID && !$0.canonicalDueTruthChanged }) ?? true,
              addedRowFamilyCount == 0 else { throw MyDayFailureV1.invalidValue }
    }
}
