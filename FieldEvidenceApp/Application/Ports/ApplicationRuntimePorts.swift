import Foundation

enum C52ServiceRequestRuntimePortBoundaryV1 {
    static let hostedTransportEnabled = false
    static let automaticDispatchEnabled = false
    static let capabilityBytesEnterRuntimePort = false
}

protocol ScheduleProjectionClockV1: Sendable { func nowUTC() -> Date }

enum C51ScheduleRuntimeBoundaryV1 {
    static let injectedClockType = ScheduleProjectionClockV1.self
    static let localOnly = true
    static let eventKitPermissionRequested = false
    static let backgroundScheduleDaemon = false
    static let frozenTimeBasisIsReused = true
}

protocol ApplicationClock: Sendable {
    /// Wall time for durable records and user-visible calendar context only.
    /// It must never be used to order causal mutations or measure durations.
    func now() -> Date
}

enum C33TemporalEvidenceRuntimeBoundaryV1 { static let runtimeCaptureProviderOwnedByC33=false;static let automaticTranscriptionEnabled=false;static let clockIsInjected=true;static let canonicalMutationKind:WorkspaceCommandKindV1 = .applyTemporalEvidence }

/// An in-process monotonic instant. It deliberately has no Codable
/// conformance because monotonic ticks have no meaning after process restart.
struct ApplicationMonotonicInstantV1: Equatable, Comparable, Sendable {
    let uptimeNanoseconds: UInt64

    init(uptimeNanoseconds: UInt64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }

    static func < (
        lhs: ApplicationMonotonicInstantV1,
        rhs: ApplicationMonotonicInstantV1
    ) -> Bool {
        lhs.uptimeNanoseconds < rhs.uptimeNanoseconds
    }
}

protocol ApplicationMonotonicClockV1: Sendable {
    func instant() -> ApplicationMonotonicInstantV1
}

protocol ApplicationIDSource: Sendable {
    func makeID() -> UUID
}

enum ApplicationFileAuthorityErrorV1: Error, Equatable {
    case invalidComponent
}

