import CryptoKit
import Foundation

enum AppRootV1: String, CaseIterable, Codable, Hashable, Sendable {
    case today = "TODAY"
    case work = "WORK"
    case assets = "ASSETS"
    case reports = "REPORTS"

    static let frozenOrder: [Self] = [.today, .work, .assets, .reports]
}

/// C16 has exactly four shell roots. Search scopes are not shell roots and
/// may therefore include Locations without creating a fifth navigation tab.
enum WorkspaceExperienceRouteBoundaryV1 {
    static let rootCount = 4

    static func validate() throws {
        guard AppRootV1.frozenOrder.map(\.rawValue)
                == WorkspaceExperienceRootV1.canonicalShellOrder.map(\.rawValue),
              AppRootV1.frozenOrder.count == rootCount,
              Set(AppRootV1.frozenOrder).count == rootCount else {
            throw RouteContractFailureV1.invalidFallback
        }
    }
}

enum NavigationDestinationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case today = "TODAY"
    case work = "WORK"
    case assets = "ASSETS"
    case reports = "REPORTS"
    case settings = "SETTINGS"
    case draftReview = "DRAFT_REVIEW"
    case searchResults = "SEARCH_RESULTS"
    case scheduleOccurrence = "SCHEDULE_OCCURRENCE"
    case signoffEditor = "SIGNOFF_EDITOR"
    case signoffHistory = "SIGNOFF_HISTORY"
    case recipientReviewRequest = "RECIPIENT_REVIEW_REQUEST"
    case recipientReviewResponseQuarantine = "RECIPIENT_REVIEW_RESPONSE_QUARANTINE"
    case packageSurface = "PACKAGE_SURFACE"
    case startupMaintenance = "STARTUP_MAINTENANCE"
    case mutationRecovery = "MUTATION_RECOVERY"
    case recoveryCenter = "RECOVERY_CENTER"
}

enum NavigationRequestedModeV1: String, Codable, Hashable, Sendable {
    case read = "READ"
    case resume = "RESUME"
}

enum PrivateSystemDiscoveryRouteBoundaryV1 {
    static let allowedDestinations: Set<NavigationDestinationV1> = [.today, .assets, .reports]
    static func validate(_ target: NavigationTargetV1) throws {
        try target.validate()
        guard allowedDestinations.contains(target.destination), target.requestedMode == .read,
              target.packageSurfaceID == nil else { throw RouteContractFailureV1.missingSemanticIdentity }
    }
}

struct FieldPositionAnchorV1: Codable, Equatable, Hashable, Sendable {
    let sectionID: String?
    let fieldID: String?
    let selectedStableID: String?
    let boundedPosition: Int?

    init(sectionID: String? = nil, fieldID: String? = nil, selectedStableID: String? = nil, boundedPosition: Int? = nil) throws {
        self.sectionID = sectionID
        self.fieldID = fieldID
        self.selectedStableID = selectedStableID
        self.boundedPosition = boundedPosition
        try validate()
    }

    func validate() throws {
        try [sectionID, fieldID, selectedStableID].compactMap { $0 }.forEach(RouteContractValidationV1.semanticID)
        guard boundedPosition.map({ (0...100_000).contains($0) }) ?? true else { throw RouteContractFailureV1.invalidAnchor }
    }
}

struct RouteSearchAnchorV1: Codable, Equatable, Hashable, Sendable {
    let scopeID: String?
    let filterIDs: [String]
    let selectedStableID: String?
    let boundedPosition: Int?

    init(scopeID: String? = nil, filterIDs: [String] = [], selectedStableID: String? = nil, boundedPosition: Int? = nil) throws {
        self.scopeID = scopeID
        self.filterIDs = filterIDs.sorted()
        self.selectedStableID = selectedStableID
        self.boundedPosition = boundedPosition
        try validate()
    }

    init(sanitizing session: SearchSessionStateV1) throws {
        try session.validate()
        try self.init(
            scopeID: session.scope.rawValue,
            filterIDs: session.filters.map { $0.kind.rawValue },
            selectedStableID: session.selectedStableID ?? session.scrollAnchor?.stableID,
            boundedPosition: nil
        )
    }

