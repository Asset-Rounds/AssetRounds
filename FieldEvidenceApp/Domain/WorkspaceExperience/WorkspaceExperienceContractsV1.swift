import Foundation

enum WorkspaceExperienceFailureV1: Error, Equatable, Sendable {
    case incompatibleVersion
    case invalidValue
    case invalidDigest
    case wrongWorkspace
    case duplicateIdentity
    case unorderedValue
    case staleRevision
    case practiceOnly
    case realWorkspaceRequired
    case permissionRequired
    case automaticInstallForbidden
    case customerContentForbidden
    case unsupportedAction
}

enum WorkspaceExperienceLimitsV1 {
    static let maximumTextBytes = 512
    static let maximumBodyBytes = 8_192
    static let maximumItems = 256
    static let maximumTags = 32
    static let maximumActionCount = 8
}

private enum WorkspaceExperienceValidationV1 {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    static func id(_ value: UUID) throws {
        guard value != zero else { throw WorkspaceExperienceFailureV1.invalidValue }
    }

    static func text(_ value: String, maximumBytes: Int = WorkspaceExperienceLimitsV1.maximumTextBytes) throws {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.utf8.count <= maximumBytes else { throw WorkspaceExperienceFailureV1.invalidValue }
    }

    static func digest(_ value: String) throws {
        guard KernelCanonicalHashV1.validSHA256(value) else { throw WorkspaceExperienceFailureV1.invalidDigest }
    }

    static func instant(_ value: Date) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else { throw WorkspaceExperienceFailureV1.invalidValue }
    }

    static func sortedUnique<T: Comparable & Hashable>(_ values: [T], maximum: Int = WorkspaceExperienceLimitsV1.maximumItems) throws {
        guard values.count <= maximum, values == values.sorted(), Set(values).count == values.count else {
            throw WorkspaceExperienceFailureV1.unorderedValue
        }
    }
}

enum WorkspaceExperienceCanonicalCodecV1 {
    static func data<T: Encodable>(_ value: T) throws -> Data { try WorkspaceMutationCanonicalV1.data(value) }
    static func sha256<T: Encodable>(_ value: T) throws -> String { try WorkspaceMutationCanonicalV1.sha256(value) }

    static func decode<T: Codable>(_ type: T.Type, from data: Data, validate: (T) throws -> Void) throws -> T {
        let value = try JSONDecoder().decode(type, from: data)
        try validate(value)
        guard try self.data(value) == data else { throw WorkspaceExperienceFailureV1.invalidDigest }
        return value
    }
}

enum WorkspaceExperienceRootV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable {
    case today = "TODAY"
    case work = "WORK"
    case assets = "ASSETS"
    case reports = "REPORTS"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    static let canonicalShellOrder: [Self] = [.today, .work, .assets, .reports]
}

enum WorkspaceExperienceSearchScopeV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable {
    case all = "ALL"
    case assets = "ASSETS"
    case locations = "LOCATIONS"
    case work = "WORK"
    case reports = "REPORTS"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    static let canonicalOrder: [Self] = [.all, .assets, .locations, .work, .reports]
}

enum WorkspaceExperienceAvailabilityReasonV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable {
    case available = "AVAILABLE"
    case disabledByPolicy = "DISABLED_BY_POLICY"
    case appLocked = "APP_LOCKED"
    case protectedDataUnavailable = "PROTECTED_DATA_UNAVAILABLE"
    case realWorkspaceRequired = "REAL_WORKSPACE_REQUIRED"
    case practiceWorkspaceRequired = "PRACTICE_WORKSPACE_REQUIRED"
    case sourceUnavailable = "SOURCE_UNAVAILABLE"
    case staleSource = "STALE_SOURCE"
    case permissionNotGranted = "PERMISSION_NOT_GRANTED"
    case unsupported = "UNSUPPORTED"
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum WorkspaceExperienceAvailabilityNextActionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case none = "NONE"
    case enableSetting = "ENABLE_SETTING"
    case unlockApp = "UNLOCK_APP"
    case unlockProtectedData = "UNLOCK_PROTECTED_DATA"
    case selectRealWorkspace = "SELECT_REAL_WORKSPACE"
    case selectPracticeWorkspace = "SELECT_PRACTICE_WORKSPACE"
    case restoreSource = "RESTORE_SOURCE"
    case refreshSource = "REFRESH_SOURCE"
    case grantPermission = "GRANT_PERMISSION"
}

struct FeatureAvailabilityPresentationV1: Codable, Equatable, Hashable, Sendable {
    let featureKey: String
    let isAvailable: Bool
    let reason: WorkspaceExperienceAvailabilityReasonV1
    let nextAction: WorkspaceExperienceAvailabilityNextActionV1
    let explanationKey: String

    init(featureKey: String, isAvailable: Bool, reason: WorkspaceExperienceAvailabilityReasonV1, explanationKey: String) throws {
        try WorkspaceExperienceValidationV1.text(featureKey)
        try WorkspaceExperienceValidationV1.text(explanationKey)
        guard isAvailable == (reason == .available) else { throw WorkspaceExperienceFailureV1.invalidValue }
        let action: WorkspaceExperienceAvailabilityNextActionV1
        switch reason {
        case .available, .unsupported: action = .none
        case .disabledByPolicy: action = .enableSetting
        case .appLocked: action = .unlockApp
        case .protectedDataUnavailable: action = .unlockProtectedData
        case .realWorkspaceRequired: action = .selectRealWorkspace
        case .practiceWorkspaceRequired: action = .selectPracticeWorkspace
        case .sourceUnavailable: action = .restoreSource
        case .staleSource: action = .refreshSource
        case .permissionNotGranted: action = .grantPermission
        }
        self.featureKey = featureKey; self.isAvailable = isAvailable; self.reason = reason
        nextAction = action; self.explanationKey = explanationKey
        try validate()
    }

    func validate() throws {
        try WorkspaceExperienceValidationV1.text(featureKey)
        try WorkspaceExperienceValidationV1.text(explanationKey)
        let expected = try Self(
            featureKey: featureKey,
            isAvailable: isAvailable,
            reason: reason,
            explanationKey: explanationKey,
            validatingRecursion: false
        )
        guard nextAction == expected.nextAction else { throw WorkspaceExperienceFailureV1.invalidValue }
    }

