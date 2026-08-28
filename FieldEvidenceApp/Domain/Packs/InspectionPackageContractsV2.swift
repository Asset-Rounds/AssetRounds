import Foundation

enum InspectionPackageFailureV2: Error, Equatable, Sendable {
    case invalidValue
    case duplicatePackageID
    case duplicateDeclaration
    case unknownPackage
    case incompatiblePackage
    case undeclaredCapability
    case undeclaredPermission
    case undeclaredGuidance
    case nonCanonicalData
    case publicationInterrupted
    case bundledPackageUnavailable
}

enum InspectionPackageCapabilityV2: String, CaseIterable, Codable, Hashable, Sendable {
    case photoCapture = "PHOTO_CAPTURE"
    case photoImport = "PHOTO_IMPORT"
    case visibleIssueClassification = "VISIBLE_ISSUE_CLASSIFICATION"
    case couldNotVerify = "COULD_NOT_VERIFY"
    case recheck = "RECHECK"
    case workEvidence = "WORK_EVIDENCE"
}

enum InspectionPackagePermissionV2: String, CaseIterable, Codable, Hashable, Sendable {
    case camera = "CAMERA"
    case photoLibrarySelection = "PHOTO_LIBRARY_SELECTION"
}

enum InspectionPackageGuidanceKindV2: String, CaseIterable, Codable, Hashable, Sendable {
    case evidence = "EVIDENCE"
    case safety = "SAFETY"
    case limitation = "LIMITATION"
}

struct InspectionPackageGuidanceV2: Codable, Equatable, Sendable {
    let guidanceID: String
    let kind: InspectionPackageGuidanceKindV2
    let localizationKey: String

    init(
        guidanceID: String,
        kind: InspectionPackageGuidanceKindV2,
        localizationKey: String
    ) {
        self.guidanceID = guidanceID
        self.kind = kind
        self.localizationKey = localizationKey
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(guidanceID, maximumBytes: 120),
              InspectionPackageValidationV2.validIdentifier(
                localizationKey,
                maximumBytes: 200
              ) else {
            throw InspectionPackageFailureV2.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case guidanceID, kind, localizationKey
    }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            guidanceID: try values.decode(String.self, forKey: .guidanceID),
            kind: try values.decode(InspectionPackageGuidanceKindV2.self, forKey: .kind),
            localizationKey: try values.decode(String.self, forKey: .localizationKey)
        )
        try validate()
    }
}

struct InspectionPackageDisplayEntryV2: Codable, Equatable, Sendable {
    let key: String
    let display: String

    init(key: String, display: String) {
        self.key = key
        self.display = display
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(key, maximumBytes: 100),
              InspectionPackageValidationV2.validText(display, maximumCharacters: 300) else {
            throw InspectionPackageFailureV2.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case key, display }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try values.decode(String.self, forKey: .key),
            display: try values.decode(String.self, forKey: .display)
        )
        try validate()
    }
}

struct InspectionPackageEvidencePurposeV2: Codable, Equatable, Sendable {
    let key: String
    let display: String
    let instruction: String

    init(key: String, display: String, instruction: String) {
        self.key = key
        self.display = display
        self.instruction = instruction
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(key, maximumBytes: 100),
              InspectionPackageValidationV2.validText(display, maximumCharacters: 200),
              InspectionPackageValidationV2.validText(instruction, maximumCharacters: 1_000) else {
            throw InspectionPackageFailureV2.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key, display, instruction
    }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try values.decode(String.self, forKey: .key),
            display: try values.decode(String.self, forKey: .display),
            instruction: try values.decode(String.self, forKey: .instruction)
        )
        try validate()
    }
}

struct InspectionPackageAcknowledgementV2: Codable, Equatable, Sendable {
    let key: String
    let copy: String
    let version: String

    init(key: String, copy: String, version: String) {
        self.key = key
        self.copy = copy
        self.version = version
    }

    func validate() throws {
        guard InspectionPackageValidationV2.validIdentifier(key, maximumBytes: 100),
              InspectionPackageValidationV2.validText(copy, maximumCharacters: 1_000),
              InspectionPackageValidationV2.validToken(version, maximumBytes: 200) else {
            throw InspectionPackageFailureV2.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case key, copy, version
    }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try values.decode(String.self, forKey: .key),
            copy: try values.decode(String.self, forKey: .copy),
            version: try values.decode(String.self, forKey: .version)
        )
        try validate()
    }
}