    func validate() throws {
        try [scopeID, selectedStableID].compactMap { $0 }.forEach(RouteContractValidationV1.semanticID)
        try filterIDs.forEach(RouteContractValidationV1.semanticID)
        guard filterIDs == filterIDs.sorted(), Set(filterIDs).count == filterIDs.count,
              boundedPosition.map({ (0...100_000).contains($0) }) ?? true else { throw RouteContractFailureV1.invalidAnchor }
    }
}

struct NavigationFallbackV1: Codable, Equatable, Hashable, Sendable {
    let root: AppRootV1
    let destination: NavigationDestinationV1

    init(root: AppRootV1, destination: NavigationDestinationV1) throws {
        self.root = root
        self.destination = destination
        try validate()
    }

    static var today: Self { Self(uncheckedRoot: .today, destination: .today) }

    private init(uncheckedRoot: AppRootV1, destination: NavigationDestinationV1) {
        root = uncheckedRoot
        self.destination = destination
    }

    func validate() throws {
        let safeDestinations: Set<NavigationDestinationV1> = [.today, .work, .assets, .reports, .settings, .draftReview, .searchResults, .recoveryCenter]
        guard safeDestinations.contains(destination), RouteRegistryV1.root(for: destination) == root else {
            throw RouteContractFailureV1.invalidFallback
        }
    }
}

struct NavigationTargetV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let root: AppRootV1
    let destination: NavigationDestinationV1
    let stableEntityID: UUID?
    let stableScheduleDefinitionID: UUID?
    let stableScheduleReleaseID: UUID?
    let stableSessionID: UUID?
    let stableOccurrenceID: OccurrenceIDV1?
    let stableLocationID: UUID?
    let packageSurfaceID: String?
    let requestedMode: NavigationRequestedModeV1
    let expectedRevision: UInt64?
    let expectedScheduleRevision: UInt64?
    let expectedOccurrenceRevision: UInt64?
    let draftResumeAnchor: DraftResumeAnchorV1?
    let fieldPosition: FieldPositionAnchorV1?
    let searchAnchor: RouteSearchAnchorV1?
    let fallback: NavigationFallbackV1

    init(
        workspaceID: WorkspaceID,
        destination: NavigationDestinationV1,
        root: AppRootV1? = nil,
        stableEntityID: UUID? = nil,
        stableScheduleDefinitionID: UUID? = nil,
        stableScheduleReleaseID: UUID? = nil,
        stableSessionID: UUID? = nil,
        stableOccurrenceID: OccurrenceIDV1? = nil,
        stableLocationID: UUID? = nil,
        packageSurfaceID: String? = nil,
        requestedMode: NavigationRequestedModeV1 = .read,
        expectedRevision: UInt64? = nil,
        expectedScheduleRevision: UInt64? = nil,
        expectedOccurrenceRevision: UInt64? = nil,
        draftResumeAnchor: DraftResumeAnchorV1? = nil,
        fieldPosition: FieldPositionAnchorV1? = nil,
        searchAnchor: RouteSearchAnchorV1? = nil,
        fallback: NavigationFallbackV1 = .today
    ) throws {
        self.workspaceID = workspaceID
        self.root = root ?? RouteRegistryV1.root(for: destination)
        self.destination = destination
        self.stableEntityID = stableEntityID
        self.stableScheduleDefinitionID = stableScheduleDefinitionID
        self.stableScheduleReleaseID = stableScheduleReleaseID
        self.stableSessionID = stableSessionID
        self.stableOccurrenceID = stableOccurrenceID
        self.stableLocationID = stableLocationID
        self.packageSurfaceID = packageSurfaceID
        self.requestedMode = requestedMode
        self.expectedRevision = expectedRevision
        self.expectedScheduleRevision = expectedScheduleRevision
        self.expectedOccurrenceRevision = expectedOccurrenceRevision
        self.draftResumeAnchor = draftResumeAnchor
        self.fieldPosition = fieldPosition
        self.searchAnchor = searchAnchor
        self.fallback = fallback
        try validate()
    }

    func validate() throws {
        guard workspaceID.rawValue != RouteContractValidationV1.zeroUUID else { throw RouteContractFailureV1.invalidWorkspace }
        try draftResumeAnchor?.validate()
        try fieldPosition?.validate()
        try searchAnchor?.validate()
        try stableOccurrenceID?.validate()
        try fallback.validate()
        if let packageSurfaceID { try RouteContractValidationV1.semanticID(packageSurfaceID) }
        let stableIDs = [stableEntityID, stableScheduleDefinitionID, stableScheduleReleaseID, stableSessionID, stableLocationID].compactMap { $0 }
        guard (destination == .packageSurface) == (packageSurfaceID != nil),
              !stableIDs.contains(RouteContractValidationV1.zeroUUID),
              (destination == .packageSurface || root == RouteRegistryV1.root(for: destination)),
              destination != .signoffEditor || stableEntityID != nil,
              destination != .signoffHistory || stableEntityID != nil,
              destination != .scheduleOccurrence || (stableScheduleDefinitionID != nil && stableScheduleReleaseID != nil && stableOccurrenceID != nil && expectedScheduleRevision != nil && expectedOccurrenceRevision != nil),
              (stableScheduleDefinitionID == nil) == (expectedScheduleRevision == nil),
              (stableScheduleDefinitionID == nil) == (stableScheduleReleaseID == nil),
              expectedScheduleRevision.map({ $0 > 0 }) ?? true,
              expectedOccurrenceRevision.map({ $0 > 0 }) ?? true,
              (stableOccurrenceID == nil) == (expectedOccurrenceRevision == nil) else {
            throw RouteContractFailureV1.missingSemanticIdentity
        }
    }
}

