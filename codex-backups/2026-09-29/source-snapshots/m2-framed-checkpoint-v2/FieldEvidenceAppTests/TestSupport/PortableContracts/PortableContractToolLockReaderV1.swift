import Foundation
import CryptoKit

struct PortableContractValidatorToolV1: Decodable, Equatable, Sendable {
    let toolID: String; let implementationLanguage: String; let minimumPython: String
    let stdlibOnly: Bool; let entryPoint: String; let lockChecker: String; let networkPolicy: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case toolID, implementationLanguage, minimumPython, stdlibOnly, entryPoint, lockChecker, networkPolicy }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        toolID = try c.decode(String.self, forKey: .toolID); implementationLanguage = try c.decode(String.self, forKey: .implementationLanguage)
        minimumPython = try c.decode(String.self, forKey: .minimumPython); stdlibOnly = try c.decode(Bool.self, forKey: .stdlibOnly)
        entryPoint = try c.decode(String.self, forKey: .entryPoint); lockChecker = try c.decode(String.self, forKey: .lockChecker)
        networkPolicy = try c.decode(String.self, forKey: .networkPolicy)
    }
}

struct PortableContractMetaSchemaRegistrationV1: Decodable, Equatable, Sendable {
    let uri: String; let path: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case uri, path }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decode(String.self, forKey: .uri); path = try c.decode(String.self, forKey: .path)
    }
}

struct PortableContractOfficialMetaSchemaV1: Decodable, Equatable, Sendable {
    let draft: String; let rootURI: String; let registry: [PortableContractMetaSchemaRegistrationV1]
    private enum CodingKeys: String, CodingKey, CaseIterable { case draft, rootURI, registry }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        draft = try c.decode(String.self, forKey: .draft); rootURI = try c.decode(String.self, forKey: .rootURI)
        registry = try c.decode([PortableContractMetaSchemaRegistrationV1].self, forKey: .registry)
    }
}

struct PortableContractLockedFileV1: Decodable, Equatable, Sendable {
    let path: String; let role: String; let byteCount: Int; let sha256: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case path, role, byteCount, sha256 }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path); role = try c.decode(String.self, forKey: .role)
        byteCount = try c.decode(Int.self, forKey: .byteCount); sha256 = try c.decode(String.self, forKey: .sha256)
    }
}

struct PortableContractInventoryPolicyV1: Decodable, Equatable, Sendable {
    let lockedFileCount: Int; let selfHashDisposition: String
    let unexpectedOwnedFileDisposition: String; let lineEndingPolicy: String
    private enum CodingKeys: String, CodingKey, CaseIterable { case lockedFileCount, selfHashDisposition, unexpectedOwnedFileDisposition, lineEndingPolicy }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        lockedFileCount = try c.decode(Int.self, forKey: .lockedFileCount); selfHashDisposition = try c.decode(String.self, forKey: .selfHashDisposition)
        unexpectedOwnedFileDisposition = try c.decode(String.self, forKey: .unexpectedOwnedFileDisposition); lineEndingPolicy = try c.decode(String.self, forKey: .lineEndingPolicy)
    }
}

struct PortableContractReferencePolicyV1: Decodable, Equatable, Sendable {
    let remoteResolution: String; let allowedAbsoluteURIs: [String]
    let allowedRelativeReferencePrefixes: [String]
    private enum CodingKeys: String, CodingKey, CaseIterable { case remoteResolution, allowedAbsoluteURIs, allowedRelativeReferencePrefixes }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        remoteResolution = try c.decode(String.self, forKey: .remoteResolution)
        allowedAbsoluteURIs = try c.decode([String].self, forKey: .allowedAbsoluteURIs)
        allowedRelativeReferencePrefixes = try c.decode([String].self, forKey: .allowedRelativeReferencePrefixes)
    }
}