struct InspectionPackagePresentationV2: Codable, Equatable, Sendable {
    let assetSingular: String
    let assetPlural: String
    let checkSingular: String
    let checkPlural: String
    let issueSingular: String
    let issuePlural: String
    let evidencePurposes: [InspectionPackageEvidencePurposeV2]
    let acknowledgements: [InspectionPackageAcknowledgementV2]
    let issueLabels: [InspectionPackageDisplayEntryV2]
    let couldNotVerifyRegistryVersion: String
    let couldNotVerifyReasons: [InspectionPackageDisplayEntryV2]
    let stageDisplays: [InspectionPackageDisplayEntryV2]
    let outcomeDisplays: [InspectionPackageDisplayEntryV2]
    let disclaimer: String

    init(
        assetSingular: String,
        assetPlural: String,
        checkSingular: String,
        checkPlural: String,
        issueSingular: String,
        issuePlural: String,
        evidencePurposes: [InspectionPackageEvidencePurposeV2],
        acknowledgements: [InspectionPackageAcknowledgementV2],
        issueLabels: [InspectionPackageDisplayEntryV2],
        couldNotVerifyRegistryVersion: String,
        couldNotVerifyReasons: [InspectionPackageDisplayEntryV2],
        stageDisplays: [InspectionPackageDisplayEntryV2],
        outcomeDisplays: [InspectionPackageDisplayEntryV2],
        disclaimer: String
    ) {
        self.assetSingular = assetSingular
        self.assetPlural = assetPlural
        self.checkSingular = checkSingular
        self.checkPlural = checkPlural
        self.issueSingular = issueSingular
        self.issuePlural = issuePlural
        self.evidencePurposes = evidencePurposes
        self.acknowledgements = acknowledgements
        self.issueLabels = issueLabels
        self.couldNotVerifyRegistryVersion = couldNotVerifyRegistryVersion
        self.couldNotVerifyReasons = couldNotVerifyReasons
        self.stageDisplays = stageDisplays
        self.outcomeDisplays = outcomeDisplays
        self.disclaimer = disclaimer
    }

    func validate() throws {
        for (singular, plural) in [
            (assetSingular, assetPlural),
            (checkSingular, checkPlural),
            (issueSingular, issuePlural),
        ] {
            guard InspectionPackageValidationV2.validText(singular, maximumCharacters: 100),
                  InspectionPackageValidationV2.validText(plural, maximumCharacters: 100),
                  singular != plural else { throw InspectionPackageFailureV2.invalidValue }
        }
        guard !evidencePurposes.isEmpty, evidencePurposes.count <= 64,
              acknowledgements.count <= 64, issueLabels.count <= 128,
              couldNotVerifyReasons.count <= 128, stageDisplays.count <= 64,
              outcomeDisplays.count <= 128,
              InspectionPackageValidationV2.validToken(
                couldNotVerifyRegistryVersion,
                maximumBytes: 200
              ),
              InspectionPackageValidationV2.validText(disclaimer, maximumCharacters: 2_000) else {
            throw InspectionPackageFailureV2.invalidValue
        }
        try evidencePurposes.forEach { try $0.validate() }
        try acknowledgements.forEach { try $0.validate() }
        for values in [issueLabels, couldNotVerifyReasons, stageDisplays, outcomeDisplays] {
            try values.forEach { try $0.validate() }
            guard InspectionPackageValidationV2.unique(values.map(\.key)),
                  InspectionPackageValidationV2.unique(values.map(\.display)) else {
                throw InspectionPackageFailureV2.duplicateDeclaration
            }
        }
        guard InspectionPackageValidationV2.unique(evidencePurposes.map(\.key)),
              InspectionPackageValidationV2.unique(acknowledgements.map(\.key)) else {
            throw InspectionPackageFailureV2.duplicateDeclaration
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case assetSingular, assetPlural, checkSingular, checkPlural
        case issueSingular, issuePlural, evidencePurposes, acknowledgements
        case issueLabels, couldNotVerifyRegistryVersion, couldNotVerifyReasons
        case stageDisplays, outcomeDisplays, disclaimer
    }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            assetSingular: try values.decode(String.self, forKey: .assetSingular),
            assetPlural: try values.decode(String.self, forKey: .assetPlural),
            checkSingular: try values.decode(String.self, forKey: .checkSingular),
            checkPlural: try values.decode(String.self, forKey: .checkPlural),
            issueSingular: try values.decode(String.self, forKey: .issueSingular),
            issuePlural: try values.decode(String.self, forKey: .issuePlural),
            evidencePurposes: try values.decode(
                [InspectionPackageEvidencePurposeV2].self,
                forKey: .evidencePurposes
            ),
            acknowledgements: try values.decode(
                [InspectionPackageAcknowledgementV2].self,
                forKey: .acknowledgements
            ),
            issueLabels: try values.decode(
                [InspectionPackageDisplayEntryV2].self,
                forKey: .issueLabels
            ),
            couldNotVerifyRegistryVersion: try values.decode(
                String.self,
                forKey: .couldNotVerifyRegistryVersion
            ),
            couldNotVerifyReasons: try values.decode(
                [InspectionPackageDisplayEntryV2].self,
                forKey: .couldNotVerifyReasons
            ),
            stageDisplays: try values.decode(
                [InspectionPackageDisplayEntryV2].self,
                forKey: .stageDisplays
            ),
            outcomeDisplays: try values.decode(
                [InspectionPackageDisplayEntryV2].self,
                forKey: .outcomeDisplays
            ),
            disclaimer: try values.decode(String.self, forKey: .disclaimer)
        )
        try validate()
    }
}

