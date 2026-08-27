import Foundation

enum BundledLocalizationKeyV1: String, CaseIterable, Sendable {
    case feedbackSubject = "feedback.mail.subject"
    case feedbackBodyTemplate = "feedback.mail.body_template"
    case mailComposerTitle = "feedback.mail.composer.title"
    case mailRecipient = "feedback.mail.recipient"
    case mailAttachmentCount = "feedback.mail.attachment_count"
    case mailMessageHeading = "feedback.mail.message.heading"
    case mailMessageLabel = "feedback.mail.message.label"
    case commonDone = "common.done"
    case packageRequiredViews = "package.illuminated_sign.guidance.required_views"
    case packageVisibleConditionsOnly = "package.illuminated_sign.guidance.visible_conditions_only"
    case packageAuthorizedPosition = "package.illuminated_sign.guidance.authorized_position"
}

enum LocalizationCatalogPublicationBoundaryV1: String, CaseIterable, Sendable {
    case beforeValidation = "BEFORE_VALIDATION"
    case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
    case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
}

struct LocalizationCatalogPublicationReceiptV1: Codable, Equatable, Sendable {
    let release: LocalizationCatalogReleaseV1
    let semanticRegistrySHA256: String
    let legacyBaselineSHA256: String
    let packageBindingSHA256s: [String]
    let persistentWriteOccurred: Bool
}

enum LocalizationCatalogPublicationV1: Equatable, Sendable {
    case zero
    case complete(
        registry: LocalizationKeyRegistryV1,
        accessibility: SemanticAccessibilityIDRegistryV1,
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        packageBindings: [PackageLocalizationReleaseBindingV1],
        receipt: LocalizationCatalogPublicationReceiptV1
    )
}

enum BundledLocalizationCatalogV1 {
    typealias Interruption = @Sendable (LocalizationCatalogPublicationBoundaryV1) throws -> Void

    static let runtimeLanguage = "en"
    static let appStorePrimaryMetadataLocale = "en-US"
    static let runtimeDownloadsAllowed = false
    static let inheritedMailAccessibilityIDs = [
        "s8.4.mail.attachment-count",
        "s8.4.mail.body",
        "s8.4.mail.done",
        "s8.4.mail.recipient",
        "s8.4.mail.screen",
    ]

    static func mailLegacyAllowlist() throws
        -> LegacyLocalizationAccessibilityAllowlistV1 {
        try LegacyLocalizationAccessibilityAllowlistV1(
            entries: inheritedMailAccessibilityIDs.map {
                LegacyLocalizationAccessibilityEntryV1(
                    kind: .phaseAccessibilityID,
                    stableFingerprint: KernelCanonicalHashV1.sha256(Data($0.utf8))
                )
            }
        )
    }

    static func registry() throws -> LocalizationKeyRegistryV1 {
        try LocalizationKeyRegistryV1(definitions: [
            try definition(.commonDone, "common.action.done", "Done", "Completes and closes the current task."),
            try definition(.feedbackBodyTemplate, "feedback.mail.body.template", "App version: %@ (%@)\nDevice: %@\nOS: iOS %@\n\nFeedback:\n", "Editable support-email body. Arguments are app version, build, device model, and OS version."),
            try definition(.feedbackSubject, "feedback.mail.subject", "App feedback", "Subject of the support email."),
            try definition(.mailAttachmentCount, "feedback.mail.attachment.count", "Diagnostic attachments: %lld", "Number of diagnostic files attached to the support email.", arguments: [.init(name: "count", shape: .integerPlural)], plurals: ["one", "other"]),
            try definition(.mailComposerTitle, "feedback.mail.composer.title", "Feedback composer", "Heading of the deterministic feedback composer used by UI tests."),
            try definition(.mailMessageHeading, "feedback.mail.message.heading", "Editable message", "Heading above the editable feedback message."),
            try definition(.mailMessageLabel, "feedback.mail.message.label", "Feedback message", "Accessibility label for the editable feedback message."),
            try definition(.mailRecipient, "feedback.mail.recipient", "To: %@", "Support-email recipient summary. Argument is the recipient list."),
            try definition(.packageRequiredViews, "package.guidance.required_views", "Capture the required views.", "Shipping illuminated-sign package guidance for required evidence views."),
            try definition(.packageVisibleConditionsOnly, "package.guidance.visible_conditions_only", "Record only conditions visible in the evidence.", "Shipping illuminated-sign package limitation guidance."),
            try definition(.packageAuthorizedPosition, "package.guidance.authorized_position", "Stand in an authorized position before taking a photo.", "Shipping illuminated-sign package safety guidance."),
        ])
    }

