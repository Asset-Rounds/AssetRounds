import Foundation
import SwiftData
import SwiftUI
import UIKit
import XCTest
@testable import FieldEvidenceApp

final class V23_P04_C42PartyContactSiteRoleWorkflowUITests: V23ProductionFourRootShellTestSupport {
    private enum SemanticSelector {
        static let screen = "v23.p04.c42.party-contact-site-role.screen"
        static let party = "v23.p04.c42.party-contact-site-role.party"
        static let contacts = "v23.p04.c42.party-contact-site-role.contacts"
        static let preferred = "v23.p04.c42.party-contact-site-role.preferred"
        static let siteRole = "v23.p04.c42.party-contact-site-role.site-role"
        static let impactWarnings = "v23.p04.c42.party-contact-site-role.impact-warnings"
        static let history = "v23.p04.c42.party-contact-site-role.history"
        static let reversal = "v23.p04.c42.party-contact-site-role.reversal"
        static let boundaries = "v23.p04.c42.party-contact-site-role.boundaries"

        static let all = [screen, party, contacts, preferred, siteRole, impactWarnings, history, reversal, boundaries]
    }

    @MainActor
    func testV23P04C42SemanticSelectorContractIsClosedAndUnique() {
        let viewIdentifiers = [
            PartyContactSiteRoleWorkflowView.screenAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.partyAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.contactsAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.preferredAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.siteRoleAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.impactWarningsAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.historyAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.reversalAccessibilityIdentifier,
            PartyContactSiteRoleWorkflowView.boundariesAccessibilityIdentifier
        ]

        XCTAssertEqual(SemanticSelector.all.count, 9)
        XCTAssertEqual(Set(SemanticSelector.all).count, SemanticSelector.all.count)
        XCTAssertEqual(viewIdentifiers, SemanticSelector.all)
        XCTAssertTrue(SemanticSelector.all.allSatisfy {
            $0.hasPrefix("v23.p04.c42.party-contact-site-role.")
                && $0 == $0.lowercased()
                && !$0.contains(where: { $0.isWhitespace })
        })
    }

    @MainActor
    func testV23P04C42WorkflowInitializerBindsCoreContractShapes() {
        let impact: (PartyContactSiteRoleOperationV1) -> PartyContactSiteRoleOperationV1 = { $0 }
        let partyCommand: (PartyWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitParty($0) }
        let contactCommand: (OperationalContactWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitContact($0) }
        let siteRoleCommand: (SiteRoleWorkflowPreviewV1) -> PartyContactSiteRoleWorkflowCommandV1 = { .commitSiteRole($0) }
        let coordinator = PartyContactSiteRoleWorkflowCoordinatorV1.self
        let initializeSurface: (
            PartyWorkflowPreviewV1?,
            OperationalContactWorkflowPreviewV1?,
            SiteRoleWorkflowPreviewV1?,
            PartyContactSiteRoleHistoryProjectionV1?
        ) -> PartyContactSiteRoleWorkflowView = { party, contact, siteRole, history in
            PartyContactSiteRoleWorkflowView(
                partyPreview: party,
                contactPreview: contact,
                siteRolePreview: siteRole,
                history: history,
                onRequestPreview: { _ in },
                onConfirmPartyRetirement: { _ in },
                onConfirmContactRetirement: { _ in },
                onConfirmSiteRoleReversal: { _ in }
            )
        }

        XCTAssertNotNil(impact)
        XCTAssertNotNil(partyCommand)
        XCTAssertNotNil(contactCommand)
        XCTAssertNotNil(siteRoleCommand)
        XCTAssertNotNil(coordinator)
        XCTAssertNotNil(initializeSurface)
    }

