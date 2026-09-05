import Foundation

enum AssetLabelContractFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, invalidChecksum, malformedPayload
    case unsupportedTemplate, limitExceeded, duplicateIdentity, staleBinding
    case missingRelease, scratchRequired, invalidSuccessor, wrongWorkspace
    case invalidReceipt, incompatibleVersion, nonCanonicalData
    case shortCodeCollisionLimitReached, insufficientCryptographicEntropy
    case shortCodeRecoveryRequiresPreparedRequest
}

enum AssetLabelLimitsV1 {
    static let maximumPlanItems = 1_000
    static let maximumPDFBytes: Int64 = 64 * 1_024 * 1_024
    static let maximumFormulaSafeCSVBytes: Int64 = 16 * 1_024 * 1_024
    static let maximumStructuredTextBytes: Int64 = 16 * 1_024 * 1_024
    static let maximumArtifactBytes: Int64 = 96 * 1_024 * 1_024

    static func maximumBytes(for kind: LabelArtifactKindV1) -> Int64 {
        switch kind {
        case .pdf: return maximumPDFBytes
        case .formulaSafeCSV: return maximumFormulaSafeCSVBytes
        case .structuredText: return maximumStructuredTextBytes
        }
    }
}

private struct AssetLabelAnyCodingKeyV1: CodingKey {
    let stringValue: String; let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

private enum AssetLabelClosedCodingV1 {
    static func require<K: CodingKey & CaseIterable>(_ decoder: Decoder, _ keys: K.Type) throws
    where K.AllCases: Collection {
        let allowed = Set(keys.allCases.map(\.stringValue))
        let actual = Set(try decoder.container(keyedBy: AssetLabelAnyCodingKeyV1.self).allKeys.map(\.stringValue))
        guard actual.isSubset(of: allowed) else { throw AssetLabelContractFailureV1.nonCanonicalData }
    }
}

enum AssetLabelCanonicalCodecV1 {
    static let maximumCanonicalByteCount = 16 * 1_024 * 1_024
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw AssetLabelContractFailureV1.limitExceeded
        }
        return data
    }
    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= maximumCanonicalByteCount else {
            throw AssetLabelContractFailureV1.limitExceeded
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw AssetLabelContractFailureV1.nonCanonicalData }
        return value
    }
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        KernelCanonicalHashV1.sha256(try encode(value))
    }
}

private enum AssetLabelValidationV1 {
    static let zeroUUID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    static func uuid(_ value: UUID) throws { guard value != zeroUUID else { throw AssetLabelContractFailureV1.invalidValue } }
    static func digest(_ value: String) throws { guard KernelCanonicalHashV1.validSHA256(value) else { throw AssetLabelContractFailureV1.invalidDigest } }
    static func token(_ value: String, maximumBytes: Int = 160) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AssetLabelContractFailureV1.invalidValue
        }
    }
    static func display(_ value: String, maximumBytes: Int = 320) throws {
        guard !value.isEmpty, value.utf8.count <= maximumBytes,
              value == value.precomposedStringWithCanonicalMapping,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.unicodeScalars.allSatisfy({ scalar in
                let v = scalar.value
                return !(v < 0x20 || (0x7f...0x9f).contains(v) || (0x202a...0x202e).contains(v))
              }) else { throw AssetLabelContractFailureV1.invalidValue }
    }
    static func mediaType(_ value: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&^_.+-/")
        guard !value.isEmpty, value.utf8.count <= 100,
              value == value.lowercased(), value.filter({ $0 == "/" }).count == 1,
              !value.hasPrefix("/"), !value.hasSuffix("/"),
              value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AssetLabelContractFailureV1.invalidValue
        }
    }
    static func instant(_ value: Date) throws { guard value.timeIntervalSince1970.isFinite else { throw AssetLabelContractFailureV1.invalidValue } }
    static func checkedAdd(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw AssetLabelContractFailureV1.limitExceeded }; return value
    }
    static func checkedMultiply(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw AssetLabelContractFailureV1.limitExceeded }; return value
    }
}

struct ManualShortCodeV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion = 1
    static let alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    static let randomBodyLength = 10
    static let externalKeyNamespace = "assetrounds.asset-label.short-code.v1"
    let schemaVersion: Int
    let randomBody: String
    let checkCharacter: String

    init(randomBody: String) throws {
        let canonical = randomBody.uppercased(with: Locale(identifier: "en_US_POSIX"))
        schemaVersion = Self.schemaVersion; self.randomBody = canonical
        checkCharacter = try Self.checkCharacter(for: canonical)
        try validate()
    }

    init(displayValue: String) throws {
        let value = displayValue.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let pieces = value.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard pieces.count == 4, pieces[0] == "AR", pieces[1].count == 5,
              pieces[2].count == 5, pieces[3].count == 1 else {
            throw AssetLabelContractFailureV1.malformedPayload
        }
        schemaVersion = Self.schemaVersion; randomBody = pieces[1] + pieces[2]
        checkCharacter = pieces[3]
        try validate()
    }

    var displayValue: String {
        let split = randomBody.index(randomBody.startIndex, offsetBy: 5)
        return "AR-\(randomBody[..<split])-\(randomBody[split...])-\(checkCharacter)"
    }
    var canonicalLocatorValue: String { "AR1:\(randomBody):\(checkCharacter)" }
    func externalKey() throws -> ExternalKeyV1 {
        try ExternalKeyV1(namespaceID: Self.externalKeyNamespace,
                          normalization: .asciiCaseInsensitive,
                          suppliedValue: canonicalLocatorValue)
    }
    func validate() throws {
        let allowed = Set(Self.alphabet)
        guard schemaVersion == Self.schemaVersion,
              randomBody.count == Self.randomBodyLength,
              randomBody.allSatisfy({ allowed.contains($0) }),
              checkCharacter.count == 1,
              checkCharacter == (try Self.checkCharacter(for: randomBody)) else {
            throw AssetLabelContractFailureV1.invalidChecksum
        }
    }
    private static func checkCharacter(for body: String) throws -> String {
        let alphabet = Array(Self.alphabet); let indexes = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })
        guard body.count == randomBodyLength else { throw AssetLabelContractFailureV1.invalidChecksum }
        var accumulator = schemaVersion
        for character in body {
            guard let index = indexes[character] else { throw AssetLabelContractFailureV1.invalidChecksum }
            accumulator = (accumulator * 17 + index) % alphabet.count
        }
        return String(alphabet[accumulator])
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case schemaVersion, randomBody, checkCharacter }
    init(from decoder: Decoder) throws {
        try AssetLabelClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let body = try c.decode(String.self, forKey: .randomBody)
        let rebuilt = try Self(randomBody: body)
        guard try c.decode(Int.self, forKey: .schemaVersion) == Self.schemaVersion,
              try c.decode(String.self, forKey: .checkCharacter) == rebuilt.checkCharacter else {
            throw AssetLabelContractFailureV1.invalidChecksum
        }
        self = rebuilt
    }
}

/// Immutable operation identity for one C27 locator binding. The random body is
/// deliberately absent: only the issuer may attach cryptographic entropy to it.
struct ManualShortCodeIssuanceOperationV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let workspaceID: WorkspaceID
    let assetID: UUID
    let locatorID: UUID
    let bindingReceiptID: UUID
    let mutationID: MutationIDV1
    let recordedBy: ActorSnapshotV1
    let requestedAt: Date

    init(workspaceID: WorkspaceID, assetID: UUID, locatorID: UUID,
         bindingReceiptID: UUID, mutationID: MutationIDV1,
         recordedBy: ActorSnapshotV1, requestedAt: Date) throws {
        schemaVersion = Self.schemaVersion; self.workspaceID = workspaceID
        self.assetID = assetID; self.locatorID = locatorID
        self.bindingReceiptID = bindingReceiptID; self.mutationID = mutationID
        self.recordedBy = recordedBy; self.requestedAt = requestedAt
        try validate()
    }

    func validate() throws {
        try AssetLabelValidationV1.uuid(assetID); try AssetLabelValidationV1.uuid(locatorID)
        try AssetLabelValidationV1.uuid(bindingReceiptID); try recordedBy.validate()
        try AssetLabelValidationV1.instant(requestedAt)
        guard schemaVersion == Self.schemaVersion, recordedBy.workspaceID == workspaceID else {
            throw AssetLabelContractFailureV1.wrongWorkspace
        }
    }
}

/// Prepared recovery envelope. Production creates this only after querying the
/// canonical C27 locator index for workspace uniqueness. Retrying this exact
/// value preserves the random body across effect-before-receipt recovery.
struct ManualShortCodeIssuanceRequestV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let operation: ManualShortCodeIssuanceOperationV1
    let shortCode: ManualShortCodeV1
    let requestSHA256: String

    init(operation: ManualShortCodeIssuanceOperationV1,
         issuerGeneratedShortCode shortCode: ManualShortCodeV1) throws {
        schemaVersion = Self.schemaVersion; self.operation = operation; self.shortCode = shortCode
        requestSHA256 = try AssetLabelCanonicalCodecV1.sha256(
            Basis(schemaVersion: Self.schemaVersion, operation: operation, shortCode: shortCode)
        )
        try validate()
    }

    func validate() throws {
        try operation.validate(); try shortCode.validate()
        guard schemaVersion == Self.schemaVersion,
              requestSHA256 == (try AssetLabelCanonicalCodecV1.sha256(basis)) else {
            throw AssetLabelContractFailureV1.invalidDigest
        }
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, operation: operation, shortCode: shortCode) }
    private struct Basis: Codable { let schemaVersion: Int; let operation: ManualShortCodeIssuanceOperationV1; let shortCode: ManualShortCodeV1 }
}

/// Returned proof is a view over the sole C27 locator mutation and its durable
/// generic receipt. It is not a second persistent family or identifier system.
struct ManualShortCodeIssuanceReceiptV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let request: ManualShortCodeIssuanceRequestV1
    let locator: AssetLocatorV1
    let bindingReceipt: LocatorBindingReceiptV1
    let mutationReceipt: MutationReceiptV1
    let issuanceSHA256: String

    init(request: ManualShortCodeIssuanceRequestV1, locator: AssetLocatorV1,
         bindingReceipt: LocatorBindingReceiptV1, mutationReceipt: MutationReceiptV1) throws {
        schemaVersion = Self.schemaVersion; self.request = request; self.locator = locator
        self.bindingReceipt = bindingReceipt; self.mutationReceipt = mutationReceipt
        issuanceSHA256 = try AssetLabelCanonicalCodecV1.sha256(Basis(
            schemaVersion: Self.schemaVersion, request: request, locator: locator,
            bindingReceipt: bindingReceipt,
            mutationReceiptSHA256: mutationReceipt.canonicalSHA256()
        ))
        try validate()
    }

    var mutation: AssetLocatorMutationV1 { get throws {
        try AssetLocatorMutationV1(workspaceID: request.operation.workspaceID,
                                   mutationID: request.operation.mutationID,
                                   payload: .bind(locator, receipt: bindingReceipt, predecessorReceipt: nil))
    } }

    func validate() throws {
        try request.validate(); try locator.validate(); try bindingReceipt.validateIntrinsic()
        let operation = request.operation
        guard schemaVersion == Self.schemaVersion, locator.locatorID == operation.locatorID,
              locator.workspaceID == operation.workspaceID, locator.assetID == operation.assetID,
              locator.mutationID == operation.mutationID, locator.revision == 1, locator.state == .active,
              locator.representation == .externalKey(try request.shortCode.externalKey()),
              bindingReceipt.receiptID == operation.bindingReceiptID,
              bindingReceipt.manualShortCodeIssuance == request.shortCode,
              bindingReceipt.recordedBy == operation.recordedBy,
              bindingReceipt.recordedAt == operation.requestedAt,
              bindingReceipt.mutationID == operation.mutationID,
              issuanceSHA256 == (try AssetLabelCanonicalCodecV1.sha256(basis)) else {
            throw AssetLabelContractFailureV1.invalidReceipt
        }
        _ = try AssetLocatorMutationReceiptV1(mutation: mutation, mutationReceipt: mutationReceipt)
    }
    private var basis: Basis { get throws { try .init(
        schemaVersion: schemaVersion, request: request, locator: locator,
        bindingReceipt: bindingReceipt, mutationReceiptSHA256: mutationReceipt.canonicalSHA256()
    ) } }
    private struct Basis: Codable {
        let schemaVersion: Int; let request: ManualShortCodeIssuanceRequestV1
        let locator: AssetLocatorV1; let bindingReceipt: LocatorBindingReceiptV1
        let mutationReceiptSHA256: String
    }
}

