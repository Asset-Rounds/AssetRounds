import SwiftUI
import UIKit

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

enum AssetRoundsBrandColorAsset: String, CaseIterable {
    case accentTeal = "AssetRoundsAccentTeal"
    case deepTeal = "AssetRoundsDeepTeal"
    case checkpointGreen = "AssetRoundsCheckpointGreen"
    case brandCanvas = "AssetRoundsBrandCanvas"
    case ink = "AssetRoundsInk"
    case slate = "AssetRoundsSlate"

    var color: Color {
        Color(rawValue)
    }
}

enum AssetRoundsBrandImageAsset: String, CaseIterable {
    case originalSymbol = "AssetRoundsBrandSymbol"
    case templateSymbol = "AssetRoundsBrandSymbolTemplate"
}

enum DesignTokens {
    enum TokenID: String, CaseIterable {
        case workBackground = "color.workBackground"
        case groupedBackground = "color.groupedBackground"
        case elevatedSurface = "color.elevatedSurface"
        case primaryText = "color.primaryText"
        case secondaryText = "color.secondaryText"
        case tertiaryText = "color.tertiaryText"
        case separator = "color.separator"
        case primaryAction = "color.primaryAction"
        case brandHeading = "color.brandHeading"
        case completed = "color.completed"
        case warning = "color.warning"
        case error = "color.error"
        case unavailable = "color.unavailable"
        case selected = "color.selected"
        case disabled = "color.disabled"
        case screenTitle = "type.screenTitle"
        case sectionHeading = "type.sectionHeading"
        case primaryBody = "type.primaryBody"
        case secondaryBody = "type.secondaryBody"
        case fieldLabel = "type.fieldLabel"
        case supportingCaption = "type.supportingCaption"
        case numericOrTimestamp = "type.numericOrTimestamp"
        case space4 = "space.4"
        case space8 = "space.8"
        case space12 = "space.12"
        case space16 = "space.16"
        case space20 = "space.20"
        case space24 = "space.24"
        case space32 = "space.32"
        case radiusCompact = "radius.compact"
        case radiusStandard = "radius.standard"
        case radiusProminent = "radius.prominent"
        case strokeStandard = "stroke.standard"
        case strokeSelected = "stroke.selected"
        case minimumInteractive = "target.minimumInteractive"
        case darkMode = "environment.darkMode"
        case increaseContrast = "environment.increaseContrast"
        case differentiateWithoutColor = "environment.differentiateWithoutColor"
        case reduceMotion = "environment.reduceMotion"
        case reduceTransparency = "environment.reduceTransparency"
        case largerText = "environment.largerText"
        case voiceOver = "environment.voiceOver"
        case voiceControl = "environment.voiceControl"
        case currentPlatform = "environment.currentPlatform"
        case minimumPlatform = "environment.minimumPlatform"
    }

    static let tokenIDs = TokenID.allCases.map(\.rawValue)

    enum SemanticColors {
        static let roleIDs = Array(TokenID.allCases.prefix(15)).map(\.rawValue)

        static let workBackground = Color(uiColor: .systemBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)
        static let elevatedSurface = Color(uiColor: .secondarySystemGroupedBackground)
        static let primaryText = Color(uiColor: .label)
        static let secondaryText = Color(uiColor: .secondaryLabel)
        static let tertiaryText = Color(uiColor: .tertiaryLabel)
        static let separator = Color(uiColor: .separator)
        static let primaryAction = AssetRoundsBrandColorAsset.accentTeal.color
        static let brandHeading = AssetRoundsBrandColorAsset.deepTeal.color
        static let completed = AssetRoundsBrandColorAsset.checkpointGreen.color
        static let warning = Color(uiColor: .systemOrange)
        static let error = Color(uiColor: .systemRed)
        static let unavailable = Color(uiColor: .label)
        static let selected = AssetRoundsBrandColorAsset.accentTeal.color
        static let disabled = Color(uiColor: .tertiaryLabel)
    }

    enum Colors {
        static let semanticRoleIDs = SemanticColors.roleIDs
        static let assetNames = WorklightColorAsset.allCases.map(\.rawValue)
        static let brandAssetNames = AssetRoundsBrandColorAsset.allCases.map(\.rawValue)

