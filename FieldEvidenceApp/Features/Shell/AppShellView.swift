import Foundation
import SwiftData
import SwiftUI
import UIKit

private struct EraseAllAction {
    let call: @MainActor () -> Void
}

private struct EraseAllActionKey: EnvironmentKey {
    static let defaultValue = EraseAllAction(call: {})
}

private extension EnvironmentValues {
    var eraseAllAction: EraseAllAction {
        get { self[EraseAllActionKey.self] }
        set { self[EraseAllActionKey.self] = newValue }
    }
}

private struct AppLockSettingsSectionKey: EnvironmentKey {
    static let defaultValue: AppLockSettingsSectionV1? = nil
}

private struct ReminderSettingsSectionKey: EnvironmentKey {
    static let defaultValue: ReminderSettingsSectionV1? = nil
}

private struct AppContentAccessKey: EnvironmentKey {
    static let defaultValue: AppAccessPresentationV1.ContentAccess? = nil
}

private extension EnvironmentValues {
    var appContentAccess: AppAccessPresentationV1.ContentAccess? {
        get { self[AppContentAccessKey.self] }
        set { self[AppContentAccessKey.self] = newValue }
    }
    var appLockSettingsSection: AppLockSettingsSectionV1? {
        get { self[AppLockSettingsSectionKey.self] }
        set { self[AppLockSettingsSectionKey.self] = newValue }
    }
    var reminderSettingsSection: ReminderSettingsSectionV1? {
        get { self[ReminderSettingsSectionKey.self] }
        set { self[ReminderSettingsSectionKey.self] = newValue }
    }
}

@MainActor
private struct ProductionShellComposition {
    let root: ProductionCompositionRoot
    let workflow: ProductionSignWorkflow
    let scene: AppShellSceneStateV1
    let myDaySources: ProductionMyDaySourceStateV1
    let completedWork: CompletedWorkPresentationV1
}

@MainActor
private struct ProductionSceneShellContentV1<Content: View>: View {
    @ObservedObject var scene: AppShellSceneStateV1
    let content: (AppShellSceneStateV1) -> Content

    var body: some View { content(scene) }
}

@MainActor
struct WorkAssetPreflightRouteAdmissionV1 {
    let target: NavigationTargetV1
    let workflow: ProductionSignWorkflow
    let scene: AppShellSceneStateV1
    let contentAccess: AppAccessPresentationV1.ContentAccess

    func isActiveWorkRoute() -> Bool {
        isAssetTarget
            && scene.snapshot?.selectedRoot == .work
            && scene.snapshot?.path(for: .work)?.targets == [target]
    }

    func loadForActivePresentation() throws -> FirstSignSnapshot {
        guard isActiveWorkRoute() else { throw AppAccessContractFailureV1.accessDenied }
        return try loadCurrentSnapshot(matching: nil, clearsRouteOnFactChange: false)
    }

    func validateBeforeBegin(displayedSnapshot: FirstSignSnapshot) throws {
        _ = try loadCurrentSnapshot(
            matching: displayedSnapshot,
            clearsRouteOnFactChange: true
        )
    }

    func cancel() throws {
        guard isActiveWorkRoute() else { return }
        workflow.checkRunner.clearPendingRecheckRequest()
        try scene.setPath([], for: .work)
    }

    private func loadCurrentSnapshot(
        matching displayed: FirstSignSnapshot?,
        clearsRouteOnFactChange: Bool
    ) throws -> FirstSignSnapshot {
        guard isAssetTarget else { throw AppAccessContractFailureV1.accessDenied }
        try scene.restore()
        guard let restoration = scene.lastRestoration,
              restoration.receipt.source == .sceneSnapshot,
              restoration.receipt.result.disposition == .resolved,
              restoration.receipt.result.target == target,
              isActiveWorkRoute() else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let fresh = try contentAccess.withRead {
            let matches = try workflow.firstSign.loadAll().filter { snapshot in
                snapshot.assetID == target.stableEntityID
            }
            guard matches.count == 1, let snapshot = matches.first else {
                throw AppAccessContractFailureV1.accessDenied
            }
            return snapshot
        }
        guard displayed == nil || displayed == fresh else {
            if clearsRouteOnFactChange { try scene.setPath([], for: .work) }
            throw AppAccessContractFailureV1.accessDenied
        }
        return fresh
    }

    private var isAssetTarget: Bool {
        target.destination == .work
            && target.root == .work
            && target.requestedMode == .read
            && target.stableEntityID != nil
            && target.stableScheduleDefinitionID == nil
            && target.stableScheduleReleaseID == nil
            && target.stableSessionID == nil
            && target.stableOccurrenceID == nil
            && target.stableLocationID == nil
            && target.packageSurfaceID == nil
            && target.draftResumeAnchor == nil
            && target.fieldPosition == nil
            && target.searchAnchor == nil
            && target.fallback.root == .work
            && target.fallback.destination == .work
    }
}

private struct WorkAssetPreflightTaskIdentityV1: Hashable {
    let target: NavigationTargetV1
    let isWorkSelected: Bool
}

@MainActor
private struct WorkAssetPreflightDestinationV1: View {
    let admission: WorkAssetPreflightRouteAdmissionV1
    @ObservedObject var scene: AppShellSceneStateV1
    let pack: SignPack
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter

    @State private var displayedSnapshot: FirstSignSnapshot?
    @State private var isUnavailable = false

