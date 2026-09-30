import Foundation
import MessageUI
import SwiftUI
import UIKit

struct FeedbackMailAttachmentV1: Equatable, Sendable {
    let data: Data
    let filename: String
    let mimeType: String
}

struct FeedbackMailDraftV1: Equatable, Sendable {
    let recipients: [String]
    let subject: String
    let body: String
    let attachments: [FeedbackMailAttachmentV1]
}

enum FeedbackMailDraftError: Error, Equatable {
    case invalidAuthority
}

enum FeedbackMailDraftBuilderV1 {
    static func make(
        configuration: FeedbackConfigurationV1,
        diagnostic: PreparedDiagnosticExportV1,
        attachmentChoice: FeedbackAttachmentChoiceV1
    ) throws -> FeedbackMailDraftV1 {
        guard let address = configuration.validatedSupportAddress,
              diagnostic.value.isValid,
              let exactData = try? DiagnosticExportCanonicalEncoderV1.encode(
                  diagnostic.value
              ),
              exactData == diagnostic.canonicalData else {
            throw FeedbackMailDraftError.invalidAuthority
        }

        let value = diagnostic.value
        let body = String(
            format: BundledLocalizationCatalogV1.localized(.feedbackBodyTemplate),
            locale: Locale(identifier: BundledLocalizationCatalogV1.runtimeLanguage),
            value.app.version, value.app.build, value.device.model, value.device.osVersion
        )
        let attachments: [FeedbackMailAttachmentV1]
        switch attachmentChoice {
        case .attach:
            attachments = [
                FeedbackMailAttachmentV1(
                    data: diagnostic.canonicalData,
                    filename: "field-record-diagnostics.json",
                    mimeType: "application/json"
                ),
            ]
        case .doNotAttach:
            attachments = []
        }
        return FeedbackMailDraftV1(
            recipients: [address],
            subject: BundledLocalizationCatalogV1.localized(.feedbackSubject),
            body: body,
            attachments: attachments
        )
    }
}

enum FeedbackMailResultV1: Equatable, Sendable {
    case cancelled
    case failed
    case saved
    case sent
}

@MainActor
struct MailComposerAdapter {
    typealias ControllerFactory = (
        FeedbackMailDraftV1,
        MailComposerCoordinator
    ) -> UIViewController

    private let availability: () -> Bool
    fileprivate let controllerFactory: ControllerFactory

    init(
        availability: @escaping () -> Bool,
        controllerFactory: @escaping ControllerFactory
    ) {
        self.availability = availability
        self.controllerFactory = controllerFactory
    }

    var isAvailable: Bool { availability() }

    static var live: MailComposerAdapter {
        MailComposerAdapter(
            availability: { MFMailComposeViewController.canSendMail() },
            controllerFactory: { draft, coordinator in
                let controller = MFMailComposeViewController()
                controller.mailComposeDelegate = coordinator
                controller.setToRecipients(draft.recipients)
                controller.setSubject(draft.subject)
                controller.setMessageBody(draft.body, isHTML: false)
                for attachment in draft.attachments {
                    controller.addAttachmentData(
                        attachment.data,
                        mimeType: attachment.mimeType,
                        fileName: attachment.filename
                    )
                }
                return controller
            }
        )
    }

    static var unavailable: MailComposerAdapter {
        MailComposerAdapter(
            availability: { false },
            controllerFactory: { _, _ in UIViewController() }
        )
    }

    static var uiTest: MailComposerAdapter {
        MailComposerAdapter(
            availability: { true },
            controllerFactory: { draft, coordinator in
                FeedbackUITestMailViewController(
                    draft: draft,
                    finished: { coordinator.complete(.saved) }
                )
            }
        )
    }
}

struct MailComposerSheet: UIViewControllerRepresentable {
    let adapter: MailComposerAdapter
    let draft: FeedbackMailDraftV1
    let finished: @MainActor (FeedbackMailResultV1) -> Void

    func makeCoordinator() -> MailComposerCoordinator {
        MailComposerCoordinator(finished: finished)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        adapter.controllerFactory(draft, context.coordinator)
    }

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {}
}

