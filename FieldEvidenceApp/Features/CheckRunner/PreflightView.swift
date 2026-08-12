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
        cancel: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.pack = pack
        self.coordinator = coordinator
        self.generationRootURL = generationRootURL
        self.usesImportedCaptureFixturesForUITest =
            usesImportedCaptureFixturesForUITest
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
                        usesImportedCaptureFixturesForUITest
                )
            } else {
                ScrollView {
                    Group {
                        if isCheckingForDraft {
                            ProgressView("Checking for an active check")
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else if didFailDraftCheck {
                            loadFailure
                        } else {
                            preflight
                        }
                    }
                    .padding(DesignTokens.Spacing.medium)
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
        .background(DesignTokens.Colors.canvas)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
            WorklightCard {
                WorklightStatusBadge(kind: .information, text: "Ready for night check")

                Text(snapshot.signLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if confirmedTimeZoneID == nil {
                    timeZoneConfirmation
                } else if let confirmedTimeZoneID {
                    detailRow(title: "Confirmed time zone", value: confirmedTimeZoneID)
                }
            }

            WorklightCard {
                Text("Before you begin")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                ForEach(pack.acknowledgements) { acknowledgement in
                    Toggle(
                        acknowledgement.copy,
                        isOn: acknowledgementBinding(for: acknowledgement.key)
                    )
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityIdentifier(
                        acknowledgement.key == "after_dark"
                            ? Self.afterDarkAccessibilityIdentifier
                            : Self.safePositionAccessibilityIdentifier
                    )
                }
            }

            if let errorMessage {
                WorklightCard {
                    WorklightStatusBadge(kind: .blocked, text: "Check not started")

                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Begin check") {
                begin()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!canBegin || isBeginning)
            .accessibilityHint(canBegin ? "Creates or resumes this sign's check" : beginDisabledHint)
            .accessibilityIdentifier(Self.beginAccessibilityIdentifier)

            Button("Cancel — no check started", action: cancel)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
        }
    }

    private var timeZoneConfirmation: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Site time zone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)

            TextField("IANA time zone, for example America/New_York", text: $timeZoneID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.none)
                .submitLabel(.done)
                .focused($focusedField, equals: .timeZone)
                .padding(.horizontal, DesignTokens.Spacing.small)
                .frame(minHeight: DesignTokens.Control.minimumHitSize)
                .background(DesignTokens.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                        .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
                }
                .accessibilityLabel("IANA time zone")
                .accessibilityHint("Enter a time zone such as America slash New York")
                .accessibilityIdentifier(Self.timeZoneAccessibilityIdentifier)
                .onChange(of: timeZoneID) { _, _ in
                    isTimeZoneConfirmed = false
                    errorMessage = nil
                }

            Toggle("I confirm this is the site's time zone.", isOn: $isTimeZoneConfirmed)
                .disabled(!hasValidEnteredTimeZone)
                .frame(minHeight: DesignTokens.Control.minimumHitSize)
                .accessibilityHint(
                    hasValidEnteredTimeZone
                        ? "Confirms the entered time zone for this site"
                        : "Enter a valid IANA time zone first"
                )
                .accessibilityIdentifier(Self.timeZoneConfirmationAccessibilityIdentifier)
        }
    }

    private var loadFailure: some View {
        WorklightCard {
            WorklightStatusBadge(kind: .blocked, text: "Active check unavailable")

            Text("The active check could not be opened.")
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
