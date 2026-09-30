import CryptoKit
import Foundation

enum CompatibilityCanonicalV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch {
            throw CompatibilityContractErrorV1.invalidCanonicalValue
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            let value = try JSONDecoder().decode(type, from: data)
            guard try encode(value) == data else {
                throw CompatibilityContractErrorV1.invalidCanonicalValue
            }
            return value
        } catch let error as CompatibilityContractErrorV1 {
            throw error
        } catch {
            throw CompatibilityContractErrorV1.invalidCanonicalValue
        }
    }

    static func validSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
            }
    }

    static func validGitObjectID(_ value: String) -> Bool {
        value.utf8.count == 40
            && value.utf8.allSatisfy { byte in
                (0x30...0x39).contains(byte) || (0x61...0x66).contains(byte)
            }
    }

    static func validToken(_ value: String, maximumUTF8ByteCount: Int = 128) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= maximumUTF8ByteCount,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (
                CharacterSet.alphanumerics.contains(scalar)
                    || "._:/+-".unicodeScalars.contains(scalar)
            )
        }
    }

    static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              value.utf8.count <= 512,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.hasPrefix("/"),
              !value.hasSuffix("/"),
              !value.contains("\\"),
              !value.contains(":"),
              !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { $0 != "." && $0 != ".." && !$0.isEmpty }
    }
}

enum CompatibilityCaseKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case positive
    case hostile
    case interruption
    case recovery
}

enum CompatibilityFixtureSourceV1: String, Codable, Sendable {
    case checkedFixture = "checked_fixture"
    case deterministicGenerator = "deterministic_generator"
}

enum CompatibilityExpectedDispositionV1: String, Codable, Sendable {
    case succeeds
    case failsClosedUnsupportedVersion = "fails_closed_unsupported_version"
    case failsClosedInvalidData = "fails_closed_invalid_data"
    case resumesIdempotently = "resumes_idempotently"
}

