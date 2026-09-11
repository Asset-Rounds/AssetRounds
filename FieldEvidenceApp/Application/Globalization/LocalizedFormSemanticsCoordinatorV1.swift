import Foundation

/// Resolves localized presentation only. Existing package facts, field
/// definitions, values, validation, units, and conditional rules remain the
/// canonical authority.
struct LocalizedFormSemanticsCoordinatorV1 {
    let formatter: LocaleFormattingServiceV1
    let bundle: Bundle
    let locale: Locale?

    init(
        profile: FormattingLocaleProfileV1,
        bundle: Bundle = .main,
        locale: Locale? = nil
    ) throws {
        formatter = try LocaleFormattingServiceV1(profile: profile)
        self.bundle = bundle
        self.locale = locale
    }

    /// Presents a fact that has no response-field definition, such as an
    /// instruction or repeatable-group heading. Package text is taken only
    /// from the exact archive bound to this release's localization digest.
    func project(
        release: SurveyDefinitionReleaseV1,
        fact: FactDefinitionV1,
        archive: V30CatalogReleaseArchiveV1
    ) throws -> LocalizedFormSemanticsProjectionV1 {
        try release.validate()
        guard release.sections.flatMap(\.facts).contains(fact) else {
            throw LocalizedFormSemanticsFailureV1.fieldFactMismatch
        }
        return try projection(
            fact: fact,
            archive: archive,
            release: release,
            requirement: nil
        )
    }

    /// Presents a response field only when its requirement and choice contract
    /// agrees exactly with the released fact. The canonical field validator is
    /// still called separately for response admission.
    func project(
        release: SurveyDefinitionReleaseV1,
        fact: FactDefinitionV1,
        field: ResponseFieldDefinitionV1,
        archive: V30CatalogReleaseArchiveV1
    ) throws -> LocalizedFormSemanticsProjectionV1 {
        try field.validateSurveyFact(fact)
        try validate(field: field, agreesWith: fact)
        try release.validate()
        guard release.sections.flatMap(\.facts).contains(fact) else {
            throw LocalizedFormSemanticsFailureV1.fieldFactMismatch
        }
        return try projection(
            fact: fact,
            archive: archive,
            release: release,
            requirement: requirementPresentation(for: fact)
        )
    }

    /// Calls the incumbent canonical validator. The returned wording is a
    /// localized presentation of its failure, never an alternate validation
    /// result or a statement that a response was stored.
    func validate(
        response: BoundResponseValueV1,
        against field: ResponseFieldDefinitionV1
    ) -> LocalizedFormValidationPresentationV1 {
        do {
            // Establish that a field contract is valid before interpreting a
            // cardinality failure as a missing user response.
            try field.validate()
        } catch let error as ResponseContractFailureV1 {
            return .init(
                isValid: false,
                error: error,
                messageKey: .invalidResponse,
                message: appText(.invalidResponse)
            )
        } catch {
            return .init(
                isValid: false,
                error: nil,
                messageKey: .invalidResponse,
                message: appText(.invalidResponse)
            )
        }

        do {
            try ResponseFieldValidatorV1.validate(response, against: field)
            return .init(isValid: true, error: nil, messageKey: nil, message: nil)
        } catch let error as ResponseContractFailureV1 {
            let key = messageKey(for: error, response: response, field: field)
            return .init(
                isValid: false,
                error: error,
                messageKey: key,
                message: appText(key)
            )
        } catch {
            // Do not recast an unknown incumbent failure as a canonical
            // ResponseContractFailureV1 case.
            return .init(
                isValid: false,
                error: nil,
                messageKey: .invalidResponse,
                message: appText(.invalidResponse)
            )
        }
    }

    /// Validates the complete incumbent release before presenting a condition
    /// failure, so malformed decoded data cannot reach its internal indexes.
    func validateConditions(
        in release: SurveyDefinitionReleaseV1
    ) -> LocalizedFormConditionValidationPresentationV1 {
        do {
            try release.validate()
            return .init(isValid: true, error: nil, messageKey: nil, message: nil)
        } catch let error as SurveyDefinitionFailureV1 {
            return .init(
                isValid: false,
                error: error,
                messageKey: .invalidCondition,
                message: appText(.invalidCondition)
            )
        } catch {
            return .init(
                isValid: false,
                error: nil,
                messageKey: .invalidCondition,
                message: appText(.invalidCondition)
            )
        }
    }

    func formatDecimal(_ value: Decimal) throws -> String {
        try formatter.formatDecimal(value)
    }

    /// The supplied canonical unit stays explicit. This method does not parse
    /// input or change the stored value/unit.
    func formatLength(
        _ value: Decimal,
        canonicalUnit: LocaleLengthUnitV1
    ) throws -> String {
        try formatter.formatLength(value, canonicalUnit: canonicalUnit)
    }

