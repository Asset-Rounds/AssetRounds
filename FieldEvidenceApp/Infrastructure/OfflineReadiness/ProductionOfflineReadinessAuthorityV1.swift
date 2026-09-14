import Foundation
import SwiftData
import UIKit

enum ProductionRoundReadinessUnavailableV1: Equatable, Sendable {
    case completionAuthorityUnavailable
    case fieldReferenceContentClosureUnavailable
    case staleFieldReferenceBinding
    case missingExactPackage
}

/// Canonical metadata acquired only inside the caller's fresh access-read
/// operation. No content bytes, readiness flag, or persistence is owned here.
struct ProductionOfflineReadinessSourceClosureV1: Encodable {
    struct AssetIdentity: Codable { let id: UUID; let siteID: UUID }
    let packages: [PromotedPackageReleaseV1]
    let assets: [AssetIdentity]
    let rounds: [RoundSessionV1]
    let releases: [FieldReferenceReleaseV1]
    let bindings: [FieldReferenceBindingV1]
    let localization: LocalizationKeyRegistryV1

    @MainActor init(context: ModelContext, workspaceID: WorkspaceID) throws {
        guard !context.hasChanges else { throw MyDaySourceReadFailureV1.sourcesChanged }
        let workspace = workspaceID.rawValue
        packages = try context.fetch(FetchDescriptor<PromotedPackageReleaseRow>(predicate: #Predicate { $0.workspaceID == workspace }))
            .map { try $0.value() }.sorted { $0.releaseRecordID.uuidString < $1.releaseRecordID.uuidString }
        assets = try context.fetch(FetchDescriptor<Asset>())
            .map { AssetIdentity(id: $0.id, siteID: $0.siteID) }.sorted { $0.id.uuidString < $1.id.uuidString }
        rounds = try context.fetch(FetchDescriptor<RoundSessionRevisionRowV1>(predicate: #Predicate { $0.workspaceID == workspace }))
            .map { try $0.value() }.sorted { ($0.sessionID.uuidString, $0.revision) < ($1.sessionID.uuidString, $1.revision) }
        releases = try context.fetch(FetchDescriptor<FieldReferenceReleaseRow>(predicate: #Predicate { $0.workspaceID == workspace }))
            .map { try $0.value() }.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
        let exactReleases = releases
        bindings = try context.fetch(FetchDescriptor<FieldReferenceBindingRow>(predicate: #Predicate { $0.workspaceID == workspace }))
            .map { row in
                let matches = exactReleases.filter { $0.releaseID == row.releaseID }
                guard matches.count == 1, let release = matches.first else {
                    throw MyDaySourceReadFailureV1.corruptSourceClosure
                }
                return try row.value(release: release)
            }.sorted { $0.bindingID.uuidString < $1.bindingID.uuidString }
        localization = try BundledLocalizationCatalogV1.registry()
        try localization.validate()
        guard Set(packages.map(\.releaseRecordID)).count == packages.count,
              Set(packages.map { $0.packageRelease.packageReleaseID }).count == packages.count,
              Set(assets.map(\.id)).count == assets.count,
              Set(releases.map(\.releaseID)).count == releases.count,
              Set(bindings.map(\.bindingID)).count == bindings.count else {
            throw MyDaySourceReadFailureV1.corruptSourceClosure
        }
        for (id, history) in Dictionary(grouping: rounds, by: \.sessionID) {
            _ = try RoundSessionHistoryValidatorV1.validate(history, workspaceID: workspaceID, sessionID: id)
        }
        for release in releases {
            if let predecessorID = release.supersedesReleaseID {
                guard let predecessor = releases.first(where: { $0.releaseID == predecessorID }) else {
                    throw MyDaySourceReadFailureV1.corruptSourceClosure
                }
                try release.validateSuccessor(of: predecessor)
            }
            guard releases.filter({ $0.supersedesReleaseID == release.releaseID }).count <= 1 else {
                throw MyDaySourceReadFailureV1.corruptSourceClosure
            }
        }
        for binding in bindings {
            if let predecessorID = binding.supersedesBindingID {
                guard let predecessor = bindings.first(where: { $0.bindingID == predecessorID }),
                      let release = releases.first(where: { $0.releaseID == binding.releaseID }) else {
                    throw MyDaySourceReadFailureV1.corruptSourceClosure
                }
                try binding.validateSuccessor(of: predecessor, release: release)
            }
            guard bindings.filter({ $0.supersedesBindingID == binding.bindingID }).count <= 1 else {
                throw MyDaySourceReadFailureV1.corruptSourceClosure
            }
        }
    }

    func sha256() throws -> String { try MyDayCanonicalCodecV1.sha256(self) }

    func package(for expected: RoundPackageReleaseReferenceV1) throws -> InspectionPackageReleaseV1? {
        guard let value = packages.first(where: { $0.packageRelease.packageReleaseID == expected.packageReleaseID }) else { return nil }
        try expected.validate(against: value.packageRelease)
        _ = try InspectionPackageCanonicalCodecV2.decode(value.packageRelease.canonicalPackageBytes)
        return value.packageRelease
    }

    func currentBindings(for session: RoundSessionV1) -> [FieldReferenceBindingV1] {
        let history = bindings.filter { $0.workspaceID == session.workspaceID && $0.subjectKind == .roundSession && $0.subjectID == session.sessionID }
        let superseded = Set(history.compactMap(\.supersedesBindingID))
        return history.filter { !superseded.contains($0.bindingID) }
    }
}

/// Immutable evidence retained only by one returned derived-read result. It
/// never grants access, reserves storage, or carries content bytes.
struct ProductionOfflineReadinessPublicationEvidenceV1 {
    let authorityID: UUID
    let operationToken: AppAccessGateV1.ContentReadToken
    let writerRevision: WorkspaceRevisionV1
    let sourceClosureSHA256: String
    let completionRootIdentity: ReportPDFAnchoredFile.RootIdentity?
}

struct ProductionOfflineReadinessReadResultV1 {
    let manifest: OfflineReadinessManifestV1
    let publicationEvidence: ProductionOfflineReadinessPublicationEvidenceV1
}

/// Concrete async readback of the incumbent round readiness owner. It does
/// not authenticate, admit work, reserve storage, or expose a cached permit.
@MainActor final class ProductionOfflineReadinessAuthorityV1 {
    private weak var session: StoreSessionCoordinator?
    private weak var originalWriter: WorkspaceWriterV1?
    private let workspaceID: WorkspaceID
    private let generationID: UUID
    private let uiGenerationToken: UInt64
    private let accessGate: AppAccessGateV1
    private let clock: any ApplicationClock
    private let ledger: OwnedStorageLedgerV1
    private let applicationSupportURL: URL
    private let content: EvidenceBundleStore
    /// Per-authority identity binds an immutable returned proof to this exact
    /// publication's readback owner, even when source rows remain unchanged.
    private let publicationAuthorityID = UUID()

    #if DEBUG
    /// Race-only boundary after canonical source observation and before the
    /// original access token is revalidated.
    var afterRoundSessionSourceObservationForTesting: (@MainActor () async throws -> Void)?
    /// Race-only boundary after readiness materialization and before its
    /// final original-token publication validation.
    var afterRoundReadinessMaterializationForTesting: (@MainActor () async throws -> Void)?
    #endif

    init(session: StoreSessionCoordinator, accessGate: AppAccessGateV1,
         clock: any ApplicationClock, ownedStorageLedger: OwnedStorageLedgerV1,
         expectedApplicationSupportURL: URL) {
        self.session = session; originalWriter = session.workspaceWriter
        workspaceID = session.workspaceID; generationID = session.generationID
        uiGenerationToken = session.uiGenerationToken; self.accessGate = accessGate
        self.clock = clock; ledger = ownedStorageLedger
        applicationSupportURL = expectedApplicationSupportURL
        content = EvidenceBundleStore(generationRootURL: session.generationRootURL)
    }

    /// Resolves an exact current session frontier using a fresh operation
    /// token. The caller's visible publication is fenced independently.
    func readSession(
        sessionID: UUID,
        expectedRevision: UInt64?
    ) async throws -> RoundSessionV1 {
        let token = try await accessGate.beginContentRead(for: .render)
        try Task.checkCancellation()
        let current = try currentSession()
        let writerRevision = try current.workspaceWriter.currentRevision()
        let initial = try ProductionOfflineReadinessSourceClosureV1(
            context: current.modelContext,
            workspaceID: workspaceID
        )
        let initialSHA = try initial.sha256()
        #if DEBUG
        if let afterRoundSessionSourceObservationForTesting {
            try await afterRoundSessionSourceObservationForTesting()
        }
        #endif
        guard let round = try RoundSessionHistoryValidatorV1.validate(
            initial.rounds.filter { $0.sessionID == sessionID },
            workspaceID: workspaceID,
            sessionID: sessionID
        ), expectedRevision.map({ $0 == round.revision }) ?? true else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.currentSessionUnavailable
        }
        try await accessGate.validateContentRead(token, for: .render)
        try Task.checkCancellation()
        let reread = try currentSession()
        guard try reread.workspaceWriter.currentRevision() == writerRevision,
              try ProductionOfflineReadinessSourceClosureV1(
                context: reread.modelContext,
                workspaceID: workspaceID
              ).sha256() == initialSHA else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        return round
    }

    /// Rebuilds the incumbent derived C19 manifest for an exact current
    /// frontier. It never creates a session successor or readiness record.
    func rebuildReadiness(
        for session: RoundSessionV1,
        previous: OfflineReadinessManifestV1?
    ) async throws -> ProductionOfflineReadinessReadResultV1 {
        #if DEBUG
        var rebuildStage = "session-validation"
        var rebuildCompleted = false
        defer {
            if !rebuildCompleted {
                print("ProductionOfflineReadinessAuthorityV1.rebuildReadiness phase=\(rebuildStage) completed=false")
            }
        }
        #endif
        try session.validateIntrinsic()
        guard session.workspaceID == workspaceID else {
            throw MyDayFailureV1.wrongWorkspace
        }
        #if DEBUG
        rebuildStage = "begin-content-read"
        #endif
        let token = try await accessGate.beginContentRead(for: .render)
        try Task.checkCancellation()
        #if DEBUG
        rebuildStage = "initial-source"
        #endif
        let current = try currentSession()
        let writerRevision = try current.workspaceWriter.currentRevision()
        let initial = try ProductionOfflineReadinessSourceClosureV1(
            context: current.modelContext,
            workspaceID: workspaceID
        )
        let initialSHA = try initial.sha256()
        #if DEBUG
        rebuildStage = "initial-frontier"
        #endif
        guard let initialRound = try RoundSessionHistoryValidatorV1.validate(
            initial.rounds.filter { $0.sessionID == session.sessionID },
            workspaceID: workspaceID,
            sessionID: session.sessionID
        ), try initialRound.reference == session.reference else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
        }
        let readback = RoundReadback(owner: self, token: token)
        let coordinator = OfflineReadinessPreflightCoordinatorV1(
            sessionReader: readback,
            authority: readback
        )
        #if DEBUG
        rebuildStage = "coordinator-rebuild"
        #endif
        let manifest = try await coordinator.rebuild(
            sessionID: session.sessionID,
            previous: previous
        )
        #if DEBUG
        rebuildStage = "manifest-frontier"
        #endif
        guard manifest.session == (try session.reference) else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
        }
        let reference = MyDayEligibleReferenceV1.roundSession(
            workspaceID: session.workspaceID,
            sessionID: session.sessionID,
            revision: session.revision,
            sessionSHA256: session.sessionSHA256
        )
        let assessment = MyDaySourceReadinessAssessmentV1(
            reference: reference,
            assessment: .roundManifest(manifest)
        )
        #if DEBUG
        rebuildStage = "completion-publication"
        #endif
        let completionRoot = try await validateCompletionsForPublication(
            [assessment],
            token: token
        )
        #if DEBUG
        rebuildStage = "materialization-hook"
        if let afterRoundReadinessMaterializationForTesting {
            try await afterRoundReadinessMaterializationForTesting()
        }
        rebuildStage = "final-content-read"
        #endif
        try await accessGate.validateContentRead(token, for: .render)
        try Task.checkCancellation()
        #if DEBUG
        rebuildStage = "final-source-frontier"
        #endif
        let reread = try currentSession()
        guard try reread.workspaceWriter.currentRevision() == writerRevision,
              try ProductionOfflineReadinessSourceClosureV1(
                context: reread.modelContext,
                workspaceID: workspaceID
              ).sha256() == initialSHA else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        #if DEBUG
        rebuildStage = "storage-publication"
        #endif
        try validateStorageForPublication(
            [assessment],
            expectedGenerationRootIdentity: completionRoot
        )
        #if DEBUG
        rebuildCompleted = true
        #endif
        return .init(
            manifest: manifest,
            publicationEvidence: .init(
                authorityID: publicationAuthorityID,
                operationToken: token,
                writerRevision: writerRevision,
                sourceClosureSHA256: initialSHA,
                completionRootIdentity: completionRoot
            )
        )
    }

    /// Synchronous final read fence used immediately before a caller exposes
    /// an already-read round frontier. It has no access-token hold of its own:
    /// the publication boundary owns that original hold.
    func validateSessionForPublication(_ expected: RoundSessionV1) throws {
        try expected.validateIntrinsic()
        guard expected.workspaceID == workspaceID else {
            throw MyDayFailureV1.wrongWorkspace
        }
        let current = try currentSession()
        _ = try current.workspaceWriter.currentRevision()
        let sources = try ProductionOfflineReadinessSourceClosureV1(
            context: current.modelContext,
            workspaceID: workspaceID
        )
        guard let actual = try RoundSessionHistoryValidatorV1.validate(
            sources.rounds.filter { $0.sessionID == expected.sessionID },
            workspaceID: workspaceID,
            sessionID: expected.sessionID
        ), try actual.reference == expected.reference else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
        }
    }

    /// Synchronous post-await fence for one returned readiness value. The
    /// caller supplies the original visible publication hold; this method
    /// only rechecks canonical/store/root/storage facts and never starts a
    /// second read or nests a content hold.
    func validateReadinessForPublication(
        _ evidence: ProductionOfflineReadinessPublicationEvidenceV1,
        manifest: OfflineReadinessManifestV1
    ) throws {
        guard evidence.authorityID == publicationAuthorityID else {
            throw AppAccessContractFailureV1.accessDenied
        }
        let current = try currentSession()
        guard try current.workspaceWriter.currentRevision() == evidence.writerRevision else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let sources = try ProductionOfflineReadinessSourceClosureV1(
            context: current.modelContext,
            workspaceID: workspaceID
        )
        guard try sources.sha256() == evidence.sourceClosureSHA256,
              let actual = try RoundSessionHistoryValidatorV1.validate(
                sources.rounds.filter { $0.sessionID == manifest.session.sessionID },
                workspaceID: workspaceID,
                sessionID: manifest.session.sessionID
              ), try actual.reference == manifest.session else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let assessment = MyDaySourceReadinessAssessmentV1(
            reference: .roundSession(
                workspaceID: workspaceID,
                sessionID: manifest.session.sessionID,
                revision: manifest.session.revision,
                sessionSHA256: manifest.session.sessionSHA256
            ),
            assessment: .roundManifest(manifest)
        )
        try validateStorageForPublication(
            [assessment],
            expectedGenerationRootIdentity: evidence.completionRootIdentity
        )
    }

    func assess(_ reference: MyDayEligibleReferenceV1) async throws -> MyDaySourceReadinessAssessmentV1 {
        let token = try await accessGate.beginContentRead(for: .render)
        try Task.checkCancellation()
        try reference.validate()
        guard reference.workspaceID == workspaceID else { throw MyDayFailureV1.wrongWorkspace }
        guard case let .roundSession(_, sessionID, revision, digest) = reference else {
            try await accessGate.validateContentRead(token, for: .render)
            _ = try currentSession()
            return .init(reference: reference, assessment: .notAssessed)
        }
        let current = try currentSession()
        let writerRevision = try current.workspaceWriter.currentRevision()
        let initial = try ProductionOfflineReadinessSourceClosureV1(context: current.modelContext, workspaceID: workspaceID)
        let initialSHA = try initial.sha256()
        let history = initial.rounds.filter { $0.sessionID == sessionID }
        guard let round = try RoundSessionHistoryValidatorV1.validate(history, workspaceID: workspaceID, sessionID: sessionID),
              round.revision == revision, round.sessionSHA256 == digest else {
            throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
        }
        let assessment: MyDayReadinessAssessmentV1
        if !(try completedItemsMatch(round, sources: initial)) {
            assessment = .unavailable(.completionAuthorityUnavailable)
        } else {
            let bindings = initial.currentBindings(for: round)
            let expectedState: FieldReferenceSubjectStateV1 = round.state == .completed || round.state == .archived ? .finalized : .active
            if bindings.contains(where: { $0.subjectRevision != round.revision || $0.subjectState != expectedState }) {
                assessment = .unavailable(.staleFieldReferenceBinding)
            } else if try await fieldReferenceReadiness(for: round, sources: initial,
                checkedAt: clock.now(), token: token) == nil {
                assessment = .unavailable(.fieldReferenceContentClosureUnavailable)
            } else if let expected = round.items.first?.requirement.packageRelease,
                      try initial.package(for: expected) != nil {
                let readback = RoundReadback(owner: self, token: token)
                let coordinator = OfflineReadinessPreflightCoordinatorV1(sessionReader: readback, authority: readback)
                assessment = .roundManifest(try await coordinator.rebuild(sessionID: sessionID))
            } else {
                assessment = .unavailable(.missingExactPackage)
            }
        }
        let result = MyDaySourceReadinessAssessmentV1(reference: reference, assessment: assessment)
        let completionRoot = try await validateCompletionsForPublication([result], token: token)
        try await accessGate.validateContentRead(token, for: .render)
        try Task.checkCancellation()
        let reread = try currentSession()
        guard try reread.workspaceWriter.currentRevision() == writerRevision,
              try ProductionOfflineReadinessSourceClosureV1(context: reread.modelContext, workspaceID: workspaceID).sha256() == initialSHA else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        try validateStorageForPublication([result], expectedGenerationRootIdentity: completionRoot)
        return result
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID, session.generationID == generationID,
              session.uiGenerationToken == uiGenerationToken else { throw MyDaySourceReadFailureV1.sessionChanged }
        guard !session.modelContext.hasChanges else { throw MyDaySourceReadFailureV1.sourcesChanged }
        return session
    }

    /// Reuses the actual current writer and finalizer's immutable snapshot
    /// readback. Package publication comes from the canonical source closure;
    /// an old completion with no recorded workflow correspondence stays absent.
    private func completedItemsMatch(
        _ round: RoundSessionV1,
        sources: ProductionOfflineReadinessSourceClosureV1
    ) throws -> Bool {
        let session = try currentSession()
        return try Self.completedItemsMatch(round, sources: sources, session: session)
    }

    /// Shared, exact Finalization readback proof used by readiness and the
    /// explicit round transition boundary. It deliberately validates every
    /// resolvable package group before reporting an unavailable sibling.
    static func completedItemsMatch(
        _ round: RoundSessionV1,
        sources: ProductionOfflineReadinessSourceClosureV1,
        session: StoreSessionCoordinator
    ) throws -> Bool {
        guard round.items.count <= RoundSessionLimitsV1.maximumItems else {
            throw MyDaySourceReadFailureV1.corruptSourceClosure
        }
        var packageOrder: [Data] = []
        var groups: [Data: [(request: FinalizationService.CompletedInspectionRequest,
                            expected: RoundItemCompletionReferenceV1)]] = [:]
        var allMatch = true
        for item in round.items {
            guard let completion = item.completion else { continue }
            guard let release = try sources.package(for: item.requirement.packageRelease),
                  release.packageID == ShippingIlluminatedSignAdapterV1.packageID else {
                allMatch = false
                continue
            }
            let bytes = release.canonicalPackageBytes
            if groups[bytes] == nil { packageOrder.append(bytes) }
            groups[bytes, default: []].append((.init(recordID: completion.completionID,
                expectedAssetID: item.selection.assetID, expectedRelease: release), completion))
        }
        for bytes in packageOrder {
            guard let group = groups[bytes] else { throw MyDaySourceReadFailureV1.corruptSourceClosure }
            let package = try InspectionPackageCanonicalCodecV2.decode(bytes)
            let signPack = try ShippingIlluminatedSignAdapterV1.signPack(from: package)
            let finalization = try FinalizationService(modelContext: session.modelContext,
                signPack: signPack, generationRootURL: session.generationRootURL,
                workspaceWriter: session.workspaceWriter)
            let actual = try finalization.completedInspectionReferences(requests: group.map(\.request))
            if actual.count != group.count || !zip(actual, group).allSatisfy({ $0.0 == $0.1.expected }) {
                allMatch = false
            }
        }
        // An unavailable item cannot hide a corrupt supported completion in
        // another group. Validate every resolvable group before returning.
        return allMatch
    }

    /// Canonical release facts select the existing immutable byte owner. A
    /// supported sibling is still verified when another entry is unavailable.
    private func fieldReferenceReadiness(for round: RoundSessionV1,
        sources: ProductionOfflineReadinessSourceClosureV1, checkedAt: Date,
        token: AppAccessGateV1.ContentReadToken) async throws -> [FieldReferenceOfflineReadinessV1]? {
        let pairs = try fieldReferenceBindings(for: round, sources: sources)
        let superseded = Set(sources.releases.compactMap(\.supersedesReleaseID))
        let revoked = Set(sources.releases.filter { $0.releaseDisposition == .revoked }.map(\.releaseID))
        var values: [FieldReferenceOfflineReadinessV1] = []
        var complete = true
        for (release, binding) in pairs {
            try Task.checkCancellation()
            _ = try currentSession().workspaceWriter.currentRevision()
            guard let metadata = release.importedContent else { complete = false; continue }
            var supported: [FieldReferenceImportedContentV1.Entry] = []
            for entry in metadata.entries {
                do {
                    guard try EvidenceBundleStore.fieldReferenceLocator(for: entry.reference) == entry.locator else {
                        complete = false; continue
                    }
                    supported.append(entry)
                } catch FieldReferencePackFailureV1.unsupported {
                    complete = false
                }
            }
            var present: [FieldReferenceImportedContentV1.Entry] = []
            if !supported.isEmpty {
                try await accessGate.validateContentRead(token, for: .render)
                try Task.checkCancellation()
                _ = try currentSession().workspaceWriter.currentRevision()
                present = try await content.readFieldReferenceContent(.init(entries: supported))
                try Task.checkCancellation()
                _ = try currentSession().workspaceWriter.currentRevision()
            }
            if supported.count != metadata.entries.count { continue }
            let inputs = FieldReferenceReadinessInputsV1(references: present.map(\.reference),
                locators: present.map(\.locator), knownSupersededReleaseIDs: superseded,
                knownRevokedReleaseIDs: revoked, evaluatedAt: checkedAt,
                protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
            let value = try FieldReferenceOfflineReadinessV1(release: release, binding: binding, inputs: inputs)
            try value.validate(recomputedFrom: inputs, release: release, binding: binding)
            values.append(value)
        }
        return complete ? values : nil
    }

    private func fieldReferenceBindings(for round: RoundSessionV1,
        sources: ProductionOfflineReadinessSourceClosureV1) throws
        -> [(release: FieldReferenceReleaseV1, binding: FieldReferenceBindingV1)] {
        let bindings = sources.currentBindings(for: round)
        guard bindings.count <= OfflineReadinessManifestLimitsV1.maximumFieldReferences else {
            throw MyDaySourceReadFailureV1.corruptSourceClosure
        }
        let state: FieldReferenceSubjectStateV1 = round.state == .completed || round.state == .archived ? .finalized : .active
        return try bindings.map { binding in
            guard binding.subjectRevision == round.revision, binding.subjectState == state,
                  let release = sources.releases.first(where: { $0.releaseID == binding.releaseID }) else {
                throw MyDaySourceReadFailureV1.sourcesChanged
            }
            try binding.validate(release: release)
            return (release, binding)
        }
    }

    /// Reads protected completion content before the caller's final validation
    /// of its original content-read token. No proof survives that operation.
    func validateCompletionsForPublication(_ assessments: [MyDaySourceReadinessAssessmentV1],
        token: AppAccessGateV1.ContentReadToken) async throws
        -> ReportPDFAnchoredFile.RootIdentity? {
        _ = try currentSession()
        let manifests = assessments.compactMap { record -> OfflineReadinessManifestV1? in
            if case let .roundManifest(manifest) = record.assessment { return manifest }
            return nil
        }
        guard !manifests.isEmpty else { return nil }
        let session = try currentSession()
        let rootIdentity = try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL)
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: session.modelContext, workspaceID: workspaceID)
        for manifest in manifests {
            guard let round = try RoundSessionHistoryValidatorV1.validate(
                sources.rounds.filter { $0.sessionID == manifest.session.sessionID },
                workspaceID: workspaceID, sessionID: manifest.session.sessionID),
                  try round.reference == manifest.session,
                  try completedItemsMatch(round, sources: sources) else {
                throw MyDaySourceReadFailureV1.sourcesChanged
            }
            guard let references = try await fieldReferenceReadiness(for: round, sources: sources,
                checkedAt: manifest.checkedAt, token: token) else {
                throw MyDaySourceReadFailureV1.sourcesChanged
            }
            let observations = try references.map(OfflineReadinessReferenceObservationV1.init)
                .sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
            let requirements = try fieldReferenceBindings(for: round, sources: sources).map { pair in
                let (release, binding) = pair
                return try OfflineReadinessFieldReferenceRequirementV1(workspaceID: release.workspaceID.rawValue.uuidString.lowercased(),
                    releaseID: release.releaseID, releaseRevision: release.revision, releaseSHA256: release.releaseSHA256,
                    manifestSHA256: release.manifestSHA256, bindingID: binding.bindingID,
                    bindingRevision: binding.revision, bindingSHA256: binding.bindingSHA256)
            }.sorted { $0.releaseID.uuidString < $1.releaseID.uuidString }
            guard observations == manifest.referenceObservations, requirements == manifest.expectedFieldReferences else {
                throw MyDaySourceReadFailureV1.sourcesChanged
            }
        }
        guard try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == rootIdentity else {
            #if DEBUG
            print("ProductionOfflineReadinessAuthorityV1.publication phase=completion-root rootComparisonPassed=false")
            #endif
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        return rootIdentity
    }

    /// Fresh metadata-only observation after the last awaited access check.
    /// Reservations are not canonical rows and need their own observation.
    func validateStorageForPublication(_ assessments: [MyDaySourceReadinessAssessmentV1],
        expectedGenerationRootIdentity: ReportPDFAnchoredFile.RootIdentity?) throws {
        let session = try currentSession()
        let manifests = assessments.compactMap { record -> OfflineReadinessManifestV1? in
            if case let .roundManifest(manifest) = record.assessment { return manifest }
            return nil
        }
        guard !manifests.isEmpty else { return }
        guard let expectedGenerationRootIdentity,
              try ReportPDFAnchoredFile.rootIdentity(at: session.generationRootURL) == expectedGenerationRootIdentity else {
            #if DEBUG
            print("ProductionOfflineReadinessAuthorityV1.publication phase=storage-root expectedRootPresent=\(expectedGenerationRootIdentity != nil) rootComparisonPassed=false")
            #endif
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let current = try ledger.observeOfflineReadiness(expectedApplicationSupportURL: applicationSupportURL)
        let protected = UIApplication.shared.isProtectedDataAvailable
        guard manifests.allSatisfy({ $0.storage == current && $0.protectedDataAvailable == protected }) else {
            #if DEBUG
            let storageMatches = manifests.allSatisfy { $0.storage == current }
            let protectedDataMatches = manifests.allSatisfy { $0.protectedDataAvailable == protected }
            print("ProductionOfflineReadinessAuthorityV1.publication phase=storage-protected-data storageMatches=\(storageMatches) protectedDataMatches=\(protectedDataMatches)")
            for (index, manifest) in manifests.enumerated() {
                let previous = manifest.storage
                print("ProductionOfflineReadinessAuthorityV1.storage index=\(index) field=capacityState before=\(previous.capacityState.rawValue) after=\(current.capacityState.rawValue)")
                print("ProductionOfflineReadinessAuthorityV1.storage index=\(index) field=availableBytes before=\(String(describing: previous.availableBytes)) after=\(String(describing: current.availableBytes))")
                print("ProductionOfflineReadinessAuthorityV1.storage index=\(index) field=reservedBytes before=\(previous.reservedBytes) after=\(current.reservedBytes)")
                print("ProductionOfflineReadinessAuthorityV1.storage index=\(index) field=operationReserveBytes before=\(previous.operationReserveBytes) after=\(current.operationReserveBytes)")
            }
            #endif
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let now = clock.now()
        let sources = try ProductionOfflineReadinessSourceClosureV1(context: session.modelContext, workspaceID: workspaceID)
        for manifest in manifests {
            guard now.timeIntervalSinceReferenceDate.isFinite, now >= manifest.checkedAt,
                  manifest.timeZoneIdentifier == TimeZone.current.identifier else {
                #if DEBUG
                let finiteNow = now.timeIntervalSinceReferenceDate.isFinite
                let notBeforeCheckedAt = now >= manifest.checkedAt
                let timeZoneComparisonFailed = finiteNow && notBeforeCheckedAt
                print("ProductionOfflineReadinessAuthorityV1.publication phase=clock-time-zone finiteNow=\(finiteNow) notBeforeCheckedAt=\(notBeforeCheckedAt) timeZoneComparisonFailed=\(timeZoneComparisonFailed)")
                #endif
                throw MyDaySourceReadFailureV1.sourcesChanged
            }
            for observation in manifest.referenceObservations where observation.availability == .readyOffline {
                guard let release = sources.releases.first(where: { $0.releaseID == observation.releaseID }),
                      release.expiresAt.map({ $0 > now }) ?? true else {
                    #if DEBUG
                    let observedRelease = sources.releases.first { $0.releaseID == observation.releaseID }
                    let releasePresent = observedRelease != nil
                    let unexpired = observedRelease.map { $0.expiresAt.map { $0 > now } ?? true } ?? false
                    print("ProductionOfflineReadinessAuthorityV1.publication phase=reference-expiry releasePresent=\(releasePresent) unexpired=\(unexpired)")
                    #endif
                    throw MyDaySourceReadFailureV1.sourcesChanged
                }
            }
        }
    }

    /// Operation-scoped only. Each current() call reacquires canonical rows;
    /// the existing coordinator performs both complete materializations.
    @MainActor private final class RoundReadback: OfflineReadinessRoundSessionReadingV1, OfflineReadinessPreflightAuthorityReadingV1 {
        let owner: ProductionOfflineReadinessAuthorityV1
        let token: AppAccessGateV1.ContentReadToken
        private var sources: ProductionOfflineReadinessSourceClosureV1?
        private var round: RoundSessionV1?
        private let operationCheckedAt: Date
        init(owner: ProductionOfflineReadinessAuthorityV1, token: AppAccessGateV1.ContentReadToken) {
            self.owner = owner; self.token = token
            operationCheckedAt = owner.clock.now()
        }

        func current(sessionID: UUID) throws -> RoundSessionV1? {
            let session = try owner.currentSession()
            let value = try ProductionOfflineReadinessSourceClosureV1(context: session.modelContext, workspaceID: owner.workspaceID)
            let current = try RoundSessionHistoryValidatorV1.validate(value.rounds.filter { $0.sessionID == sessionID }, workspaceID: owner.workspaceID, sessionID: sessionID)
            sources = value; round = current
            return current
        }
        func validateCurrentFrontier(_ reference: RoundSessionReferenceV1) throws -> RoundSessionV1 {
            guard let round, try round.reference == reference,
                  try owner.completedItemsMatch(round, sources: requireSources()) else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
            }
            guard round.items.flatMap(\.requirement.requiredContent).allSatisfy({
                $0.workspaceID == owner.workspaceID.rawValue.uuidString.lowercased()
            }) else { throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements }
            return round
        }
        func checkCancellation() throws { try Task.checkCancellation(); _ = try owner.currentSession() }
        func checkedAt() async throws -> Date { try checkCancellation(); return operationCheckedAt }
        func timeZoneIdentifier() async throws -> String { TimeZone.current.identifier }
        func clockState(previous: OfflineReadinessManifestV1?, checkedAt: Date, timeZoneIdentifier: String) async throws -> OfflineReadinessClockStateV1 {
            let now = owner.clock.now()
            guard checkedAt.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite,
                  now >= checkedAt, TimeZone(identifier: timeZoneIdentifier) != nil else { return .uncheckable }
            if let previous, previous.timeZoneIdentifier != timeZoneIdentifier || checkedAt < previous.checkedAt { return .changedSincePriorManifest }
            return .checked
        }
        private func requireSources() throws -> ProductionOfflineReadinessSourceClosureV1 {
            guard let sources else { throw OfflineReadinessPreflightCoordinatorFailureV1.currentSessionUnavailable }
            return sources
        }
        func observedPackage(for expected: RoundPackageReleaseReferenceV1) async throws -> RoundPackageReleaseReferenceV1? {
            guard let release = try requireSources().package(for: expected) else { return nil }
            return try RoundPackageReleaseReferenceV1(release)
        }
        func observedAssetIDs(workspaceID: WorkspaceID, selectedAssets: [RoundAssetSelectionV1]) async throws -> Set<UUID> {
            guard workspaceID == owner.workspaceID else { throw MyDayFailureV1.wrongWorkspace }
            let assets = try requireSources().assets
            return Set(selectedAssets.filter { selected in assets.contains { $0.id == selected.assetID && $0.siteID == selected.siteID } }.map(\.assetID))
        }
        private func guidance(_ expected: RoundPackageReleaseReferenceV1) throws -> [InspectionPackageGuidanceV2] {
            guard let release = try requireSources().package(for: expected) else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            return try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes).advisoryGuidance
        }
        func guidanceReferenceIDs(for expected: RoundPackageReleaseReferenceV1) async throws -> [String] { try guidance(expected).map(\.guidanceID).sorted() }
        func availableGuidanceReferenceIDs(for expected: RoundPackageReleaseReferenceV1) async throws -> Set<String> {
            let registry = try requireSources().localization
            let keys = Set(registry.definitions.filter { !$0.englishDefaultValue.isEmpty }.map { $0.key.rawValue })
            return Set(try guidance(expected).filter { keys.contains($0.localizationKey) }.map(\.guidanceID))
        }
        func contentObservations(for requirements: [OfflineReadinessContentRequirementV1]) async throws -> [OfflineReadinessContentObservationV1] {
            var values: [OfflineReadinessContentObservationV1] = []
            for requirement in requirements {
                try await owner.accessGate.validateContentRead(token, for: .render)
                try checkCancellation()
                let reference = requirement.reference
                let state: OfflineReadinessContentObservationStateV1
                do {
                    let resolved = try await owner.content.resolveContentReference(reference)
                    state = resolved == reference ? .present : .missing
                } catch is CancellationError { throw CancellationError() }
                catch { state = .uncheckable }
                values.append(try .init(contentID: reference.contentID, workspaceID: reference.workspaceID,
                    state: state, observedSHA256: state == .present ? reference.digests.digest(for: .sha256)?.hexadecimalValue : nil,
                    observedByteLength: state == .present ? reference.byteLength : nil))
            }
            return values
        }
        func expectedFieldReferenceBindings(session: RoundSessionReferenceV1, expectedPackage: RoundPackageReleaseReferenceV1) async throws -> [(release: FieldReferenceReleaseV1, binding: FieldReferenceBindingV1)] {
            let sources = try requireSources()
            guard let round, try round.reference == session, try sources.package(for: expectedPackage) != nil else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            return try owner.fieldReferenceBindings(for: round, sources: sources)
        }
        func fieldReferenceReadiness(workspaceID: WorkspaceID, checkedAt: Date) async throws -> [FieldReferenceOfflineReadinessV1] {
            guard workspaceID == owner.workspaceID, let round,
                  let values = try await owner.fieldReferenceReadiness(for: round,
                    sources: requireSources(), checkedAt: checkedAt, token: token) else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            return values
        }
        func storageObservation(for requirements: [OfflineReadinessContentRequirementV1]) async throws -> OfflineReadinessStorageObservationV1 {
            try owner.ledger.observeOfflineReadiness(expectedApplicationSupportURL: owner.applicationSupportURL)
        }
        func accessObservation() async throws -> OfflineReadinessAccessObservationV1 {
            // Fresh concrete gate observation; no authentication or fallback.
            try await owner.accessGate.validateContentRead(token, for: .render)
            return .init(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
        }
    }
}