struct SignoffEditorRouteV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let signoffID: UUID
    let expectedRevision: UInt64?

    var target: NavigationTargetV1 {
        get throws {
            try NavigationTargetV1(workspaceID: workspaceID, destination: .signoffEditor, stableEntityID: signoffID, requestedMode: .resume, expectedRevision: expectedRevision)
        }
    }
}

struct SignoffHistoryRouteV1: Codable, Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let signoffID: UUID

    var target: NavigationTargetV1 {
        get throws { try NavigationTargetV1(workspaceID: workspaceID, destination: .signoffHistory, stableEntityID: signoffID) }
    }
}

/// Exact derived identity used by the incumbent route registry when a
/// Scan-to-Work preview is ready. It deliberately excludes raw scan bytes and
/// URLs while retaining every canonical frontier needed to reject stale,
/// foreign, or mismatched resume attempts.
struct ScanToWorkRouteIdentityV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let session: RoundSessionReferenceV1
    let assetID: UUID
    let siteID: UUID
    let assetRevision: UInt64
    let assetSHA256: String
    let bindingSHA256: String
    let qualifiedPose: AssetPoseEventReferenceV1?

    init(flow: ScanToWorkFlowV1) throws {
        try flow.validateIntrinsic()
        guard flow.preview.outcome == .ready, let asset = flow.preview.asset else {
            throw ScanToWorkFailureV1.notReady
        }
        workspaceID = asset.workspaceID
        session = asset.readiness.session
        assetID = asset.assetID
        siteID = asset.siteID
        assetRevision = asset.assetRevision
        assetSHA256 = asset.assetSHA256
        bindingSHA256 = asset.bindingSHA256
        qualifiedPose = asset.qualifiedPose
        try validate(flow: flow)
    }

    func validate(flow: ScanToWorkFlowV1) throws {
        try flow.validateIntrinsic()
        guard self == (try Self(unvalidatedFlow: flow)) else {
            throw ScanToWorkFailureV1.stale
        }
    }

    private init(unvalidatedFlow flow: ScanToWorkFlowV1) throws {
        guard flow.preview.outcome == .ready, let asset = flow.preview.asset else {
            throw ScanToWorkFailureV1.notReady
        }
        workspaceID = asset.workspaceID; session = asset.readiness.session
        assetID = asset.assetID; siteID = asset.siteID
        assetRevision = asset.assetRevision; assetSHA256 = asset.assetSHA256
        bindingSHA256 = asset.bindingSHA256; qualifiedPose = asset.qualifiedPose
    }
}

struct ScanToWorkRouteV1: Codable, Equatable, Sendable {
    let identity: ScanToWorkRouteIdentityV1
    let requestedMode: NavigationRequestedModeV1
    let target: NavigationTargetV1

    init(flow: ScanToWorkFlowV1, requestedMode: NavigationRequestedModeV1 = .read) throws {
        identity = try ScanToWorkRouteIdentityV1(flow: flow)
        self.requestedMode = requestedMode
        target = try NavigationTargetV1(
            workspaceID: identity.workspaceID,
            destination: .work,
            stableEntityID: identity.assetID,
            stableSessionID: identity.session.sessionID,
            stableLocationID: identity.siteID,
            requestedMode: requestedMode
        )
        try validate(flow: flow)
    }

