import Foundation
import SwiftData
import SwiftUI

struct FirstSignInput: Equatable, Sendable {
    let siteLabel: String
    let signLabel: String
    let address: String
    let timeZoneID: String
    let isTimeZoneConfirmed: Bool

    init(
        siteLabel: String,
        signLabel: String,
        address: String = "",
        timeZoneID: String = "",
        isTimeZoneConfirmed: Bool = false
    ) {
        self.siteLabel = siteLabel
        self.signLabel = signLabel
        self.address = address
        self.timeZoneID = timeZoneID
        self.isTimeZoneConfirmed = isTimeZoneConfirmed
    }
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
    case storedDataInvalid
    case saveFailed
}

@MainActor
final class FirstSignCoordinator: ObservableObject {
    private let modelContext: ModelContext
    private let diagnosticsStore: DiagnosticsStore
    private let signPack: SignPack

    init(
        modelContext: ModelContext,
        diagnosticsStore: DiagnosticsStore,
        signPack: SignPack
    ) {
        self.modelContext = modelContext
        self.diagnosticsStore = diagnosticsStore
        self.signPack = signPack
    }

    func load() throws -> FirstSignSnapshot? {
        var assetDescriptor = FetchDescriptor<Asset>()
        assetDescriptor.fetchLimit = 2
        let assets = try modelContext.fetch(assetDescriptor)

        guard let asset = assets.first else {
            return nil
        }
        guard assets.count == 1 else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }

        let siteID = asset.siteID
        let siteDescriptor = FetchDescriptor<Site>(
            predicate: #Predicate { $0.id == siteID }
        )
        let sites = try modelContext.fetch(siteDescriptor)
        guard sites.count == 1, let site = sites.first else {
            throw FirstSignCoordinatorError.storedDataInvalid
        }

        return snapshot(site: site, asset: asset)
    }

    func create(_ input: FirstSignInput) async throws -> FirstSignSnapshot {
        let normalized = try validated(input)

        var assetDescriptor = FetchDescriptor<Asset>()
        assetDescriptor.fetchLimit = 1
        guard try modelContext.fetch(assetDescriptor).isEmpty else {
            throw FirstSignCoordinatorError.firstSignAlreadyExists
        }

        let now = Date()
        let site = Site(
            label: normalized.siteLabel,
            address: normalized.address,
            timeZoneID: normalized.timeZoneID,
            createdAt: now
        )
        let asset = Asset(
            siteID: site.id,
            packID: signPack.packID,
            packSchemaVersion: signPack.schemaVersion,
            packContentVersion: signPack.contentVersion,
            label: normalized.signLabel,
            createdAt: now
        )

        modelContext.insert(site)
        modelContext.insert(asset)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw FirstSignCoordinatorError.saveFailed
        }

        await diagnosticsStore.increment(.firstSignCreated)
        return snapshot(site: site, asset: asset)
    }

    private func validated(_ input: FirstSignInput) throws -> NormalizedFirstSignInput {
        let siteLabel = trimmed(input.siteLabel)
        guard !siteLabel.isEmpty else {
            throw FirstSignCoordinatorError.validation(.siteLabel)
        }

        let signLabel = trimmed(input.signLabel)
        guard !signLabel.isEmpty else {
            throw FirstSignCoordinatorError.validation(.signLabel)
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
            siteLabel: siteLabel,
            signLabel: signLabel,
            address: address,
            timeZoneID: timeZoneID
        )
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
    let siteLabel: String
    let signLabel: String
    let address: String?
    let timeZoneID: String?
}
