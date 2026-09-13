import Foundation

protocol SceneNavigationDeviceStatePortV1: AnyObject {
    func loadSceneNavigationData() throws -> Data?
    func saveSceneNavigationData(_ data: Data) throws
    func eraseSceneNavigationData() throws
}

enum SceneNavigationLoadResultV1: Equatable {
    case absent
    case restored(SceneNavigationSnapshotV1)
    case discarded(RouteFallbackReasonV1)
}

final class SceneNavigationStateAdapterV1 {
    private let port: SceneNavigationDeviceStatePortV1

    init(port: SceneNavigationDeviceStatePortV1) { self.port = port }

    func save(_ snapshot: SceneNavigationSnapshotV1) throws {
        try snapshot.validate()
        let data = try RouteCanonicalCodecV1.encode(snapshot)
        guard data.count <= SceneNavigationSnapshotV1.maximumEncodedByteCount else {
            throw SceneNavigationFailureV1.invalidSnapshot
        }
        try port.saveSceneNavigationData(data)
    }

    func save(
        _ snapshot: SceneNavigationSnapshotV1,
        using token: AppAccessGateV1.ContentReadToken
    ) throws {
        try token.withContentRead(for: .sceneRestoration) {
            try save(snapshot)
        }
    }

    func loadAndReconcile() throws -> SceneNavigationLoadResultV1 {
        let data: Data
        do {
            guard let stored = try port.loadSceneNavigationData() else { return .absent }
            data = stored
        } catch SceneNavigationFailureV1.invalidSnapshot {
            try port.eraseSceneNavigationData()
            return .discarded(.corruptSnapshot)
        }
        guard data.count <= SceneNavigationSnapshotV1.maximumEncodedByteCount else {
            try port.eraseSceneNavigationData()
            return .discarded(.corruptSnapshot)
        }
        let version: Int
        do { version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion }
        catch {
            try port.eraseSceneNavigationData()
            return .discarded(.corruptSnapshot)
        }
        guard version == SceneNavigationSnapshotV1.schemaVersion else {
            try port.eraseSceneNavigationData()
            return .discarded(.unsupportedSnapshotVersion)
        }
        do {
            let snapshot = try JSONDecoder().decode(SceneNavigationSnapshotV1.self, from: data)
            try snapshot.validate()
            return .restored(snapshot)
        } catch {
            try port.eraseSceneNavigationData()
            return .discarded(.corruptSnapshot)
        }
    }

    func loadAndReconcile(
        accessGate: any AppAccessGatePortV1
    ) async throws -> SceneNavigationLoadResultV1 {
        _ = try await accessGate.requireContentAccess(for: .sceneRestoration)
        return try loadAndReconcile()
    }

    func loadAndReconcile(
        using token: AppAccessGateV1.ContentReadToken
    ) throws -> SceneNavigationLoadResultV1 {
        try token.withContentRead(for: .sceneRestoration) {
            try loadAndReconcile()
        }
    }

    func erase() throws { try port.eraseSceneNavigationData() }

    private struct VersionProbe: Decodable { let schemaVersion: Int }
}

final class InMemorySceneNavigationDeviceStatePortV1: SceneNavigationDeviceStatePortV1 {
    private(set) var data: Data?
    func loadSceneNavigationData() throws -> Data? { data }
    func saveSceneNavigationData(_ data: Data) throws { self.data = data }
    func eraseSceneNavigationData() throws { data = nil }
}
