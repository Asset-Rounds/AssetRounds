import SwiftUI

struct WorklightCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            content
        }
        .padding(DesignTokens.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.raisedSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
        }
    }
}

enum WorklightStatusKind: String, CaseIterable {
    case complete
    case attention
    case blocked
    case information

    fileprivate var iconName: String {
        switch self {
        case .complete: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        case .information: "info.circle.fill"
        }
    }

    fileprivate var accessibilityName: String {
        switch self {
        case .complete: "Complete"
        case .attention: "Attention"
        case .blocked: "Blocked"
        case .information: "Information"
        }
    }

    fileprivate var foregroundColor: Color {
        switch self {
        case .complete: DesignTokens.Colors.completeText
        case .attention: DesignTokens.Colors.attentionText
        case .blocked: DesignTokens.Colors.blockedText
        case .information: DesignTokens.Colors.informationText
        }
    }

    fileprivate var backgroundColor: Color {
        switch self {
        case .complete: DesignTokens.Colors.completeContainer
        case .attention: DesignTokens.Colors.attentionContainer
        case .blocked: DesignTokens.Colors.blockedContainer
        case .information: DesignTokens.Colors.informationContainer
        }
    }
}

struct WorklightStatusBadge: View {
    let kind: WorklightStatusKind
    let text: String

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.iconName)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(kind.foregroundColor)
        .padding(.horizontal, DesignTokens.Spacing.medium)
        .padding(.vertical, DesignTokens.Spacing.small)
        .frame(minHeight: DesignTokens.Control.minimumHitSize)
        .background(kind.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.accessibilityName): \(text)")
    }
}

struct WorklightPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? DesignTokens.Colors.onAccent : DesignTokens.Colors.secondaryText)
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Control.minimumHitSize)
            .background(isEnabled ? DesignTokens.Colors.interactionAccent : DesignTokens.Colors.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(
                        isEnabled ? DesignTokens.Colors.interactionAccent : DesignTokens.Colors.essentialControlStroke,
                        lineWidth: 1
                    )
            }
            .brightness(configuration.isPressed && isEnabled ? -0.08 : 0)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
    }
}

struct WorklightSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? DesignTokens.Colors.interactionAccent : DesignTokens.Colors.secondaryText)
            .padding(.horizontal, DesignTokens.Spacing.medium)
            .frame(
                minWidth: DesignTokens.Control.minimumHitSize,
                minHeight: DesignTokens.Control.minimumHitSize
            )
            .background(DesignTokens.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
            }
            .brightness(configuration.isPressed && isEnabled ? -0.05 : 0)
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
    }
}

enum AssetRoundsComponentRole: String, CaseIterable {
    case screenFoundation = "component.screen-foundation"
    case primaryAction = "component.primary-action"
    case secondaryAction = "component.secondary-action"
    case destructiveAction = "component.destructive-action"
    case evidenceCard = "component.evidence-card"
    case photoCapture = "component.photo-capture"
    case stateLabel = "component.state-label"
    case emptyState = "component.empty-state"
    case reportBrandHeader = "component.report-brand-header"
}

enum AssetRoundsComponentContract {
    static let roleIDs = AssetRoundsComponentRole.allCases.map(\.rawValue)
    static let evidenceCardContentOrder = ["finding", "photo", "status", "work", "recheck"]
    static let photoCaptureFeedback = ["thumbnail", "retake", "delete", "durable state"]
    static let maximumPrimaryActionsPerState = 1
    static let usesNativeControls = true
    static let usesSystemSymbolsForFamiliarActions = true
    static let usesColorOnlyStatus = false
    static let usesNonessentialAnimation = false
    static let usesTranslucentMaterial = false
}

struct AssetRoundsPrimaryAction<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(DesignTokens.Typography.sectionHeading)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
    }
}

extension AssetRoundsPrimaryAction where Label == Text {
    init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(action: action) {
            Text(titleKey)
        }
    }
}

struct AssetRoundsSecondaryAction<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .font(DesignTokens.Typography.sectionHeading)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.SemanticColors.primaryAction)
        .controlSize(.large)
        .frame(
            minWidth: DesignTokens.Target.minimumInteractiveWidth,
            minHeight: DesignTokens.Target.minimumInteractiveHeight
        )
    }
}