struct InspectionPackageV2: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let packageID: String
    let contentVersion: Int
    let minimumRegistryVersion: Int
    let maximumRegistryVersion: Int
    let capabilities: [InspectionPackageCapabilityV2]
    let permissions: [InspectionPackagePermissionV2]
    let advisoryGuidance: [InspectionPackageGuidanceV2]
    let presentation: InspectionPackagePresentationV2

    init(
        packageID: String,
        contentVersion: Int,
        minimumRegistryVersion: Int = InspectionPackageRegistrySchemaV2.version,
        maximumRegistryVersion: Int = InspectionPackageRegistrySchemaV2.version,
        capabilities: [InspectionPackageCapabilityV2],
        permissions: [InspectionPackagePermissionV2],
        advisoryGuidance: [InspectionPackageGuidanceV2],
        presentation: InspectionPackagePresentationV2
    ) throws {
        schemaVersion = Self.schemaVersion
        self.packageID = packageID
        self.contentVersion = contentVersion
        self.minimumRegistryVersion = minimumRegistryVersion
        self.maximumRegistryVersion = maximumRegistryVersion
        self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
        self.permissions = permissions.sorted { $0.rawValue < $1.rawValue }
        self.advisoryGuidance = advisoryGuidance.sorted { $0.guidanceID < $1.guidanceID }
        self.presentation = presentation
        try validate()
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              InspectionPackageValidationV2.validIdentifier(packageID, maximumBytes: 200),
              contentVersion > 0,
              minimumRegistryVersion > 0,
              maximumRegistryVersion >= minimumRegistryVersion,
              capabilities.count <= InspectionPackageCapabilityV2.allCases.count,
              permissions.count <= InspectionPackagePermissionV2.allCases.count,
              advisoryGuidance.count <= 64,
              capabilities == capabilities.sorted(by: { $0.rawValue < $1.rawValue }),
              permissions == permissions.sorted(by: { $0.rawValue < $1.rawValue }),
              advisoryGuidance == advisoryGuidance.sorted(by: {
                $0.guidanceID < $1.guidanceID
              }) else {
            throw InspectionPackageFailureV2.invalidValue
        }
        guard InspectionPackageValidationV2.unique(capabilities.map(\.rawValue)),
              InspectionPackageValidationV2.unique(permissions.map(\.rawValue)),
              InspectionPackageValidationV2.unique(advisoryGuidance.map(\.guidanceID)) else {
            throw InspectionPackageFailureV2.duplicateDeclaration
        }
        guard !capabilities.contains(.photoCapture) || permissions.contains(.camera),
              !capabilities.contains(.photoImport) || permissions.contains(.photoLibrarySelection),
              !permissions.contains(.camera) || capabilities.contains(.photoCapture),
              !permissions.contains(.photoLibrarySelection)
                || capabilities.contains(.photoImport) else {
            throw InspectionPackageFailureV2.undeclaredPermission
        }
        try advisoryGuidance.forEach { try $0.validate() }
        try presentation.validate()
    }

    func requireCapability(_ capability: InspectionPackageCapabilityV2) throws {
        guard capabilities.contains(capability) else {
            throw InspectionPackageFailureV2.undeclaredCapability
        }
    }

    func requirePermission(_ permission: InspectionPackagePermissionV2) throws {
        guard permissions.contains(permission) else {
            throw InspectionPackageFailureV2.undeclaredPermission
        }
    }

    func requireGuidance(_ guidanceID: String) throws -> InspectionPackageGuidanceV2 {
        guard let value = advisoryGuidance.first(where: { $0.guidanceID == guidanceID }) else {
            throw InspectionPackageFailureV2.undeclaredGuidance
        }
        return value
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, packageID, contentVersion, minimumRegistryVersion
        case maximumRegistryVersion, capabilities, permissions, advisoryGuidance, presentation
    }

    init(from decoder: any Decoder) throws {
        try InspectionPackageClosedCodingV2.requireExactKeys(
            decoder,
            expected: CodingKeys.allCases.map(\.rawValue)
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        try self.init(
            packageID: values.decode(String.self, forKey: .packageID),
            contentVersion: values.decode(Int.self, forKey: .contentVersion),
            minimumRegistryVersion: values.decode(Int.self, forKey: .minimumRegistryVersion),
            maximumRegistryVersion: values.decode(Int.self, forKey: .maximumRegistryVersion),
            capabilities: values.decode([InspectionPackageCapabilityV2].self, forKey: .capabilities),
            permissions: values.decode([InspectionPackagePermissionV2].self, forKey: .permissions),
            advisoryGuidance: values.decode([InspectionPackageGuidanceV2].self, forKey: .advisoryGuidance),
            presentation: values.decode(InspectionPackagePresentationV2.self, forKey: .presentation)
        )
    }
}

