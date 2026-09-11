import Foundation

/// App-owned form semantics. Package-authored labels, instructions, and choice
/// text are read only from the exact validated catalog archive supplied to the
/// coordinator; they never enter this app-owned message catalog.
enum LocalizedFormSemanticsMessageKeyV1: String, CaseIterable, Sendable {
    case required = "v30.form-semantics.required"
    case optional = "v30.form-semantics.optional"
    case invalidResponse = "v30.form-semantics.invalid-response"
    case missingRequiredResponse = "v30.form-semantics.missing-required-response"
    case invalidSelection = "v30.form-semantics.invalid-selection"
    case invalidNumber = "v30.form-semantics.invalid-number"
    case invalidUnit = "v30.form-semantics.invalid-unit"
    case invalidCondition = "v30.form-semantics.invalid-condition"

    var localizationKey: LocalizationKeyV1 {
        // These are closed, repository-owned literals. The catalog registry
        // independently validates them before publishing a catalog release.
        try! LocalizationKeyV1(rawValue)
    }
}

enum LocalizedFormSemanticsFailureV1: Error, Equatable, Sendable {
    case fieldFactMismatch
    case requirementMismatch
    case choiceMismatch
    case catalogReleaseMismatch
    case duplicateCatalogKey
    case missingCatalogText
    case unsupportedCatalogMessage
    case sourceCatalogMismatch
}

enum LocalizedFormRequirementV1: String, Equatable, Sendable {
    case required = "REQUIRED"
    case optional = "OPTIONAL"
}

struct LocalizedFormRequirementPresentationV1: Equatable, Sendable {
    let state: LocalizedFormRequirementV1
    let messageKey: LocalizedFormSemanticsMessageKeyV1
    let text: String
}

struct LocalizedFormChoicePresentationV1: Equatable, Sendable {
    let choiceID: String
    let label: String
    let accessibilityLabel: String
}

/// A read-only presentation of one pre-existing form fact. `visibility` is the
/// unmodified canonical condition expression; presentation never evaluates,
/// reorders, or otherwise changes it.
struct LocalizedFormSemanticsProjectionV1: Equatable, Sendable {
    let factID: String
    let label: String
    let accessibilityLabel: String
    let helpText: String?
    /// Requirement wording exists only when a matching response-field contract is supplied.
    let requirement: LocalizedFormRequirementPresentationV1?
    let choices: [LocalizedFormChoicePresentationV1]
    let visibility: SurveyVisibilityExpressionV1?
}

struct LocalizedFormValidationPresentationV1: Equatable, Sendable {
    let isValid: Bool
    let error: ResponseContractFailureV1?
    let messageKey: LocalizedFormSemanticsMessageKeyV1?
    let message: String?
}

struct LocalizedFormConditionValidationPresentationV1: Equatable, Sendable {
    let isValid: Bool
    let error: SurveyDefinitionFailureV1?
    let messageKey: LocalizedFormSemanticsMessageKeyV1?
    let message: String?
}