    /// V23-P04-C42: app-hosted UNIT evidence of the Phase 1 boundary, not
    /// adoption of a live Party/contact route or a system permission journey.
    @MainActor
    func testV23P04C42WorkflowRemainsContainedBeforeS10() async throws {
        let fixture = try await makeFixture("c42-contained-manual-preview")
        defer { fixture.cleanUp() }
        let context = fixture.coordinator.modelContext
        let writer = fixture.coordinator.workspaceWriter
        let workspaceID = fixture.coordinator.workspaceID
        let now = Date(timeIntervalSince1970: 1_788_192_000)
        let setupReceiptCount = try context.fetchCount(FetchDescriptor<MutationReceiptRow>())
        let site = try await makeWorkAsset(in: fixture, label: "C42 explicit setup")
        XCTAssertTrue(try context.fetch(FetchDescriptor<ServicePartyRow>()).isEmpty,
            "Creating a Site/asset must not implicitly create a Party")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MutationReceiptRow>()), setupReceiptCount + 1)
        let seededSites = try context.fetch(FetchDescriptor<Site>()).filter { $0.id == site.siteID }
        XCTAssertEqual(seededSites.map(\.label), [site.siteLabel])
        let query = C42Query(context: context, workspaceID: workspaceID)
        let system = C42BoundarySystemHandoff()
        let contactQuery = OperationalContactRowQueryV1(modelContext: context, workspaceID: workspaceID)
        let contactCoordinator = OperationalContactCoordinatorV1(query: contactQuery, writer: writer,
            system: system, clock: SystemApplicationClock(), idSource: SystemApplicationIDSource(),
            importQuery: contactQuery)
        let workflow = PartyContactSiteRoleWorkflowCoordinatorV1(
            partyCoordinator: PartyAccountabilityCoordinatorV1(writer: writer, idSource: SystemApplicationIDSource()),
            contactCoordinator: contactCoordinator, query: query)
        let partyID = UUID(), phoneID = UUID(), seedRoleID = UUID()

        // Explicit fixture commands use the SAME published production writer.
        // They finish before the immutable measured baseline; previews below do
        // not execute their commands or implicitly create a Party for a Site.
        let seedParty = try await workflow.previewCreateParty(workspaceID: workspaceID,
            partyID: partyID, kind: .organization, displayName: "C42 synthetic operator",
            profileDescriptor: "Operational contact", effectiveAt: now,
            expectedRevision: c42Expected(writer, kind: .serviceParty, id: partyID),
            mutationID: writer.makeMutationID())
        guard case .party = try await workflow.execute(.commitParty(seedParty)) else {
            return XCTFail("Explicit C42 Party setup must commit through the existing writer")
        }
        let seedPhone = try await workflow.previewCreateContact(workspaceID: workspaceID,
            contactPointID: phoneID, partyID: partyID, kind: .phone, label: .work,
            displayValue: "+12125550142", preferred: true, effectiveAt: now,
            expectedRevision: c42Expected(writer, kind: .serviceContactPoint, id: phoneID),
            mutationID: writer.makeMutationID())
        guard case .contact = try await workflow.execute(.commitContact(seedPhone)) else {
            return XCTFail("Explicit C42 contact setup must commit through the existing writer")
        }
        let seedRole = try await workflow.previewAppendSiteRole(workspaceID: workspaceID,
            eventID: seedRoleID, siteID: site.siteID, partyID: partyID, role: .operator,
            effectiveFrom: now, recordedAt: now,
            expectedRevision: c42Expected(writer, kind: .sitePartyRoleEvent, id: seedRoleID),
            mutationID: writer.makeMutationID())
        guard case .siteRole = try await workflow.execute(.commitSiteRole(seedRole)) else {
            return XCTFail("Explicit C42 Site-role setup must commit through the existing writer")
        }
        let revisionBefore = try writer.currentRevision()
        let rowsBefore = try c42CanonicalRows(in: context)
        XCTAssertEqual(rowsBefore.parties.count, 1)
        XCTAssertEqual(rowsBefore.contacts.count, 1)
        XCTAssertEqual(rowsBefore.siteRoles.count, 1)
        XCTAssertEqual(rowsBefore.receipts.count, setupReceiptCount + 4, "First Sign, Party, contact and Site role are explicit setup only")
        XCTAssertTrue(rowsBefore.handoffIntents.isEmpty)
        XCTAssertTrue(system.requests.isEmpty)
        XCTAssertFalse(context.hasChanges)

        let proposedPartyID = UUID(), proposedContactID = UUID(), proposedRoleID = UUID()
        let partyPreview = try await workflow.previewCreateParty(workspaceID: workspaceID,
            partyID: proposedPartyID, kind: .person, displayName: "C42 manual preview only",
            profileDescriptor: "Operational contact", effectiveAt: now,
            expectedRevision: c42Expected(writer, kind: .serviceParty, id: proposedPartyID),
            mutationID: writer.makeMutationID())
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)
        let contactPreview = try await workflow.previewCreateContact(workspaceID: workspaceID,
            contactPointID: proposedContactID, partyID: partyID, kind: .email, label: .work,
            displayValue: "c42@example.test", preferred: true, effectiveAt: now,
            expectedRevision: c42Expected(writer, kind: .serviceContactPoint, id: proposedContactID),
            mutationID: writer.makeMutationID())
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)
        let rolePreview = try await workflow.previewAppendSiteRole(workspaceID: workspaceID,
            eventID: proposedRoleID, siteID: site.siteID, partyID: partyID, role: .serviceProvider,
            effectiveFrom: now, recordedAt: now,
            expectedRevision: c42Expected(writer, kind: .sitePartyRoleEvent, id: proposedRoleID),
            mutationID: writer.makeMutationID())
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(partyPreview.zeroWrite)
        XCTAssertTrue(contactPreview.zeroWrite)
        XCTAssertTrue(rolePreview.zeroWrite)
        XCTAssertEqual(partyPreview.impact.operation, .createParty)
        XCTAssertEqual(partyPreview.impact.affectedPartyIDs, [proposedPartyID])
        XCTAssertTrue(partyPreview.impact.affectedContactPointIDs.isEmpty)
        XCTAssertTrue(partyPreview.impact.affectedSiteRoleEventIDs.isEmpty)
        XCTAssertTrue(partyPreview.impact.preferredScopes.isEmpty)
        XCTAssertEqual(contactPreview.impact.operation, .createContact)
        XCTAssertEqual(contactPreview.impact.affectedPartyIDs, [partyID])
        XCTAssertEqual(contactPreview.impact.affectedContactPointIDs, [proposedContactID])
        XCTAssertTrue(contactPreview.impact.affectedSiteRoleEventIDs.isEmpty)
        XCTAssertEqual(contactPreview.impact.preferredScopes, contactPreview.mutation.preferredScopes)
        XCTAssertEqual(contactPreview.impact.preferredScopes.map(\.partyID), [partyID])
        XCTAssertEqual(contactPreview.impact.preferredScopes.map(\.kind), [.email])
        XCTAssertEqual(contactPreview.impact.preferredScopes.map(\.activeContactPointIDs), [[proposedContactID]])
        XCTAssertEqual(contactPreview.impact.preferredScopes.map(\.preferredContactPointID), [Optional(proposedContactID)])
        XCTAssertTrue(contactPreview.mutation.handoffIntents.isEmpty)
        XCTAssertEqual(rolePreview.impact.operation, .appendSiteRole)
        XCTAssertEqual(rolePreview.impact.affectedPartyIDs, [partyID])
        XCTAssertEqual(rolePreview.impact.affectedSiteRoleEventIDs, [proposedRoleID])
        XCTAssertTrue(rolePreview.impact.affectedContactPointIDs.isEmpty)
        XCTAssertTrue(rolePreview.impact.preferredScopes.isEmpty)
        for impact in [partyPreview.impact, contactPreview.impact, rolePreview.impact] {
            XCTAssertEqual(impact.cascadeCount, 0)
            XCTAssertEqual(impact.identityMergeCount, 0)
            XCTAssertEqual(impact.warnings, [.equalValuesRemainDistinct, .noCascade,
                .operationalPurposeOnly, .customerAndSiteLabelsArePresentationOnly])
        }
        let parties = try context.fetch(FetchDescriptor<ServicePartyRow>()).map { try $0.value() }
        let contacts = try context.fetch(FetchDescriptor<ServiceContactPointRow>()).map { try $0.value() }
        let roles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>()).map { try $0.value() }
        let history = try workflow.history(workspaceID: workspaceID,
            partyRevisions: parties, contactRevisions: contacts, siteRoleEvents: roles)
        XCTAssertEqual(history.partyRevisions, parties)
        XCTAssertEqual(history.contactRevisions, contacts)
        XCTAssertEqual(history.siteRoleEvents, roles)
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)

        let callbacks = C42BoundaryCallbacks()
        let surfaces = [
            callbacks.surface(party: partyPreview, history: history),
            callbacks.surface(contact: contactPreview, history: history),
            callbacks.surface(role: rolePreview, history: history)
        ]
        #if DEBUG
        // Check native tab identity/selection for all four persisted roots.
        // Dynamic C42 absence is tested only on Today and Work after their
        // actual loaded-content witnesses, plus Settings below. Assets/Reports
        // root-content/route containment remains PENDING, not inferred from tabs.
        // C42 has no gate case: no unrelated feature or allFeatures is borrowed.
        let scene = AppShellSceneStateV1(workspaceID: workspaceID,
            access: try XCTUnwrap(fixture.presentation.sceneNavigationAccess), registry: try RouteRegistryV1())
        try scene.restore()
        let titles = ["Today", "Work", "Assets", "Reports"]
        let identifiers = ["v23.tab.today", "v23.tab.work", "s1.tab.signs", "s1.tab.reports"]
        for (root, title) in zip(AppRootV1.frozenOrder, titles) {
            try scene.select(root)
            let bound = expectation(description: "Actual shipping C42 front door: \(title)")
            var observedTabBar: UITabBar?
            let mounted = try mountC42ShippingShell(fixture) { tabBar in
                guard observedTabBar == nil, tabBar.selectedItem?.title == title else { return }
                observedTabBar = tabBar
                bound.fulfill()
            }
            defer { mounted.unmount() }
            await fulfillment(of: [bound], timeout: 20)
            let tabBar = try XCTUnwrap(observedTabBar)
            XCTAssertEqual(tabBar.items?.map(\.title), titles.map(Optional.some))
            XCTAssertEqual(tabBar.items?.map(\.accessibilityIdentifier), identifiers.map(Optional.some))
            XCTAssertEqual(tabBar.selectedItem?.title, title)
            switch root {
            case .today, .work:
                let loadedRootIdentifier = root == .today
                    ? ProductionMyDayRootViewV1.phaseOneEmptyStateAccessibilityIdentifier
                    : ProductionWorkRootViewV1.screenAccessibilityIdentifier
                let rootContentMounted = await waitForMountedScreen(loadedRootIdentifier, from: mounted.host)
                XCTAssertTrue(rootContentMounted,
                    "Actual selected Today/Work content must load before a C42 absence assertion")
                XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)
            case .assets, .reports:
                // Their accepted tab controls are measured above. Current C42
                // content/route absence on these roots is not observed here.
                break
            }
            XCTAssertEqual(try writer.currentRevision(), revisionBefore)
            XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
            XCTAssertFalse(context.hasChanges)
            mounted.unmount()
        }
        let settings = try mountC42Settings(fixture)
        defer { settings.unmount() }
        let settingsMounted = await waitForMountedScreen(AppShellView.settingsScreenAccessibilityIdentifier,
            from: settings.host)
        XCTAssertTrue(settingsMounted, "Actual production Settings must load before a C42 absence assertion")
        XCTAssertFalse(nativeScreenObservation(SemanticSelector.screen, from: settings.host).found)
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)
        settings.unmount()

        // Each actual contained view displays one real, supplied preview. This
        // positive control makes the same C42 witness absence checks meaningful.
        for surface in surfaces {
            let mounted = try mountC42Content(AnyView(NavigationStack { surface }.modelContext(context)))
            defer { mounted.unmount() }
            let surfaceMounted = await waitForMountedScreen(SemanticSelector.screen, from: mounted.host)
            XCTAssertTrue(surfaceMounted, "Actual contained C42 view must load with a real preview")
            XCTAssertTrue(nativeScreenObservation(SemanticSelector.screen, from: mounted.host).found)
            XCTAssertTrue(callbacks.previewRequests.isEmpty)
            XCTAssertEqual(callbacks.confirmationCount, 0)
            XCTAssertTrue(system.requests.isEmpty)
            XCTAssertEqual(try writer.currentRevision(), revisionBefore)
            XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
            XCTAssertFalse(context.hasChanges)
            mounted.unmount()
        }
        #endif
        // Exercise the supplied request callback explicitly, not a native tap or
        // live adoption claim. Real preview generation above already used the
        // coordinator; these callbacks cannot execute or enroll handoff intents.
        for (surface, operation) in zip(surfaces, [PartyContactSiteRoleOperationV1.createParty,
                .createContact, .appendSiteRole]) {
            surface.onRequestPreview(operation)
        }
        XCTAssertEqual(callbacks.previewRequests, [.createParty, .createContact, .appendSiteRole])
        XCTAssertEqual(callbacks.confirmationCount, 0)
        XCTAssertTrue(system.requests.isEmpty)
        XCTAssertEqual(try writer.currentRevision(), revisionBefore)
        XCTAssertEqual(try c42CanonicalRows(in: context), rowsBefore)
        XCTAssertFalse(context.hasChanges)
    }

    @MainActor
    private func c42Expected(_ writer: WorkspaceWriterV1, kind: WorkspaceEntityKindV1,
                             id: UUID) throws -> WorkspaceExpectedRevisionV1 {
        let current = try writer.currentRevision()
        let identity = try WorkspaceEntityIdentityV1(kind: kind, id: id)
        var revisions = current.entityRevisions.filter { $0.identity != identity }
        revisions.append(WorkspaceEntityRevisionV1(identity: identity, revision: 0))
        return try .init(workspaceID: current.workspaceID, generationID: current.generationID,
            writerInstanceID: current.writerInstanceID, workspaceRevision: current.revision,
            entityRevisions: revisions.sorted { $0.identity.stableKey < $1.identity.stableKey })
    }

    @MainActor
    private func c42CanonicalRows(in context: ModelContext) throws -> C42BoundaryRows {
        // Copy immutable bytes now; retaining mutable SwiftData row objects
        // would let a later mutation change both sides of an equality assertion.
        let parties = try context.fetch(FetchDescriptor<ServicePartyRow>())
            .sorted { $0.partyID.uuidString < $1.partyID.uuidString }.map { row in
                _ = try row.value()
                return row.canonicalData
            }
        let contacts = try context.fetch(FetchDescriptor<ServiceContactPointRow>())
            .sorted { $0.contactPointID.uuidString < $1.contactPointID.uuidString }.map { row in
                _ = try row.value()
                return row.canonicalData
            }
        let roles = try context.fetch(FetchDescriptor<SitePartyRoleEventRow>())
            .sorted { $0.eventID.uuidString < $1.eventID.uuidString }.map { row in
                _ = try row.value()
                return row.canonicalData
            }
        let intents = try context.fetch(FetchDescriptor<SystemHandoffIntentRow>())
            .sorted { $0.intentID.uuidString < $1.intentID.uuidString }.map { row in
                _ = try row.value()
                return row.canonicalData
            }
        let receipts = try context.fetch(FetchDescriptor<MutationReceiptRow>())
            .sorted { $0.receiptIdentity < $1.receiptIdentity }.map { C42BoundaryReceipt($0) }
        return C42BoundaryRows(parties: parties, contacts: contacts, siteRoles: roles,
            handoffIntents: intents, receipts: receipts)
    }

    #if DEBUG
    @MainActor
    private func mountC42ShippingShell(_ fixture: V23ProductionMyDayPresentationHarness,
        onTabs: @escaping @MainActor (UITabBar) -> Void) throws -> SIG1MountedShellV1 {
        var shell = AppShellView(packLoadResult: .available(.illuminatedSignV1),
            storeSession: fixture.coordinator,
            contentAccess: try XCTUnwrap(fixture.presentation.renderAccess),
            sceneNavigationAccess: try XCTUnwrap(fixture.presentation.sceneNavigationAccess),
            myDayAccess: try XCTUnwrap(fixture.presentation.myDayAccess),
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            entitlementProcessor: fixture.router.entitlementProcessor)
        shell.onNativeTabsBoundForTesting = onTabs
        return try mountC42Content(AnyView(shell.modelContext(fixture.coordinator.modelContext)))
    }

    @MainActor
    private func mountC42Settings(_ fixture: V23ProductionMyDayPresentationHarness) throws -> SIG1MountedShellV1 {
        let processor = fixture.router.entitlementProcessor
        let settings = SettingsPlaceholderView(modelContext: fixture.coordinator.modelContext,
            generationRootURL: fixture.coordinator.generationRootURL,
            diagnosticsStore: fixture.diagnostics,
            metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter(manager: nil),
            feedbackConfiguration: .production, mailComposerAdapter: .unavailable,
            purchaseCoordinator: StoreKitPurchaseCoordinator(processor: processor,
                diagnosticsStore: fixture.diagnostics, catalogLinks: nil),
            lifecycleCoordinator: StoreKitLifecycleCoordinator(processor: processor))
        let section = ReminderSettingsSectionV1(access: try XCTUnwrap(fixture.presentation.reminderSettingsAccess))
        let contentAccess = try XCTUnwrap(fixture.presentation.renderAccess)
        return try mountC42Content(AnyView(NavigationStack {
            settings.reminderSettingsSectionForTesting(section, contentAccess: contentAccess)
        }
            .modelContext(fixture.coordinator.modelContext)))
    }

    @MainActor
    private func mountC42Content(_ content: AnyView) throws -> SIG1MountedShellV1 {
        let windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = windowScene.windows.first { $0.isKeyWindow }
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        return SIG1MountedShellV1(window: window, host: host, previousKeyWindow: previousKeyWindow)
    }
    #endif
}