    private init(featureKey: String, isAvailable: Bool, reason: WorkspaceExperienceAvailabilityReasonV1, explanationKey: String, validatingRecursion: Bool) throws {
        guard !validatingRecursion, isAvailable == (reason == .available) else { throw WorkspaceExperienceFailureV1.invalidValue }
        self.featureKey = featureKey; self.isAvailable = isAvailable; self.reason = reason; self.explanationKey = explanationKey
        switch reason {
        case .available, .unsupported: nextAction = .none
        case .disabledByPolicy: nextAction = .enableSetting
        case .appLocked: nextAction = .unlockApp
        case .protectedDataUnavailable: nextAction = .unlockProtectedData
        case .realWorkspaceRequired: nextAction = .selectRealWorkspace
        case .practiceWorkspaceRequired: nextAction = .selectPracticeWorkspace
        case .sourceUnavailable: nextAction = .restoreSource
        case .staleSource: nextAction = .refreshSource
        case .permissionNotGranted: nextAction = .grantPermission
        }
    }
}

struct SettingsProjectionV1: Codable, Equatable, Hashable, Sendable {
    let schemaVersion: Int
    let workspaceID: WorkspaceID?
    let deviceLocalAppLockEnabled: Bool
    let activeWorkspaceSelection: ActiveWorkspaceSelectionV1?
    let availability: [FeatureAvailabilityPresentationV1]
    static let currentSchemaVersion = 1

    init(workspaceID: WorkspaceID?, deviceLocalAppLockEnabled: Bool, activeWorkspaceSelection: ActiveWorkspaceSelectionV1?, availability: [FeatureAvailabilityPresentationV1]) throws {
        schemaVersion = Self.currentSchemaVersion
        self.workspaceID = workspaceID; self.deviceLocalAppLockEnabled = deviceLocalAppLockEnabled
        self.activeWorkspaceSelection = activeWorkspaceSelection
        self.availability = availability.sorted { $0.featureKey < $1.featureKey }
        try validate()
    }

    func validate() throws {
        try activeWorkspaceSelection?.validate()
        try availability.forEach { try $0.validate() }
        guard schemaVersion == Self.currentSchemaVersion,
              activeWorkspaceSelection?.workspaceID == workspaceID,
              availability.count <= WorkspaceExperienceLimitsV1.maximumItems,
              availability == availability.sorted(by: { $0.featureKey < $1.featureKey }),
              Set(availability.map(\.featureKey)).count == availability.count else { throw WorkspaceExperienceFailureV1.invalidValue }
    }
}

enum WorkspaceExperienceWorkspaceKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case real = "REAL"
    case practice = "PRACTICE"
}

enum WorkspaceExperienceDeviceLocalDispositionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case deviceLocalNotBackedUp = "DEVICE_LOCAL_NOT_BACKED_UP"
}

struct StarterWorkspaceTemplateReleaseV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let templateID: UUID
    let release: UInt64
    let titleKey: String
    let workspaceKind: WorkspaceExperienceWorkspaceKindV1
    let packageReleaseIDs: [String]
    let roots: [WorkspaceExperienceRootV1]
    let searchScopes: [WorkspaceExperienceSearchScopeV1]
    let syntheticOnly: Bool
    let offlineCapable: Bool
    let requiresPermission: Bool
    let practiceWatermark: String
    let templateSHA256: String

    init(templateID: UUID, release: UInt64, titleKey: String, workspaceKind: WorkspaceExperienceWorkspaceKindV1 = .practice, packageReleaseIDs: [String], roots: [WorkspaceExperienceRootV1] = WorkspaceExperienceRootV1.canonicalShellOrder, searchScopes: [WorkspaceExperienceSearchScopeV1] = WorkspaceExperienceSearchScopeV1.canonicalOrder, syntheticOnly: Bool = true, offlineCapable: Bool = true, requiresPermission: Bool = false, practiceWatermark: String) throws {
        schemaVersion = Self.schemaVersion; self.templateID = templateID; self.release = release; self.titleKey = titleKey
        self.workspaceKind = workspaceKind; self.packageReleaseIDs = packageReleaseIDs.sorted(); self.roots = roots
        self.searchScopes = searchScopes; self.syntheticOnly = syntheticOnly; self.offlineCapable = offlineCapable
        self.requiresPermission = requiresPermission; self.practiceWatermark = practiceWatermark
        templateSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, templateID: templateID, release: release, titleKey: titleKey, workspaceKind: workspaceKind, packageReleaseIDs: packageReleaseIDs.sorted(), roots: roots, searchScopes: searchScopes, syntheticOnly: syntheticOnly, offlineCapable: offlineCapable, requiresPermission: requiresPermission, practiceWatermark: practiceWatermark))
        try validate()
    }

    func validate() throws {
        try WorkspaceExperienceValidationV1.id(templateID); try WorkspaceExperienceValidationV1.text(titleKey)
        try WorkspaceExperienceValidationV1.text(practiceWatermark, maximumBytes: 128); try WorkspaceExperienceValidationV1.digest(templateSHA256)
        try packageReleaseIDs.forEach { try WorkspaceExperienceValidationV1.text($0) }
        guard schemaVersion == Self.schemaVersion, release > 0, workspaceKind == .practice,
              packageReleaseIDs == packageReleaseIDs.sorted(), Set(packageReleaseIDs).count == packageReleaseIDs.count,
              roots == WorkspaceExperienceRootV1.canonicalShellOrder,
              searchScopes == WorkspaceExperienceSearchScopeV1.canonicalOrder,
              syntheticOnly, offlineCapable, !requiresPermission,
              practiceWatermark == "PRACTICE — NOT FOR FIELD USE",
              templateSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.invalidValue }
    }

    private var basis: Basis { .init(schemaVersion: schemaVersion, templateID: templateID, release: release, titleKey: titleKey, workspaceKind: workspaceKind, packageReleaseIDs: packageReleaseIDs, roots: roots, searchScopes: searchScopes, syntheticOnly: syntheticOnly, offlineCapable: offlineCapable, requiresPermission: requiresPermission, practiceWatermark: practiceWatermark) }
    private struct Basis: Codable { let schemaVersion: Int; let templateID: UUID; let release: UInt64; let titleKey: String; let workspaceKind: WorkspaceExperienceWorkspaceKindV1; let packageReleaseIDs: [String]; let roots: [WorkspaceExperienceRootV1]; let searchScopes: [WorkspaceExperienceSearchScopeV1]; let syntheticOnly: Bool; let offlineCapable: Bool; let requiresPermission: Bool; let practiceWatermark: String }
}

struct StarterWorkspaceInstallPlanV1: Codable, Equatable, Hashable, Sendable {
    let planID: UUID
    let workspaceID: WorkspaceID
    let templateID: UUID
    let templateRelease: UInt64
    let templateSHA256: String
    let mutationID: MutationIDV1
    let requestedAt: Date
    let explicitUserRequest: Bool
    let destinationWasEmpty: Bool
    let planSHA256: String

