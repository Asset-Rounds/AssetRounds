import SwiftUI

enum WorklightColorAsset: String, CaseIterable {
    case canvas = "WorklightCanvas"
    case surface = "WorklightSurface"
    case raisedSurface = "WorklightRaisedSurface"
    case primaryText = "WorklightPrimaryText"
    case secondaryText = "WorklightSecondaryText"
    case tertiaryText = "WorklightTertiaryText"
    case interactionAccent = "WorklightInteractionAccent"
    case onAccent = "WorklightOnAccent"
    case accentContainer = "WorklightAccentContainer"
    case onAccentContainer = "WorklightOnAccentContainer"
    case essentialControlStroke = "WorklightEssentialControlStroke"
    case completeText = "WorklightCompleteText"
    case completeContainer = "WorklightCompleteContainer"
    case attentionText = "WorklightAttentionText"
    case attentionContainer = "WorklightAttentionContainer"
    case blockedText = "WorklightBlockedText"
    case blockedContainer = "WorklightBlockedContainer"
    case informationText = "WorklightInformationText"
    case informationContainer = "WorklightInformationContainer"

    var color: Color {
        Color(rawValue)
    }
}

enum DesignTokens {
    enum Colors {
        static let assetNames = WorklightColorAsset.allCases.map(\.rawValue)

        static let canvas = WorklightColorAsset.canvas.color
        static let surface = WorklightColorAsset.surface.color
        static let raisedSurface = WorklightColorAsset.raisedSurface.color
        static let primaryText = WorklightColorAsset.primaryText.color
        static let secondaryText = WorklightColorAsset.secondaryText.color
        static let tertiaryText = WorklightColorAsset.tertiaryText.color
        static let interactionAccent = WorklightColorAsset.interactionAccent.color
        static let onAccent = WorklightColorAsset.onAccent.color
        static let accentContainer = WorklightColorAsset.accentContainer.color
        static let onAccentContainer = WorklightColorAsset.onAccentContainer.color
        static let essentialControlStroke = WorklightColorAsset.essentialControlStroke.color
        static let completeText = WorklightColorAsset.completeText.color
        static let completeContainer = WorklightColorAsset.completeContainer.color
        static let attentionText = WorklightColorAsset.attentionText.color
        static let attentionContainer = WorklightColorAsset.attentionContainer.color
        static let blockedText = WorklightColorAsset.blockedText.color
        static let blockedContainer = WorklightColorAsset.blockedContainer.color
        static let informationText = WorklightColorAsset.informationText.color
        static let informationContainer = WorklightColorAsset.informationContainer.color
    }

    enum Spacing {
        static let unit: CGFloat = 8
        static let small: CGFloat = unit
        static let medium: CGFloat = unit * 2
        static let large: CGFloat = unit * 3
        static let extraLarge: CGFloat = unit * 4
        static let cardPadding: CGFloat = medium
    }

    enum Radius {
        static let standard: CGFloat = 12
    }

    enum Control {
        static let minimumHitSize: CGFloat = 44
    }
}