/// Produces deterministic, device-local temporary names for a mutation.
///
/// The authority returns a relative path component only. The caller remains
/// responsible for resolving it beneath an already-authorized generation root.
protocol ApplicationFileAuthorityV1: Sendable {
    func temporaryRelativePath(
        mutationID: MutationIDV1,
        component: String
    ) throws -> String
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_Ports_ApplicationRuntimePorts {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_Ports_ApplicationRuntimePorts_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Application_Ports_ApplicationRuntimePorts {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/Ports/ApplicationRuntimePorts.swift", role: .port)
}

enum C31LightingRuntimePortBoundaryV1 {
    static let projectionIsLocalAndMetadataOnly = true
    static let cameraAndSolarInputsRemainRecordedFacts = true
    static let noRemoteControlOrOperationalInference = true
}
// MARK: - C32 assistance runtime capability boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_Ports_ApplicationRuntimePorts_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let capabilityUnavailableKeepsManualPath = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}

enum AssetLabelRuntimeLimitsV1 {
    static let maximumItems = AssetLabelGenerationPlanV1.maximumItemCount
    static let maximumArtifacts = LabelArtifactKindV1.allCases.count
    static let requiresProtectedLocalFiles = true
    static let allowsProviderOrNetworkRuntime = false
    static let claimsNativeAcceptanceOrPhysicalScan = false
}

// MARK: - C46 explicit system handoff ports

/// Stable navigation state for a user-reviewed operational handoff.  Route
/// restoration deliberately contains identity only; destination values are
/// resolved from canonical workspace state immediately before the OS call.
enum OperationalContactHandoffRouteV1: Codable, Equatable, Hashable, Sendable {
    case directions(siteID: UUID)
    case call(contactPointID: UUID)
    case text(contactPointID: UUID)
    case email(contactPointID: UUID)

    var targetID: UUID {
        switch self {
        case let .directions(siteID): siteID
        case let .call(contactPointID), let .text(contactPointID),
             let .email(contactPointID): contactPointID
        }
    }

    var kind: SystemHandoffKindV1 {
        switch self {
        case .directions: .directions
        case .call: .call
        case .text: .text
        case .email: .email
        }
    }

    var targetKind: SystemHandoffTargetKindV1 {
        switch self {
        case .directions: .site
        case .call, .text, .email: .serviceContactPoint
        }
    }
}

/// The exact, user-visible source of an operational handoff. This identity is
/// deliberately non-Codable: C31 presentation state is ephemeral and may not
/// become scene restoration, history, diagnostics, or analytics state.
enum OperationalContactHandoffSubjectV1: Equatable, Hashable, Sendable {
    case site(siteID: UUID)
    case party(partyID: UUID)

    var stableID: UUID {
        switch self {
        case let .site(siteID): siteID
        case let .party(partyID): partyID
        }
    }
}

/// One currently valid contact value displayed in an ephemeral Party handoff
/// chooser. The value remains in memory only while the chooser is presented.
struct OperationalContactHandoffContactPresentationV1: Equatable, Sendable {
    let contactPointID: UUID
    let kind: ServiceContactKindV1
    let label: ServiceContactLabelV1
    let displayValue: String
    let preferred: Bool
    let target: SystemHandoffTargetReferenceV1

    init(contact: ServiceContactPointV1) throws {
        try contact.validate()
        guard contact.lifecycle == .effective else {
            throw OperationalContactFailureV1.invalidHandoffTarget
        }
        contactPointID = contact.contactPointID
        kind = contact.kind
        label = contact.label
        displayValue = contact.displayValue
        preferred = contact.preferred
        target = try SystemHandoffTargetReferenceV1(
            workspaceID: contact.workspaceID,
            kind: .serviceContactPoint,
            targetID: contact.contactPointID,
            expectedRevision: contact.revision,
            expectedSHA256: contact.contactPointSHA256
        )
    }
}

/// A point-in-time Site or Party presentation read. It is intentionally not
/// Codable because it contains customer-work values only needed to let the
/// user review an explicit system handoff.
struct OperationalContactHandoffPresentationSnapshotV1: Equatable, Sendable {
    let subject: OperationalContactHandoffSubjectV1
    let displayName: String
    let directions: SiteDirectionsTargetSnapshotV1?
    let contacts: [OperationalContactHandoffContactPresentationV1]

    init(
        subject: OperationalContactHandoffSubjectV1,
        displayName: String,
        directions: SiteDirectionsTargetSnapshotV1? = nil,
        contacts: [OperationalContactHandoffContactPresentationV1] = []
    ) throws {
        guard !displayName.isEmpty,
              displayName == displayName.precomposedStringWithCanonicalMapping else {
            throw OperationalContactFailureV1.invalidValue
        }
        let ordered = contacts.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            if lhs.preferred != rhs.preferred { return lhs.preferred }
            if lhs.label != rhs.label { return lhs.label.rawValue < rhs.label.rawValue }
            return lhs.contactPointID.uuidString < rhs.contactPointID.uuidString
        }
        guard Set(ordered.map(\.contactPointID)).count == ordered.count else {
            throw OperationalContactFailureV1.invalidValue
        }
        switch subject {
        case .site:
            guard directions != nil, ordered.isEmpty else {
                throw OperationalContactFailureV1.invalidHandoffTarget
            }
        case .party:
            guard directions == nil else {
                throw OperationalContactFailureV1.invalidHandoffTarget
            }
            let preferredCounts = Dictionary(grouping: ordered, by: \.kind)
                .values.map { $0.filter(\.preferred).count }
            guard preferredCounts.allSatisfy({ $0 <= 1 }) else {
                throw OperationalContactFailureV1.preferredConflict
            }
        }
        self.subject = subject
        self.displayName = displayName
        self.directions = directions
        self.contacts = ordered
    }
}

/// Canonical read authority. Implementations may materialize a destination
/// only for the duration of a handoff; callers must never retain it in routes,
/// intents, presentation history, or analytics.
@MainActor
protocol OperationalContactHandoffQueryingV1: SystemHandoffTargetResolvingV1 {
    /// Produces the bounded Site or Party chooser material for one foreground
    /// presentation. Implementations must not cache or persist this value.
    func currentHandoffPresentationSnapshot(
        workspaceID: WorkspaceID,
        subject: OperationalContactHandoffSubjectV1
    ) async throws -> OperationalContactHandoffPresentationSnapshotV1?

    func currentSiteDirectionsSnapshot(
        workspaceID: WorkspaceID,
        siteID: UUID
    ) async throws -> SiteDirectionsTargetSnapshotV1?

