import Foundation
import SwiftData
import SwiftUI

@MainActor
final class StoreSessionCoordinator: ObservableObject {
    @Published private(set) var uiGenerationToken: UInt64 = 0

    private var session: StoreGenerationSession
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private(set) var workspaceWriter: WorkspaceWriterV1

    init(
        session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1()
    ) {
        self.session = session
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.workspaceWriter = Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority
        )
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

    var workspaceQueryClient: any WorkspaceQueryClientV1 {
        workspaceWriter
    }

    func activate(session: StoreGenerationSession) {
        workspaceWriter.invalidate()
        self.session = session
        workspaceWriter = Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority
        )
        if uiGenerationToken < .max {
            uiGenerationToken += 1
        }
    }

    private static func makeWriter(
        session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1
    ) -> WorkspaceWriterV1 {
        do {
            let journalStore = try MutationJournalStoreV1(
                modelContext: session.modelContext,
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                allowStateBootstrap: false
            )
            try MutationReceiptRecoveryServiceV1(
                store: journalStore
            ).recoverBeforeWriterActivation()
            let revision = try WorkspaceRevisionV1(
                workspaceID: session.workspaceID,
                generationID: session.generationID,
                revision: 0,
                entityRevisions: []
            )
            return try WorkspaceWriterV1(
                identity: session.workspaceIdentity,
                generationID: session.generationID,
                initialRevision: revision,
                clock: clock,
                idSource: idSource,
                fileAuthority: fileAuthority,
                adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
                journalStore: journalStore
            )
        } catch {
            preconditionFailure("Store generation identity could not install WorkspaceWriterV1: \(error)")
        }
    }
}
