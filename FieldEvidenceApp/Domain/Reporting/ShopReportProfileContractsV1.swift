import Foundation

enum ShopReportProfileFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, staleRevision, digestMismatch
    case profileMismatch, privacyConfirmationRequired, artifactMismatch, limitExceeded
}

enum ShopReportProfileLimitsV1 {
    static let maximumCanonicalBytes = 4 * 1_024 * 1_024
    static let maximumTextBytes = 512
    static let maximumBrandLines = 8
    static let maximumMediaItems = 256
    static let maximumArtifactBytes = 64 * 1_024 * 1_024
    static let maximumHandoffBytes = 128 * 1_024 * 1_024
    static let maximumHistoryRevisions = 4_096
}

private let shopReportProfileNilUUIDV1 = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

enum ShopReportProfileActivationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case off = "OFF"
    case on = "ON"
}

enum ShopOpenEvidencePackagingV1: String, Codable, CaseIterable, Hashable, Sendable {
    case separateFiles = "SEPARATE_FILES"
    case combinedArchive = "COMBINED_ARCHIVE"
}

struct ShopReportBrandV1: Codable, Equatable, Sendable {
    let shopDisplayName: String
    let orderedBrandLines: [String]
    let accentHexRGB: String?
    let logo: OutputScopedContentReferenceV1?

    init(shopDisplayName: String, orderedBrandLines: [String] = [],
         accentHexRGB: String? = nil, logo: OutputScopedContentReferenceV1? = nil) throws {
        guard Self.validText(shopDisplayName),
              orderedBrandLines.count <= ShopReportProfileLimitsV1.maximumBrandLines,
              orderedBrandLines.allSatisfy(Self.validText),
              accentHexRGB.map(Self.validHex) ?? true else { throw ShopReportProfileFailureV1.invalidValue }
        try logo?.validate()
        self.shopDisplayName = shopDisplayName; self.orderedBrandLines = orderedBrandLines
        self.accentHexRGB = accentHexRGB; self.logo = logo
    }
    func validate() throws { guard self == (try Self(shopDisplayName: shopDisplayName, orderedBrandLines: orderedBrandLines, accentHexRGB: accentHexRGB, logo: logo)) else { throw ShopReportProfileFailureV1.invalidValue } }
    func validate(audience: ReportAudienceV1, policy: AudiencePrivacyPolicyV1) throws {
        try validate(); try policy.validate()
        guard policy.audience == audience else { throw ShopReportProfileFailureV1.profileMismatch }
        guard audience != .customerSafe || (Self.customerSafe([shopDisplayName] + orderedBrandLines, policy: policy)
            && (logo.map{$0.byteRole == .derivative && $0.mediaType.lowercased().hasPrefix("image/")} ?? true)) else {
            throw ShopReportProfileFailureV1.invalidValue
        }
    }
    func rebindingWorkspaceID(_ workspaceID:WorkspaceID,outputScopeID:String)throws->Self {
        try validate()
        guard logo?.outputScopeID == outputScopeID || logo == nil else { throw ShopReportProfileFailureV1.profileMismatch }
        let reboundLogo:OutputScopedContentReferenceV1?
        if let logo {
            let workspace=workspaceID.rawValue.uuidString.lowercased()
            guard let ordinal=Int(logo.outputReferenceID.suffix(3)),(0...999).contains(ordinal) else{throw ShopReportProfileFailureV1.invalidValue}
            let namespace=KernelCanonicalHashV1.sha256(Data("\(workspace)|\(outputScopeID)|\(logo.contentSHA256)".utf8))
            let wire=LogoWire(outputScopeID:outputScopeID,outputReferenceID:"out-\(namespace.prefix(16))-\(String(format:"%03d",ordinal))",workspaceBindingSHA256:KernelCanonicalHashV1.sha256(Data("\(workspace)|\(outputScopeID)".utf8)),contentSHA256:logo.contentSHA256,mediaType:logo.mediaType,byteRole:logo.byteRole)
            reboundLogo=try JSONDecoder().decode(OutputScopedContentReferenceV1.self,from:ShopReportProfileCanonicalCodecV1.encode(wire))
        }else{reboundLogo=nil}
        return try Self(shopDisplayName:shopDisplayName,orderedBrandLines:orderedBrandLines,accentHexRGB:accentHexRGB,logo:reboundLogo)
    }
    private static func validText(_ value: String) -> Bool { !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines) && value == value.precomposedStringWithCanonicalMapping && value.utf8.count <= ShopReportProfileLimitsV1.maximumTextBytes }
    private static func validHex(_ value: String) -> Bool { value.count == 7 && value.first == "#" && value.dropFirst().allSatisfy { $0.isHexDigit } }
    private struct LogoWire:Codable{let outputScopeID:String;let outputReferenceID:String;let workspaceBindingSHA256:String;let contentSHA256:String;let mediaType:String;let byteRole:ContentByteRoleV1}
    private static func customerSafe(_ values:[String],policy:AudiencePrivacyPolicyV1)->Bool {
        guard !policy.containsProhibitedCanary(in:values),
              !AudiencePrivacyLexicalDetectorV1.containsProhibitedPattern(in:values) else{return false}
        let prohibited=["<",">","&lt;","&gt;","javascript:","vbscript:","data:text/html","onerror=","onload=","srcdoc=","{{","{%","<?","url(","](","http://","https://","file://","c:\\","/users/","\\users\\"]
        let claimTerms:Set<String>=["contact","phone","telephone","email","cost","costs","price","pricing","diagnostic","diagnostics","capability","capabilities","verified","verifies","verification","delivered","delivery","secure","security","approved","approval","certified","certification","compliant","compliance"]
        let identifierPhrases=[" internal id "," internal identifier "," workspace id "," workspace identifier "," mutation id "," mutation identifier "," local id "," local identifier "," profile id "," profile identifier "]
        return values.allSatisfy { value in
            let folded=value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            let normalizedWords=folded.split{!$0.isLetter && !$0.isNumber}.map(String.init)
            let words=" "+normalizedWords.joined(separator:" ")+" "
            let containsUUIDLikeIdentifier = folded.range(of:"[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",options:.regularExpression) != nil
            return !prohibited.contains(where:folded.contains)
                && claimTerms.isDisjoint(with:normalizedWords)
                && !identifierPhrases.contains(where:words.contains)
                && !containsUUIDLikeIdentifier
                && !["=","+","-","@"].contains(where:folded.hasPrefix)
        }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable { case shopDisplayName, orderedBrandLines, accentHexRGB, logo }
    init(from decoder: Decoder) throws { try ClosedContractDecodingV1.rejectUnknownKeys(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue))); let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(shopDisplayName: c.decode(String.self, forKey: .shopDisplayName), orderedBrandLines: c.decode([String].self, forKey: .orderedBrandLines), accentHexRGB: c.decodeIfPresent(String.self, forKey: .accentHexRGB), logo: c.decodeIfPresent(OutputScopedContentReferenceV1.self, forKey: .logo)) }
}