    init(planID: UUID, workspaceID: WorkspaceID, template: StarterWorkspaceTemplateReleaseV1, mutationID: MutationIDV1, requestedAt: Date, explicitUserRequest: Bool, destinationWasEmpty: Bool) throws {
        self.planID = planID; self.workspaceID = workspaceID; templateID = template.templateID; templateRelease = template.release
        templateSHA256 = template.templateSHA256; self.mutationID = mutationID; self.requestedAt = requestedAt
        self.explicitUserRequest = explicitUserRequest; self.destinationWasEmpty = destinationWasEmpty
        planSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(planID: planID, workspaceID: workspaceID, templateID: template.templateID, templateRelease: template.release, templateSHA256: template.templateSHA256, mutationID: mutationID, requestedAt: requestedAt, explicitUserRequest: explicitUserRequest, destinationWasEmpty: destinationWasEmpty))
        try validate(template: template)
    }

    func validate() throws {
        try WorkspaceExperienceValidationV1.id(planID); try WorkspaceExperienceValidationV1.id(workspaceID.rawValue)
        try WorkspaceExperienceValidationV1.id(templateID); try WorkspaceExperienceValidationV1.instant(requestedAt)
        try WorkspaceExperienceValidationV1.digest(templateSHA256); try WorkspaceExperienceValidationV1.digest(planSHA256)
        guard templateRelease > 0, explicitUserRequest, destinationWasEmpty,
              planSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.automaticInstallForbidden }
    }

    func validate(template: StarterWorkspaceTemplateReleaseV1) throws {
        try validate(); try template.validate()
        guard templateID == template.templateID, templateRelease == template.release, templateSHA256 == template.templateSHA256 else { throw WorkspaceExperienceFailureV1.staleRevision }
    }
    private var basis: Basis { .init(planID: planID, workspaceID: workspaceID, templateID: templateID, templateRelease: templateRelease, templateSHA256: templateSHA256, mutationID: mutationID, requestedAt: requestedAt, explicitUserRequest: explicitUserRequest, destinationWasEmpty: destinationWasEmpty) }
    private struct Basis: Codable { let planID: UUID; let workspaceID: WorkspaceID; let templateID: UUID; let templateRelease: UInt64; let templateSHA256: String; let mutationID: MutationIDV1; let requestedAt: Date; let explicitUserRequest: Bool; let destinationWasEmpty: Bool }
}

struct StarterWorkspaceInstallReceiptV1: Codable, Equatable, Hashable, Sendable {
    let receiptID: UUID; let workspaceID: WorkspaceID; let planID: UUID; let planSHA256: String
    let resultingWorkspaceRevision: UInt64; let mutationID: MutationIDV1; let installedAt: Date
    let disposition: WorkspaceExperienceInstallDispositionV1; let receiptSHA256: String

    init(receiptID: UUID, plan: StarterWorkspaceInstallPlanV1, resultingWorkspaceRevision: UInt64, installedAt: Date, disposition: WorkspaceExperienceInstallDispositionV1) throws {
        self.receiptID = receiptID; workspaceID = plan.workspaceID; planID = plan.planID; planSHA256 = plan.planSHA256
        self.resultingWorkspaceRevision = resultingWorkspaceRevision; mutationID = plan.mutationID; self.installedAt = installedAt; self.disposition = disposition
        receiptSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(receiptID: receiptID, workspaceID: plan.workspaceID, planID: plan.planID, planSHA256: plan.planSHA256, resultingWorkspaceRevision: resultingWorkspaceRevision, mutationID: plan.mutationID, installedAt: installedAt, disposition: disposition))
        try validate(plan: plan)
    }

    func validate() throws {
        try WorkspaceExperienceValidationV1.id(receiptID); try WorkspaceExperienceValidationV1.id(workspaceID.rawValue)
        try WorkspaceExperienceValidationV1.id(planID); try WorkspaceExperienceValidationV1.digest(planSHA256)
        try WorkspaceExperienceValidationV1.instant(installedAt); try WorkspaceExperienceValidationV1.digest(receiptSHA256)
        guard resultingWorkspaceRevision > 0,
              receiptSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.invalidDigest }
    }
    func validate(plan: StarterWorkspaceInstallPlanV1) throws { try validate(); try plan.validate(); guard workspaceID == plan.workspaceID, planID == plan.planID, planSHA256 == plan.planSHA256, mutationID == plan.mutationID else { throw WorkspaceExperienceFailureV1.invalidValue } }
    private var basis: Basis { .init(receiptID: receiptID, workspaceID: workspaceID, planID: planID, planSHA256: planSHA256, resultingWorkspaceRevision: resultingWorkspaceRevision, mutationID: mutationID, installedAt: installedAt, disposition: disposition) }
    private struct Basis: Codable { let receiptID: UUID; let workspaceID: WorkspaceID; let planID: UUID; let planSHA256: String; let resultingWorkspaceRevision: UInt64; let mutationID: MutationIDV1; let installedAt: Date; let disposition: WorkspaceExperienceInstallDispositionV1 }
}

enum WorkspaceExperienceInstallDispositionV1: String, CaseIterable, Codable, Hashable, Sendable { case committed = "COMMITTED"; case idempotentReplay = "IDEMPOTENT_REPLAY" }

