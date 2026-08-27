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
    case accountabilityHeading = "accountability.heading"
    case accountabilityParty = "accountability.party"
    case accountabilityRole = "accountability.role"
    case accountabilityActor = "accountability.actor"
    case accountabilityQualification = "accountability.qualification"
    case accountabilitySignoff = "accountability.signoff"
    case assetSemanticIlluminatedSignName = "asset.semantic.sign.illuminated.name"
    case assetSemanticIlluminatedSignDescription = "asset.semantic.sign.illuminated.description"
    case assetSemanticHeading = "asset.semantic.heading"
    case assetSemanticKind = "asset.semantic.kind"
    case assetSemanticProductIdentity = "asset.semantic.product_identity"
    case assetSemanticWorkSubjectScope = "asset.semantic.work_subject_scope"
    case assetSemanticLifecycle = "asset.semantic.lifecycle"
    case assetSemanticState = "asset.semantic.state"
    case assetSemanticUnknownState = "asset.semantic.state.unknown"
    case assetSemanticDuplicateState = "asset.semantic.state.duplicate"
    case assetSemanticRetiredState = "asset.semantic.state.retired"
    case assetSemanticReplacedState = "asset.semantic.state.replaced"
    case assetSemanticRecordedState = "asset.semantic.state.recorded"
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

    /// C38's additive key surface.  The legacy `registry()` remains frozen so
    /// S8.4 mail callers retain their exact V1 key/ID contract.
    static func accountabilityRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try registry()
        let additions = [
            try definition(
                .accountabilityHeading, "report.accountability.heading", "Accountability",
                "Heading for the localized accountability projection in a report."
            ),
            try definition(
                .accountabilityParty, "report.accountability.party", "Party",
                "Localized label for a service party in the accountability projection."
            ),
            try definition(
                .accountabilityRole, "report.accountability.role", "Site role",
                "Localized label for a historical site role event."
            ),
            try definition(
                .accountabilityActor, "report.accountability.actor", "Responsible actor",
                "Localized label for a locally captured responsible actor."
            ),
            try definition(
                .accountabilityQualification, "report.accountability.qualification", "Declared qualification",
                "Localized label for a declared qualification snapshot."
            ),
            try definition(
                .accountabilitySignoff, "report.accountability.signoff", "Local response",
                "Localized label for a local signoff assertion or disposition."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
    }

    /// C39's additive key surface.  The C16 and C38 registries remain
    /// available as frozen compatibility projections; this registry is the
    /// first one that exposes semantic kind, product, lifecycle, and subject
    /// scope labels.
    static func assetSemanticRegistry() throws -> LocalizationKeyRegistryV1 {
        let base = try accountabilityRegistry()
        let additions = [
            try definition(
                .assetSemanticIlluminatedSignName, "asset.semantic.sign.illuminated.name", "Illuminated sign",
                "Localized name for the bundled illuminated-sign semantic kind."
            ),
            try definition(
                .assetSemanticIlluminatedSignDescription, "asset.semantic.sign.illuminated.description",
                "Illuminated sign semantic kind",
                "Localized description for the bundled illuminated-sign semantic kind."
            ),
            try definition(
                .assetSemanticHeading, "asset.semantic.heading", "Asset semantics",
                "Heading for the local asset semantic and lifecycle projection."
            ),
            try definition(
                .assetSemanticKind, "asset.semantic.kind", "Semantic kind",
                "Localized label for an accepted asset semantic kind."
            ),
            try definition(
                .assetSemanticProductIdentity, "asset.semantic.product_identity", "Product identity",
                "Localized label for progressively disclosed product identifier attributes."
            ),
            try definition(
                .assetSemanticWorkSubjectScope, "asset.semantic.work_subject_scope", "Work subject scope",
                "Localized label for the immutable subject scope captured by completed work."
            ),
            try definition(
                .assetSemanticLifecycle, "asset.semantic.lifecycle", "Lifecycle",
                "Localized label for a human-recorded asset lifecycle history."
            ),
            try definition(
                .assetSemanticState, "asset.semantic.state", "Recorded state",
                "Accessible label for an asset semantic state without operational claims."
            ),
            try definition(
                .assetSemanticUnknownState, "asset.semantic.state.unknown", "Unknown",
                "Accessible text for an unknown or not-recorded semantic value."
            ),
            try definition(
                .assetSemanticDuplicateState, "asset.semantic.state.duplicate", "Duplicate value",
                "Accessible text for a duplicate product identifier value."
            ),
            try definition(
                .assetSemanticRetiredState, "asset.semantic.state.retired", "Retired",
                "Accessible text for a human-recorded retired lifecycle event."
            ),
            try definition(
                .assetSemanticReplacedState, "asset.semantic.state.replaced", "Replaced",
                "Accessible text for a human-recorded replaced lifecycle event."
            ),
            try definition(
                .assetSemanticRecordedState, "asset.semantic.state.recorded", "Recorded",
                "Accessible text for a fact explicitly recorded by a local actor."
            ),
        ]
        return try LocalizationKeyRegistryV1(definitions: base.definitions + additions)
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

    static func accountabilityAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try accessibilityRegistry(localization: localization)
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: "accountability.party", role: .group,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityParty.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.site-role", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityRole.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.actor", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityActor.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.qualification", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilityQualification.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff.disclosure", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: "accountability.signoff.history", role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.accountabilitySignoff.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func assetSemanticAccessibilityRegistry(
        localization: LocalizationKeyRegistryV1
    ) throws -> SemanticAccessibilityIDRegistryV1 {
        let base = try accountabilityAccessibilityRegistry(localization: localization)
        let entries: [AccessibilityContractV1] = [
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.screen.rawValue, role: .screen,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticHeading.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.heading.rawValue, role: .heading,
                reachability: .always,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticHeading.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.kind.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticKind.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.productIdentity.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticProductIdentity.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.lifecycle.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticLifecycle.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.workSubjectScope.rawValue, role: .group,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticWorkSubjectScope.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.state.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.unknownState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticUnknownState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.duplicateState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticDuplicateState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.retiredState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticRetiredState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.replacedState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticReplacedState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
            AccessibilityContractV1(
                semanticID: AssetSemanticAccessibilityIDV1.recordedState.rawValue, role: .status,
                reachability: .whenAvailable,
                labelKey: try LocalizationKeyV1(BundledLocalizationKeyV1.assetSemanticRecordedState.rawValue),
                hintKey: nil, valueKey: nil, dynamicSuffixPolicy: .none,
                deprecatedAliases: []
            ),
        ]
        return try base.appending(entries, localization: localization)
    }

    static func publish(
        sourceCatalogBytes: Data,
        packagePublications: [InspectionPackagePublishedReleaseV1] = [],
        legacy: LegacyLocalizationAccessibilityAllowlistV1,
        previousRegistry: LocalizationKeyRegistryV1? = nil,
        previousLegacy: LegacyLocalizationAccessibilityAllowlistV1? = nil,
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false,
        interruption: Interruption = { _ in }
    ) throws -> LocalizationCatalogPublicationV1 {
        try interruption(.beforeValidation)
        try legacy.validate()
        let locales = LocalizationLocaleManifestV1.shippingV1()
        try locales.validate()
        let keys: LocalizationKeyRegistryV1
        if includeAssetSemantics {
            keys = try assetSemanticRegistry()
        } else if includeAccountability {
            keys = try accountabilityRegistry()
        } else {
            keys = try registry()
        }
        try validateSourceCatalog(sourceCatalogBytes, registry: keys)
        if let previousRegistry { try keys.validateSuccessor(of: previousRegistry) }
        let requiredMailLegacy = try mailLegacyAllowlist()
        guard legacy == requiredMailLegacy else {
            throw LocalizationContractFailureV1.legacyAllowlistGrowth
        }
        if let previousLegacy { try previousLegacy.validateObserved(legacy.entries) }
        let accessibility: SemanticAccessibilityIDRegistryV1
        if includeAssetSemantics {
            accessibility = try assetSemanticAccessibilityRegistry(localization: keys)
        } else if includeAccountability {
            accessibility = try accountabilityAccessibilityRegistry(localization: keys)
        } else {
            accessibility = try accessibilityRegistry(localization: keys)
        }
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
        packagePublications: [InspectionPackagePublishedReleaseV1] = [],
        includeAccountability: Bool = false,
        includeAssetSemantics: Bool = false
    ) throws -> LocalizationCatalogPublicationV1 {
        switch (sourceCatalogBytes, receipt) {
        case (nil, nil): return .zero
        case let (.some(bytes), .some(expected)):
            let publication = try publish(
                sourceCatalogBytes: bytes,
                packagePublications: packagePublications,
                legacy: legacy,
                includeAccountability: includeAccountability,
                includeAssetSemantics: includeAssetSemantics
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
        case .accountabilityHeading:
            return String(localized: "accountability.heading", defaultValue: "Accountability", bundle: bundle, locale: locale, comment: "Heading for the localized accountability projection in a report.")
        case .accountabilityParty:
            return String(localized: "accountability.party", defaultValue: "Party", bundle: bundle, locale: locale, comment: "Localized label for a service party in the accountability projection.")
        case .accountabilityRole:
            return String(localized: "accountability.role", defaultValue: "Site role", bundle: bundle, locale: locale, comment: "Localized label for a historical site role event.")
        case .accountabilityActor:
            return String(localized: "accountability.actor", defaultValue: "Responsible actor", bundle: bundle, locale: locale, comment: "Localized label for a locally captured responsible actor.")
        case .accountabilityQualification:
            return String(localized: "accountability.qualification", defaultValue: "Declared qualification", bundle: bundle, locale: locale, comment: "Localized label for a declared qualification snapshot.")
        case .accountabilitySignoff:
            return String(localized: "accountability.signoff", defaultValue: "Local response", bundle: bundle, locale: locale, comment: "Localized label for a local signoff assertion or disposition.")
        case .assetSemanticIlluminatedSignName:
            return String(localized: "asset.semantic.sign.illuminated.name", defaultValue: "Illuminated sign", bundle: bundle, locale: locale, comment: "Localized name for the bundled illuminated-sign semantic kind.")
        case .assetSemanticIlluminatedSignDescription:
            return String(localized: "asset.semantic.sign.illuminated.description", defaultValue: "Illuminated sign semantic kind", bundle: bundle, locale: locale, comment: "Localized description for the bundled illuminated-sign semantic kind.")
        case .assetSemanticHeading:
            return String(localized: "asset.semantic.heading", defaultValue: "Asset semantics", bundle: bundle, locale: locale, comment: "Heading for the local asset semantic and lifecycle projection.")
        case .assetSemanticKind:
            return String(localized: "asset.semantic.kind", defaultValue: "Semantic kind", bundle: bundle, locale: locale, comment: "Localized label for an accepted asset semantic kind.")
        case .assetSemanticProductIdentity:
            return String(localized: "asset.semantic.product_identity", defaultValue: "Product identity", bundle: bundle, locale: locale, comment: "Localized label for progressively disclosed product identifier attributes.")
        case .assetSemanticWorkSubjectScope:
            return String(localized: "asset.semantic.work_subject_scope", defaultValue: "Work subject scope", bundle: bundle, locale: locale, comment: "Localized label for the immutable subject scope captured by completed work.")
        case .assetSemanticLifecycle:
            return String(localized: "asset.semantic.lifecycle", defaultValue: "Lifecycle", bundle: bundle, locale: locale, comment: "Localized label for a human-recorded asset lifecycle history.")
        case .assetSemanticState:
            return String(localized: "asset.semantic.state", defaultValue: "Recorded state", bundle: bundle, locale: locale, comment: "Accessible label for an asset semantic state without operational claims.")
        case .assetSemanticUnknownState:
            return String(localized: "asset.semantic.state.unknown", defaultValue: "Unknown", bundle: bundle, locale: locale, comment: "Accessible text for an unknown or not-recorded semantic value.")
        case .assetSemanticDuplicateState:
            return String(localized: "asset.semantic.state.duplicate", defaultValue: "Duplicate value", bundle: bundle, locale: locale, comment: "Accessible text for a duplicate product identifier value.")
        case .assetSemanticRetiredState:
            return String(localized: "asset.semantic.state.retired", defaultValue: "Retired", bundle: bundle, locale: locale, comment: "Accessible text for a human-recorded retired lifecycle event.")
        case .assetSemanticReplacedState:
            return String(localized: "asset.semantic.state.replaced", defaultValue: "Replaced", bundle: bundle, locale: locale, comment: "Accessible text for a human-recorded replaced lifecycle event.")
        case .assetSemanticRecordedState:
            return String(localized: "asset.semantic.state.recorded", defaultValue: "Recorded", bundle: bundle, locale: locale, comment: "Accessible text for a fact explicitly recorded by a local actor.")
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
              let strings = root["strings"] as? [String: Any] else {
            throw LocalizationContractFailureV1.invalidValue
        }
        let registeredKeys = Set(registry.definitions.map(\.key.rawValue))
        // The source catalog may be validated against any currently declared
        // additive projection, while the selected registry still controls the
        // required subset.  This keeps C16/C38 compatibility callers frozen
        // and lets the C39 typed surface publish atomically.
        let supportedKeys = Set((try? assetSemanticRegistry())?.definitions.map(\.key.rawValue) ?? [])
        guard registeredKeys.isSubset(of: Set(strings.keys)),
              Set(strings.keys).isSubset(of: supportedKeys) else {
            throw LocalizationContractFailureV1.invalidValue
        }
        for definition in registry.definitions {
            let rawKey = definition.key.rawValue
            guard let rawEntry = strings[rawKey],
                  let entry = rawEntry as? [String: Any],
                  let comment = entry["comment"] as? String,
                  !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let localizations = entry["localizations"] as? [String: Any],
                  Set(localizations.keys) == Set(["en"]),
                  (try? registry.definition(for: LocalizationKeyV1(rawKey))) != nil else {
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