struct AssetLabelOpaqueQRPayloadV1: Codable, Equatable, Hashable, Sendable {
    static let prefix = "AR1"
    static let maximumPayloadBytes = 64
    let shortCode: ManualShortCodeV1
    init(shortCode: ManualShortCodeV1) throws { self.shortCode = shortCode; try validate() }
    init(canonicalBytes: Data) throws {
        guard canonicalBytes.count <= Self.maximumPayloadBytes,
              let value = String(data: canonicalBytes, encoding: .ascii) else {
            throw AssetLabelContractFailureV1.malformedPayload
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == Self.prefix else { throw AssetLabelContractFailureV1.malformedPayload }
        self.shortCode = try ManualShortCodeV1(displayValue: "AR-\(parts[1].prefix(5))-\(parts[1].dropFirst(5))-\(parts[2])")
        try validate()
        guard canonicalString == value else { throw AssetLabelContractFailureV1.nonCanonicalData }
    }
    var canonicalString: String { shortCode.canonicalLocatorValue }
    var canonicalBytes: Data { Data(canonicalString.utf8) }
    var sha256: String { KernelCanonicalHashV1.sha256(canonicalBytes) }
    func validate() throws {
        try shortCode.validate()
        guard canonicalBytes.count <= Self.maximumPayloadBytes,
              !canonicalString.contains("//"), !canonicalString.lowercased().contains("http") else {
            throw AssetLabelContractFailureV1.malformedPayload
        }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case canonicalString }
    init(from decoder: Decoder) throws {
        try AssetLabelClosedCodingV1.require(decoder, CodingKeys.self)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(canonicalBytes: Data(c.decode(String.self, forKey: .canonicalString).utf8))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(canonicalString, forKey: .canonicalString)
    }
}

extension AssetLabelOpaqueQRPayloadV1 {
    /// C21 labels resolve through the same typed external-key namespace as
    /// manual entry. The payload is data, never an executable URL.
    func scanToWorkExternalKey() throws -> ExternalKeyV1 {
        try validate(); return try shortCode.externalKey()
    }
}

struct AssetLabelGeometryV1: Codable, Equatable, Hashable, Sendable {
    /// Five metres is intentionally above supported sheet media while keeping every
    /// integer micrometre-to-point intermediate far below Int64 overflow.
    static let maximumDimensionMicrometres: Int64 = 5_000_000
    let pageWidthMicrometres: Int64; let pageHeightMicrometres: Int64
    let rows: Int; let columns: Int
    let originXMicrometres: Int64; let originYMicrometres: Int64
    let cellWidthMicrometres: Int64; let cellHeightMicrometres: Int64
    let horizontalGapMicrometres: Int64; let verticalGapMicrometres: Int64
    let quietZoneMicrometres: Int64; let textBoundMicrometres: Int64
    init(pageWidthMicrometres:Int64,pageHeightMicrometres:Int64,rows:Int,columns:Int,
         originXMicrometres:Int64,originYMicrometres:Int64,cellWidthMicrometres:Int64,
         cellHeightMicrometres:Int64,horizontalGapMicrometres:Int64,verticalGapMicrometres:Int64,
         quietZoneMicrometres:Int64,textBoundMicrometres:Int64)throws{
        self.pageWidthMicrometres=pageWidthMicrometres;self.pageHeightMicrometres=pageHeightMicrometres
        self.rows=rows;self.columns=columns;self.originXMicrometres=originXMicrometres;self.originYMicrometres=originYMicrometres
        self.cellWidthMicrometres=cellWidthMicrometres;self.cellHeightMicrometres=cellHeightMicrometres
        self.horizontalGapMicrometres=horizontalGapMicrometres;self.verticalGapMicrometres=verticalGapMicrometres
        self.quietZoneMicrometres=quietZoneMicrometres;self.textBoundMicrometres=textBoundMicrometres;try validate()
    }
    var capacity: Int { rows * columns }
    func validate() throws {
        let boundedDimensions=[pageWidthMicrometres,pageHeightMicrometres,originXMicrometres,originYMicrometres,cellWidthMicrometres,cellHeightMicrometres,horizontalGapMicrometres,verticalGapMicrometres,quietZoneMicrometres,textBoundMicrometres]
        guard boundedDimensions.allSatisfy({$0<=Self.maximumDimensionMicrometres}),
              pageWidthMicrometres>0,pageHeightMicrometres>0,rows>0,columns>0,rows<=100,columns<=100,
              originXMicrometres>=0,originYMicrometres>=0,cellWidthMicrometres>0,cellHeightMicrometres>0,
              horizontalGapMicrometres>=0,verticalGapMicrometres>=0,quietZoneMicrometres>0,textBoundMicrometres>0,
              textBoundMicrometres < cellWidthMicrometres else { throw AssetLabelContractFailureV1.unsupportedTemplate }
        let width = try AssetLabelValidationV1.checkedAdd(originXMicrometres, try AssetLabelValidationV1.checkedAdd(try AssetLabelValidationV1.checkedMultiply(Int64(columns),cellWidthMicrometres),try AssetLabelValidationV1.checkedMultiply(Int64(columns-1),horizontalGapMicrometres)))
        let height = try AssetLabelValidationV1.checkedAdd(originYMicrometres, try AssetLabelValidationV1.checkedAdd(try AssetLabelValidationV1.checkedMultiply(Int64(rows),cellHeightMicrometres),try AssetLabelValidationV1.checkedMultiply(Int64(rows-1),verticalGapMicrometres)))
        guard width<=pageWidthMicrometres,height<=pageHeightMicrometres,
              try AssetLabelValidationV1.checkedMultiply(quietZoneMicrometres, 2) < min(cellWidthMicrometres,cellHeightMicrometres) else { throw AssetLabelContractFailureV1.unsupportedTemplate }
    }
}

struct AssetLabelTemplateReferenceV1: Codable, Equatable, Hashable, Sendable {
    let templateID:String;let revision:UInt64;let templateSHA256:String
    init(templateID:String,revision:UInt64,templateSHA256:String)throws{self.templateID=templateID;self.revision=revision;self.templateSHA256=templateSHA256;try AssetLabelValidationV1.token(templateID);try AssetLabelValidationV1.digest(templateSHA256);guard revision>0 else{throw AssetLabelContractFailureV1.invalidValue}}
}

enum AssetLabelRendererReleaseCatalogV1 {
    static let rendererID = "deterministic-pdf-renderer-v1"
    static let rendererVersion = "deterministic-pdf-renderer-v1"
    /// Frozen native text layout release: CoreText shaping, NFC input, native
    /// PostScript font cascade, FSI/PDI bidi isolation, 1x grayscale raster,
    /// antialiasing disabled, and fixed ten-pixel tail-truncating line metrics.
    static let nativeTextLayoutReleaseID = "CORETEXT_NFC_NATIVE_POSTSCRIPT_FSI_PDI_GRAY1X_AA_OFF_LINE10_V1"
    static let rendererSHA256 = KernelCanonicalHashV1.sha256(
        Data("assetrounds.deterministic-pdf-renderer-v1|deterministic-pdf-renderer-v1|asset-label-contract-v1|\(nativeTextLayoutReleaseID)".utf8)
    )
}

struct AssetLabelRendererReleaseReferenceV1:Codable,Equatable,Hashable,Sendable{
    let rendererID:String;let rendererVersion:String;let rendererSHA256:String;let nativeTextLayoutReleaseID:String
    init(rendererID:String,rendererVersion:String,rendererSHA256:String,nativeTextLayoutReleaseID:String=AssetLabelRendererReleaseCatalogV1.nativeTextLayoutReleaseID)throws{self.rendererID=rendererID;self.rendererVersion=rendererVersion;self.rendererSHA256=rendererSHA256;self.nativeTextLayoutReleaseID=nativeTextLayoutReleaseID;try validate()}
    static var current:Self{get throws{try .init(rendererID:AssetLabelRendererReleaseCatalogV1.rendererID,rendererVersion:AssetLabelRendererReleaseCatalogV1.rendererVersion,rendererSHA256:AssetLabelRendererReleaseCatalogV1.rendererSHA256,nativeTextLayoutReleaseID:AssetLabelRendererReleaseCatalogV1.nativeTextLayoutReleaseID)}}
    func validate()throws{guard rendererID==AssetLabelRendererReleaseCatalogV1.rendererID,rendererVersion==AssetLabelRendererReleaseCatalogV1.rendererVersion,rendererSHA256==AssetLabelRendererReleaseCatalogV1.rendererSHA256,nativeTextLayoutReleaseID==AssetLabelRendererReleaseCatalogV1.nativeTextLayoutReleaseID else{throw AssetLabelContractFailureV1.missingRelease}}
}

struct AssetLabelNativeFontIdentityV1:Codable,Equatable,Hashable,Comparable,Sendable{
    let postScriptName:String
    let fontFileSHA256:String
    init(postScriptName:String,fontFileSHA256:String)throws{
        try AssetLabelValidationV1.token(postScriptName,maximumBytes:200)
        try AssetLabelValidationV1.digest(fontFileSHA256)
        self.postScriptName=postScriptName
        self.fontFileSHA256=fontFileSHA256
    }
    static func <(lhs:Self,rhs:Self)->Bool{
        lhs.postScriptName != rhs.postScriptName ? lhs.postScriptName<rhs.postScriptName : lhs.fontFileSHA256<rhs.fontFileSHA256
    }
}

struct AssetLabelNativeTextEnvironmentV1:Codable,Equatable,Hashable,Sendable{
    static let schemaVersion=1
    static let maximumSelectedFontCount=512
    let schemaVersion:Int
    let planSHA256:String
    let nativeTextLayoutReleaseID:String
    let coreTextVersion:UInt32
    let operatingSystemBuild:String
    let baseFont:AssetLabelNativeFontIdentityV1
    let selectedFonts:[AssetLabelNativeFontIdentityV1]
    let environmentSHA256:String
    init(planSHA256:String,nativeTextLayoutReleaseID:String,coreTextVersion:UInt32,operatingSystemBuild:String,baseFont:AssetLabelNativeFontIdentityV1,selectedFonts:[AssetLabelNativeFontIdentityV1])throws{
        let ordered=selectedFonts.sorted()
        let basis=Basis(schemaVersion:Self.schemaVersion,planSHA256:planSHA256,nativeTextLayoutReleaseID:nativeTextLayoutReleaseID,coreTextVersion:coreTextVersion,operatingSystemBuild:operatingSystemBuild,baseFont:baseFont,selectedFonts:ordered)
        schemaVersion=Self.schemaVersion
        self.planSHA256=planSHA256
        self.nativeTextLayoutReleaseID=nativeTextLayoutReleaseID
        self.coreTextVersion=coreTextVersion
        self.operatingSystemBuild=operatingSystemBuild
        self.baseFont=baseFont
        self.selectedFonts=ordered
        environmentSHA256=try AssetLabelCanonicalCodecV1.sha256(basis)
        try validate(planSHA256:planSHA256)
    }
    func validate(planSHA256 expectedPlanSHA256:String)throws{
        try AssetLabelValidationV1.digest(planSHA256)
        try AssetLabelValidationV1.digest(expectedPlanSHA256)
        try AssetLabelValidationV1.token(nativeTextLayoutReleaseID)
        try AssetLabelValidationV1.token(operatingSystemBuild)
        _=try AssetLabelNativeFontIdentityV1(postScriptName:baseFont.postScriptName,fontFileSHA256:baseFont.fontFileSHA256)
        try selectedFonts.forEach{_ = try AssetLabelNativeFontIdentityV1(postScriptName:$0.postScriptName,fontFileSHA256:$0.fontFileSHA256)}
        guard schemaVersion==Self.schemaVersion,
              planSHA256==expectedPlanSHA256,
              nativeTextLayoutReleaseID==AssetLabelRendererReleaseCatalogV1.nativeTextLayoutReleaseID,
              coreTextVersion>0,
              !selectedFonts.isEmpty,
              selectedFonts.count<=Self.maximumSelectedFontCount,
              selectedFonts==selectedFonts.sorted(),
              Set(selectedFonts.map(\.postScriptName)).count==selectedFonts.count,
              selectedFonts.contains(baseFont),
              environmentSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis)) else {
            throw AssetLabelContractFailureV1.missingRelease
        }
    }
    private var basis:Basis{.init(schemaVersion:schemaVersion,planSHA256:planSHA256,nativeTextLayoutReleaseID:nativeTextLayoutReleaseID,coreTextVersion:coreTextVersion,operatingSystemBuild:operatingSystemBuild,baseFont:baseFont,selectedFonts:selectedFonts)}
    private struct Basis:Codable{let schemaVersion:Int;let planSHA256:String;let nativeTextLayoutReleaseID:String;let coreTextVersion:UInt32;let operatingSystemBuild:String;let baseFont:AssetLabelNativeFontIdentityV1;let selectedFonts:[AssetLabelNativeFontIdentityV1]}
}

