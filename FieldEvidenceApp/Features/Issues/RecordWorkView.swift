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
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.space16) {
                AssetRoundsEvidenceCard {
                    Text("Record work")
                        .font(DesignTokens.Typography.screenTitle)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
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
                    .frame(minHeight: DesignTokens.Target.minimumInteractiveHeight)
                    .accessibilityLabel("Date")
                    .accessibilityHint("Required")
                    .accessibilityIdentifier(Self.dateAccessibilityIdentifier)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                        Text("Short description")
                            .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)

                        TextField("Short description", text: $description, axis: .vertical)
                            .lineLimit(3 ... 5)
                            .focused($fieldFocus)
                            .onChange(of: description) { _, value in
                                guard showsDescriptionValidation else { return }
                                let normalizedValue = value
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                if !normalizedValue.isEmpty,
                                   normalizedValue.count <= 160 {
                                    showsDescriptionValidation = false
                                }
                            }
                            .padding(DesignTokens.Spacing.space16)
                            .frame(
                                minHeight: DesignTokens.Target.minimumInteractiveHeight,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.SemanticColors.elevatedSurface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        showsDescriptionValidation
                                            ? DesignTokens.SemanticColors.warning
                                            : DesignTokens.SemanticColors.separator,
                                        lineWidth: showsDescriptionValidation ? DesignTokens.Stroke.selected : DesignTokens.Stroke.standard
                                    )
                            }
                            .accessibilityLabel("Short description")
                            .accessibilityHint("Required")
                            .accessibilityIdentifier(Self.descriptionAccessibilityIdentifier)
                            .accessibilityFocused(
                                $accessibilityFocus,
                                equals: .description
                            )

                        if showsDescriptionValidation {
                            Label {
                                Text("Short description")
                                    .foregroundStyle(
                                        DesignTokens.SemanticColors.primaryText
                                    )
                            } icon: {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(
                                        DesignTokens.SemanticColors.warning
                                    )
                            }
                            .font(DesignTokens.Typography.primaryBody.weight(.semibold))
                            .accessibilityIdentifier(Self.validationAccessibilityIdentifier)
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.space8) {
                        Text("Note")
                            .font(DesignTokens.Typography.supportingCaption.weight(.semibold))
                            .foregroundStyle(DesignTokens.SemanticColors.primaryText)

                        TextField("Note", text: $note, axis: .vertical)
                            .lineLimit(2 ... 5)
                            .padding(DesignTokens.Spacing.space16)
                            .frame(
                                minHeight: DesignTokens.Target.minimumInteractiveHeight,
                                alignment: .topLeading
                            )
                            .background(DesignTokens.SemanticColors.elevatedSurface)
                            .clipShape(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.standard)
                                    .stroke(
                                        DesignTokens.SemanticColors.separator,
                                        lineWidth: DesignTokens.Stroke.standard
                                    )
                            }
                            .accessibilityLabel("Note")
                            .accessibilityHint("Optional")
                            .accessibilityIdentifier(Self.noteAccessibilityIdentifier)
                    }
                }

                AssetRoundsPhotoCapture {
                    Text("Add one optional photo showing the work performed.")
                        .font(DesignTokens.Typography.primaryBody)
                        .foregroundStyle(DesignTokens.SemanticColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if usesImportedFixtureForUITest {
                        AssetRoundsSecondaryAction(
                            "Add one optional photo showing the work performed.",
                            action: importFixture
                        )
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
                .accessibilityHidden(showsDescriptionValidation && fieldFocus)

                if isSaving {
                    ProgressView("Record work")
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Target.minimumInteractiveHeight)
                        .accessibilityIdentifier(Self.savingAccessibilityIdentifier)
                        .accessibilityFocused($accessibilityFocus, equals: .saving)
                }

                if showsFailure {
                    Label("Record work", systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.primaryBody.weight(.semibold))
                        .foregroundStyle(DesignTokens.SemanticColors.warning)
                        .accessibilityIdentifier(Self.failureAccessibilityIdentifier)
                        .accessibilityFocused($accessibilityFocus, equals: .failure)
                }

                AssetRoundsPrimaryAction("Record work", action: save)
                    .disabled(isSaving)
                    .accessibilityIdentifier(Self.saveAccessibilityIdentifier)
                    .accessibilityHidden(
                        isSaving || (showsDescriptionValidation && fieldFocus)
                    )
            }
            .padding(DesignTokens.Spacing.space16)
        }
        .scrollDismissesKeyboard(showsDescriptionValidation ? .never : .immediately)
        .navigationTitle("Record work")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.SemanticColors.workBackground)
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
        let minimumSavingPresentationNanoseconds: UInt64 =
            usesImportedFixtureForUITest
                ? (photos.isEmpty ? 5_000_000_000 : 75_000_000_000)
                : 5_000_000_000
        Task {
            let minimumSavingPresentation = Task<Void, Never> {
                try? await Task.sleep(
                    nanoseconds: minimumSavingPresentationNanoseconds
                )
            }
            do {
                let issue = try await coordinator.saveWork(
                    draftID: draft.recordID,
                    submission: submission
                )
                await minimumSavingPresentation.value
                isSaving = false
                onComplete(issue)
            } catch {
                await minimumSavingPresentation.value
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
