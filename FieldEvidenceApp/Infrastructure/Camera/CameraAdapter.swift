import AVFoundation
import Foundation
import UIKit

enum CameraScheduleBoundaryV1 { static let cameraResolutionMayStartOccurrence = false }

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