    func validate(flow: ScanToWorkFlowV1) throws {
        try identity.validate(flow: flow); try target.validate()
        guard target.workspaceID == identity.workspaceID,
              target.destination == .work,
              target.stableEntityID == identity.assetID,
              target.stableSessionID == identity.session.sessionID,
              target.stableLocationID == identity.siteID,
              target.requestedMode == requestedMode,
              target.expectedRevision == nil else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }
}

struct ScanToWorkNavigationProjectionV1: Codable, Equatable, Sendable {
    let flow: ScanToWorkFlowV1
    let route: ScanToWorkRouteV1?
    let resolution: RouteResolutionResultV1?
    let canonicalMutationCount: Int
    let startsAutomaticWork: Bool

    init(flow: ScanToWorkFlowV1, route: ScanToWorkRouteV1?, resolution: RouteResolutionResultV1?) throws {
        try flow.validateIntrinsic(); try route?.validate(flow: flow)
        self.flow = flow; self.route = route; self.resolution = resolution
        canonicalMutationCount = 0; startsAutomaticWork = false
        let ready = flow.preview.outcome == .ready
        guard ready == (route != nil), ready == (resolution != nil),
              resolution.map({ $0.disposition == .resolved && $0.target == route?.target
                  && $0.canonicalMutationCount == 0 && !$0.startsAutomaticWork }) ?? !ready else {
            throw ScanToWorkFailureV1.authorityMismatch
        }
    }
}

enum PackageSurfaceContributionKindV1: String, Codable, Hashable, Sendable {
    case destination = "DESTINATION"
    case navigationAction = "NAVIGATION_ACTION"
}

struct PackageSurfaceRouteV1: Codable, Equatable, Hashable, Sendable {
    let routeID: String
    let root: AppRootV1
    let destination: NavigationDestinationV1
    let kind: PackageSurfaceContributionKindV1
    let startsAutomaticWork: Bool

    func validate() throws {
        try RouteContractValidationV1.semanticID(routeID)
        guard destination == .packageSurface, startsAutomaticWork == false else { throw RouteContractFailureV1.packageAuthorityEscalation }
    }
}

struct PackageSurfaceManifestV1: Codable, Equatable, Sendable {
    let packageID: String
    let routes: [PackageSurfaceRouteV1]
    let addsNavigationShell: Bool
    let addsDeepLinkParser: Bool
    let addsSettingsTree: Bool
    let addsMutationAuthority: Bool

    init(
        packageID: String,
        routes: [PackageSurfaceRouteV1],
        addsNavigationShell: Bool = false,
        addsDeepLinkParser: Bool = false,
        addsSettingsTree: Bool = false,
        addsMutationAuthority: Bool = false
    ) throws {
        self.packageID = packageID
        self.routes = routes.sorted { $0.routeID < $1.routeID }
        self.addsNavigationShell = addsNavigationShell
        self.addsDeepLinkParser = addsDeepLinkParser
        self.addsSettingsTree = addsSettingsTree
        self.addsMutationAuthority = addsMutationAuthority
        try validate()
    }

    func validate() throws {
        try RouteContractValidationV1.semanticID(packageID)
        try routes.forEach { try $0.validate() }
        guard routes == routes.sorted(by: { $0.routeID < $1.routeID }),
              Set(routes.map(\.routeID)).count == routes.count,
              !addsNavigationShell, !addsDeepLinkParser, !addsSettingsTree, !addsMutationAuthority else {
            throw RouteContractFailureV1.packageAuthorityEscalation
        }
    }
}

struct RouteDescriptorV1: Codable, Equatable, Hashable, Sendable {
    let routeID: String
    let root: AppRootV1
    let destination: NavigationDestinationV1
    let packageID: String?
}

struct RouteResolutionContextV1: Equatable, Sendable {
    let currentWorkspaceID: WorkspaceID
    let currentRevision: UInt64
    let availablePackageIDs: Set<String>
    let unavailableStableIDs: Set<UUID>
    let unavailableOccurrenceIDs: Set<OccurrenceIDV1>
    let currentScheduleRevisions: [UUID: UInt64]
    let currentScheduleReleaseIDs: [UUID: UUID]
    let currentOccurrenceRevisions: [OccurrenceIDV1: UInt64]
    let protectedDataAvailable: Bool
    let availabilityRevoked: Bool

