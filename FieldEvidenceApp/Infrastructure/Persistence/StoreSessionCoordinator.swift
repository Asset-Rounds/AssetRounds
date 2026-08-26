import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StoreSessionCoordinator: ObservableObject {
    @Published private(set) var uiGenerationToken: UInt64 = 0

    private var session: StoreGenerationSession

    init(session: StoreGenerationSession) {
        self.session = session
    }

    var modelContext: ModelContext {
        session.modelContext
    }

    var generationID: UUID {
        session.generationID
    }

    var generationRootURL: URL {
        session.generationRootURL
    }

    var workspaceID: WorkspaceID {
        session.workspaceID
    }

    var replicaID: ReplicaID {
        session.replicaID
    }

    var workspaceIdentity: WorkspaceReplicaIdentityV1 {
        session.workspaceIdentity
    }

    func activate(session: StoreGenerationSession) {
        self.session = session
        if uiGenerationToken < .max {
            uiGenerationToken += 1
        }
    }
}
