import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct CaptureStepView: View {
    static let legacyCaptureUnavailableAccessibilityIdentifier =
        "s3.runner.capture-unavailable"
    static let screenAccessibilityIdentifier = "s3.capture.screen"
    static let headingAccessibilityIdentifier = "s3.capture.heading"
    static let fixtureImportAccessibilityIdentifier = "s3.capture.import-fixture"
    static let previewAccessibilityIdentifier = "s3.capture.preview"
    static let retakeAccessibilityIdentifier = "s3.capture.retake"
    static let usePhotoAccessibilityIdentifier = "s3.capture.use-photo"
    static let takePhotoAccessibilityIdentifier = "s3.capture.take-photo"
    static let choosePhotosAccessibilityIdentifier = "s3.capture.choose-photos"
    static let openSettingsAccessibilityIdentifier = "s3.capture.open-settings"
    static let cannotCompleteAccessibilityIdentifier = "s3.capture.cannot-complete"
    static let outcomeUnavailableAccessibilityIdentifier =
        "s3.runner.outcome-unavailable"

    let assetID: UUID
    let coordinator: CheckRunnerCoordinator
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter
    let cannotComplete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var preparation: CapturePreparation?
    @State private var candidate: CaptureCandidate?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var cameraStatus: CameraAuthorizationStatus?
    @State private var presentsCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var didOpenCameraSettings = false
    @State private var showsCouldNotVerify = false

    var body: some View {
        Group {
            if showsCouldNotVerify {
                OutcomeReviewView(
                    assetID: assetID,
                    coordinator: coordinator,
                    startsWithCouldNotVerify: true
                )
            } else if let preparation, preparation.step == .outcome {
                OutcomeReviewView(
                    assetID: assetID,
                    coordinator: coordinator
                )
            } else {
                captureScroll
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .task {
            guard preparation == nil, errorMessage == nil else { return }
            loadPreparation()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            importPhotoItem(item)
        }
        .sheet(isPresented: $presentsCamera) {
            CameraCaptureView(
                onCapture: { data in
                    presentsCamera = false
                    importSourceData(data)
                },
                onCancel: {
                    presentsCamera = false
                    errorMessage = nil
                },
                onFailure: {
                    presentsCamera = false
                    errorMessage = BundledLocalizationCatalogV1.v30Text(.captureCameraFailure)
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.didBecomeActiveNotification
        )) { _ in
            guard didOpenCameraSettings else { return }
            didOpenCameraSettings = false
            cameraStatus = cameraAdapter.authorizationStatus()
        }
    }

    private var captureScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if let preparation {
                    captureContent(preparation)
                } else if let errorMessage {
                    failure(message: errorMessage)
                } else {
                    ProgressView(BundledLocalizationCatalogV1.v30Text(.captureCheckProgress))
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle(BundledLocalizationCatalogV1.v30Text(.captureContentNavigation))
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    @ViewBuilder
    private func captureContent(_ preparation: CapturePreparation) -> some View {
        if let purpose = preparation.purpose {
            WorklightCard {
                Text(heading(for: preparation.step, purpose: purpose))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(purpose.instruction)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let candidate {
                preview(candidate)

                captureActionLayout {
                    Button(BundledLocalizationCatalogV1.v30Text(.captureContentAction)) {
                        retake(candidate)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier(Self.retakeAccessibilityIdentifier)

                    Button(BundledLocalizationCatalogV1.v30Text(.capturePhotoAction)) {
                        usePhoto(candidate)
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier(Self.usePhotoAccessibilityIdentifier)
                }
            } else {
                captureActions(for: preparation.step)
            }

            if let errorMessage {
                WorklightCard {
                    WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.capturePhotoStatus))
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func captureActions(for step: WorkflowDraftStep) -> some View {
        Button(BundledLocalizationCatalogV1.v30Text(.capturePhotoAction2)) {
            takePhoto(for: step)
        }
        .buttonStyle(WorklightPrimaryButtonStyle())
        .disabled(isWorking)
        .accessibilityIdentifier(Self.takePhotoAccessibilityIdentifier)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Text(BundledLocalizationCatalogV1.v30Text(.capturePhotoLabel))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .disabled(isWorking)
        .accessibilityIdentifier(Self.choosePhotosAccessibilityIdentifier)

        if cameraStatus == .denied || cameraStatus == .restricted {
            WorklightCard {
                WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.captureCameraFailure2))
                Text(BundledLocalizationCatalogV1.v30Text(.capturePhotoLabel2))
                    .font(.body)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(BundledLocalizationCatalogV1.v30Text(.captureContentAction2)) {
                openSettings()
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .accessibilityIdentifier(Self.openSettingsAccessibilityIdentifier)
        }

        Button(BundledLocalizationCatalogV1.v30Text(.captureContentAction3)) {
            showsCouldNotVerify = true
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
        .disabled(isWorking)
        .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.captureCheckAccessibility))
        .accessibilityIdentifier(Self.cannotCompleteAccessibilityIdentifier)

        if usesImportedCaptureFixturesForUITest {
            Button(BundledLocalizationCatalogV1.v30Text(.capturePhotoAction3)) {
                importFixture(for: step)
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
            .disabled(isWorking)
            .accessibilityIdentifier(Self.fixtureImportAccessibilityIdentifier)
        }
    }

    private func preview(_ candidate: CaptureCandidate) -> some View {
        WorklightCard {
            if let image = UIImage(data: candidate.previewJPEG) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.capturePhotoAccessibility))
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            } else {
                Text(BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            }
        }
    }

    private var captureActionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DesignTokens.Spacing.medium))
            : AnyLayout(HStackLayout(spacing: DesignTokens.Spacing.medium))
    }

    private func failure(message: String) -> some View {
        WorklightCard {
            WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.captureCheckFailure))
            Text(message)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(BundledLocalizationCatalogV1.v30Text(.captureContentRetry)) {
                errorMessage = nil
                loadPreparation()
            }
            .buttonStyle(WorklightSecondaryButtonStyle())
        }
    }

    private func heading(
        for step: WorkflowDraftStep,
        purpose: SignPack.EvidencePurpose
    ) -> String {
        step == .wide
            ? BundledLocalizationCatalogV1.v30CaptureStepStepOfTwo(step: 1, purpose: purpose.display)
            : BundledLocalizationCatalogV1.v30CaptureStepStepOfTwo(step: 2, purpose: purpose.display)
    }

    private func loadPreparation() {
        do {
            preparation = try coordinator.prepareCapture(assetID: assetID)
            errorMessage = nil
        } catch {
            preparation = nil
            errorMessage = BundledLocalizationCatalogV1.v30Text(.captureCheckFailure2)
        }
    }

    private func takePhoto(for step: WorkflowDraftStep) {
        guard !isWorking else { return }
        errorMessage = nil
        Task { @MainActor in
            let status = cameraAdapter.authorizationStatus()
            let resolvedStatus: CameraAuthorizationStatus
            if status == .notDetermined {
                isWorking = true
                resolvedStatus = await cameraAdapter.requestAuthorization()
                isWorking = false
            } else {
                resolvedStatus = status
            }
            cameraStatus = resolvedStatus
            guard resolvedStatus == .authorized else { return }
            guard cameraAdapter.isCameraAvailable() else {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.captureCameraFailure3)
                return
            }
            if usesImportedCaptureFixturesForUITest {
                importFixture(for: step)
            } else {
                presentsCamera = true
            }
        }
    }

    private func importPhotoItem(_ item: PhotosPickerItem) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer {
                selectedPhotoItem = nil
                isWorking = false
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure2)
                    return
                }
                candidate = try await coordinator.importCandidate(
                    assetID: assetID,
                    sourceData: data,
                    createdAt: Date()
                )
            } catch CheckRunnerCoordinatorError.storageUnavailable {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.captureContentFailure)
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure3)
            }
        }
    }

    private func importSourceData(_ data: Data) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                candidate = try await coordinator.importCandidate(
                    assetID: assetID,
                    sourceData: data,
                    createdAt: Date()
                )
            } catch CheckRunnerCoordinatorError.storageUnavailable {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.captureContentFailure)
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure4)
            }
            isWorking = false
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        didOpenCameraSettings = true
        UIApplication.shared.open(settingsURL)
    }

    private func importFixture(for step: WorkflowDraftStep) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        let environmentKey = step == .wide
            ? "S3_2_WIDE_FIXTURE_BASE64"
            : "S3_2_CLOSE_FIXTURE_BASE64"
        guard let encoded = ProcessInfo.processInfo.environment[environmentKey],
              let sourceData = Data(base64Encoded: encoded) else {
            isWorking = false
            errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure5)
            return
        }

        Task { @MainActor in
            do {
                candidate = try await coordinator.importCandidate(
                    assetID: assetID,
                    sourceData: sourceData,
                    createdAt: Date()
                )
            } catch CheckRunnerCoordinatorError.storageUnavailable {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.captureContentFailure)
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure3)
            }
            isWorking = false
        }
    }

    private func retake(_ candidate: CaptureCandidate) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await coordinator.retake(candidate: candidate)
                self.candidate = nil
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure6)
            }
            isWorking = false
        }
    }

    private func usePhoto(_ candidate: CaptureCandidate) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await coordinator.accept(
                    candidate: candidate,
                    assetID: assetID
                )
                self.candidate = nil
                preparation = try coordinator.prepareCapture(assetID: assetID)
            } catch {
                errorMessage = BundledLocalizationCatalogV1.v30Text(.capturePhotoFailure7)
            }
            isWorking = false
        }
    }
}