    var body: some View {
        Group {
            if let displayedSnapshot {
                PreflightView(
                    snapshot: displayedSnapshot,
                    pack: pack,
                    coordinator: admission.workflow.checkRunner,
                    generationRootURL: generationRootURL,
                    usesImportedCaptureFixturesForUITest: usesImportedCaptureFixturesForUITest,
                    cameraAdapter: cameraAdapter,
                    beforeBeginRouteValidation: {
                        try admission.validateBeforeBegin(displayedSnapshot: displayedSnapshot)
                    },
                    cannotComplete: {
                        admission.workflow.checkRunner.clearPendingRecheckRequest()
                    },
                    cancel: cancel
                )
                #if DEBUG
                .onAppear {
                    print("WorkStartupDiagnostic preflight_appeared active=\(admission.isActiveWorkRoute()) selected_asset_matches=\(displayedSnapshot.assetID == admission.target.stableEntityID)")
                }
                #endif
            } else if isUnavailable {
                AssetRoundsEmptyState(
                    title: Text("Work unavailable"),
                    message: Text("Your current work could not be opened. Try again.")
                )
            } else {
                ProgressView("Opening work")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: WorkAssetPreflightTaskIdentityV1(
            target: admission.target,
            isWorkSelected: scene.snapshot?.selectedRoot == .work
        )) {
            #if DEBUG
            print("WorkStartupDiagnostic task_started work_selected=\(scene.snapshot?.selectedRoot == .work) active=\(admission.isActiveWorkRoute())")
            #endif
            guard admission.isActiveWorkRoute() else { return }
            displayedSnapshot = nil
            isUnavailable = false
            do {
                displayedSnapshot = try admission.loadForActivePresentation()
                #if DEBUG
                print("WorkStartupDiagnostic load_ready selected_asset_matches=\(displayedSnapshot?.assetID == admission.target.stableEntityID)")
                #endif
            } catch {
                #if DEBUG
                print("WorkStartupDiagnostic load_failed type=\(String(reflecting: type(of: error))) code=\((error as NSError).code)")
                #endif
                isUnavailable = true
            }
        }
    }

    private func cancel() {
        do {
            try admission.cancel()
        } catch {
            admission.scene.discardPresentation()
        }
    }
}

struct ReportsNavigationPresentationV1: Equatable {
    private var transientAnchor: [ReportHistoryRoute] = []
    private var transientRoutes: [ReportHistoryRoute] = []
    private var transientSnapshotID: UUID?

    mutating func setPresentedRoutes(
        _ routes: [ReportHistoryRoute],
        snapshotID: UUID?
    ) -> [ReportHistoryRoute] {
        let canonical: [ReportHistoryRoute] = Array(routes.prefix { route in
            switch route {
            case .report, .signoffHistory: return true
            case .comparison: return false
            }
        })
        transientAnchor = canonical
        transientRoutes = Array(routes.dropFirst(canonical.count))
        transientSnapshotID = snapshotID
        return canonical
    }

    mutating func reconcileCanonicalRoutes(
        _ canonical: [ReportHistoryRoute],
        snapshotID: UUID?
    ) {
        guard canonical == transientAnchor,
              snapshotID == transientSnapshotID else {
            reset()
            return
        }
    }

    mutating func refreshCanonicalSnapshot(
        from canonicalBefore: [ReportHistoryRoute],
        snapshotIDBefore: UUID?,
        to canonicalAfter: [ReportHistoryRoute],
        snapshotIDAfter: UUID?
    ) {
        guard transientAnchor == canonicalBefore,
              transientSnapshotID == snapshotIDBefore,
              canonicalAfter == transientAnchor else {
            reset()
            return
        }
        transientSnapshotID = snapshotIDAfter
    }

    func presentedRoutes(
        for canonical: [ReportHistoryRoute],
        snapshotID: UUID?
    ) -> [ReportHistoryRoute] {
        guard canonical == transientAnchor,
              snapshotID == transientSnapshotID else {
            return canonical
        }
        return canonical + transientRoutes
    }

    mutating func reset() {
        transientAnchor = []
        transientRoutes = []
        transientSnapshotID = nil
    }
}

struct AppShellView: View {
    static let screenAccessibilityIdentifier = "s1.shell.screen"
    static let signsTabAccessibilityIdentifier = "s1.tab.signs"
    static let todayTabAccessibilityIdentifier = "v23.tab.today"
    static let workTabAccessibilityIdentifier = "v23.tab.work"
    // Keep the incumbent automation identity when renaming the visible root.
    static let assetsTabAccessibilityIdentifier = signsTabAccessibilityIdentifier
    static let reportsTabAccessibilityIdentifier = "s1.tab.reports"
    static let settingsButtonAccessibilityIdentifier = "s1.settings.button"
    static let settingsScreenAccessibilityIdentifier = "s1.settings.screen"
    static let reportsPlaceholderAccessibilityIdentifier = "s1.reports.placeholder"
    static let unavailableAccessibilityIdentifier = "s1.pack.unavailable"

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.v23PhaseGate) private var phaseGate

    let packLoadResult: SignPackLoadResult
    let exposesColorSchemeForUITest: Bool
    let storeSession: StoreSessionCoordinator
    let contentAccess: AppAccessPresentationV1.ContentAccess
    let sceneNavigationAccess: AppAccessPresentationV1.SceneNavigationAccess
    let myDayAccess: AppAccessPresentationV1.MyDayAccess
    let roundAccess: AppAccessPresentationV1.RoundAccess?
    let diagnosticsStore: DiagnosticsStore
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter
    let usesImportedCaptureFixturesForUITest: Bool
    let injectsLowStorageFailureOnceForUITest: Bool
    let cameraAdapter: CameraAdapter
    let restoreDataBackup: @MainActor () -> Void
    let replaceDataBackup: @MainActor () -> Void
    let eraseAll: @MainActor () -> Void
    let appLockSettingsSection: AppLockSettingsSectionV1?
    let reminderSettingsSection: ReminderSettingsSectionV1?

    #if DEBUG
    /// Observes actual native tab binding; cannot supply composition or state.
    var onNativeTabsBoundForTesting: (@MainActor (UITabBar) -> Void)?
    /// Observes the established production scene; cannot supply composition or state.
    var onProductionSceneBoundForTesting: (@MainActor (AppShellSceneStateV1) -> Void)?
    #endif

    @StateObject private var purchaseCoordinator: StoreKitPurchaseCoordinator
    @StateObject private var lifecycleCoordinator: StoreKitLifecycleCoordinator

    @State private var productionComposition: ProductionShellComposition?
    @State private var productionCompositionErrorMessage: String?
    @StateObject private var savedReview = ProductionSavedReviewSheetStateV1()
    @State private var isComposingProductionWorkflow = false
    @State private var reportsPresentation = ReportsNavigationPresentationV1()

    private var modelContext: ModelContext { storeSession.modelContext }
    private var generationRootURL: URL { storeSession.generationRootURL }