struct PracticeWorkspaceProvenanceV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int; let provenanceID: UUID; let workspaceID: WorkspaceID
    let templateID: UUID; let templateRelease: UInt64; let templateSHA256: String
    let installReceiptID: UUID; let installReceiptSHA256: String; let revision: UInt64
    let mutationID: MutationIDV1; let installedAt: Date; let provenanceSHA256: String

    init(provenanceID: UUID, plan: StarterWorkspaceInstallPlanV1, receipt: StarterWorkspaceInstallReceiptV1, revision: UInt64) throws {
        schemaVersion = Self.schemaVersion; self.provenanceID = provenanceID; workspaceID = plan.workspaceID
        templateID = plan.templateID; templateRelease = plan.templateRelease; templateSHA256 = plan.templateSHA256
        installReceiptID = receipt.receiptID; installReceiptSHA256 = receipt.receiptSHA256; self.revision = revision
        mutationID = plan.mutationID; installedAt = receipt.installedAt
        provenanceSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, provenanceID: provenanceID, workspaceID: plan.workspaceID, templateID: plan.templateID, templateRelease: plan.templateRelease, templateSHA256: plan.templateSHA256, installReceiptID: receipt.receiptID, installReceiptSHA256: receipt.receiptSHA256, revision: revision, mutationID: plan.mutationID, installedAt: receipt.installedAt))
        try validate(plan: plan, receipt: receipt)
    }

    func validate() throws {
        try WorkspaceExperienceValidationV1.id(provenanceID); try WorkspaceExperienceValidationV1.id(workspaceID.rawValue)
        try WorkspaceExperienceValidationV1.id(templateID); try WorkspaceExperienceValidationV1.id(installReceiptID)
        try WorkspaceExperienceValidationV1.digest(templateSHA256); try WorkspaceExperienceValidationV1.digest(installReceiptSHA256)
        try WorkspaceExperienceValidationV1.digest(provenanceSHA256); try WorkspaceExperienceValidationV1.instant(installedAt)
        guard schemaVersion == Self.schemaVersion, templateRelease > 0, revision == 1,
              provenanceSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.invalidValue }
    }
    func validate(plan: StarterWorkspaceInstallPlanV1, receipt: StarterWorkspaceInstallReceiptV1) throws { try validate(); try receipt.validate(plan: plan); guard workspaceID == plan.workspaceID, templateID == plan.templateID, templateRelease == plan.templateRelease, templateSHA256 == plan.templateSHA256, installReceiptID == receipt.receiptID, installReceiptSHA256 == receipt.receiptSHA256, mutationID == plan.mutationID, installedAt == receipt.installedAt else { throw WorkspaceExperienceFailureV1.invalidValue } }
    private var basis: Basis { .init(schemaVersion: schemaVersion, provenanceID: provenanceID, workspaceID: workspaceID, templateID: templateID, templateRelease: templateRelease, templateSHA256: templateSHA256, installReceiptID: installReceiptID, installReceiptSHA256: installReceiptSHA256, revision: revision, mutationID: mutationID, installedAt: installedAt) }
    private struct Basis: Codable { let schemaVersion: Int; let provenanceID: UUID; let workspaceID: WorkspaceID; let templateID: UUID; let templateRelease: UInt64; let templateSHA256: String; let installReceiptID: UUID; let installReceiptSHA256: String; let revision: UInt64; let mutationID: MutationIDV1; let installedAt: Date }
}

enum WorkspaceExperienceClassificationV1 {
    static func kind(provenance: PracticeWorkspaceProvenanceV1?) throws -> WorkspaceExperienceWorkspaceKindV1 {
        try provenance?.validate()
        return provenance == nil ? .real : .practice
    }
}

struct PracticeWorkspaceResetPlanV1: Codable, Equatable, Hashable, Sendable {
    let planID: UUID; let workspaceID: WorkspaceID; let provenanceID: UUID; let provenanceSHA256: String
    let expectedWorkspaceRevision: UInt64; let mutationID: MutationIDV1; let requestedAt: Date
    let explicitUserRequest: Bool; let automaticallyReinstall: Bool; let planSHA256: String
    init(planID: UUID, provenance: PracticeWorkspaceProvenanceV1, expectedWorkspaceRevision: UInt64, mutationID: MutationIDV1, requestedAt: Date, explicitUserRequest: Bool, automaticallyReinstall: Bool = false) throws {
        self.planID = planID; workspaceID = provenance.workspaceID; provenanceID = provenance.provenanceID; provenanceSHA256 = provenance.provenanceSHA256
        self.expectedWorkspaceRevision = expectedWorkspaceRevision; self.mutationID = mutationID; self.requestedAt = requestedAt
        self.explicitUserRequest = explicitUserRequest; self.automaticallyReinstall = automaticallyReinstall
        planSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(planID: planID, workspaceID: provenance.workspaceID, provenanceID: provenance.provenanceID, provenanceSHA256: provenance.provenanceSHA256, expectedWorkspaceRevision: expectedWorkspaceRevision, mutationID: mutationID, requestedAt: requestedAt, explicitUserRequest: explicitUserRequest, automaticallyReinstall: automaticallyReinstall))
        try validate(provenance: provenance)
    }
    func validate() throws { try WorkspaceExperienceValidationV1.id(planID); try WorkspaceExperienceValidationV1.id(workspaceID.rawValue); try WorkspaceExperienceValidationV1.id(provenanceID); try WorkspaceExperienceValidationV1.digest(provenanceSHA256); try WorkspaceExperienceValidationV1.instant(requestedAt); guard expectedWorkspaceRevision > 0, explicitUserRequest, !automaticallyReinstall, planSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.practiceOnly } }
    func validate(provenance: PracticeWorkspaceProvenanceV1) throws { try validate(); try provenance.validate(); guard workspaceID == provenance.workspaceID, provenanceID == provenance.provenanceID, provenanceSHA256 == provenance.provenanceSHA256 else { throw WorkspaceExperienceFailureV1.practiceOnly } }
    private var basis: Basis { .init(planID: planID, workspaceID: workspaceID, provenanceID: provenanceID, provenanceSHA256: provenanceSHA256, expectedWorkspaceRevision: expectedWorkspaceRevision, mutationID: mutationID, requestedAt: requestedAt, explicitUserRequest: explicitUserRequest, automaticallyReinstall: automaticallyReinstall) }
    private struct Basis: Codable { let planID: UUID; let workspaceID: WorkspaceID; let provenanceID: UUID; let provenanceSHA256: String; let expectedWorkspaceRevision: UInt64; let mutationID: MutationIDV1; let requestedAt: Date; let explicitUserRequest: Bool; let automaticallyReinstall: Bool }
}