    init(currentWorkspaceID: WorkspaceID, currentRevision: UInt64, availablePackageIDs: Set<String> = [], unavailableStableIDs: Set<UUID> = [], unavailableOccurrenceIDs: Set<OccurrenceIDV1> = [], currentScheduleRevisions: [UUID: UInt64] = [:], currentScheduleReleaseIDs: [UUID: UUID] = [:], currentOccurrenceRevisions: [OccurrenceIDV1: UInt64] = [:], protectedDataAvailable: Bool = true, availabilityRevoked: Bool = false) {
        self.currentWorkspaceID = currentWorkspaceID
        self.currentRevision = currentRevision
        self.availablePackageIDs = availablePackageIDs
        self.unavailableStableIDs = unavailableStableIDs
        self.unavailableOccurrenceIDs = unavailableOccurrenceIDs
        self.currentScheduleRevisions = currentScheduleRevisions
        self.currentScheduleReleaseIDs = currentScheduleReleaseIDs
        self.currentOccurrenceRevisions = currentOccurrenceRevisions
        self.protectedDataAvailable = protectedDataAvailable
        self.availabilityRevoked = availabilityRevoked
    }
}

enum RouteFallbackReasonV1: String, Codable, Hashable, Sendable {
    case wrongWorkspace = "WRONG_WORKSPACE"
    case staleRevision = "STALE_REVISION"
    case deletedOrTombstoned = "DELETED_OR_TOMBSTONED"
    case retiredOrMissingPackage = "RETIRED_OR_MISSING_PACKAGE"
    case revokedAvailability = "REVOKED_AVAILABILITY"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case corruptSnapshot = "CORRUPT_SNAPSHOT"
    case unsupportedSnapshotVersion = "UNSUPPORTED_SNAPSHOT_VERSION"
    case invalidTarget = "INVALID_TARGET"
}

enum RouteResolutionDispositionV1: String, Codable, Hashable, Sendable {
    case resolved = "RESOLVED"
    case safeFallback = "SAFE_FALLBACK"
}

struct RouteResolutionResultV1: Codable, Equatable, Sendable {
    let disposition: RouteResolutionDispositionV1
    let target: NavigationTargetV1
    let reason: RouteFallbackReasonV1?
    let canonicalMutationCount: Int
    let startsAutomaticWork: Bool
}

struct RouteRegistryV1: Sendable {
    let descriptors: [RouteDescriptorV1]
    let manifests: [PackageSurfaceManifestV1]

    init(manifests: [PackageSurfaceManifestV1] = []) throws {
        try manifests.forEach { try $0.validate() }
        guard Set(manifests.map(\.packageID)).count == manifests.count else { throw RouteContractFailureV1.duplicatePackage }
        let builtIns = NavigationDestinationV1.allCases.filter { $0 != .packageSurface }.map {
            RouteDescriptorV1(routeID: "builtin.\($0.rawValue.lowercased())", root: Self.root(for: $0), destination: $0, packageID: nil)
        }
        let contributed = manifests.flatMap { manifest in
            manifest.routes.map { RouteDescriptorV1(routeID: $0.routeID, root: $0.root, destination: $0.destination, packageID: manifest.packageID) }
        }
        let all = builtIns + contributed
        guard Set(all.map(\.routeID)).count == all.count,
              Set(AppRootV1.frozenOrder) == Set(AppRootV1.allCases), AppRootV1.frozenOrder.count == 4 else {
            throw RouteContractFailureV1.duplicateRoute
        }
        self.descriptors = all.sorted { $0.routeID < $1.routeID }
        self.manifests = manifests.sorted { $0.packageID < $1.packageID }
    }

