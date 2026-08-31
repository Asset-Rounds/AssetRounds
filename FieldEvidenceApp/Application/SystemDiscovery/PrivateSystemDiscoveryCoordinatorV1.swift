import Foundation

protocol PrivateSystemDiscoveryRouteContextPortV1: Sendable {
    func routeContext(workspaceID: WorkspaceID) async throws -> RouteResolutionContextV1
}

/// Sole C14 execution endpoint. The access gate is always consulted before
/// availability, route context, private parameter resolution, preview, or
/// speech-visible result construction. A locked request is discarded; callers
/// must submit a fresh request after authorization.
struct PrivateSystemDiscoveryCoordinatorV1: Sendable {
    private let accessGate: any AppAccessGatePortV1
    private let availability: any PrivateSystemDiscoveryAvailabilityPortV1
    private let projection: any PrivateSystemDiscoveryProjectionPortV1
    private let routeContext: any PrivateSystemDiscoveryRouteContextPortV1
    private let routeRegistry: RouteRegistryV1

    init(accessGate: any AppAccessGatePortV1,
         availability: any PrivateSystemDiscoveryAvailabilityPortV1,
         projection: any PrivateSystemDiscoveryProjectionPortV1,
         routeContext: any PrivateSystemDiscoveryRouteContextPortV1,
         routeRegistry: RouteRegistryV1) {
        self.accessGate = accessGate; self.availability = availability; self.projection = projection
        self.routeContext = routeContext; self.routeRegistry = routeRegistry
    }

    func execute(_ request: PrivateSystemDiscoveryRequestV1) async throws -> PrivateSystemDiscoveryResultV1 {
        do { try await accessGate.requireContentAccess() }
        catch { return .unlockRequired }

        let decision = try await availability.availability(
            workspaceID: request.workspaceID, action: request.action, evaluatedAt: request.requestedAt
        )
        try decision.validate()
        guard decision.workspaceID == request.workspaceID, decision.action == request.action, decision.available else {
            return .unavailable
        }

        switch request.action {
        case .searchWorkspace:
            guard let token = request.privateParameterToken else { throw PrivateSystemDiscoveryFailureV1.invalidValue }
            let value = try await projection.resolvePrivateRead(workspaceID: request.workspaceID, opaqueParameterToken: token)
            guard value.workspaceID == request.workspaceID else { throw PrivateSystemDiscoveryFailureV1.wrongWorkspace }
            return .read(value)
        case .openToday, .openAssets, .openReports:
            let destination: NavigationDestinationV1
            switch request.action {
            case .openToday: destination = .today
            case .openAssets: destination = .assets
            case .openReports: destination = .reports
            case .searchWorkspace: throw PrivateSystemDiscoveryFailureV1.unsupportedAction
            }
            let context = try await routeContext.routeContext(workspaceID: request.workspaceID)
            guard context.currentWorkspaceID == request.workspaceID, context.protectedDataAvailable,
                  !context.availabilityRevoked else { throw PrivateSystemDiscoveryFailureV1.wrongWorkspace }
            let target = try NavigationTargetV1(workspaceID: request.workspaceID, destination: destination, requestedMode: .read)
            let result = try routeRegistry.resolve(target, context: context)
            guard result.canonicalMutationCount == 0, !result.startsAutomaticWork else { throw PrivateSystemDiscoveryFailureV1.unsafeRoute }
            return .navigation(result)
        }
    }

    /// Preview and speech intentionally share the same gate and do not cache a
    /// prior locked request or resolved parameter.
    func preview(_ request: PrivateSystemDiscoveryRequestV1) async throws -> PrivateSystemDiscoveryResultV1 {
        try await execute(request)
    }
}

struct PrivateSystemDiscoveryAvailabilityAdapterV1: PrivateSystemDiscoveryAvailabilityPortV1, Sendable {
    private let featurePolicy: FeaturePolicyLoaderV1
    private let preferences: any PrivateSystemDiscoveryPreferencePortV1
    private let accessGate: any AppAccessGatePortV1
    private let platformMajorVersion: Int
    private let protectedDataAvailable: @Sendable () async -> Bool

    init(featurePolicy: FeaturePolicyLoaderV1, preferences: any PrivateSystemDiscoveryPreferencePortV1,
         accessGate: any AppAccessGatePortV1, platformMajorVersion: Int,
         protectedDataAvailable: @escaping @Sendable () async -> Bool) {
        self.featurePolicy = featurePolicy; self.preferences = preferences; self.accessGate = accessGate
        self.platformMajorVersion = platformMajorVersion; self.protectedDataAvailable = protectedDataAvailable
    }
    func availability(workspaceID: WorkspaceID, action: PrivateSystemDiscoveryActionV1,
                      evaluatedAt: Date) async throws -> AppIntentAvailabilityV1 {
        let policy = try PrivateSystemDiscoveryFeaturePolicyBoundaryV1.resolve(using: featurePolicy)
        let selection = try preferences.readPrivateSystemDiscoveryOptIn()
        let accessState = await accessGate.currentState()
        let access = accessState.permitsContentAccess
        let protected = await protectedDataAvailable()
        let reason: FeatureAvailabilityReasonV1
        if policy.policyState != .enabled { reason = .packageNotEnabled }
        else if platformMajorVersion < policy.minimumPlatformMajorVersion { reason = .unsupportedOSOrDevice }
        else if !selection.contains(workspaceID) { reason = .workspacePolicyDisabled }
        else if !protected || !access { reason = .temporarilyUnavailable }
        else { reason = .available }
        return try AppIntentAvailabilityV1(workspaceID: workspaceID, action: action,
            optedIn: selection.contains(workspaceID), featureReason: reason,
            appAccessPermitsContent: access, protectedDataAvailable: protected, evaluatedAt: evaluatedAt)
    }
}

