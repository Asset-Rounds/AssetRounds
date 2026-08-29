import Foundation

protocol ScheduleProjectionClockV1: Sendable { func nowUTC() -> Date }

protocol ApplicationClock: Sendable {
    /// Wall time for durable records and user-visible calendar context only.
    /// It must never be used to order causal mutations or measure durations.
    func now() -> Date
}

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
