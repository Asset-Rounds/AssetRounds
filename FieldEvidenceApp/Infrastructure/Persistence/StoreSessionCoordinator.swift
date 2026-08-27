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
    private let generationFactory: StoreGenerationFactory
    private var writerLeaseHandle: GenerationLeaseHandleV1
    private(set) var workspaceWriter: WorkspaceWriterV1

    convenience init(
        session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1()
    ) {
        let resolvedFactory = StoreGenerationFactory(
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
        let binding: WriterBinding
        do {
            binding = try Self.makeWriter(
                session: session,
                clock: clock,
                idSource: idSource,
                fileAuthority: fileAuthority,
                generationFactory: resolvedFactory
            )
        } catch {
            preconditionFailure(
                "Store generation could not install its writer lease: \(error)"
            )
        }
        self.init(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory,
            binding: binding
        )
    }

    convenience init(
        validatingSession session: StoreGenerationSession,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1()
    ) throws {
        let resolvedFactory = StoreGenerationFactory(
            applicationSupportURL: Self.applicationSupportURL(for: session)
        )
        let binding = try Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory
        )
        self.init(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: resolvedFactory,
            binding: binding
        )
    }

    private init(
        session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        generationFactory: StoreGenerationFactory,
        binding: WriterBinding
    ) {
        self.session = session
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.generationFactory = generationFactory
        self.writerLeaseHandle = binding.leaseHandle
        self.workspaceWriter = binding.writer
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

    func packageLifecycleDependencies(
        profileRegistry: WorkspacePackageLifecycleProfileRegistryV1
    ) throws -> WorkspacePackageLifecycleDependenciesV1 {
        try WorkspacePackageLifecycleDependenciesV1(
            workspaceID: session.workspaceID,
            generationID: session.generationID,
            generationRootURL: session.generationRootURL,
            writer: workspaceWriter,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            profileRegistry: profileRegistry
        )
    }

    func activate(session: StoreGenerationSession) {
        do {
            try activateValidating(session: session)
        } catch {
            preconditionFailure(
                "Store generation could not replace its writer lease: \(error)"
            )
        }
    }

    func activateValidating(session: StoreGenerationSession) throws {
        guard Self.applicationSupportURL(for: session)
                == generationFactory.restoreApplicationSupportURL.standardizedFileURL else {
            throw GenerationLeaseRegistryFailureV1.invalidPath
        }
        let binding = try Self.makeWriter(
            session: session,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            generationFactory: generationFactory
        )
        try writerLeaseHandle.close()
        workspaceWriter.invalidate()
        self.session = session
        writerLeaseHandle = binding.leaseHandle
        workspaceWriter = binding.writer
        if uiGenerationToken < .max {
            uiGenerationToken += 1
        }
    }

    private struct WriterBinding {
        let writer: WorkspaceWriterV1
        let leaseHandle: GenerationLeaseHandleV1
    }

    private static func makeWriter(
        session: StoreGenerationSession,
        clock: any ApplicationClock,
        idSource: any ApplicationIDSource,
        fileAuthority: any ApplicationFileAuthorityV1,
        generationFactory: StoreGenerationFactory
    ) throws -> WriterBinding {
        guard let generationEpoch = session.generationEpoch else {
            throw GenerationLeaseRegistryFailureV1.staleGeneration
        }
        let registry = try generationFactory.makeGenerationLeaseRegistry()
        let leaseHandle = try registry.acquireHandle(
            epoch: generationEpoch,
            role: .writer
        )
        let writerLeaseToken: GenerationLeaseTokenV1 = leaseHandle.token
        let staleWriterFence: StaleWriterFenceV1
        do {
            staleWriterFence = try generationFactory.makeWriterFence(
                expectedGenerationEpoch: generationEpoch,
                writerLeaseToken: writerLeaseToken,
                registry: registry
            )
        } catch let fenceFailure {
            do {
                try leaseHandle.close()
            } catch let releaseFailure {
                throw releaseFailure
            }
            throw fenceFailure
        }
        let journalStore = try MutationJournalStoreV1(
            modelContext: session.modelContext,
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            allowStateBootstrap: false,
            staleWriterFence: staleWriterFence
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
        let writer = try WorkspaceWriterV1(
            identity: session.workspaceIdentity,
            generationID: session.generationID,
            initialRevision: revision,
            clock: clock,
            idSource: idSource,
            fileAuthority: fileAuthority,
            adapter: WorkspaceWriterAdapterV1(modelContext: session.modelContext),
            journalStore: journalStore
        )
        return WriterBinding(writer: writer, leaseHandle: leaseHandle)
    }

    private static func applicationSupportURL(
        for session: StoreGenerationSession
    ) -> URL {
        session.generationRootURL
            .deletingLastPathComponent() // generations
            .deletingLastPathComponent() // FieldEvidenceData
            .deletingLastPathComponent() // Application Support root
            .standardizedFileURL
    }
}
