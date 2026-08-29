import CryptoKit
import Foundation

enum ReleaseExclusionSurfaceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case sourceMembership = "SOURCE_MEMBERSHIP"
    case targetDependencyGraph = "TARGET_DEPENDENCY_GRAPH"
    case compiledArchive = "COMPILED_ARCHIVE"
    case bundleResources = "BUNDLE_RESOURCES"
    case localizationCatalog = "LOCALIZATION_CATALOG"
    case packageRegistry = "PACKAGE_REGISTRY"
    case routeRegistry = "ROUTE_REGISTRY"
    case settingsRegistry = "SETTINGS_REGISTRY"
    case publicSymbols = "PUBLIC_SYMBOLS"
    case publicStrings = "PUBLIC_STRINGS"
    case screenshots = "SCREENSHOTS"
    case appStoreDrafts = "APP_STORE_DRAFTS"
    case runtimeSurface = "RUNTIME_SURFACE"

    var requiredEvidenceKind: ReleaseExclusionEvidenceKindV1 {
        switch self {
        case .sourceMembership: return .projectSourceMembership
        case .targetDependencyGraph: return .projectTargetDependencyGraph
        case .compiledArchive: return .releaseArchiveInventory
        case .bundleResources: return .releaseBundleResourceInventory
        case .localizationCatalog: return .repositoryLocalizationCatalog
        case .packageRegistry: return .repositoryPackageRegistry
        case .routeRegistry: return .repositoryRouteRegistry
        case .settingsRegistry: return .repositorySettingsRegistry
        case .publicSymbols: return .releasePublicSymbolTable
        case .publicStrings: return .releasePublicStringTable
        case .screenshots: return .releaseScreenshotInventory
        case .appStoreDrafts: return .appStoreDraftInventory
        case .runtimeSurface: return .releaseRuntimeEnumeration
        }
    }

    var requiredSourceIdentity: ReleaseExclusionEvidenceSourceV1 {
        switch self {
        case .sourceMembership, .targetDependencyGraph: return .repositoryProjectFile
        case .compiledArchive: return .releaseArchiveArtifact
        case .bundleResources: return .releaseAppBundle
        case .localizationCatalog: return .repositoryLocalizationCatalog
        case .packageRegistry: return .repositoryPackageRegistry
        case .routeRegistry: return .repositoryRouteRegistry
        case .settingsRegistry: return .repositorySettingsRegistry
        case .publicSymbols: return .releaseExecutableSymbolTable
        case .publicStrings: return .releaseExecutableStringTable
        case .screenshots: return .releaseScreenshotCapture
        case .appStoreDrafts: return .appStoreConnectDraftExport
        case .runtimeSurface: return .releaseRuntimeEnumeration
        }
    }

    var requiresNativeOrExternalEvidence: Bool {
        switch self {
        case .compiledArchive, .bundleResources, .publicSymbols, .publicStrings,
             .screenshots, .appStoreDrafts, .runtimeSurface:
            return true
        case .sourceMembership, .targetDependencyGraph, .localizationCatalog,
             .packageRegistry, .routeRegistry, .settingsRegistry:
            return false
        }
    }

    var requiredArtifactKind: ReleaseExclusionArtifactKindV1? {
        switch self {
        case .compiledArchive: return .xcarchive
        case .bundleResources: return .appBundle
        case .publicSymbols, .publicStrings, .screenshots, .runtimeSurface: return .executable
        case .sourceMembership, .targetDependencyGraph, .localizationCatalog,
             .packageRegistry, .routeRegistry, .settingsRegistry, .appStoreDrafts:
            return nil
        }
    }
}