    init(
        packLoadResult: SignPackLoadResult,
        exposesColorSchemeForUITest: Bool = false,
        storeSession: StoreSessionCoordinator,
        contentAccess: AppAccessPresentationV1.ContentAccess,
        sceneNavigationAccess: AppAccessPresentationV1.SceneNavigationAccess,
        myDayAccess: AppAccessPresentationV1.MyDayAccess,
        roundAccess: AppAccessPresentationV1.RoundAccess? = nil,
        diagnosticsStore: DiagnosticsStore,
        metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter,
        feedbackConfiguration: FeedbackConfigurationV1,
        mailComposerAdapter: MailComposerAdapter,
        usesImportedCaptureFixturesForUITest: Bool = false,
        injectsLowStorageFailureOnceForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        entitlementProcessor: StoreKitTransactionProcessor? = nil,
        paywallCatalogLinks: PaywallCatalogLinksV1? = nil,
        restoreDataBackup: @escaping @MainActor () -> Void = {},
        replaceDataBackup: @escaping @MainActor () -> Void = {},
        eraseAll: @escaping @MainActor () -> Void = {},
        appLockSettingsSection: AppLockSettingsSectionV1? = nil,
        reminderSettingsSection: ReminderSettingsSectionV1? = nil
    ) {
        self.packLoadResult = packLoadResult
        self.exposesColorSchemeForUITest = exposesColorSchemeForUITest
        self.storeSession = storeSession
        self.contentAccess = contentAccess
        self.sceneNavigationAccess = sceneNavigationAccess
        self.myDayAccess = myDayAccess
        self.roundAccess = roundAccess
        self.diagnosticsStore = diagnosticsStore
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        self.feedbackConfiguration = feedbackConfiguration
        self.mailComposerAdapter = mailComposerAdapter
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.injectsLowStorageFailureOnceForUITest =
            injectsLowStorageFailureOnceForUITest
        self.cameraAdapter = cameraAdapter
        _purchaseCoordinator = StateObject(
            wrappedValue: StoreKitPurchaseCoordinator(
                processor: entitlementProcessor,
                diagnosticsStore: diagnosticsStore,
                catalogLinks: paywallCatalogLinks
            )
        )
        _lifecycleCoordinator = StateObject(
            wrappedValue: StoreKitLifecycleCoordinator(
                processor: entitlementProcessor
            )
        )
        self.restoreDataBackup = restoreDataBackup
        self.replaceDataBackup = replaceDataBackup
        self.eraseAll = eraseAll
        self.appLockSettingsSection = appLockSettingsSection
        self.reminderSettingsSection = reminderSettingsSection
    }

    var body: some View {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--s6-3-ui-test-validation-summary")
            || arguments.contains("--s6-4-ui-test-export-source") {
            S6_3BackupValidationUITestHost(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                keepsPackageForRestoreUITest: arguments.contains(
                    "--s6-4-ui-test-export-source"
                )
            )
        } else {
            switch packLoadResult {
            case let .available(pack):
                availableShell(pack: pack)
            case .unavailable:
                PackUnavailableView()
                    .accessibilityIdentifier(Self.unavailableAccessibilityIdentifier)
            }
        }
    }

    private func availableShell(pack: SignPack) -> some View {
        Group {
            if let productionComposition {
                ProductionSceneShellContentV1(scene: productionComposition.scene) { scene in
                    Group {
                        if scene.snapshot != nil {
                            availableTabs(pack: pack, workflow: productionComposition.workflow,
                                scene: scene, sources: productionComposition.myDaySources,
                                completedWork: productionComposition.completedWork)
                        } else {
                            ProductionWorkflowUnavailableView(
                                message: "Navigation could not be restored safely.",
                                retry: { restoreScene(scene) })
                        }
                    }
                }
                .onDisappear { productionComposition.myDaySources.discard() }
            } else if let productionCompositionErrorMessage {
                ProductionWorkflowUnavailableView(
                    message: productionCompositionErrorMessage,
                    retry: { composeProductionWorkflow(pack: pack) }
                )
            } else {
                AssetRoundsScreenFoundation {
                    ProgressView("Opening your workspace")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel("Opening your workspace")
                }
            }
        }
        .task {
            composeProductionWorkflow(pack: pack)
        }
    }

