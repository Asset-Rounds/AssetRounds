import Foundation
import SwiftData
import SwiftUI

struct FirstSignInput: Equatable, Sendable {
    let existingSiteID: UUID?
    let siteLabel: String
    let signLabel: String
    let address: String
    let timeZoneID: String
    let isTimeZoneConfirmed: Bool

    init(
        existingSiteID: UUID? = nil,
        siteLabel: String,
        signLabel: String,
        address: String = "",
        timeZoneID: String = "",
        isTimeZoneConfirmed: Bool = false
    ) {
        self.existingSiteID = existingSiteID
        self.siteLabel = siteLabel
        self.signLabel = signLabel
        self.address = address
        self.timeZoneID = timeZoneID
        self.isTimeZoneConfirmed = isTimeZoneConfirmed
    }
}

struct FirstSignSiteOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let address: String?
    let timeZoneID: String?
}

struct FirstSignSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID { assetID }

    let siteID: UUID
    let assetID: UUID
    let siteLabel: String
    let signLabel: String
    let address: String?
    let timeZoneID: String?
    let packID: String
    let packSchemaVersion: Int
    let packContentVersion: Int
}

enum FirstSignValidationField: String, Equatable, Sendable {
    case siteLabel
    case signLabel
    case timeZoneID
    case timeZoneConfirmation
}

enum FirstSignCoordinatorError: Error, Equatable {
    case validation(FirstSignValidationField)
    case firstSignAlreadyExists
    case accessDenied(DraftAccessDecisionV1)
    case storedDataInvalid
    case saveFailed
}