enum ReleaseExclusionEvidenceKindV1: String, Codable, Hashable, Sendable {
    case projectSourceMembership = "PROJECT_SOURCE_MEMBERSHIP"
    case projectTargetDependencyGraph = "PROJECT_TARGET_DEPENDENCY_GRAPH"
    case releaseArchiveInventory = "RELEASE_ARCHIVE_INVENTORY"
    case releaseBundleResourceInventory = "RELEASE_BUNDLE_RESOURCE_INVENTORY"
    case repositoryLocalizationCatalog = "REPOSITORY_LOCALIZATION_CATALOG"
    case repositoryPackageRegistry = "REPOSITORY_PACKAGE_REGISTRY"
    case repositoryRouteRegistry = "REPOSITORY_ROUTE_REGISTRY"
    case repositorySettingsRegistry = "REPOSITORY_SETTINGS_REGISTRY"
    case releasePublicSymbolTable = "RELEASE_PUBLIC_SYMBOL_TABLE"
    case releasePublicStringTable = "RELEASE_PUBLIC_STRING_TABLE"
    case releaseScreenshotInventory = "RELEASE_SCREENSHOT_INVENTORY"
    case appStoreDraftInventory = "APP_STORE_DRAFT_INVENTORY"
    case releaseRuntimeEnumeration = "RELEASE_RUNTIME_ENUMERATION"
}

enum ReleaseExclusionEvidenceSourceV1: String, Codable, Hashable, Sendable {
    case repositoryProjectFile = "REPOSITORY_PROJECT_FILE"
    case releaseArchiveArtifact = "RELEASE_ARCHIVE_ARTIFACT"
    case releaseAppBundle = "RELEASE_APP_BUNDLE"
    case repositoryLocalizationCatalog = "REPOSITORY_LOCALIZATION_CATALOG"
    case repositoryPackageRegistry = "REPOSITORY_PACKAGE_REGISTRY"
    case repositoryRouteRegistry = "REPOSITORY_ROUTE_REGISTRY"
    case repositorySettingsRegistry = "REPOSITORY_SETTINGS_REGISTRY"
    case releaseExecutableSymbolTable = "RELEASE_EXECUTABLE_SYMBOL_TABLE"
    case releaseExecutableStringTable = "RELEASE_EXECUTABLE_STRING_TABLE"
    case releaseScreenshotCapture = "RELEASE_SCREENSHOT_CAPTURE"
    case appStoreConnectDraftExport = "APP_STORE_CONNECT_DRAFT_EXPORT"
    case releaseRuntimeEnumeration = "RELEASE_RUNTIME_ENUMERATION"
}

enum ReleaseExclusionDispositionV1: String, Codable, Hashable, Sendable {
    case provenAbsent = "PROVEN_ABSENT"
    case staticPendingNative = "STATIC_PENDING_NATIVE"
}

enum ReleaseExclusionArtifactKindV1: String, Codable, Hashable, Sendable {
    case xcarchive = "XCARCHIVE"
    case appBundle = "APP_BUNDLE"
    case executable = "EXECUTABLE"
}

struct ReleaseExclusionArtifactProvenanceV1: Codable, Equatable, Sendable {
    let artifactKind: ReleaseExclusionArtifactKindV1
    let releaseConfiguration: String
    let projectRelativePath: String
    let scheme: String
    let artifactIdentity: String
    let artifactByteCount: Int
    let artifactSHA256: String

    init(
        artifactKind: ReleaseExclusionArtifactKindV1,
        projectRelativePath: String,
        scheme: String,
        artifactIdentity: String,
        artifactBytes: Data
    ) throws {
        self.artifactKind = artifactKind
        releaseConfiguration = "Release"
        self.projectRelativePath = projectRelativePath
        self.scheme = scheme
        self.artifactIdentity = artifactIdentity
        artifactByteCount = artifactBytes.count
        artifactSHA256 = ReleaseExclusionDigestV1.sha256(artifactBytes)
        try validate()
    }

    func validate() throws {
        guard releaseConfiguration == "Release",
              ReleaseExclusionCanonicalPathV1.isCanonical(projectRelativePath),
              projectRelativePath.hasSuffix(".xcodeproj"),
              !scheme.isEmpty,
              scheme.utf8.count <= 128,
              !artifactIdentity.isEmpty,
              artifactIdentity.utf8.count <= 512,
              artifactByteCount > 0,
              ReleaseExclusionDigestV1.isNonPlaceholderSHA256(artifactSHA256)
        else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case artifactKind, releaseConfiguration, projectRelativePath, scheme
        case artifactIdentity, artifactByteCount, artifactSHA256
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        artifactKind = try values.decode(ReleaseExclusionArtifactKindV1.self, forKey: .artifactKind)
        releaseConfiguration = try values.decode(String.self, forKey: .releaseConfiguration)
        projectRelativePath = try values.decode(String.self, forKey: .projectRelativePath)
        scheme = try values.decode(String.self, forKey: .scheme)
        artifactIdentity = try values.decode(String.self, forKey: .artifactIdentity)
        artifactByteCount = try values.decode(Int.self, forKey: .artifactByteCount)
        artifactSHA256 = try values.decode(String.self, forKey: .artifactSHA256)
        try validate()
    }
}

