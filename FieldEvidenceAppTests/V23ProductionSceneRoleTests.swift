import Foundation
import SwiftData
import XCTest
@testable import FieldEvidenceApp

final class V23ProductionSceneRoleTests: XCTestCase {
    @MainActor
    func testRoundSessionUsesCanonicalHistoryAndRejectsTerminalResume() throws {
        let fixture = try makeStore("round")
        defer { try? FileManager.default.removeItem(at: fixture.support) }
        let store = fixture.store
        let actor = try makeActor(workspaceID: store.workspaceID, at: baseDate)
        let release = try C21ClientCapabilityTestSupport.publishedRelease(
            workflowID: "v23.navigation.round"
        )
        let requirement = try RoundPackageContentRequirementV1(
            packageRelease: RoundPackageReleaseReferenceV1(release),
            requiredContent: []
        )
        let pending = try RoundItemV1(
            itemID: UUID(), order: 0,
            selection: RoundAssetSelectionV1(
                assetID: UUID(), siteID: UUID(), labelAtSelection: "Role fixture asset"
            ),
            requirement: requirement
        )
        let sessionID = UUID()
        func session(
            _ predecessor: RoundSessionV1?,
            revision: UInt64,
            state: RoundSessionStateV1,
            transition: RoundSessionTransitionV1,
            item: RoundItemV1,
            transitionItemID: UUID? = nil
        ) throws -> RoundSessionV1 {
            try RoundSessionV1(
                workspaceID: store.workspaceID, sessionID: sessionID,
                predecessor: predecessor, revision: revision,
                mutationID: try mutation(), state: state, transition: transition,
                transitionItemID: transitionItemID, items: [item],
                recordedBy: actor,
                recordedAt: baseDate.addingTimeInterval(TimeInterval(revision))
            )
        }
        let draft = try session(nil, revision: 1, state: .draft,
                                transition: .create, item: pending)
        let active = try session(draft, revision: 2, state: .active,
                                 transition: .start, item: pending)
        let visit = try RoundItemVisitV1(
            visitedAt: baseDate.addingTimeInterval(3), recordedBy: actor
        )
        let visitedItem = try RoundItemV1(
            itemID: pending.itemID, order: pending.order,
            selection: pending.selection, requirement: pending.requirement,
            disposition: .visited, visit: visit
        )
        let visited = try session(active, revision: 3, state: .active,
                                  transition: .visitItem, item: visitedItem,
                                  transitionItemID: pending.itemID)
        let completedItem = try RoundItemV1(
            itemID: pending.itemID, order: pending.order,
            selection: pending.selection, requirement: pending.requirement,
            disposition: .completed, visit: visit,
            completion: try RoundItemCompletionReferenceV1(
                completionID: UUID(), revision: 1,
                completionSHA256: digest("round-completion")
            )
        )
        let itemCompleted = try session(
            visited, revision: 4, state: .active, transition: .completeItem,
            item: completedItem, transitionItemID: pending.itemID
        )
        let completed = try session(itemCompleted, revision: 5, state: .completed,
                                    transition: .close, item: completedItem)
        let archived = try session(completed, revision: 6, state: .archived,
                                   transition: .archive, item: completedItem)
        for value in [draft, active, visited, itemCompleted, completed, archived] {
            store.modelContext.insert(try RoundSessionRevisionRowV1(value))
        }
        try store.modelContext.save()

        let read = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .work,
            stableSessionID: sessionID, expectedRevision: archived.revision
        )
        let terminalResume = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .work,
            stableSessionID: sessionID, requestedMode: .resume,
            expectedRevision: archived.revision
        )
        let stale = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .work,
            stableSessionID: sessionID, expectedRevision: completed.revision
        )
        try assertReadOnlyResolution(
            [read: nil, terminalResume: .invalidTarget, stale: .staleRevision],
            store: store, registry: try RouteRegistryV1()
        )
        XCTAssertEqual(
            try store.modelContext.fetchCount(FetchDescriptor<RoundSessionRevisionRowV1>()), 6
        )
    }

    @MainActor
    func testScheduleUsesCanonicalReleaseAndOccurrenceLifecycle() throws {
        let fixture = try makeStore("schedule")
        defer { try? FileManager.default.removeItem(at: fixture.support) }
        let store = fixture.store
        let actor = try makeActor(workspaceID: store.workspaceID, at: baseDate)
        let packageRelease = try C21ClientCapabilityTestSupport.publishedRelease(
            workflowID: "v23.navigation.schedule"
        )
        let definition = try C26SurveySessionTestSupport.release(
            releaseSlot: 23_001, workspaceID: store.workspaceID,
            ownerPackageID: packageRelease.packageID
        )
        let timeBasis = try FrozenScheduleTimeBasisV1(
            ianaTimeZoneIdentifier: "UTC",
            timeZoneRuleSetVersion: "v23-navigation-fixture-v1",
            timeZoneRuleSetSHA256: digest("schedule-time-zone"),
            ambiguousTimePolicy: .earlierOffset,
            nonexistentTimePolicy: .shiftForwardByGap,
            calendarBasisSHA256: digest("schedule-calendar")
        )
        let schedule = try ScheduleDefinitionReleaseV1(
            scheduleDefinitionID: UUID(), releaseID: UUID(),
            workspaceID: store.workspaceID, occurrenceIdentityNamespaceID: UUID(),
            action: .create, lifecycleState: .active,
            recurrence: .fixedCalendar(FixedCalendarScheduleRuleV1(
                cadence: .daily, interval: 1,
                anchor: ScheduleLocalAnchorV1(
                    year: nil, month: nil, day: nil, weekday: nil,
                    weekdayOrdinal: nil, hour: 9, minute: 0, second: 0
                )
            )),
            timeBasis: timeBasis, startsAtUTC: baseDate,
            generationHorizonDays: 30, maximumGeneratedOccurrences: 16,
            readyLeadSeconds: 3_600, overdueGraceSeconds: 7_200,
            subject: WorkSubjectReferenceV1(
                kind: .asset, subjectID: UUID(), revision: 1, ownerAssetID: nil
            ),
            workDefinition: try ScheduledWorkDefinitionReferenceV1(
                kind: .workPacket, definition: definition,
                packageRelease: packageRelease
            ),
            revision: 1, mutationID: try mutation(), authoredBy: actor,
            authoredAt: baseDate
        )
        func basis(day: Int, offset: TimeInterval) throws -> ResolvedOccurrenceBasisV1 {
            try ResolvedOccurrenceBasisV1(
                nominalLocalDate: String(format: "2027-01-%02d", day),
                nominalLocalTime: "09:00:00",
                resolvedAtUTC: baseDate.addingTimeInterval(offset),
                utcOffsetSeconds: 0, disposition: .unambiguous,
                timeBasisSHA256: timeBasis.canonicalSHA256(),
                adjustmentProvenanceSHA256: nil
            )
        }
        func generated(
            basis: ResolvedOccurrenceBasisV1,
            recordedAt: Date
        ) throws -> OccurrenceHistoryEventV1 {
            let occurrenceID = try OccurrenceIDV1(
                scheduleDefinitionID: schedule.scheduleDefinitionID,
                identityNamespaceID: schedule.occurrenceIdentityNamespaceID,
                nominalKey: basis.nominalKey
            )
            return try OccurrenceHistoryEventV1(
                eventID: UUID(), workspaceID: store.workspaceID,
                occurrenceID: occurrenceID,
                scheduleRelease: ScheduleDefinitionReleaseReferenceV1(schedule),
                action: .generated, nominalBasis: basis, effectiveBasis: basis,
                predecessor: nil, revision: 1, mutationID: try mutation(),
                recordedBy: actor, recordedAt: recordedAt
            )
        }
        let resumable = try generated(
            basis: basis(day: 15, offset: 86_400),
            recordedAt: baseDate.addingTimeInterval(10)
        )
        let skippedInitial = try generated(
            basis: basis(day: 16, offset: 172_800),
            recordedAt: baseDate.addingTimeInterval(20)
        )
        let skippedException = try ScheduleExceptionV1(
            exceptionID: UUID(), kind: .skipped,
            priorEffectiveBasisSHA256: ScheduleCanonicalCodecV1.sha256(
                skippedInitial.effectiveBasis
            ),
            reasonCode: "V23_NAVIGATION_SKIPPED", recordedBy: actor,
            recordedAt: baseDate.addingTimeInterval(21)
        )
        let skipped = try OccurrenceHistoryEventV1(
            eventID: UUID(), workspaceID: store.workspaceID,
            occurrenceID: skippedInitial.occurrenceID,
            scheduleRelease: skippedInitial.scheduleRelease,
            action: .applyException, nominalBasis: skippedInitial.nominalBasis,
            effectiveBasis: skippedInitial.effectiveBasis,
            exception: skippedException, predecessor: skippedInitial,
            revision: 2, mutationID: try mutation(), recordedBy: actor,
            recordedAt: baseDate.addingTimeInterval(21)
        )
        store.modelContext.insert(try ScheduleDefinitionReleaseRow(schedule))
        for value in [resumable, skippedInitial, skipped] {
            store.modelContext.insert(try OccurrenceHistoryEventRow(value))
        }
        try store.modelContext.save()

        let scheduleRead = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .work,
            stableScheduleDefinitionID: schedule.scheduleDefinitionID,
            stableScheduleReleaseID: schedule.releaseID,
            expectedScheduleRevision: schedule.revision
        )
        let resumableTarget = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .scheduleOccurrence,
            stableScheduleDefinitionID: schedule.scheduleDefinitionID,
            stableScheduleReleaseID: schedule.releaseID,
            stableOccurrenceID: resumable.occurrenceID, requestedMode: .resume,
            expectedScheduleRevision: schedule.revision,
            expectedOccurrenceRevision: resumable.revision
        )
        let skippedRead = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .scheduleOccurrence,
            stableScheduleDefinitionID: schedule.scheduleDefinitionID,
            stableScheduleReleaseID: schedule.releaseID,
            stableOccurrenceID: skipped.occurrenceID,
            expectedScheduleRevision: schedule.revision,
            expectedOccurrenceRevision: skipped.revision
        )
        let skippedResume = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .scheduleOccurrence,
            stableScheduleDefinitionID: schedule.scheduleDefinitionID,
            stableScheduleReleaseID: schedule.releaseID,
            stableOccurrenceID: skipped.occurrenceID, requestedMode: .resume,
            expectedScheduleRevision: schedule.revision,
            expectedOccurrenceRevision: skipped.revision
        )
        let staleOccurrence = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .scheduleOccurrence,
            stableScheduleDefinitionID: schedule.scheduleDefinitionID,
            stableScheduleReleaseID: schedule.releaseID,
            stableOccurrenceID: skipped.occurrenceID,
            expectedScheduleRevision: schedule.revision,
            expectedOccurrenceRevision: skippedInitial.revision
        )
        try assertReadOnlyResolution(
            [scheduleRead: nil, resumableTarget: nil, skippedRead: nil,
             skippedResume: .invalidTarget, staleOccurrence: .staleRevision],
            store: store, registry: try RouteRegistryV1()
        )
    }

    @MainActor
    func testSignoffUsesSupersessionAndSubjectRevision() throws {
        let fixture = try makeStore("signoff")
        defer { try? FileManager.default.removeItem(at: fixture.support) }
        let store = fixture.store
        let subjectID = UUID()
        let first = try SignoffSnapshotV1(
            snapshotID: UUID(), workspaceID: store.workspaceID,
            purpose: "V23 navigation signoff", subjectID: subjectID,
            subjectRevision: 1, disposition: .notRecorded, method: .noAssertion,
            recordedAt: baseDate, mutationID: try mutation()
        )
        let current = try SignoffSnapshotV1(
            snapshotID: UUID(), workspaceID: store.workspaceID,
            purpose: first.purpose, subjectID: subjectID,
            subjectRevision: 2, disposition: .notApplicable, method: .noAssertion,
            recordedAt: baseDate.addingTimeInterval(1),
            supersedesSnapshotID: first.snapshotID, mutationID: try mutation()
        )
        store.modelContext.insert(try SignoffSnapshotRow(first))
        store.modelContext.insert(try SignoffSnapshotRow(current, predecessor: first))
        try store.modelContext.save()

        let supersededEditor = try SignoffEditorRouteV1(
            workspaceID: store.workspaceID, signoffID: first.snapshotID,
            expectedRevision: first.subjectRevision
        ).target
        let historicRead = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .signoffHistory,
            stableEntityID: first.snapshotID, expectedRevision: first.subjectRevision
        )
        let currentEditor = try SignoffEditorRouteV1(
            workspaceID: store.workspaceID, signoffID: current.snapshotID,
            expectedRevision: current.subjectRevision
        ).target
        let staleCurrentEditor = try SignoffEditorRouteV1(
            workspaceID: store.workspaceID, signoffID: current.snapshotID,
            expectedRevision: first.subjectRevision
        ).target
        try assertReadOnlyResolution(
            [supersededEditor: .staleRevision, historicRead: nil,
             currentEditor: nil, staleCurrentEditor: .staleRevision],
            store: store, registry: try RouteRegistryV1()
        )
    }

    @MainActor
    func testPackageSurfaceUsesPromotionClosureAndCurrentDisposition() throws {
        let fixture = try makeStore("package")
        defer { try? FileManager.default.removeItem(at: fixture.support) }
        let store = fixture.store
        let package = try makePromotedPackage(workspaceID: store.workspaceID)
        store.modelContext.insert(try PromotedPackageReleaseRow(package.promoted))
        store.modelContext.insert(try PackageSandboxRunRow(package.sandbox))
        store.modelContext.insert(try PackagePromotionReceiptRow(package.receipt))
        store.modelContext.insert(try ActivePackageRegistryPointerRow(package.pointer))
        store.modelContext.insert(try PackageLifecycleDispositionRow(
            package.activeDisposition, release: package.release
        ))
        try store.modelContext.save()

        let route = PackageSurfaceRouteV1(
            routeID: "v23.navigation.package.surface", root: .work,
            destination: .packageSurface, kind: .destination,
            startsAutomaticWork: false
        )
        let registry = try RouteRegistryV1(manifests: [
            try PackageSurfaceManifestV1(
                packageID: package.release.packageID, routes: [route]
            )
        ])
        let target = try NavigationTargetV1(
            workspaceID: store.workspaceID, destination: .packageSurface,
            root: .work, packageSurfaceID: route.routeID
        )
        try assertReadOnlyResolution([target: nil], store: store, registry: registry)

        let withdrawn = try PackageLifecycleDispositionV1(
            dispositionID: UUID(), workspaceID: store.workspaceID,
            release: package.release, state: .withdrawn,
            reason: "V23 navigation withdrawal fixture",
            recordedAt: baseDate.addingTimeInterval(4),
            supersedesDispositionID: package.activeDisposition.dispositionID,
            revision: 2, mutationID: try mutation()
        )
        store.modelContext.insert(try PackageLifecycleDispositionRow(
            withdrawn, release: package.release
        ))
        try store.modelContext.save()
        try assertReadOnlyResolution(
            [target: .retiredOrMissingPackage], store: store, registry: registry
        )
    }

    @MainActor
    private func makeStore(_ role: String) throws -> (
        support: URL, store: StoreSessionCoordinator
    ) {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("V23-SceneRole-\(role)-\(UUID().uuidString)")
        let generation = try StoreGenerationFactory(
            applicationSupportURL: support
        ).openOrBootstrapCurrent()
        return (support, try StoreSessionCoordinator(validatingSession: generation))
    }

    @MainActor
    private func assertReadOnlyResolution(
        _ expected: [NavigationTargetV1: RouteFallbackReasonV1?],
        store: StoreSessionCoordinator,
        registry: RouteRegistryV1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let before = try store.workspaceWriter.currentRevision()
        let context = try ProductionSceneNavigationSourceV1.context(
            for: Array(expected.keys), in: store, registry: registry
        )
        for (target, reason) in expected {
            let result = try registry.resolve(target, context: context)
            XCTAssertEqual(result.reason, reason, file: file, line: line)
            XCTAssertEqual(
                result.disposition, reason == nil ? .resolved : .safeFallback,
                file: file, line: line
            )
            XCTAssertEqual(result.canonicalMutationCount, 0, file: file, line: line)
            XCTAssertFalse(result.startsAutomaticWork, file: file, line: line)
        }
        XCTAssertEqual(try store.workspaceWriter.currentRevision(), before, file: file, line: line)
        XCTAssertFalse(store.modelContext.hasChanges, file: file, line: line)
    }

    private var baseDate: Date { Date(timeIntervalSince1970: 1_800_100_000) }

    private func mutation() throws -> MutationIDV1 {
        try MutationIDV1(rawValue: UUID())
    }

    private func digest(_ value: String) -> String {
        KernelCanonicalHashV1.sha256(Data(value.utf8))
    }

    private func makeActor(workspaceID: WorkspaceID, at date: Date) throws
        -> ActorSnapshotV1 {
        let reference = try LocalActorReferenceV1(
            actorReferenceID: UUID(), workspaceID: workspaceID,
            displayName: "V23 navigation fixture recorder"
        )
        return try ActorSnapshotV1(
            snapshotID: UUID(), workspaceID: workspaceID, actor: reference,
            responsibility: .recordedBy,
            displayNameAtTime: reference.displayName, capturedAt: date
        )
    }

    private struct PromotedPackageFixture {
        let release: InspectionPackageReleaseV1
        let promoted: PromotedPackageReleaseV1
        let sandbox: PackageSandboxRunV1
        let pointer: ActivePackageRegistryPointerV1
        let receipt: PackagePromotionReceiptV1
        let activeDisposition: PackageLifecycleDispositionV1
    }

    private func makePromotedPackage(
        workspaceID: WorkspaceID
    ) throws -> PromotedPackageFixture {
        let release = try C21ClientCapabilityTestSupport.publishedRelease(
            workflowID: "v23.navigation.package"
        )
        let diff = try PackageSemanticDifferV1.diff(source: release, target: release)
        let mutationID = try mutation()
        let pointerStateSHA256 = digest("v23-no-active-package-pointer")
        let checks = PackageSandboxCheckKindV1.allCases.flatMap { kind in
            PackageSandboxFixtureShapeV1.allCases.map { shape in
                let fixtureID = "v23.\(kind.rawValue.lowercased()).\(shape.rawValue.lowercased())"
                return PackageSandboxCheckResultV1(
                    kind: kind, shape: shape, fixtureID: fixtureID,
                    fixtureSHA256: digest("fixture-\(fixtureID)"),
                    resultSHA256: digest("result-\(fixtureID)"),
                    disposition: .passed, activationEvidence: .notAttempted
                )
            }
        }
        let sandbox = try PackageSandboxRunV1(
            runID: UUID(), workspaceID: workspaceID,
            packageReleaseID: release.packageReleaseID,
            packageSHA256: release.packageSHA256,
            workflowSHA256: release.workflowSHA256,
            semanticDiffSHA256: diff.diffSHA256,
            exactHead: String(repeating: "c", count: 40),
            activePointerStateBeforeSHA256: pointerStateSHA256,
            activePointerStateAfterSHA256: pointerStateSHA256,
            checks: checks, mutationID: mutationID
        )
        let promoted = try PromotedPackageReleaseV1(
            releaseRecordID: UUID(), workspaceID: workspaceID,
            packageRelease: release, mutationID: mutationID,
            promotedAt: baseDate.addingTimeInterval(1)
        )
        let receiptID = UUID()
        let pointer = try ActivePackageRegistryPointerV1(
            pointerID: UUID(), workspaceID: workspaceID,
            packageID: release.packageID,
            activeReleaseRecordID: promoted.releaseRecordID,
            promotionReceiptID: receiptID,
            activePackageReleaseID: release.packageReleaseID,
            activeReleaseRecordSHA256: promoted.releaseRecordSHA256,
            revision: 1, mutationID: mutationID
        )
        let actor = try makeActor(workspaceID: workspaceID, at: baseDate)
        let receipt = try PackagePromotionReceiptV1(
            receiptID: receiptID, workspaceID: workspaceID,
            promotedRelease: promoted, sandboxRun: sandbox, diff: diff,
            predecessorPointer: nil, resultingPointer: pointer, actor: actor,
            exactHead: sandbox.exactHead, operation: .initialActivation,
            rollbackCompatibility: .activatedForwardFixRequired,
            mutationID: mutationID, recordedAt: baseDate.addingTimeInterval(2)
        )
        let activeDisposition = try PackageLifecycleDispositionV1(
            dispositionID: UUID(), workspaceID: workspaceID, release: release,
            state: .active, reason: "V23 navigation active fixture",
            recordedAt: baseDate.addingTimeInterval(3), mutationID: try mutation()
        )
        return PromotedPackageFixture(
            release: release, promoted: promoted, sandbox: sandbox,
            pointer: pointer, receipt: receipt,
            activeDisposition: activeDisposition
        )
    }
}