enum AssetLabelTemplateProfileV1:String,Codable,CaseIterable,Hashable,Sendable{
    case letterTwoByTwo="LETTER_2X2_V1"
    case letterOneByTwoAndFiveEighths="LETTER_1X2_5_8_V1"
    case letterOneByFour="LETTER_1X4_V1"
    case a4SeventyByThirtySeven="A4_70X37_V1"
    case rollFiftyByTwentyFive="ROLL_50X25_V1"
}

enum AssetLabelTemplateCatalogV1{
    static let effectiveAt=Date(timeIntervalSince1970:1_767_225_600)
    static func pageMediaID(for profile:AssetLabelTemplateProfileV1)->String{switch profile{case .letterTwoByTwo,.letterOneByTwoAndFiveEighths,.letterOneByFour:return "NA_LETTER";case .a4SeventyByThirtySeven:return "ISO_A4";case .rollFiftyByTwentyFive:return "ROLL_50X25_MM"}}
    static func geometry(for profile:AssetLabelTemplateProfileV1)throws->AssetLabelGeometryV1{switch profile{
    case .letterTwoByTwo:return try .init(pageWidthMicrometres:215_900,pageHeightMicrometres:279_400,rows:5,columns:4,originXMicrometres:6_350,originYMicrometres:12_700,cellWidthMicrometres:50_800,cellHeightMicrometres:50_800,horizontalGapMicrometres:0,verticalGapMicrometres:0,quietZoneMicrometres:4_000,textBoundMicrometres:42_000)
    case .letterOneByTwoAndFiveEighths:return try .init(pageWidthMicrometres:215_900,pageHeightMicrometres:279_400,rows:10,columns:3,originXMicrometres:4_775,originYMicrometres:12_700,cellWidthMicrometres:66_675,cellHeightMicrometres:25_400,horizontalGapMicrometres:3_175,verticalGapMicrometres:0,quietZoneMicrometres:3_000,textBoundMicrometres:20_000)
    case .letterOneByFour:return try .init(pageWidthMicrometres:215_900,pageHeightMicrometres:279_400,rows:10,columns:2,originXMicrometres:6_350,originYMicrometres:12_700,cellWidthMicrometres:101_600,cellHeightMicrometres:25_400,horizontalGapMicrometres:0,verticalGapMicrometres:0,quietZoneMicrometres:3_000,textBoundMicrometres:20_000)
    case .a4SeventyByThirtySeven:return try .init(pageWidthMicrometres:210_000,pageHeightMicrometres:297_000,rows:8,columns:3,originXMicrometres:0,originYMicrometres:500,cellWidthMicrometres:70_000,cellHeightMicrometres:37_000,horizontalGapMicrometres:0,verticalGapMicrometres:0,quietZoneMicrometres:4_000,textBoundMicrometres:56_000)
    case .rollFiftyByTwentyFive:return try .init(pageWidthMicrometres:50_000,pageHeightMicrometres:25_000,rows:1,columns:1,originXMicrometres:0,originYMicrometres:0,cellWidthMicrometres:50_000,cellHeightMicrometres:25_000,horizontalGapMicrometres:0,verticalGapMicrometres:0,quietZoneMicrometres:3_000,textBoundMicrometres:20_000)
    }}
    static func makeRelease(_ profile:AssetLabelTemplateProfileV1)throws->AssetLabelTemplateReleaseV1{try .init(templateID:profile.rawValue,revision:1,pageMediaID:pageMediaID(for:profile),geometry:geometry(for:profile),rendererID:AssetLabelRendererReleaseCatalogV1.rendererID,rendererVersion:AssetLabelRendererReleaseCatalogV1.rendererVersion,rendererSHA256:AssetLabelRendererReleaseCatalogV1.rendererSHA256,effectiveAt:effectiveAt)}
    static func validateRelease(templateID:String,revision:UInt64,pageMediaID:String,geometry:AssetLabelGeometryV1,rendererRelease:AssetLabelRendererReleaseReferenceV1,effectiveAt:Date,supersedes:AssetLabelTemplateReferenceV1?)throws{guard let profile=AssetLabelTemplateProfileV1(rawValue:templateID),revision==1,pageMediaID==self.pageMediaID(for:profile),geometry==(try self.geometry(for:profile)),rendererRelease==(try AssetLabelRendererReleaseReferenceV1.current),effectiveAt==self.effectiveAt,supersedes==nil else{throw AssetLabelContractFailureV1.unsupportedTemplate}}
}

enum AssetLabelLineBreakPolicyV1:String,Codable,CaseIterable,Hashable,Sendable{case fixedGraphemeTailTruncation="FIXED_GRAPHEME_TAIL_TRUNCATION_V1"}
enum AssetLabelQRCorrectionLevelV1:String,Codable,CaseIterable,Hashable,Sendable{case medium="M"}

struct AssetLabelTemplateReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let templateID:String;let revision:UInt64;let pageMediaID:String
    let geometry:AssetLabelGeometryV1;let lineBreakPolicy:AssetLabelLineBreakPolicyV1
    let qrCorrectionLevel:AssetLabelQRCorrectionLevelV1;let interpolationEnabled:Bool;let overlaidLogoEnabled:Bool
    let rendererID:String;let rendererVersion:String;let rendererSHA256:String;let rendererRelease:AssetLabelRendererReleaseReferenceV1
    let effectiveAt:Date;let supersedes:AssetLabelTemplateReferenceV1?;let templateSHA256:String
    init(templateID:String,revision:UInt64,pageMediaID:String,geometry:AssetLabelGeometryV1,
         rendererID:String,rendererVersion:String,rendererSHA256:String,effectiveAt:Date,
         supersedes:AssetLabelTemplateReferenceV1?=nil)throws{
        let rendererRelease=try AssetLabelRendererReleaseReferenceV1(rendererID:rendererID,rendererVersion:rendererVersion,rendererSHA256:rendererSHA256);let digestBasis=Basis(schemaVersion:Self.schemaVersion,templateID:templateID,revision:revision,pageMediaID:pageMediaID,geometry:geometry,lineBreakPolicy:.fixedGraphemeTailTruncation,qrCorrectionLevel:.medium,interpolationEnabled:false,overlaidLogoEnabled:false,rendererID:rendererID,rendererVersion:rendererVersion,rendererSHA256:rendererSHA256,rendererRelease:rendererRelease,effectiveAt:effectiveAt,supersedes:supersedes)
        schemaVersion=Self.schemaVersion;self.templateID=templateID;self.revision=revision;self.pageMediaID=pageMediaID;self.geometry=geometry;lineBreakPolicy = .fixedGraphemeTailTruncation;qrCorrectionLevel = .medium;interpolationEnabled=false;overlaidLogoEnabled=false;self.rendererID=rendererID;self.rendererVersion=rendererVersion;self.rendererSHA256=rendererSHA256;self.rendererRelease=rendererRelease;self.effectiveAt=effectiveAt;self.supersedes=supersedes;templateSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()
    }
    var reference:AssetLabelTemplateReferenceV1{get throws{try .init(templateID:templateID,revision:revision,templateSHA256:templateSHA256)}}
    func validate()throws{try [templateID,pageMediaID,rendererID,rendererVersion].forEach{try AssetLabelValidationV1.token($0)};try geometry.validate();try rendererRelease.validate();try AssetLabelValidationV1.instant(effectiveAt);try AssetLabelTemplateCatalogV1.validateRelease(templateID:templateID,revision:revision,pageMediaID:pageMediaID,geometry:geometry,rendererRelease:rendererRelease,effectiveAt:effectiveAt,supersedes:supersedes);guard rendererID==rendererRelease.rendererID,rendererVersion==rendererRelease.rendererVersion,rendererSHA256==rendererRelease.rendererSHA256,schemaVersion==Self.schemaVersion,lineBreakPolicy == .fixedGraphemeTailTruncation,qrCorrectionLevel == .medium,!interpolationEnabled,!overlaidLogoEnabled,templateSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.unsupportedTemplate}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,templateID:templateID,revision:revision,pageMediaID:pageMediaID,geometry:geometry,lineBreakPolicy:lineBreakPolicy,qrCorrectionLevel:qrCorrectionLevel,interpolationEnabled:interpolationEnabled,overlaidLogoEnabled:overlaidLogoEnabled,rendererID:rendererID,rendererVersion:rendererVersion,rendererSHA256:rendererSHA256,rendererRelease:rendererRelease,effectiveAt:effectiveAt,supersedes:supersedes)}
    private struct Basis:Codable{let schemaVersion:Int;let templateID:String;let revision:UInt64;let pageMediaID:String;let geometry:AssetLabelGeometryV1;let lineBreakPolicy:AssetLabelLineBreakPolicyV1;let qrCorrectionLevel:AssetLabelQRCorrectionLevelV1;let interpolationEnabled:Bool;let overlaidLogoEnabled:Bool;let rendererID:String;let rendererVersion:String;let rendererSHA256:String;let rendererRelease:AssetLabelRendererReleaseReferenceV1;let effectiveAt:Date;let supersedes:AssetLabelTemplateReferenceV1?}
}