extension AssetRoundsSecondaryAction where Label == Text {
    init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(action: action) {
            Text(titleKey)
        }
    }
}

struct AssetRoundsDestructiveAction<Label: View>: View {
    private let action: () -> Void
    private let label: Label

    init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            label
                .font(DesignTokens.Typography.sectionHeading)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(
            minWidth: DesignTokens.Target.minimumInteractiveWidth,
            minHeight: DesignTokens.Target.minimumInteractiveHeight
        )
    }
}

extension AssetRoundsDestructiveAction where Label == Text {
    init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.init(action: action) {
            Text(titleKey)
        }
    }
}

struct AssetRoundsEvidenceCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space12) {
            content
        }
        .font(DesignTokens.Typography.primaryBody)
        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
        .padding(DesignTokens.Spacing.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.SemanticColors.elevatedSurface)
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(
                    DesignTokens.SemanticColors.separator,
                    lineWidth: colorSchemeContrast == .increased
                        ? DesignTokens.Stroke.selected
                        : DesignTokens.Stroke.standard
                )
        }
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.standard, style: .continuous)
    }
}

struct AssetRoundsPhotoCapture<Thumbnail: View>: View {
    private enum Presentation {
        case capture
        case captured
        case content
    }

    private let presentation: Presentation
    private let captureTitle: LocalizedStringKey?
    private let retakeTitle: LocalizedStringKey?
    private let deleteTitle: LocalizedStringKey?
    private let onCapture: () -> Void
    private let onRetake: (() -> Void)?
    private let onDelete: (() -> Void)?
    private let thumbnail: Thumbnail

    init(
        retakeTitle: LocalizedStringKey,
        deleteTitle: LocalizedStringKey,
        onRetake: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) {
        self.presentation = .captured
        self.captureTitle = nil
        self.retakeTitle = retakeTitle
        self.deleteTitle = deleteTitle
        self.onCapture = onRetake
        self.onRetake = onRetake
        self.onDelete = onDelete
        self.thumbnail = thumbnail()
    }

    init(@ViewBuilder content: () -> Thumbnail) {
        self.presentation = .content
        self.captureTitle = nil
        self.retakeTitle = nil
        self.deleteTitle = nil
        self.onCapture = {}
        self.onRetake = nil
        self.onDelete = nil
        self.thumbnail = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space12) {
            switch presentation {
            case .captured:
                thumbnail
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isImage)

                if let retakeTitle, let onRetake {
                    AssetRoundsSecondaryAction(action: onRetake) {
                        Label(retakeTitle, systemImage: "camera")
                    }
                }

                if let deleteTitle, let onDelete {
                    AssetRoundsDestructiveAction(action: onDelete) {
                        Label(deleteTitle, systemImage: "trash")
                    }
                }
            case .capture:
                if let captureTitle {
                    AssetRoundsPrimaryAction(action: onCapture) {
                        Label(captureTitle, systemImage: "camera")
                    }
                }
            case .content:
                thumbnail
            }
        }
        .padding(DesignTokens.Spacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.SemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard, style: .continuous))
    }
}

extension AssetRoundsPhotoCapture where Thumbnail == EmptyView {
    init(captureTitle: LocalizedStringKey, onCapture: @escaping () -> Void) {
        self.presentation = .capture
        self.captureTitle = captureTitle
        self.retakeTitle = nil
        self.deleteTitle = nil
        self.onCapture = onCapture
        self.onRetake = nil
        self.onDelete = nil
        self.thumbnail = EmptyView()
    }
}

enum AssetRoundsStateKind: String, CaseIterable {
    case completed
    case warning
    case error
    case unavailable
    case selected

    fileprivate var iconName: String {
        switch self {
        case .completed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .unavailable: "slash.circle.fill"
        case .selected: "checkmark.circle.fill"
        }
    }

    fileprivate var accessibilityName: LocalizedStringKey {
        switch self {
        case .completed: "Completed"
        case .warning: "Warning"
        case .error: "Error"
        case .unavailable: "Unavailable"
        case .selected: "Selected"
        }
    }

