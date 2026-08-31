import Foundation

enum PrivateSystemDiscoveryFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, corruptDigest, wrongWorkspace
    case practiceWorkspaceForbidden, optedOut, unavailable, accessRequired
    case unsupportedAction, privateResolutionBeforeAccess, unsafeRoute, unsafeShare
}

enum PrivateSystemDiscoveryLifecycleV1 {
    static let namedIndex = "PRIVATE_SYSTEM_DISCOVERY_INDEX_V1"
    static let canonicalPersistence = false
    static let createsSecondIndex = false
    static let createsSecondSettingsSchema = false
    static let defaultEnabled = false
    static let activationEnabled = false
    static let adoptionEnabled = false
    static let dropAndRebuildOnRestore = true
    static let removalIsJournaled = true
}

private enum PrivateSystemDiscoveryValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static func id(_ value: UUID) throws { guard value != zero else { throw PrivateSystemDiscoveryFailureV1.invalidValue } }
    static func token(_ value: String, maximum: Int = 160) throws {
        guard SettingsValidationV1.validToken(value, maximumBytes: maximum) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    static func digest(_ value: String) throws {
        guard value == value.lowercased(), CompatibilityCanonicalV1.validSHA256(value) else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }
    }
    static func instant(_ value: Date) throws { guard value.timeIntervalSinceReferenceDate.isFinite else { throw PrivateSystemDiscoveryFailureV1.invalidValue } }
    static func hash<T: Encodable>(_ value: T) throws -> String { CompatibilityCanonicalV1.sha256(try CompatibilityCanonicalV1.encode(value)) }
}

enum PrivateSystemDiscoveryWorkspaceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case real = "REAL"
    case practice = "PRACTICE"
}

/// Device-local selection only. OFF is represented by an empty set and can
/// never silently bind whichever workspace happens to be visible later.
struct PrivateSystemDiscoveryOptInV1: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    static let settingKey = "device.privateSystemDiscovery.selectedWorkspace"
    static let offToken = "OFF"
    static let canonicalPrefix = "V2:"
    static let maximumSelectedWorkspaceCount = 16
    let schemaVersion: Int
    let selectedWorkspaceIDs: [WorkspaceID]
    var isEnabled: Bool { !selectedWorkspaceIDs.isEmpty }
    var selectedWorkspaceID: WorkspaceID? { selectedWorkspaceIDs.count == 1 ? selectedWorkspaceIDs[0] : nil }
    var workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1? { isEnabled ? .real : nil }
    func contains(_ workspaceID: WorkspaceID) -> Bool { selectedWorkspaceIDs.contains(workspaceID) }
    var canonicalSettingToken: String {
        isEnabled ? Self.canonicalPrefix + selectedWorkspaceIDs.map { $0.rawValue.uuidString.lowercased() }.joined(separator: "+") : Self.offToken
    }
    var canonicalSettingData: Data { get throws { try CompatibilityCanonicalV1.encode(canonicalSettingToken) } }

    init(selectedWorkspaceID: WorkspaceID?, workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1?) throws {
        if workspaceKind == .practice { throw PrivateSystemDiscoveryFailureV1.practiceWorkspaceForbidden }
        try self.init(selectedWorkspaceIDs: selectedWorkspaceID.map { [$0] } ?? [], workspaceKind: workspaceKind)
    }
    init(selectedWorkspaceIDs: [WorkspaceID], workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1?) throws {
        schemaVersion = Self.schemaVersion
        self.selectedWorkspaceIDs = selectedWorkspaceIDs.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        if workspaceKind == .practice { throw PrivateSystemDiscoveryFailureV1.practiceWorkspaceForbidden }
        guard (self.selectedWorkspaceIDs.isEmpty && workspaceKind == nil) || (!self.selectedWorkspaceIDs.isEmpty && workspaceKind == .real)
        else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
        try validate()
    }
    static var disabled: Self { try! Self(selectedWorkspaceIDs: [], workspaceKind: nil) }
    static func enabled(workspaceID: WorkspaceID, workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1) throws -> Self {
        try Self(selectedWorkspaceIDs: [workspaceID], workspaceKind: workspaceKind)
    }
    static func enabled(workspaceIDs: [WorkspaceID], workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1 = .real) throws -> Self {
        try Self(selectedWorkspaceIDs: workspaceIDs, workspaceKind: workspaceKind)
    }
    init(canonicalSettingToken: String, workspaceKind: PrivateSystemDiscoveryWorkspaceKindV1?) throws {
        if canonicalSettingToken == Self.offToken { try self.init(selectedWorkspaceIDs: [], workspaceKind: nil); return }
        let isCanonicalSet = canonicalSettingToken.hasPrefix(Self.canonicalPrefix)
        let payload = isCanonicalSet
            ? String(canonicalSettingToken.dropFirst(Self.canonicalPrefix.count)) : canonicalSettingToken
        let tokens = payload.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let ids = try tokens.map { token -> WorkspaceID in
            guard let raw = UUID(uuidString: token),
                  !isCanonicalSet || raw.uuidString.lowercased() == token else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            return WorkspaceID(rawValue: raw)
        }
        try self.init(selectedWorkspaceIDs: ids, workspaceKind: workspaceKind)
    }
    func validate() throws {
        guard schemaVersion == Self.schemaVersion, selectedWorkspaceIDs.count <= Self.maximumSelectedWorkspaceCount,
              selectedWorkspaceIDs == selectedWorkspaceIDs.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }),
              Set(selectedWorkspaceIDs).count == selectedWorkspaceIDs.count,
              !selectedWorkspaceIDs.contains(where: { $0.rawValue == PrivateSystemDiscoveryValidationV1.zero })
        else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, selectedWorkspaceIDs }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else { throw PrivateSystemDiscoveryFailureV1.incompatibleVersion }
        let ids = try c.decode([WorkspaceID].self, forKey: .selectedWorkspaceIDs)
        try self.init(selectedWorkspaceIDs: ids, workspaceKind: ids.isEmpty ? nil : .real)
    }
}

enum PrivateSystemDiscoveryActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case openToday = "OPEN_TODAY"
    case openAssets = "OPEN_ASSETS"
    case searchWorkspace = "SEARCH_WORKSPACE"
    case openReports = "OPEN_REPORTS"
}

enum PrivateSystemDiscoveryActionKindV1: String, Codable, Hashable, Sendable {
    case foregroundNavigation = "FOREGROUND_NAVIGATION"
    case foregroundRead = "FOREGROUND_READ"
}

struct PrivateSystemDiscoveryActionDescriptorV1: Codable, Equatable, Hashable, Sendable {
    let action: PrivateSystemDiscoveryActionV1
    let kind: PrivateSystemDiscoveryActionKindV1
    let titleKey: String
    let requiresPrivateParameterResolution: Bool
    let performsMutation: Bool
    let permitsBackgroundExecution: Bool
    let permitsNetworkAccess: Bool
    func validate() throws {
        try PrivateSystemDiscoveryValidationV1.token(titleKey)
        guard !performsMutation, !permitsBackgroundExecution, !permitsNetworkAccess,
              requiresPrivateParameterResolution == (action == .searchWorkspace) else { throw PrivateSystemDiscoveryFailureV1.unsupportedAction }
    }
}

struct PrivateSystemDiscoveryManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let manifestID: String
    let indexName: String
    let featureID: String
    let actions: [PrivateSystemDiscoveryActionDescriptorV1]
    let activationEnabled: Bool
    let adoptionEnabled: Bool
    let manifestSHA256: String

    init(manifestID: String = "private-system-discovery-v1", featureID: String = "privateSystemDiscovery",
         actions: [PrivateSystemDiscoveryActionDescriptorV1] = Self.canonicalActions,
         activationEnabled: Bool = false, adoptionEnabled: Bool = false) throws {
        schemaVersion = Self.schemaVersion; self.manifestID = manifestID; indexName = PrivateSystemDiscoveryLifecycleV1.namedIndex
        self.featureID = featureID; self.actions = actions; self.activationEnabled = activationEnabled; self.adoptionEnabled = adoptionEnabled
        manifestSHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, manifestID: manifestID,
            indexName: PrivateSystemDiscoveryLifecycleV1.namedIndex, featureID: featureID, actions: actions,
            activationEnabled: activationEnabled, adoptionEnabled: adoptionEnabled)); try validate()
    }
    func validate() throws {
        try PrivateSystemDiscoveryValidationV1.token(manifestID); try PrivateSystemDiscoveryValidationV1.token(indexName)
        try PrivateSystemDiscoveryValidationV1.token(featureID); try actions.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion, indexName == PrivateSystemDiscoveryLifecycleV1.namedIndex,
              (2...5).contains(actions.count), actions == actions.sorted(by: { $0.action.rawValue < $1.action.rawValue }),
              Set(actions.map(\.action)).count == actions.count, Set(actions.map(\.action)) == Set(PrivateSystemDiscoveryActionV1.allCases),
              !activationEnabled, !adoptionEnabled, manifestSHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis))
        else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    static let canonicalActions: [PrivateSystemDiscoveryActionDescriptorV1] = [
        .init(action: .openAssets, kind: .foregroundNavigation, titleKey: "discovery.openAssets", requiresPrivateParameterResolution: false, performsMutation: false, permitsBackgroundExecution: false, permitsNetworkAccess: false),
        .init(action: .openReports, kind: .foregroundNavigation, titleKey: "discovery.openReports", requiresPrivateParameterResolution: false, performsMutation: false, permitsBackgroundExecution: false, permitsNetworkAccess: false),
        .init(action: .openToday, kind: .foregroundNavigation, titleKey: "discovery.openToday", requiresPrivateParameterResolution: false, performsMutation: false, permitsBackgroundExecution: false, permitsNetworkAccess: false),
        .init(action: .searchWorkspace, kind: .foregroundRead, titleKey: "discovery.searchWorkspace", requiresPrivateParameterResolution: true, performsMutation: false, permitsBackgroundExecution: false, permitsNetworkAccess: false),
    ]
    private var basis: Basis { .init(schemaVersion: schemaVersion, manifestID: manifestID, indexName: indexName, featureID: featureID, actions: actions, activationEnabled: activationEnabled, adoptionEnabled: adoptionEnabled) }
    private struct Basis: Codable { let schemaVersion: Int; let manifestID: String; let indexName: String; let featureID: String; let actions: [PrivateSystemDiscoveryActionDescriptorV1]; let activationEnabled: Bool; let adoptionEnabled: Bool }
    private enum CodingKeys: String, CodingKey { case schemaVersion, manifestID, indexName, featureID, actions, activationEnabled, adoptionEnabled, manifestSHA256 }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .indexName) == PrivateSystemDiscoveryLifecycleV1.namedIndex else { throw PrivateSystemDiscoveryFailureV1.incompatibleVersion }
        let value = try Self(manifestID: c.decode(String.self, forKey: .manifestID), featureID: c.decode(String.self, forKey: .featureID),
            actions: c.decode([PrivateSystemDiscoveryActionDescriptorV1].self, forKey: .actions),
            activationEnabled: c.decode(Bool.self, forKey: .activationEnabled), adoptionEnabled: c.decode(Bool.self, forKey: .adoptionEnabled))
        guard value.manifestSHA256 == (try c.decode(String.self, forKey: .manifestSHA256)) else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }
        self = value
    }
}