enum InspectionPackageRegistrySchemaV2 {
    static let name = "PACKAGE_REGISTRY_V2"
    static let version = 2
    static let maximumPackageCount = 32
}

enum InspectionPackageCanonicalCodecV2 {
    static func encode(_ value: InspectionPackageV2) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> InspectionPackageV2 {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw InspectionPackageFailureV2.invalidValue
        }
        let value = try JSONDecoder().decode(InspectionPackageV2.self, from: data)
        guard try encode(value) == data else {
            throw InspectionPackageFailureV2.nonCanonicalData
        }
        return value
    }
}

enum InspectionPackageCompatibilityValidatorV2 {
    static func validate(_ package: InspectionPackageV2) throws {
        try package.validate()
        // Schema V2 is closed and still decoded exactly as before.  Content
        // versions are release identities, however, so a positive successor
        // must be admitted when it remains within this registry's declared
        // compatibility range.
        guard package.contentVersion > 0,
              package.minimumRegistryVersion <= InspectionPackageRegistrySchemaV2.version,
              package.maximumRegistryVersion >= InspectionPackageRegistrySchemaV2.version else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
    }
}

enum InspectionPackageLifecycleV2 {
    static let mode = "DECLARATION_ONLY"
    static let schema = "PACKAGE_REGISTRY_V2"
    static let version = 2
    static let migrationRequired = false
    static let backupRestoreRequired = false
    static let deleteEraseRequired = false
    static let exportReportRequired = false
    static let downgradePolicy = "DORMANT_REVERT_ALLOWED"
    static let persistent = false

    static let writerCommand = "NOT_APPLICABLE"
    static let canonicalQuery = "BUNDLED_IN_MEMORY_DECLARATION"
    static let filesystemBackup = "EXCLUDED"
    static let semanticBackup = "EXCLUDED"
    static let replaceRestore = "NOT_APPLICABLE"
    static let clone = "NOT_APPLICABLE"
    static let fork = "NOT_APPLICABLE"
    static let importDisposition = "BUNDLED_ONLY"
    static let exportDisposition = "EXCLUDED"
    static let journal = "NOT_APPLICABLE"
    static let replay = "DETERMINISTIC_REBUILD_FROM_BUNDLE"
    static let search = "NOT_APPLICABLE"
    static let rebuild = "DETERMINISTIC_REBUILD_FROM_BUNDLE"
    static let delete = "NOT_APPLICABLE"
    static let erase = "NOT_APPLICABLE"
    static let retention = "PROCESS_LIFETIME_ONLY"
    static let compatibility = "EXACT_REGISTRY_V2_RANGE"
    static let forwardFix = "REPLACE_BUNDLED_DECLARATION"
    static let interruption = "ZERO_OR_COMPLETE"
    static let idempotentReceipt = "CANONICAL_BYTES_ADOPTION"
}