enum LabelDisclosureProfileV1:String,Codable,CaseIterable,Hashable,Sendable{case shortCodeOnly="SHORT_CODE_ONLY";case assetAndShortCode="ASSET_AND_SHORT_CODE";case assetLocationAndShortCode="ASSET_LOCATION_AND_SHORT_CODE"}
enum LabelReprintEligibilityV1:String,Codable,CaseIterable,Hashable,Sendable{case activeExactReprint="ACTIVE_EXACT_REPRINT";case historicExportOnly="HISTORIC_EXPORT_ONLY";case blockedMissingRelease="BLOCKED_MISSING_RELEASE"}
enum LabelOutputDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case generated="GENERATED";case handedOffToSystem="HANDED_OFF_TO_SYSTEM"}
enum LabelOutputActivationDecisionV1:String,Codable,CaseIterable,Hashable,Sendable{case enabledBoundedLocalOnly="ENABLED_BOUNDED_LOCAL_ONLY";case disabledOrDeferred="DISABLED_OR_DEFERRED"}
enum AcceptedLabelSnapshotDispositionV1:String,Codable,CaseIterable,Hashable,Sendable{case activeSourceWorkspace="ACTIVE_SOURCE_WORKSPACE";case historicCloneOrFork="HISTORIC_CLONE_OR_FORK"}
enum LabelGenerationStartDecisionV1:String,Codable,CaseIterable,Hashable,Sendable{case explicitStartRequired="EXPLICIT_START_REQUIRED"}
enum AssetLabelItemOrderingPolicyV1:String,Codable,CaseIterable,Hashable,Sendable{case explicitSelectionOrderThenAssetID="EXPLICIT_SELECTION_ORDER_THEN_ASSET_ID_V1"}

struct AssetLabelItemSnapshotV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let assetID:UUID;let assetRevision:UInt64
    let locator:AssetLocatorReferenceV1;let locatorState:AssetLocatorStateV1
    let bindingReceiptID:UUID;let bindingReceiptRevision:UInt64;let bindingReceiptSHA256:String
    let shortCode:ManualShortCodeV1;let qrPayload:AssetLabelOpaqueQRPayloadV1
    let assetDisplay:String;let locationDisplay:String?;let disclosure:LabelDisclosureProfileV1;let orderIndex:Int;let itemSHA256:String
    init(workspaceID:WorkspaceID,assetID:UUID,assetRevision:UInt64,locator:AssetLocatorV1,
         bindingReceipt:LocatorBindingReceiptV1,shortCode:ManualShortCodeV1,assetDisplay:String,
         locationDisplay:String?,disclosure:LabelDisclosureProfileV1,orderIndex:Int)throws{
        let qr=try AssetLabelOpaqueQRPayloadV1(shortCode:shortCode);let ref=try locator.reference
        let digestBasis=Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,assetID:assetID,assetRevision:assetRevision,locator:ref,locatorState:locator.state,bindingReceiptID:bindingReceipt.receiptID,bindingReceiptRevision:bindingReceipt.revision,bindingReceiptSHA256:bindingReceipt.receiptSHA256,shortCode:shortCode,qrPayload:qr,assetDisplay:assetDisplay,locationDisplay:locationDisplay,disclosure:disclosure,orderIndex:orderIndex)
        schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;self.assetID=assetID;self.assetRevision=assetRevision;self.locator=ref;locatorState=locator.state;bindingReceiptID=bindingReceipt.receiptID;bindingReceiptRevision=bindingReceipt.revision;bindingReceiptSHA256=bindingReceipt.receiptSHA256;self.shortCode=shortCode;qrPayload=qr;self.assetDisplay=assetDisplay;self.locationDisplay=locationDisplay;self.disclosure=disclosure;self.orderIndex=orderIndex;itemSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis)
        try locator.validate();try bindingReceipt.validateIntrinsic();guard locator.workspaceID==workspaceID,locator.assetID==assetID,bindingReceipt.workspaceID==workspaceID,bindingReceipt.after==ref,case .externalKey(let key)=locator.representation,key == (try shortCode.externalKey())else{throw AssetLabelContractFailureV1.staleBinding};try validate()
    }
    func validate()throws{try AssetLabelValidationV1.uuid(assetID);try locator.validate();try AssetLabelValidationV1.uuid(bindingReceiptID);try AssetLabelValidationV1.digest(bindingReceiptSHA256);try shortCode.validate();try qrPayload.validate();try AssetLabelValidationV1.display(assetDisplay);if let locationDisplay{try AssetLabelValidationV1.display(locationDisplay)};guard schemaVersion==Self.schemaVersion,assetRevision>0,bindingReceiptRevision>0,orderIndex>=0,qrPayload.shortCode==shortCode,(disclosure == .shortCodeOnly ? assetDisplay == shortCode.displayValue:true),(disclosure == .assetLocationAndShortCode)==(locationDisplay != nil),itemSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidValue}}
    fileprivate func canonicalizedOrderIndex(_ value:Int)throws->Self{try Self(intrinsicWorkspaceID:workspaceID,source:self,orderIndex:value)}
    private init(intrinsicWorkspaceID:WorkspaceID,source:Self,orderIndex:Int)throws{let digestBasis=Basis(schemaVersion:Self.schemaVersion,workspaceID:intrinsicWorkspaceID,assetID:source.assetID,assetRevision:source.assetRevision,locator:source.locator,locatorState:source.locatorState,bindingReceiptID:source.bindingReceiptID,bindingReceiptRevision:source.bindingReceiptRevision,bindingReceiptSHA256:source.bindingReceiptSHA256,shortCode:source.shortCode,qrPayload:source.qrPayload,assetDisplay:source.assetDisplay,locationDisplay:source.locationDisplay,disclosure:source.disclosure,orderIndex:orderIndex);schemaVersion=Self.schemaVersion;workspaceID=intrinsicWorkspaceID;assetID=source.assetID;assetRevision=source.assetRevision;locator=source.locator;locatorState=source.locatorState;bindingReceiptID=source.bindingReceiptID;bindingReceiptRevision=source.bindingReceiptRevision;bindingReceiptSHA256=source.bindingReceiptSHA256;shortCode=source.shortCode;qrPayload=source.qrPayload;assetDisplay=source.assetDisplay;locationDisplay=source.locationDisplay;disclosure=source.disclosure;self.orderIndex=orderIndex;itemSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()}
    private var basis:Basis{.init(schemaVersion:schemaVersion,workspaceID:workspaceID,assetID:assetID,assetRevision:assetRevision,locator:locator,locatorState:locatorState,bindingReceiptID:bindingReceiptID,bindingReceiptRevision:bindingReceiptRevision,bindingReceiptSHA256:bindingReceiptSHA256,shortCode:shortCode,qrPayload:qrPayload,assetDisplay:assetDisplay,locationDisplay:locationDisplay,disclosure:disclosure,orderIndex:orderIndex)}
    private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let assetID:UUID;let assetRevision:UInt64;let locator:AssetLocatorReferenceV1;let locatorState:AssetLocatorStateV1;let bindingReceiptID:UUID;let bindingReceiptRevision:UInt64;let bindingReceiptSHA256:String;let shortCode:ManualShortCodeV1;let qrPayload:AssetLabelOpaqueQRPayloadV1;let assetDisplay:String;let locationDisplay:String?;let disclosure:LabelDisclosureProfileV1;let orderIndex:Int}
}

struct AssetLabelGenerationPlanV1:Codable,Equatable,Sendable{
    static let schemaVersion=1;static let maximumItemCount=AssetLabelLimitsV1.maximumPlanItems
    let schemaVersion:Int;let planID:UUID;let workspaceID:WorkspaceID;let template:AssetLabelTemplateReleaseV1
    let disclosure:LabelDisclosureProfileV1;let items:[AssetLabelItemSnapshotV1];let orderingPolicy:AssetLabelItemOrderingPolicyV1;let startOffset:Int;let startDecision:LabelGenerationStartDecisionV1
    let localeIdentifier:String;let frozenGeneratedAt:Date?;let planSHA256:String
    init(planID:UUID,workspaceID:WorkspaceID,template:AssetLabelTemplateReleaseV1,disclosure:LabelDisclosureProfileV1,
         items:[AssetLabelItemSnapshotV1],startOffset:Int,localeIdentifier:String,frozenGeneratedAt:Date?=nil)throws{
        let selected=items.sorted{$0.orderIndex == $1.orderIndex ? $0.assetID.uuidString<$1.assetID.uuidString : $0.orderIndex<$1.orderIndex};let ordered=try selected.enumerated().map{$0.element.canonicalizedOrderIndex($0.offset)};let digestBasis=Basis(schemaVersion:Self.schemaVersion,planID:planID,workspaceID:workspaceID,template:template,disclosure:disclosure,items:ordered,orderingPolicy:.explicitSelectionOrderThenAssetID,startOffset:startOffset,startDecision:.explicitStartRequired,localeIdentifier:localeIdentifier,frozenGeneratedAt:frozenGeneratedAt)
        schemaVersion=Self.schemaVersion;self.planID=planID;self.workspaceID=workspaceID;self.template=template;self.disclosure=disclosure;self.items=ordered;orderingPolicy = .explicitSelectionOrderThenAssetID;self.startOffset=startOffset;startDecision = .explicitStartRequired;self.localeIdentifier=localeIdentifier;self.frozenGeneratedAt=frozenGeneratedAt;planSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()
    }
    func validate()throws{try AssetLabelValidationV1.uuid(planID);try template.validate();try AssetLabelValidationV1.token(localeIdentifier);if let frozenGeneratedAt{try AssetLabelValidationV1.instant(frozenGeneratedAt)};try items.forEach{try $0.validate()};guard schemaVersion==Self.schemaVersion,orderingPolicy == .explicitSelectionOrderThenAssetID,startDecision == .explicitStartRequired,!items.isEmpty,items.count<=Self.maximumItemCount,startOffset>=0,startOffset<template.geometry.capacity,items.allSatisfy({$0.workspaceID==workspaceID&&$0.disclosure==disclosure}),items.map(\.orderIndex)==Array(0..<items.count),Set(items.map(\.assetID)).count==items.count,Set(items.map(\.locator.locatorID)).count==items.count,planSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,planID:planID,workspaceID:workspaceID,template:template,disclosure:disclosure,items:items,orderingPolicy:orderingPolicy,startOffset:startOffset,startDecision:startDecision,localeIdentifier:localeIdentifier,frozenGeneratedAt:frozenGeneratedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let planID:UUID;let workspaceID:WorkspaceID;let template:AssetLabelTemplateReleaseV1;let disclosure:LabelDisclosureProfileV1;let items:[AssetLabelItemSnapshotV1];let orderingPolicy:AssetLabelItemOrderingPolicyV1;let startOffset:Int;let startDecision:LabelGenerationStartDecisionV1;let localeIdentifier:String;let frozenGeneratedAt:Date?}
}

