import Foundation
import PhotosUI
import SwiftUI
import UIKit

/// Explicit durable actions for a live Round item. Selection stages through
/// the C36 pipeline; Use Photo commits; the host owns Outcome and navigation.
@MainActor
struct CheckRunnerDurableCaptureActionsV1 {
    let preparation: CapturePreparation?
    let pending: ProductionCheckRunnerPendingPhotoV1?
    let preview: Data?
    let stagePhoto: @MainActor (Data, OriginalContentOriginV1) async throws -> Void
    let usePhoto: @MainActor () async throws -> Void
    let cannotComplete: @MainActor () throws -> Void
}

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
    private enum Backend {
        case standalone(CheckRunnerCoordinator)
        case durable(CheckRunnerDurableCaptureActionsV1)
    }
    private let backend: Backend
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

    init(assetID: UUID, coordinator: CheckRunnerCoordinator,
         usesImportedCaptureFixturesForUITest: Bool, cameraAdapter: CameraAdapter,
         cannotComplete: @escaping () -> Void) {
        self.assetID = assetID
        self.backend = .standalone(coordinator)
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        self.cannotComplete = cannotComplete
    }

    /// The live parent owns selection, commit and the Outcome screen; this
    /// backend never calls the standalone coordinator.
    init(assetID: UUID, durable: CheckRunnerDurableCaptureActionsV1,
         usesImportedCaptureFixturesForUITest: Bool = false, cameraAdapter: CameraAdapter = .live) {
        self.assetID = assetID
        self.backend = .durable(durable)
        self.usesImportedCaptureFixturesForUITest = usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        self.cannotComplete = {}
    }

    private var currentPreparation: CapturePreparation? {
        if case let .durable(actions) = backend { return actions.preparation }
        return preparation
    }

    var body: some View {
        Group {
            if case let .standalone(coordinator) = backend, showsCouldNotVerify {
                OutcomeReviewView(
                    assetID: assetID,
                    coordinator: coordinator,
                    startsWithCouldNotVerify: true
                )
            } else if case let .standalone(coordinator) = backend, let preparation, preparation.step == .outcome {
                OutcomeReviewView(
                    assetID: assetID,
                    coordinator: coordinator
                )
            } else {
                captureScroll
            }
        }
        .modifier(
            CaptureTabBarVisibility(
                hidesOnLegacyOS: usesImportedCaptureFixturesForUITest
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .task {
            guard case .standalone = backend, preparation == nil, errorMessage == nil else { return }
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
                if let preparation = currentPreparation {
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

            if case let .durable(actions) = backend, let pending = actions.pending {
                AssetRoundsPhotoCapture {
                    durablePreview(actions.preview, pending: pending)

                    if pending.needsSourceAgain {
                        Text("This photo could not be finished on this iPhone.")
                            .font(DesignTokens.Typography.primaryBody)
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    } else {
                        AssetRoundsPrimaryAction(action: {
                            useDurablePhoto(actions)
                        }) {
                            Text("Use Photo")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier(Self.usePhotoAccessibilityIdentifier)
                    }
                }
            } else if let candidate {
                AssetRoundsPhotoCapture {
                    preview(candidate)

                    let actionLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: DesignTokens.Spacing.space16))
                        : AnyLayout(HStackLayout(spacing: DesignTokens.Spacing.space16))

                    actionLayout {
                        AssetRoundsSecondaryAction(action: {
                            retake(candidate)
                        }) {
                            Text("Retake")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isWorking)
                        .accessibilityIdentifier(Self.retakeAccessibilityIdentifier)

                        AssetRoundsPrimaryAction(action: {
                            usePhoto(candidate)
                        }) {
                            Text("Use Photo")
                                .frame(maxWidth: .infinity)
                        }
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
        AssetRoundsPrimaryAction("Take photo") {
            takePhoto(for: step)
        }
        .disabled(isWorking)
        .accessibilityIdentifier(Self.takePhotoAccessibilityIdentifier)

        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            Text("Choose from Photos")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(WorklightSecondaryButtonStyle())
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

            AssetRoundsSecondaryAction("Open Settings") {
                openSettings()
            }
            .accessibilityIdentifier(Self.openSettingsAccessibilityIdentifier)
        }

        AssetRoundsSecondaryAction("Cannot complete") {
            if case let .durable(actions) = backend {
                do { try actions.cannotComplete() }
                catch { errorMessage = "Your changes could not be saved. Try again." }
            } else {
                showsCouldNotVerify = true
            }
        }
        .disabled(isWorking)
        .accessibilityHint("Opens the reason flow to save this check as incomplete")
        .accessibilityIdentifier(Self.cannotCompleteAccessibilityIdentifier)

        if usesImportedCaptureFixturesForUITest {
            AssetRoundsSecondaryAction("Import test photo") {
                importFixture(for: step)
            }
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

            AssetRoundsSecondaryAction("Retry") {
                errorMessage = nil
                loadPreparation()
            }
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

    /// A preview of bytes selected in this scene, or a plain saved-state label
    /// after reopening; staged bytes are never read back for presentation.
    private func durablePreview(_ data: Data?, pending: ProductionCheckRunnerPendingPhotoV1) -> some View {
        AssetRoundsEvidenceCard {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                    .accessibilityLabel("Selected photo preview")
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            } else {
                Text("A photo is selected for this step and saved on this iPhone.")
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            }
        }
    }

    private func useDurablePhoto(_ actions: CheckRunnerDurableCaptureActionsV1) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do { try await actions.usePhoto() }
            catch { errorMessage = "The photo could not be saved. Try again." }
        }
    }

    /// One entry for picker, camera and UI-test bytes. Durable selection stages
    /// through the live parent; standalone creates the incumbent candidate.
    private func acceptSelected(_ data: Data, origin: OriginalContentOriginV1) async throws {
        switch backend {
        case let .standalone(coordinator):
            candidate = try await coordinator.importCandidate(assetID: assetID, sourceData: data, createdAt: Date())
        case let .durable(actions):
            try await actions.stagePhoto(data, origin)
        }
    }

    private func loadPreparation() {
        guard case let .standalone(coordinator) = backend else { return }
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
                try await acceptSelected(data, origin: .localImport)
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
                try await acceptSelected(data, origin: .humanCapture)
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
                try await acceptSelected(sourceData, origin: .localImport)
            } catch CheckRunnerCoordinatorError.storageUnavailable {
                errorMessage = "Free space is too low. Free space, then try again."
            } catch {
                errorMessage = "The photo could not be imported. Try another photo."
            }
            isWorking = false
        }
    }

    private func retake(_ candidate: CaptureCandidate) {
        guard !isWorking, case let .standalone(coordinator) = backend else { return }
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
        guard !isWorking, case let .standalone(coordinator) = backend else { return }
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

private struct CaptureTabBarVisibility: ViewModifier {
    let hidesOnLegacyOS: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else if hidesOnLegacyOS {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}