        // Compatibility roles used by released screens before S10.3.
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

        // Frozen AssetRounds brand colors. Named catalog variants resolve appearance
        // and Increased Contrast without feature-owned color literals.
        static let accentTeal = AssetRoundsBrandColorAsset.accentTeal.color
        static let deepTeal = AssetRoundsBrandColorAsset.deepTeal.color
        static let checkpointGreen = AssetRoundsBrandColorAsset.checkpointGreen.color
        static let brandCanvas = AssetRoundsBrandColorAsset.brandCanvas.color
        static let ink = AssetRoundsBrandColorAsset.ink.color
        static let slate = AssetRoundsBrandColorAsset.slate.color

        // Frozen semantic roles. System colors remain system-owned so Light, Dark,
        // Increased Contrast, and disabled-control behavior follow the platform.
        static let workBackground = SemanticColors.workBackground
        static let groupedBackground = SemanticColors.groupedBackground
        static let elevatedSurface = SemanticColors.elevatedSurface
        static let separator = SemanticColors.separator
        static let primaryAction = SemanticColors.primaryAction
        static let brandHeading = SemanticColors.brandHeading
        static let completed = SemanticColors.completed
        static let warning = SemanticColors.warning
        static let error = SemanticColors.error
        static let unavailable = SemanticColors.unavailable
        static let selected = SemanticColors.selected
        static let disabled = SemanticColors.disabled
    }

    enum Typography {
        static let roleIDs = Array(TokenID.allCases.dropFirst(15).prefix(7)).map(\.rawValue)

        static let screenTitle = Font.largeTitle
        static let sectionHeading = Font.headline
        static let primaryBody = Font.body
        static let secondaryBody = Font.subheadline
        static let fieldLabel = Font.subheadline.weight(.semibold)
        static let supportingCaption = Font.caption
        static let numericOrTimestamp = Font.body.monospacedDigit()
    }

    enum Spacing {
        static let roleIDs = Array(TokenID.allCases.dropFirst(22).prefix(7)).map(\.rawValue)

        static let unit: CGFloat = 8
        static let space4: CGFloat = 4
        static let space8: CGFloat = 8
        static let space12: CGFloat = 12
        static let space16: CGFloat = 16
        static let space20: CGFloat = 20
        static let space24: CGFloat = 24
        static let space32: CGFloat = 32

        static let small: CGFloat = unit
        static let medium: CGFloat = unit * 2
        static let large: CGFloat = unit * 3
        static let extraLarge: CGFloat = unit * 4
        static let cardPadding: CGFloat = medium
    }

    enum Radius {
        static let roleIDs = Array(TokenID.allCases.dropFirst(29).prefix(3)).map(\.rawValue)

        static let compact: CGFloat = 8
        static let standard: CGFloat = 12
        static let prominent: CGFloat = 16
    }

    enum Stroke {
        static let roleIDs = Array(TokenID.allCases.dropFirst(32).prefix(2)).map(\.rawValue)

        static let standard: CGFloat = 1
        static let selected: CGFloat = 2
    }

    enum Target {
        static let roleIDs = [TokenID.minimumInteractive.rawValue]

        static let minimumInteractiveWidth: CGFloat = 44
        static let minimumInteractiveHeight: CGFloat = 44
        static let minimumInteractive = CGSize(
            width: minimumInteractiveWidth,
            height: minimumInteractiveHeight
        )
    }

    enum Environment {
        static let roleIDs = Array(TokenID.allCases.suffix(10)).map(\.rawValue)
        static let minimumSupportedIOSMajorVersion = 18
    }

    enum Control {
        static let minimumHitSize: CGFloat = 44
    }
}

struct AssetRoundsScreenFoundation<Content: View>: View {
    private let title: Text?
    private let content: Content

    init(title: Text? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            DesignTokens.SemanticColors.workBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                if let title {
                    title
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .accessibilityAddTraits(.isHeader)
                }

                content
            }
            .font(DesignTokens.Typography.primaryBody)
            .foregroundStyle(DesignTokens.SemanticColors.primaryText)
            .padding(DesignTokens.Spacing.space16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