enum LabelArtifactKindV1:String,Codable,CaseIterable,Hashable,Sendable{case pdf="PDF";case formulaSafeCSV="FORMULA_SAFE_CSV";case structuredText="STRUCTURED_TEXT"}
enum LabelProjectionDispositionV1:String,Equatable,Hashable,Sendable{case scratchPreviewRequiresExplicitStart="SCRATCH_PREVIEW_REQUIRES_EXPLICIT_START"}
struct LabelArtifactManifestEntryV1:Codable,Equatable,Hashable,Sendable{let kind:LabelArtifactKindV1;let safeFilename:String;let mediaType:String;let byteCount:Int64;let sha256:String;let itemCount:Int;init(kind:LabelArtifactKindV1,safeFilename:String,mediaType:String,byteCount:Int64,sha256:String,itemCount:Int)throws{self.kind=kind;self.safeFilename=safeFilename;self.mediaType=mediaType;self.byteCount=byteCount;self.sha256=sha256;self.itemCount=itemCount;try AssetLabelValidationV1.token(safeFilename,maximumBytes:200);try AssetLabelValidationV1.mediaType(mediaType);try AssetLabelValidationV1.digest(sha256);guard byteCount>0,byteCount<=AssetLabelLimitsV1.maximumBytes(for:kind),itemCount>0,itemCount<=AssetLabelGenerationPlanV1.maximumItemCount,!safeFilename.contains("/")&&!safeFilename.contains("\\")else{throw AssetLabelContractFailureV1.invalidValue}}}
struct LabelArtifactManifestV1:Codable,Equatable,Sendable{let planSHA256:String;let entries:[LabelArtifactManifestEntryV1];let manifestSHA256:String;init(planSHA256:String,entries:[LabelArtifactManifestEntryV1])throws{let ordered=entries.sorted{$0.kind.rawValue<$1.kind.rawValue};self.planSHA256=planSHA256;self.entries=ordered;manifestSHA256=try AssetLabelCanonicalCodecV1.sha256(Basis(planSHA256:planSHA256,entries:ordered));try validate()};func validate()throws{try AssetLabelValidationV1.digest(planSHA256);var total:Int64=0;for entry in entries{total=try AssetLabelValidationV1.checkedAdd(total,entry.byteCount)};guard total<=AssetLabelLimitsV1.maximumArtifactBytes,entries.count==LabelArtifactKindV1.allCases.count,Set(entries.map(\.kind))==Set(LabelArtifactKindV1.allCases),Set(entries.map(\.safeFilename)).count==entries.count,entries==entries.sorted(by:{$0.kind.rawValue<$1.kind.rawValue}),manifestSHA256==(try AssetLabelCanonicalCodecV1.sha256(Basis(planSHA256:planSHA256,entries:entries)))else{throw AssetLabelContractFailureV1.invalidValue}};private struct Basis:Codable{let planSHA256:String;let entries:[LabelArtifactManifestEntryV1]}}
struct LabelProjectedArtifactV1:Equatable,Sendable{let entry:LabelArtifactManifestEntryV1;let bytes:Data;init(kind:LabelArtifactKindV1,safeFilename:String,mediaType:String,bytes:Data,itemCount:Int)throws{guard !bytes.isEmpty,Int64(bytes.count)<=AssetLabelLimitsV1.maximumBytes(for:kind)else{throw AssetLabelContractFailureV1.limitExceeded};entry=try .init(kind:kind,safeFilename:safeFilename,mediaType:mediaType,byteCount:Int64(bytes.count),sha256:KernelCanonicalHashV1.sha256(bytes),itemCount:itemCount);self.bytes=bytes}}
struct LabelProjectionResultV1:Equatable,Sendable{
    let disposition:LabelProjectionDispositionV1
    let planSHA256:String
    let nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1
    let artifacts:[LabelProjectedArtifactV1]
    let manifest:LabelArtifactManifestV1
    init(plan:AssetLabelGenerationPlanV1,artifacts:[LabelProjectedArtifactV1],nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1)throws{
        try plan.validate()
        let ordered=artifacts.sorted{$0.entry.kind.rawValue<$1.entry.kind.rawValue}
        disposition = .scratchPreviewRequiresExplicitStart
        planSHA256=plan.planSHA256
        self.nativeTextEnvironment=nativeTextEnvironment
        self.artifacts=ordered
        manifest=try .init(planSHA256:plan.planSHA256,entries:ordered.map(\.entry))
        try validate(plan:plan)
    }
    func validate(plan:AssetLabelGenerationPlanV1)throws{
        try plan.validate()
        try nativeTextEnvironment.validate(planSHA256:plan.planSHA256)
        try manifest.validate()
        guard disposition == .scratchPreviewRequiresExplicitStart,planSHA256==plan.planSHA256,manifest.planSHA256==planSHA256,artifacts.count==LabelArtifactKindV1.allCases.count,artifacts.map(\.entry)==manifest.entries,try artifacts.allSatisfy({$0.entry.byteCount==Int64($0.bytes.count)&&$0.entry.sha256==KernelCanonicalHashV1.sha256($0.bytes)&&$0.entry.itemCount==plan.items.count})else{throw AssetLabelContractFailureV1.invalidDigest}
    }
}

struct AssetLabelPublishedArtifactContentV1:Codable,Equatable,Sendable{
    let kind:LabelArtifactKindV1;let reference:ContentReferenceV1;let locator:ContentLocatorV1
    init(kind:LabelArtifactKindV1,reference:ContentReferenceV1,locator:ContentLocatorV1)throws{self.kind=kind;self.reference=reference;self.locator=locator;try validate()}
    func validate()throws{try locator.validate(against:reference);guard reference.byteRole == .derivative,reference.byteLength>0,reference.digests.digest(for:.sha256) != nil else{throw AssetLabelContractFailureV1.invalidReceipt}}
    func validate(entry:LabelArtifactManifestEntryV1,workspaceID:WorkspaceID)throws{try validate();let workspace=workspaceID.rawValue.uuidString.lowercased();guard kind==entry.kind,reference.workspaceID==workspace,locator.workspaceID==workspace,reference.byteLength==entry.byteCount,reference.mediaType==entry.mediaType,reference.digests.digest(for:.sha256)?.hexadecimalValue==entry.sha256 else{throw AssetLabelContractFailureV1.invalidReceipt}}
}

struct AssetLabelRenderPublicationBindingV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let workspaceID:WorkspaceID;let jobID:LocalJobIDV1;let planSHA256:String;let manifestSHA256:String;let outputSHA256:String;let publishedArtifacts:[AssetLabelPublishedArtifactContentV1];let publicationReceipt:LocalJobPublicationReceiptV1;let publicationReceiptSHA256:String;let bindingSHA256:String
    init(workspaceID:WorkspaceID,planSHA256:String,manifestSHA256:String,outputSHA256:String,publishedArtifacts:[AssetLabelPublishedArtifactContentV1],publicationReceipt:LocalJobPublicationReceiptV1)throws{let ordered=publishedArtifacts.sorted{$0.kind.rawValue<$1.kind.rawValue};let publicationReceiptSHA256=try AssetLabelCanonicalCodecV1.sha256(publicationReceipt);let basis=Basis(schemaVersion:Self.schemaVersion,workspaceID:workspaceID,jobID:publicationReceipt.jobID,planSHA256:planSHA256,manifestSHA256:manifestSHA256,outputSHA256:outputSHA256,publishedArtifacts:ordered,publicationReceipt:publicationReceipt,publicationReceiptSHA256:publicationReceiptSHA256);schemaVersion=Self.schemaVersion;self.workspaceID=workspaceID;jobID=publicationReceipt.jobID;self.planSHA256=planSHA256;self.manifestSHA256=manifestSHA256;self.outputSHA256=outputSHA256;self.publishedArtifacts=ordered;self.publicationReceipt=publicationReceipt;self.publicationReceiptSHA256=publicationReceiptSHA256;bindingSHA256=try AssetLabelCanonicalCodecV1.sha256(basis);try validate()}
    func validate()throws{
        try [planSHA256,manifestSHA256,outputSHA256,publicationReceiptSHA256,bindingSHA256].forEach{try AssetLabelValidationV1.digest($0)}
        try AssetLabelValidationV1.uuid(jobID.rawValue)
        try AssetLabelValidationV1.instant(publicationReceipt.readBackAt)
        try publishedArtifacts.forEach{try $0.validate()}
        let workspace=workspaceID.rawValue.uuidString.lowercased()
        let job=jobID.rawValue.uuidString.lowercased()
        for artifact in publishedArtifacts {
            let suffix:String
            switch artifact.kind {
            case .pdf:suffix="pdf"
            case .formulaSafeCSV:suffix="csv"
            case .structuredText:suffix="text"
            }
            let contentID="asset-label-\(job)-\(suffix)"
            guard let sha256=artifact.reference.digests.digest(for:.sha256),
                  artifact.reference.workspaceID==workspace,
                  artifact.reference.contentID==contentID,
                  artifact.reference.byteRole == .derivative,
                  artifact.reference.digests.values.count==1,
                  artifact.reference.digests.values.first?.algorithm == .sha256,
                  artifact.locator.workspaceID==workspace,
                  artifact.locator.contentID==contentID,
                  artifact.locator.locatorID=="c05-\(contentID)",
                  artifact.locator.locatorRevision==1,
                  artifact.locator.contentDigest==sha256 else {
                throw AssetLabelContractFailureV1.invalidReceipt
            }
        }
        guard schemaVersion==Self.schemaVersion,publishedArtifacts.count==LabelArtifactKindV1.allCases.count,publishedArtifacts.map(\.kind)==LabelArtifactKindV1.allCases.sorted(by:{$0.rawValue<$1.rawValue}),Set(publishedArtifacts.map{ $0.reference.contentID }).count==publishedArtifacts.count,Set(publishedArtifacts.map{ $0.locator.locatorID }).count==publishedArtifacts.count,publicationReceipt.schemaVersion==LocalJobPublicationReceiptV1.currentSchemaVersion,publicationReceipt.kind == .render,publicationReceipt.attemptCount>0,publicationReceipt.jobID==jobID,publicationReceipt.outputSHA256==outputSHA256,publicationReceiptSHA256==(try AssetLabelCanonicalCodecV1.sha256(publicationReceipt)),bindingSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidReceipt}
    }
    func validate(manifest:LabelArtifactManifestV1)throws{try validate();try manifest.validate();guard manifest.manifestSHA256==manifestSHA256,manifest.entries.count==publishedArtifacts.count else{throw AssetLabelContractFailureV1.invalidReceipt};for (artifact,entry) in zip(publishedArtifacts,manifest.entries){try artifact.validate(entry:entry,workspaceID:workspaceID)}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,workspaceID:workspaceID,jobID:jobID,planSHA256:planSHA256,manifestSHA256:manifestSHA256,outputSHA256:outputSHA256,publishedArtifacts:publishedArtifacts,publicationReceipt:publicationReceipt,publicationReceiptSHA256:publicationReceiptSHA256)};private struct Basis:Codable{let schemaVersion:Int;let workspaceID:WorkspaceID;let jobID:LocalJobIDV1;let planSHA256:String;let manifestSHA256:String;let outputSHA256:String;let publishedArtifacts:[AssetLabelPublishedArtifactContentV1];let publicationReceipt:LocalJobPublicationReceiptV1;let publicationReceiptSHA256:String}
}