struct ReleaseExclusionObservationV1: Codable, Equatable, Sendable {
    let surface: ReleaseExclusionSurfaceV1
    let evidenceKind: ReleaseExclusionEvidenceKindV1
    let sourceIdentity: ReleaseExclusionEvidenceSourceV1
    let repositoryRelativeInputs: [String]
    let disposition: ReleaseExclusionDispositionV1
    let artifactIdentity: String?
    let inspectedByteCount: Int?
    let inspectedSHA256: String?
    let releaseArtifactProvenance: ReleaseExclusionArtifactProvenanceV1?
    let forbiddenMatches: [String]

    init(
        surface: ReleaseExclusionSurfaceV1,
        sourceIdentity: ReleaseExclusionEvidenceSourceV1,
        repositoryRelativeInputs: [String],
        artifactIdentity: String,
        evidenceBytes: Data,
        releaseArtifactProvenance: ReleaseExclusionArtifactProvenanceV1? = nil,
        forbiddenMatches: [String]
    ) throws {
        self.surface = surface
        evidenceKind = surface.requiredEvidenceKind
        self.sourceIdentity = sourceIdentity
        self.repositoryRelativeInputs = repositoryRelativeInputs.sorted()
        disposition = .provenAbsent
        self.artifactIdentity = artifactIdentity
        inspectedByteCount = evidenceBytes.count
        inspectedSHA256 = ReleaseExclusionDigestV1.sha256(evidenceBytes)
        self.releaseArtifactProvenance = releaseArtifactProvenance
        self.forbiddenMatches = forbiddenMatches.sorted()
        try validate()
    }

    static func staticPendingNative(
        surface: ReleaseExclusionSurfaceV1,
        repositoryRelativeInputs: [String]
    ) throws -> ReleaseExclusionObservationV1 {
        guard surface.requiresNativeOrExternalEvidence else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
        return try ReleaseExclusionObservationV1(
            surface: surface,
            evidenceKind: surface.requiredEvidenceKind,
            sourceIdentity: surface.requiredSourceIdentity,
            repositoryRelativeInputs: repositoryRelativeInputs.sorted(),
            disposition: .staticPendingNative,
            artifactIdentity: nil,
            inspectedByteCount: nil,
            inspectedSHA256: nil,
            releaseArtifactProvenance: nil,
            forbiddenMatches: []
        )
    }

    var certifiesAbsence: Bool { disposition == .provenAbsent }

    func validate() throws {
        guard evidenceKind == surface.requiredEvidenceKind,
              sourceIdentity == surface.requiredSourceIdentity,
              !repositoryRelativeInputs.isEmpty,
              repositoryRelativeInputs == repositoryRelativeInputs.sorted(),
              Set(repositoryRelativeInputs).count == repositoryRelativeInputs.count,
              repositoryRelativeInputs.allSatisfy(ReleaseExclusionCanonicalPathV1.isCanonical),
              forbiddenMatches.isEmpty,
              forbiddenMatches == forbiddenMatches.sorted()
        else {
            throw CrossMarketConformanceFailureV1.releaseLeak(surface.rawValue)
        }

        switch disposition {
        case .provenAbsent:
            guard let artifactIdentity,
                  !artifactIdentity.isEmpty,
                  artifactIdentity.utf8.count <= 512,
                  let inspectedByteCount,
                  inspectedByteCount > 0,
                  let inspectedSHA256,
                  ReleaseExclusionDigestV1.isNonPlaceholderSHA256(inspectedSHA256)
            else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
            if let requiredArtifactKind = surface.requiredArtifactKind {
                guard let releaseArtifactProvenance,
                      releaseArtifactProvenance.artifactKind == requiredArtifactKind
                else {
                    throw CrossMarketConformanceFailureV1.invalidValue
                }
                try releaseArtifactProvenance.validate()
            } else {
                guard releaseArtifactProvenance == nil else {
                    throw CrossMarketConformanceFailureV1.invalidValue
                }
            }
        case .staticPendingNative:
            guard surface.requiresNativeOrExternalEvidence,
                  artifactIdentity == nil,
                  inspectedByteCount == nil,
                  inspectedSHA256 == nil,
                  releaseArtifactProvenance == nil
            else {
                throw CrossMarketConformanceFailureV1.invalidValue
            }
        }
    }