struct ShopReportProfileReferenceV1: Codable, Equatable, Hashable, Sendable {
    let profileID: UUID; let revision: UInt64; let profileSHA256: String
    init(profileID: UUID, revision: UInt64, profileSHA256: String) throws { guard profileID != shopReportProfileNilUUIDV1, revision > 0, KernelCanonicalHashV1.validSHA256(profileSHA256) else { throw ShopReportProfileFailureV1.invalidValue }; self.profileID = profileID; self.revision = revision; self.profileSHA256 = profileSHA256 }
    func validate() throws { _ = try Self(profileID: profileID, revision: revision, profileSHA256: profileSHA256) }
    private enum CodingKeys:String,CodingKey,CaseIterable{case profileID,revision,profileSHA256}
    init(from decoder:Decoder)throws{try ClosedContractDecodingV1.rejectUnknownKeys(decoder,allowed:Set(CodingKeys.allCases.map(\.rawValue)));let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(profileID:c.decode(UUID.self,forKey:.profileID),revision:c.decode(UInt64.self,forKey:.revision),profileSHA256:c.decode(String.self,forKey:.profileSHA256))}
}

struct ShopReportProfileV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let persistentKind = "SHOP_REPORT_PROFILE_V1"
    let schemaVersion: Int; let persistentKind: String
    let workspaceID: WorkspaceID; let profileID: UUID; let revision: UInt64
    let predecessor: ShopReportProfileReferenceV1?; let mutationID: MutationIDV1
    let activation: ShopReportProfileActivationV1; let brand: ShopReportBrandV1
    let reportLayoutProfile: ReportLayoutProfileV1; let exportProfile: ExportProfileV1
    let evidenceDetailProfile: EvidenceDetailCardProfileV1
    let sectionRegistry: ReportSectionRegistryV1
    let sectionRegistryID: String; let sectionRegistryVersion: Int; let sectionRegistrySHA256: String
    let rendererVersion: String; let packaging: ShopOpenEvidencePackagingV1
    let recordedBy: ActorSnapshotV1; let recordedAt: Date; let profileSHA256: String

    var reference: ShopReportProfileReferenceV1 { get throws { try .init(profileID: profileID, revision: revision, profileSHA256: profileSHA256) } }
    init(workspaceID: WorkspaceID, profileID: UUID, predecessor: ShopReportProfileV1? = nil,
         revision: UInt64, mutationID: MutationIDV1, activation: ShopReportProfileActivationV1,
         brand: ShopReportBrandV1, reportLayoutProfile: ReportLayoutProfileV1,
         exportProfile: ExportProfileV1, evidenceDetailProfile: EvidenceDetailCardProfileV1,
         sectionRegistry: ReportSectionRegistryV1, rendererVersion: String,
         packaging: ShopOpenEvidencePackagingV1, recordedBy: ActorSnapshotV1, recordedAt: Date) throws {
        try sectionRegistry.validate(); try reportLayoutProfile.validate(against: sectionRegistry)
        try exportProfile.validate(); try evidenceDetailProfile.validate(); try brand.validate(); try recordedBy.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let registryDigest = KernelCanonicalHashV1.sha256(try encoder.encode(sectionRegistry))
        schemaVersion = Self.schemaVersion; persistentKind = Self.persistentKind
        self.workspaceID = workspaceID; self.profileID = profileID; self.revision = revision
        self.predecessor = try predecessor?.reference; self.mutationID = mutationID; self.activation = activation
        self.brand = brand; self.reportLayoutProfile = reportLayoutProfile; self.exportProfile = exportProfile
        self.evidenceDetailProfile = evidenceDetailProfile; self.sectionRegistry = sectionRegistry; sectionRegistryID = sectionRegistry.registryID
        sectionRegistryVersion = sectionRegistry.registryVersion; sectionRegistrySHA256 = registryDigest
        self.rendererVersion = rendererVersion; self.packaging = packaging; self.recordedBy = recordedBy; self.recordedAt = recordedAt
        profileSHA256 = try ShopReportProfileCanonicalCodecV1.sha256(Basis(schemaVersion: Self.schemaVersion, persistentKind: Self.persistentKind, workspaceID: workspaceID, profileID: profileID, revision: revision, predecessor: try predecessor?.reference, mutationID: mutationID, activation: activation, brand: brand, reportLayoutProfile: reportLayoutProfile, exportProfile: exportProfile, evidenceDetailProfile: evidenceDetailProfile, sectionRegistry:sectionRegistry, sectionRegistryID: sectionRegistry.registryID, sectionRegistryVersion: sectionRegistry.registryVersion, sectionRegistrySHA256: registryDigest, rendererVersion: rendererVersion, packaging: packaging, recordedBy: recordedBy, recordedAt: recordedAt))
        try validate(sectionRegistry: sectionRegistry)
    }

    func validate(sectionRegistry: ReportSectionRegistryV1) throws {
        try validateIntrinsic(); try sectionRegistry.validate(); try reportLayoutProfile.validate(against: sectionRegistry)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard self.sectionRegistry == sectionRegistry,
              sectionRegistryID == sectionRegistry.registryID, sectionRegistryVersion == sectionRegistry.registryVersion,
              sectionRegistrySHA256 == KernelCanonicalHashV1.sha256(try encoder.encode(sectionRegistry)),
              reportLayoutProfile.sectionIDs == sectionRegistry.sections.filter({ reportLayoutProfile.sectionIDs.contains($0.sectionID) }).map(\.sectionID) else { throw ShopReportProfileFailureV1.profileMismatch }
    }
    func validateIntrinsic() throws {
        try sectionRegistry.validate();try reportLayoutProfile.validate(against:sectionRegistry)
        try brand.validate(audience:reportLayoutProfile.audience,policy:evidenceDetailProfile.audiencePrivacyPolicy); try exportProfile.validate(); try evidenceDetailProfile.validate(); try predecessor?.validate(); try recordedBy.validate()
        let registryDigest=try ShopReportProfileCanonicalCodecV1.sha256(sectionRegistry)
        guard schemaVersion == Self.schemaVersion, persistentKind == Self.persistentKind,
              profileID != shopReportProfileNilUUIDV1, revision > 0, (predecessor == nil) == (revision == 1),
              predecessor.map({ $0.profileID == profileID && revision > 1 && $0.revision == revision - 1 }) ?? true,
              recordedAt.timeIntervalSinceReferenceDate.isFinite,
              sectionRegistryID == sectionRegistry.registryID,sectionRegistryVersion == sectionRegistry.registryVersion,
              sectionRegistrySHA256 == registryDigest,
              SnapshotProjectionValidationV1.validID(rendererVersion),
              rendererVersion == evidenceDetailProfile.rendererVersion,
              reportLayoutProfile.audience == evidenceDetailProfile.audience,
              reportLayoutProfile.localeIdentifier == evidenceDetailProfile.localeIdentifier,
              reportLayoutProfile.displayProfileID == evidenceDetailProfile.displayProfileID,
              exportProfile.privacyTransformID == evidenceDetailProfile.privacyTransformID,
              Set([ReportProjectionFormatV1.pdf,.openJSON,.structuredText,.formulaSafeCSV]).isSubset(of:Set(exportProfile.formats)),
              brand.logo.map({$0.outputScopeID == evidenceDetailProfile.outputScopeID
                && $0.workspaceBindingSHA256 == KernelCanonicalHashV1.sha256(Data("\(workspaceID.rawValue.uuidString.lowercased())|\(evidenceDetailProfile.outputScopeID)".utf8))}) ?? true,
              packaging.matches(exportProfile.packaging),
              profileSHA256 == (try ShopReportProfileCanonicalCodecV1.sha256(basis)) else { throw ShopReportProfileFailureV1.digestMismatch }
    }
    func validateSuccessor(of prior: Self, sectionRegistry: ReportSectionRegistryV1) throws { try prior.validate(sectionRegistry: sectionRegistry); try validate(sectionRegistry: sectionRegistry); guard predecessor == (try prior.reference), workspaceID == prior.workspaceID, profileID == prior.profileID, revision == prior.revision + 1, mutationID != prior.mutationID, recordedAt >= prior.recordedAt else { throw ShopReportProfileFailureV1.staleRevision } }
    func rebindingWorkspaceID(
        _ targetWorkspaceID: WorkspaceID,
        rebasedPredecessor: ShopReportProfileV1?,
        sectionRegistry: ReportSectionRegistryV1
    ) throws -> Self {
        try validate(sectionRegistry: sectionRegistry)
        guard (revision == 1 && predecessor == nil && rebasedPredecessor == nil)
                || (revision > 1
                    && predecessor != nil
                    && rebasedPredecessor?.workspaceID == targetWorkspaceID
                    && rebasedPredecessor?.profileID == profileID
                    && rebasedPredecessor?.revision == revision - 1) else {
            throw ShopReportProfileFailureV1.staleRevision
        }
        return try Self(
            workspaceID: targetWorkspaceID,
            profileID: profileID,
            predecessor: rebasedPredecessor,
            revision: revision,
            mutationID: mutationID,
            activation: activation,
            brand: try brand.rebindingWorkspaceID(targetWorkspaceID,outputScopeID:evidenceDetailProfile.outputScopeID),
            reportLayoutProfile: reportLayoutProfile,
            exportProfile: exportProfile,
            evidenceDetailProfile: evidenceDetailProfile,
            sectionRegistry: sectionRegistry,
            rendererVersion: rendererVersion,
            packaging: packaging,
            recordedBy: recordedBy,
            recordedAt: recordedAt
        )
    }
    private var basis: Basis { .init(schemaVersion: schemaVersion, persistentKind: persistentKind, workspaceID: workspaceID, profileID: profileID, revision: revision, predecessor: predecessor, mutationID: mutationID, activation: activation, brand: brand, reportLayoutProfile: reportLayoutProfile, exportProfile: exportProfile, evidenceDetailProfile: evidenceDetailProfile, sectionRegistry:sectionRegistry, sectionRegistryID: sectionRegistryID, sectionRegistryVersion: sectionRegistryVersion, sectionRegistrySHA256: sectionRegistrySHA256, rendererVersion: rendererVersion, packaging: packaging, recordedBy: recordedBy, recordedAt: recordedAt) }
    private struct Basis: Codable { let schemaVersion:Int;let persistentKind:String;let workspaceID:WorkspaceID;let profileID:UUID;let revision:UInt64;let predecessor:ShopReportProfileReferenceV1?;let mutationID:MutationIDV1;let activation:ShopReportProfileActivationV1;let brand:ShopReportBrandV1;let reportLayoutProfile:ReportLayoutProfileV1;let exportProfile:ExportProfileV1;let evidenceDetailProfile:EvidenceDetailCardProfileV1;let sectionRegistry:ReportSectionRegistryV1;let sectionRegistryID:String;let sectionRegistryVersion:Int;let sectionRegistrySHA256:String;let rendererVersion:String;let packaging:ShopOpenEvidencePackagingV1;let recordedBy:ActorSnapshotV1;let recordedAt:Date }
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,persistentKind,workspaceID,profileID,revision,predecessor,mutationID,activation,brand,reportLayoutProfile,exportProfile,evidenceDetailProfile,sectionRegistry,sectionRegistryID,sectionRegistryVersion,sectionRegistrySHA256,rendererVersion,packaging,recordedBy,recordedAt,profileSHA256}
    init(from decoder: Decoder) throws { try ClosedContractDecodingV1.rejectUnknownKeys(decoder,allowed:Set(CodingKeys.allCases.map(\.rawValue)));let c=try decoder.container(keyedBy:CodingKeys.self);schemaVersion=try c.decode(Int.self,forKey:.schemaVersion);persistentKind=try c.decode(String.self,forKey:.persistentKind);workspaceID=try c.decode(WorkspaceID.self,forKey:.workspaceID);profileID=try c.decode(UUID.self,forKey:.profileID);revision=try c.decode(UInt64.self,forKey:.revision);predecessor=try c.decodeIfPresent(ShopReportProfileReferenceV1.self,forKey:.predecessor);mutationID=try c.decode(MutationIDV1.self,forKey:.mutationID);activation=try c.decode(ShopReportProfileActivationV1.self,forKey:.activation);brand=try c.decode(ShopReportBrandV1.self,forKey:.brand);reportLayoutProfile=try c.decode(ReportLayoutProfileV1.self,forKey:.reportLayoutProfile);exportProfile=try c.decode(ExportProfileV1.self,forKey:.exportProfile);evidenceDetailProfile=try c.decode(EvidenceDetailCardProfileV1.self,forKey:.evidenceDetailProfile);sectionRegistry=try c.decode(ReportSectionRegistryV1.self,forKey:.sectionRegistry);sectionRegistryID=try c.decode(String.self,forKey:.sectionRegistryID);sectionRegistryVersion=try c.decode(Int.self,forKey:.sectionRegistryVersion);sectionRegistrySHA256=try c.decode(String.self,forKey:.sectionRegistrySHA256);rendererVersion=try c.decode(String.self,forKey:.rendererVersion);packaging=try c.decode(ShopOpenEvidencePackagingV1.self,forKey:.packaging);recordedBy=try c.decode(ActorSnapshotV1.self,forKey:.recordedBy);recordedAt=try c.decode(Date.self,forKey:.recordedAt);profileSHA256=try c.decode(String.self,forKey:.profileSHA256);try validateIntrinsic() }
}