    private func availableTabs(
        pack: SignPack,
        workflow: ProductionSignWorkflow,
        scene: AppShellSceneStateV1,
        sources: ProductionMyDaySourceStateV1,
        completedWork: CompletedWorkPresentationV1
    ) -> some View {
        TabView(selection: rootSelection(scene)) {
            SwiftUI.Tab(value: AppRootV1.today) {
                NavigationStack {
                    ProductionMyDayRootViewV1(source: sources)
                        .toolbar { settingsToolbar }
                }
            } label: {
                Label("Today", systemImage: "sun.max")
                    .accessibilityIdentifier(Self.todayTabAccessibilityIdentifier)
            }

            SwiftUI.Tab(value: AppRootV1.work) {
                NavigationStack(path: workPath(scene)) {
                    workRoot(scene: scene, sources: sources, completedWork: completedWork)
                        .sheet(item: Binding(get: { savedReview.route },
                            set: { if $0 == nil { savedReview.dismiss() } })) { route in
                            if let roundAccess {
                                ProductionRepetitiveCaptureReviewDestinationV1(
                                    reference: route.reference, access: roundAccess,
                                    validateIntent: {
                                        try savedReview.validateIntent(route, scene: scene,
                                            sceneAccess: sceneNavigationAccess)
                                    })
                            }
                        }
                        .alert("Saved draft unavailable", isPresented: Binding(
                            get: { savedReview.errorMessage != nil },
                            set: { if !$0 { savedReview.dismissError() } })) {
                            Button("OK", role: .cancel) { savedReview.dismissError() }
                        } message: {
                            Text(savedReview.errorMessage ?? "Refresh Work and try again.")
                        }
                        #if DEBUG
                        .onAppear { print("WorkStartupDiagnostic root_appeared") }
                        #endif
                        .toolbar { settingsToolbar }
                        .navigationDestination(for: NavigationTargetV1.self) { target in
                            if ProductionRoundSessionPresentationV1.accepts(target), let roundAccess {
                                ProductionRoundSessionDestinationV1(target: target, scene: scene,
                                    access: roundAccess)
                                    .id(target)
                            } else if isWorkAssetPreflightTarget(target) {
                            WorkAssetPreflightDestinationV1(
                                admission: WorkAssetPreflightRouteAdmissionV1(
                                    target: target,
                                    workflow: workflow,
                                    scene: scene,
                                    contentAccess: contentAccess
                                ),
                                scene: scene,
                                pack: pack,
                                generationRootURL: generationRootURL,
                                usesImportedCaptureFixturesForUITest:
                                    usesImportedCaptureFixturesForUITest,
                                cameraAdapter: cameraAdapter
                            )
                            } else {
                                AssetRoundsEmptyState(title: Text("Work unavailable"),
                                    message: Text("Your current work could not be opened. Try again."))
                            }
                        }
                }
            } label: {
                Label("Work", systemImage: "checklist")
                    .accessibilityIdentifier(Self.workTabAccessibilityIdentifier)
            }

            SwiftUI.Tab(value: AppRootV1.assets) {
                SignsRootView(
                    workflow: workflow,
                    modelContext: modelContext,
                    diagnosticsStore: diagnosticsStore,
                    metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                    feedbackConfiguration: feedbackConfiguration,
                    mailComposerAdapter: mailComposerAdapter,
                    pack: pack,
                    generationRootURL: generationRootURL,
                    usesImportedCaptureFixturesForUITest:
                        usesImportedCaptureFixturesForUITest,
                    cameraAdapter: cameraAdapter,
                    purchaseCoordinator: purchaseCoordinator,
                    lifecycleCoordinator: lifecycleCoordinator,
                    restoreDataBackup: restoreDataBackup,
                    replaceDataBackup: replaceDataBackup
                )
                .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
                .accessibilityValue(
                    Text(
                        verbatim: exposesColorSchemeForUITest
                            ? (colorScheme == .dark ? "Dark" : "Light")
                            : ""
                    )
                )
            } label: {
                Label("Assets", systemImage: "signpost.right.fill")
                    .accessibilityIdentifier(Self.assetsTabAccessibilityIdentifier)
            }

            SwiftUI.Tab(value: AppRootV1.reports) {
                NavigationStack(path: reportHistoryPath(scene)) {
                    ReportsRootView(
                        workflow: workflow,
                        loadSignoffHistory: signoffHistoryLoader(workflow)
                    )
                    .toolbar {
                        settingsToolbar
                    }
                }
                .onChange(of: scene.snapshot?.snapshotID) { _, _ in
                    reportsPresentation.reconcileCanonicalRoutes(
                        canonicalReportHistoryRoutes(in: scene),
                        snapshotID: scene.snapshot?.snapshotID
                    )
                }
            } label: {
                Label("Reports", systemImage: "doc.text.fill")
                    .accessibilityIdentifier(Self.reportsTabAccessibilityIdentifier)
            }
        }
        .background {
            nativeTabIdentifierBinder()
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .tint(DesignTokens.SemanticColors.primaryAction)
        .background(DesignTokens.SemanticColors.workBackground)
        .environment(\.eraseAllAction, EraseAllAction(call: eraseAll))
        .environment(\.appLockSettingsSection, appLockSettingsSection)
        .environment(\.reminderSettingsSection, reminderSettingsSection)
        .environment(\.appContentAccess, contentAccess)
    }

    /// The Work root with the SIG-1 Completed work section. Its detail and
    /// editor are local pushes; they never enter the saved Work path.
    private func workRoot(
        scene: AppShellSceneStateV1,
        sources: ProductionMyDaySourceStateV1,
        completedWork: CompletedWorkPresentationV1
    ) -> some View {
        let openRoundAction: ((MyDayEligibleReferenceV1) -> Void)? = roundAccess.map { _ in
            { reference in openRound(reference, in: scene) }
        }
        let openReviewAction: ((MyDayEligibleReferenceV1) -> Void)? = roundAccess.map { _ in
            { reference in openSavedReview(reference, in: scene) }
        }
        // Round and saved-draft rows open nothing while current work is gated.
        let showsWorkSources: Bool = phaseGate.allows(.workSources)
        return ProductionWorkRootViewV1(
            source: sources,
            openRound: showsWorkSources ? openRoundAction : nil,
            reviewAccess: roundAccess,
            openSavedReview: showsWorkSources ? openReviewAction : nil,
            completedWork: completedWork
        )
        .completedWorkNavigation(completedWork)
    }

    /// Every service call runs inside the current content-access read.
    private func signoffHistoryLoader(
        _ workflow: ProductionSignWorkflow
    ) -> CompletedWorkHistoryLoaderV1 {
        let access = contentAccess
        let service = workflow.completedWorkResponses
        return { signoffID in
            try access.withRead {
                try service.history(focusedSignoffID: signoffID)
            }
        }
    }

    /// Composes the SIG-1 presentation over the one workflow service. Each
    /// service call runs inside the current content-access read; the history
    /// scene transition runs outside it, as its own scene operation.
    private func makeCompletedWorkPresentation(
        workflow: ProductionSignWorkflow,
        scene: AppShellSceneStateV1
    ) -> CompletedWorkPresentationV1 {
        let access = contentAccess
        let service = workflow.completedWorkResponses
        let list: CompletedWorkListOperationV1 = {
            try access.withRead { try service.completedWork() }
        }
        let detail: CompletedWorkDetailOperationV1 = { key in
            try access.withRead { try service.subjectDetail(key) }
        }
        let prepare: CompletedWorkPrepareOperationV1 = { submission, proof in
            try access.withRead {
                try service.prepare(submission: submission, expectedProof: proof)
            }
        }
        let record: CompletedWorkRecordOperationV1 = { prepared in
            try access.withRead { service.record(prepared) }
        }
        let openHistory: CompletedWorkOpenHistoryOperationV1 = { route in
            do {
                try scene.open(try route.reportsTarget)
            } catch {
                productionCompositionErrorMessage = "Navigation could not be restored safely."
            }
        }
        return CompletedWorkPresentationV1(operations: CompletedWorkPresentationV1.Operations(
            list: list,
            detail: detail,
            prepare: prepare,
            record: record,
            openHistory: openHistory
        ))
    }

    private func nativeTabIdentifierBinder() -> NativeTabAccessibilityIdentifierBinder {
        let identifiers = [
            Self.todayTabAccessibilityIdentifier,
            Self.workTabAccessibilityIdentifier,
            Self.assetsTabAccessibilityIdentifier,
            Self.reportsTabAccessibilityIdentifier,
        ]
        #if DEBUG
        return NativeTabAccessibilityIdentifierBinder(identifiers: identifiers,
            onBoundForTesting: onNativeTabsBoundForTesting)
        #else
        return NativeTabAccessibilityIdentifierBinder(identifiers: identifiers)
        #endif
    }

    private func rootSelection(_ scene: AppShellSceneStateV1) -> Binding<AppRootV1> {
        Binding(get: { scene.snapshot?.selectedRoot ?? .today }, set: { root in
            do {
                let canonicalBefore = canonicalReportHistoryRoutes(in: scene)
                let snapshotIDBefore = scene.snapshot?.snapshotID
                try scene.select(root)
                reportsPresentation.refreshCanonicalSnapshot(
                    from: canonicalBefore,
                    snapshotIDBefore: snapshotIDBefore,
                    to: canonicalReportHistoryRoutes(in: scene),
                    snapshotIDAfter: scene.snapshot?.snapshotID
                )
            } catch {
                productionCompositionErrorMessage = "Navigation could not be restored safely."
            }
        })
    }

    private func reportHistoryPath(
        _ scene: AppShellSceneStateV1
    ) -> Binding<[ReportHistoryRoute]> {
        Binding(
            get: { reportHistoryRoutes(in: scene) },
            set: { routes in persistReportHistory(routes, in: scene) }
        )
    }

    private func workPath(
        _ scene: AppShellSceneStateV1
    ) -> Binding<[NavigationTargetV1]> {
        Binding(
            get: {
                guard let targets = scene.snapshot?.path(for: .work)?.targets,
                      targets.count == 1, let target = targets.first,
                      isSupportedWorkTarget(target) else { return [] }
                return [target]
            },
            set: { targets in persistWorkPath(targets, in: scene) }
        )
    }

    private func persistWorkPath(
        _ targets: [NavigationTargetV1],
        in scene: AppShellSceneStateV1
    ) {
        guard targets.count <= 1,
              targets.allSatisfy(isSupportedWorkTarget) else { return }
        let current = scene.snapshot?.path(for: .work)?.targets ?? []
        let presented = current.count == 1 && current.allSatisfy(isSupportedWorkTarget)
            ? current : []
        guard presented != targets else { return }
        do {
            if current.isEmpty, let target = targets.first {
                try scene.open(target)
            } else {
                try scene.setPath(targets, for: .work)
            }
        } catch {
            productionCompositionErrorMessage = "Navigation could not be restored safely."
        }
    }

    private func isSupportedWorkTarget(_ target: NavigationTargetV1) -> Bool {
        isWorkAssetPreflightTarget(target) || ProductionRoundSessionPresentationV1.accepts(target)
    }

    private func openRound(_ reference: MyDayEligibleReferenceV1, in scene: AppShellSceneStateV1) {
        guard case let .roundSession(workspaceID, sessionID, revision, _) = reference else { return }
        do {
            let target = try NavigationTargetV1(workspaceID: workspaceID, destination: .work,
                stableSessionID: sessionID, requestedMode: .read, expectedRevision: revision,
                fallback: NavigationFallbackV1(root: .work, destination: .work))
            try scene.open(target)
        } catch {
            productionCompositionErrorMessage = "Navigation could not be restored safely."
        }
    }

    private func openSavedReview(_ reference: MyDayEligibleReferenceV1,
                                 in scene: AppShellSceneStateV1) {
        guard let roundAccess else { return }
        savedReview.open(reference, scene: scene, sceneAccess: sceneNavigationAccess,
            access: roundAccess)
    }

    private func isWorkAssetPreflightTarget(
        _ target: NavigationTargetV1
    ) -> Bool {
        target.destination == .work
            && target.root == .work
            && target.requestedMode == .read
            && target.stableEntityID != nil
            && target.stableScheduleDefinitionID == nil
            && target.stableScheduleReleaseID == nil
            && target.stableSessionID == nil
            && target.stableOccurrenceID == nil
            && target.stableLocationID == nil
            && target.packageSurfaceID == nil
            && target.draftResumeAnchor == nil
            && target.fieldPosition == nil
            && target.searchAnchor == nil
            && target.fallback.root == .work
            && target.fallback.destination == .work
    }

    private func reportHistoryRoutes(
        in scene: AppShellSceneStateV1
    ) -> [ReportHistoryRoute] {
        let canonicalRoutes = canonicalReportHistoryRoutes(in: scene)
        return reportsPresentation.presentedRoutes(
            for: canonicalRoutes,
            snapshotID: scene.snapshot?.snapshotID
        )
    }

    private func canonicalReportHistoryRoutes(
        in scene: AppShellSceneStateV1
    ) -> [ReportHistoryRoute] {
        guard let targets = scene.snapshot?.path(for: .reports)?.targets else {
            return []
        }
        return targets.compactMap { target -> ReportHistoryRoute? in
            guard target.requestedMode == .read,
                  let entityID = target.stableEntityID else { return nil }
            switch target.destination {
            case .reports: return .report(entityID)
            case .signoffHistory: return .signoffHistory(entityID)
            default: return nil
            }
        }
    }

    private func persistReportHistory(
        _ routes: [ReportHistoryRoute],
        in scene: AppShellSceneStateV1
    ) {
        let canonicalBefore = canonicalReportHistoryRoutes(in: scene)
        let snapshotIDBefore = scene.snapshot?.snapshotID
        let canonicalRoutes = reportsPresentation.setPresentedRoutes(
            routes,
            snapshotID: scene.snapshot?.snapshotID
        )
        guard let targets = canonicalReportTargets(
            canonicalRoutes,
            preserving: scene
        ) else { return }
        let currentCanonicalRoutes = canonicalReportHistoryRoutes(in: scene)
        guard canonicalRoutes != currentCanonicalRoutes else { return }
        do {
            if canonicalRoutes.count == currentCanonicalRoutes.count + 1,
               let target = targets.last {
                try scene.open(target)
            } else {
                try scene.setPath(targets, for: .reports)
            }
            reportsPresentation.refreshCanonicalSnapshot(
                from: canonicalBefore,
                snapshotIDBefore: snapshotIDBefore,
                to: canonicalReportHistoryRoutes(in: scene),
                snapshotIDAfter: scene.snapshot?.snapshotID
            )
        } catch {
            reportsPresentation.reset()
            productionCompositionErrorMessage =
                "Navigation could not be restored safely."
        }
    }

    private func canonicalReportTargets(
        _ routes: [ReportHistoryRoute],
        preserving scene: AppShellSceneStateV1
    ) -> [NavigationTargetV1]? {
        let existing = scene.snapshot?.path(for: .reports)?.targets ?? []
        var targets: [NavigationTargetV1] = []
        for route in routes {
            switch route {
            case let .report(reportID):
                if let target = existing.first(where: {
                    $0.destination == .reports
                        && $0.requestedMode == .read
                        && $0.stableEntityID == reportID
                }) {
                    targets.append(target)
                } else if let target = try? NavigationTargetV1(
                    workspaceID: storeSession.workspaceID,
                    destination: .reports,
                    stableEntityID: reportID,
                    requestedMode: .read,
                    fallback: try NavigationFallbackV1(
                        root: .reports,
                        destination: .reports
                    )
                ) {
                    targets.append(target)
                } else { return nil }
            case let .signoffHistory(signoffID):
                if let target = existing.first(where: {
                    $0.destination == .signoffHistory
                        && $0.requestedMode == .read
                        && $0.stableEntityID == signoffID
                }) {
                    targets.append(target)
                } else if let target = try? SignoffHistoryRouteV1(
                    workspaceID: storeSession.workspaceID,
                    signoffID: signoffID
                ).reportsTarget {
                    targets.append(target)
                } else { return nil }
            case .comparison:
                return nil
            }
        }
        return targets
    }

    private func restoreScene(_ scene: AppShellSceneStateV1) {
        let priorCanonicalRoutes = canonicalReportHistoryRoutes(in: scene)
        let priorSnapshotID = scene.snapshot?.snapshotID
        do {
            try scene.restore()
            let restoredCanonicalRoutes = canonicalReportHistoryRoutes(in: scene)
            if restoredCanonicalRoutes == priorCanonicalRoutes {
                reportsPresentation.refreshCanonicalSnapshot(
                    from: priorCanonicalRoutes,
                    snapshotIDBefore: priorSnapshotID,
                    to: restoredCanonicalRoutes,
                    snapshotIDAfter: scene.snapshot?.snapshotID
                )
            } else {
                reportsPresentation.reset()
            }
        } catch {
            reportsPresentation.reset()
            productionCompositionErrorMessage = "Navigation could not be restored safely."
        }
    }

    @MainActor
    private func composeProductionWorkflow(pack: SignPack) {
        guard productionComposition == nil,
              !isComposingProductionWorkflow else { return }
        isComposingProductionWorkflow = true
        productionCompositionErrorMessage = nil
        do {
            let composed = try contentAccess.withRead {
            let registry = try WorkspacePackageLifecycleCompatibilityV1
                .legacyV3Registry(package: pack)
            let root = try ProductionCompositionRoot(
                storeSession: storeSession,
                diagnosticsStore: diagnosticsStore,
                profileRegistry: registry
            )
            let installedLifecycleCoordinator = lifecycleCoordinator
            let workflow = try root.makeSignWorkflow(
                signPack: pack,
                accessState: { installedLifecycleCoordinator.draftAccessState },
                injectsLowStorageFailureOnceForUITest:
                    injectsLowStorageFailureOnceForUITest
            )
            return (root: root, workflow: workflow)
            }
            // Scene operations own a distinct, nonrecursive capability hold.
            let scene = AppShellSceneStateV1(workspaceID: storeSession.workspaceID,
                access: sceneNavigationAccess, registry: try RouteRegistryV1())
            try scene.restore()
            let sources = ProductionMyDaySourceStateV1(workspaceID: storeSession.workspaceID,
                access: myDayAccess)
            let completedWork = makeCompletedWorkPresentation(workflow: composed.workflow,
                scene: scene)
            try contentAccess.withRead {
                productionComposition = ProductionShellComposition(root: composed.root,
                    workflow: composed.workflow, scene: scene, myDaySources: sources,
                    completedWork: completedWork)
            }
            #if DEBUG
            onProductionSceneBoundForTesting?(scene)
            #endif
        } catch {
            productionCompositionErrorMessage =
                "Your workspace could not be opened safely."
        }
        isComposingProductionWorkflow = false
    }

    @ToolbarContentBuilder
    private var settingsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsPlaceholderView(
                    modelContext: modelContext,
                    generationRootURL: generationRootURL,
                    diagnosticsStore: diagnosticsStore,
                    metricKitDiagnosticsAdapter: metricKitDiagnosticsAdapter,
                    feedbackConfiguration: feedbackConfiguration,
                    mailComposerAdapter: mailComposerAdapter,
                    purchaseCoordinator: purchaseCoordinator,
                    lifecycleCoordinator: lifecycleCoordinator,
                    restoreDataBackup: replaceDataBackup
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .frame(
                minWidth: DesignTokens.Target.minimumInteractiveWidth,
                minHeight: DesignTokens.Target.minimumInteractiveHeight
            )
            .contentShape(Rectangle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(Self.settingsButtonAccessibilityIdentifier)
        }
    }
}

private struct S6_3BackupValidationUITestHost: View {
    let modelContext: ModelContext
    let generationRootURL: URL
    let keepsPackageForRestoreUITest: Bool