struct ConfigurationClonePlanV1: Codable, Equatable, Hashable, Sendable {
    let planID: UUID; let sourceWorkspaceID: WorkspaceID; let destinationWorkspaceID: WorkspaceID
    let sourceWorkspaceRevision: UInt64; let destinationIdentityIsNew: Bool; let destinationKind: WorkspaceExperienceWorkspaceKindV1
    let copiesConfigurationOnly: Bool; let copiesCustomerContent: Bool; let copiesPracticeProvenance: Bool
    let copiedDefinitionSHA256s: [String]; let mutationID: MutationIDV1; let planSHA256: String
    init(planID: UUID, sourceWorkspaceID: WorkspaceID, destinationWorkspaceID: WorkspaceID, sourceWorkspaceRevision: UInt64, destinationIdentityIsNew: Bool, destinationKind: WorkspaceExperienceWorkspaceKindV1, copiesConfigurationOnly: Bool, copiesCustomerContent: Bool, copiesPracticeProvenance: Bool, copiedDefinitionSHA256s: [String], mutationID: MutationIDV1) throws {
        self.planID = planID; self.sourceWorkspaceID = sourceWorkspaceID; self.destinationWorkspaceID = destinationWorkspaceID
        self.sourceWorkspaceRevision = sourceWorkspaceRevision; self.destinationIdentityIsNew = destinationIdentityIsNew; self.destinationKind = destinationKind
        self.copiesConfigurationOnly = copiesConfigurationOnly; self.copiesCustomerContent = copiesCustomerContent; self.copiesPracticeProvenance = copiesPracticeProvenance
        self.copiedDefinitionSHA256s = copiedDefinitionSHA256s.sorted(); self.mutationID = mutationID
        planSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(planID: planID, sourceWorkspaceID: sourceWorkspaceID, destinationWorkspaceID: destinationWorkspaceID, sourceWorkspaceRevision: sourceWorkspaceRevision, destinationIdentityIsNew: destinationIdentityIsNew, destinationKind: destinationKind, copiesConfigurationOnly: copiesConfigurationOnly, copiesCustomerContent: copiesCustomerContent, copiesPracticeProvenance: copiesPracticeProvenance, copiedDefinitionSHA256s: copiedDefinitionSHA256s.sorted(), mutationID: mutationID)); try validate()
    }
    func validate() throws { try WorkspaceExperienceValidationV1.id(planID); try WorkspaceExperienceValidationV1.id(sourceWorkspaceID.rawValue); try WorkspaceExperienceValidationV1.id(destinationWorkspaceID.rawValue); try copiedDefinitionSHA256s.forEach(WorkspaceExperienceValidationV1.digest); guard sourceWorkspaceID != destinationWorkspaceID, sourceWorkspaceRevision > 0, destinationIdentityIsNew, destinationKind == .real, copiesConfigurationOnly, !copiesCustomerContent, !copiesPracticeProvenance, copiedDefinitionSHA256s == copiedDefinitionSHA256s.sorted(), Set(copiedDefinitionSHA256s).count == copiedDefinitionSHA256s.count, planSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(basis)) else { throw WorkspaceExperienceFailureV1.customerContentForbidden } }
    private var basis: Basis { .init(planID: planID, sourceWorkspaceID: sourceWorkspaceID, destinationWorkspaceID: destinationWorkspaceID, sourceWorkspaceRevision: sourceWorkspaceRevision, destinationIdentityIsNew: destinationIdentityIsNew, destinationKind: destinationKind, copiesConfigurationOnly: copiesConfigurationOnly, copiesCustomerContent: copiesCustomerContent, copiesPracticeProvenance: copiesPracticeProvenance, copiedDefinitionSHA256s: copiedDefinitionSHA256s, mutationID: mutationID) }
    private struct Basis: Codable { let planID: UUID; let sourceWorkspaceID: WorkspaceID; let destinationWorkspaceID: WorkspaceID; let sourceWorkspaceRevision: UInt64; let destinationIdentityIsNew: Bool; let destinationKind: WorkspaceExperienceWorkspaceKindV1; let copiesConfigurationOnly: Bool; let copiesCustomerContent: Bool; let copiesPracticeProvenance: Bool; let copiedDefinitionSHA256s: [String]; let mutationID: MutationIDV1 }
}

struct ActiveWorkspaceSelectionV1: Codable, Equatable, Hashable, Sendable {
    static let persistenceDisposition = "DEVICE_LOCAL_NOT_BACKED_UP"
    static let lifecycleDisposition = WorkspaceExperienceDeviceLocalDispositionV1.deviceLocalNotBackedUp
    let workspaceID: WorkspaceID; let selectedAt: Date; let deviceLocalRevision: UInt64
    init(workspaceID: WorkspaceID, selectedAt: Date, deviceLocalRevision: UInt64) throws { self.workspaceID = workspaceID; self.selectedAt = selectedAt; self.deviceLocalRevision = deviceLocalRevision; try validate() }
    func validate() throws { try WorkspaceExperienceValidationV1.id(workspaceID.rawValue); try WorkspaceExperienceValidationV1.instant(selectedAt); guard deviceLocalRevision > 0 else { throw WorkspaceExperienceFailureV1.invalidValue } }
}

enum FirstValueKindV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable { case firstAsset = "FIRST_ASSET"; case firstCompletedWork = "FIRST_COMPLETED_WORK"; case firstReport = "FIRST_REPORT"; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }
struct FirstValueProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let achieved: [FirstValueKindV1]; let evaluatedAt: Date; init(workspaceID: WorkspaceID, achieved: [FirstValueKindV1], evaluatedAt: Date) throws { self.workspaceID = workspaceID; self.achieved = achieved.sorted(); self.evaluatedAt = evaluatedAt; try WorkspaceExperienceValidationV1.id(workspaceID.rawValue); try WorkspaceExperienceValidationV1.instant(evaluatedAt); try WorkspaceExperienceValidationV1.sortedUnique(self.achieved) } }

struct UXSimplicityPolicyV1: Codable, Equatable, Sendable {
    let maximumPrimaryActions: Int; let maximumCaptureTaps: Int; let maximumResumeTaps: Int; let maximumContextSwitches: Int
    init(maximumPrimaryActions: Int, maximumCaptureTaps: Int, maximumResumeTaps: Int, maximumContextSwitches: Int) throws { self.maximumPrimaryActions = maximumPrimaryActions; self.maximumCaptureTaps = maximumCaptureTaps; self.maximumResumeTaps = maximumResumeTaps; self.maximumContextSwitches = maximumContextSwitches; guard (1...WorkspaceExperienceLimitsV1.maximumActionCount).contains(maximumPrimaryActions), (1...12).contains(maximumCaptureTaps), (1...8).contains(maximumResumeTaps), (0...8).contains(maximumContextSwitches) else { throw WorkspaceExperienceFailureV1.invalidValue } }
}

struct WorkspaceExperienceProfileV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let kind: WorkspaceExperienceWorkspaceKindV1; let roots: [WorkspaceExperienceRootV1]; let searchScopes: [WorkspaceExperienceSearchScopeV1]; let policy: UXSimplicityPolicyV1; init(workspaceID: WorkspaceID, provenance: PracticeWorkspaceProvenanceV1?, policy: UXSimplicityPolicyV1) throws { self.workspaceID = workspaceID; kind = try WorkspaceExperienceClassificationV1.kind(provenance: provenance); roots = WorkspaceExperienceRootV1.canonicalShellOrder; searchScopes = WorkspaceExperienceSearchScopeV1.canonicalOrder; self.policy = policy; guard provenance?.workspaceID == workspaceID || provenance == nil else { throw WorkspaceExperienceFailureV1.wrongWorkspace } } }