    func resolve(_ target: NavigationTargetV1, context: RouteResolutionContextV1) throws -> RouteResolutionResultV1 {
        do { try target.validate() }
        catch { return try fallback(for: target, context: context, reason: .invalidTarget) }
        let reason: RouteFallbackReasonV1?
        if target.workspaceID != context.currentWorkspaceID { reason = .wrongWorkspace }
        else if !context.protectedDataAvailable { reason = .protectedDataUnavailable }
        else if context.availabilityRevoked { reason = .revokedAvailability }
        else if let revision = target.expectedRevision, revision != context.currentRevision { reason = .staleRevision }
        else if let scheduleID = target.stableScheduleDefinitionID,
                context.currentScheduleRevisions[scheduleID] == nil { reason = .deletedOrTombstoned }
        else if let scheduleID = target.stableScheduleDefinitionID, let revision = target.expectedScheduleRevision,
                context.currentScheduleRevisions[scheduleID] != revision { reason = .staleRevision }
        else if let scheduleID = target.stableScheduleDefinitionID,
                context.currentScheduleReleaseIDs[scheduleID] == nil { reason = .deletedOrTombstoned }
        else if let scheduleID = target.stableScheduleDefinitionID, let releaseID = target.stableScheduleReleaseID,
                context.currentScheduleReleaseIDs[scheduleID] != releaseID { reason = .staleRevision }
        else if let occurrenceID = target.stableOccurrenceID,
                context.currentOccurrenceRevisions[occurrenceID] == nil { reason = .deletedOrTombstoned }
        else if let occurrenceID = target.stableOccurrenceID, let revision = target.expectedOccurrenceRevision,
                context.currentOccurrenceRevisions[occurrenceID] != revision { reason = .staleRevision }
        else if [target.stableEntityID, target.stableScheduleDefinitionID, target.stableScheduleReleaseID, target.stableSessionID, target.stableLocationID].compactMap({ $0 }).contains(where: context.unavailableStableIDs.contains)
                    || target.stableOccurrenceID.map(context.unavailableOccurrenceIDs.contains) == true { reason = .deletedOrTombstoned }
        else if let surface = target.packageSurfaceID,
                !context.availablePackageIDs.contains(where: { packageID in
                    manifests.contains(where: { manifest in
                        manifest.packageID == packageID && manifest.routes.contains(where: { $0.routeID == surface && $0.root == target.root })
                    })
                }) { reason = .retiredOrMissingPackage }
        else { reason = nil }
        if let reason { return try fallback(for: target, context: context, reason: reason) }
        return RouteResolutionResultV1(disposition: .resolved, target: target, reason: nil, canonicalMutationCount: 0, startsAutomaticWork: false)
    }

    func fallback(for target: NavigationTargetV1, context: RouteResolutionContextV1, reason: RouteFallbackReasonV1) throws -> RouteResolutionResultV1 {
        let safeDestination: NavigationDestinationV1
        // Recovery is the fail-closed startup/support surface. A malformed or
        // unavailable recovery target must stay there rather than falling
        // through to a normal-shell destination.
        if target.destination == .recoveryCenter { safeDestination = .recoveryCenter }
        else if (try? target.fallback.validate()) != nil { safeDestination = target.fallback.destination }
        else { safeDestination = .today }
        let safe = try NavigationTargetV1(workspaceID: context.currentWorkspaceID, destination: safeDestination, fallback: .today)
        return RouteResolutionResultV1(disposition: .safeFallback, target: safe, reason: reason, canonicalMutationCount: 0, startsAutomaticWork: false)
    }

    static func root(for destination: NavigationDestinationV1) -> AppRootV1 {
        switch destination {
        case .today, .startupMaintenance: return .today
        case .work, .draftReview, .scheduleOccurrence, .signoffEditor, .mutationRecovery: return .work
        case .assets, .searchResults, .recipientReviewRequest, .recipientReviewResponseQuarantine, .packageSurface: return .assets
        case .reports, .signoffHistory, .settings, .recoveryCenter: return .reports
        }
    }

    static func rootDestination(for root: AppRootV1) -> NavigationDestinationV1 {
        switch root {
        case .today: return .today
        case .work: return .work
        case .assets: return .assets
        case .reports: return .reports
        }
    }
}

enum RouteContractFailureV1: Error, Equatable {
    case invalidWorkspace
    case invalidSemanticID
    case invalidAnchor
    case invalidFallback
    case missingSemanticIdentity
    case packageAuthorityEscalation
    case duplicatePackage
    case duplicateRoute
}

enum RouteContractValidationV1 {
    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func semanticID(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 256,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.unicodeScalars.contains(where: { $0.properties.isBidiControl }) else {
            throw RouteContractFailureV1.invalidSemanticID
        }
    }
}

enum RouteCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func sha256<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}