    @State private var summary: BackupValidationSummaryV1?
    @State private var didStart = false

    var body: some View {
        Group {
            if let summary {
                BackupValidationSummaryView(summary: summary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .task {
            guard !didStart else { return }
            didStart = true
            loadValidatedSummary()
        }
    }

    @MainActor
    private func loadValidatedSummary() {
        do {
            let fileManager = FileManager.default
            let destination: URL
            if keepsPackageForRestoreUITest {
                destination = try BackupRestoreService.applicationSupportURL(
                    containing: generationRootURL
                ).appendingPathComponent(
                    "S6_4UITestSource",
                    isDirectory: true
                )
            } else {
                destination = fileManager.temporaryDirectory.appendingPathComponent(
                    "S6_3BackupValidationUITest",
                    isDirectory: true
                )
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            try materializeMixedFixture(fileManager: fileManager)
            let exporter = BackupExportService(
                modelContext: modelContext,
                generationRootURL: generationRootURL,
                now: { Date(timeIntervalSince1970: 1_786_708_800) }
            )
            let preview = try exporter.prepare()
            let packageURL = try exporter.export(
                previewID: preview.id,
                to: destination
            )
            let importer = try BackupImportService(
                generationRootURL: generationRootURL,
                scopedAccess: .alreadyAuthorized
            )
            let validatedPackage = try importer.stageAndValidate(
                selectedPackageURL: packageURL
            )
            try importer.discard(validatedPackage)
            summary = validatedPackage.summary
        } catch {
            summary = nil
        }
    }

    @MainActor
    private func materializeMixedFixture(fileManager: FileManager) throws {
        let issues = try modelContext.fetch(FetchDescriptor<Issue>())
        let records = try modelContext.fetch(FetchDescriptor<WorkflowRecord>())
        let reports = try modelContext.fetch(FetchDescriptor<Report>())
        guard issues.count == 1,
              let issue = issues.first,
              issue.status == IssueStatus.resolved.rawValue,
              let resolvedBy = issue.resolvedByRecordID,
              let opening = records.first(where: { $0.id == issue.openedByRecordID }),
              let recheck = records.first(where: {
                  $0.id == resolvedBy
                      && $0.stage == WorkflowStage.recheck.rawValue
                      && $0.revisionKind == WorkflowRevisionKind.original.rawValue
              }),
              let correction = records.first(where: {
                  $0.revisesRecordID == recheck.id
                      && $0.revisionKind == WorkflowRevisionKind.clericalCorrection.rawValue
              }),
              correction.evidenceSourceRecordID == recheck.id,
              let separate = records.first(where: {
                  $0.stage == WorkflowStage.check.rawValue
                      && $0.outcomeKey == "no_visible_issue"
                      && $0.issueID == nil
              }),
              let openingReport = reports.first(where: { $0.sourceRecordID == opening.id }),
              let recheckReport = reports.first(where: { $0.sourceRecordID == recheck.id }),
              let correctionReport = reports.first(where: { $0.sourceRecordID == correction.id }),
              let separateReport = reports.first(where: { $0.sourceRecordID == separate.id }),
              reports.count == 4,
              recheckReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.pdfState == ReportPDFState.ready.rawValue,
              correctionReport.replacesReportID == recheckReport.id else {
            throw BackupImportServiceError.invalidSource
        }

        try removeReadyPDF(openingReport, fileManager: fileManager)
        openingReport.pdfState = ReportPDFState.failed.rawValue
        openingReport.pdfRelativePath = nil
        openingReport.pdfSHA256 = nil
        try removeReadyPDF(separateReport, fileManager: fileManager)
        separateReport.pdfState = ReportPDFState.pending.rawValue
        separateReport.pdfRelativePath = nil
        separateReport.pdfSHA256 = nil

        modelContext.insert(Packet(
            id: UUID(uuidString: "63000000-0000-0000-0000-000000000089")!,
            stableRootID: UUID(uuidString: "63000000-0000-0000-0000-000000000090")!,
            currentRecordID: nil,
            evaluationCounted: true,
            contentDeletedAt: Date(timeIntervalSince1970: 1_735_689_590),
            createdAt: Date(timeIntervalSince1970: 1_735_689_500)
        ))
        try modelContext.save()
    }

    private func removeReadyPDF(
        _ report: Report,
        fileManager: FileManager
    ) throws {
        let expectedPath = "pdfs/\(report.id.uuidString.lowercased()).pdf"
        guard report.pdfState == ReportPDFState.ready.rawValue,
              report.pdfRelativePath == expectedPath,
              report.pdfSHA256 != nil else {
            throw BackupImportServiceError.invalidSource
        }
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: generationRootURL)
        let url = generationRootURL.appendingPathComponent(expectedPath)
        _ = try ReportPDFAnchoredFile.readRegularFile(
            at: url,
            within: generationRootURL,
            rootIdentity: rootIdentity
        )
        try fileManager.removeItem(at: url)
    }
}

struct SettingsPlaceholderView: View {
    private struct PaywallPresentation: Identifiable {
        let id = UUID()
    }

    private struct LifecyclePresentation: Identifiable {
        let id = UUID()
    }

    @Environment(\.eraseAllAction) private var eraseAllAction
    @Environment(\.appLockSettingsSection) private var appLockSettingsSection
    @Environment(\.reminderSettingsSection) private var reminderSettingsSection
    @Environment(\.appContentAccess) private var contentAccess
    @Environment(\.v23PhaseGate) private var phaseGate

    @ObservedObject var purchaseCoordinator: StoreKitPurchaseCoordinator
    @ObservedObject var lifecycleCoordinator: StoreKitLifecycleCoordinator

    let modelContext: ModelContext
    let generationRootURL: URL
    let diagnosticsStore: DiagnosticsStore
    let metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter
    let feedbackConfiguration: FeedbackConfigurationV1
    let mailComposerAdapter: MailComposerAdapter
    let restoreDataBackup: @MainActor () -> Void

    @State private var paywallPresentation: PaywallPresentation?
    @State private var lifecyclePresentation: LifecyclePresentation?

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        diagnosticsStore: DiagnosticsStore,
        metricKitDiagnosticsAdapter: MetricKitDiagnosticsAdapter,
        feedbackConfiguration: FeedbackConfigurationV1,
        mailComposerAdapter: MailComposerAdapter,
        purchaseCoordinator: StoreKitPurchaseCoordinator,
        lifecycleCoordinator: StoreKitLifecycleCoordinator,
        restoreDataBackup: @escaping @MainActor () -> Void = {}
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL
        self.diagnosticsStore = diagnosticsStore
        self.metricKitDiagnosticsAdapter = metricKitDiagnosticsAdapter
        self.feedbackConfiguration = feedbackConfiguration
        self.mailComposerAdapter = mailComposerAdapter
        self.purchaseCoordinator = purchaseCoordinator
        self.lifecycleCoordinator = lifecycleCoordinator
        self.restoreDataBackup = restoreDataBackup
    }

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text("Settings")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .accessibilityAddTraits(.isHeader)

                    if let appLockSettingsSection {
                        appLockSettingsSection
                    }
                    // Reminder owners stay wired (Erase still clears their
                    // notification mappings); only the Settings row is gated.
                    if let reminderSettingsSection, phaseGate.allows(.reminders) {
                        reminderSettingsSection
                    }

                if let contentAccess {
                AssetRoundsPrimaryNavigationLink("Back up current data") {
                    BackupExportView(
                        modelContext: modelContext,
                        generationRootURL: generationRootURL,
                        contentAccess: contentAccess
                    )
                }
                .accessibilityIdentifier(
                    BackupExportView.settingsEntryAccessibilityIdentifier
                )
                }

                AssetRoundsSecondaryAction("Restore data backup", action: restoreDataBackup)
                    .accessibilityLabel("Restore data backup")
                    .accessibilityIdentifier(
                        BackupRestoreProgressView.settingsEntryAccessibilityIdentifier
                    )

                AssetRoundsSecondaryAction("View subscription") {
                    paywallPresentation = PaywallPresentation()
                }
                .accessibilityLabel("View subscription")
                .accessibilityHint(
                    "Shows the monthly subscription without changing existing data"
                )
                .accessibilityIdentifier(
                    PaywallView.settingsEntryAccessibilityIdentifier
                )

                AssetRoundsSecondaryAction("Restore Purchases") {
                    lifecyclePresentation = LifecyclePresentation()
                }
                .accessibilityLabel("Restore Purchases")
                .accessibilityHint(
                    "Checks Apple purchase history without restoring inspection data"
                )
                .accessibilityIdentifier(
                    SubscriptionStatusView.settingsRestoreAccessibilityIdentifier
                )

                NavigationLink("View diagnostics") {
                    DiagnosticExportView(
                        diagnosticsStore: diagnosticsStore,
                        metricKitAdapter: metricKitDiagnosticsAdapter
                    )
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .frame(
                    minWidth: DesignTokens.Target.minimumInteractiveWidth,
                    minHeight: DesignTokens.Target.minimumInteractiveHeight
                )
                .accessibilityHint(
                    "Previews privacy-safe local counters and bounded system diagnostics before saving"
                )
                .accessibilityIdentifier(
                    DiagnosticExportView.settingsEntryAccessibilityIdentifier
                )

                NavigationLink("Send feedback") {
                    FeedbackView(
                        diagnosticsStore: diagnosticsStore,
                        metricKitAdapter: metricKitDiagnosticsAdapter,
                        configuration: feedbackConfiguration,
                        mailComposer: mailComposerAdapter
                    )
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .frame(
                    minWidth: DesignTokens.Target.minimumInteractiveWidth,
                    minHeight: DesignTokens.Target.minimumInteractiveHeight
                )
                .accessibilityHint(
                    "Reviews privacy-safe diagnostics and asks before attaching them to editable feedback"
                )
                .accessibilityIdentifier(
                    FeedbackView.settingsEntryAccessibilityIdentifier
                )

                Text("Inspection data and photos are device-local and do not sync with the subscription.")
                    .font(DesignTokens.Typography.secondaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    AssetRoundsSecondaryAction("Erase All", action: eraseAllAction.call)
                        .accessibilityLabel("Erase All")
                        .accessibilityIdentifier(
                            EraseAllView.settingsEntryAccessibilityIdentifier
                        )
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(AppShellView.settingsScreenAccessibilityIdentifier)
        .sheet(item: $paywallPresentation) { presentation in
            PaywallView(
                coordinator: purchaseCoordinator,
                presentationToken: presentation.id,
                close: { paywallPresentation = nil }
            )
        }
        .sheet(item: $lifecyclePresentation) { _ in
            NavigationStack {
                SubscriptionStatusView(
                    coordinator: lifecycleCoordinator,
                    startsRestoreOnAppear: true,
                    close: { lifecyclePresentation = nil }
                )
            }
        }
    }
}

#if DEBUG
extension SettingsPlaceholderView {
    /// Test hosts only: supplies a reminder section through the same private
    /// environment value the shell installs. It adds no route or state.
    func reminderSettingsSectionForTesting(
        _ section: ReminderSettingsSectionV1?
    ) -> some View {
        environment(\.reminderSettingsSection, section)
    }
}
#endif

private struct NativeTabAccessibilityIdentifierBinder:
    UIViewControllerRepresentable
{
    let identifiers: [String]

    #if DEBUG
    var onBoundForTesting: (@MainActor (UITabBar) -> Void)?
    #endif

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(identifiers: identifiers)
        #if DEBUG
        controller.onBoundForTesting = onBoundForTesting
        #endif
        return controller
    }

    func updateUIViewController(
        _ uiViewController: Controller,
        context: Context
    ) {
        uiViewController.identifiers = identifiers
        #if DEBUG
        uiViewController.onBoundForTesting = onBoundForTesting
        #endif
        uiViewController.bindAccessibilityIdentifiers()
    }

    final class Controller: UIViewController {
        var identifiers: [String]

        #if DEBUG
        var onBoundForTesting: (@MainActor (UITabBar) -> Void)?
        #endif

        init(identifiers: [String]) {
            self.identifiers = identifiers
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            bindAccessibilityIdentifiers()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            bindAccessibilityIdentifiers()
            DispatchQueue.main.async { [weak self] in
                self?.bindAccessibilityIdentifiers()
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            bindAccessibilityIdentifiers()
        }

        func bindAccessibilityIdentifiers() {
            guard let tabBar = tabBarController?.tabBar
                    ?? findTabBar(in: view.window),
                  let items = tabBar.items,
                  items.count == identifiers.count else {
                return
            }
            for (item, identifier) in zip(items, identifiers) {
                item.accessibilityIdentifier = identifier
            }
            #if DEBUG
            onBoundForTesting?(tabBar)
            #endif
        }

        private func findTabBar(in view: UIView?) -> UITabBar? {
            guard let view else { return nil }
            if let tabBar = view as? UITabBar { return tabBar }
            for subview in view.subviews {
                if let tabBar = findTabBar(in: subview) {
                    return tabBar
                }
            }
            return nil
        }
    }
}

private struct PackUnavailableView: View {
    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    Text("Content unavailable")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text("The bundled sign content could not be loaded.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    AssetRoundsStateLabel(
                        kind: .unavailable,
                        "No partial or guessed content is shown."
                    )
                    .accessibilityLabel("No partial or guessed content is shown.")
                    .accessibilityValue(Text(verbatim: String()))
                }
            }
        }
    }
}

private struct ProductionWorkflowUnavailableView: View {
    let message: String
    let retry: @MainActor () -> Void

    var body: some View {
        AssetRoundsScreenFoundation {
            ScrollView {
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(kind: .unavailable, "Unavailable")
                        .accessibilityLabel("Blocked: Unavailable")
                        .accessibilityValue(Text(verbatim: String()))

                    Text("Signs and reports unavailable")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(message)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    AssetRoundsPrimaryAction("Retry", action: retry)
                }
            }
        }
        .accessibilityIdentifier(AppShellView.unavailableAccessibilityIdentifier)
    }
}