    private init(
        surface: ReleaseExclusionSurfaceV1,
        evidenceKind: ReleaseExclusionEvidenceKindV1,
        sourceIdentity: ReleaseExclusionEvidenceSourceV1,
        repositoryRelativeInputs: [String],
        disposition: ReleaseExclusionDispositionV1,
        artifactIdentity: String?,
        inspectedByteCount: Int?,
        inspectedSHA256: String?,
        releaseArtifactProvenance: ReleaseExclusionArtifactProvenanceV1?,
        forbiddenMatches: [String]
    ) throws {
        self.surface = surface
        self.evidenceKind = evidenceKind
        self.sourceIdentity = sourceIdentity
        self.repositoryRelativeInputs = repositoryRelativeInputs
        self.disposition = disposition
        self.artifactIdentity = artifactIdentity
        self.inspectedByteCount = inspectedByteCount
        self.inspectedSHA256 = inspectedSHA256
        self.releaseArtifactProvenance = releaseArtifactProvenance
        self.forbiddenMatches = forbiddenMatches
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case surface, evidenceKind, sourceIdentity, repositoryRelativeInputs, disposition
        case artifactIdentity, inspectedByteCount, inspectedSHA256
        case releaseArtifactProvenance, forbiddenMatches
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            surface: values.decode(ReleaseExclusionSurfaceV1.self, forKey: .surface),
            evidenceKind: values.decode(ReleaseExclusionEvidenceKindV1.self, forKey: .evidenceKind),
            sourceIdentity: values.decode(ReleaseExclusionEvidenceSourceV1.self, forKey: .sourceIdentity),
            repositoryRelativeInputs: values.decode([String].self, forKey: .repositoryRelativeInputs),
            disposition: values.decode(ReleaseExclusionDispositionV1.self, forKey: .disposition),
            artifactIdentity: values.decodeIfPresent(String.self, forKey: .artifactIdentity),
            inspectedByteCount: values.decodeIfPresent(Int.self, forKey: .inspectedByteCount),
            inspectedSHA256: values.decodeIfPresent(String.self, forKey: .inspectedSHA256),
            releaseArtifactProvenance: values.decodeIfPresent(
                ReleaseExclusionArtifactProvenanceV1.self,
                forKey: .releaseArtifactProvenance
            ),
            forbiddenMatches: values.decode([String].self, forKey: .forbiddenMatches)
        )
    }
}

