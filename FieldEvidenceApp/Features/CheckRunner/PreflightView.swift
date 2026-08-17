import Foundation
import SwiftUI

struct PreflightView: View {
    static let screenAccessibilityIdentifier = "s3.preflight.screen"
    static let timeZoneAccessibilityIdentifier = "s3.preflight.time-zone"
    static let timeZoneConfirmationAccessibilityIdentifier = "s3.preflight.time-zone-confirmed"
    static let afterDarkAccessibilityIdentifier = "s3.preflight.after-dark"
    static let safePositionAccessibilityIdentifier = "s3.preflight.safe-position"
    static let beginAccessibilityIdentifier = "s3.preflight.begin"
    static let cancelAccessibilityIdentifier = "s3.preflight.cancel"

    let snapshot: FirstSignSnapshot
    let pack: SignPack
    let coordinator: CheckRunnerCoordinator
    let generationRootURL: URL
    let usesImportedCaptureFixturesForUITest: Bool
    let cameraAdapter: CameraAdapter
    let cannotComplete: () -> Void
    let cancel: () -> Void

    @State private var timeZoneID: String
    @State private var isTimeZoneConfirmed: Bool
    @State private var confirmedTimeZoneID: String?
    @State private var afterDarkAccepted = false
    @State private var safePositionAccepted = false
    @State private var didCheckForDraft = false
    @State private var isCheckingForDraft = true
    @State private var didFailDraftCheck = false
    @State private var hasDraft = false
    @State private var isBeginning = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case timeZone
    }

    init(
        snapshot: FirstSignSnapshot,
        pack: SignPack,
        coordinator: CheckRunnerCoordinator,
        generationRootURL: URL,
        usesImportedCaptureFixturesForUITest: Bool = false,
        cameraAdapter: CameraAdapter = .live,
        cannotComplete: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.pack = pack
        self.coordinator = coordinator
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest =
            usesImportedCaptureFixturesForUITest
        self.cameraAdapter = cameraAdapter
        self.cannotComplete = cannotComplete
        self.cancel = cancel
        _timeZoneID = State(initialValue: snapshot.timeZoneID ?? "")
        _isTimeZoneConfirmed = State(initialValue: snapshot.timeZoneID != nil)
        _confirmedTimeZoneID = State(initialValue: snapshot.timeZoneID)
    }

    var body: some View {
        Group {
            if !isCheckingForDraft, !didFailDraftCheck, hasDraft {
                CaptureStepView(
                    assetID: snapshot.assetID,
                    coordinator: coordinator,
                    usesImportedCaptureFixturesForUITest:
                        usesImportedCaptureFixturesForUITest,
                    cameraAdapter: cameraAdapter,
                    cannotComplete: cannotComplete
                )
            } else {
                ScrollView {
                    Group {
                        if isCheckingForDraft {
                            ProgressView("Checking for an active check")
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: DesignTokens.Target.minimumInteractiveHeight
                                )
                        } else if didFailDraftCheck {
                            loadFailure
                        } else {
                            preflight
                        }
                    }
                    .padding(DesignTokens.Spacing.space16)
                }
                .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
            }
        }
        .navigationTitle(
            !isCheckingForDraft && !didFailDraftCheck && hasDraft
                ? "Capture"
                : "Ready for night check"
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
        .task {
            guard !didCheckForDraft else { return }
            didCheckForDraft = true
            coordinator.configureCapture(generationRootURL: generationRootURL)

            do {
                let preparation = try coordinator.prepare(assetID: snapshot.assetID)
                confirmedTimeZoneID = preparation.confirmedTimeZoneID
                hasDraft = preparation.existingDraftID != nil
            } catch {
                didFailDraftCheck = true
            }
            isCheckingForDraft = false

            if confirmedTimeZoneID == nil, !hasDraft {
                await Task.yield()
                focusedField = .timeZone
            }
        }
    }

    private var preflight: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
            AssetRoundsEvidenceCard {
                Label("Ready for night check", systemImage: "info.circle.fill")
                    .font(DesignTokens.Typography.secondaryBody.weight(.semibold))
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Information: Ready for night check")

                Text(snapshot.signLabel)
                    .font(DesignTokens.Typography.screenTitle)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if confirmedTimeZoneID == nil {
                    timeZoneConfirmation
                } else if let confirmedTimeZoneID {
                    detailRow(title: "Confirmed time zone", value: confirmedTimeZoneID)
                }
            }

            AssetRoundsEvidenceCard {
                Text("Before you begin")
                    .font(DesignTokens.Typography.sectionHeading)
                    .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                ForEach(pack.acknowledgements) { acknowledgement in
                    Toggle(
                        acknowledgement.copy,
                        isOn: acknowledgementBinding(for: acknowledgement.key)
                    )
                    .frame(
                        minWidth: DesignTokens.Target.minimumInteractiveWidth,
                        maxWidth: .infinity,
                        minHeight: DesignTokens.Target.minimumInteractiveHeight,
                        alignment: .leading
                    )
                    .contentShape(.interaction, Rectangle())
                    .contentShape(.accessibility, Rectangle())
                    .accessibilityIdentifier(
                        acknowledgement.key == "after_dark"
                            ? Self.afterDarkAccessibilityIdentifier
                            : Self.safePositionAccessibilityIdentifier
                    )
                }
            }

            if let errorMessage {
                AssetRoundsEvidenceCard {
                    AssetRoundsStateLabel(
                        kind: .error,
                        text: Text("Check not started")
                    )
                    .accessibilityLabel("Blocked: Check not started")
                    .accessibilityValue(Text(verbatim: String()))

                    Text(errorMessage)
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Begin check") {
                begin()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.SemanticColors.primaryAction)
            .controlSize(.large)
            .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
            .disabled(!canBegin || isBeginning)
            .accessibilityHint(canBegin ? "Creates or resumes this sign's check" : beginDisabledHint)
            .accessibilityIdentifier(Self.beginAccessibilityIdentifier)
            .accessibilityHidden(focusedField == .timeZone)

            Button("Cancel — no check started", action: cancel)
                .buttonStyle(.bordered)
                .tint(DesignTokens.SemanticColors.primaryAction)
                .controlSize(.large)
                .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
                .accessibilityHidden(focusedField == .timeZone)
        }
    }

    private var timeZoneConfirmation: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text("Site time zone")
                .font(DesignTokens.Typography.fieldLabel)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)

            TextField("IANA time zone, for example America/New_York", text: $timeZoneID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.none)
                .submitLabel(.done)
                .focused($focusedField, equals: .timeZone)
                .onSubmit {
                    focusedField = nil
                }
                .padding(.horizontal, DesignTokens.Spacing.space8)
                .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                .background(DesignTokens.SemanticColors.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                        .stroke(DesignTokens.SemanticColors.separator, lineWidth: DesignTokens.Stroke.standard)
                }
                .accessibilityLabel("IANA time zone")
                .accessibilityHint("Enter a time zone such as America slash New York")
                .accessibilityIdentifier(Self.timeZoneAccessibilityIdentifier)
                .onChange(of: timeZoneID) { _, _ in
                    isTimeZoneConfirmed = false
                    errorMessage = nil
                }

            Toggle(isOn: $isTimeZoneConfirmed) {
                Text("I confirm this is the site's time zone.")
            }
                .frame(
                    minWidth: DesignTokens.Target.minimumInteractiveWidth,
                    maxWidth: .infinity,
                    minHeight: DesignTokens.Target.minimumInteractiveHeight,
                    alignment: .leading
                )
                .contentShape(.interaction, Rectangle())
                .contentShape(.accessibility, Rectangle())
                .disabled(!hasValidEnteredTimeZone)
                .accessibilityHint(
                    hasValidEnteredTimeZone
                        ? "Confirms the entered time zone for this site"
                        : "Enter a valid IANA time zone first"
                )
                .accessibilityIdentifier(Self.timeZoneConfirmationAccessibilityIdentifier)
                .onChange(of: isTimeZoneConfirmed) { _, isConfirmed in
                    if isConfirmed {
                        focusedField = nil
                    }
                }
        }
    }

    private var loadFailure: some View {
        AssetRoundsEvidenceCard {
            AssetRoundsStateLabel(
                kind: .error,
                text: Text("Active check unavailable")
            )
            .accessibilityLabel("Blocked: Active check unavailable")
            .accessibilityValue(Text(verbatim: String()))

            Text("The active check could not be opened.")
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var normalizedTimeZoneID: String {
        timeZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasValidEnteredTimeZone: Bool {
        TimeZone.knownTimeZoneIdentifiers.contains(normalizedTimeZoneID)
    }

    private var hasValidConfirmedTimeZone: Bool {
        confirmedTimeZoneID != nil || (hasValidEnteredTimeZone && isTimeZoneConfirmed)
    }

    private var canBegin: Bool {
        hasValidConfirmedTimeZone && afterDarkAccepted && safePositionAccepted
    }

    private var beginDisabledHint: String {
        if !hasValidConfirmedTimeZone {
            return "Confirm a valid site time zone before beginning"
        }
        return "Accept both acknowledgements before beginning"
    }

    private func begin() {
        guard canBegin, !isBeginning else { return }
        isBeginning = true
        errorMessage = nil
        focusedField = nil

        do {
            _ = try coordinator.beginCheck(
                assetID: snapshot.assetID,
                timeZoneID: confirmedTimeZoneID ?? normalizedTimeZoneID,
                isTimeZoneConfirmed: confirmedTimeZoneID != nil || isTimeZoneConfirmed,
                afterDarkAccepted: afterDarkAccepted,
                safePositionAccepted: safePositionAccepted,
                observedAt: Date()
            )
            hasDraft = true
        } catch {
            errorMessage = "The check could not be started. Try again."
            if let preparation = try? coordinator.prepare(assetID: snapshot.assetID) {
                confirmedTimeZoneID = preparation.confirmedTimeZoneID
                hasDraft = preparation.existingDraftID != nil
            }
        }

        isBeginning = false
    }

    private func acknowledgementBinding(for key: String) -> Binding<Bool> {
        switch key {
        case "after_dark":
            $afterDarkAccepted
        case "safe_authorized_position":
            $safePositionAccepted
        default:
            .constant(false)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
            Text(title)
                .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)

            Text(value)
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