@MainActor
final class MailComposerCoordinator: NSObject {
    private let finished: @MainActor (FeedbackMailResultV1) -> Void
    private var didFinish = false

    init(finished: @escaping @MainActor (FeedbackMailResultV1) -> Void) {
        self.finished = finished
    }

    func complete(_ result: FeedbackMailResultV1) {
        guard !didFinish else { return }
        didFinish = true
        finished(result)
    }

    nonisolated static func outcome(
        for result: MFMailComposeResult,
        hasError: Bool
    ) -> FeedbackMailResultV1 {
        if hasError { return .failed }
        switch result {
        case .cancelled:
            return .cancelled
        case .failed:
            return .failed
        case .saved:
            return .saved
        case .sent:
            return .sent
        @unknown default:
            return .failed
        }
    }
}

extension MailComposerCoordinator: MFMailComposeViewControllerDelegate {
    nonisolated func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: (any Error)?
    ) {
        let outcome = Self.outcome(for: result, hasError: error != nil)
        // MessageUI invokes this delegate on the main thread. Keep the handoff
        // synchronous so the first terminal callback deterministically wins;
        // no controller or Error value crosses the actor boundary.
        MainActor.assumeIsolated {
            complete(outcome)
        }
    }
}

@MainActor
private final class FeedbackUITestMailViewController: UIViewController {
    private let draft: FeedbackMailDraftV1
    private let finished: () -> Void

    init(draft: FeedbackMailDraftV1, finished: @escaping () -> Void) {
        self.draft = draft
        self.finished = finished
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = BundledLocalizationCatalogV1.localized(.mailComposerTitle)
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.accessibilityTraits.insert(.header)
        title.accessibilityIdentifier = FeedbackMailAccessibilityIDV1.screen.rawValue

        let recipient = UILabel()
        recipient.text = String(
            format: BundledLocalizationCatalogV1.localized(.mailRecipient),
            draft.recipients.joined(separator: ", ")
        )
        recipient.font = .preferredFont(forTextStyle: .body)
        recipient.adjustsFontForContentSizeCategory = true
        recipient.numberOfLines = 0
        recipient.accessibilityIdentifier = FeedbackMailAccessibilityIDV1.recipient.rawValue

        let attachment = UILabel()
        attachment.text = String.localizedStringWithFormat(
            BundledLocalizationCatalogV1.localized(.mailAttachmentCount),
            draft.attachments.count
        )
        attachment.font = .preferredFont(forTextStyle: .body)
        attachment.adjustsFontForContentSizeCategory = true
        attachment.numberOfLines = 0
        attachment.accessibilityIdentifier = FeedbackMailAccessibilityIDV1.attachmentCount.rawValue
        attachment.accessibilityValue = BundledLocalizationCatalogV1.formattedInteger(
            draft.attachments.count
        )

        let bodyLabel = UILabel()
        bodyLabel.text = BundledLocalizationCatalogV1.localized(.mailMessageHeading)
        bodyLabel.font = .preferredFont(forTextStyle: .headline)
        bodyLabel.adjustsFontForContentSizeCategory = true

        let message = UITextView()
        message.text = draft.body
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.layer.borderColor = UIColor.separator.cgColor
        message.layer.borderWidth = 1
        message.layer.cornerRadius = 8
        message.accessibilityLabel = BundledLocalizationCatalogV1.localized(.mailMessageLabel)
        message.accessibilityIdentifier = FeedbackMailAccessibilityIDV1.body.rawValue
        message.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
            .isActive = true

        let done = UIButton(type: .system)
        done.setTitle(BundledLocalizationCatalogV1.localized(.commonDone), for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.titleLabel?.adjustsFontForContentSizeCategory = true
        done.accessibilityIdentifier = FeedbackMailAccessibilityIDV1.done.rawValue
        done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
            .isActive = true
        done.addAction(UIAction { [weak self] _ in
            self?.finished()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            title, recipient, attachment, bodyLabel, message, done,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.leadingAnchor,
                constant: 20
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.trailingAnchor,
                constant: -20
            ),
            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: 24
            ),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -24
            ),
        ])
    }
}
