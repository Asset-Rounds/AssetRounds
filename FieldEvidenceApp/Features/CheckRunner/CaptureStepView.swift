import Foundation
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
    static let outcomeUnavailableAccessibilityIdentifier =
        "s3.runner.outcome-unavailable"

    let assetID: UUID
    let coordinator: CheckRunnerCoordinator
    let usesImportedCaptureFixturesForUITest: Bool

    @State private var preparation: CapturePreparation?
    @State private var candidate: CaptureCandidate?
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                if let preparation {
                    if preparation.step == .outcome {
                        outcomeUnavailable
                    } else {
                        captureContent(preparation)
                    }
                } else if let errorMessage {
                    failure(message: errorMessage)
                } else {
                    ProgressView("Opening active check")
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .task {
            guard preparation == nil, errorMessage == nil else { return }
            loadPreparation()
        }
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

                HStack(spacing: DesignTokens.Spacing.medium) {
                    Button("Retake") {
                        retake(candidate)
                    }
                    .buttonStyle(WorklightSecondaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier(Self.retakeAccessibilityIdentifier)

                    Button("Use Photo") {
                        usePhoto(candidate)
                    }
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(isWorking)
                    .accessibilityIdentifier(Self.usePhotoAccessibilityIdentifier)
                }
            } else if usesImportedCaptureFixturesForUITest {
                Button("Import test photo") {
                    importFixture(for: preparation.step)
                }
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier(Self.fixtureImportAccessibilityIdentifier)
            } else {
                Text("Capture is unavailable until S3.2.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(
                        Self.legacyCaptureUnavailableAccessibilityIdentifier
                    )

                WorklightCard {
                    WorklightStatusBadge(
                        kind: .information,
                        text: "Imported fixture capture is available only in the S3.2 test route."
                    )
                }
            }

            if let errorMessage {
                WorklightCard {
                    WorklightStatusBadge(kind: .blocked, text: "Photo not accepted")
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                    .accessibilityLabel("Imported photo preview")
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            } else {
                Text("The imported photo preview is unavailable.")
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityIdentifier(Self.previewAccessibilityIdentifier)
            }
        }
    }

    private var outcomeUnavailable: some View {
        WorklightCard {
            Text("Outcome is unavailable until S3.3.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.outcomeUnavailableAccessibilityIdentifier)
        }
    }

    private func failure(message: String) -> some View {
        WorklightCard {
            WorklightStatusBadge(kind: .blocked, text: "Active check unavailable")
            Text(message)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button("Retry") {
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
