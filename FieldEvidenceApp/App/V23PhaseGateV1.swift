import SwiftUI

/// Merge phases for the V23 expansion inside the accepted S10 app. Main
/// advances one complete, verified phase at a time; a surface whose phase is
/// later than the shipping phase has no production entry point.
enum V23PhaseV1: Int, CaseIterable, Comparable, Sendable {
    case phase1 = 1
    case phase2
    case phase3

    static func < (lhs: V23PhaseV1, rhs: V23PhaseV1) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The closed set of V23 surfaces that exist in the app but are not yet part
/// of a shipping phase. Gating hides an entry point only: schemas, registries,
/// backup/restore and service wiring are unchanged, and nothing is persisted.
enum V23GatedFeatureV1: String, CaseIterable, Sendable {
    /// Today: the My Day available-work list, the Plan entry and its editor.
    case myDay
    /// Work: the current-work list, including Round and saved-draft rows.
    case workSources
    /// Settings: the Reminders section.
    case reminders
    /// App Intents for private system discovery.
    case systemDiscovery
    /// Opening `.arenvelope` files in the app. This one is a static Info.plist
    /// declaration, so the built plist omits the document type while gated.
    ///
    /// Intentionally failing provisional card scripts while Phase 1 ships
    /// (they assert the later-phase declarations; not run by any workflow):
    /// - `Scripts/v23/p03_c54_contracts.py:712-726` requires the `.arenvelope`
    ///   `CFBundleDocumentTypes` entry removed from Info.plist.
    /// - `Scripts/v23/p04_c25_contracts.py:33` requires the
    ///   `NSMicrophoneUsageDescription` key removed from InfoPlist.xcstrings
    ///   when the catalog was restored to the S10 camera-only wording.
    case envelopeDocumentOpen

    /// The phase that makes this surface reachable. MERGE_READINESS has not
    /// yet numbered the later phases, so every gated surface is assigned the
    /// first later phase until the phase ledger records its actual phase.
    var phase: V23PhaseV1 {
        switch self {
        case .myDay, .workSources, .reminders, .systemDiscovery, .envelopeDocumentOpen:
            return .phase2
        }
    }
}

/// Which gated V23 surfaces are reachable. Views read it from the SwiftUI
/// environment (`\.v23PhaseGate`, default `.shipping`); non-view code reads
/// `V23PhaseGateV1.shipping` directly.
struct V23PhaseGateV1: Equatable, Sendable {
    /// The production gate: only Phase 1 journeys are reachable.
    static let shipping = V23PhaseGateV1(through: .phase1)

    let enabled: Set<V23GatedFeatureV1>

    init(through phase: V23PhaseV1) {
        let features: [V23GatedFeatureV1] = V23GatedFeatureV1.allCases.filter { feature in
            feature.phase <= phase
        }
        enabled = Set(features)
    }

    #if DEBUG
    /// Test hosts only: every gated surface is reachable so existing tests of
    /// later-phase surfaces keep exercising them. Absent from Release builds.
    static let allFeatures = V23PhaseGateV1(enabled: Set(V23GatedFeatureV1.allCases))

    private init(enabled: Set<V23GatedFeatureV1>) {
        self.enabled = enabled
    }
    #endif

    func allows(_ feature: V23GatedFeatureV1) -> Bool {
        enabled.contains(feature)
    }
}

private struct V23PhaseGateKeyV1: EnvironmentKey {
    static let defaultValue: V23PhaseGateV1 = .shipping
}

extension EnvironmentValues {
    var v23PhaseGate: V23PhaseGateV1 {
        get { self[V23PhaseGateKeyV1.self] }
        set { self[V23PhaseGateKeyV1.self] = newValue }
    }
}