    fileprivate var foregroundColor: Color {
        switch self {
        case .completed: DesignTokens.SemanticColors.completed
        case .warning: DesignTokens.SemanticColors.warning
        case .error: DesignTokens.SemanticColors.error
        case .unavailable: DesignTokens.SemanticColors.unavailable
        case .selected: DesignTokens.SemanticColors.selected
        }
    }

    fileprivate var textForegroundColor: Color {
        switch self {
        case .error: DesignTokens.SemanticColors.primaryText
        default: foregroundColor
        }
    }
}

struct AssetRoundsStateLabel: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let kind: AssetRoundsStateKind
    let text: Text

    init(kind: AssetRoundsStateKind, text: Text) {
        self.kind = kind
        self.text = text
    }

    init(kind: AssetRoundsStateKind, _ titleKey: LocalizedStringKey) {
        self.init(kind: kind, text: Text(titleKey))
    }

    var body: some View {
        Label {
            text
                .foregroundStyle(kind.textForegroundColor)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind.iconName)
                .foregroundStyle(kind.foregroundColor)
                .accessibilityHidden(true)
        }
        .font(DesignTokens.Typography.secondaryBody.weight(.semibold))
        .padding(.horizontal, DesignTokens.Spacing.space12)
        .padding(.vertical, DesignTokens.Spacing.space8)
        .background(DesignTokens.SemanticColors.elevatedSurface)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.compact, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.compact, style: .continuous)
                .stroke(
                    kind.foregroundColor,
                    lineWidth: colorSchemeContrast == .increased
                        ? DesignTokens.Stroke.selected
                        : DesignTokens.Stroke.standard
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.accessibilityName))
        .accessibilityValue(text)
    }
}

struct AssetRoundsEmptyState: View {
    let title: Text
    let message: Text
    let showsBrandSymbol: Bool
    let actionLabel: Text?
    let action: (() -> Void)?

    init(
        title: Text,
        message: Text,
        showsBrandSymbol: Bool = false,
        actionLabel: Text? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.showsBrandSymbol = showsBrandSymbol
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space24) {
            if showsBrandSymbol {
                Image(AssetRoundsBrandImageAsset.templateSymbol.rawValue)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .frame(
                        width: DesignTokens.Spacing.space32,
                        height: DesignTokens.Spacing.space32
                    )
                    .accessibilityHidden(true)
            }

            title
                .font(DesignTokens.Typography.screenTitle)
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            message
                .font(DesignTokens.Typography.primaryBody)
                .foregroundStyle(DesignTokens.SemanticColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let actionLabel, let action {
                AssetRoundsPrimaryAction(action: action) {
                    actionLabel
                }
            }
        }
        .padding(DesignTokens.Spacing.space24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.SemanticColors.workBackground)
    }
}

enum AssetRoundsBrandSymbolRendering: String, CaseIterable {
    case original
    case template
}

struct AssetRoundsReportBrandHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: Text
    let subtitle: Text?
    let symbolRendering: AssetRoundsBrandSymbolRendering

    init(
        title: Text,
        subtitle: Text? = nil,
        symbolRendering: AssetRoundsBrandSymbolRendering = .template
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbolRendering = symbolRendering
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.space12) {
                    brandSymbol
                    liveText
                }
            } else {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.space12) {
                    brandSymbol
                    liveText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var brandSymbol: some View {
        switch symbolRendering {
        case .original:
            Image(AssetRoundsBrandImageAsset.originalSymbol.rawValue)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(
                    width: DesignTokens.Spacing.space32,
                    height: DesignTokens.Spacing.space32
                )
                .accessibilityHidden(true)
        case .template:
            Image(AssetRoundsBrandImageAsset.templateSymbol.rawValue)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                .frame(
                    width: DesignTokens.Spacing.space32,
                    height: DesignTokens.Spacing.space32
                )
                .accessibilityHidden(true)
        }
    }

    private var liveText: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.space4) {
            title
                .font(DesignTokens.Typography.screenTitle)
                .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                subtitle
                    .font(DesignTokens.Typography.sectionHeading)
                    .foregroundStyle(DesignTokens.SemanticColors.brandHeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