    static func accessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let values: [(String, String, SemanticAccessibilityRoleV1, BundledLocalizationKeyV1)] = [
            ("feedback.mail.screen", "s8.4.mail.screen", .screen, .mailComposerTitle),
            ("feedback.mail.recipient", "s8.4.mail.recipient", .group, .mailRecipient),
            ("feedback.mail.attachment-count", "s8.4.mail.attachment-count", .status, .mailAttachmentCount),
            ("feedback.mail.body", "s8.4.mail.body", .textField, .mailMessageLabel),
            ("feedback.mail.done", "s8.4.mail.done", .button, .commonDone),
        ]
        let entries = try values.map {
            AccessibilityContractV1(
                semanticID: $0.0, role: $0.2, reachability: .always,
                labelKey: try LocalizationKeyV1($0.3.rawValue), hintKey: nil,
                valueKey: nil, dynamicSuffixPolicy: .none, deprecatedAliases: [$0.1]
            )
        }
        return try SemanticAccessibilityIDRegistryV1(
            entries: entries, localization: localization
        )
    }

    static func publish(
        sourceCatalogBytes: Data,
        packagePublications: [InspectionPackagePublishedReleaseV1] = [],
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        previousRegistry: LocalizationKeyRegistryV1? = nil,
        previousLegacy: LegacyLocalizationAccessibilityAllowlistV1? = nil,
        interruption: Interruption = { _ in }
    ) throws -> LocalizationCatalogPublicationV1 {
        try interruption(.beforeValidation)
        try legacy.validate()
        let locales = LocalizationLocaleManifestV1.shippingV1()
        try locales.validate()
        let keys = try registry()
        try validateSourceCatalog(sourceCatalogBytes, registry: keys)
        if let previousRegistry { try keys.validateSuccessor(of: previousRegistry) }
        let requiredMailLegacy = try mailLegacyAllowlist()
        guard legacy == requiredMailLegacy else {
            throw LocalizationContractFailureV1.legacyAllowlistGrowth
        }
        if let previousLegacy { try previousLegacy.validateObserved(legacy.entries) }
        let accessibility = try accessibilityRegistry(localization: keys)
        let registryBytes = try LocalizationContractCanonicalCodecV1.encode(keys)
        let localeBytes = try LocalizationContractCanonicalCodecV1.encode(locales)
        let release = try LocalizationCatalogReleaseV1.make(
            sourceCatalog: sourceCatalogBytes, registry: registryBytes,
            localeManifest: localeBytes
        )
        let packageBindings = try packagePublications.map {
            try PackageLocalizationReleaseBindingV1(
                publication: $0, localizationRelease: release,
                slotBindings: try BundledInspectionPackageRegistryV2.shippingLocalizationSlotBindings(),
                registry: keys
            )
        }.sorted { $0.packageReleaseID < $1.packageReleaseID }
        try interruption(.afterValidationBeforePublication)
        let accessibilityBytes = try LocalizationContractCanonicalCodecV1.encode(accessibility)
        let legacyBytes = try LocalizationContractCanonicalCodecV1.encode(legacy)
        let bindingBytes = try packageBindings.map {
            try LocalizationContractCanonicalCodecV1.encode($0)
        }
        let receipt = LocalizationCatalogPublicationReceiptV1(
            release: release,
            semanticRegistrySHA256: KernelCanonicalHashV1.sha256(accessibilityBytes),
            legacyBaselineSHA256: KernelCanonicalHashV1.sha256(legacyBytes),
            packageBindingSHA256s: bindingBytes.map(KernelCanonicalHashV1.sha256),
            persistentWriteOccurred: false
        )
        try interruption(.afterPublicationBeforeReceipt)
        return .complete(
            registry: keys, accessibility: accessibility, legacy: legacy,
            packageBindings: packageBindings, receipt: receipt
        )
    }

    static func recover(
        sourceCatalogBytes: Data?,
        receipt: LocalizationCatalogPublicationReceiptV1?,
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        packagePublications: [InspectionPackagePublishedReleaseV1] = []
    ) throws -> LocalizationCatalogPublicationV1 {
        switch (sourceCatalogBytes, receipt) {
        case (nil, nil): return .zero
        case let (.some(bytes), .some(expected)):
            let publication = try publish(
                sourceCatalogBytes: bytes,
                packagePublications: packagePublications,
                legacy: legacy
            )
            guard case let .complete(_, _, _, _, actual) = publication,
                  actual == expected else { throw LocalizationContractFailureV1.digestMismatch }
            return publication
        default: throw LocalizationContractFailureV1.partialPublication
        }
    }

    static func localized(_ key: BundledLocalizationKeyV1, bundle: Bundle = .main) -> String {
        let locale = Locale(identifier: runtimeLanguage)
        switch key {
        case .feedbackSubject:
            return String(localized: "feedback.mail.subject", defaultValue: "App feedback", bundle: bundle, locale: locale, comment: "Subject of the support email.")
        case .feedbackBodyTemplate:
            return String(localized: "feedback.mail.body_template", defaultValue: "App version: %@ (%@)\nDevice: %@\nOS: iOS %@\n\nFeedback:\n", bundle: bundle, locale: locale, comment: "Editable support-email body. Arguments are app version, build, device model, and OS version.")
        case .mailComposerTitle:
            return String(localized: "feedback.mail.composer.title", defaultValue: "Feedback composer", bundle: bundle, locale: locale, comment: "Heading of the deterministic feedback composer used by UI tests.")
        case .mailRecipient:
            return String(localized: "feedback.mail.recipient", defaultValue: "To: %@", bundle: bundle, locale: locale, comment: "Support-email recipient summary. Argument is the recipient list.")
        case .mailAttachmentCount:
            return String(localized: "feedback.mail.attachment_count", defaultValue: "Diagnostic attachments: %lld", bundle: bundle, locale: locale, comment: "Number of diagnostic files attached to the support email.")
        case .mailMessageHeading:
            return String(localized: "feedback.mail.message.heading", defaultValue: "Editable message", bundle: bundle, locale: locale, comment: "Heading above the editable feedback message.")
        case .mailMessageLabel:
            return String(localized: "feedback.mail.message.label", defaultValue: "Feedback message", bundle: bundle, locale: locale, comment: "Accessibility label for the editable feedback message.")
        case .commonDone:
            return String(localized: "common.done", defaultValue: "Done", bundle: bundle, locale: locale, comment: "Completes and closes the current task.")
        case .packageRequiredViews:
            return String(localized: "package.illuminated_sign.guidance.required_views", defaultValue: "Capture the required views.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package guidance for required evidence views.")
        case .packageVisibleConditionsOnly:
            return String(localized: "package.illuminated_sign.guidance.visible_conditions_only", defaultValue: "Record only conditions visible in the evidence.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package limitation guidance.")
        case .packageAuthorizedPosition:
            return String(localized: "package.illuminated_sign.guidance.authorized_position", defaultValue: "Stand in an authorized position before taking a photo.", bundle: bundle, locale: locale, comment: "Shipping illuminated-sign package safety guidance.")
        }
    }

    static func formattedInteger(_ value: Int, regionSource: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = englishPresentationLocale(regionSource)
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func formattedLength(
        _ measurement: Measurement<UnitLength>, regionSource: Locale = .current
    ) -> String {
        let formatter = MeasurementFormatter()
        formatter.locale = englishPresentationLocale(regionSource)
        formatter.unitOptions = .naturalScale
        return formatter.string(from: measurement)
    }

    static func formattedDate(
        _ value: Date,
        timeZone: TimeZone,
        regionSource: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = englishPresentationLocale(regionSource)
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: value)
    }

    private static func englishPresentationLocale(_ source: Locale) -> Locale {
        Locale(identifier: "en-" + (source.region?.identifier ?? "US"))
    }

    private static func validateSourceCatalog(
        _ data: Data,
        registry: LocalizationKeyRegistryV1
    ) throws {
        guard data.count <= 2_097_152,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["sourceLanguage"] as? String == "en",
              root["version"] as? String == "1.0",
              let strings = root["strings"] as? [String: Any],
              Set(strings.keys) == Set(registry.definitions.map(\.key.rawValue)) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        for (rawKey, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let comment = entry["comment"] as? String,
                  !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let localizations = entry["localizations"] as? [String: Any],
                  Set(localizations.keys) == Set(["en"]),
                  let definition = try? registry.definition(for: LocalizationKeyV1(rawKey)) else {
                throw LocalizationContractFailureV1.missingComment
            }
            guard comment == definition.translatorComment,
                  let english = localizations["en"] as? [String: Any] else {
                throw LocalizationContractFailureV1.invalidValue
            }
            if definition.requiredEnglishPluralCategories == ["one", "other"] {
                guard let variations = english["variations"] as? [String: Any],
                      let plural = variations["plural"] as? [String: Any],
                      Set(plural.keys) == Set(["one", "other"]),
                      let one = plural["one"] as? [String: Any],
                      let oneUnit = one["stringUnit"] as? [String: Any],
                      let oneValue = oneUnit["value"] as? String, !oneValue.isEmpty,
                      let other = plural["other"] as? [String: Any],
                      let unit = other["stringUnit"] as? [String: Any],
                      unit["value"] as? String == definition.englishDefaultValue else {
                    throw LocalizationContractFailureV1.invalidValue
                }
            } else {
                guard let unit = english["stringUnit"] as? [String: Any],
                      unit["value"] as? String == definition.englishDefaultValue else {
                    throw LocalizationContractFailureV1.invalidValue
                }
            }
        }
    }

    private static func definition(
        _ key: BundledLocalizationKeyV1, _ meaning: String, _ value: String,
        _ comment: String, arguments: [LocalizationArgumentV1] = [],
        plurals: [String] = []
    ) throws -> LocalizationKeyDefinitionV1 {
        LocalizationKeyDefinitionV1(
            key: try LocalizationKeyV1(key.rawValue), meaningID: meaning,
            translatorComment: comment, englishDefaultValue: value,
            arguments: arguments, requiredEnglishPluralCategories: plurals,
            state: .active, deprecatedFallbackKey: nil
        )
    }
}

extension FrozenDisplaySnapshotV1 {
    init(reportSnapshot: ReportSnapshotV1) throws {
        let encoded = try ReportSnapshotEncoderV1().encode(reportSnapshot)
        try self.init(canonicalBytes: encoded.data, sha256: encoded.sha256)
    }

    func validateUnchanged(reportSnapshot: ReportSnapshotV1) throws {
        let encoded = try ReportSnapshotEncoderV1().encode(reportSnapshot)
        try validateUnchanged(canonicalBytes: encoded.data, sha256: encoded.sha256)
    }
}