enum NextRequiredActionKindV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable { case resumeDraft = "RESUME_DRAFT"; case reviewRecovery = "REVIEW_RECOVERY"; case startWork = "START_WORK"; case continueWork = "CONTINUE_WORK"; case reviewFinding = "REVIEW_FINDING"; case renderReport = "RENDER_REPORT"; case none = "NONE"; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }
struct NextRequiredActionProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let action: NextRequiredActionKindV1; let sourceID: UUID?; let sourceRevision: UInt64?; let sourceSHA256: String?; let reasonKey: String; init(workspaceID: WorkspaceID, action: NextRequiredActionKindV1, sourceID: UUID?, sourceRevision: UInt64?, sourceSHA256: String?, reasonKey: String) throws { self.workspaceID = workspaceID; self.action = action; self.sourceID = sourceID; self.sourceRevision = sourceRevision; self.sourceSHA256 = sourceSHA256; self.reasonKey = reasonKey; try WorkspaceExperienceValidationV1.text(reasonKey); let hasSource = sourceID != nil || sourceRevision != nil || sourceSHA256 != nil; guard action == .none ? !hasSource : (sourceID != nil && sourceRevision != nil && sourceSHA256 != nil) else { throw WorkspaceExperienceFailureV1.invalidValue }; if let id = sourceID { try WorkspaceExperienceValidationV1.id(id) }; if let revision = sourceRevision { guard revision > 0 else { throw WorkspaceExperienceFailureV1.invalidValue } }; if let digest = sourceSHA256 { try WorkspaceExperienceValidationV1.digest(digest) } } }

enum WorkspaceResumeDispositionV1: String, CaseIterable, Codable, Hashable, Sendable { case resume = "RESUME"; case reviewRequired = "REVIEW_REQUIRED"; case unavailable = "UNAVAILABLE" }
struct WorkspaceResumeProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let draftID: UUID; let disposition: WorkspaceResumeDispositionV1; let routeToken: String?; let restoredWorkMustNotRestart: Bool; let updatedAt: Date; init(workspaceID: WorkspaceID, draftID: UUID, disposition: WorkspaceResumeDispositionV1, routeToken: String?, restoredWorkMustNotRestart: Bool = true, updatedAt: Date) throws { self.workspaceID = workspaceID; self.draftID = draftID; self.disposition = disposition; self.routeToken = routeToken; self.restoredWorkMustNotRestart = restoredWorkMustNotRestart; self.updatedAt = updatedAt; try WorkspaceExperienceValidationV1.id(workspaceID.rawValue); try WorkspaceExperienceValidationV1.id(draftID); try WorkspaceExperienceValidationV1.instant(updatedAt); if let routeToken { try WorkspaceExperienceValidationV1.text(routeToken) }; guard restoredWorkMustNotRestart, disposition == .unavailable ? routeToken == nil : routeToken != nil else { throw WorkspaceExperienceFailureV1.invalidValue } } }

struct LocationManagementProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let locationID: UUID; let locationRevision: UInt64; let locationSHA256: String; let childCount: Int; let canMove: Bool; let canRetire: Bool; init(workspaceID: WorkspaceID, locationID: UUID, locationRevision: UInt64, locationSHA256: String, childCount: Int, canMove: Bool, canRetire: Bool) throws { self.workspaceID = workspaceID; self.locationID = locationID; self.locationRevision = locationRevision; self.locationSHA256 = locationSHA256; self.childCount = childCount; self.canMove = canMove; self.canRetire = canRetire; try WorkspaceExperienceValidationV1.id(workspaceID.rawValue); try WorkspaceExperienceValidationV1.id(locationID); try WorkspaceExperienceValidationV1.digest(locationSHA256); guard locationRevision > 0, childCount >= 0, childCount <= WorkspaceExperienceLimitsV1.maximumItems else { throw WorkspaceExperienceFailureV1.invalidValue } } }

struct SemanticReversalPresenterV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let targetMutationID: MutationIDV1; let isAvailable: Bool; let reason: WorkspaceExperienceAvailabilityReasonV1; let confirmationKey: String; let consequenceKeys: [String]; init(workspaceID: WorkspaceID, targetMutationID: MutationIDV1, isAvailable: Bool, reason: WorkspaceExperienceAvailabilityReasonV1, confirmationKey: String, consequenceKeys: [String]) throws { self.workspaceID = workspaceID; self.targetMutationID = targetMutationID; self.isAvailable = isAvailable; self.reason = reason; self.confirmationKey = confirmationKey; self.consequenceKeys = consequenceKeys.sorted(); try WorkspaceExperienceValidationV1.text(confirmationKey); try consequenceKeys.forEach { try WorkspaceExperienceValidationV1.text($0) }; guard isAvailable == (reason == .available), self.consequenceKeys == consequenceKeys.sorted(), Set(consequenceKeys).count == consequenceKeys.count else { throw WorkspaceExperienceFailureV1.invalidValue } } }

enum FirstRealJobStageV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable { case chooseWorkspace = "CHOOSE_WORKSPACE"; case locateAsset = "LOCATE_ASSET"; case captureEvidence = "CAPTURE_EVIDENCE"; case recordOutcome = "RECORD_OUTCOME"; case finishWork = "FINISH_WORK"; case reviewReport = "REVIEW_REPORT"; case complete = "COMPLETE"; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }
struct TechnicianWorkflowBudgetV1: Codable, Equatable, Sendable { let maximumTapsToCapture: Int; let maximumTapsToResume: Int; let maximumPrimaryActionsPerScreen: Int; let maximumSecondsBeforeDurableCheckpoint: Int; init(maximumTapsToCapture: Int, maximumTapsToResume: Int, maximumPrimaryActionsPerScreen: Int, maximumSecondsBeforeDurableCheckpoint: Int) throws { self.maximumTapsToCapture = maximumTapsToCapture; self.maximumTapsToResume = maximumTapsToResume; self.maximumPrimaryActionsPerScreen = maximumPrimaryActionsPerScreen; self.maximumSecondsBeforeDurableCheckpoint = maximumSecondsBeforeDurableCheckpoint; guard (1...12).contains(maximumTapsToCapture), (1...8).contains(maximumTapsToResume), (1...WorkspaceExperienceLimitsV1.maximumActionCount).contains(maximumPrimaryActionsPerScreen), (1...300).contains(maximumSecondsBeforeDurableCheckpoint) else { throw WorkspaceExperienceFailureV1.invalidValue } } }
struct FirstRealJobConductorProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let workspaceKind: WorkspaceExperienceWorkspaceKindV1; let stage: FirstRealJobStageV1; let nextAction: NextRequiredActionProjectionV1; let budget: TechnicianWorkflowBudgetV1; let evaluatedAt: Date; init(workspaceID: WorkspaceID, workspaceKind: WorkspaceExperienceWorkspaceKindV1, stage: FirstRealJobStageV1, nextAction: NextRequiredActionProjectionV1, budget: TechnicianWorkflowBudgetV1, evaluatedAt: Date) throws { self.workspaceID = workspaceID; self.workspaceKind = workspaceKind; self.stage = stage; self.nextAction = nextAction; self.budget = budget; self.evaluatedAt = evaluatedAt; try WorkspaceExperienceValidationV1.instant(evaluatedAt); guard nextAction.workspaceID == workspaceID, workspaceKind == .real else { throw WorkspaceExperienceFailureV1.realWorkspaceRequired } } }

