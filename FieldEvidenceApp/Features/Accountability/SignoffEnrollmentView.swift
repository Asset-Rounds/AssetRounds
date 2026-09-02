import SwiftUI

/// Route facts for the contained C43 enrollment surface. The model carries
/// only stable identifiers and the frozen purpose; it does not restore or
/// persist a navigation path.
struct SignoffEnrollmentRouteMetadataV1: Equatable, Hashable, Sendable {
    let workspaceID: WorkspaceID
    let signoffID: UUID
    let subjectID: UUID
    let subjectRevision: UInt64
    let purpose: String

    init(
        workspaceID: WorkspaceID,
        subjectID: UUID,
        subjectRevision: UInt64,
        signoffID: UUID = UUID()
    ) {
        self.workspaceID = workspaceID
        self.signoffID = signoffID
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        purpose = SignoffEnrollmentManifestV1.workDetailCompletedResponseV1.purpose
    }

    var editorRoute: SignoffEditorRouteV1 {
        SignoffEditorRouteV1(
            workspaceID: workspaceID,
            signoffID: signoffID,
            expectedRevision: subjectRevision
        )
    }

    var historyRoute: SignoffHistoryRouteV1 {
        SignoffHistoryRouteV1(workspaceID: workspaceID, signoffID: signoffID)
    }

    var routeChain: SignoffEnrollmentRouteChainTruthV1 {
        SignoffEnrollmentRouteChainTruthV1()
    }
}

/// The typed, pre-canonical input emitted by the view. A drawn mark is
/// represented by presence only; no strokes, image bytes, timing, pressure,
/// or biometric/template data leave the view.
struct SignoffEnrollmentSubmissionV1: Equatable, Sendable {
    let route: SignoffEnrollmentRouteMetadataV1
    let typedName: String
    let claimedRole: String
    let claimedRelationship: SitePartyRoleV1?
    let disclosure: SignoffEnrollmentDisclosureV1
    let drawnMark: SignoffEnrollmentDrawnMarkV1?

    init(
        route: SignoffEnrollmentRouteMetadataV1,
        typedName: String,
        claimedRole: String,
        claimedRelationship: SitePartyRoleV1? = nil,
        disclosure: SignoffEnrollmentDisclosureV1 = SignoffEnrollmentDisclosureV1(),
        drawnMark: SignoffEnrollmentDrawnMarkV1? = nil
    ) {
        self.route = route
        self.typedName = typedName
        self.claimedRole = claimedRole
        self.claimedRelationship = claimedRelationship
        self.disclosure = disclosure
        self.drawnMark = drawnMark
    }
}

enum SignoffEnrollmentRevisionStateV1: String, Equatable, Sendable {
    case current
    case stale
    case unavailable
}

/// Shared, iPhone-native C43 response editor. It owns no canonical writer,
/// identity resolution, biometric operation, or route transition. The owner
/// receives a typed submission and decides whether the existing canonical
/// command can accept it.
@MainActor
struct SignoffEnrollmentView: View {
    static let editorAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.editor"
    static let screenAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.screen"
    static let workRootAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.work-root"
    static let immutableDetailAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.immutable-work-detail"
    static let moreAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.more"
    static let recordResponseAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.record-approval-response"
    static let historyAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.history"
    static let headerAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.header"
    static let subjectAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.subject"
    static let purposeAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.purpose"
    static let revisionAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.revision"
    static let disclosureSectionAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.disclosure-section"
    static let disclosureAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.disclosure"
    static let typedNameAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.typed-name"
    static let claimedRoleAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.claimed-role"
    static let claimedRelationshipAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.claimed-relationship"
    static let drawnMarkAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.drawn-mark"
    static let drawnMarkStatusAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.drawn-mark.status"
    static let clearDrawnMarkAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.drawn-mark.clear"
    static let skipDrawnMarkAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.drawn-mark.skip"
    static let validationAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.validation"
    static let failureAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.failure"
    static let statusAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.status"
    static let confirmAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.confirm"
    static let recordApprovalResponseAccessibilityIdentifier = confirmAccessibilityIdentifier
    static let cancelAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.cancel"
    static let boundariesAccessibilityIdentifier = "v23.p04.c43.signoff-enrollment.boundaries"