struct PrivateSystemDiscoverySearchProjectionAdapterV1: PrivateSystemDiscoveryProjectionPortV1, Sendable {
    private let search: SearchCoordinatorV1
    private let registry: SearchableFieldRegistryV1
    private let source: @Sendable (WorkspaceID) async throws -> SearchSourceRevisionV1
    private let resolveOpaqueQuery: @Sendable (String) async throws -> String
    init(search: SearchCoordinatorV1, registry: SearchableFieldRegistryV1,
         source: @escaping @Sendable (WorkspaceID) async throws -> SearchSourceRevisionV1,
         resolveOpaqueQuery: @escaping @Sendable (String) async throws -> String) {
        self.search = search; self.registry = registry; self.source = source; self.resolveOpaqueQuery = resolveOpaqueQuery
    }
    func resolvePrivateRead(workspaceID: WorkspaceID, opaqueParameterToken: String) async throws
        -> PrivateSystemDiscoveryReadProjectionV1 {
        let source = try await source(workspaceID)
        guard source.workspaceID == workspaceID.rawValue else { throw PrivateSystemDiscoveryFailureV1.wrongWorkspace }
        let query = try await resolveOpaqueQuery(opaqueParameterToken)
        let plan = try search.makePlan(query: query, maximumResults: 100, sourceRevision: source.commitRevision)
        let response = try await search.search(plan, source: source, registry: registry)
        let ids = try response.results.map { result -> UUID in
            guard result.workspaceID == workspaceID.rawValue, let id = UUID(uuidString: result.stableID) else {
                throw PrivateSystemDiscoveryFailureV1.invalidValue
            }
            return id
        }.sorted { $0.uuidString < $1.uuidString }
        return try PrivateSystemDiscoveryReadProjectionV1(workspaceID: workspaceID, resultIDs: ids,
            querySHA256: WorkspaceMutationCanonicalV1.sha256(plan))
    }
}

struct PrivateSystemDiscoveryRouteContextAdapterV1: PrivateSystemDiscoveryRouteContextPortV1, Sendable {
    private let load: @Sendable (WorkspaceID) async throws -> RouteResolutionContextV1
    init(load: @escaping @Sendable (WorkspaceID) async throws -> RouteResolutionContextV1) { self.load = load }
    func routeContext(workspaceID: WorkspaceID) async throws -> RouteResolutionContextV1 {
        let value = try await load(workspaceID)
        guard value.currentWorkspaceID == workspaceID else { throw PrivateSystemDiscoveryFailureV1.wrongWorkspace }
        return value
    }
}

struct PrivateSystemDiscoveryIntentWorkspaceAdapterV1: PrivateSystemDiscoveryIntentWorkspacePortV1, Sendable {
    private let preferences: any PrivateSystemDiscoveryPreferencePortV1
    private let currentWorkspace: @Sendable () async -> WorkspaceID?
    init(preferences: any PrivateSystemDiscoveryPreferencePortV1,
         currentWorkspace: @escaping @Sendable () async -> WorkspaceID?) {
        self.preferences = preferences; self.currentWorkspace = currentWorkspace
    }
    func selectedRealWorkspaceID() async -> WorkspaceID? {
        guard let current = await currentWorkspace(),
              let selection = try? preferences.readPrivateSystemDiscoveryOptIn(), selection.contains(current) else { return nil }
        return current
    }
}

struct PrivateSystemDiscoveryRuntimeV1: Sendable {
    let coordinator: PrivateSystemDiscoveryCoordinatorV1
    let intentWorkspace: PrivateSystemDiscoveryIntentWorkspaceAdapterV1
    init(accessGate: any AppAccessGatePortV1, featurePolicy: FeaturePolicyLoaderV1,
         preferences: any PrivateSystemDiscoveryPreferencePortV1, platformMajorVersion: Int,
         protectedDataAvailable: @escaping @Sendable () async -> Bool,
         search: SearchCoordinatorV1, searchRegistry: SearchableFieldRegistryV1,
         searchSource: @escaping @Sendable (WorkspaceID) async throws -> SearchSourceRevisionV1,
         resolveOpaqueQuery: @escaping @Sendable (String) async throws -> String,
         routeContext: @escaping @Sendable (WorkspaceID) async throws -> RouteResolutionContextV1,
         currentWorkspace: @escaping @Sendable () async -> WorkspaceID?, routeRegistry: RouteRegistryV1) {
        let availability = PrivateSystemDiscoveryAvailabilityAdapterV1(featurePolicy: featurePolicy, preferences: preferences,
            accessGate: accessGate, platformMajorVersion: platformMajorVersion, protectedDataAvailable: protectedDataAvailable)
        let projection = PrivateSystemDiscoverySearchProjectionAdapterV1(search: search, registry: searchRegistry,
            source: searchSource, resolveOpaqueQuery: resolveOpaqueQuery)
        let route = PrivateSystemDiscoveryRouteContextAdapterV1(load: routeContext)
        coordinator = PrivateSystemDiscoveryCoordinatorV1(accessGate: accessGate, availability: availability,
            projection: projection, routeContext: route, routeRegistry: routeRegistry)
        intentWorkspace = PrivateSystemDiscoveryIntentWorkspaceAdapterV1(preferences: preferences, currentWorkspace: currentWorkspace)
    }
}