struct AppIntentAvailabilityV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let action: PrivateSystemDiscoveryActionV1
    let optedIn: Bool
    let featureReason: FeatureAvailabilityReasonV1
    let appAccessPermitsContent: Bool
    let protectedDataAvailable: Bool
    let available: Bool
    let evaluatedAt: Date
    let availabilitySHA256: String
    init(workspaceID: WorkspaceID, action: PrivateSystemDiscoveryActionV1, optedIn: Bool,
         featureReason: FeatureAvailabilityReasonV1, appAccessPermitsContent: Bool,
         protectedDataAvailable: Bool, evaluatedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.action = action; self.optedIn = optedIn
        self.featureReason = featureReason; self.appAccessPermitsContent = appAccessPermitsContent
        self.protectedDataAvailable = protectedDataAvailable
        available = optedIn && featureReason == .available && appAccessPermitsContent && protectedDataAvailable
        self.evaluatedAt = evaluatedAt
        availabilitySHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID,
            action: action, optedIn: optedIn, featureReason: featureReason, appAccessPermitsContent: appAccessPermitsContent,
            protectedDataAvailable: protectedDataAvailable, available: available, evaluatedAt: evaluatedAt)); try validate()
    }
    func validate() throws {
        try PrivateSystemDiscoveryValidationV1.instant(evaluatedAt)
        guard schemaVersion == Self.schemaVersion,
              available == (optedIn && featureReason == .available && appAccessPermitsContent && protectedDataAvailable),
              availabilitySHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis)) else { throw PrivateSystemDiscoveryFailureV1.unavailable }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID, action: action, optedIn: optedIn, featureReason: featureReason, appAccessPermitsContent: appAccessPermitsContent, protectedDataAvailable: protectedDataAvailable, available: available, evaluatedAt: evaluatedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let action: PrivateSystemDiscoveryActionV1; let optedIn: Bool; let featureReason: FeatureAvailabilityReasonV1; let appAccessPermitsContent: Bool; let protectedDataAvailable: Bool; let available: Bool; let evaluatedAt: Date }
}

enum PrivateSystemDiscoveryCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data { try CompatibilityCanonicalV1.encode(value) }
    static func decodeManifest(_ data: Data) throws -> PrivateSystemDiscoveryManifestV1 {
        let value = try CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryManifestV1.self, from: data); try value.validate()
        guard try encode(value) == data else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }; return value
    }
    static func decodeStateMap(_ data: Data) throws -> PrivateSystemDiscoveryStateMapV1 {
        let value = try CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryStateMapV1.self, from: data); try value.validate()
        guard try encode(value) == data else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }; return value
    }
    static func decodeJournalEntry(_ data: Data) throws -> PrivateSystemDiscoveryJournalEntryV1 {
        let value = try CompatibilityCanonicalV1.decode(PrivateSystemDiscoveryJournalEntryV1.self, from: data); try value.validate()
        guard try encode(value) == data else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }; return value
    }
}

struct PrivateSystemDiscoveryRequestV1: Equatable, Sendable {
    let requestID: UUID; let workspaceID: WorkspaceID; let action: PrivateSystemDiscoveryActionV1
    let privateParameterToken: String?; let requestedAt: Date
    init(requestID: UUID, workspaceID: WorkspaceID, action: PrivateSystemDiscoveryActionV1,
         privateParameterToken: String? = nil, requestedAt: Date) throws {
        self.requestID = requestID; self.workspaceID = workspaceID; self.action = action
        self.privateParameterToken = privateParameterToken; self.requestedAt = requestedAt
        try PrivateSystemDiscoveryValidationV1.id(requestID); try PrivateSystemDiscoveryValidationV1.instant(requestedAt)
        if let privateParameterToken { try PrivateSystemDiscoveryValidationV1.token(privateParameterToken, maximum: 256) }
        guard (privateParameterToken != nil) == (action == .searchWorkspace) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
}

struct PrivateSystemDiscoveryReadProjectionV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let resultIDs: [UUID]; let querySHA256: String
    init(workspaceID: WorkspaceID, resultIDs: [UUID], querySHA256: String) throws {
        self.workspaceID = workspaceID; self.resultIDs = resultIDs; self.querySHA256 = querySHA256
        try PrivateSystemDiscoveryValidationV1.digest(querySHA256)
        guard resultIDs.count <= 100, resultIDs == resultIDs.sorted(by: { $0.uuidString < $1.uuidString }), Set(resultIDs).count == resultIDs.count
        else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
}

enum PrivateSystemDiscoveryResultV1: Equatable, Sendable {
    case unlockRequired
    case unavailable
    case navigation(RouteResolutionResultV1)
    case read(PrivateSystemDiscoveryReadProjectionV1)
}

protocol PrivateSystemDiscoveryProjectionPortV1: Sendable {
    func resolvePrivateRead(workspaceID: WorkspaceID, opaqueParameterToken: String) async throws -> PrivateSystemDiscoveryReadProjectionV1
}

protocol PrivateSystemDiscoveryAvailabilityPortV1: Sendable {
    func availability(workspaceID: WorkspaceID, action: PrivateSystemDiscoveryActionV1, evaluatedAt: Date) async throws -> AppIntentAvailabilityV1
}

struct PrivateSystemDiscoveryShareDescriptorV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let audience: EvidenceAudienceV1; let content: ContentReferenceV1
    let privacyManifestID: UUID; let privacyManifestSHA256: String
    init(workspaceID: WorkspaceID, audience: EvidenceAudienceV1, content: ContentReferenceV1,
         privacyManifest: PrivacyTransformManifestV1, policy: PrivacyTransformPolicyV1,
         review: PrivacyReviewReceiptV1, now: Date) throws {
        self.workspaceID = workspaceID; self.audience = audience; self.content = content
        privacyManifestID = privacyManifest.manifestID; privacyManifestSHA256 = privacyManifest.manifestSHA256
        let decision = try PrivacyProjectionV1.decide(manifest: privacyManifest, review: review, policy: policy,
            requestedAudience: audience, currentSourceRevision: privacyManifest.sourceRevision,
            currentSourceSHA256: privacyManifest.sourceSHA256, at: now)
        guard decision.derivative == content, decision.denial == nil, audience == privacyManifest.audience, content == privacyManifest.derivative,
              content.byteRole == .derivative, content.workspaceID == workspaceID.rawValue.uuidString.lowercased()
        else { throw PrivateSystemDiscoveryFailureV1.unsafeShare }
    }
}