private extension ShopOpenEvidencePackagingV1 { func matches(_ value:ReportPackagingV1)->Bool{switch(self,value){case(.combinedArchive,.combined),(.separateFiles,.separatePerWorkItem):true;default:false}} }

struct ShopReportProfileMutationV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID; let expectedRevision: UInt64; let mutationID: MutationIDV1
    let profile: ShopReportProfileV1
    init(workspaceID: WorkspaceID, expectedRevision: UInt64, mutationID: MutationIDV1, profile: ShopReportProfileV1) throws { guard expectedRevision < .max else { throw ShopReportProfileFailureV1.staleRevision }; try profile.validateIntrinsic(); guard workspaceID == profile.workspaceID, mutationID == profile.mutationID, profile.revision == expectedRevision + 1, (expectedRevision == 0) == (profile.predecessor == nil), profile.predecessor?.revision == expectedRevision else { throw ShopReportProfileFailureV1.staleRevision }; self.workspaceID=workspaceID;self.expectedRevision=expectedRevision;self.mutationID=mutationID;self.profile=profile }
    var affectedIdentity: WorkspaceEntityIdentityV1 { get throws { try .init(kind: .shopReportProfile, id: profile.profileID) } }
    var concurrencyIdentity: WorkspaceEntityIdentityV1 { get throws { try .init(kind: .shopReportProfile, id: profile.profileID) } }
    func validate()throws{_ = try Self(workspaceID:workspaceID,expectedRevision:expectedRevision,mutationID:mutationID,profile:profile)}
    private enum CodingKeys:String,CodingKey,CaseIterable{case workspaceID,expectedRevision,mutationID,profile}
    init(from decoder:Decoder)throws{try ClosedContractDecodingV1.rejectUnknownKeys(decoder,allowed:Set(CodingKeys.allCases.map(\.rawValue)));let c=try decoder.container(keyedBy:CodingKeys.self);try self.init(workspaceID:c.decode(WorkspaceID.self,forKey:.workspaceID),expectedRevision:c.decode(UInt64.self,forKey:.expectedRevision),mutationID:c.decode(MutationIDV1.self,forKey:.mutationID),profile:c.decode(ShopReportProfileV1.self,forKey:.profile))}
}

