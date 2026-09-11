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
        if round.items.contains(where: { $0.completion != nil }) {
            assessment = .unavailable(.completionAuthorityUnavailable)
        } else {
            let bindings = initial.currentBindings(for: round)
            let expectedState: FieldReferenceSubjectStateV1 = round.state == .completed || round.state == .archived ? .finalized : .active
            if bindings.contains(where: { $0.subjectRevision != round.revision || $0.subjectState != expectedState }) {
                assessment = .unavailable(.staleFieldReferenceBinding)
            } else if !bindings.isEmpty {
                // Canonical release/binding rows do not contain the actual
                // content-locator closure. Never manufacture it from a manifest.
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
        try await accessGate.validateContentRead(token, for: .render)
        try Task.checkCancellation()
        let reread = try currentSession()
        guard try reread.workspaceWriter.currentRevision() == writerRevision,
              try ProductionOfflineReadinessSourceClosureV1(context: reread.modelContext, workspaceID: workspaceID).sha256() == initialSHA else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
        let result = MyDaySourceReadinessAssessmentV1(reference: reference, assessment: assessment)
        try validateStorageForPublication([result])
        return result
    }

    private func currentSession() throws -> StoreSessionCoordinator {
        guard let session, let originalWriter, originalWriter === session.workspaceWriter,
              session.workspaceID == workspaceID, session.generationID == generationID,
              session.uiGenerationToken == uiGenerationToken else { throw MyDaySourceReadFailureV1.sessionChanged }
        guard !session.modelContext.hasChanges else { throw MyDaySourceReadFailureV1.sourcesChanged }
        return session
    }

    /// The composing provider calls this after its last awaited gate check.
    /// Storage reservations are not canonical rows and therefore need their
    /// own fresh observation at publication, without acquiring a reservation.
    func validateStorageForPublication(_ assessments: [MyDaySourceReadinessAssessmentV1]) throws {
        _ = try currentSession()
        let manifests = assessments.compactMap { record -> OfflineReadinessManifestV1? in
            if case let .roundManifest(manifest) = record.assessment { return manifest }
            return nil
        }
        guard !manifests.isEmpty else { return }
        let current = try ledger.observeOfflineReadiness(expectedApplicationSupportURL: applicationSupportURL)
        let protected = UIApplication.shared.isProtectedDataAvailable
        guard manifests.allSatisfy({ $0.storage == current && $0.protectedDataAvailable == protected }) else {
            throw MyDaySourceReadFailureV1.sourcesChanged
        }
    }

    /// Operation-scoped only. Each current() call reacquires canonical rows;
    /// the existing coordinator performs both complete materializations.
    @MainActor private final class RoundReadback: OfflineReadinessRoundSessionReadingV1, OfflineReadinessPreflightAuthorityReadingV1 {
        let owner: ProductionOfflineReadinessAuthorityV1
        let token: AppAccessGateV1.ContentReadToken
        private var sources: ProductionOfflineReadinessSourceClosureV1?
        private var round: RoundSessionV1?
        init(owner: ProductionOfflineReadinessAuthorityV1, token: AppAccessGateV1.ContentReadToken) {
            self.owner = owner; self.token = token
        }

        func current(sessionID: UUID) throws -> RoundSessionV1? {
            let session = try owner.currentSession()
            let value = try ProductionOfflineReadinessSourceClosureV1(context: session.modelContext, workspaceID: owner.workspaceID)
            let current = try RoundSessionHistoryValidatorV1.validate(value.rounds.filter { $0.sessionID == sessionID }, workspaceID: owner.workspaceID, sessionID: sessionID)
            sources = value; round = current
            return current
        }
        func validateCurrentFrontier(_ reference: RoundSessionReferenceV1) throws -> RoundSessionV1 {
            guard let round, try round.reference == reference, !round.items.contains(where: { $0.completion != nil }) else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.frontierChangedDuringReadback
            }
            guard round.items.flatMap(\.requirement.requiredContent).allSatisfy({
                $0.workspaceID == owner.workspaceID.rawValue.uuidString.lowercased()
            }) else { throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements }
            return round
        }
        func checkCancellation() throws { try Task.checkCancellation(); _ = try owner.currentSession() }
        func checkedAt() async throws -> Date { try checkCancellation(); return owner.clock.now() }
        func timeZoneIdentifier() async throws -> String { TimeZone.current.identifier }
        func clockState(previous: OfflineReadinessManifestV1?, checkedAt: Date, timeZoneIdentifier: String) async throws -> OfflineReadinessClockStateV1 {
            guard checkedAt.timeIntervalSinceReferenceDate.isFinite, TimeZone(identifier: timeZoneIdentifier) != nil else { return .uncheckable }
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
            guard let round, try round.reference == session, try sources.package(for: expectedPackage) != nil,
                  sources.currentBindings(for: round).isEmpty else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            // The exact closed package has no field-reference declaration;
            // the fully validated subject binding history is genuinely empty.
            return []
        }
        func fieldReferenceReadiness(workspaceID: WorkspaceID, checkedAt: Date) async throws -> [FieldReferenceOfflineReadinessV1] {
            guard workspaceID == owner.workspaceID, let round, try requireSources().currentBindings(for: round).isEmpty else {
                throw OfflineReadinessPreflightCoordinatorFailureV1.inconsistentSessionRequirements
            }
            return []
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
