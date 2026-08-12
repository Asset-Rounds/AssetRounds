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