enum InspectionPackageKernelDependencyBoundaryV2 {
    static let packageNeutral = true
    static let importsFeatureOrUITypes = false
    static let signSpecificBranchAllowed = false
    static let allowedFoundationDependency = "Foundation"
}

enum InspectionPackageAssetSemanticBoundaryV1 {
    static let assetIdentityOwner = "ASSET_ID"
    static let packageBindingChangesPhysicalIdentity = false
    static let packageBindingChangesSite = false
    static let packageBindingChangesPlacement = false
    static let packageBindingChangesAssetKindImplicitly = false
    static let multipleCompatiblePackageBindingsAllowed = true
    static let userAuthoredSemanticKindsAllowed = false
    static let structuralPolicyOwner = "V23-P03-C35"
    static let functionalRelationshipPolicyOwner = "V23-P03-C41"
}

/// Declarative C40 sidecar. It binds an exact package release to immutable
/// protocol/evaluator releases and cannot contain executable package content.
struct InspectionPackageAuthorityCriterionBindingV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let packageRelease: PackageReleaseIdentityV1
    let criterionIDs: [String]
    let measurementProtocolReleases: [MeasurementProtocolReleaseV1]
    let evaluatorDescriptors: [DerivedFactEvaluatorDescriptorV1]
    let declaresExecutableContent: Bool

    init(
        workspaceID: WorkspaceID,
        packageRelease: PackageReleaseIdentityV1,
        criterionIDs: [String],
        measurementProtocolReleases: [MeasurementProtocolReleaseV1],
        evaluatorDescriptors: [DerivedFactEvaluatorDescriptorV1],
        declaresExecutableContent: Bool = false
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.packageRelease = packageRelease
        self.criterionIDs = criterionIDs.sorted()
        self.measurementProtocolReleases = measurementProtocolReleases.sorted {
            $0.releaseID.uuidString < $1.releaseID.uuidString
        }
        self.evaluatorDescriptors = evaluatorDescriptors.sorted {
            $0.descriptorID.uuidString < $1.descriptorID.uuidString
        }
        self.declaresExecutableContent = declaresExecutableContent
        try validate()
    }

    func validate() throws {
        try AuthorityCriterionValidationV1.requireWorkspace(workspaceID)
        try AuthorityCriterionValidationV1.requireUnique(criterionIDs)
        try AuthorityCriterionValidationV1.requireUnique(
            measurementProtocolReleases.map(\.releaseID)
        )
        try AuthorityCriterionValidationV1.requireUnique(
            evaluatorDescriptors.map(\.descriptorID)
        )
        for criterionID in criterionIDs {
            try AuthorityCriterionValidationV1.requireText(criterionID, maximumBytes: 256)
        }
        try measurementProtocolReleases.forEach { try $0.validate() }
        try evaluatorDescriptors.forEach {
            try BundledDerivedFactEvaluatorRegistryV1.validate($0)
        }
        let evaluatorIDs = Set(evaluatorDescriptors.map(\.descriptorID))
        guard schemaVersion == Self.schemaVersion,
              !declaresExecutableContent,
              packageRelease.schemaVersion == InspectionPackageV2.schemaVersion,
              measurementProtocolReleases.allSatisfy({ $0.workspaceID == workspaceID }),
              evaluatorDescriptors.allSatisfy({ $0.workspaceID == workspaceID }),
              measurementProtocolReleases.allSatisfy({
                  evaluatorIDs.contains($0.evaluatorDescriptorID)
              }) else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
    }
}

/// Declarative C41 sidecar. Functional topology policy is immutable package
/// vocabulary and remains outside the package's executable/canonical V2 body.
struct InspectionPackageFunctionalRelationshipBindingV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let packageRelease: PackageReleaseIdentityV1
    let descriptorReleases: [FunctionalRelationshipTypeDescriptorV1]
    let declaresExecutableContent: Bool

    init(
        workspaceID: WorkspaceID,
        packageRelease: PackageReleaseIdentityV1,
        descriptorReleases: [FunctionalRelationshipTypeDescriptorV1],
        declaresExecutableContent: Bool = false
    ) throws {
        schemaVersion = Self.schemaVersion
        self.workspaceID = workspaceID
        self.packageRelease = packageRelease
        self.descriptorReleases = descriptorReleases.sorted {
            $0.descriptorReleaseID.uuidString < $1.descriptorReleaseID.uuidString
        }
        self.declaresExecutableContent = declaresExecutableContent
        try validate()
    }

    func validate() throws {
        try descriptorReleases.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              AssetSemanticValidationV1.validPackageRelease(packageRelease),
              descriptorReleases.count <= FunctionalRelationshipLimitsV1.maximumDescriptors,
              Set(descriptorReleases.map(\.descriptorReleaseID)).count == descriptorReleases.count,
              descriptorReleases.allSatisfy({
                $0.workspaceID == workspaceID && $0.packageRelease == packageRelease
              }),
              !declaresExecutableContent else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
    }
}