private struct C42BoundaryRows: Equatable {
    let parties: [Data]
    let contacts: [Data]
    let siteRoles: [Data]
    let handoffIntents: [Data]
    let receipts: [C42BoundaryReceipt]
}

private struct C42BoundaryReceipt: Equatable {
    let mutationID: UUID
    let workspaceMutationKey: String
    let receiptIdentity: String
    let workspaceID: UUID
    let replicaID: UUID
    let localSequence: Int64
    let commandKind: String
    let envelopeData: Data
    let envelopeSHA256: String
    let receiptData: Data
    let receiptSHA256: String
    let reversalBasisData: Data?
    let reversalBasisSHA256: String?
    let semanticReversalData: Data?

    @MainActor
    init(_ row: MutationReceiptRow) {
        mutationID = row.mutationID
        workspaceMutationKey = row.workspaceMutationKey
        receiptIdentity = row.receiptIdentity
        workspaceID = row.workspaceID
        replicaID = row.replicaID
        localSequence = row.localSequence
        commandKind = row.commandKind
        envelopeData = row.envelopeData
        envelopeSHA256 = row.envelopeSHA256
        receiptData = row.receiptData
        receiptSHA256 = row.receiptSHA256
        reversalBasisData = row.reversalBasisData
        reversalBasisSHA256 = row.reversalBasisSHA256
        semanticReversalData = row.semanticReversalData
    }
}

