import Foundation
import SwiftData

enum StoreGenerationFailure: Error, Equatable {
    case dataPointerInvalid
    case dataGenerationMissing
}

@MainActor
final class StoreGenerationSession {
    let generationID: UUID
    let generationRootURL: URL
    let modelContext: ModelContext

    private let modelContainer: ModelContainer

    fileprivate init(
        generationID: UUID,
        generationRootURL: URL,
        modelContainer: ModelContainer
    ) {
        self.generationID = generationID
        self.generationRootURL = generationRootURL
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }
}

struct StoreGenerationFactory {
    private static let dataDirectoryName = "FieldEvidenceData"
    private static let bootstrapDirectoryName = ".FieldEvidenceData.bootstrap"
    private static let generationsDirectoryName = "generations"
    private static let currentPointerName = "current.json"
    private static let retiredPointerName = "retired.json"
    private static let modelStoreName = "model.sqlite"

    private let applicationSupportURL: URL
    private let fileManager: FileManager

    init(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) {
        self.applicationSupportURL = applicationSupportURL
        self.fileManager = fileManager
    }

    static func backupImportStagingDirectory(
        containing generationRootURL: URL
    ) throws -> URL {
        let root = generationRootURL.standardizedFileURL
        let generations = root.deletingLastPathComponent()
        let dataRoot = generations.deletingLastPathComponent()
        guard root.isFileURL,
              generations.lastPathComponent == Self.generationsDirectoryName,
              dataRoot.lastPathComponent == Self.dataDirectoryName,
              let generationID = UUID(uuidString: root.lastPathComponent),
              generationID.uuidString.lowercased() == root.lastPathComponent else {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return dataRoot.deletingLastPathComponent()
            .appendingPathComponent("FieldEvidenceRestore", isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
    }

    @MainActor
    func openOrBootstrapCurrent() throws -> StoreGenerationSession {
        let dataRootURL = applicationSupportURL.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )

        switch try itemType(at: dataRootURL) {
        case nil:
            try bootstrapDataRoot(at: dataRootURL)
        case .some(.typeDirectory):
            break
        case .some:
            throw StoreGenerationFailure.dataPointerInvalid
        }

        return try openCurrent(in: dataRootURL)
    }

    @MainActor
    private func bootstrapDataRoot(at dataRootURL: URL) throws {
        try fileManager.createDirectory(
            at: applicationSupportURL,
            withIntermediateDirectories: true
        )

        let bootstrapURL = applicationSupportURL.appendingPathComponent(
            Self.bootstrapDirectoryName,
            isDirectory: true
        )
        if try itemType(at: bootstrapURL) != nil {
            try fileManager.removeItem(at: bootstrapURL)
        }

        let generationID = UUID()
        let generationName = canonicalString(for: generationID)
        let generationRootURL = bootstrapURL
            .appendingPathComponent(Self.generationsDirectoryName, isDirectory: true)
            .appendingPathComponent(generationName, isDirectory: true)

        try fileManager.createDirectory(
            at: generationRootURL,
            withIntermediateDirectories: true
        )

        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        try createAndReleaseEmptyContainer(at: modelStoreURL)

        guard try itemType(at: modelStoreURL) == .typeRegular else {
            throw StoreGenerationFailure.dataGenerationMissing
        }

        let currentPointer = CurrentPointerV1(
            generationID: generationName,
            schemaVersion: 1
        )
        let retiredPointer = RetiredPointerV1(
            generationIDs: [],
            schemaVersion: 1
        )
        try canonicalData(for: currentPointer).write(
            to: bootstrapURL.appendingPathComponent(Self.currentPointerName),
            options: .atomic
        )
        try canonicalData(for: retiredPointer).write(
            to: bootstrapURL.appendingPathComponent(Self.retiredPointerName),
            options: .atomic
        )

        // The staging root is a fixed sibling, so this move is a same-volume
        // atomic publication of an already complete generation and pointers.
        try fileManager.moveItem(at: bootstrapURL, to: dataRootURL)
    }

    @MainActor
    private func openCurrent(in dataRootURL: URL) throws -> StoreGenerationSession {
        let currentURL = dataRootURL.appendingPathComponent(
            Self.currentPointerName,
            isDirectory: false
        )
        let retiredURL = dataRootURL.appendingPathComponent(
            Self.retiredPointerName,
            isDirectory: false
        )
        guard try itemType(at: currentURL) == .typeRegular,
              try itemType(at: retiredURL) == .typeRegular else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let current: CurrentPointerV1 = try decodeCanonicalPointer(at: currentURL)
        let retired: RetiredPointerV1 = try decodeCanonicalPointer(at: retiredURL)
        guard current.schemaVersion == 1,
              retired.schemaVersion == 1,
              let currentID = canonicalUUID(from: current.generationID),
              retired.generationIDs.allSatisfy({ canonicalUUID(from: $0) != nil }),
              retired.generationIDs == retired.generationIDs.sorted(),
              Set(retired.generationIDs).count == retired.generationIDs.count,
              !retired.generationIDs.contains(current.generationID) else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let generationsURL = dataRootURL.appendingPathComponent(
            Self.generationsDirectoryName,
            isDirectory: true
        )
        guard let generationsType = try itemType(at: generationsURL) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard generationsType == .typeDirectory else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let expectedGenerationNames = Set(
            [current.generationID] + retired.generationIDs
        )
        let actualGenerationNames: Set<String>
        do {
            actualGenerationNames = Set(
                try fileManager.contentsOfDirectory(atPath: generationsURL.path)
            )
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        guard actualGenerationNames == expectedGenerationNames else {
            if expectedGenerationNames.subtracting(actualGenerationNames).isEmpty {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            throw StoreGenerationFailure.dataGenerationMissing
        }

        for generationName in expectedGenerationNames {
            let generationURL = generationsURL.appendingPathComponent(
                generationName,
                isDirectory: true
            )
            guard let generationType = try itemType(at: generationURL) else {
                throw StoreGenerationFailure.dataGenerationMissing
            }
            guard generationType == .typeDirectory else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
        }

        let generationRootURL = generationsURL.appendingPathComponent(
            current.generationID,
            isDirectory: true
        )
        let modelStoreURL = generationRootURL.appendingPathComponent(
            Self.modelStoreName,
            isDirectory: false
        )
        guard let modelStoreType = try itemType(at: modelStoreURL) else {
            throw StoreGenerationFailure.dataGenerationMissing
        }
        guard modelStoreType == .typeRegular else {
            throw StoreGenerationFailure.dataPointerInvalid
        }

        let container: ModelContainer
        do {
            container = try makeContainer(at: modelStoreURL)
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
        return StoreGenerationSession(
            generationID: currentID,
            generationRootURL: generationRootURL,
            modelContainer: container
        )
    }

    @MainActor
    private func createAndReleaseEmptyContainer(at modelStoreURL: URL) throws {
        _ = try makeContainer(at: modelStoreURL)
    }

    @MainActor
    private func makeContainer(at modelStoreURL: URL) throws -> ModelContainer {
        let schema = Schema(
            [
                Site.self,
                Asset.self,
                WorkflowRecord.self,
                EvidenceFile.self,
                Issue.self,
                Packet.self,
                Report.self,
            ],
            version: Schema.Version(1, 0, 0)
        )
        let configuration = ModelConfiguration(
            "FieldEvidenceV1",
            schema: schema,
            url: modelStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: nil,
            configurations: [configuration]
        )
    }

    private func decodeCanonicalPointer<Value: Decodable & Encodable>(
        at url: URL
    ) throws -> Value {
        do {
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(Value.self, from: data)
            guard try canonicalData(for: value) == data else {
                throw StoreGenerationFailure.dataPointerInvalid
            }
            return value
        } catch let failure as StoreGenerationFailure {
            throw failure
        } catch {
            throw StoreGenerationFailure.dataPointerInvalid
        }
    }

    private func canonicalData<Value: Encodable>(for value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private func canonicalUUID(from value: String) -> UUID? {
        guard let uuid = UUID(uuidString: value),
              canonicalString(for: uuid) == value else {
            return nil
        }
        return uuid
    }

    private func canonicalString(for uuid: UUID) -> String {
        uuid.uuidString.lowercased()
    }

    private func itemType(at url: URL) throws -> FileAttributeType? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType
        } catch let error as CocoaError where
            error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw error
        }
    }
}

private struct CurrentPointerV1: Codable {
    let generationID: String
    let schemaVersion: Int
}

private struct RetiredPointerV1: Codable {
    let generationIDs: [String]
    let schemaVersion: Int
}