@MainActor
final class FirstSignCoordinator: ObservableObject {
    private let modelContext: ModelContext
    private let workspaceWriter: WorkspaceWriterV1?
    private let mutationAdapter: WorkspaceWriterAdapterV1
    private let clock: any ApplicationClock
    private let idSource: any ApplicationIDSource
    private let fileAuthority: any ApplicationFileAuthorityV1
    private let diagnosticsStore: DiagnosticsStore
    private let signPack: SignPack
    private let accessState: (@MainActor () -> DraftAccessNormalizedStateV1)?

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        signPack: SignPack,
        workspaceWriter: WorkspaceWriterV1? = nil,
        clock: any ApplicationClock = SystemApplicationClock(),
        idSource: any ApplicationIDSource = SystemApplicationIDSource(),
        fileAuthority: any ApplicationFileAuthorityV1 = SystemApplicationFileAuthorityV1(),
        accessState: (@MainActor () -> DraftAccessNormalizedStateV1)? = nil
    ) {
        self.modelContext = modelContext
        self.workspaceWriter = workspaceWriter
        self.mutationAdapter = WorkspaceWriterAdapterV1(modelContext: modelContext)
        self.clock = clock
        self.idSource = idSource
        self.fileAuthority = fileAuthority
        self.diagnosticsStore = diagnosticsStore
        self.signPack = signPack
        self.accessState = accessState
    }

    func load() throws -> FirstSignSnapshot? {
        let values = try loadAll()
        guard values.count <= 1 else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        return values.first
    }

    func loadAll() throws -> [FirstSignSnapshot] {
        guard !modelContext.hasChanges else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        let sites = try validatedSites()
        let sitesByID = Dictionary(uniqueKeysWithValues: sites.map { ($0.id, $0) })
        guard Set(assets.map(\.id)).count == assets.count else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        return try assets.map { asset in
            guard asset.schemaVersion == 1,
                  asset.label == trimmed(asset.label),
                  !asset.label.isEmpty,
                  asset.updatedAt >= asset.createdAt,
                  asset.packID == signPack.packID,
                  asset.packSchemaVersion == signPack.schemaVersion,
                  asset.packContentVersion == signPack.contentVersion,
                  let site = sitesByID[asset.siteID] else {
                throw FirstSignCoordinatorError.storedDataInvalid
            }
            return snapshot(site: site, asset: asset)
        }.sorted {
            if $0.signLabel != $1.signLabel {
                return $0.signLabel.localizedStandardCompare($1.signLabel)
                    == .orderedAscending
            }
            return $0.assetID.uuidString < $1.assetID.uuidString
        }
    }

    func siteOptions() throws -> [FirstSignSiteOption] {
        try validatedSites().map {
            FirstSignSiteOption(
                id: $0.id,
                label: $0.label,
                address: $0.address,
                timeZoneID: $0.timeZoneID
            )
        }.sorted {
            if $0.label != $1.label {
                return $0.label.localizedStandardCompare($1.label)
                    == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func accessDecisionForCreateSign() throws -> DraftAccessDecisionV1 {
        let assets = try validatedAccessAssets()
        guard let accessState else {
            return assets.isEmpty ? .allow : .blockEvaluation
        }
        return DraftAccessPolicy.evaluate(
            DraftAccessPolicyInputV1(
                accessState: accessState(),
                liveAssetCount: assets.count,
                countedStableRootIDs: try countedStableRootIDs(),
                requestedEntry: .createSign
            )
        )
    }

    func create(_ input: FirstSignInput) async throws -> FirstSignSnapshot {
        let normalized = try validated(input)

        let assetCountBefore = try validatedAccessAssets().count
        let decision = try accessDecisionForCreateSign()
        guard decision == .allow else {
            if case nil = accessState, assetCountBefore > 0 {
                throw FirstSignCoordinatorError.firstSignAlreadyExists
            }
            throw FirstSignCoordinatorError.accessDenied(decision)
        }

        let now = clock.now()
        let site: Site
        let insertsSite: Bool
        if let existingSiteID = normalized.existingSiteID {
            let matches = try validatedSites().filter { $0.id == existingSiteID }
            guard matches.count == 1, let existing = matches.first else {
                throw FirstSignCoordinatorError.storedDataInvalid
            }
            site = existing
            insertsSite = false
        } else {
            site = Site(
                id: idSource.makeID(),
                label: normalized.siteLabel,
                address: normalized.address,
                timeZoneID: normalized.timeZoneID,
                createdAt: now
            )
            insertsSite = true
        }
        let asset = Asset(
            id: idSource.makeID(),
            siteID: site.id,
            packID: signPack.packID,
            packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            label: normalized.signLabel,
            createdAt: now
        )

        do {
            let value = FirstSignMutationV1(
                siteID: site.id,
                newSite: insertsSite ? .init(
                    id: site.id,
                    label: site.label,
                    address: site.address,
                    timeZoneID: site.timeZoneID
                ) : nil,
                assetID: asset.id,
                assetLabel: asset.label,
                packID: asset.packID,
                packSchemaVersion: asset.packSchemaVersion,
                packContentVersion: asset.packContentVersion,
                createdAt: now
            )
            try executeWorkspaceMutation(.createFirstSign(value), occurredAt: now)
        } catch {
            modelContext.rollback()
            throw FirstSignCoordinatorError.saveFailed
        }

        let siteID = site.id
        let assetID = asset.id
        guard let persistedSites = try? modelContext.fetch(FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        )),
        let persistedAssets = try? modelContext.fetch(FetchDescriptor<Asset>(
            predicate: #Predicate { $0.id == assetID }
        )),
        persistedSites.count == 1,
        persistedAssets.count == 1,
        let persistedSite = persistedSites.first,
        let persistedAsset = persistedAssets.first else {
            throw FirstSignCoordinatorError.saveFailed
        }

        if (await diagnosticsStore.snapshot()).firstSignCreated == 0 {
            await diagnosticsStore.increment(.firstSignCreated)
        }
        return snapshot(site: persistedSite, asset: persistedAsset)
    }

    private func executeWorkspaceMutation(
        _ command: WorkspaceCommandV1,
        occurredAt: Date
    ) throws {
        let mutationID = try workspaceWriter?.makeMutationID()
            ?? MutationIDV1(rawValue: idSource.makeID())
        if let workspaceWriter {
            let current = try workspaceWriter.currentRevision()
            let targets: [WorkspaceEntityIdentityV1]
            switch command {
            case let .createFirstSign(value):
                targets = try [
                    WorkspaceEntityIdentityV1(kind: .site, id: value.siteID),
                    WorkspaceEntityIdentityV1(kind: .asset, id: value.assetID),
                ]
            default:
                throw WorkspaceMutationFailureV1.unsupportedCommand
            }
            let known = Dictionary(
                uniqueKeysWithValues: current.entityRevisions.map { ($0.identity, $0.revision) }
            )
            let scoped = try WorkspaceRevisionV1(
                workspaceID: current.workspaceID,
                generationID: current.generationID,
                writerInstanceID: current.writerInstanceID,
                revision: current.revision,
                entityRevisions: targets.map {
                    WorkspaceEntityRevisionV1(identity: $0, revision: known[$0, default: 0])
                }
            )
            _ = try workspaceWriter.execute(WorkspaceMutationRequestV1(
                mutationID: mutationID,
                expectedRevision: WorkspaceExpectedRevisionV1(snapshot: scoped),
                command: command
            ))
        } else {
            let temporaryPath = try fileAuthority.temporaryRelativePath(
                mutationID: mutationID,
                component: command.kind.rawValue
            )
            _ = try mutationAdapter.apply(
                command,
                occurredAt: occurredAt,
                temporaryRelativePath: temporaryPath
            )
        }
    }

    private func validated(_ input: FirstSignInput) throws -> NormalizedFirstSignInput {
        let signLabel = trimmed(input.signLabel)
        guard !signLabel.isEmpty else {
            throw FirstSignCoordinatorError.validation(.signLabel)
        }

        if let existingSiteID = input.existingSiteID {
            let matches = try validatedSites().filter { $0.id == existingSiteID }
            guard matches.count == 1 else {
                throw FirstSignCoordinatorError.storedDataInvalid
            }
            return NormalizedFirstSignInput(
                existingSiteID: existingSiteID,
                siteLabel: "",
                signLabel: signLabel,
                address: nil,
                timeZoneID: nil
            )
        }

        let siteLabel = trimmed(input.siteLabel)
        guard !siteLabel.isEmpty else {
            throw FirstSignCoordinatorError.validation(.siteLabel)
        }

        let address = optionalTrimmed(input.address)
        let timeZoneID = optionalTrimmed(input.timeZoneID)

        if let timeZoneID {
            guard TimeZone.knownTimeZoneIdentifiers.contains(timeZoneID) else {
                throw FirstSignCoordinatorError.validation(.timeZoneID)
            }
            guard input.isTimeZoneConfirmed else {
                throw FirstSignCoordinatorError.validation(.timeZoneConfirmation)
            }
        }

        return NormalizedFirstSignInput(
            existingSiteID: nil,
            siteLabel: siteLabel,
            signLabel: signLabel,
            address: address,
            timeZoneID: timeZoneID
        )
    }

    private func validatedAccessAssets() throws -> [Asset] {
        guard !modelContext.hasChanges else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        let assets = try modelContext.fetch(FetchDescriptor<Asset>())
        guard Set(assets.map(\.id)).count == assets.count,
              assets.allSatisfy({
                $0.schemaVersion == 1
                    && $0.updatedAt >= $0.createdAt
                    && $0.label == trimmed($0.label)
                    && !$0.label.isEmpty
              }) else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        return assets
    }

    private func countedStableRootIDs() throws -> Set<UUID> {
        let packets = try modelContext.fetch(FetchDescriptor<Packet>())
        guard Set(packets.map(\.id)).count == packets.count,
              Set(packets.map(\.stableRootID)).count == packets.count,
              packets.allSatisfy({ packet in
                guard packet.schemaVersion == 1 else { return false }
                if packet.currentRecordID == nil {
                    return packet.contentDeletedAt != nil
                        && packet.contentDeletedAt! >= packet.createdAt
                }
                return packet.contentDeletedAt == nil
              }) else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        return Set(
            packets.lazy.filter(\.evaluationCounted).map(\.stableRootID)
        )
    }

    private func validatedSites() throws -> [Site] {
        guard !modelContext.hasChanges else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        let sites = try modelContext.fetch(FetchDescriptor<Site>())
        guard Set(sites.map(\.id)).count == sites.count,
              sites.allSatisfy({ site in
                site.schemaVersion == 1
                    && site.label == trimmed(site.label)
                    && !site.label.isEmpty
                    && site.address.map {
                        $0 == trimmed($0) && !$0.isEmpty
                    } ?? true
                    && site.timeZoneID.map {
                        TimeZone.knownTimeZoneIdentifiers.contains($0)
                    } ?? true
                    && site.updatedAt >= site.createdAt
              }) else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }
        return sites
    }

    private func snapshot(site: Site, asset: Asset) -> FirstSignSnapshot {
        FirstSignSnapshot(
            siteID: site.id,
            assetID: asset.id,
            siteLabel: site.label,
            signLabel: asset.label,
            address: site.address,
            timeZoneID: site.timeZoneID,
            packID: asset.packID,
            packSchemaVersion: asset.packSchemaVersion,
            packContentVersion: asset.packContentVersion
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optionalTrimmed(_ value: String) -> String? {
        let normalized = trimmed(value)
        return normalized.isEmpty ? nil : normalized
    }
}

private struct NormalizedFirstSignInput {
    let existingSiteID: UUID?
    let siteLabel: String
    let signLabel: String
    let address: String?
    let timeZoneID: String?
}