enum TodayUpdateKindV1: String, CaseIterable, Codable, Comparable, Hashable, Sendable { case due = "DUE"; case blocked = "BLOCKED"; case ready = "READY"; case resumed = "RESUMED"; case completed = "COMPLETED"; static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue } }
struct TodayUpdateProjectionV1: Codable, Equatable, Comparable, Sendable { let updateID: UUID; let workspaceID: WorkspaceID; let sourceID: UUID; let sourceRevision: UInt64; let sourceSHA256: String; let kind: TodayUpdateKindV1; let titleKey: String; let occurredAt: Date; init(updateID: UUID, workspaceID: WorkspaceID, sourceID: UUID, sourceRevision: UInt64, sourceSHA256: String, kind: TodayUpdateKindV1, titleKey: String, occurredAt: Date) throws { self.updateID = updateID; self.workspaceID = workspaceID; self.sourceID = sourceID; self.sourceRevision = sourceRevision; self.sourceSHA256 = sourceSHA256; self.kind = kind; self.titleKey = titleKey; self.occurredAt = occurredAt; try WorkspaceExperienceValidationV1.id(updateID); try WorkspaceExperienceValidationV1.id(sourceID); try WorkspaceExperienceValidationV1.digest(sourceSHA256); try WorkspaceExperienceValidationV1.text(titleKey); try WorkspaceExperienceValidationV1.instant(occurredAt); guard sourceRevision > 0 else { throw WorkspaceExperienceFailureV1.invalidValue } }; static func < (lhs: Self, rhs: Self) -> Bool { lhs.occurredAt == rhs.occurredAt ? lhs.updateID.uuidString < rhs.updateID.uuidString : lhs.occurredAt > rhs.occurredAt } }

struct ProductChangeCatalogReleaseV1: Codable, Equatable, Sendable { let catalogID: UUID; let version: UInt64; let notices: [ProductChangeNoticeV1]; let catalogSHA256: String; init(catalogID: UUID, version: UInt64, notices: [ProductChangeNoticeV1]) throws { self.catalogID = catalogID; self.version = version; self.notices = notices.sorted { $0.noticeID.uuidString < $1.noticeID.uuidString }; catalogSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(catalogID: catalogID, version: version, notices: self.notices)); try validate() }; func validate() throws { try WorkspaceExperienceValidationV1.id(catalogID); try notices.forEach { try $0.validate() }; guard version > 0, notices.count <= WorkspaceExperienceLimitsV1.maximumItems, notices == notices.sorted(by: { $0.noticeID.uuidString < $1.noticeID.uuidString }), Set(notices.map(\.noticeID)).count == notices.count, catalogSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(catalogID: catalogID, version: version, notices: notices))) else { throw WorkspaceExperienceFailureV1.invalidDigest } }; private struct Basis: Codable { let catalogID: UUID; let version: UInt64; let notices: [ProductChangeNoticeV1] } }
struct ProductChangeNoticeV1: Codable, Equatable, Sendable { let noticeID: UUID; let releaseVersion: String; let titleKey: String; let bodyKey: String; let effectiveAt: Date; let expiresAt: Date?; let noticeSHA256: String; init(noticeID: UUID, releaseVersion: String, titleKey: String, bodyKey: String, effectiveAt: Date, expiresAt: Date?) throws { self.noticeID = noticeID; self.releaseVersion = releaseVersion; self.titleKey = titleKey; self.bodyKey = bodyKey; self.effectiveAt = effectiveAt; self.expiresAt = expiresAt; noticeSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(noticeID: noticeID, releaseVersion: releaseVersion, titleKey: titleKey, bodyKey: bodyKey, effectiveAt: effectiveAt, expiresAt: expiresAt)); try validate() }; func validate() throws { try WorkspaceExperienceValidationV1.id(noticeID); try WorkspaceExperienceValidationV1.text(releaseVersion); try WorkspaceExperienceValidationV1.text(titleKey); try WorkspaceExperienceValidationV1.text(bodyKey, maximumBytes: WorkspaceExperienceLimitsV1.maximumBodyBytes); try WorkspaceExperienceValidationV1.instant(effectiveAt); try expiresAt.map(WorkspaceExperienceValidationV1.instant); guard expiresAt.map { $0 > effectiveAt } ?? true, noticeSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(noticeID: noticeID, releaseVersion: releaseVersion, titleKey: titleKey, bodyKey: bodyKey, effectiveAt: effectiveAt, expiresAt: expiresAt))) else { throw WorkspaceExperienceFailureV1.invalidDigest } }; private struct Basis: Codable { let noticeID: UUID; let releaseVersion: String; let titleKey: String; let bodyKey: String; let effectiveAt: Date; let expiresAt: Date? } }
struct NoticeAcknowledgementV1: Codable, Equatable, Sendable { static let persistenceDisposition = "DEVICE_LOCAL_NOT_BACKED_UP"; static let lifecycleDisposition = WorkspaceExperienceDeviceLocalDispositionV1.deviceLocalNotBackedUp; let noticeID: UUID; let noticeSHA256: String; let acknowledgedAt: Date; let deviceLocalRevision: UInt64; init(noticeID: UUID, noticeSHA256: String, acknowledgedAt: Date, deviceLocalRevision: UInt64) throws { self.noticeID = noticeID; self.noticeSHA256 = noticeSHA256; self.acknowledgedAt = acknowledgedAt; self.deviceLocalRevision = deviceLocalRevision; try WorkspaceExperienceValidationV1.id(noticeID); try WorkspaceExperienceValidationV1.digest(noticeSHA256); try WorkspaceExperienceValidationV1.instant(acknowledgedAt); guard deviceLocalRevision > 0 else { throw WorkspaceExperienceFailureV1.invalidValue } } }