enum PrivateSystemDiscoveryProjectionDomainV1: String, CaseIterable, Codable, Hashable, Sendable {
    case navigation = "NAVIGATION"
    case workspaceSearch = "WORKSPACE_SEARCH"
}

struct PrivateSystemDiscoveryProjectionDescriptorV1: Codable, Equatable, Hashable, Sendable {
    let domain: PrivateSystemDiscoveryProjectionDomainV1
    let projectionVersion: UInt64
    let allowlistSHA256: String
    let policySHA256: String
    let indexDefinitionSHA256: String
    init(domain: PrivateSystemDiscoveryProjectionDomainV1, projectionVersion: UInt64,
         allowlistSHA256: String, policySHA256: String, indexDefinitionSHA256: String) throws {
        self.domain = domain; self.projectionVersion = projectionVersion; self.allowlistSHA256 = allowlistSHA256
        self.policySHA256 = policySHA256; self.indexDefinitionSHA256 = indexDefinitionSHA256; try validate()
    }
    func validate() throws {
        guard projectionVersion > 0 else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
        try PrivateSystemDiscoveryValidationV1.digest(allowlistSHA256); try PrivateSystemDiscoveryValidationV1.digest(policySHA256)
        try PrivateSystemDiscoveryValidationV1.digest(indexDefinitionSHA256)
    }
    var stableKey: String { domain.rawValue }
}

struct PrivateSystemDiscoveryWorkspaceStateV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let workspaceID: WorkspaceID; let workspaceRevision: UInt64
    let projections: [PrivateSystemDiscoveryProjectionDescriptorV1]
    let deletionFrontier: UInt64; let rebuiltAt: Date; let stateSHA256: String
    init(workspaceID: WorkspaceID, workspaceRevision: UInt64,
         projections: [PrivateSystemDiscoveryProjectionDescriptorV1], deletionFrontier: UInt64, rebuiltAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID; self.workspaceRevision = workspaceRevision
        self.projections = projections; self.deletionFrontier = deletionFrontier; self.rebuiltAt = rebuiltAt
        stateSHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, projections: projections, deletionFrontier: deletionFrontier, rebuiltAt: rebuiltAt)); try validate()
    }
    func validate() throws {
        try projections.forEach { try $0.validate() }; try PrivateSystemDiscoveryValidationV1.instant(rebuiltAt)
        guard schemaVersion == Self.schemaVersion, workspaceRevision >= deletionFrontier,
              projections == projections.sorted(by: { $0.stableKey < $1.stableKey }),
              Set(projections.map(\.domain)).count == projections.count,
              stateSHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis)) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, workspaceID: workspaceID, workspaceRevision: workspaceRevision, projections: projections, deletionFrontier: deletionFrontier, rebuiltAt: rebuiltAt) }
    private struct Basis: Codable { let schemaVersion: Int; let workspaceID: WorkspaceID; let workspaceRevision: UInt64; let projections: [PrivateSystemDiscoveryProjectionDescriptorV1]; let deletionFrontier: UInt64; let rebuiltAt: Date }
}

struct PrivateSystemDiscoveryStateMapV1: Codable, Equatable, Sendable {
    let workspaces: [PrivateSystemDiscoveryWorkspaceStateV1]
    init(workspaces: [PrivateSystemDiscoveryWorkspaceStateV1]) throws {
        self.workspaces = workspaces; try validate()
    }
    func validate() throws {
        try workspaces.forEach { try $0.validate() }
        guard workspaces == workspaces.sorted(by: { $0.workspaceID.rawValue.uuidString < $1.workspaceID.rawValue.uuidString }),
              Set(workspaces.map(\.workspaceID)).count == workspaces.count else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
}

enum PrivateSystemDiscoveryJournalOperationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case rebuild = "REBUILD", removal = "REMOVAL"
}

