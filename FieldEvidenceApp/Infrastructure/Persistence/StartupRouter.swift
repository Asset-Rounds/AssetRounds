import Foundation
import SwiftUI

enum StartupMaintenanceReason: String, CaseIterable, Error, Sendable {
    case dataPointerInvalid = "data_pointer_invalid"
    case dataGenerationMissing = "data_generation_missing"
    case finalizationInconsistent = "finalization_inconsistent"
    case mediaInconsistent = "media_inconsistent"
    case restoreInconsistent = "restore_inconsistent"
    case eraseInconsistent = "erase_inconsistent"
}

enum StartupStep: String, CaseIterable, Sendable {
    case erase
    case restore
    case currentOpen
    case finalization
    case deletion
    case media
    case pdf
}

@MainActor
final class StartupRouter: ObservableObject {
    enum Route {
        case checking
        case ready(StoreSessionCoordinator)
        case maintenance(StartupMaintenanceReason)
    }

    @Published private(set) var route: Route = .checking

    private let applicationSupportURL: URL
    private let generationFactory: StoreGenerationFactory
    private let diagnosticsStore: DiagnosticsStore
    private let fileManager: FileManager
    private let didBeginStep: (StartupStep) -> Void

    private var hasStarted = false
    private var isRunning = false

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default,
        didBeginStep: @escaping (StartupStep) -> Void = { _ in }
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.generationFactory = StoreGenerationFactory(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        self.diagnosticsStore = DiagnosticsStore(
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.didBeginStep = didBeginStep
    }

    func startIfNeeded() async {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        await retryChecks()
    }

    func retryChecks() async {
        guard !isRunning else {
            return
        }

        isRunning = true
        route = .checking
        defer { isRunning = false }

        do {
            didBeginStep(.erase)
            try requireNoPendingJournal(
                in: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceErase",
                    isDirectory: true
                ),
                reason: .eraseInconsistent
            )

            didBeginStep(.restore)
            try requireNoPendingJournal(
                in: applicationSupportURL.appendingPathComponent(
                    "FieldEvidenceRestore",
                    isDirectory: true
                ),
                reason: .restoreInconsistent
            )

            didBeginStep(.currentOpen)
            let session = try openCurrentGeneration()

            // These ordered checkpoints are intentionally inert until their
            // owning cards install the corresponding reconcilers.
            didBeginStep(.finalization)
            didBeginStep(.deletion)
            didBeginStep(.media)
            didBeginStep(.pdf)

            await diagnosticsStore.prepare()
            route = .ready(StoreSessionCoordinator(session: session))
        } catch let reason as StartupMaintenanceReason {
            route = .maintenance(reason)
        } catch {
            route = .maintenance(.dataPointerInvalid)
        }
    }

    private func openCurrentGeneration() throws -> StoreGenerationSession {
        do {
            return try generationFactory.openOrBootstrapCurrent()
        } catch let failure as StoreGenerationFailure {
            switch failure {
            case .dataPointerInvalid:
                throw StartupMaintenanceReason.dataPointerInvalid
            case .dataGenerationMissing:
                throw StartupMaintenanceReason.dataGenerationMissing
            }
        } catch {
            throw StartupMaintenanceReason.dataPointerInvalid
        }
    }

    private func requireNoPendingJournal(
        in rootURL: URL,
        reason: StartupMaintenanceReason
    ) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: rootURL.path,
            isDirectory: &isDirectory
        ) else {
            return
        }

        guard isDirectory.boolValue else {
            throw reason
        }

        let entries: [String]
        do {
            entries = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        } catch {
            throw reason
        }

        guard entries.isEmpty else {
            throw reason
        }
    }
}