struct ReleaseExclusionReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let requiredTestSupportPaths = [
        "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/CompositeAreaSafetyArchetypeV1.swift",
        "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ControllerZoneDistributionArchetypeV1.swift",
        "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ModelBasedConformanceContractsV1.swift",
        "FieldEvidenceAppTests/TestSupport/CrossMarketConformance/ReleaseExclusionReceiptV1.swift"
    ]
    static let forbiddenReleaseSymbols = [
        "CompositeAreaSafetyArchetypeV1", "ControllerZoneDistributionArchetypeV1",
        "ModelOperationV1", "ModelRunReceiptV1", "DeterministicRegressionPromotionReceiptV1",
        "ModelConformanceRunnerV1", "SeededModelGeneratorV1", "ReleaseExclusionReceiptV1"
    ]
    static let requiredSurfaces = ReleaseExclusionSurfaceV1.allCases.sorted {
        $0.rawValue < $1.rawValue
    }

    let schemaVersion: Int
    let releaseConfiguration: String
    let testSupportPaths: [String]
    let forbiddenReleaseSymbols: [String]
    let observations: [ReleaseExclusionObservationV1]
    let hostileFixtureCount: Int
    let generatedScratchRemoved: Bool
    let receiptSHA256: String

    init(
        releaseConfiguration: String = "Release",
        observations: [ReleaseExclusionObservationV1],
        hostileFixtureCount: Int,
        generatedScratchRemoved: Bool
    ) throws {
        schemaVersion = Self.schemaVersion
        self.releaseConfiguration = releaseConfiguration
        testSupportPaths = Self.requiredTestSupportPaths
        forbiddenReleaseSymbols = Self.forbiddenReleaseSymbols
        self.observations = observations.sorted { $0.surface.rawValue < $1.surface.rawValue }
        self.hostileFixtureCount = hostileFixtureCount
        self.generatedScratchRemoved = generatedScratchRemoved
        receiptSHA256 = try CrossMarketCanonicalV1.sha256(
            Basis(
                schemaVersion: Self.schemaVersion,
                releaseConfiguration: releaseConfiguration,
                testSupportPaths: Self.requiredTestSupportPaths,
                forbiddenReleaseSymbols: Self.forbiddenReleaseSymbols,
                observations: self.observations,
                hostileFixtureCount: hostileFixtureCount,
                generatedScratchRemoved: generatedScratchRemoved
            )
        )
        try validate()
    }

    var isComplete: Bool {
        observations.count == Self.requiredSurfaces.count
            && observations.allSatisfy(\.certifiesAbsence)
    }

    var certifiesReleaseExclusion: Bool { isComplete }

    func validate() throws {
        try observations.forEach { try $0.validate() }
        guard schemaVersion == Self.schemaVersion,
              releaseConfiguration == "Release",
              testSupportPaths == Self.requiredTestSupportPaths,
              forbiddenReleaseSymbols == Self.forbiddenReleaseSymbols,
              observations.count == Self.requiredSurfaces.count,
              observations.map(\.surface) == Self.requiredSurfaces,
              Set(observations.map(\.surface)).count == Self.requiredSurfaces.count,
              hostileFixtureCount >= 0,
              generatedScratchRemoved,
              ReleaseExclusionDigestV1.isNonPlaceholderSHA256(receiptSHA256),
              receiptSHA256 == (try CrossMarketCanonicalV1.sha256(basis))
        else {
            throw CrossMarketConformanceFailureV1.invalidValue
        }
    }

    private var basis: Basis {
        .init(
            schemaVersion: schemaVersion,
            releaseConfiguration: releaseConfiguration,
            testSupportPaths: testSupportPaths,
            forbiddenReleaseSymbols: forbiddenReleaseSymbols,
            observations: observations,
            hostileFixtureCount: hostileFixtureCount,
            generatedScratchRemoved: generatedScratchRemoved
        )
    }

    private struct Basis: Codable {
        let schemaVersion: Int
        let releaseConfiguration: String
        let testSupportPaths: [String]
        let forbiddenReleaseSymbols: [String]
        let observations: [ReleaseExclusionObservationV1]
        let hostileFixtureCount: Int
        let generatedScratchRemoved: Bool
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, releaseConfiguration, testSupportPaths, forbiddenReleaseSymbols
        case observations, hostileFixtureCount, generatedScratchRemoved, receiptSHA256
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        releaseConfiguration = try values.decode(String.self, forKey: .releaseConfiguration)
        testSupportPaths = try values.decode([String].self, forKey: .testSupportPaths)
        forbiddenReleaseSymbols = try values.decode([String].self, forKey: .forbiddenReleaseSymbols)
        observations = try values.decode([ReleaseExclusionObservationV1].self, forKey: .observations)
        hostileFixtureCount = try values.decode(Int.self, forKey: .hostileFixtureCount)
        generatedScratchRemoved = try values.decode(Bool.self, forKey: .generatedScratchRemoved)
        receiptSHA256 = try values.decode(String.self, forKey: .receiptSHA256)
        try validate()
    }
}

private enum ReleaseExclusionDigestV1 {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isNonPlaceholderSHA256(_ value: String) -> Bool {
        CrossMarketCanonicalV1.isSHA256(value) && Set(value).count > 1
    }
}

private enum ReleaseExclusionCanonicalPathV1 {
    static func isCanonical(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 512,
              value == value.precomposedStringWithCanonicalMapping,
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.contains(":"),
              !value.contains("\0")
        else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            component != "." && component != ".." && !component.isEmpty
        }
    }
}