enum InspectionPackageValidationV2 {
    static func validIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        value == value.lowercased()
            && validToken(value, maximumBytes: maximumBytes)
    }

    static func validToken(_ value: String, maximumBytes: Int) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maximumBytes else { return false }
        return value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0) || $0 == 0x2D
                || $0 == 0x2E || $0 == 0x5F
        }
    }

    static func validText(_ value: String, maximumCharacters: Int) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty && value.count <= maximumCharacters
            && value == value.precomposedStringWithCanonicalMapping
            && !value.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
    }

    static func unique(_ values: [String]) -> Bool { Set(values).count == values.count }
}

private struct InspectionPackageDynamicCodingKeyV2: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum InspectionPackageClosedCodingV2 {
    static func requireExactKeys(
        _ decoder: any Decoder,
        expected: [String]
    ) throws {
        let values = try decoder.container(keyedBy: InspectionPackageDynamicCodingKeyV2.self)
        let observed = Set(values.allKeys.map(\.stringValue))
        guard observed == Set(expected), observed.count == expected.count else {
            throw InspectionPackageFailureV2.nonCanonicalData
        }
    }
}

// MARK: - C19 measurement package bindings

extension InspectionPackageAuthorityCriterionBindingV1 {
    /// Verifies that a protocol release is explicitly declared by the
    /// package's immutable C40 authority sidecar.
    func c19ValidateMeasurementProtocol(
        _ protocolRelease: MeasurementProtocolReleaseV1
    ) throws {
        try validate()
        try protocolRelease.validate()
        guard protocolRelease.workspaceID == workspaceID,
              measurementProtocolReleases.contains(protocolRelease) else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }

    /// Binds a C19 capture to the exact package release and workflow bytes;
    /// package declarations remain nonpersistent and contain no executable
    /// evaluator or import source.
    func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1,
        release: InspectionPackageReleaseV1,
        package: InspectionPackageV2
    ) throws {
        try validate()
        try release.validate()
        try package.validate()
        try capture.validate()
        guard packageRelease.packageID == package.packageID,
              packageRelease.schemaVersion == package.schemaVersion,
              packageRelease.contentVersion == package.contentVersion,
              release.packageID == package.packageID,
              release.packageContentVersion == package.contentVersion,
              capture.packageReleaseID == release.packageReleaseID,
              capture.workflowSHA256 == release.workflowSHA256,
              capture.workspaceID == workspaceID else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }
}

// MARK: - C20 reviewed-derivative package binding

extension InspectionPackageAuthorityCriterionBindingV1 {
    /// Validates a reviewed derivative at the package boundary without
    /// changing the immutable package/release declaration or making a
    /// privacy decision on behalf of the package. The projection helper is
    /// the sole owner of audience, policy, source, review, and freshness
    /// admission.
    func c20ValidateReviewedDerivative(
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date,
        release: InspectionPackageReleaseV1,
        package: InspectionPackageV2
    ) throws -> ContentReferenceV1 {
        try validate()
        try package.validate()
        try release.validate()
        let packageBytes = try InspectionPackageCanonicalCodecV2.encode(package)
        guard packageRelease.packageID == package.packageID,
              packageRelease.schemaVersion == package.schemaVersion,
              packageRelease.contentVersion == package.contentVersion,
              release.packageID == package.packageID,
              release.packageContentVersion == package.contentVersion,
              release.canonicalPackageBytes == packageBytes,
              release.packageSHA256 == KernelCanonicalHashV1.sha256(packageBytes) else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        guard workspaceID == policy.workspaceID,
              manifest.workspaceID == policy.workspaceID else {
            throw PrivacyTransformFailureV1.wrongWorkspace
        }
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}