    func currentServiceContactPoint(
        workspaceID: WorkspaceID,
        contactPointID: UUID
    ) async throws -> ServiceContactPointV1?

    func handoffIntent(
        workspaceID: WorkspaceID,
        intentID: UUID
    ) async throws -> SystemHandoffIntentV1?
}

extension OperationalContactHandoffQueryingV1 {
    func currentTargetReference(
        workspaceID: WorkspaceID,
        route: OperationalContactHandoffRouteV1
    ) async throws -> SystemHandoffTargetReferenceV1? {
        switch route {
        case let .directions(siteID):
            return try await currentSiteDirectionsSnapshot(
                workspaceID: workspaceID,
                siteID: siteID
            )?.currentTarget
        case let .call(contactPointID), let .text(contactPointID),
             let .email(contactPointID):
            guard let contact = try await currentServiceContactPoint(
                workspaceID: workspaceID,
                contactPointID: contactPointID
            ) else { return nil }
            return try SystemHandoffTargetReferenceV1(
                workspaceID: contact.workspaceID,
                kind: .serviceContactPoint,
                targetID: contact.contactPointID,
                expectedRevision: contact.revision,
                expectedSHA256: contact.contactPointSHA256
            )
        }
    }

    func resolveForHandoff(
        _ intent: SystemHandoffIntentV1
    ) async -> SystemHandoffResolutionV1 {
        do {
            try intent.validate()
            guard intent.disposition == .activeSourceWorkspace else {
                return .targetInvalid
            }
            switch intent.kind {
            case .directions:
                guard let snapshot = try await currentSiteDirectionsSnapshot(
                    workspaceID: intent.workspaceID,
                    siteID: intent.target.targetID
                ) else { return .targetMissing }
                guard snapshot.currentTarget == intent.target else {
                    return .targetStale
                }
                return .resolved(try SystemHandoffRequestV1(
                    intent: intent,
                    currentTarget: snapshot.currentTarget,
                    destination: snapshot.preferredDestination()
                ))
            case .call, .text, .email:
                guard let contact = try await currentServiceContactPoint(
                    workspaceID: intent.workspaceID,
                    contactPointID: intent.target.targetID
                ) else { return .targetMissing }
                try contact.validate()
                guard contact.workspaceID == intent.workspaceID,
                      contact.lifecycle == .effective else {
                    return .targetInvalid
                }
                let current = try SystemHandoffTargetReferenceV1(
                    workspaceID: contact.workspaceID,
                    kind: .serviceContactPoint,
                    targetID: contact.contactPointID,
                    expectedRevision: contact.revision,
                    expectedSHA256: contact.contactPointSHA256
                )
                guard current == intent.target else { return .targetStale }
                let destination: SystemHandoffDestinationV1
                switch (intent.kind, contact.kind) {
                case (.call, .phone), (.text, .phone):
                    destination = .phone(contact.displayValue)
                case (.email, .email):
                    destination = .email(contact.displayValue)
                default:
                    return .targetInvalid
                }
                return .resolved(try SystemHandoffRequestV1(
                    intent: intent,
                    currentTarget: current,
                    destination: destination
                ))
            }
        } catch {
            return .targetInvalid
        }
    }
}

/// Compatibility name for the sole core-owned canonical writer protocol.
/// This alias cannot introduce storage, row writes, or a second writer.
typealias OperationalContactCanonicalWorkspaceWritingV1 =
    OperationalContactMutationCommittingV1

/// One revision-bound view used to construct a complete PARTY_CONTACTS_V1
/// mutation. `contacts` includes every current contact in each requested
/// party/kind scope so predecessors and preferred selection cannot be computed
/// from a partial import file.
struct OperationalContactImportCurrentStateV1: Equatable, Sendable {
    let parties: [ServicePartyReferenceV1]
    let contacts: [ServiceContactPointV1]

