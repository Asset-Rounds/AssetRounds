import SwiftUI

/// A presentation-only rendering of a single derived local readiness manifest.
/// The owning coordinator supplies the manifest and any action closures; this
/// view deliberately creates no store, writer, router, or replacement manifest.
struct OfflineReadinessPreflightView: View {
    static let screenAccessibilityIdentifier = OfflineReadinessPreflightAccessibilityIDV1.screen.rawValue

    let manifest: OfflineReadinessManifestV1?
    let isLoading: Bool
    let errorMessage: String?
    let onRebuild: (() -> Void)?
    let onCancel: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var statusSymbolSize = 26

    init(
        manifest: OfflineReadinessManifestV1?,
        isLoading: Bool = false,
        errorMessage: String? = nil,
        onRebuild: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) {
        self.manifest = manifest
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRebuild = onRebuild
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(localized(.heading))
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier(Self.screenAccessibilityIdentifier)

                if isLoading {
                    loadingState
                } else if let manifest {
                    manifestState(manifest)
                } else {
                    unavailableState
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(localized(.heading))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(localized(.loading))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.status.rawValue)
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized(.unavailable), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.primary)
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.status.rawValue)
            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            actionButtons
        }
    }

    private func manifestState(_ manifest: OfflineReadinessManifestV1) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            statusCard(for: manifest)
            requirements(for: manifest)
            Text(localized(.localOnlyDisclosure))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.localOnlyDisclosure.rawValue)
            actionButtons
        }
    }

    private func statusCard(for manifest: OfflineReadinessManifestV1) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(statusText(manifest.status))
                    .font(.headline)
            } icon: {
                Image(systemName: statusSymbol(manifest.status))
                    .font(.system(size: statusSymbolSize, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.status.rawValue)

            Text(manifest.mayStartFieldWork ? localized(.safeToStart) : localized(.notSafeToStartOrClose))
                .font(.body.weight(.medium))
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.safety.rawValue)
            if manifest.maySafelyCloseFieldWork {
                Text(localized(.safeToClose))
                    .font(.body.weight(.medium))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func requirements(for manifest: OfflineReadinessManifestV1) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized(.requirementsHeading))
                .font(.headline)
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.requirements.rawValue)
            ForEach(manifest.requirements, id: \.requirementID) { requirement in
                requirementRow(requirement)
            }
        }
    }

    private func requirementRow(_ requirement: OfflineReadinessRequirementV1) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: requirement.state == .satisfied ? "checkmark.circle" : "exclamationmark.circle")
                    .accessibilityHidden(true)
                Text(requirement.requirementID)
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                Text(localized(requirement.mandatory ? .required : .optional))
                    .font(.caption.weight(.semibold))
            }
            .accessibilityElement(children: .combine)

            if let reason = requirement.reason,
               let remediation = requirement.remediation,
               let fallback = requirement.manualFallback {
                VStack(alignment: .leading, spacing: 5) {
                    labeledText(.reasonsHeading, reasonText(reason))
                        .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.reasons.rawValue + "." + requirement.requirementID)
                    labeledText(.remediation, remediationText(remediation))
                        .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.remediation.rawValue + "." + requirement.requirementID)
                    labeledText(.manualFallback, fallbackText(fallback))
                        .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.manualFallback.rawValue + "." + requirement.requirementID)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func labeledText(
        _ label: OfflineReadinessPreflightLocalizationKeyV1,
        _ value: String
    ) -> some View {
        Text("\(localized(label)): \(value)")
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let onRebuild {
            Button(localized(.rebuild), action: onRebuild)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.rebuild.rawValue)
        } else {
            Text(localized(.rebuildUnavailable))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let onCancel {
            Button(localized(.cancel), action: onCancel)
                .buttonStyle(.bordered)
                .accessibilityIdentifier(OfflineReadinessPreflightAccessibilityIDV1.cancel.rawValue)
        }
    }

    private func statusText(_ status: OfflineReadinessStatusV1) -> String {
        switch status {
        case .ready: return localized(.ready)
        case .blocked: return localized(.blocked)
        case .warning: return localized(.warning)
        case .stale: return localized(.stale)
        }
    }

    private func statusSymbol(_ status: OfflineReadinessStatusV1) -> String {
        switch status {
        case .ready: return "checkmark.seal.fill"
        case .blocked: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .stale: return "arrow.triangle.2.circlepath"
        }
    }

    private func reasonText(_ reason: OfflineReadinessReasonV1) -> String {
        switch reason {
        case .packageMismatch: return localized(.reasonPackageMismatch)
        case .selectedAssetMismatch: return localized(.reasonSelectedAssetMismatch)
        case .guidanceReferenceMismatch: return localized(.reasonGuidanceReferenceMismatch)
        case .fieldReferenceUnavailable: return localized(.reasonFieldReferenceUnavailable)
        case .missingMandatoryContent: return localized(.reasonMissingMandatoryContent)
        case .missingOptionalContent: return localized(.reasonMissingOptionalContent)
        case .corruptMandatoryContent: return localized(.reasonCorruptMandatoryContent)
        case .corruptOptionalContent: return localized(.reasonCorruptOptionalContent)
        case .partialMandatoryContent: return localized(.reasonPartialMandatoryContent)
        case .partialOptionalContent: return localized(.reasonPartialOptionalContent)
        case .wrongWorkspaceContent: return localized(.reasonWrongWorkspaceContent)
        case .protectedDataUnavailable: return localized(.reasonProtectedDataUnavailable)
        case .storageUncheckable: return localized(.reasonStorageUncheckable)
        case .insufficientStorage: return localized(.reasonInsufficientStorage)
        case .storageArithmeticOverflow: return localized(.reasonStorageArithmeticOverflow)
        case .clockUncheckable: return localized(.reasonClockUncheckable)
        case .clockOrTimeZoneChanged: return localized(.reasonClockOrTimeZoneChanged)
        case .sourceBindingDrift: return localized(.reasonSourceBindingDrift)
        }
    }

    private func remediationText(_ remediation: OfflineReadinessRemediationV1) -> String {
        switch remediation {
        case .rebuildPreflight: return localized(.remediationRebuild)
        case .restoreExactPackage: return localized(.remediationRestorePackage)
        case .reselectAssets: return localized(.remediationReselectAssets)
        case .restoreGuidance: return localized(.remediationRestoreGuidance)
        case .restoreFieldReference: return localized(.remediationRestoreFieldReference)
        case .restoreExactContent: return localized(.remediationRestoreContent)
        case .unlockProtectedData: return localized(.remediationUnlock)
        case .freeStorage: return localized(.remediationFreeStorage)
        case .checkStorageAgain: return localized(.remediationCheckStorage)
        case .checkClockAndTimeZone: return localized(.remediationCheckClock)
        }
    }

    private func fallbackText(_ fallback: OfflineReadinessManualFallbackV1) -> String {
        switch fallback {
        case .doNotStart: return localized(.fallbackDoNotStart)
        case .deferFieldWork: return localized(.fallbackDeferFieldWork)
        case .useApprovedManualProcedure: return localized(.fallbackApprovedManualProcedure)
        case .contactSupervisor: return localized(.fallbackContactSupervisor)
        }
    }

    private func localized(_ key: OfflineReadinessPreflightLocalizationKeyV1) -> String {
        BundledLocalizationCatalogV1.offlineReadinessPreflightLocalized(key)
    }
}