@MainActor
private final class C42BoundaryCallbacks {
    var previewRequests: [PartyContactSiteRoleOperationV1] = []
    var confirmationCount = 0

    func surface(party: PartyWorkflowPreviewV1? = nil,
                 contact: OperationalContactWorkflowPreviewV1? = nil,
                 role: SiteRoleWorkflowPreviewV1? = nil,
                 history: PartyContactSiteRoleHistoryProjectionV1) -> PartyContactSiteRoleWorkflowView {
        PartyContactSiteRoleWorkflowView(partyPreview: party, contactPreview: contact,
            siteRolePreview: role, history: history,
            onRequestPreview: { self.previewRequests.append($0) },
            onConfirmPartyRetirement: { _ in self.confirmationCount += 1 },
            onConfirmContactRetirement: { _ in self.confirmationCount += 1 },
            onConfirmSiteRoleReversal: { _ in self.confirmationCount += 1 })
    }
}

@MainActor
private final class C42BoundarySystemHandoff: SystemHandoffPortV1 {
    var requests: [SystemHandoffRequestV1] = []

    func handOff(_ request: SystemHandoffRequestV1) async -> SystemHandoffResultV1 {
        requests.append(request)
        return try! .init(intentID: request.intent.intentID, disposition: .systemUnavailable,
            evaluatedAt: Date(timeIntervalSince1970: 1_788_192_000))
    }
}