    init(
        parties: [ServicePartyReferenceV1],
        contacts: [ServiceContactPointV1]
    ) throws {
        let orderedParties = parties.sorted { $0.partyID.uuidString < $1.partyID.uuidString }
        let orderedContacts = contacts.sorted {
            $0.contactPointID.uuidString < $1.contactPointID.uuidString
        }
        guard orderedParties.count == Set(orderedParties.map(\.partyID)).count,
              orderedContacts.count == Set(orderedContacts.map(\.contactPointID)).count else {
            throw OperationalContactFailureV1.invalidValue
        }
        for party in orderedParties { try party.validate() }
        for contact in orderedContacts { try contact.validate() }
        self.parties = orderedParties
        self.contacts = orderedContacts
    }
}

@MainActor
protocol OperationalContactImportQueryingV1: AnyObject {
    /// Must be one canonical, revision-bound query. A missing requested party
    /// or incomplete preferred scope fails acceptance before any write.
    func currentImportState(
        workspaceID: WorkspaceID,
        partyIDs: [UUID]
    ) async throws -> OperationalContactImportCurrentStateV1
}

enum C46SystemHandoffRuntimeBoundaryV1 {
    static let routeContainsStableIDsOnly = true
    static let destinationIsRequeriedAtTap = true
    static let platformOutcomeIsPersistent =
        OperationalContactPersistenceEnrollmentV1.handoffOutcomeIsPersistent
    static let usesContactsPermission = false
    static let usesCurrentLocationPermission = false
    static let allowsBackgroundHandoff = false
    static let allowsAutomaticRetryOrAlternateTarget = false
}

/// C34 adoption keeps runtime callers on the canonical route registry and
/// makes package availability resolve to a safe, non-mutating disposition.
enum C34RouteAdoptionAdapterV1 {
    static let appRootType = AppRootV1.self
    static let routeRegistryType = RouteRegistryV1.self
    static let packageSurfaceManifestType = PackageSurfaceManifestV1.self
    static let packageSurfaceRouteType = PackageSurfaceRouteV1.self
    static let navigationTargetType = NavigationTargetV1.self
    static let sceneSnapshotType = SceneNavigationSnapshotV1.self
    static let restorationReceiptType = RouteRestorationReceiptV1.self
    static let conformanceReceiptType = RouteConformanceReceiptV1.self
    static let roots = AppRootV1.frozenOrder
    static let startsAutomaticWork = false
    static let canonicalMutationCount = 0

    static func packageSurfaceTarget(
        workspaceID: WorkspaceID,
        root: AppRootV1,
        routeID: String,
        requestedMode: NavigationRequestedModeV1 = .read
    ) throws -> NavigationTargetV1 {
        try RouteContractValidationV1.semanticID(routeID)
        return try NavigationTargetV1(
            workspaceID: workspaceID,
            destination: .packageSurface,
            root: root,
            packageSurfaceID: routeID,
            requestedMode: requestedMode
        )
    }

    static func resolve(
        _ target: NavigationTargetV1,
        registry: RouteRegistryV1,
        context: RouteResolutionContextV1
    ) throws -> RouteResolutionResultV1 {
        let result = try registry.resolve(target, context: context)
        guard result.canonicalMutationCount == 0, !result.startsAutomaticWork else {
            throw RouteContractFailureV1.packageAuthorityEscalation
        }
        return result
    }

    static func requireSafeFallback(
        _ result: RouteResolutionResultV1,
        availability: FeatureAvailabilityDecisionV1
    ) throws -> RouteResolutionResultV1 {
        guard result.canonicalMutationCount == 0,
              !result.startsAutomaticWork,
              availability.preservesEssentialOperations else {
            throw RouteContractFailureV1.packageAuthorityEscalation
        }
        if availability.reason != .available {
            guard result.disposition == .safeFallback else {
                throw RouteContractFailureV1.packageAuthorityEscalation
            }
        }
        return result
    }

    static func conformanceReceipt(
        for registry: RouteRegistryV1,
        evidenceKind: RouteEvidenceKindV1
    ) throws -> RouteConformanceReceiptV1 {
        let receipt = RouteConformanceReceiptV1(
            registry: registry,
            evidenceKind: evidenceKind,
            observedShellCount: 1,
            observedParserCount: 1,
            observedMutationAuthorityCount: 0
        )
        try receipt.validate()
        return receipt
    }
}

enum C34RouteAdoptionBoundary_ApplicationRuntimePortsV1 {
    static let fallbackType = NavigationFallbackV1.self
    static let availabilityDecisionType = FeatureAvailabilityDecisionV1.self
    static let packageAuthorityRemainsBounded = true
    static let startsAutomaticWork = false
}