struct CompatibilityCaseManifestV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let caseID: String
    let family: CompatibilityArtifactFamilyV1
    let artifactVersion: String
    let kind: CompatibilityCaseKindV1
    let artifactRelativePath: String
    let artifactSHA256: String
    let normalizedExpectedSHA256: String?
    let source: CompatibilityFixtureSourceV1
    let generatorVersion: String?
    let generatorSeed: UInt64?
    let dependencyFamilies: [CompatibilityArtifactFamilyV1]
    let scenarioTags: [String]
    let expectedDisposition: CompatibilityExpectedDispositionV1
    let synthetic: Bool
    let licenseIdentifier: String
    let containsCustomerData: Bool
    let containsSecrets: Bool
    let immutable: Bool
    let representative: Bool

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        caseID: String,
        family: CompatibilityArtifactFamilyV1,
        artifactVersion: String,
        kind: CompatibilityCaseKindV1,
        artifactRelativePath: String,
        artifactSHA256: String,
        normalizedExpectedSHA256: String? = nil,
        source: CompatibilityFixtureSourceV1,
        generatorVersion: String? = nil,
        generatorSeed: UInt64? = nil,
        dependencyFamilies: [CompatibilityArtifactFamilyV1] = [],
        scenarioTags: [String],
        expectedDisposition: CompatibilityExpectedDispositionV1,
        synthetic: Bool = true,
        licenseIdentifier: String,
        containsCustomerData: Bool = false,
        containsSecrets: Bool = false,
        immutable: Bool = true,
        representative: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.caseID = caseID
        self.family = family
        self.artifactVersion = artifactVersion
        self.kind = kind
        self.artifactRelativePath = artifactRelativePath
        self.artifactSHA256 = artifactSHA256
        self.normalizedExpectedSHA256 = normalizedExpectedSHA256
        self.source = source
        self.generatorVersion = generatorVersion
        self.generatorSeed = generatorSeed
        self.dependencyFamilies = dependencyFamilies
        self.scenarioTags = scenarioTags
        self.expectedDisposition = expectedDisposition
        self.synthetic = synthetic
        self.licenseIdentifier = licenseIdentifier
        self.containsCustomerData = containsCustomerData
        self.containsSecrets = containsSecrets
        self.immutable = immutable
        self.representative = representative
    }

    func validate(against dataManifest: DataCompatibilityManifestV1) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              CompatibilityCanonicalV1.validToken(caseID),
              CompatibilityCanonicalV1.validToken(artifactVersion, maximumUTF8ByteCount: 160),
              CompatibilityCanonicalV1.validRelativePath(artifactRelativePath),
              CompatibilityCanonicalV1.validSHA256(artifactSHA256),
              normalizedExpectedSHA256.map(CompatibilityCanonicalV1.validSHA256) ?? true,
              synthetic,
              !containsCustomerData,
              !containsSecrets,
              immutable,
              CompatibilityCanonicalV1.validToken(licenseIdentifier),
              dependencyFamilies == dependencyFamilies.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(dependencyFamilies).count == dependencyFamilies.count,
              scenarioTags == scenarioTags.sorted(),
              Set(scenarioTags).count == scenarioTags.count,
              !scenarioTags.isEmpty,
              scenarioTags.allSatisfy({ CompatibilityCanonicalV1.validToken($0) }) else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        switch source {
        case .checkedFixture:
            guard generatorVersion == nil, generatorSeed == nil else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        case .deterministicGenerator:
            guard generatorVersion.map({ CompatibilityCanonicalV1.validToken($0) }) == true,
                  generatorSeed != nil else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        }
        let path = try dataManifest.path(for: family)
        guard path.readableVersions.contains(artifactVersion) else {
            if kind == .hostile,
               expectedDisposition == .failsClosedUnsupportedVersion {
                return
            }
            throw CompatibilityContractErrorV1.unsupportedVersion
        }
        switch kind {
        case .positive:
            guard expectedDisposition == .succeeds else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        case .hostile:
            guard expectedDisposition == .failsClosedInvalidData
                    || expectedDisposition == .failsClosedUnsupportedVersion else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        case .interruption, .recovery:
            guard expectedDisposition == .resumesIdempotently else {
                throw CompatibilityContractErrorV1.invalidCorpus
            }
        }
    }

    func canonicalData() throws -> Data {
        try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(
        _ data: Data,
        against dataManifest: DataCompatibilityManifestV1
    ) throws -> CompatibilityCaseManifestV1 {
        let value: CompatibilityCaseManifestV1 = try CompatibilityCanonicalV1.decode(
            CompatibilityCaseManifestV1.self,
            from: data
        )
        try value.validate(against: dataManifest)
        return value
    }
}

enum CompatibilityCorpusSealStateV1: String, Codable, Sendable {
    case provisionalPrePublic = "provisional_pre_public"
    case firstPublic = "first_public"
}

struct CompatibilityCorpusManifestV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let corpusID: String
    let sealState: CompatibilityCorpusSealStateV1
    let policyManifestSHA256: String
    let cases: [CompatibilityCaseManifestV1]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        corpusID: String,
        sealState: CompatibilityCorpusSealStateV1 = .provisionalPrePublic,
        policyManifestSHA256: String,
        cases: [CompatibilityCaseManifestV1]
    ) {
        self.schemaVersion = schemaVersion
        self.corpusID = corpusID
        self.sealState = sealState
        self.policyManifestSHA256 = policyManifestSHA256
        self.cases = cases
    }

    func validate(
        against dataManifest: DataCompatibilityManifestV1,
        previous: CompatibilityCorpusManifestV1? = nil
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              CompatibilityCanonicalV1.validToken(corpusID),
              CompatibilityCanonicalV1.validSHA256(policyManifestSHA256),
              policyManifestSHA256 == (try dataManifest.canonicalSHA256()),
              !cases.isEmpty,
              cases == cases.sorted(by: { $0.caseID < $1.caseID }),
              Set(cases.map(\.caseID)).count == cases.count,
              cases.contains(where: \.representative) else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        try cases.forEach { try $0.validate(against: dataManifest) }
        guard Set(cases.map(\.kind)) == Set(CompatibilityCaseKindV1.allCases) else {
            throw CompatibilityContractErrorV1.invalidCorpus
        }
        for path in dataManifest.supportedUpgradePaths {
            for version in path.readableVersions where !validatesEnrollment(
                family: path.family,
                version: version
            ) {
                throw CompatibilityContractErrorV1.missingCorpusEnrollment
            }
        }
        if let previous {
            try validateExtension(of: previous)
        }
    }

    func validateExtension(of previous: CompatibilityCorpusManifestV1) throws {
        let currentByID = Dictionary(uniqueKeysWithValues: cases.map { ($0.caseID, $0) })
        for oldCase in previous.cases {
            guard let current = currentByID[oldCase.caseID] else {
                throw CompatibilityContractErrorV1.releasedCaseRemoved
            }
            guard try current.canonicalSHA256() == oldCase.canonicalSHA256() else {
                throw CompatibilityContractErrorV1.quarantinedCaseIDReuse
            }
        }
    }

    func validatesEnrollment(family: CompatibilityArtifactFamilyV1, version: String) -> Bool {
        cases.contains {
            $0.family == family && $0.artifactVersion == version && $0.kind == .positive
        }
    }

    func canonicalData() throws -> Data {
        try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(
        _ data: Data,
        against dataManifest: DataCompatibilityManifestV1,
        previous: CompatibilityCorpusManifestV1? = nil
    ) throws -> CompatibilityCorpusManifestV1 {
        let value: CompatibilityCorpusManifestV1 = try CompatibilityCanonicalV1.decode(
            CompatibilityCorpusManifestV1.self,
            from: data
        )
        try value.validate(against: dataManifest, previous: previous)
        return value
    }
}