struct LabelOutputReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let planID:UUID;let planSHA256:String;let manifestSHA256:String;let nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1;let publicationBinding:AssetLabelRenderPublicationBindingV1;let disposition:LabelOutputDispositionV1;let generatedAt:Date;let handedOffAt:Date?;let receiptSHA256:String
    init(receiptID:UUID,workspaceID:WorkspaceID,planID:UUID,planSHA256:String,manifestSHA256:String,nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1,publicationBinding:AssetLabelRenderPublicationBindingV1,disposition:LabelOutputDispositionV1,generatedAt:Date,handedOffAt:Date?=nil)throws{let digestBasis=Basis(schemaVersion:Self.schemaVersion,receiptID:receiptID,workspaceID:workspaceID,planID:planID,planSHA256:planSHA256,manifestSHA256:manifestSHA256,nativeTextEnvironment:nativeTextEnvironment,publicationBinding:publicationBinding,disposition:disposition,generatedAt:generatedAt,handedOffAt:handedOffAt);schemaVersion=Self.schemaVersion;self.receiptID=receiptID;self.workspaceID=workspaceID;self.planID=planID;self.planSHA256=planSHA256;self.manifestSHA256=manifestSHA256;self.nativeTextEnvironment=nativeTextEnvironment;self.publicationBinding=publicationBinding;self.disposition=disposition;self.generatedAt=generatedAt;self.handedOffAt=handedOffAt;receiptSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()}
    func validate()throws{try AssetLabelValidationV1.uuid(receiptID);try AssetLabelValidationV1.uuid(planID);try AssetLabelValidationV1.digest(planSHA256);try AssetLabelValidationV1.digest(manifestSHA256);try nativeTextEnvironment.validate(planSHA256:planSHA256);try publicationBinding.validate();try AssetLabelValidationV1.instant(generatedAt);if let handedOffAt{try AssetLabelValidationV1.instant(handedOffAt)};guard publicationBinding.workspaceID==workspaceID,publicationBinding.planSHA256==planSHA256,publicationBinding.manifestSHA256==manifestSHA256,(disposition == .handedOffToSystem)==(handedOffAt != nil),handedOffAt.map({$0>=generatedAt}) ?? true,receiptSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidReceipt}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,receiptID:receiptID,workspaceID:workspaceID,planID:planID,planSHA256:planSHA256,manifestSHA256:manifestSHA256,nativeTextEnvironment:nativeTextEnvironment,publicationBinding:publicationBinding,disposition:disposition,generatedAt:generatedAt,handedOffAt:handedOffAt)};private struct Basis:Codable{let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let planID:UUID;let planSHA256:String;let manifestSHA256:String;let nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1;let publicationBinding:AssetLabelRenderPublicationBindingV1;let disposition:LabelOutputDispositionV1;let generatedAt:Date;let handedOffAt:Date?}
}

struct AcceptedLabelGenerationSnapshotV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let plan:AssetLabelGenerationPlanV1;let manifest:LabelArtifactManifestV1;let outputReceipt:LabelOutputReceiptV1;let activationDecision:LabelOutputActivationDecisionV1;let disposition:AcceptedLabelSnapshotDispositionV1;let expectedRevision:WorkspaceExpectedRevisionV1;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64;let snapshotSHA256:String
    init(snapshotID:UUID,plan:AssetLabelGenerationPlanV1,result:LabelProjectionResultV1,outputReceipt:LabelOutputReceiptV1,activationDecision:LabelOutputActivationDecisionV1,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws{try result.validate(plan:plan);try outputReceipt.validate();guard outputReceipt.nativeTextEnvironment==result.nativeTextEnvironment else{throw AssetLabelContractFailureV1.missingRelease};let digestBasis=Basis(schemaVersion:Self.schemaVersion,snapshotID:snapshotID,workspaceID:plan.workspaceID,plan:plan,manifest:result.manifest,outputReceipt:outputReceipt,activationDecision:activationDecision,disposition:.activeSourceWorkspace,expectedRevision:expectedRevision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt,revision:1);schemaVersion=Self.schemaVersion;self.snapshotID=snapshotID;workspaceID=plan.workspaceID;self.plan=plan;manifest=result.manifest;self.outputReceipt=outputReceipt;self.activationDecision=activationDecision;disposition = .activeSourceWorkspace;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt;revision=1;snapshotSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()}
    private init(snapshotID:UUID,workspaceID:WorkspaceID,plan:AssetLabelGenerationPlanV1,manifest:LabelArtifactManifestV1,outputReceipt:LabelOutputReceiptV1,activationDecision:LabelOutputActivationDecisionV1,disposition:AcceptedLabelSnapshotDispositionV1,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date,revision:UInt64)throws{let digestBasis=Basis(schemaVersion:Self.schemaVersion,snapshotID:snapshotID,workspaceID:workspaceID,plan:plan,manifest:manifest,outputReceipt:outputReceipt,activationDecision:activationDecision,disposition:disposition,expectedRevision:expectedRevision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt,revision:revision);schemaVersion=Self.schemaVersion;self.snapshotID=snapshotID;self.workspaceID=workspaceID;self.plan=plan;self.manifest=manifest;self.outputReceipt=outputReceipt;self.activationDecision=activationDecision;self.disposition=disposition;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.recordedBy=recordedBy;self.recordedAt=recordedAt;self.revision=revision;snapshotSHA256=try AssetLabelCanonicalCodecV1.sha256(digestBasis);try validate()}
    func validate()throws{try AssetLabelValidationV1.uuid(snapshotID);try plan.validate();try manifest.validate();try outputReceipt.validate();try outputReceipt.publicationBinding.validate(manifest:manifest);try expectedRevision.validate();try recordedBy.validate();try AssetLabelValidationV1.instant(recordedAt);let workspaceBindingValid = disposition == .activeSourceWorkspace ? workspaceID==plan.workspaceID : workspaceID != plan.workspaceID;guard schemaVersion==Self.schemaVersion,revision==1,workspaceBindingValid,workspaceID==expectedRevision.workspaceID,recordedBy.workspaceID==workspaceID,manifest.planSHA256==plan.planSHA256,outputReceipt.workspaceID==plan.workspaceID,outputReceipt.planID==plan.planID,outputReceipt.planSHA256==plan.planSHA256,outputReceipt.manifestSHA256==manifest.manifestSHA256,outputReceipt.disposition == .generated,activationDecision == .enabledBoundedLocalOnly,snapshotSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidValue}}
    func rebound(to workspaceID:WorkspaceID,expectedRevision:WorkspaceExpectedRevisionV1,mutationID:MutationIDV1,recordedBy:ActorSnapshotV1,recordedAt:Date)throws->Self{guard workspaceID != plan.workspaceID else{throw AssetLabelContractFailureV1.wrongWorkspace};return try .init(snapshotID:snapshotID,workspaceID:workspaceID,plan:plan,manifest:manifest,outputReceipt:outputReceipt,activationDecision:activationDecision,disposition:.historicCloneOrFork,expectedRevision:expectedRevision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt,revision:revision)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,snapshotID:snapshotID,workspaceID:workspaceID,plan:plan,manifest:manifest,outputReceipt:outputReceipt,activationDecision:activationDecision,disposition:disposition,expectedRevision:expectedRevision,mutationID:mutationID,recordedBy:recordedBy,recordedAt:recordedAt,revision:revision)}
    private struct Basis:Codable{let schemaVersion:Int;let snapshotID:UUID;let workspaceID:WorkspaceID;let plan:AssetLabelGenerationPlanV1;let manifest:LabelArtifactManifestV1;let outputReceipt:LabelOutputReceiptV1;let activationDecision:LabelOutputActivationDecisionV1;let disposition:AcceptedLabelSnapshotDispositionV1;let expectedRevision:WorkspaceExpectedRevisionV1;let mutationID:MutationIDV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date;let revision:UInt64}
}

struct AssetLabelMutationV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let snapshot:AcceptedLabelGenerationSnapshotV1;let mutationSHA256:String
    init(snapshot:AcceptedLabelGenerationSnapshotV1)throws{try snapshot.validate();let basis=Basis(schemaVersion:Self.schemaVersion,snapshot:snapshot);schemaVersion=Self.schemaVersion;self.snapshot=snapshot;mutationSHA256=try AssetLabelCanonicalCodecV1.sha256(basis);try validate()}
    var workspaceID:WorkspaceID{snapshot.workspaceID};var mutationID:MutationIDV1{snapshot.mutationID};var expectedRevision:WorkspaceExpectedRevisionV1{snapshot.expectedRevision}
    func validate()throws{try snapshot.validate();guard schemaVersion==Self.schemaVersion,mutationSHA256==(try AssetLabelCanonicalCodecV1.sha256(basis))else{throw AssetLabelContractFailureV1.invalidValue}}
    private var basis:Basis{.init(schemaVersion:schemaVersion,snapshot:snapshot)};private struct Basis:Codable{let schemaVersion:Int;let snapshot:AcceptedLabelGenerationSnapshotV1}
}
struct AssetLabelAcceptanceRequestV1:Codable,Equatable,Sendable{let mutation:AssetLabelMutationV1;init(mutation:AssetLabelMutationV1)throws{try mutation.validate();self.mutation=mutation};init(snapshot:AcceptedLabelGenerationSnapshotV1)throws{try self.init(mutation:.init(snapshot:snapshot))};var snapshot:AcceptedLabelGenerationSnapshotV1{mutation.snapshot};var workspaceID:WorkspaceID{mutation.workspaceID};var mutationID:MutationIDV1{mutation.mutationID};var expectedRevision:WorkspaceExpectedRevisionV1{mutation.expectedRevision};func validate()throws{try mutation.validate()}}
struct AssetLabelAcceptanceReceiptV1:Codable,Equatable,Sendable{
    let snapshotSHA256:String;let mutationSHA256:String;let canonicalMutationReceipt:MutationReceiptV1;let receiptSHA256:String
    init(mutation:AssetLabelMutationV1,canonicalMutationReceipt:MutationReceiptV1)throws{try mutation.validate();let snapshot=mutation.snapshot;try canonicalMutationReceipt.validate();snapshotSHA256=snapshot.snapshotSHA256;mutationSHA256=mutation.mutationSHA256;self.canonicalMutationReceipt=canonicalMutationReceipt;receiptSHA256=try AssetLabelCanonicalCodecV1.sha256(Basis(snapshotSHA256:snapshot.snapshotSHA256,mutationSHA256:mutation.mutationSHA256,canonicalReceiptSHA256:WorkspaceMutationCanonicalV1.sha256(canonicalMutationReceipt)));try validate(snapshot:snapshot)}
    init(snapshot:AcceptedLabelGenerationSnapshotV1,canonicalMutationReceipt:MutationReceiptV1)throws{try self.init(mutation:.init(snapshot:snapshot),canonicalMutationReceipt:canonicalMutationReceipt)}
    func validate(snapshot:AcceptedLabelGenerationSnapshotV1)throws{
        try snapshot.validate();try canonicalMutationReceipt.validate()
        let mutation=try AssetLabelMutationV1(snapshot:snapshot)
        let affected=try mutation.affectedIdentity
        let postImage=try mutation.mutationPostImage
        let resulting=canonicalMutationReceipt.resultingRevision.entityRevisions.first(where:{$0.identity==affected})?.revision
        guard snapshotSHA256==snapshot.snapshotSHA256,mutationSHA256==mutation.mutationSHA256,
              canonicalMutationReceipt.mutationID==snapshot.mutationID,
              canonicalMutationReceipt.identity.workspaceID==snapshot.workspaceID,
              canonicalMutationReceipt.expectedRevision==snapshot.expectedRevision,
              canonicalMutationReceipt.commandBodySHA256==(try WorkspaceMutationCanonicalV1.sha256(WorkspaceCommandV1.applyAssetLabel(mutation))),
              canonicalMutationReceipt.postImages==[postImage],resulting==snapshot.revision,
              receiptSHA256==(try AssetLabelCanonicalCodecV1.sha256(Basis(snapshotSHA256:snapshotSHA256,mutationSHA256:mutationSHA256,canonicalReceiptSHA256:WorkspaceMutationCanonicalV1.sha256(canonicalMutationReceipt))))else{throw AssetLabelContractFailureV1.invalidReceipt}
    }
    private struct Basis:Codable{let snapshotSHA256:String;let mutationSHA256:String;let canonicalReceiptSHA256:String}
}