struct PrivateSystemDiscoveryOperationIDV1: Codable, Equatable, Hashable, Sendable {
    let rawValue: UUID
    let operation: PrivateSystemDiscoveryJournalOperationV1
    let workspaceID: WorkspaceID
    let inputSHA256: String
    let bindingSHA256: String
    init(rawValue: UUID, operation: PrivateSystemDiscoveryJournalOperationV1,
         workspaceID: WorkspaceID, inputSHA256: String) throws {
        self.rawValue = rawValue; self.operation = operation; self.workspaceID = workspaceID; self.inputSHA256 = inputSHA256
        try PrivateSystemDiscoveryValidationV1.id(rawValue); try PrivateSystemDiscoveryValidationV1.digest(inputSHA256)
        bindingSHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(rawValue: rawValue, operation: operation,
            workspaceID: workspaceID, inputSHA256: inputSHA256)); try validate()
    }
    func validate() throws {
        try PrivateSystemDiscoveryValidationV1.id(rawValue); try PrivateSystemDiscoveryValidationV1.digest(inputSHA256)
        try PrivateSystemDiscoveryValidationV1.digest(bindingSHA256)
        guard bindingSHA256 == (try PrivateSystemDiscoveryValidationV1.hash(Basis(rawValue: rawValue, operation: operation,
            workspaceID: workspaceID, inputSHA256: inputSHA256))) else { throw PrivateSystemDiscoveryFailureV1.corruptDigest }
    }
    private struct Basis: Codable { let rawValue: UUID; let operation: PrivateSystemDiscoveryJournalOperationV1; let workspaceID: WorkspaceID; let inputSHA256: String }
}

struct PrivateSystemDiscoveryRebuildRequestV1: Codable, Equatable, Sendable {
    let operationID: PrivateSystemDiscoveryOperationIDV1; let workspaceID: WorkspaceID
    let workspaceRevision: UInt64; let deletionFrontier: UInt64; let sourceStateSHA256: String
    let requestedAt: Date; let requestSHA256: String
    init(operationRawID: UUID, workspaceID: WorkspaceID, workspaceRevision: UInt64,
         deletionFrontier: UInt64, sourceStateSHA256: String, requestedAt: Date) throws {
        operationID = try .init(rawValue: operationRawID, operation: .rebuild, workspaceID: workspaceID, inputSHA256: sourceStateSHA256)
        self.workspaceID = workspaceID; self.workspaceRevision = workspaceRevision; self.deletionFrontier = deletionFrontier
        self.sourceStateSHA256 = sourceStateSHA256; self.requestedAt = requestedAt
        requestSHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(operationID: operationID, workspaceID: workspaceID,
            workspaceRevision: workspaceRevision, deletionFrontier: deletionFrontier, sourceStateSHA256: sourceStateSHA256, requestedAt: requestedAt)); try validate()
    }
    func validate() throws {
        try operationID.validate(); try PrivateSystemDiscoveryValidationV1.digest(sourceStateSHA256)
        try PrivateSystemDiscoveryValidationV1.instant(requestedAt)
        guard operationID.operation == .rebuild, operationID.workspaceID == workspaceID,
              operationID.inputSHA256 == sourceStateSHA256, workspaceRevision >= deletionFrontier,
              requestSHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis)) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    private var basis: Basis { .init(operationID: operationID, workspaceID: workspaceID, workspaceRevision: workspaceRevision, deletionFrontier: deletionFrontier, sourceStateSHA256: sourceStateSHA256, requestedAt: requestedAt) }
    private struct Basis: Codable { let operationID: PrivateSystemDiscoveryOperationIDV1; let workspaceID: WorkspaceID; let workspaceRevision: UInt64; let deletionFrontier: UInt64; let sourceStateSHA256: String; let requestedAt: Date }
}