enum CompatibilityRunSelectionV1: String, Codable, Sendable {
    case representativeSentinel = "representative_sentinel"
    case dependencyClosure = "dependency_closure"
    case fullCorpus = "full_corpus"
}

enum CompatibilityRunModeV1: String, Codable, Sendable {
    case acceptingFailFast = "accepting_fail_fast"
    case diagnosticContinue = "diagnostic_continue"
}

enum CompatibilityReplayDispositionV1: String, Codable, Sendable {
    case differentRun = "different_run"
    case idempotentReplay = "idempotent_replay"
}

enum CompatibilityCaseRunOutcomeV1: String, Codable, Sendable {
    case passed
    case failed
    case interrupted
}

struct CompatibilityCaseRunResultV1: Codable, Equatable, Sendable {
    let caseID: String
    let caseManifestSHA256: String
    let outcome: CompatibilityCaseRunOutcomeV1
    let normalizedOutputSHA256: String?
    let failureCode: String?

    init(
        caseID: String,
        caseManifestSHA256: String,
        outcome: CompatibilityCaseRunOutcomeV1,
        normalizedOutputSHA256: String? = nil,
        failureCode: String? = nil
    ) {
        self.caseID = caseID
        self.caseManifestSHA256 = caseManifestSHA256
        self.outcome = outcome
        self.normalizedOutputSHA256 = normalizedOutputSHA256
        self.failureCode = failureCode
    }

    func validate() throws {
        guard CompatibilityCanonicalV1.validToken(caseID),
              CompatibilityCanonicalV1.validSHA256(caseManifestSHA256),
              normalizedOutputSHA256.map(CompatibilityCanonicalV1.validSHA256) ?? true else {
            throw CompatibilityContractErrorV1.invalidRunReceipt
        }
        switch outcome {
        case .passed:
            guard normalizedOutputSHA256 != nil,
                  failureCode == nil else {
                throw CompatibilityContractErrorV1.invalidRunReceipt
            }
        case .failed, .interrupted:
            guard failureCode.map({ CompatibilityCanonicalV1.validToken($0) }) == true else {
                throw CompatibilityContractErrorV1.invalidRunReceipt
            }
        }
    }
}