struct AssetLabelCurrentBindingV1:Codable,Equatable,Sendable{let assetID:UUID;let assetRevision:UInt64;let locator:AssetLocatorReferenceV1;let locatorState:AssetLocatorStateV1;let bindingReceiptID:UUID;let bindingReceiptRevision:UInt64;let bindingReceiptSHA256:String;func validate()throws{try AssetLabelValidationV1.uuid(assetID);try locator.validate();try AssetLabelValidationV1.uuid(bindingReceiptID);try AssetLabelValidationV1.digest(bindingReceiptSHA256);guard assetRevision>0,bindingReceiptRevision>0 else{throw AssetLabelContractFailureV1.invalidValue}}}
struct AssetLabelReprintContextV1:Sendable{let templateRelease:AssetLabelTemplateReferenceV1?;let rendererRelease:AssetLabelRendererReleaseReferenceV1?;let nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1?;let currentBindings:[AssetLabelCurrentBindingV1];init(templateRelease:AssetLabelTemplateReferenceV1?,rendererRelease:AssetLabelRendererReleaseReferenceV1?,nativeTextEnvironment:AssetLabelNativeTextEnvironmentV1?,currentBindings:[AssetLabelCurrentBindingV1])throws{try templateRelease?.validate();try rendererRelease?.validate();if let nativeTextEnvironment{try nativeTextEnvironment.validate(planSHA256:nativeTextEnvironment.planSHA256)};try currentBindings.forEach{try $0.validate()};guard Set(currentBindings.map(\.assetID)).count==currentBindings.count else{throw AssetLabelContractFailureV1.duplicateIdentity};self.templateRelease=templateRelease;self.rendererRelease=rendererRelease;self.nativeTextEnvironment=nativeTextEnvironment;self.currentBindings=currentBindings}}
extension AcceptedLabelGenerationSnapshotV1{func reprintEligibility(in context:AssetLabelReprintContextV1)throws->LabelReprintEligibilityV1{try validate();guard context.templateRelease==(try plan.template.reference),context.rendererRelease==plan.template.rendererRelease,context.nativeTextEnvironment==outputReceipt.nativeTextEnvironment else{return .blockedMissingRelease};guard disposition == .activeSourceWorkspace else{return .historicExportOnly};let current=Dictionary(uniqueKeysWithValues:context.currentBindings.map{($0.assetID,$0)});for item in plan.items{guard let value=current[item.assetID] else{return .historicExportOnly};if value.assetRevision != item.assetRevision || value.locator != item.locator || value.locatorState != .active || value.bindingReceiptID != item.bindingReceiptID || value.bindingReceiptRevision != item.bindingReceiptRevision || value.bindingReceiptSHA256 != item.bindingReceiptSHA256{return .historicExportOnly}};return .activeExactReprint}}

// MARK: - Closed canonical decoding

extension ManualShortCodeIssuanceOperationV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,assetID,locatorID,bindingReceiptID,mutationID,recordedBy,requestedAt}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),assetID:c.decode(UUID.self,forKey:.assetID),locatorID:c.decode(UUID.self,forKey:.locatorID),bindingReceiptID:c.decode(UUID.self,forKey:.bindingReceiptID),mutationID:c.decode(MutationIDV1.self,forKey:.mutationID),recordedBy:c.decode(ActorSnapshotV1.self,forKey:.recordedBy),requestedAt:c.decode(Date.self,forKey:.requestedAt));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension ManualShortCodeIssuanceRequestV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,operation,shortCode,requestSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(operation:c.decode(ManualShortCodeIssuanceOperationV1.self,forKey:.operation),issuerGeneratedShortCode:c.decode(ManualShortCodeV1.self,forKey:.shortCode));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(String.self,forKey:.requestSHA256)==value.requestSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension ManualShortCodeIssuanceReceiptV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,request,locator,bindingReceipt,mutationReceipt,issuanceSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(request:c.decode(ManualShortCodeIssuanceRequestV1.self,forKey:.request),locator:c.decode(AssetLocatorV1.self,forKey:.locator),bindingReceipt:c.decode(LocatorBindingReceiptV1.self,forKey:.bindingReceipt),mutationReceipt:c.decode(MutationReceiptV1.self,forKey:.mutationReceipt));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(String.self,forKey:.issuanceSHA256)==value.issuanceSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelGeometryV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case pageWidthMicrometres,pageHeightMicrometres,rows,columns,originXMicrometres,originYMicrometres,cellWidthMicrometres,cellHeightMicrometres,horizontalGapMicrometres,verticalGapMicrometres,quietZoneMicrometres,textBoundMicrometres}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(pageWidthMicrometres:c.decode(Int64.self,forKey:.pageWidthMicrometres),pageHeightMicrometres:c.decode(Int64.self,forKey:.pageHeightMicrometres),rows:c.decode(Int.self,forKey:.rows),columns:c.decode(Int.self,forKey:.columns),originXMicrometres:c.decode(Int64.self,forKey:.originXMicrometres),originYMicrometres:c.decode(Int64.self,forKey:.originYMicrometres),cellWidthMicrometres:c.decode(Int64.self,forKey:.cellWidthMicrometres),cellHeightMicrometres:c.decode(Int64.self,forKey:.cellHeightMicrometres),horizontalGapMicrometres:c.decode(Int64.self,forKey:.horizontalGapMicrometres),verticalGapMicrometres:c.decode(Int64.self,forKey:.verticalGapMicrometres),quietZoneMicrometres:c.decode(Int64.self,forKey:.quietZoneMicrometres),textBoundMicrometres:c.decode(Int64.self,forKey:.textBoundMicrometres))}
}

extension AssetLabelTemplateReferenceV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case templateID,revision,templateSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(templateID:c.decode(String.self,forKey:.templateID),revision:c.decode(UInt64.self,forKey:.revision),templateSHA256:c.decode(String.self,forKey:.templateSHA256))}
}

extension AssetLabelRendererReleaseReferenceV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case rendererID,rendererVersion,rendererSHA256,nativeTextLayoutReleaseID}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(rendererID:c.decode(String.self,forKey:.rendererID),rendererVersion:c.decode(String.self,forKey:.rendererVersion),rendererSHA256:c.decode(String.self,forKey:.rendererSHA256),nativeTextLayoutReleaseID:c.decode(String.self,forKey:.nativeTextLayoutReleaseID))}
}

extension AssetLabelNativeFontIdentityV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case postScriptName,fontFileSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(postScriptName:c.decode(String.self,forKey:.postScriptName),fontFileSHA256:c.decode(String.self,forKey:.fontFileSHA256))}
}

extension AssetLabelNativeTextEnvironmentV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,planSHA256,nativeTextLayoutReleaseID,coreTextVersion,operatingSystemBuild,baseFont,selectedFonts,environmentSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(planSHA256:c.decode(String.self,forKey:.planSHA256),nativeTextLayoutReleaseID:c.decode(String.self,forKey:.nativeTextLayoutReleaseID),coreTextVersion:c.decode(UInt32.self,forKey:.coreTextVersion),operatingSystemBuild:c.decode(String.self,forKey:.operatingSystemBuild),baseFont:c.decode(AssetLabelNativeFontIdentityV1.self,forKey:.baseFont),selectedFonts:c.decode([AssetLabelNativeFontIdentityV1].self,forKey:.selectedFonts));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(String.self,forKey:.environmentSHA256)==value.environmentSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelTemplateReleaseV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,templateID,revision,pageMediaID,geometry,lineBreakPolicy,qrCorrectionLevel,interpolationEnabled,overlaidLogoEnabled,rendererID,rendererVersion,rendererSHA256,rendererRelease,effectiveAt,supersedes,templateSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(templateID:c.decode(String.self,forKey:.templateID),revision:c.decode(UInt64.self,forKey:.revision),pageMediaID:c.decode(String.self,forKey:.pageMediaID),geometry:c.decode(AssetLabelGeometryV1.self,forKey:.geometry),rendererID:c.decode(String.self,forKey:.rendererID),rendererVersion:c.decode(String.self,forKey:.rendererVersion),rendererSHA256:c.decode(String.self,forKey:.rendererSHA256),effectiveAt:c.decode(Date.self,forKey:.effectiveAt),supersedes:c.decodeIfPresent(AssetLabelTemplateReferenceV1.self,forKey:.supersedes));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(AssetLabelLineBreakPolicyV1.self,forKey:.lineBreakPolicy)==value.lineBreakPolicy,try c.decode(AssetLabelQRCorrectionLevelV1.self,forKey:.qrCorrectionLevel)==value.qrCorrectionLevel,try c.decode(Bool.self,forKey:.interpolationEnabled)==value.interpolationEnabled,try c.decode(Bool.self,forKey:.overlaidLogoEnabled)==value.overlaidLogoEnabled,try c.decode(AssetLabelRendererReleaseReferenceV1.self,forKey:.rendererRelease)==value.rendererRelease,try c.decode(String.self,forKey:.templateSHA256)==value.templateSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelItemSnapshotV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,assetID,assetRevision,locator,locatorState,bindingReceiptID,bindingReceiptRevision,bindingReceiptSHA256,shortCode,qrPayload,assetDisplay,locationDisplay,disclosure,orderIndex,itemSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);schemaVersion=try c.decode(Int.self,forKey:.schemaVersion);workspaceID=try c.decode(WorkspaceID.self,forKey:.workspaceID);assetID=try c.decode(UUID.self,forKey:.assetID);assetRevision=try c.decode(UInt64.self,forKey:.assetRevision);locator=try c.decode(AssetLocatorReferenceV1.self,forKey:.locator);locatorState=try c.decode(AssetLocatorStateV1.self,forKey:.locatorState);bindingReceiptID=try c.decode(UUID.self,forKey:.bindingReceiptID);bindingReceiptRevision=try c.decode(UInt64.self,forKey:.bindingReceiptRevision);bindingReceiptSHA256=try c.decode(String.self,forKey:.bindingReceiptSHA256);shortCode=try c.decode(ManualShortCodeV1.self,forKey:.shortCode);qrPayload=try c.decode(AssetLabelOpaqueQRPayloadV1.self,forKey:.qrPayload);assetDisplay=try c.decode(String.self,forKey:.assetDisplay);locationDisplay=try c.decodeIfPresent(String.self,forKey:.locationDisplay);disclosure=try c.decode(LabelDisclosureProfileV1.self,forKey:.disclosure);orderIndex=try c.decode(Int.self,forKey:.orderIndex);itemSHA256=try c.decode(String.self,forKey:.itemSHA256);try validate()}
}

