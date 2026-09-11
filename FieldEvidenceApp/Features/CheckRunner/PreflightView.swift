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
                            ProgressView(BundledLocalizationCatalogV1.v30Text(.preflightCheckingActiveCheck))
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
                ? BundledLocalizationCatalogV1.v30Text(.preflightCaptureNavigationTitle)
                : BundledLocalizationCatalogV1.v30Text(.preflightReadyForNightCheckNavigationTitle)
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
                WorklightStatusBadge(kind: .information, text: BundledLocalizationCatalogV1.v30Text(.preflightReadyForNightCheckBadge))

                Text(snapshot.signLabel)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if confirmedTimeZoneID == nil {
                    timeZoneConfirmation
                } else if let confirmedTimeZoneID {
                    detailRow(title: BundledLocalizationCatalogV1.v30Text(.preflightConfirmedTimeZoneLabel), value: confirmedTimeZoneID)
                }
            }

            WorklightCard {
                Text(BundledLocalizationCatalogV1.v30Text(.preflightBeforeYouBeginHeading))
                    .font(.headline)
                    .foregroundStyle(DesignTokens.Colors.primaryText)
                    .accessibilityAddTraits(.isHeader)

                ForEach(pack.acknowledgements) { acknowledgement in
                    Toggle(isOn: acknowledgementBinding(for: acknowledgement.key)) {
                        Text(acknowledgement.copy)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                    }
                    .frame(
                        minWidth: DesignTokens.Control.minimumHitSize,
                        maxWidth: .infinity,
                        minHeight: DesignTokens.Control.minimumHitSize,
                        alignment: .leading
                    )
                    .contentShape(.interaction, Rectangle())
                    .contentShape(.accessibility, Rectangle())
                    .accessibilityHint(
                        BundledLocalizationCatalogV1.formSemanticsText(.required)
                    )
                    .accessibilityIdentifier(
                        acknowledgement.key == "after_dark"
                            ? Self.afterDarkAccessibilityIdentifier
                            : Self.safePositionAccessibilityIdentifier
                    )
                }
            }

            if let errorMessage {
                WorklightCard {
                    WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.preflightCheckNotStartedBadge))

                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(BundledLocalizationCatalogV1.v30Text(.preflightBeginCheckAction)) {
                begin()
            }
            .buttonStyle(WorklightPrimaryButtonStyle())
            .disabled(!canBegin || isBeginning)
            .accessibilityHint(canBegin ? BundledLocalizationCatalogV1.v30Text(.preflightBeginCheckEnabledHint) : beginDisabledHint)
            .accessibilityIdentifier(Self.beginAccessibilityIdentifier)

            Button(BundledLocalizationCatalogV1.v30Text(.preflightCancelNoCheckStartedAction), action: cancel)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
        }
    }

    private var timeZoneConfirmation: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(BundledLocalizationCatalogV1.v30Text(.preflightSiteTimeZoneHeading))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityValue(
                    BundledLocalizationCatalogV1.formSemanticsText(.required)
                )

            TextField(BundledLocalizationCatalogV1.v30Text(.preflightTimeZonePlaceholder), text: $timeZoneID)
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
                .accessibilityLabel(BundledLocalizationCatalogV1.v30Text(.preflightTimeZoneAccessibilityLabel))
                .accessibilityHint(BundledLocalizationCatalogV1.v30Text(.preflightTimeZoneAccessibilityHint))
                .accessibilityIdentifier(Self.timeZoneAccessibilityIdentifier)
                .onChange(of: timeZoneID) { _, _ in
                    isTimeZoneConfirmed = false
                    errorMessage = nil
                }

            Toggle(isOn: $isTimeZoneConfirmed) {
                Text(BundledLocalizationCatalogV1.v30Text(.preflightConfirmTimeZoneToggle))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
                .frame(
                    minWidth: DesignTokens.Control.minimumHitSize,
                    maxWidth: .infinity,
                    minHeight: DesignTokens.Control.minimumHitSize,
                    alignment: .leading
                )
                .contentShape(.interaction, Rectangle())
                .contentShape(.accessibility, Rectangle())
                .disabled(!hasValidEnteredTimeZone)
                .accessibilityHint(
                    hasValidEnteredTimeZone
                        ? BundledLocalizationCatalogV1.v30Text(.preflightConfirmTimeZoneEnabledHint)
                        : BundledLocalizationCatalogV1.v30Text(.preflightConfirmTimeZoneDisabledHint)
                )
                .accessibilityIdentifier(Self.timeZoneConfirmationAccessibilityIdentifier)
        }
    }

    private var loadFailure: some View {
        WorklightCard {
            WorklightStatusBadge(kind: .blocked, text: BundledLocalizationCatalogV1.v30Text(.preflightActiveCheckUnavailableBadge))

            Text(BundledLocalizationCatalogV1.v30Text(.preflightActiveCheckUnavailableMessage))
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
            return BundledLocalizationCatalogV1.v30Text(.preflightConfirmValidTimeZoneBeforeBeginningHint)
        }
        return BundledLocalizationCatalogV1.v30Text(.preflightAcceptAcknowledgementsBeforeBeginningHint)
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
            errorMessage = BundledLocalizationCatalogV1.v30Text(.preflightCheckCouldNotBeStartedError)
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
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
