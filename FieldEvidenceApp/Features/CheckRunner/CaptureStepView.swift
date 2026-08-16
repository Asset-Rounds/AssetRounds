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
        .background(DesignTokens.SemanticColors.workBackground)
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
                    errorMessage = "The camera could not take a photo. Choose from Photos or try again."
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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                if let preparation {
                    captureContent(preparation)
                } else if let errorMessage {
                    failure(message: errorMessage)
                } else {
                    ProgressView("Opening active check")
                        .frame(
                            maxWidth: .infinity,
                            minHeight: DesignTokens.Target.minimumInteractiveHeight
                        )
                }
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .navigationTitle("Capture")
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
    }

    @ViewBuilder
    private func captureContent(_ preparation: CapturePreparation) -> some View {
        if let purpose = preparation.purpose {
            AssetRoundsEvidenceCard {
                Text(heading(for: preparation.step, purpose: purpose))
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingAccessibilityIdentifier)

                Text(purpose.instruction)
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let candidate {
                AssetRoundsPhotoCapture {
                    preview(candidate)

                    HStack(spacing: DesignTokens.Spacing.space16) {
                        Button("Retake") {
                            retake(candidate)
                        }
                        .buttonStyle(.bordered)
                        .tint(DesignTokens.SemanticColors.primaryAction)
                        .controlSize(.large)
                        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                        .disabled(isWorking)
                        .accessibilityIdentifier(Self.retakeAccessibilityIdentifier)

                        Button("Use Photo") {
                            usePhoto(candidate)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignTokens.SemanticColors.primaryAction)
                        .controlSize(.large)
                        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                        .disabled(isWorking)
                        .accessibilityIdentifier(Self.usePhotoAccessibilityIdentifier)
                    }
                }
            } else {
                AssetRoundsPhotoCapture {
                    captureActions(for: preparation.step)
                }
            }

            if let errorMessage {
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(
                        kind: .error,
                        text: Text("Photo not accepted")
                    )
                    .accessibilityLabel("Blocked: Photo not accepted")
                    .accessibilityValue(Text(verbatim: String()))
                    Text(errorMessage)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func captureActions(for step: WorkflowDraftStep) -> some View {
        Button("Take photo") {
            takePhoto(for: step)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        .disabled(isWorking)
        .accessibilityIdentifier(Self.takePhotoAccessibilityIdentifier)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Text("Choose from Photos")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        .disabled(isWorking)
        .accessibilityIdentifier(Self.choosePhotosAccessibilityIdentifier)

        if cameraStatus == .denied || cameraStatus == .restricted {
            AssetRoundsEvidenceCard {
                AssetRoundsStateLabel(
                    kind: .error,
                    text: Text("Camera access unavailable")
                )
                .accessibilityLabel("Blocked: Camera access unavailable")
                .accessibilityValue(Text(verbatim: String()))
                Text("Choose a photo, open Settings, or leave this check incomplete and return later.")
                    .font(DesignTokens.Typography.primaryBody)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Open Settings") {
                openSettings()
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.SemanticColors.primaryAction)
            .controlSize(.large)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
            .accessibilityIdentifier(Self.openSettingsAccessibilityIdentifier)
        }

        Button("Cannot complete") {
            showsCouldNotVerify = true
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        .disabled(isWorking)
        .accessibilityHint("Opens the reason flow to save this check as incomplete")
        .accessibilityIdentifier(Self.cannotCompleteAccessibilityIdentifier)

        if usesImportedCaptureFixturesForUITest {
            Button("Import test photo") {
                importFixture(for: step)
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.SemanticColors.primaryAction)
            .controlSize(.large)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
            .disabled(isWorking)
            .accessibilityIdentifier(Self.fixtureImportAccessibilityIdentifier)
        }
    }

    private func preview(_ candidate: CaptureCandidate) -> some View {
        AssetRoundsEvidenceCard {
            if let image = UIImage(data: candidate.previewJPEG) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityLabel("Imported photo preview")
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            } else {
                Text("The imported photo preview is unavailable.")
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            }
        }
    }

    private func failure(message: String) -> some View {
        AssetRoundsEvidenceCard {
            AssetRoundsStateLabel(
                kind: .error,
                text: Text("Active check unavailable")
            )
            .accessibilityLabel("Blocked: Active check unavailable")
            .accessibilityValue(Text(verbatim: String()))
            Text(message)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry") {
                errorMessage = nil
                loadPreparation()
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.SemanticColors.primaryAction)
            .controlSize(.large)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
        }
    }

    private func heading(
        for step: WorkflowDraftStep,
        purpose: SignPack.EvidencePurpose
    ) -> String {
        step == .wide
            ? "1 of 2 · \(purpose.display)"
            : "2 of 2 · \(purpose.display)"
    }

    private func loadPreparation() {
        do {
            preparation = try coordinator.prepareCapture(assetID: assetID)
            errorMessage = nil
        } catch {
            preparation = nil
            errorMessage = "The active check could not be opened."
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
                errorMessage = "The camera is unavailable. Choose from Photos or return later."
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
                    errorMessage = "The selected photo could not be read. Choose another photo."
                    return
                }
                candidate = try await coordinator.importCandidate(
                    assetID: assetID,
                    sourceData: data,
                    createdAt: Date()
                )
            } catch CheckRunnerCoordinatorError.storageUnavailable {
                errorMessage = "Free space is too low. Free space, then try again."
            } catch {
                errorMessage = "The photo could not be imported. Try another photo."
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
                errorMessage = "Free space is too low. Free space, then try again."
            } catch {
                errorMessage = "The photo could not be prepared. Choose another photo."
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
            errorMessage = "The test photo could not be imported."
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
                errorMessage = "Free space is too low. Free space, then try again."
            } catch {
                errorMessage = "The photo could not be imported. Try another photo."
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
                errorMessage = "The photo could not be cleared. Try again."
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
                errorMessage = "The photo could not be saved. Try again."
            }
            isWorking = false
        }
    }
}