extension AssetLabelGenerationPlanV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,planID,workspaceID,template,disclosure,items,orderingPolicy,startOffset,startDecision,localeIdentifier,frozenGeneratedAt,planSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);schemaVersion=try c.decode(Int.self,forKey:.schemaVersion);planID=try c.decode(UUID.self,forKey:.planID);workspaceID=try c.decode(WorkspaceID.self,forKey:.workspaceID);template=try c.decode(AssetLabelTemplateReleaseV1.self,forKey:.template);disclosure=try c.decode(LabelDisclosureProfileV1.self,forKey:.disclosure);items=try c.decode([AssetLabelItemSnapshotV1].self,forKey:.items);orderingPolicy=try c.decode(AssetLabelItemOrderingPolicyV1.self,forKey:.orderingPolicy);startOffset=try c.decode(Int.self,forKey:.startOffset);startDecision=try c.decode(LabelGenerationStartDecisionV1.self,forKey:.startDecision);localeIdentifier=try c.decode(String.self,forKey:.localeIdentifier);frozenGeneratedAt=try c.decodeIfPresent(Date.self,forKey:.frozenGeneratedAt);planSHA256=try c.decode(String.self,forKey:.planSHA256);try validate()}
}

extension LabelArtifactManifestEntryV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case kind,safeFilename,mediaType,byteCount,sha256,itemCount}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(kind:c.decode(LabelArtifactKindV1.self,forKey:.kind),safeFilename:c.decode(String.self,forKey:.safeFilename),mediaType:c.decode(String.self,forKey:.mediaType),byteCount:c.decode(Int64.self,forKey:.byteCount),sha256:c.decode(String.self,forKey:.sha256),itemCount:c.decode(Int.self,forKey:.itemCount))}
}

extension LabelArtifactManifestV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case planSHA256,entries,manifestSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let decodedEntries=try c.decode([LabelArtifactManifestEntryV1].self,forKey:.entries);let value=try Self(planSHA256:c.decode(String.self,forKey:.planSHA256),entries:decodedEntries);guard decodedEntries==value.entries,try c.decode(String.self,forKey:.manifestSHA256)==value.manifestSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension LabelOutputReceiptV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,receiptID,workspaceID,planID,planSHA256,manifestSHA256,nativeTextEnvironment,publicationBinding,disposition,generatedAt,handedOffAt,receiptSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(receiptID:c.decode(UUID.self,forKey:.receiptID),workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),planID:c.decode(UUID.self,forKey:.planID),planSHA256:c.decode(String.self,forKey:.planSHA256),manifestSHA256:c.decode(String.self,forKey:.manifestSHA256),nativeTextEnvironment:c.decode(AssetLabelNativeTextEnvironmentV1.self,forKey:.nativeTextEnvironment),publicationBinding:c.decode(AssetLabelRenderPublicationBindingV1.self,forKey:.publicationBinding),disposition:c.decode(LabelOutputDispositionV1.self,forKey:.disposition),generatedAt:c.decode(Date.self,forKey:.generatedAt),handedOffAt:c.decodeIfPresent(Date.self,forKey:.handedOffAt));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(String.self,forKey:.receiptSHA256)==value.receiptSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelRenderPublicationBindingV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,workspaceID,jobID,planSHA256,manifestSHA256,outputSHA256,publishedArtifacts,publicationReceipt,publicationReceiptSHA256,bindingSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),planSHA256:c.decode(String.self,forKey:.planSHA256),manifestSHA256:c.decode(String.self,forKey:.manifestSHA256),outputSHA256:c.decode(String.self,forKey:.outputSHA256),publishedArtifacts:c.decode([AssetLabelPublishedArtifactContentV1].self,forKey:.publishedArtifacts),publicationReceipt:c.decode(LocalJobPublicationReceiptV1.self,forKey:.publicationReceipt));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(LocalJobIDV1.self,forKey:.jobID)==value.jobID,try c.decode(String.self,forKey:.publicationReceiptSHA256)==value.publicationReceiptSHA256,try c.decode(String.self,forKey:.bindingSHA256)==value.bindingSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelPublishedArtifactContentV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case kind,reference,locator}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(kind:c.decode(LabelArtifactKindV1.self,forKey:.kind),reference:c.decode(ContentReferenceV1.self,forKey:.reference),locator:c.decode(ContentLocatorV1.self,forKey:.locator))}
}

extension AcceptedLabelGenerationSnapshotV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,snapshotID,workspaceID,plan,manifest,outputReceipt,activationDecision,disposition,expectedRevision,mutationID,recordedBy,recordedAt,revision,snapshotSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);schemaVersion=try c.decode(Int.self,forKey:.schemaVersion);snapshotID=try c.decode(UUID.self,forKey:.snapshotID);workspaceID=try c.decode(WorkspaceID.self,forKey:.workspaceID);plan=try c.decode(AssetLabelGenerationPlanV1.self,forKey:.plan);manifest=try c.decode(LabelArtifactManifestV1.self,forKey:.manifest);outputReceipt=try c.decode(LabelOutputReceiptV1.self,forKey:.outputReceipt);activationDecision=try c.decode(LabelOutputActivationDecisionV1.self,forKey:.activationDecision);disposition=try c.decode(AcceptedLabelSnapshotDispositionV1.self,forKey:.disposition);expectedRevision=try c.decode(WorkspaceExpectedRevisionV1.self,forKey:.expectedRevision);mutationID=try c.decode(MutationIDV1.self,forKey:.mutationID);recordedBy=try c.decode(ActorSnapshotV1.self,forKey:.recordedBy);recordedAt=try c.decode(Date.self,forKey:.recordedAt);revision=try c.decode(UInt64.self,forKey:.revision);snapshotSHA256=try c.decode(String.self,forKey:.snapshotSHA256);try validate()}
}

extension AssetLabelMutationV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,snapshot,mutationSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);let value=try Self(snapshot:c.decode(AcceptedLabelGenerationSnapshotV1.self,forKey:.snapshot));guard try c.decode(Int.self,forKey:.schemaVersion)==value.schemaVersion,try c.decode(String.self,forKey:.mutationSHA256)==value.mutationSHA256 else{throw AssetLabelContractFailureV1.nonCanonicalData};self=value}
}

extension AssetLabelAcceptanceRequestV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case mutation}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(mutation:c.decode(AssetLabelMutationV1.self,forKey:.mutation))}
}

extension AssetLabelAcceptanceReceiptV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case snapshotSHA256,mutationSHA256,canonicalMutationReceipt,receiptSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);snapshotSHA256=try c.decode(String.self,forKey:.snapshotSHA256);mutationSHA256=try c.decode(String.self,forKey:.mutationSHA256);canonicalMutationReceipt=try c.decode(MutationReceiptV1.self,forKey:.canonicalMutationReceipt);receiptSHA256=try c.decode(String.self,forKey:.receiptSHA256);try validateIntrinsic()}
    func validateIntrinsic()throws{try AssetLabelValidationV1.digest(snapshotSHA256);try AssetLabelValidationV1.digest(mutationSHA256);try canonicalMutationReceipt.validate();guard receiptSHA256==(try AssetLabelCanonicalCodecV1.sha256(Basis(snapshotSHA256:snapshotSHA256,mutationSHA256:mutationSHA256,canonicalReceiptSHA256:WorkspaceMutationCanonicalV1.sha256(canonicalMutationReceipt))))else{throw AssetLabelContractFailureV1.invalidReceipt}}
}

extension AssetLabelCurrentBindingV1 {
    private enum CodingKeys:String,CodingKey,CaseIterable{case assetID,assetRevision,locator,locatorState,bindingReceiptID,bindingReceiptRevision,bindingReceiptSHA256}
    init(from decoder:Decoder)throws{try AssetLabelClosedCodingV1.require(decoder,CodingKeys.self);let c=try decoder.container(keyedBy:CodingKeys.self);assetID=try c.decode(UUID.self,forKey:.assetID);assetRevision=try c.decode(UInt64.self,forKey:.assetRevision);locator=try c.decode(AssetLocatorReferenceV1.self,forKey:.locator);locatorState=try c.decode(AssetLocatorStateV1.self,forKey:.locatorState);bindingReceiptID=try c.decode(UUID.self,forKey:.bindingReceiptID);bindingReceiptRevision=try c.decode(UInt64.self,forKey:.bindingReceiptRevision);bindingReceiptSHA256=try c.decode(String.self,forKey:.bindingReceiptSHA256);try validate()}
}

enum AssetLabelPersistenceEnrollmentV1{static let persistentSchemaVersion=34;static let recordsSchemaVersion=33;static let durableModelCount=1;static let persistentFamilies=["AcceptedLabelGenerationSnapshotRow"];static let derivedFamilies=["AssetLabelGenerationPlanV1","LabelProjectionResultV1"];static let createsSecondLocatorStore=false;static let createsSecondRenderer=false}

enum C46OperationalContactConformance_FieldEvidenceApp_Domain_Labels_AssetLabelContractsV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let siteRoleOwnershipForbidden = true
}
enum C52ServiceRequestBoundary_AssetLabelContractsV1 {
    static let sourceKind: ServiceRequestSourceKindV1 = .portableSubmission
    static let requesterAssertionType: ServiceRequestRequesterAssertionV1.Type = ServiceRequestRequesterAssertionV1.self
    static let contactAssertionType: ServiceRequestContactAssertionV1.Type = ServiceRequestContactAssertionV1.self
    static let requesterIdentityIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.requesterIdentityIsVerified
    static let contactAssertionWording: String = "SELF_ASSERTED_UNVERIFIED"
    static let urgencyIsUnverified: Bool = !PortableServiceRequestFormatBoundaryV1.urgencyIsVerified
    static let cleartextIsReadableAndForwardable: Bool = PortableServiceRequestFormatBoundaryV1.submissionIsCleartext && PortableServiceRequestFormatBoundaryV1.invitationIsReadableAndForwardable
    static let providerContactPurposeSeparationRequired: Bool = true
    static let canonicalSourceBytesAreAuthoritative: Bool = true
    static let duplicateCandidatesAreDerived: Bool = !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityMayBecomeWorkspaceTruth: Bool = ServiceRequestNoncanonicalBoundaryV1.rawCapabilityIsWorkspaceTruth
    static let automaticWorkOrDuplicateActionPermitted: Bool = ServiceRequestNoncanonicalBoundaryV1.automaticWorkCreationPermitted || ServiceRequestNoncanonicalBoundaryV1.automaticDuplicateMergePermitted
    static let excludedSurfaces: [String] = ["REPORT", "SEARCH", "DIAGNOSTIC", "LIFECYCLE", "COMPATIBILITY", "BACKUP", "DELETE"]
}