struct PrivateSystemDiscoveryRemovalRequestV1: Codable, Equatable, Sendable {
    let operationID: PrivateSystemDiscoveryOperationIDV1; let workspaceID: WorkspaceID
    let priorStateSHA256: String; let requestedAt: Date; let requestSHA256: String
    init(operationRawID: UUID, workspaceID: WorkspaceID, priorStateSHA256: String, requestedAt: Date) throws {
        operationID = try .init(rawValue: operationRawID, operation: .removal, workspaceID: workspaceID, inputSHA256: priorStateSHA256)
        self.workspaceID = workspaceID; self.priorStateSHA256 = priorStateSHA256; self.requestedAt = requestedAt
        requestSHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(operationID: operationID, workspaceID: workspaceID,
            priorStateSHA256: priorStateSHA256, requestedAt: requestedAt)); try validate()
    }
    func validate() throws {
        try operationID.validate(); try PrivateSystemDiscoveryValidationV1.digest(priorStateSHA256); try PrivateSystemDiscoveryValidationV1.instant(requestedAt)
        guard operationID.operation == .removal, operationID.workspaceID == workspaceID,
              operationID.inputSHA256 == priorStateSHA256,
              requestSHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis)) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    private var basis: Basis { .init(operationID: operationID, workspaceID: workspaceID, priorStateSHA256: priorStateSHA256, requestedAt: requestedAt) }
    private struct Basis: Codable { let operationID: PrivateSystemDiscoveryOperationIDV1; let workspaceID: WorkspaceID; let priorStateSHA256: String; let requestedAt: Date }
}
enum PrivateSystemDiscoveryJournalStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case prepared = "PREPARED", effectApplied = "EFFECT_APPLIED", committed = "COMMITTED"
}
struct PrivateSystemDiscoveryJournalEntryV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let operationID: UUID; let workspaceID: WorkspaceID
    let operation: PrivateSystemDiscoveryJournalOperationV1; let expectedPriorStateSHA256: String?
    let resultingStateSHA256: String?; let state: PrivateSystemDiscoveryJournalStateV1
    let recordedAt: Date; let entrySHA256: String
    init(operationID: UUID, workspaceID: WorkspaceID, operation: PrivateSystemDiscoveryJournalOperationV1,
         expectedPriorStateSHA256: String?, resultingStateSHA256: String?,
         state: PrivateSystemDiscoveryJournalStateV1, recordedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.operationID = operationID; self.workspaceID = workspaceID; self.operation = operation
        self.expectedPriorStateSHA256 = expectedPriorStateSHA256; self.resultingStateSHA256 = resultingStateSHA256
        self.state = state; self.recordedAt = recordedAt
        entrySHA256 = try PrivateSystemDiscoveryValidationV1.hash(Basis(schemaVersion: Self.schemaVersion, operationID: operationID,
            workspaceID: workspaceID, operation: operation, expectedPriorStateSHA256: expectedPriorStateSHA256,
            resultingStateSHA256: resultingStateSHA256, state: state, recordedAt: recordedAt)); try validate()
    }
    init(operationID: PrivateSystemDiscoveryOperationIDV1, expectedPriorStateSHA256: String?,
         resultingStateSHA256: String?, state: PrivateSystemDiscoveryJournalStateV1, recordedAt: Date) throws {
        try operationID.validate()
        try self.init(operationID: operationID.rawValue, workspaceID: operationID.workspaceID,
            operation: operationID.operation, expectedPriorStateSHA256: expectedPriorStateSHA256,
            resultingStateSHA256: resultingStateSHA256, state: state, recordedAt: recordedAt)
    }
    func validate() throws {
        try PrivateSystemDiscoveryValidationV1.id(operationID); try PrivateSystemDiscoveryValidationV1.instant(recordedAt)
        try expectedPriorStateSHA256.map(PrivateSystemDiscoveryValidationV1.digest)
        try resultingStateSHA256.map(PrivateSystemDiscoveryValidationV1.digest)
        guard schemaVersion == Self.schemaVersion,
              (state == .prepared ? resultingStateSHA256 == nil : resultingStateSHA256 != nil),
              entrySHA256 == (try PrivateSystemDiscoveryValidationV1.hash(basis)) else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, operationID: operationID, workspaceID: workspaceID, operation: operation, expectedPriorStateSHA256: expectedPriorStateSHA256, resultingStateSHA256: resultingStateSHA256, state: state, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let operationID: UUID; let workspaceID: WorkspaceID; let operation: PrivateSystemDiscoveryJournalOperationV1; let expectedPriorStateSHA256: String?; let resultingStateSHA256: String?; let state: PrivateSystemDiscoveryJournalStateV1; let recordedAt: Date }
}
