import Foundation
import SwiftData

@MainActor
struct ProductionSignWorkflow {
    let firstSign: FirstSignCoordinator
    let checkRunner: CheckRunnerCoordinator
    let reportDelivery: ReportDeliveryCoordinator
    let reportHistory: ReportHistoryCoordinator
    let work: WorkCoordinator
    let deletion: WholeSignDeletionService
}

@MainActor
final class ProductionCompositionRoot {
    private let modelContext: ModelContext
    private let generationRootURL: URL
    private let diagnosticsStore: DiagnosticsStore
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource

    init(
        modelContext: ModelContext,
        generationRootURL: URL,
        diagnosticsStore: DiagnosticsStore,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource()
    ) {
        self.modelContext = modelContext
        self.generationRootURL = generationRootURL.standardizedFileURL
        self.diagnosticsStore = diagnosticsStore
        self.clock = clock
        self.idSource = idSource
    }

    func makeSignWorkflow(
        signPack: SignPack,
        accessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil
    ) throws -> ProductionSignWorkflow {
        let storagePreflight = StoragePreflightService()
        let checkRunner = CheckRunnerCoordinator(
            modelContext: modelContext,
            signPack: signPack,
            diagnosticsStore: diagnosticsStore,
            storagePreflight: storagePreflight,
            draftAccessState: accessState
        )
        checkRunner.configureCapture(generationRootURL: generationRootURL)

        let reportDelivery = try ReportDeliveryCoordinator(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            diagnosticsStore: diagnosticsStore,
            signPack: signPack
        )
        let reportHistory = ReportHistoryCoordinator(
            modelContext: modelContext,
            deliveryCoordinator: reportDelivery
        )
        let work = try WorkCoordinator(
            modelContext: modelContext,
            signPack: signPack,
            generationRootURL: generationRootURL,
            checkRunnerCoordinator: checkRunner,
            storagePreflight: storagePreflight
        )
        let deletion = WholeSignDeletionService(
            modelContext: modelContext,
            generationRootURL: generationRootURL,
            now: clock.now,
            makeUUID: idSource.makeID
        )
        let firstSign = FirstSignCoordinator(
            modelContext: modelContext,
            diagnosticsStore: diagnosticsStore,
            signPack: signPack,
            accessState: accessState
        )
        return ProductionSignWorkflow(
            firstSign: firstSign,
            checkRunner: checkRunner,
            reportDelivery: reportDelivery,
            reportHistory: reportHistory,
            work: work,
            deletion: deletion
        )
    }
}