    let route: SignoffEnrollmentRouteMetadataV1
    let revisionState: SignoffEnrollmentRevisionStateV1
    let onRecordResponse: @MainActor (SignoffEnrollmentSubmissionV1) -> Void
    let onCancel: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @FocusState private var focusedField: Field?

    @State private var typedName: String
    @State private var claimedRole: String
    @State private var claimedRelationship: SitePartyRoleV1?
    @State private var markStrokes: [MarkStroke] = []
    @State private var activeStrokeID: UUID?
    @State private var validationMessage: String?
    @State private var failureMessage: String?
    @State private var statusMessage: String?
    @State private var isSubmitting = false

    private enum FocusTarget: Hashable {
        case heading
        case typedName
        case claimedRole
        case revisionWarning
        case errorSummary
        case status
    }

    private enum Field: Hashable {
        case typedName
        case claimedRole
    }

    private struct MarkStroke: Identifiable, Equatable {
        let id: UUID
        var points: [CGPoint]
    }

    init(
        route: SignoffEnrollmentRouteMetadataV1,
        revisionState: SignoffEnrollmentRevisionStateV1 = .current,
        initialTypedName: String = "",
        initialClaimedRole: String = "",
        initialClaimedRelationship: SitePartyRoleV1? = nil,
        onRecordResponse: @escaping @MainActor (SignoffEnrollmentSubmissionV1) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.route = route
        self.revisionState = revisionState
        self.onRecordResponse = onRecordResponse
        self.onCancel = onCancel
        _typedName = State(initialValue: initialTypedName)
        _claimedRole = State(initialValue: initialClaimedRole)
        _claimedRelationship = State(initialValue: initialClaimedRelationship)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                heading
                subjectContext
                responseFields
                disclosure
                optionalDrawnMark

                if let validationMessage {
                    messageCard(
                        text: validationMessage,
                        identifier: Self.validationAccessibilityIdentifier,
                        focus: .errorSummary,
                        systemImage: "exclamationmark.circle.fill"
                    )
                }

                if let failureMessage {
                    messageCard(
                        text: failureMessage,
                        identifier: Self.failureAccessibilityIdentifier,
                        focus: .errorSummary,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                }

                if let statusMessage {
                    messageCard(
                        text: statusMessage,
                        identifier: Self.statusAccessibilityIdentifier,
                        focus: .status,
                        systemImage: "info.circle.fill"
                    )
                }

                actions
                boundaries
            }
            .padding(DesignTokens.Spacing.medium)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(Self.editorAccessibilityIdentifier)
        }
        .navigationTitle("Record response")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            moveAccessibilityFocus(
                to: revisionState == .current ? .heading : .revisionWarning
            )
        }
        .onDisappear {
            markStrokes.removeAll()
            activeStrokeID = nil
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text("Record approval response")
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                .accessibilityFocused($accessibilityFocus, equals: .heading)

            Text(
                "Add your typed response about this completed work. The response is your own local assertion and does not change the work record."
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subjectContext: some View {
        WorklightCard {
            sectionHeading("Completed work", identifier: Self.immutableDetailAccessibilityIdentifier)
            valueRow("Subject", route.subjectID.uuidString)
            valueRow("Purpose", route.purpose)
                .accessibilityIdentifier(Self.purposeAccessibilityIdentifier)
            valueRow("Completed-work revision", "\(route.subjectRevision)")
                .accessibilityIdentifier(Self.revisionAccessibilityIdentifier)

            if revisionState == .current {
                Text(
                    "This response is bound to the supplied immutable completed-work revision. Review the detail again if the revision becomes stale."
                )
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(revisionMessage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.attentionText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityFocused($accessibilityFocus, equals: .revisionWarning)
            }

            Text("The owner supplies the SignoffHistoryRouteV1 destination after a response action is accepted.")
                .font(.footnote)
                .foregroundStyle(DesignTokens.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.historyAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var responseFields: some View {
        WorklightCard {
            sectionHeading("Your response", identifier: "\(Self.screenAccessibilityIdentifier).fields")
            requiredTextField(
                title: "Typed name",
                prompt: "Type your name",
                text: $typedName,
                hint: "Required. This is a self-entered name and is not identity verification.",
                identifier: Self.typedNameAccessibilityIdentifier,
                focusTarget: .typedName,
                field: .typedName,
                submitLabel: .next
            ) {
                focusedField = .claimedRole
            }
            requiredTextField(
                title: "Claimed role",
                prompt: "Type your claimed role",
                text: $claimedRole,
                hint: "Required. This is your claimed role and is not verified authority.",
                identifier: Self.claimedRoleAccessibilityIdentifier,
                focusTarget: .claimedRole,
                field: .claimedRole,
                submitLabel: .done
            ) {
                focusedField = nil
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Text("Claimed relationship")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.secondaryText)
                Picker("Claimed relationship", selection: $claimedRelationship) {
                    Text("Not specified")
                        .tag(nil as SitePartyRoleV1?)
                    ForEach(SitePartyRoleV1.allCases, id: \.self) { relationship in
                        Text(relationshipDisplayName(relationship))
                            .tag(Optional(relationship))
                    }
                }
                .pickerStyle(.menu)
                .frame(minHeight: DesignTokens.Control.minimumHitSize, alignment: .leading)
                .accessibilityLabel("Claimed relationship")
                .accessibilityHint(
                    "Optional. This is a self-entered relationship and is not verified."
                )
                .accessibilityIdentifier(Self.claimedRelationshipAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var disclosure: some View {
        WorklightCard {
            sectionHeading(
                "What this records",
                identifier: Self.disclosureSectionAccessibilityIdentifier
            )
            Text(SignoffEnrollmentDisclosureV1.disclosureText)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(Self.disclosureAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
    }

    private var optionalDrawnMark: some View {
        WorklightCard {
            sectionHeading("Optional drawn mark", identifier: Self.drawnMarkAccessibilityIdentifier)
            Text(
                "You may leave this blank. A drawn mark is not required, is not biometric, is not identity proof, and is not stored as a copy."
            )
            .font(.body)
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)

            Canvas { context, size in
                var path = Path()
                for stroke in markStrokes {
                    guard let first = stroke.points.first else { continue }
                    path.move(to: first)
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                context.stroke(
                    path,
                    with: .color(DesignTokens.Colors.primaryText),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(DesignTokens.Colors.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                    .stroke(DesignTokens.Colors.essentialControlStroke, lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(appendMarkPoint)
                    .onEnded { _ in activeStrokeID = nil }
            )
            .accessibilityHidden(true)

            Text(
                markStrokes.isEmpty
                    ? "No drawn mark is present."
                    : "A temporary drawn mark is present for this screen only."
            )
            .font(.footnote)
            .foregroundStyle(DesignTokens.Colors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(Self.drawnMarkStatusAccessibilityIdentifier)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                Button("Clear drawn mark") {
                    markStrokes.removeAll()
                    activeStrokeID = nil
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(markStrokes.isEmpty || isSubmitting)
                .accessibilityHint("Removes the temporary mark from this screen.")
                .accessibilityIdentifier(Self.clearDrawnMarkAccessibilityIdentifier)

                Button("Skip drawn mark") {
                    markStrokes.removeAll()
                    activeStrokeID = nil
                }
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityHint("Continues without a drawn mark. Typed entry remains available.")
                .accessibilityIdentifier(Self.skipDrawnMarkAccessibilityIdentifier)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Button("Record approval response", action: submit)
                .buttonStyle(WorklightPrimaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityHint(
                    "Records your self-asserted response after required fields are valid. It does not verify identity or approval."
                )
                .accessibilityIdentifier(Self.confirmAccessibilityIdentifier)

            Button("Cancel", action: cancel)
                .buttonStyle(WorklightSecondaryButtonStyle())
                .disabled(isSubmitting)
                .accessibilityHint("Returns to the completed-work detail without recording a response.")
                .accessibilityIdentifier(Self.cancelAccessibilityIdentifier)
        }
    }

    private var boundaries: some View {
        WorklightCard {
            sectionHeading("Accessibility and boundaries", identifier: Self.boundariesAccessibilityIdentifier)
            Text(
                "Typed entry is complete for VoiceOver, Voice Control, Switch Control, keyboard, and motor access. The drawn mark is optional and has accessible Clear and Skip controls."
            )
            Text(
                "This local response does not claim verified identity or authority, final approval, acceptance for another person, a workflow transition, a legal signature or effect, or nonrepudiation."
            )
        }
        .font(.footnote)
        .foregroundStyle(DesignTokens.Colors.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var contentSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? DesignTokens.Spacing.large
            : DesignTokens.Spacing.medium
    }

    private var revisionMessage: String {
        switch revisionState {
        case .current:
            return ""
        case .stale:
            return "This completed-work revision is stale. Return to the detail and review the current immutable revision before recording a response."
        case .unavailable:
            return "This completed-work revision is unavailable. Return to the detail and review the completed work before recording a response."
        }
    }

    private func sectionHeading(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)
            Text(value)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func requiredTextField(
        title: String,
        prompt: String,
        text: Binding<String>,
        hint: String,
        identifier: String,
        focusTarget: FocusTarget,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.secondaryText)

            TextField(prompt, text: text, axis: .vertical)
                .lineLimit(1 ... 4)
                .focused($focusedField, equals: field)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .padding(DesignTokens.Spacing.medium)
                .frame(minHeight: DesignTokens.Control.minimumHitSize, alignment: .topLeading)
                .background(DesignTokens.Colors.raisedSurface)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.standard))
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                        .stroke(
                            validationMessage == nil
                                ? DesignTokens.Colors.essentialControlStroke
                                : DesignTokens.Colors.attentionText,
                            lineWidth: validationMessage == nil ? 1 : 2
                        )
                }
                .accessibilityLabel(title)
                .accessibilityHint(hint)
                .accessibilityIdentifier(identifier)
                .accessibilityFocused($accessibilityFocus, equals: focusTarget)
        }
    }

    private func messageCard(
        text: String,
        identifier: String,
        focus: FocusTarget,
        systemImage: String
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.attentionText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
            .accessibilityFocused($accessibilityFocus, equals: focus)
    }

    private func submit() {
        validationMessage = nil
        failureMessage = nil
        statusMessage = nil

        guard revisionState == .current else {
            validationMessage = revisionMessage
            moveAccessibilityFocus(to: .errorSummary)
            return
        }

        let normalizedName = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            validationMessage = "Enter a typed name to record your response."
            focusedField = .typedName
            moveAccessibilityFocus(to: .typedName)
            return
        }
        guard normalizedName.utf8.count <= PartyAccountabilityLimitsV1.maximumDisplayNameBytes else {
            validationMessage = "The typed name is too long. Use a shorter name and try again."
            focusedField = .typedName
            moveAccessibilityFocus(to: .typedName)
            return
        }

        let normalizedRole = claimedRole.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRole.isEmpty else {
            validationMessage = "Enter a claimed role to record your response."
            focusedField = .claimedRole
            moveAccessibilityFocus(to: .claimedRole)
            return
        }
        guard normalizedRole.utf8.count <= PartyAccountabilityLimitsV1.maximumDisplayNameBytes else {
            validationMessage = "The claimed role is too long. Use a shorter role and try again."
            focusedField = .claimedRole
            moveAccessibilityFocus(to: .claimedRole)
            return
        }

        let submission = SignoffEnrollmentSubmissionV1(
            route: route,
            typedName: normalizedName,
            claimedRole: normalizedRole,
            claimedRelationship: claimedRelationship,
            disclosure: SignoffEnrollmentDisclosureV1(),
            drawnMark: markStrokes.isEmpty ? nil : .presentNonBiometric
        )

        isSubmitting = true
        onRecordResponse(submission)
        isSubmitting = false
        markStrokes.removeAll()
        activeStrokeID = nil
        statusMessage = "Record approval response action invoked. This surface does not claim a saved, final, or verified result."
        moveAccessibilityFocus(to: .status)
    }

    private func cancel() {
        markStrokes.removeAll()
        activeStrokeID = nil
        onCancel()
    }

    private func appendMarkPoint(_ value: DragGesture.Value) {
        guard !isSubmitting else { return }
        if let activeStrokeID,
           let index = markStrokes.firstIndex(where: { $0.id == activeStrokeID }) {
            markStrokes[index].points.append(value.location)
            return
        }

        let stroke = MarkStroke(id: UUID(), points: [value.location])
        activeStrokeID = stroke.id
        markStrokes.append(stroke)
    }

    private func relationshipDisplayName(_ relationship: SitePartyRoleV1) -> String {
        relationship.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = target
        }
    }
}