struct ShopOpenEvidenceArtifactV1: Equatable, Sendable {
    let format: ReportProjectionFormatV1; let bytes: Data; let sha256: String
    init(format: ReportProjectionFormatV1, bytes: Data) throws { guard !bytes.isEmpty, bytes.count <= ShopReportProfileLimitsV1.maximumArtifactBytes else { throw ShopReportProfileFailureV1.limitExceeded };try Self.validate(bytes,as:format); self.format=format;self.bytes=bytes;sha256=KernelCanonicalHashV1.sha256(bytes) }
    private static func validate(_ bytes:Data,as format:ReportProjectionFormatV1)throws {
        switch format {
        case .pdf:
            let text=String(data:bytes,encoding:.isoLatin1)?.lowercased() ?? ""
            guard bytes.starts(with:Data("%PDF-".utf8)),text.trimmingCharacters(in:.whitespacesAndNewlines).hasSuffix("%%eof") else{throw ShopReportProfileFailureV1.artifactMismatch}
            let forbidden=["/javascript","/js ","/launch","/embeddedfile","/openaction","/richmedia","/xfa","http://","https://","file://"]
            guard !forbidden.contains(where:text.contains) else{throw ShopReportProfileFailureV1.artifactMismatch}
        case .openJSON:
            guard (try? JSONSerialization.jsonObject(with:bytes,options:[])) != nil,
                  let text=String(data:bytes,encoding:.utf8),safeText(text) else{throw ShopReportProfileFailureV1.artifactMismatch}
        case .structuredText:
            guard let text=String(data:bytes,encoding:.utf8),safeText(text) else{throw ShopReportProfileFailureV1.artifactMismatch}
        case .formulaSafeCSV:
            guard let text=String(data:bytes,encoding:.utf8),safeText(text),formulaSafe(text) else{throw ShopReportProfileFailureV1.artifactMismatch}
        case .manifest:
            _ = try ShopReportProfileCanonicalCodecV1.decode(ShopOpenEvidenceHashManifestV1.self,from:bytes)
        case .media:
            throw ShopReportProfileFailureV1.artifactMismatch
        }
    }
    private static func safeText(_ value:String)->Bool{let folded=value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"));let forbidden=["<script","</script","<iframe","<object","<embed","javascript:","vbscript:","data:text/html","onerror=","onload=","srcdoc=","http://","https://","file://","c:\\","/users/","\\users\\","../","..\\"];return !forbidden.contains(where:folded.contains)}
    private static func formulaSafe(_ value:String)->Bool{let rows=value.split(separator:"\n",omittingEmptySubsequences:false);guard rows.count<=10_000 else{return false};for row in rows{let cells=row.split(separator:",",omittingEmptySubsequences:false);guard cells.count<=256 else{return false};for cell in cells{var text=String(cell);if text.first=="\""{text.removeFirst()};let trimmed=text.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\u{00a0}\u{feff}")));if let first=trimmed.first,["=","+","-","@"].contains(String(first)){return false}}};return true}
}

struct ShopOpenEvidenceHashManifestEntryV1: Codable, Equatable, Hashable, Sendable {
    let format: ReportProjectionFormatV1
    let sha256: String
    let byteCount: Int
    init(format:ReportProjectionFormatV1,sha256:String,byteCount:Int)throws{guard format != .manifest,KernelCanonicalHashV1.validSHA256(sha256),byteCount>0,byteCount<=ShopReportProfileLimitsV1.maximumArtifactBytes else{throw ShopReportProfileFailureV1.artifactMismatch};self.format=format;self.sha256=sha256;self.byteCount=byteCount}
}

struct ShopOpenEvidenceHashManifestV1: Codable, Equatable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let profileFrontier:ShopReportProfileReferenceV1
    let workspaceID:String;let snapshotID:String;let sourceSnapshotSHA256:String;let outputScopeID:String
    let audience:ReportAudienceV1;let localeIdentifier:String;let rendererVersion:String
    let reportLayoutProfileSHA256:String;let exportProfileSHA256:String;let evidenceDetailProfileSHA256:String
    let sectionRegistrySHA256:String;let finalizedBindingSHA256:String;let detailReceiptSHA256:String
    let confirmationSHA256:String;let accessibilityAssessmentSHA256:String
    let artifacts:[ShopOpenEvidenceHashManifestEntryV1]
    let media:[OutputScopedContentReferenceV1];let packaging:ShopOpenEvidencePackagingV1
    let accessibleOutputSHA256:String;let manifestSHA256:String

    init(profile:ShopReportProfileV1,finalizedBinding:FinalizedReportProfileBindingV1,
         detailReceipt:EvidenceDetailCardRenderReceiptV1,confirmation:FinalAudiencePrivacyConfirmationV1,
         artifacts:[ShopOpenEvidenceArtifactV1],media:[OutputScopedContentReferenceV1],
         packaging:ShopOpenEvidencePackagingV1,accessibleAssessment:AccessibleDocumentAssessmentReceiptV1,
         accessibleOutput:AccessibleDocumentRenderOutputV1)throws {
        try profile.validateIntrinsic();try finalizedBinding.validate();try detailReceipt.validate();try confirmation.validate();try media.forEach{$0.validate()};try accessibleAssessment.validateIntrinsic();try accessibleAssessment.validateOutput(accessibleOutput.bytes)
        let entries=try artifacts.map{try ShopOpenEvidenceHashManifestEntryV1(format:$0.format,sha256:$0.sha256,byteCount:$0.bytes.count)}.sorted{$0.format.rawValue<$1.format.rawValue}
        guard Set(entries.map(\.format)) == [.pdf,.openJSON,.structuredText,.formulaSafeCSV],
              Set(entries.map(\.sha256)).count==entries.count,media==media.sorted(),Set(media).count==media.count,
              finalizedBinding.workspaceID==profile.workspaceID.rawValue.uuidString.lowercased(),
              finalizedBinding.snapshotID==detailReceipt.snapshotID,
              detailReceipt.sourceSnapshotSHA256==confirmation.sourceSnapshotSHA256,
              finalizedBinding.outputScopeID==confirmation.outputScopeID,
              accessibleAssessment.workspaceID==profile.workspaceID,
              accessibleAssessment.snapshotSHA256==confirmation.sourceSnapshotSHA256,
              accessibleAssessment.audience==finalizedBinding.audience,
              accessibleAssessment.manifestID==finalizedBinding.contractManifestID,
              accessibleAssessment.manifestVersion==finalizedBinding.contractManifestVersion,
              accessibleAssessment.manifestSHA256==finalizedBinding.contractManifestSHA256,
              accessibleAssessment.localeIdentifier==finalizedBinding.localeIdentifier,
              accessibleAssessment.profileID==finalizedBinding.reportProfileID,
              accessibleAssessment.profileRelease==finalizedBinding.reportProfileRelease,
              accessibleAssessment.profileSHA256==finalizedBinding.reportProfileSHA256,
              profile.revision<=UInt64(Int.max),
              accessibleAssessment.brandProfileID==profile.profileID.uuidString.lowercased(),
              accessibleAssessment.brandProfileRelease==Int(profile.revision),
              accessibleAssessment.brandProfileSHA256==profile.profileSHA256,
              accessibleAssessment.rendererID==accessibleOutput.rendererID,
              accessibleAssessment.rendererVersion==accessibleOutput.rendererVersion,
              packaging==profile.packaging else{throw ShopReportProfileFailureV1.artifactMismatch}
        schemaVersion=Self.schemaVersion;profileFrontier=try profile.reference;workspaceID=finalizedBinding.workspaceID
        snapshotID=finalizedBinding.snapshotID;sourceSnapshotSHA256=confirmation.sourceSnapshotSHA256;outputScopeID=finalizedBinding.outputScopeID
        audience=finalizedBinding.audience;localeIdentifier=finalizedBinding.localeIdentifier;rendererVersion=finalizedBinding.rendererVersion
        reportLayoutProfileSHA256=try ShopReportProfileCanonicalCodecV1.sha256(profile.reportLayoutProfile)
        exportProfileSHA256=try ShopReportProfileCanonicalCodecV1.sha256(profile.exportProfile)
        evidenceDetailProfileSHA256=try ShopReportProfileCanonicalCodecV1.sha256(profile.evidenceDetailProfile)
        sectionRegistrySHA256=profile.sectionRegistrySHA256
        finalizedBindingSHA256=try ShopReportProfileCanonicalCodecV1.sha256(finalizedBinding)
        detailReceiptSHA256=try ShopReportProfileCanonicalCodecV1.sha256(detailReceipt)
        confirmationSHA256=try ShopReportProfileCanonicalCodecV1.sha256(confirmation)
        accessibilityAssessmentSHA256=KernelCanonicalHashV1.sha256(try AccessibleDocumentCanonicalCodecV1.encode(accessibleAssessment))
        self.artifacts=entries;self.media=media;self.packaging=packaging;accessibleOutputSHA256=accessibleOutput.sha256
        manifestSHA256=try ShopReportProfileCanonicalCodecV1.sha256(basisWithoutDigest)
        try validate()
    }
    func validate()throws{try profileFrontier.validate();try media.forEach{$0.validate()};guard schemaVersion==Self.schemaVersion,SnapshotProjectionValidationV1.validID(workspaceID),SnapshotProjectionValidationV1.validID(snapshotID),SnapshotProjectionValidationV1.validID(outputScopeID),SnapshotProjectionValidationV1.validText(localeIdentifier),SnapshotProjectionValidationV1.validID(rendererVersion),[sourceSnapshotSHA256,reportLayoutProfileSHA256,exportProfileSHA256,evidenceDetailProfileSHA256,sectionRegistrySHA256,finalizedBindingSHA256,detailReceiptSHA256,confirmationSHA256,accessibilityAssessmentSHA256,accessibleOutputSHA256,manifestSHA256].allSatisfy(KernelCanonicalHashV1.validSHA256),artifacts==artifacts.sorted{$0.format.rawValue<$1.format.rawValue},Set(artifacts.map(\.format)) == [.pdf,.openJSON,.structuredText,.formulaSafeCSV],Set(artifacts).count==artifacts.count,artifacts.allSatisfy{KernelCanonicalHashV1.validSHA256($0.sha256)&&$0.byteCount>0&&$0.byteCount<=ShopReportProfileLimitsV1.maximumArtifactBytes},media==media.sorted(),Set(media).count==media.count,manifestSHA256==(try ShopReportProfileCanonicalCodecV1.sha256(basisWithoutDigest))else{throw ShopReportProfileFailureV1.artifactMismatch}}
    func canonicalData()throws->Data{try validate();return try ShopReportProfileCanonicalCodecV1.encode(self)}
    private var basisWithoutDigest:Basis{.init(schemaVersion:schemaVersion,profileFrontier:profileFrontier,workspaceID:workspaceID,snapshotID:snapshotID,sourceSnapshotSHA256:sourceSnapshotSHA256,outputScopeID:outputScopeID,audience:audience,localeIdentifier:localeIdentifier,rendererVersion:rendererVersion,reportLayoutProfileSHA256:reportLayoutProfileSHA256,exportProfileSHA256:exportProfileSHA256,evidenceDetailProfileSHA256:evidenceDetailProfileSHA256,sectionRegistrySHA256:sectionRegistrySHA256,finalizedBindingSHA256:finalizedBindingSHA256,detailReceiptSHA256:detailReceiptSHA256,confirmationSHA256:confirmationSHA256,accessibilityAssessmentSHA256:accessibilityAssessmentSHA256,artifacts:artifacts,media:media,packaging:packaging,accessibleOutputSHA256:accessibleOutputSHA256)}
    private struct Basis:Codable{let schemaVersion:Int;let profileFrontier:ShopReportProfileReferenceV1;let workspaceID:String;let snapshotID:String;let sourceSnapshotSHA256:String;let outputScopeID:String;let audience:ReportAudienceV1;let localeIdentifier:String;let rendererVersion:String;let reportLayoutProfileSHA256:String;let exportProfileSHA256:String;let evidenceDetailProfileSHA256:String;let sectionRegistrySHA256:String;let finalizedBindingSHA256:String;let detailReceiptSHA256:String;let confirmationSHA256:String;let accessibilityAssessmentSHA256:String;let artifacts:[ShopOpenEvidenceHashManifestEntryV1];let media:[OutputScopedContentReferenceV1];let packaging:ShopOpenEvidencePackagingV1;let accessibleOutputSHA256:String}
    private enum CodingKeys:String,CodingKey,CaseIterable{case schemaVersion,profileFrontier,workspaceID,snapshotID,sourceSnapshotSHA256,outputScopeID,audience,localeIdentifier,rendererVersion,reportLayoutProfileSHA256,exportProfileSHA256,evidenceDetailProfileSHA256,sectionRegistrySHA256,finalizedBindingSHA256,detailReceiptSHA256,confirmationSHA256,accessibilityAssessmentSHA256,artifacts,media,packaging,accessibleOutputSHA256,manifestSHA256}
    init(from decoder:Decoder)throws{try ClosedContractDecodingV1.rejectUnknownKeys(decoder,allowed:Set(CodingKeys.allCases.map(\.rawValue)));let c=try decoder.container(keyedBy:CodingKeys.self);schemaVersion=try c.decode(Int.self,forKey:.schemaVersion);profileFrontier=try c.decode(ShopReportProfileReferenceV1.self,forKey:.profileFrontier);workspaceID=try c.decode(String.self,forKey:.workspaceID);snapshotID=try c.decode(String.self,forKey:.snapshotID);sourceSnapshotSHA256=try c.decode(String.self,forKey:.sourceSnapshotSHA256);outputScopeID=try c.decode(String.self,forKey:.outputScopeID);audience=try c.decode(ReportAudienceV1.self,forKey:.audience);localeIdentifier=try c.decode(String.self,forKey:.localeIdentifier);rendererVersion=try c.decode(String.self,forKey:.rendererVersion);reportLayoutProfileSHA256=try c.decode(String.self,forKey:.reportLayoutProfileSHA256);exportProfileSHA256=try c.decode(String.self,forKey:.exportProfileSHA256);evidenceDetailProfileSHA256=try c.decode(String.self,forKey:.evidenceDetailProfileSHA256);sectionRegistrySHA256=try c.decode(String.self,forKey:.sectionRegistrySHA256);finalizedBindingSHA256=try c.decode(String.self,forKey:.finalizedBindingSHA256);detailReceiptSHA256=try c.decode(String.self,forKey:.detailReceiptSHA256);confirmationSHA256=try c.decode(String.self,forKey:.confirmationSHA256);accessibilityAssessmentSHA256=try c.decode(String.self,forKey:.accessibilityAssessmentSHA256);artifacts=try c.decode([ShopOpenEvidenceHashManifestEntryV1].self,forKey:.artifacts);media=try c.decode([OutputScopedContentReferenceV1].self,forKey:.media);packaging=try c.decode(ShopOpenEvidencePackagingV1.self,forKey:.packaging);accessibleOutputSHA256=try c.decode(String.self,forKey:.accessibleOutputSHA256);manifestSHA256=try c.decode(String.self,forKey:.manifestSHA256);try validate()}
}

struct ShopOpenEvidenceHandoffReceiptV1: Equatable, Sendable {
    let profileFrontier: ShopReportProfileReferenceV1; let finalizedBinding: FinalizedReportProfileBindingV1
    let detailReceipt: EvidenceDetailCardRenderReceiptV1; let confirmation: FinalAudiencePrivacyConfirmationV1
    let artifacts: [ShopOpenEvidenceArtifactV1]; let media: [OutputScopedContentReferenceV1]
    let packaging: ShopOpenEvidencePackagingV1; let confirmedFormat: ReportProjectionFormatV1
    let accessibleAssessment:AccessibleDocumentAssessmentReceiptV1;let accessibleOutput: AccessibleDocumentRenderOutputV1
    let receiptSHA256: String; let externalOpenClaimed: Bool; let deliveryClaimed: Bool
    init(profile: ShopReportProfileV1, finalizedBinding: FinalizedReportProfileBindingV1,
         detailReceipt: EvidenceDetailCardRenderReceiptV1, confirmation: FinalAudiencePrivacyConfirmationV1,
         artifacts: [ShopOpenEvidenceArtifactV1], media: [OutputScopedContentReferenceV1],
         packaging: ShopOpenEvidencePackagingV1, confirmedFormat: ReportProjectionFormatV1,
         accessibleAssessment:AccessibleDocumentAssessmentReceiptV1,accessibleOutput: AccessibleDocumentRenderOutputV1) throws {
        try finalizedBinding.validate(); try detailReceipt.validate(); try confirmation.validate(); try media.forEach{$0.validate()};try accessibleAssessment.validateIntrinsic();try accessibleAssessment.validateOutput(accessibleOutput.bytes)
        let required:Set<ReportProjectionFormatV1>=[.pdf,.openJSON,.structuredText,.formulaSafeCSV,.manifest]
        let contentArtifacts=artifacts.filter{$0.format != .manifest}
        let expectedManifest=try ShopOpenEvidenceHashManifestV1(profile:profile,finalizedBinding:finalizedBinding,detailReceipt:detailReceipt,confirmation:confirmation,artifacts:contentArtifacts,media:media,packaging:packaging,accessibleAssessment:accessibleAssessment,accessibleOutput:accessibleOutput)
        let manifestArtifacts=artifacts.filter{$0.format == .manifest}
        guard profile.activation == .on,
              Set(artifacts.map(\.format)) == required, Set(artifacts.map(\.sha256)).count == artifacts.count,
              manifestArtifacts.count==1,manifestArtifacts[0].bytes==(try expectedManifest.canonicalData()),
              artifacts.reduce(0,{$0+$1.bytes.count}) <= ShopReportProfileLimitsV1.maximumHandoffBytes,
              Int64(artifacts.reduce(0,{$0+$1.bytes.count})) <= profile.exportProfile.maximumArchiveBytes,
              artifacts.filter({$0.format == confirmedFormat && $0.sha256 == confirmation.composedOutputSHA256}).count == 1,
              media.count <= min(ShopReportProfileLimitsV1.maximumMediaItems,profile.exportProfile.maximumMediaItems), media == media.sorted(), Set(media).count == media.count,
              media.allSatisfy({$0.outputScopeID == confirmation.outputScopeID}),
              detailReceipt.confirmation == confirmation, detailReceipt.composedOutputSHA256 == confirmation.composedOutputSHA256,
              detailReceipt.snapshotID == finalizedBinding.snapshotID,
              detailReceipt.sourceSnapshotSHA256 == confirmation.sourceSnapshotSHA256,
              finalizedBinding.workspaceID == profile.workspaceID.rawValue.uuidString.lowercased(),
              finalizedBinding.reportProfileID == profile.reportLayoutProfile.profileID,
              finalizedBinding.reportProfileRelease == profile.reportLayoutProfile.profileRelease,
              finalizedBinding.reportProfileSHA256 == (try ShopReportProfileCanonicalCodecV1.sha256(profile.reportLayoutProfile)),
              finalizedBinding.exportProfileID == profile.exportProfile.exportProfileID,
              finalizedBinding.exportProfileRelease == profile.exportProfile.exportProfileRelease,
              finalizedBinding.exportProfileSHA256 == (try ShopReportProfileCanonicalCodecV1.sha256(profile.exportProfile)),
              finalizedBinding.sectionRegistryID == profile.sectionRegistryID,
              finalizedBinding.sectionRegistryVersion == profile.sectionRegistryVersion,
              finalizedBinding.sectionRegistrySHA256 == profile.sectionRegistrySHA256,
              finalizedBinding.sectionIDs == profile.reportLayoutProfile.sectionIDs,
              finalizedBinding.rendererVersion == profile.rendererVersion,
              finalizedBinding.audience == profile.reportLayoutProfile.audience,
              finalizedBinding.detail == profile.reportLayoutProfile.detail,
              finalizedBinding.localeIdentifier == profile.reportLayoutProfile.localeIdentifier,
              finalizedBinding.unitsProfileID == profile.reportLayoutProfile.unitsProfileID,
              finalizedBinding.displayProfileID == profile.reportLayoutProfile.displayProfileID,
              finalizedBinding.orientation == profile.reportLayoutProfile.orientation,
              finalizedBinding.mediaLayout == profile.reportLayoutProfile.mediaLayout,
              finalizedBinding.privacyTransformID == profile.exportProfile.privacyTransformID,
              confirmation.audience == profile.reportLayoutProfile.audience,
              confirmation.localeIdentifier == profile.reportLayoutProfile.localeIdentifier,
              confirmation.rendererVersion == profile.rendererVersion,
              confirmation.profileID == profile.evidenceDetailProfile.profileID,
              confirmation.profileSHA256 == (try ShopReportProfileCanonicalCodecV1.sha256(profile.evidenceDetailProfile)),
              confirmation.outputScopeID == profile.evidenceDetailProfile.outputScopeID,
              confirmation.outputScopeID == finalizedBinding.outputScopeID,
              detailReceipt.confirmation.workspaceID == finalizedBinding.workspaceID,
              detailReceipt.confirmation.outputScopeID == finalizedBinding.outputScopeID,
              packaging == profile.packaging,
              accessibleAssessment.snapshotSHA256==confirmation.sourceSnapshotSHA256,
              accessibleAssessment.brandProfileSHA256==profile.profileSHA256,
              accessibleOutput.rendererVersion == profile.rendererVersion,
              KernelCanonicalHashV1.sha256(accessibleOutput.bytes) == accessibleOutput.sha256 else { throw ShopReportProfileFailureV1.artifactMismatch }
        profileFrontier=try profile.reference;self.finalizedBinding=finalizedBinding;self.detailReceipt=detailReceipt;self.confirmation=confirmation;self.artifacts=artifacts.sorted{$0.format.rawValue<$1.format.rawValue};self.media=media;self.packaging=packaging;self.confirmedFormat=confirmedFormat;self.accessibleAssessment=accessibleAssessment;self.accessibleOutput=accessibleOutput;externalOpenClaimed=false;deliveryClaimed=false
        receiptSHA256 = try ShopReportProfileCanonicalCodecV1.sha256(ReceiptBasis(profileFrontier: profileFrontier, finalizedBinding: finalizedBinding, detailReceipt: detailReceipt, confirmation: confirmation, artifactRows: self.artifacts.map{"\($0.format.rawValue):\($0.sha256):\($0.bytes.count)"}, media: media, packaging: packaging, confirmedFormat:confirmedFormat,accessibleAssessmentSHA256:KernelCanonicalHashV1.sha256(try AccessibleDocumentCanonicalCodecV1.encode(accessibleAssessment)), accessibleSHA256: accessibleOutput.sha256, externalOpenClaimed: false, deliveryClaimed: false))
    }
    private struct ReceiptBasis:Codable{let profileFrontier:ShopReportProfileReferenceV1;let finalizedBinding:FinalizedReportProfileBindingV1;let detailReceipt:EvidenceDetailCardRenderReceiptV1;let confirmation:FinalAudiencePrivacyConfirmationV1;let artifactRows:[String];let media:[OutputScopedContentReferenceV1];let packaging:ShopOpenEvidencePackagingV1;let confirmedFormat:ReportProjectionFormatV1;let accessibleAssessmentSHA256:String;let accessibleSHA256:String;let externalOpenClaimed:Bool;let deliveryClaimed:Bool}
}

enum ShopReportProfileCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];let d=try e.encode(value);guard !d.isEmpty,d.count<=ShopReportProfileLimitsV1.maximumCanonicalBytes else{throw ShopReportProfileFailureV1.limitExceeded};return d}
    static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{guard !data.isEmpty,data.count<=ShopReportProfileLimitsV1.maximumCanonicalBytes else{throw ShopReportProfileFailureV1.limitExceeded};let v=try JSONDecoder().decode(type,from:data);guard try encode(v)==data else{throw ShopReportProfileFailureV1.digestMismatch};return v}
    static func sha256<T:Encodable>(_ value:T)throws->String{KernelCanonicalHashV1.sha256(try encode(value))}
}