    private func projection(
        fact: FactDefinitionV1,
        archive: V30CatalogReleaseArchiveV1,
        release: SurveyDefinitionReleaseV1,
        requirement: LocalizedFormRequirementPresentationV1?
    ) throws -> LocalizedFormSemanticsProjectionV1 {
        .init(
            factID: fact.factID,
            label: try archiveText(
                for: fact.labelLocalizationKey,
                archive: archive,
                release: release
            ),
            accessibilityLabel: try archiveText(
                for: fact.accessibilityLabelLocalizationKey,
                archive: archive,
                release: release
            ),
            helpText: try fact.helpLocalizationKey.map {
                try archiveText(for: $0, archive: archive, release: release)
            },
            requirement: requirement,
            choices: try choicePresentations(
                payload: fact.payload,
                archive: archive,
                release: release
            ),
            visibility: fact.visibility
        )
    }
    private func requirementPresentation(
        for fact: FactDefinitionV1
    ) -> LocalizedFormRequirementPresentationV1 {
        let key: LocalizedFormSemanticsMessageKeyV1 = fact.required ? .required : .optional
        let state: LocalizedFormRequirementV1 = fact.required ? .required : .optional
        return .init(state: state, messageKey: key, text: appText(key))
    }

    private func appText(_ key: LocalizedFormSemanticsMessageKeyV1) -> String {
        BundledLocalizationCatalogV1.formSemanticsText(
            key,
            bundle: bundle,
            locale: locale
        )
    }

    /// Reads one simple English source message from the already validated
    /// archive. This is deliberately not a general `.xcstrings` resolver:
    /// plural, variation, substitution, or argument-bearing messages fail
    /// closed rather than being reinterpreted at this presentation boundary.
    private func archiveText(
        for key: String,
        archive: V30CatalogReleaseArchiveV1,
        release: SurveyDefinitionReleaseV1
    ) throws -> String {
        guard release.localizationReleaseSHA256
                == archive.descriptor.legacyRelease.releaseSHA256 else {
            throw LocalizedFormSemanticsFailureV1.catalogReleaseMismatch
        }
        let definitions = try archive.keyRegistry().definitions.filter {
            $0.key.rawValue == key
        }
        guard definitions.count == 1, let definition = definitions.first else {
            throw LocalizedFormSemanticsFailureV1.missingCatalogText
        }
        guard definition.arguments.isEmpty,
              definition.requiredEnglishPluralCategories.isEmpty else {
            throw LocalizedFormSemanticsFailureV1.unsupportedCatalogMessage
        }
        guard let object = try? JSONSerialization.jsonObject(with: archive.sourceCatalog),
              let root = object as? [String: Any],
              let strings = root["strings"] as? [String: Any],
              let entry = strings[key] as? [String: Any],
              let localizations = entry["localizations"] as? [String: Any],
              Set(localizations.keys) == Set(["en"]),
              let english = localizations["en"] as? [String: Any],
              let unit = english["stringUnit"] as? [String: Any],
              let value = unit["value"] as? String else {
            throw LocalizedFormSemanticsFailureV1.sourceCatalogMismatch
        }
        guard entry["substitutions"] == nil,
              entry["variations"] == nil,
              Set(english.keys) == Set(["stringUnit"]) else {
            throw LocalizedFormSemanticsFailureV1.unsupportedCatalogMessage
        }
        guard Data(value.utf8) == Data(definition.englishDefaultValue.utf8) else {
            // Swift String equality is canonically equivalent. Catalog source
            // provenance here requires the exact archived UTF-8 byte sequence.
            throw LocalizedFormSemanticsFailureV1.sourceCatalogMismatch
        }
        return value
    }
    private func validate(
        field: ResponseFieldDefinitionV1,
        agreesWith fact: FactDefinitionV1
    ) throws {
        guard fact.required == (field.cardinality.minimum > 0) else {
            throw LocalizedFormSemanticsFailureV1.requirementMismatch
        }
        let factChoiceIDs: [String]
        switch fact.payload {
        case .singleChoice(let choices):
            factChoiceIDs = choices.map(\.choiceID)
        case .multipleChoice(let choices, _, _):
            factChoiceIDs = choices.map(\.choiceID)
        default:
            factChoiceIDs = []
        }
        guard factChoiceIDs == field.allowedOptionIDs else {
            throw LocalizedFormSemanticsFailureV1.choiceMismatch
        }
    }


    private func choicePresentations(
        payload: SurveyFactPayloadV1,
        archive: V30CatalogReleaseArchiveV1,
        release: SurveyDefinitionReleaseV1
    ) throws -> [LocalizedFormChoicePresentationV1] {
        let choices: [SurveyChoiceV1]
        switch payload {
        case .singleChoice(let values):
            choices = values
        case .multipleChoice(let values, _, _):
            choices = values
        default:
            choices = []
        }
        return try choices.map { choice in
            .init(
                choiceID: choice.choiceID,
                label: try archiveText(
                    for: choice.labelLocalizationKey,
                    archive: archive,
                    release: release
                ),
                accessibilityLabel: try archiveText(
                    for: choice.accessibilityLabelLocalizationKey,
                    archive: archive,
                    release: release
                )
            )
        }
    }
    private func messageKey(
        for error: ResponseContractFailureV1,
        response: BoundResponseValueV1,
        field: ResponseFieldDefinitionV1
    ) -> LocalizedFormSemanticsMessageKeyV1 {
        switch error {
        case .cardinalityViolation where response.fieldID == field.fieldID
            && response.value == .noValue
            && field.cardinality.minimum > 0:
            return .missingRequiredResponse
        case .unsupportedUnit, .dimensionMismatch:
            return .invalidUnit
        case .rangeViolation, .precisionLoss, .arithmeticOverflow:
            return .invalidNumber
        case .invalidValue where response.fieldID == field.fieldID
            && (field.valueKind == .singleOption || field.valueKind == .multipleOptions):
            return .invalidSelection
        default:
            return .invalidResponse
        }
    }
}
