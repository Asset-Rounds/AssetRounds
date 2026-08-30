import AVFoundation
import Foundation
import UIKit

enum CameraScheduleBoundaryV1 { static let cameraResolutionMayStartOccurrence = false }

enum C51ScheduleCameraBoundaryV1 {
    static let cameraCaptureDoesNotStartOccurrence = true
    static let scheduleGenerationRequestsNoCameraPermission = true
    static let cameraAdapterRemainsCaptureAuthority = true
}

enum CameraAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
struct CameraAdapter {
    typealias AuthorizationStatusProvider = () -> CameraAuthorizationStatus
    typealias AuthorizationRequester = () async -> CameraAuthorizationStatus
    typealias AvailabilityProvider = () -> Bool

    static let live = CameraAdapter(
        authorizationStatus: {
            mapAuthorizationStatus(
                AVCaptureDevice.authorizationStatus(for: .video)
            )
        },
        requestAuthorization: {
            guard AVCaptureDevice.authorizationStatus(for: .video)
                    == .notDetermined else {
                return mapAuthorizationStatus(
                    AVCaptureDevice.authorizationStatus(for: .video)
                )
            }
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return mapAuthorizationStatus(
                AVCaptureDevice.authorizationStatus(for: .video)
            )
        },
        isCameraAvailable: {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }
    )

    private let authorizationStatusProvider: AuthorizationStatusProvider
    private let authorizationRequester: AuthorizationRequester
    private let availabilityProvider: AvailabilityProvider

    init(
        authorizationStatus: @escaping AuthorizationStatusProvider,
        requestAuthorization: @escaping AuthorizationRequester,
        isCameraAvailable: @escaping AvailabilityProvider
    ) {
        authorizationStatusProvider = authorizationStatus
        authorizationRequester = requestAuthorization
        availabilityProvider = isCameraAvailable
    }

    func authorizationStatus() -> CameraAuthorizationStatus {
        authorizationStatusProvider()
    }

    func requestAuthorization() async -> CameraAuthorizationStatus {
        await authorizationRequester()
    }

    func isCameraAvailable() -> Bool {
        availabilityProvider()
    }

    private static func mapAuthorizationStatus(
        _ status: AVAuthorizationStatus
    ) -> CameraAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

enum AssetLocatorCameraBoundaryV1 {
    static let cameraResolutionUsesOfflineResolver = true
    static let successfulDecodeStartsWork = false

    static func decodedInput(_ data: Data) -> LocatorDecodedInputV1 {
        AssetLocatorInputDecoderV1.decode(data, source: .camera)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_Camera_CameraAdapter {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_Camera_CameraAdapter_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_Camera_CameraAdapter {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/Camera/CameraAdapter.swift", role: .camera)
}

enum C31LightingCameraBoundaryV1 {
    static let captureRemainsUserObservedEvidence = true
    static let cameraOutputDoesNotInferDarknessOrControlState = true
    static let manualOfflinePathRemainsAvailable = true
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_Camera_CameraAdapter {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}


// MARK: - C33 deferred capture runtime boundary

/// P03-C33 defines bounded clip storage and review contracts only. Explicit
/// microphone/video capture intent and runtime permissions remain P04-C25.
enum TemporalEvidenceCaptureRuntimeBoundaryV1 {
    static let addsMicrophoneRuntime = false
    static let addsVideoRecordingRuntime = false
    static let backgroundCaptureAllowed = false
    static let explicitCaptureIntentRequired = true
    static let manualFileImportFallbackPreserved = true
}

/// C45 camera input may resolve an opaque QR payload but never mutates workspace state.
enum C45AssetLabelBoundary_CameraAdapterV1 {
    static func validate(_ plan: AssetLabelGenerationPlanV1) throws { try plan.validate() }
    static let providesScannerUIOrMutation = false
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_Camera_CameraAdapter_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}