struct CompatibilityRunReceiptV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let runID: String
    let corpusSHA256: String
    let selection: CompatibilityRunSelectionV1
    let mode: CompatibilityRunModeV1
    let affectedFamilies: [CompatibilityArtifactFamilyV1]
    let selectedCaseIDs: [String]
    let results: [CompatibilityCaseRunResultV1]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        runID: String,
        corpusSHA256: String,
        selection: CompatibilityRunSelectionV1,
        mode: CompatibilityRunModeV1,
        affectedFamilies: [CompatibilityArtifactFamilyV1] = [],
        selectedCaseIDs: [String],
        results: [CompatibilityCaseRunResultV1]
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.corpusSHA256 = corpusSHA256
        self.selection = selection
        self.mode = mode
        self.affectedFamilies = affectedFamilies
        self.selectedCaseIDs = selectedCaseIDs
        self.results = results
    }

    var isAccepting: Bool {
        mode == .acceptingFailFast
            && results.count == selectedCaseIDs.count
            && results.allSatisfy {
                $0.outcome == .passed && $0.normalizedOutputSHA256 != nil
            }
    }

    func validate(against corpus: CompatibilityCorpusManifestV1) throws {
        let validSelectionBinding: Bool
        switch selection {
        case .dependencyClosure:
            validSelectionBinding = !affectedFamilies.isEmpty
        case .representativeSentinel, .fullCorpus:
            validSelectionBinding = affectedFamilies.isEmpty
        }
        guard schemaVersion == Self.currentSchemaVersion,
              CompatibilityCanonicalV1.validToken(runID),
              CompatibilityCanonicalV1.validSHA256(corpusSHA256),
              corpusSHA256 == (try corpus.canonicalSHA256()),
              validSelectionBinding,
              affectedFamilies == affectedFamilies.sorted(by: { $0.rawValue < $1.rawValue }),
              Set(affectedFamilies).count == affectedFamilies.count,
              selectedCaseIDs == corpus.caseIDs(for: selection, affectedFamilies: affectedFamilies),
              results.map(\.caseID) == Array(selectedCaseIDs.prefix(results.count)) else {
            throw CompatibilityContractErrorV1.invalidRunReceipt
        }
        let manifestByID = Dictionary(uniqueKeysWithValues: corpus.cases.map { ($0.caseID, $0) })
        for result in results {
            try result.validate()
            guard let manifest = manifestByID[result.caseID],
                  result.caseManifestSHA256 == (try manifest.canonicalSHA256()),
                  result.outcome != .passed
                    || result.normalizedOutputSHA256
                        == (manifest.normalizedExpectedSHA256 ?? manifest.artifactSHA256) else {
                throw CompatibilityContractErrorV1.invalidRunReceipt
            }
        }
        switch mode {
        case .acceptingFailFast:
            let nonpassing = results.filter { $0.outcome != .passed }
            guard nonpassing.count <= 1,
                  nonpassing.isEmpty || results.last?.outcome != .passed,
                  nonpassing.isEmpty || results.last?.outcome == nonpassing[0].outcome else {
                throw CompatibilityContractErrorV1.invalidRunReceipt
            }
        case .diagnosticContinue:
            guard results.count == selectedCaseIDs.count else {
                throw CompatibilityContractErrorV1.invalidRunReceipt
            }
        }
    }

    func requireAccepting(against corpus: CompatibilityCorpusManifestV1) throws {
        try validate(against: corpus)
        guard isAccepting else { throw CompatibilityContractErrorV1.invalidRunReceipt }
    }

    func replayDisposition(comparedTo previous: CompatibilityRunReceiptV1) throws
        -> CompatibilityReplayDispositionV1 {
        guard runID == previous.runID else { return .differentRun }
        guard try canonicalSHA256() == previous.canonicalSHA256() else {
            throw CompatibilityContractErrorV1.quarantinedRunIDReuse
        }
        return .idempotentReplay
    }

    func canonicalData() throws -> Data {
        try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(
        _ data: Data,
        against corpus: CompatibilityCorpusManifestV1
    ) throws -> CompatibilityRunReceiptV1 {
        let value: CompatibilityRunReceiptV1 = try CompatibilityCanonicalV1.decode(
            CompatibilityRunReceiptV1.self,
            from: data
        )
        try value.validate(against: corpus)
        return value
    }
}

enum ReleaseSeedSealOwnerV1: String, Codable, Sendable {
    case v23P01C07Provisional = "V23-P01-C07"
    case v23P05C01FirstPublic = "V23-P05-C01"
}