struct ContextualHelpEntryV1: Codable, Equatable, Sendable { let entryID: String; let contextKey: String; let titleKey: String; let bodyKey: String; let actionKey: String?; let tags: [String]; init(entryID: String, contextKey: String, titleKey: String, bodyKey: String, actionKey: String?, tags: [String]) throws { self.entryID = entryID; self.contextKey = contextKey; self.titleKey = titleKey; self.bodyKey = bodyKey; self.actionKey = actionKey; self.tags = tags.sorted(); try validate() }; func validate() throws { try WorkspaceExperienceValidationV1.text(entryID); try WorkspaceExperienceValidationV1.text(contextKey); try WorkspaceExperienceValidationV1.text(titleKey); try WorkspaceExperienceValidationV1.text(bodyKey, maximumBytes: WorkspaceExperienceLimitsV1.maximumBodyBytes); if let actionKey { try WorkspaceExperienceValidationV1.text(actionKey) }; try tags.forEach { try WorkspaceExperienceValidationV1.text($0) }; guard tags.count <= WorkspaceExperienceLimitsV1.maximumTags, tags == tags.sorted(), Set(tags).count == tags.count else { throw WorkspaceExperienceFailureV1.unorderedValue } } }
struct ContextualGuidanceCatalogV1: Codable, Equatable, Sendable { let catalogID: UUID; let version: UInt64; let entries: [ContextualHelpEntryV1]; let catalogSHA256: String; init(catalogID: UUID, version: UInt64, entries: [ContextualHelpEntryV1]) throws { self.catalogID = catalogID; self.version = version; self.entries = entries.sorted { $0.entryID < $1.entryID }; catalogSHA256 = try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(catalogID: catalogID, version: version, entries: self.entries)); try validate() }; func validate() throws { try entries.forEach { try $0.validate() }; guard version > 0, entries.count <= WorkspaceExperienceLimitsV1.maximumItems, entries == entries.sorted(by: { $0.entryID < $1.entryID }), Set(entries.map(\.entryID)).count == entries.count, catalogSHA256 == (try WorkspaceExperienceCanonicalCodecV1.sha256(Basis(catalogID: catalogID, version: version, entries: entries))) else { throw WorkspaceExperienceFailureV1.invalidDigest } }; private struct Basis: Codable { let catalogID: UUID; let version: UInt64; let entries: [ContextualHelpEntryV1] } }
struct ContextualGuidanceProjectionV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let contextKey: String; let entries: [ContextualHelpEntryV1]; let generatedAt: Date; init(workspaceID: WorkspaceID, contextKey: String, entries: [ContextualHelpEntryV1], generatedAt: Date) throws { self.workspaceID = workspaceID; self.contextKey = contextKey; self.entries = entries.sorted { $0.entryID < $1.entryID }; self.generatedAt = generatedAt; try WorkspaceExperienceValidationV1.text(contextKey); try WorkspaceExperienceValidationV1.instant(generatedAt); try self.entries.forEach { try $0.validate() }; guard self.entries.allSatisfy({ $0.contextKey == contextKey }), Set(self.entries.map(\.entryID)).count == self.entries.count else { throw WorkspaceExperienceFailureV1.invalidValue } } }

struct PracticeShareConfirmationV1: Codable, Equatable, Sendable { let workspaceID: WorkspaceID; let provenanceID: UUID; let watermark: String; let explicitConfirmationRequired: Bool; let confirmationKey: String; init(provenance: PracticeWorkspaceProvenanceV1, watermark: String = "PRACTICE — NOT FOR FIELD USE", explicitConfirmationRequired: Bool = true, confirmationKey: String) throws { workspaceID = provenance.workspaceID; provenanceID = provenance.provenanceID; self.watermark = watermark; self.explicitConfirmationRequired = explicitConfirmationRequired; self.confirmationKey = confirmationKey; try provenance.validate(); try WorkspaceExperienceValidationV1.text(confirmationKey); guard watermark == "PRACTICE — NOT FOR FIELD USE", explicitConfirmationRequired else { throw WorkspaceExperienceFailureV1.practiceOnly } } }

enum WorkspaceExperienceDataPolicyV1 {
    static let practiceMetricsCollected = false
    static let practiceUsesCustomerData = false
    static let practiceRequiresNetwork = false
    static let practiceRequiresPermissions = false
    static let restoreMayExposeResume = true
    static let restoreAutomaticallyRestartsWork = false
    static let projectionsArePersistent = false
}

extension FirstValueProjectionV1: Hashable {}
extension UXSimplicityPolicyV1: Hashable {}
extension WorkspaceExperienceProfileV1: Hashable {}
extension NextRequiredActionProjectionV1: Hashable {}
extension WorkspaceResumeProjectionV1: Hashable {}
extension LocationManagementProjectionV1: Hashable {}
extension SemanticReversalPresenterV1: Hashable {}
extension TechnicianWorkflowBudgetV1: Hashable {}
extension FirstRealJobConductorProjectionV1: Hashable {}
extension TodayUpdateProjectionV1: Hashable {}

/// A contained projection under the already-declared Today root. It neither
/// creates a shell root nor persists a second copy of My Day or due truth.
struct TodayMyDayCompositionV1: Codable, Equatable, Sendable {
    let root: WorkspaceExperienceRootV1
    let summary: MyDaySummaryProjectionV1
    let updates: [TodayUpdateProjectionV1]
    let containedNonRoot: Bool
    let canonicalWriteCount: Int

    init(
        summary: MyDaySummaryProjectionV1,
        updates: [TodayUpdateProjectionV1]
    ) throws {
        try summary.validate()
        guard updates.allSatisfy({ $0.workspaceID == summary.plan.key.workspaceID }),
              Set(updates.map(\.updateID)).count == updates.count else {
            throw WorkspaceExperienceFailureV1.wrongWorkspace
        }
        root = .today
        self.summary = summary
        self.updates = updates.sorted()
        containedNonRoot = true
        canonicalWriteCount = 0
    }

    func validate() throws {
        try summary.validate()
        guard root == .today,
              containedNonRoot,
              canonicalWriteCount == 0,
              updates == updates.sorted(),
              updates.allSatisfy({ $0.workspaceID == summary.plan.key.workspaceID }),
              Set(updates.map(\.updateID)).count == updates.count else {
            throw WorkspaceExperienceFailureV1.invalidValue
        }
    }
}
extension ProductChangeCatalogReleaseV1: Hashable {}
extension ProductChangeNoticeV1: Hashable {}
extension NoticeAcknowledgementV1: Hashable {}
extension ContextualHelpEntryV1: Hashable {}
extension ContextualGuidanceCatalogV1: Hashable {}
extension ContextualGuidanceProjectionV1: Hashable {}
extension PracticeShareConfirmationV1: Hashable {}
