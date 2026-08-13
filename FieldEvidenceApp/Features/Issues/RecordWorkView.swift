import PhotosUI
import SwiftUI
import UIKit

struct RecordWorkView: View {
    static let screenAccessibilityIdentifier = "s5.1.work.screen"
    static let headerAccessibilityIdentifier = "s5.1.work.header"
    static let dateAccessibilityIdentifier = "s5.1.work.date"
    static let descriptionAccessibilityIdentifier = "s5.1.work.description"
    static let noteAccessibilityIdentifier = "s5.1.work.note"
    static let photoAccessibilityIdentifier = "s5.1.work.photo"
    static let importFixtureAccessibilityIdentifier = "s5.1.work.import-fixture"
    static let saveAccessibilityIdentifier = "s5.1.work.save"
    static let savingAccessibilityIdentifier = "s5.1.work.saving"
    static let validationAccessibilityIdentifier = "s5.1.work.validation"
    static let failureAccessibilityIdentifier = "s5.1.work.failure"

    private enum FocusTarget: Hashable {
        case header
        case description
        case saving
        case failure
    }

    let draft: WorkDraftValue
    let coordinator: WorkCoordinator
    let usesImportedFixtureForUITest: Bool
    let onComplete: (WorkIssuePresentationValue) -> Void

    @State private var performedDate = Date()
    @State private var description = ""
    @State private var note = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var showsDescriptionValidation = false
    @State private var showsFailure = false
    @AccessibilityFocusState private var accessibilityFocus: FocusTarget?
    @FocusState private var fieldFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                WorklightCard {
                    Text("Record work")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(Self.headerAccessibilityIdentifier)
                        .accessibilityFocused($accessibilityFocus, equals: .header)

                    DatePicker(
                        "Date",
                        selection: $performedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .frame(minHeight: DesignTokens.Control.minimumHitSize)
                    .accessibilityHint("Required")
                    .accessibilityIdentifier(Self.dateAccessibilityIdentifier)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("Short description")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.secondaryText)

                        TextField("Short description", text: $description, axis: .vertical)
                            .lineLimit(2 ... 5)
                            .focused($fieldFocus)
                            .padding(DesignTokens.Spacing.medium)
                            .frame(
                                minHeight: DesignTokens.Control.minimumHitSize,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.Colors.raisedSurface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        showsDescriptionValidation
                                            ? DesignTokens.Colors.attentionText
                                            : DesignTokens.Colors.essentialControlStroke,
                                        lineWidth: showsDescriptionValidation ? 2 : 1
                                    )
                            }
                            .accessibilityLabel("Short description")
                            .accessibilityHint("Required")
                            .accessibilityIdentifier(Self.descriptionAccessibilityIdentifier)
                            .accessibilityFocused(
                                $accessibilityFocus,
                                equals: .description
                            )
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        Text("Note")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.secondaryText)

                        TextField("Note", text: $note, axis: .vertical)
                            .lineLimit(2 ... 5)
                            .padding(DesignTokens.Spacing.medium)
                            .frame(
                                minHeight: DesignTokens.Control.minimumHitSize,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.Colors.raisedSurface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        DesignTokens.Colors.essentialControlStroke,
                                        lineWidth: 1
                                    )
                            }
                            .accessibilityLabel("Note")
                            .accessibilityHint("Optional")
                            .accessibilityIdentifier(Self.noteAccessibilityIdentifier)
                    }
                }

                WorklightCard {
                    Text("Add one optional photo showing the work performed.")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if usesImportedFixtureForUITest {
                        Button(
                            "Add one optional photo showing the work performed.",
                            action: importFixture
                        )
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isSaving)
                        .accessibilityIdentifier(Self.importFixtureAccessibilityIdentifier)
                    } else {
                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .images
                        ) {
                            Text("Add one optional photo showing the work performed.")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(WorklightSecondaryButtonStyle())
                        .disabled(isSaving)
                    }

                    if let photoData,
                       let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: image.size.width)
                            .accessibilityLabel(
                                "Add one optional photo showing the work performed."
                            )
                            .accessibilityIdentifier(Self.photoAccessibilityIdentifier)
                    }
                }

                if showsDescriptionValidation {
                    Label("Short description", systemImage: "exclamationmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .accessibilityIdentifier(Self.validationAccessibilityIdentifier)
                }

                if isSaving {
                    ProgressView("Record work")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier(Self.savingAccessibilityIdentifier)
                        .accessibilityFocused($accessibilityFocus, equals: .saving)
                }

                if showsFailure {
                    Label("Record work", systemImage: "exclamationmark.triangle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.attentionText)
                        .accessibilityIdentifier(Self.failureAccessibilityIdentifier)
                        .accessibilityFocused($accessibilityFocus, equals: .failure)
                }

                Button("Record work", action: save)
                    .buttonStyle(WorklightPrimaryButtonStyle())
                    .disabled(isSaving)
                    .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
            }
            .padding(DesignTokens.Spacing.medium)
        }
        .navigationTitle("Record work")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.canvas)
        .accessibilityIdentifier(Self.screenAccessibilityIdentifier)
        .onAppear {
            moveAccessibilityFocus(to: .header)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                photoData = try? await item.loadTransferable(type: Data.self)
            }
        }
    }

    private func save() {
        let normalizedDescription = description
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDescription.isEmpty,
              normalizedDescription.count <= 160 else {
            showsDescriptionValidation = true
            showsFailure = false
            fieldFocus = true
            moveAccessibilityFocus(to: .description)
            return
        }
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedNote.count <= 1_000 else {
            showsFailure = true
            moveAccessibilityFocus(to: .failure)
            return
        }

        isSaving = true
        showsDescriptionValidation = false
        showsFailure = false
        moveAccessibilityFocus(to: .saving)
        let now = Date()
        let photos = photoData.map {
            [
                WorkPhotoSubmission(
                    purposeKey: "work_context",
                    sourceData: $0,
                    createdAt: now
                ),
            ]
        } ?? []
        let submission = WorkSaveSubmission(
            performedLocalDate: Self.localDateFormatter.string(from: performedDate),
            description: normalizedDescription,
            note: normalizedNote.isEmpty ? nil : normalizedNote,
            photos: photos,
            completedAt: now
        )
        Task {
            do {
                let issue = try await coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: submission
                )
                isSaving = false
                onComplete(issue)
            } catch {
                isSaving = false
                showsFailure = true
                moveAccessibilityFocus(to: .failure)
            }
        }
    }

    private func importFixture() {
        guard let encoded = ProcessInfo.processInfo.environment[
            "S5_1_WORK_FIXTURE_BASE64"
        ], let data = Data(base64Encoded: encoded) else {
            showsFailure = true
            moveAccessibilityFocus(to: .failure)
            return
        }
        photoData = data
        showsFailure = false
    }

    private func moveAccessibilityFocus(to target: FocusTarget) {
        accessibilityFocus = nil
        Task { @MainActor in
            await Task.yield()
            accessibilityFocus = target
        }
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