struct ReleaseSeedCorpusSealV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let state: CompatibilityCorpusSealStateV1
    let owner: ReleaseSeedSealOwnerV1
    let corpusID: String
    let corpusSHA256: String
    let policyManifestSHA256: String

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        state: CompatibilityCorpusSealStateV1,
        owner: ReleaseSeedSealOwnerV1,
        corpusID: String,
        corpusSHA256: String,
        policyManifestSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.owner = owner
        self.corpusID = corpusID
        self.corpusSHA256 = corpusSHA256
        self.policyManifestSHA256 = policyManifestSHA256
    }

    func validate(corpus: CompatibilityCorpusManifestV1) throws {
        let expectedOwner: ReleaseSeedSealOwnerV1 = state == .provisionalPrePublic
            ? .v23P01C07Provisional
            : .v23P05C01FirstPublic
        guard schemaVersion == Self.currentSchemaVersion,
              owner == expectedOwner,
              corpus.sealState == state,
              corpusID == corpus.corpusID,
              CompatibilityCanonicalV1.validSHA256(corpusSHA256),
              corpusSHA256 == (try corpus.canonicalSHA256()),
              policyManifestSHA256 == corpus.policyManifestSHA256 else {
            throw CompatibilityContractErrorV1.invalidSeedSeal
        }
    }

    static func decodeCanonical(
        _ data: Data,
        corpus: CompatibilityCorpusManifestV1
    ) throws -> ReleaseSeedCorpusSealV1 {
        let value: ReleaseSeedCorpusSealV1 = try CompatibilityCanonicalV1.decode(
            ReleaseSeedCorpusSealV1.self,
            from: data
        )
        try value.validate(corpus: corpus)
        return value
    }
}

struct ReleaseSeedCorpusV1: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let manifest: CompatibilityCorpusManifestV1
    let seal: ReleaseSeedCorpusSealV1
    let syntheticOnly: Bool
    let licensedFixturesOnly: Bool
    let containsCustomerData: Bool
    let containsSecrets: Bool

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        manifest: CompatibilityCorpusManifestV1,
        seal: ReleaseSeedCorpusSealV1,
        syntheticOnly: Bool = true,
        licensedFixturesOnly: Bool = true,
        containsCustomerData: Bool = false,
        containsSecrets: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.manifest = manifest
        self.seal = seal
        self.syntheticOnly = syntheticOnly
        self.licensedFixturesOnly = licensedFixturesOnly
        self.containsCustomerData = containsCustomerData
        self.containsSecrets = containsSecrets
    }

    func validate(against policy: ReleasedDataCompatibilityPolicyV1) throws {
        guard schemaVersion == Self.currentSchemaVersion,
              syntheticOnly,
              licensedFixturesOnly,
              !containsCustomerData,
              !containsSecrets else {
            throw CompatibilityContractErrorV1.invalidSeedSeal
        }
        try policy.validate()
        try manifest.validate(against: policy.dataManifest)
        try seal.validate(corpus: manifest)
    }

    func canonicalData() throws -> Data {
        try CompatibilityCanonicalV1.encode(self)
    }

    func canonicalSHA256() throws -> String {
        CompatibilityCanonicalV1.sha256(try canonicalData())
    }

    static func decodeCanonical(
        _ data: Data,
        against policy: ReleasedDataCompatibilityPolicyV1
    ) throws -> ReleaseSeedCorpusV1 {
        let value: ReleaseSeedCorpusV1 = try CompatibilityCanonicalV1.decode(
            ReleaseSeedCorpusV1.self,
            from: data
        )
        try value.validate(against: policy)
        return value
    }
}

extension CompatibilityCorpusManifestV1 {
    func caseIDs(
        for selection: CompatibilityRunSelectionV1,
        affectedFamilies: [CompatibilityArtifactFamilyV1] = []
    ) -> [String] {
        switch selection {
        case .representativeSentinel:
            return cases.filter(\.representative).map(\.caseID)
        case .fullCorpus:
            return cases.map(\.caseID)
        case .dependencyClosure:
            var includedFamilies = Set(affectedFamilies)
            var changed = true
            while changed {
                changed = false
                for item in cases where includedFamilies.contains(item.family)
                    || !includedFamilies.isDisjoint(with: item.dependencyFamilies) {
                    if includedFamilies.insert(item.family).inserted { changed = true }
                    for dependency in item.dependencyFamilies {
                        if includedFamilies.insert(dependency).inserted { changed = true }
                    }
                }
            }
            return cases.filter { item in
                includedFamilies.contains(item.family)
                    || !includedFamilies.isDisjoint(with: item.dependencyFamilies)
            }.map(\.caseID)
        }
    }
}
