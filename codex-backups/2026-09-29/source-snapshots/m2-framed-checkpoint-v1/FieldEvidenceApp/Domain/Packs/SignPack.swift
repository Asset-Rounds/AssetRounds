import Foundation

struct SignPack: Codable, Equatable, Sendable {
    struct DisplayNoun: Codable, Equatable, Sendable {
        let singular: String
        let plural: String
    }

    struct Nouns: Codable, Equatable, Sendable {
        let asset: DisplayNoun
        let check: DisplayNoun
        let issue: DisplayNoun
    }

    struct EvidencePurpose: Codable, Equatable, Sendable, Identifiable {
        let key: String
        let display: String
        let instruction: String

        var id: String { key }
    }

    struct Acknowledgement: Codable, Equatable, Sendable, Identifiable {
        let key: String
        let copy: String
        let version: String

        var id: String { key }
    }

    struct RegistryEntry: Codable, Equatable, Sendable, Identifiable {
        let key: String
        let display: String

        var id: String { key }
    }

    struct VersionedRegistry: Codable, Equatable, Sendable {
        let version: String
        let entries: [RegistryEntry]
    }

    let schemaVersion: Int
    let packID: String
    let contentVersion: Int
    let nouns: Nouns
    let evidencePurposes: [EvidencePurpose]
    let acknowledgements: [Acknowledgement]
    let issueLabels: [RegistryEntry]
    let couldNotVerifyReasons: VersionedRegistry
    let stageDisplays: [RegistryEntry]
    let outcomeDisplays: [RegistryEntry]
    let disclaimer: String
}

extension SignPack {
    static let illuminatedSignPackageID = "field.evidence.illuminated_sign.v1"

    static let illuminatedSignV1 = SignPack(
        schemaVersion: 1,
        packID: illuminatedSignPackageID,
        contentVersion: 1,
        nouns: Nouns(
            asset: DisplayNoun(singular: "sign", plural: "signs"),
            check: DisplayNoun(singular: "check", plural: "checks"),
            issue: DisplayNoun(singular: "visible issue", plural: "visible issues")
        ),
        evidencePurposes: [
            EvidencePurpose(
                key: "wide_context",
                display: "Wide view",
                instruction: "Take one wide photo showing the full sign and its surroundings."
            ),
            EvidencePurpose(
                key: "close_detail",
                display: "Close view",
                instruction: "Take one close photo showing the sign face clearly."
            ),
            EvidencePurpose(
                key: "work_context",
                display: "Work photo",
                instruction: "Add one optional photo showing the work performed."
            )
        ],
        acknowledgements: [
            Acknowledgement(
                key: "after_dark",
                copy: "It is dark enough to observe the sign's visible illumination.",
                version: "preflight.ack.en-US.v1"
            ),
            Acknowledgement(
                key: "safe_authorized_position",
                copy: "I am in a safe, authorized position to take these photos.",
                version: "preflight.ack.en-US.v1"
            )
        ],
        issueLabels: [
            RegistryEntry(key: "dark_section", display: "Section appears dark"),
            RegistryEntry(key: "dim_or_uneven", display: "Illumination appears dim or uneven"),
            RegistryEntry(key: "flicker_or_intermittent", display: "Flicker or intermittent light"),
            RegistryEntry(key: "color_mismatch", display: "Visible color mismatch"),
            RegistryEntry(key: "physical_damage", display: "Visible physical damage"),
            RegistryEntry(key: "other_visible_condition", display: "Other visible condition")
        ],
        couldNotVerifyReasons: VersionedRegistry(
            version: "cnv.reason.en-US.v1",
            entries: [
                RegistryEntry(key: "conditions_changed", display: "Conditions changed"),
                RegistryEntry(key: "access_lost", display: "I lost safe access"),
                RegistryEntry(key: "unsafe_to_continue", display: "It became unsafe to continue"),
                RegistryEntry(key: "required_view_obstructed", display: "Required view is blocked"),
                RegistryEntry(key: "capture_unavailable", display: "Camera or photo capture is unavailable"),
                RegistryEntry(key: "other", display: "Another reason")
            ]
        ),
        stageDisplays: [
            RegistryEntry(key: "check", display: "Check"),
            RegistryEntry(key: "recheck", display: "Recheck")
        ],
        outcomeDisplays: [
            RegistryEntry(key: "no_visible_issue", display: "No visible issue"),
            RegistryEntry(key: "visible_issue", display: "Visible issue"),
            RegistryEntry(key: "could_not_verify", display: "Could not verify"),
            RegistryEntry(key: "resolved", display: "Resolved"),
            RegistryEntry(key: "issue_still_visible", display: "Issue still visible"),
            RegistryEntry(
                key: "original_resolved_different_issue",
                display: "Original resolved, different visible issue"
            )
        ],
        disclaimer: "This report records visible conditions from the listed photos and time. It is not an electrical, code, safety, or professional certification."
    )
}