struct PortableContractToolLockV1: Decodable, Equatable, Sendable {
    static let expectedSchema = "PortableContractValidatorLockV1"
    let schema: String; let schemaVersion: Int; let tool: PortableContractValidatorToolV1
    let officialMetaSchema: PortableContractOfficialMetaSchemaV1; let files: [PortableContractLockedFileV1]
    let inventoryPolicy: PortableContractInventoryPolicyV1; let referencePolicy: PortableContractReferencePolicyV1
    var networkFetchAllowed: Bool { tool.networkPolicy != "DENY_ALL" }
    var distributionSHA256: String { files.first(where: { $0.path == tool.entryPoint })?.sha256 ?? "" }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, schemaVersion, tool, officialMetaSchema, files, inventoryPolicy, referencePolicy }
    init(from decoder: any Decoder) throws {
        try StrictPortableContractCodingV1.requireExactKeys(decoder, CodingKeys.self); let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(String.self, forKey: .schema); schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        tool = try c.decode(PortableContractValidatorToolV1.self, forKey: .tool); officialMetaSchema = try c.decode(PortableContractOfficialMetaSchemaV1.self, forKey: .officialMetaSchema)
        files = try c.decode([PortableContractLockedFileV1].self, forKey: .files); inventoryPolicy = try c.decode(PortableContractInventoryPolicyV1.self, forKey: .inventoryPolicy)
        referencePolicy = try c.decode(PortableContractReferencePolicyV1.self, forKey: .referencePolicy); try validate()
    }
    func validate() throws {
        let roles: Set<String> = ["VALIDATOR_IMPLEMENTATION", "RUNNER", "LOCK_CHECKER", "OFFICIAL_META_SCHEMA"]
        let paths = files.map(\.path), registryPaths = officialMetaSchema.registry.map(\.path), registryURIs = officialMetaSchema.registry.map(\.uri)
        guard schema == Self.expectedSchema, schemaVersion == 1,
              tool.toolID == "ASSETROUNDS_PYTHON_JSON_SCHEMA_DRAFT_2020_12_V1", tool.implementationLanguage == "PYTHON_STDLIB",
              tool.minimumPython == "3.11", tool.stdlibOnly,
              tool.entryPoint == "Scripts/v21-contracts/run-portable-contracts.py", tool.lockChecker == "Scripts/v21-contracts/check-portable-contract-lock.py", tool.networkPolicy == "DENY_ALL",
              officialMetaSchema.draft == "JSON_SCHEMA_DRAFT_2020_12", officialMetaSchema.rootURI == "https://json-schema.org/draft/2020-12/schema",
              officialMetaSchema.registry.count == 8, Set(registryPaths).count == registryPaths.count, Set(registryURIs).count == registryURIs.count,
              files.count == 11, inventoryPolicy.lockedFileCount == files.count, Set(paths).count == paths.count,
              files.allSatisfy({ $0.byteCount > 0 && roles.contains($0.role) && Self.isRelativePath($0.path) && Self.isSHA256($0.sha256) }),
              Set(registryPaths).isSubset(of: Set(paths)), inventoryPolicy.selfHashDisposition == "LOCK_FILE_EXCLUDED_TO_AVOID_RECURSION",
              inventoryPolicy.unexpectedOwnedFileDisposition == "REJECT", inventoryPolicy.lineEndingPolicy == "EXACT_BYTES",
              referencePolicy.remoteResolution == "FORBIDDEN", referencePolicy.allowedAbsoluteURIs == registryURIs,
              referencePolicy.allowedRelativeReferencePrefixes == ["#", "meta/"], !distributionSHA256.isEmpty else {
            throw PortableContractValidationFailureV1.invalidToolLock
        }
    }
    private static func isSHA256(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) } }
    private static func isRelativePath(_ value: String) -> Bool { !value.isEmpty && !value.hasPrefix("/") && !value.contains("\\") && !value.split(separator: "/").contains("..") }
}

enum PortableContractToolLockReaderV1 {
    static let relativePath = "Scripts/v21-contracts/portable-contract-validator.lock.json"
    static func read(at url: URL) throws -> PortableContractToolLockV1 {
        guard url.isFileURL else { throw PortableContractValidationFailureV1.invalidToolLock }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= 256 * 1_024 else { throw PortableContractValidationFailureV1.invalidToolLock }
        do {
            let lock = try JSONDecoder().decode(PortableContractToolLockV1.self, from: data)
            try verifyLockedFiles(lock, lockURL: url.standardizedFileURL)
            return lock
        }
        catch let failure as PortableContractValidationFailureV1 { throw failure }
        catch { throw PortableContractValidationFailureV1.invalidToolLock }
    }

    /// C42 deliberately reuses the already pinned offline validator.  This
    /// narrower entry point prevents a cross-market corpus from silently
    /// selecting another tool, enabling network resolution, or weakening the
    /// exact-byte inventory policy.
    static func readForCrossMarketConformance(at url: URL) throws -> PortableContractToolLockV1 {
        let lock = try read(at: url)
        guard !lock.networkFetchAllowed,
              lock.tool.stdlibOnly,
              lock.inventoryPolicy.lineEndingPolicy == "EXACT_BYTES",
              lock.inventoryPolicy.unexpectedOwnedFileDisposition == "REJECT",
              lock.referencePolicy.remoteResolution == "FORBIDDEN",
              lock.distributionSHA256.count == 64 else {
            throw PortableContractValidationFailureV1.invalidToolLock
        }
        return lock
    }

    private static func verifyLockedFiles(
        _ lock: PortableContractToolLockV1,
        lockURL: URL
    ) throws {
        var repositoryRoot = lockURL.deletingLastPathComponent()
        repositoryRoot.deleteLastPathComponent()
        repositoryRoot.deleteLastPathComponent()
        let expected = Set(lock.files.map(\.path)).union([relativePath])
        for file in lock.files {
            let url = repositoryRoot.appendingPathComponent(file.path).standardizedFileURL
            guard url.pathComponents.starts(with: repositoryRoot.pathComponents) else {
                throw PortableContractValidationFailureV1.invalidToolLock
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard data.count == file.byteCount, digest == file.sha256 else {
                throw PortableContractValidationFailureV1.invalidToolLock
            }
        }
        let ownedRoots = [
            repositoryRoot.appendingPathComponent("Scripts/v21-contracts"),
            repositoryRoot.appendingPathComponent("TestSupport/PortableContracts/JSONSchemaDraft202012"),
        ]
        var observed: Set<String> = []
        for ownedRoot in ownedRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: ownedRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { throw PortableContractValidationFailureV1.invalidToolLock }
            for case let url as URL in enumerator {
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                let components = url.standardizedFileURL.pathComponents
                guard components.starts(with: repositoryRoot.pathComponents) else {
                    throw PortableContractValidationFailureV1.invalidToolLock
                }
                observed.insert(components.dropFirst(repositoryRoot.pathComponents.count).joined(separator: "/"))
            }
        }
        guard observed == expected else { throw PortableContractValidationFailureV1.invalidToolLock }
    }
}
