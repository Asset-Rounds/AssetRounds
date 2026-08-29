import Foundation

enum AssetLocatorFailureV1: Error, Equatable, Sendable {
    case invalidValue, invalidDigest, invalidSuccessor, invalidSignature
    case wrongWorkspace, ambiguous, stalePreview, unsupportedClaim, limitExceeded
}

enum AssetLocatorLimitsV1 {
    static let maximumInputBytes = 1_024
    static let maximumNamespaceBytes = 128
    static let ed25519PublicKeyBytes = 32
    static let ed25519SignatureBytes = 64
    static let maximumCandidates = 32
}

enum LocatorInputSourceV1: String, Codable, CaseIterable, Hashable, Sendable {
    case camera = "CAMERA", manual = "MANUAL", imported = "IMPORTED"
}

enum ExternalKeyNormalizationV1: String, Codable, CaseIterable, Hashable, Sendable {
    case exactNFC = "EXACT_NFC_V1"
    case asciiCaseInsensitive = "ASCII_CASE_INSENSITIVE_V1"
}

struct ExternalKeyV1: Codable, Equatable, Hashable, Sendable {
    let namespaceID: String
    let normalization: ExternalKeyNormalizationV1
    let normalizedValueSHA256: String

    init(namespaceID: String, normalization: ExternalKeyNormalizationV1, suppliedValue: String) throws {
        let namespace = namespaceID.precomposedStringWithCanonicalMapping
        guard Self.validToken(namespace, maximumBytes: AssetLocatorLimitsV1.maximumNamespaceBytes) else { throw AssetLocatorFailureV1.invalidValue }
        let normalized: String
        switch normalization {
        case .exactNFC:
            normalized = suppliedValue.precomposedStringWithCanonicalMapping
            guard Self.validOpaqueValue(normalized) else { throw AssetLocatorFailureV1.invalidValue }
        case .asciiCaseInsensitive:
            guard !suppliedValue.isEmpty, suppliedValue.utf8.count <= AssetLocatorLimitsV1.maximumInputBytes,
                  suppliedValue.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }) else { throw AssetLocatorFailureV1.invalidValue }
            normalized = suppliedValue.uppercased(with: Locale(identifier: "en_US_POSIX"))
        }
        self.namespaceID = namespace
        self.normalization = normalization
        normalizedValueSHA256 = KernelCanonicalHashV1.sha256(Data(normalized.utf8))
        try validate()
    }

    init(namespaceID: String, normalization: ExternalKeyNormalizationV1, normalizedValueSHA256: String) throws {
        self.namespaceID = namespaceID
        self.normalization = normalization
        self.normalizedValueSHA256 = normalizedValueSHA256
        try validate()
    }

    var lookupKey: String { "E|\(namespaceID)|\(normalization.rawValue)|\(normalizedValueSHA256)" }
    func validate() throws {
        guard Self.validToken(namespaceID, maximumBytes: AssetLocatorLimitsV1.maximumNamespaceBytes),
              KernelCanonicalHashV1.validSHA256(normalizedValueSHA256) else { throw AssetLocatorFailureV1.invalidValue }
    }
    private static func validOpaqueValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AssetLocatorLimitsV1.maximumInputBytes &&
        value == value.precomposedStringWithCanonicalMapping &&
        value.unicodeScalars.allSatisfy {
            let scalar=$0.value
            return !(scalar < 0x20 || (0x7f...0x9f).contains(scalar) ||
                (0x202a...0x202e).contains(scalar) || (0x2066...0x2069).contains(scalar))
        }
    }
    private static func validToken(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes && value == value.precomposedStringWithCanonicalMapping &&
        value.unicodeScalars.allSatisfy { (0x21...0x7e).contains($0.value) }
    }
}

enum LocatorSignatureAlgorithmV1: String, Codable, CaseIterable, Hashable, Sendable { case ed25519V1 = "ED25519_V1" }

struct LocatorSigningKeyReferenceV1: Codable, Equatable, Hashable, Sendable {
    let keyID: String; let algorithm: LocatorSignatureAlgorithmV1; let publicKeyData: Data; let publicKeySHA256: String
    init(algorithm: LocatorSignatureAlgorithmV1 = .ed25519V1, publicKeyData: Data) throws {
        self.algorithm=algorithm;self.publicKeyData=publicKeyData;publicKeySHA256=KernelCanonicalHashV1.sha256(publicKeyData);keyID=publicKeySHA256;try validate()
    }
    func validate() throws { guard algorithm == .ed25519V1,publicKeyData.count==AssetLocatorLimitsV1.ed25519PublicKeyBytes,keyID==publicKeySHA256,KernelCanonicalHashV1.sha256(publicKeyData)==publicKeySHA256 else{throw AssetLocatorFailureV1.invalidValue} }
}

struct SignedLocalAssetLocatorPayloadV1: Codable, Equatable, Hashable, Sendable {
    static let currentPayloadVersion=1
    let payloadVersion:Int;let workspaceID:WorkspaceID;let locatorID:UUID;let locatorRevision:UInt64;let assetID:UUID;let signingKey:LocatorSigningKeyReferenceV1;let signatureData:Data;let canonicalPayloadSHA256:String
    init(workspaceID:WorkspaceID,locatorID:UUID,locatorRevision:UInt64,assetID:UUID,signingKey:LocatorSigningKeyReferenceV1,signatureData:Data)throws{self.payloadVersion=Self.currentPayloadVersion;self.workspaceID=workspaceID;self.locatorID=locatorID;self.locatorRevision=locatorRevision;self.assetID=assetID;self.signingKey=signingKey;self.signatureData=signatureData;canonicalPayloadSHA256=KernelCanonicalHashV1.sha256(try Self.unsignedCanonicalData(payloadVersion:Self.currentPayloadVersion,workspaceID:workspaceID,locatorID:locatorID,locatorRevision:locatorRevision,assetID:assetID,keyID:signingKey.keyID));try validateStructure()}
    func validateStructure()throws{try signingKey.validate();guard payloadVersion==Self.currentPayloadVersion,locatorID != Self.zero,assetID != Self.zero,locatorRevision>0,signatureData.count==AssetLocatorLimitsV1.ed25519SignatureBytes,canonicalPayloadSHA256==KernelCanonicalHashV1.sha256(try unsignedCanonicalData())else{throw AssetLocatorFailureV1.invalidValue}}
    func unsignedCanonicalData()throws->Data{try Self.unsignedCanonicalData(payloadVersion:payloadVersion,workspaceID:workspaceID,locatorID:locatorID,locatorRevision:locatorRevision,assetID:assetID,keyID:signingKey.keyID)}
    private static func unsignedCanonicalData(payloadVersion:Int,workspaceID:WorkspaceID,locatorID:UUID,locatorRevision:UInt64,assetID:UUID,keyID:String)throws->Data{try AssetLocatorCanonicalCodecV1.encode(Unsigned(payloadVersion:payloadVersion,workspaceID:workspaceID,locatorID:locatorID,locatorRevision:locatorRevision,assetID:assetID,keyID:keyID))}
    private struct Unsigned:Codable{let payloadVersion:Int;let workspaceID:WorkspaceID;let locatorID:UUID;let locatorRevision:UInt64;let assetID:UUID;let keyID:String}
    private static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

enum AssetLocatorRepresentationV1: Codable, Equatable, Hashable, Sendable { case localSigned(SignedLocalAssetLocatorPayloadV1), externalKey(ExternalKeyV1) }
enum AssetLocatorStateV1:String,Codable,CaseIterable,Hashable,Sendable{case active="ACTIVE",retired="RETIRED",revoked="REVOKED",replaced="REPLACED"}
struct AssetLocatorReferenceV1:Codable,Equatable,Hashable,Sendable{let locatorID:UUID;let revision:UInt64;let locatorSHA256:String;func validate()throws{guard locatorID != Self.zero,revision>0,KernelCanonicalHashV1.validSHA256(locatorSHA256)else{throw AssetLocatorFailureV1.invalidValue}};private static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))}

struct AssetLocatorV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let locatorID:UUID;let workspaceID:WorkspaceID;let assetID:UUID;let representation:AssetLocatorRepresentationV1;let state:AssetLocatorStateV1;let replacedByLocatorID:UUID?;let predecessorLocatorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date;let locatorSHA256:String
    init(locatorID:UUID,workspaceID:WorkspaceID,assetID:UUID,representation:AssetLocatorRepresentationV1,state:AssetLocatorStateV1,replacedByLocatorID:UUID?=nil,predecessorLocatorSHA256:String?=nil,revision:UInt64,mutationID:MutationIDV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.locatorID=locatorID;self.workspaceID=workspaceID;self.assetID=assetID;self.representation=representation;self.state=state;self.replacedByLocatorID=replacedByLocatorID;self.predecessorLocatorSHA256=predecessorLocatorSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedAt=recordedAt;locatorSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,locatorID:locatorID,workspaceID:workspaceID,assetID:assetID,representation:representation,state:state,replacedByLocatorID:replacedByLocatorID,predecessorLocatorSHA256:predecessorLocatorSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt));try validate()}
    var reference:AssetLocatorReferenceV1{get throws{let v=AssetLocatorReferenceV1(locatorID:locatorID,revision:revision,locatorSHA256:locatorSHA256);try v.validate();return v}}
    var lookupKey:String{switch representation{case .externalKey(let key):return key.lookupKey;case .localSigned:return "L|\(locatorID.uuidString.lowercased())"}}
    func validate()throws{switch representation{case .externalKey(let v):try v.validate();case .localSigned(let v):try v.validateStructure();guard v.workspaceID==workspaceID,v.locatorID==locatorID,v.locatorRevision==revision,v.assetID==assetID else{throw AssetLocatorFailureV1.invalidValue}};guard schemaVersion==Self.schemaVersion,locatorID != Self.zero,assetID != Self.zero,recordedAt.timeIntervalSinceReferenceDate.isFinite,revision>0,(revision==1)==(predecessorLocatorSHA256==nil),(state == .replaced)==(replacedByLocatorID != nil),replacedByLocatorID != locatorID,locatorSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw AssetLocatorFailureV1.invalidDigest}}
    func validateSuccessor(of old:Self)throws{try old.validate();try validate();guard old.locatorID==locatorID,old.workspaceID==workspaceID,old.revision<UInt64.max,revision==old.revision+1,predecessorLocatorSHA256==old.locatorSHA256,mutationID != old.mutationID,old.state == .active else{throw AssetLocatorFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,representation:AssetLocatorRepresentationV1,predecessorLocatorSHA256:String?)throws->Self{try .init(locatorID:locatorID,workspaceID:workspaceID,assetID:assetID,representation:representation,state:state,replacedByLocatorID:replacedByLocatorID,predecessorLocatorSHA256:predecessorLocatorSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,locatorID:locatorID,workspaceID:workspaceID,assetID:assetID,representation:representation,state:state,replacedByLocatorID:replacedByLocatorID,predecessorLocatorSHA256:predecessorLocatorSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt)}
    private struct Basis:Codable{let schemaVersion:Int;let locatorID:UUID;let workspaceID:WorkspaceID;let assetID:UUID;let representation:AssetLocatorRepresentationV1;let state:AssetLocatorStateV1;let replacedByLocatorID:UUID?;let predecessorLocatorSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date}
    private static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
}

enum LocatorResolutionOutcomeV1:String,Codable,CaseIterable,Hashable,Sendable{case matched="MATCHED",noMatch="NO_MATCH",foreignWorkspace="FOREIGN_WORKSPACE",ambiguous="AMBIGUOUS",damagedOrIncomplete="DAMAGED_OR_INCOMPLETE",retired="RETIRED",revoked="REVOKED",replaced="REPLACED"}
struct LocatorResolutionV1:Codable,Equatable,Sendable{let workspaceID:WorkspaceID;let source:LocatorInputSourceV1;let inputSHA256:String;let outcome:LocatorResolutionOutcomeV1;let matchedLocator:AssetLocatorReferenceV1?;let matchedAssetID:UUID?;let replacementLocatorID:UUID?;let candidateLocators:[AssetLocatorReferenceV1];let evaluatedAt:Date;let resolutionSHA256:String
    init(workspaceID:WorkspaceID,source:LocatorInputSourceV1,inputSHA256:String,outcome:LocatorResolutionOutcomeV1,matchedLocator:AssetLocatorReferenceV1?,matchedAssetID:UUID?,replacementLocatorID:UUID?,candidateLocators:[AssetLocatorReferenceV1]=[],evaluatedAt:Date)throws{self.workspaceID=workspaceID;self.source=source;self.inputSHA256=inputSHA256;self.outcome=outcome;self.matchedLocator=matchedLocator;self.matchedAssetID=matchedAssetID;self.replacementLocatorID=replacementLocatorID;self.candidateLocators=candidateLocators.sorted{$0.locatorID.uuidString<$1.locatorID.uuidString};self.evaluatedAt=evaluatedAt;resolutionSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(workspaceID:workspaceID,source:source,inputSHA256:inputSHA256,outcome:outcome,matchedLocator:matchedLocator,matchedAssetID:matchedAssetID,replacementLocatorID:replacementLocatorID,candidateLocators:self.candidateLocators,evaluatedAt:evaluatedAt));try validate()}
    func validate()throws{try matchedLocator?.validate();try candidateLocators.forEach{$0.validate()};let selected=matchedLocator != nil&&matchedAssetID != nil,empty=matchedLocator==nil&&matchedAssetID==nil&&replacementLocatorID==nil;guard KernelCanonicalHashV1.validSHA256(inputSHA256),evaluatedAt.timeIntervalSinceReferenceDate.isFinite,candidateLocators.count<=AssetLocatorLimitsV1.maximumCandidates,Set(candidateLocators.map(\.locatorID)).count==candidateLocators.count,candidateLocators==candidateLocators.sorted(by:{$0.locatorID.uuidString<$1.locatorID.uuidString}),((outcome == .matched || outcome == .retired || outcome == .revoked) ? selected && replacementLocatorID==nil : true),(outcome == .replaced ? selected && replacementLocatorID != nil:true),([.noMatch,.foreignWorkspace,.damagedOrIncomplete].contains(outcome) ? empty:true),(outcome == .ambiguous ? empty && candidateLocators.count>1:true),resolutionSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw AssetLocatorFailureV1.invalidValue}}
    private var basis:Basis{.init(workspaceID:workspaceID,source:source,inputSHA256:inputSHA256,outcome:outcome,matchedLocator:matchedLocator,matchedAssetID:matchedAssetID,replacementLocatorID:replacementLocatorID,candidateLocators:candidateLocators,evaluatedAt:evaluatedAt)};private struct Basis:Codable{let workspaceID:WorkspaceID;let source:LocatorInputSourceV1;let inputSHA256:String;let outcome:LocatorResolutionOutcomeV1;let matchedLocator:AssetLocatorReferenceV1?;let matchedAssetID:UUID?;let replacementLocatorID:UUID?;let candidateLocators:[AssetLocatorReferenceV1];let evaluatedAt:Date}}

enum LocatorBindingActionV1: String, Codable, CaseIterable, Hashable, Sendable {
    case bind = "BIND"
    case rebind = "REBIND"
    case retire = "RETIRE"
    case revoke = "REVOKE"
    case replace = "REPLACE"
    case rotateSigningKey = "ROTATE_SIGNING_KEY"
}

struct LocatorBindingPreviewV1: Codable, Equatable, Sendable {
    let workspaceID: WorkspaceID
    let action: LocatorBindingActionV1
    let before: AssetLocatorReferenceV1?
    let after: AssetLocatorReferenceV1
    let replacement: AssetLocatorReferenceV1?
    let generatedAt: Date
    let previewSHA256: String

    init(workspaceID: WorkspaceID, action: LocatorBindingActionV1,
         before: AssetLocatorReferenceV1?, after: AssetLocatorReferenceV1,
         replacement: AssetLocatorReferenceV1?, generatedAt: Date) throws {
        self.workspaceID = workspaceID; self.action = action; self.before = before
        self.after = after; self.replacement = replacement; self.generatedAt = generatedAt
        previewSHA256 = try WorkspaceMutationCanonicalV1.sha256(
            Basis(workspaceID: workspaceID, action: action, before: before,
                  after: after, replacement: replacement, generatedAt: generatedAt)
        )
        try validate()
    }

    func validate() throws {
        try before?.validate(); try after.validate(); try replacement?.validate()
        guard generatedAt.timeIntervalSinceReferenceDate.isFinite,
              (action == .bind) == (before == nil),
              (action == .replace) == (replacement != nil),
              previewSHA256 == (try WorkspaceMutationCanonicalV1.sha256(basis)) else {
            throw AssetLocatorFailureV1.invalidValue
        }
    }

    func validate(before beforeValue: AssetLocatorV1?, after afterValue: AssetLocatorV1,
                  replacement replacementValue: AssetLocatorV1?) throws {
        try validate(); try beforeValue?.validate(); try afterValue.validate()
        try replacementValue?.validate()
        let beforeReference = try beforeValue?.reference
        let replacementReference = try replacementValue?.reference
        guard workspaceID == afterValue.workspaceID, before == beforeReference,
              after == (try afterValue.reference), replacement == replacementReference else {
            throw AssetLocatorFailureV1.invalidValue
        }
        switch action {
        case .bind:
            guard beforeValue == nil, afterValue.revision == 1,
                  afterValue.state == .active, replacementValue == nil else {
                throw AssetLocatorFailureV1.invalidValue
            }
        case .rebind:
            guard let beforeValue, replacementValue == nil, afterValue.state == .active else {
                throw AssetLocatorFailureV1.invalidValue
            }
            try afterValue.validateSuccessor(of: beforeValue)
            guard afterValue.assetID != beforeValue.assetID ||
                    afterValue.lookupKey != beforeValue.lookupKey else {
                throw AssetLocatorFailureV1.invalidValue
            }
        case .retire, .revoke:
            let expectedState: AssetLocatorStateV1 = action == .retire ? .retired : .revoked
            guard let beforeValue, replacementValue == nil,
                  afterValue.state == expectedState else {
                throw AssetLocatorFailureV1.invalidValue
            }
            try afterValue.validateSuccessor(of: beforeValue)
        case .replace:
            guard let beforeValue, let replacementValue,
                  afterValue.state == .replaced,
                  afterValue.replacedByLocatorID == replacementValue.locatorID,
                  replacementValue.state == .active, replacementValue.revision == 1,
                  replacementValue.workspaceID == workspaceID else {
                throw AssetLocatorFailureV1.invalidValue
            }
            try afterValue.validateSuccessor(of: beforeValue)
        case .rotateSigningKey:
            guard let beforeValue, replacementValue == nil, afterValue.state == .active,
                  afterValue.assetID == beforeValue.assetID,
                  case .localSigned(let old) = beforeValue.representation,
                  case .localSigned(let new) = afterValue.representation,
                  old.signingKey.keyID != new.signingKey.keyID else {
                throw AssetLocatorFailureV1.invalidValue
            }
            try afterValue.validateSuccessor(of: beforeValue)
        }
    }

    private var basis: Basis {
        .init(workspaceID: workspaceID, action: action, before: before,
              after: after, replacement: replacement, generatedAt: generatedAt)
    }
    private struct Basis: Codable {
        let workspaceID: WorkspaceID; let action: LocatorBindingActionV1
        let before: AssetLocatorReferenceV1?; let after: AssetLocatorReferenceV1
        let replacement: AssetLocatorReferenceV1?; let generatedAt: Date
    }
}

struct LocatorBindingReceiptV1:Codable,Equatable,Sendable{static let schemaVersion=1;let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let action:LocatorBindingActionV1;let before:AssetLocatorReferenceV1?;let after:AssetLocatorReferenceV1;let replacement:AssetLocatorReferenceV1?;let previewGeneratedAt:Date;let previewSHA256:String;let recordedBy:ActorSnapshotV1;let predecessorReceiptID:UUID?;let predecessorReceiptSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date;let receiptSHA256:String
    init(receiptID:UUID,preview:LocatorBindingPreviewV1,recordedBy:ActorSnapshotV1,predecessor:Self?,revision:UInt64,mutationID:MutationIDV1,recordedAt:Date)throws{schemaVersion=Self.schemaVersion;self.receiptID=receiptID;workspaceID=preview.workspaceID;action=preview.action;before=preview.before;after=preview.after;replacement=preview.replacement;previewGeneratedAt=preview.generatedAt;previewSHA256=preview.previewSHA256;self.recordedBy=recordedBy;predecessorReceiptID=predecessor?.receiptID;predecessorReceiptSHA256=predecessor?.receiptSHA256;self.revision=revision;self.mutationID=mutationID;self.recordedAt=recordedAt;receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,receiptID:receiptID,workspaceID:preview.workspaceID,action:preview.action,before:preview.before,after:preview.after,replacement:preview.replacement,previewGeneratedAt:preview.generatedAt,previewSHA256:preview.previewSHA256,recordedBy:recordedBy,predecessorReceiptID:predecessor?.receiptID,predecessorReceiptSHA256:predecessor?.receiptSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt));try validate(preview:preview,predecessor:predecessor)}
    var reconstructedPreview:LocatorBindingPreviewV1{get throws{try .init(workspaceID:workspaceID,action:action,before:before,after:after,replacement:replacement,generatedAt:previewGeneratedAt)}}
    func validateIntrinsic()throws{let preview=try reconstructedPreview;try preview.validate();try recordedBy.validate();try before?.validate();try after.validate();try replacement?.validate();guard schemaVersion==Self.schemaVersion,receiptID != Self.zero,recordedBy.workspaceID==workspaceID,previewSHA256==preview.previewSHA256,recordedAt.timeIntervalSinceReferenceDate.isFinite,previewGeneratedAt.timeIntervalSinceReferenceDate.isFinite,recordedAt>=previewGeneratedAt,revision>0,(revision==1)==(predecessorReceiptID==nil),(predecessorReceiptID==nil)==(predecessorReceiptSHA256==nil),predecessorReceiptSHA256.map(KernelCanonicalHashV1.validSHA256) ?? true,receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(basis))else{throw AssetLocatorFailureV1.invalidDigest}}
    func validate(preview:LocatorBindingPreviewV1,predecessor:Self?)throws{try validateIntrinsic();try preview.validate();guard preview == (try reconstructedPreview),predecessorReceiptID==predecessor?.receiptID,predecessorReceiptSHA256==predecessor?.receiptSHA256,predecessor.map{$0.revision<UInt64.max&&revision==$0.revision+1&&$0.workspaceID==workspaceID} ?? (revision==1)else{throw AssetLocatorFailureV1.invalidSuccessor}}
    func rebound(to workspaceID:WorkspaceID,preview:LocatorBindingPreviewV1,recordedBy:ActorSnapshotV1,predecessor:Self?)throws->Self{guard preview.workspaceID==workspaceID,recordedBy.workspaceID==workspaceID else{throw AssetLocatorFailureV1.wrongWorkspace};return try .init(receiptID:receiptID,preview:preview,recordedBy:recordedBy,predecessor:predecessor,revision:revision,mutationID:mutationID,recordedAt:recordedAt)}
    private var basis:Basis{.init(schemaVersion:schemaVersion,receiptID:receiptID,workspaceID:workspaceID,action:action,before:before,after:after,replacement:replacement,previewGeneratedAt:previewGeneratedAt,previewSHA256:previewSHA256,recordedBy:recordedBy,predecessorReceiptID:predecessorReceiptID,predecessorReceiptSHA256:predecessorReceiptSHA256,revision:revision,mutationID:mutationID,recordedAt:recordedAt)};private struct Basis:Codable{let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let action:LocatorBindingActionV1;let before:AssetLocatorReferenceV1?;let after:AssetLocatorReferenceV1;let replacement:AssetLocatorReferenceV1?;let previewGeneratedAt:Date;let previewSHA256:String;let recordedBy:ActorSnapshotV1;let predecessorReceiptID:UUID?;let predecessorReceiptSHA256:String?;let revision:UInt64;let mutationID:MutationIDV1;let recordedAt:Date};private static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))}

struct FrozenAssetLocatorInterpretationV1:Codable,Equatable,Sendable{let locator:AssetLocatorReferenceV1;let bindingReceiptID:UUID;let bindingReceiptRevision:UInt64;let bindingReceiptSHA256:String;let assetIDAtCapture:UUID;let resolutionOutcome:LocatorResolutionOutcomeV1;init(locator:AssetLocatorReferenceV1,receipt:LocatorBindingReceiptV1,assetID:UUID)throws{try receipt.validateIntrinsic();guard receipt.after==locator else{throw AssetLocatorFailureV1.invalidValue};self.locator=locator;bindingReceiptID=receipt.receiptID;bindingReceiptRevision=receipt.revision;bindingReceiptSHA256=receipt.receiptSHA256;assetIDAtCapture=assetID;resolutionOutcome = .matched;try validate()};func validate()throws{try locator.validate();guard bindingReceiptID != Self.zero,bindingReceiptRevision>0,KernelCanonicalHashV1.validSHA256(bindingReceiptSHA256),assetIDAtCapture != Self.zero,resolutionOutcome == .matched else{throw AssetLocatorFailureV1.invalidValue}};private static let zero=UUID(uuid:(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))}

struct AssetLocatorLifecycleClosureV1: Codable, Equatable, Sendable {
    let locators: [AssetLocatorV1]
    let receipts: [LocatorBindingReceiptV1]

    init(locators: [AssetLocatorV1], receipts: [LocatorBindingReceiptV1]) throws {
        self.locators = locators.sorted {
            $0.locatorID == $1.locatorID
                ? $0.revision < $1.revision
                : $0.locatorID.uuidString < $1.locatorID.uuidString
        }
        self.receipts = receipts.sorted {
            $0.revision == $1.revision
                ? $0.receiptID.uuidString < $1.receiptID.uuidString
                : $0.revision < $1.revision
        }
        try validate()
    }

    func validate() throws {
        try locators.forEach { try $0.validate() }
        try receipts.forEach { try $0.validateIntrinsic() }

        var locatorByReference: [AssetLocatorReferenceV1: AssetLocatorV1] = [:]
        for locator in locators {
            let reference = try locator.reference
            guard locatorByReference.updateValue(locator, forKey: reference) == nil else {
                throw AssetLocatorFailureV1.ambiguous
            }
        }
        guard Set(receipts.map(\.receiptID)).count == receipts.count else {
            throw AssetLocatorFailureV1.ambiguous
        }
        let referencedLocators = Set(receipts.flatMap { receipt in
            [receipt.after] + (receipt.replacement.map { [$0] } ?? [])
        })
        guard referencedLocators == Set(locatorByReference.keys) else {
            throw AssetLocatorFailureV1.invalidValue
        }

        var heads: [AssetLocatorV1] = []
        for group in Dictionary(grouping: locators, by: \.locatorID).values {
            let ordered = group.sorted { $0.revision < $1.revision }
            guard ordered.first?.revision == 1 else {
                throw AssetLocatorFailureV1.invalidSuccessor
            }
            for index in 1..<ordered.count {
                try ordered[index].validateSuccessor(of: ordered[index - 1])
            }
            if let head = ordered.last { heads.append(head) }
        }

        var receiptByID: [UUID: LocatorBindingReceiptV1] = [:]
        var childCounts: [UUID: Int] = [:]
        for receipt in receipts {
            guard let afterValue = locatorByReference[receipt.after],
                  receipt.replacement.map({ locatorByReference[$0] != nil }) ?? true else {
                throw AssetLocatorFailureV1.invalidValue
            }
            let beforeValue = receipt.before.flatMap { locatorByReference[$0] }
            let replacementValue = receipt.replacement.flatMap { locatorByReference[$0] }
            guard (receipt.before == nil) == (beforeValue == nil) else {
                throw AssetLocatorFailureV1.invalidValue
            }
            guard receipt.workspaceID == afterValue.workspaceID,
                  receipt.mutationID == afterValue.mutationID,
                  replacementValue.map({ $0.mutationID == receipt.mutationID }) ?? true else {
                throw AssetLocatorFailureV1.invalidValue
            }
            try receipt.reconstructedPreview.validate(
                before: beforeValue,
                after: afterValue,
                replacement: replacementValue
            )
            if let predecessorID = receipt.predecessorReceiptID {
                guard let predecessor = receiptByID[predecessorID] else {
                    throw AssetLocatorFailureV1.invalidSuccessor
                }
                try receipt.validate(
                    preview: receipt.reconstructedPreview,
                    predecessor: predecessor
                )
                childCounts[predecessorID, default: 0] += 1
                guard childCounts[predecessorID] == 1 else {
                    throw AssetLocatorFailureV1.ambiguous
                }
            } else {
                try receipt.validate(
                    preview: receipt.reconstructedPreview,
                    predecessor: nil
                )
            }
            guard receiptByID.updateValue(receipt, forKey: receipt.receiptID) == nil else {
                throw AssetLocatorFailureV1.ambiguous
            }
        }

        let activeByLookupKey = Dictionary(
            grouping: heads.filter { $0.state == .active },
            by: \.lookupKey
        )
        guard activeByLookupKey.values.allSatisfy({ $0.count == 1 }) else {
            throw AssetLocatorFailureV1.ambiguous
        }
    }
}

enum AssetLocatorCanonicalCodecV1{static func encode<T:Encodable>(_ value:T)throws->Data{let e=JSONEncoder();e.outputFormatting=[.sortedKeys,.withoutEscapingSlashes];e.dateEncodingStrategy = .millisecondsSince1970;return try e.encode(value)};static func decode<T:Codable>(_ type:T.Type,from data:Data)throws->T{let d=JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;let value=try d.decode(type,from:data);guard try encode(value)==data else{throw AssetLocatorFailureV1.invalidDigest};return value}}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_AssetSemantics_AssetLocatorContractsV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_AssetSemantics_AssetLocatorContractsV1_swift {
    /// Typed C37 boundary: inherited owners may retain an immutable pose
    /// reference, but cannot infer pose, compliance, or current-state truth.
    static func validate(reference: AssetPoseEventReferenceV1,
                         in workspaceID: WorkspaceID) throws {
        try reference.validate()
        guard reference.workspaceID == workspaceID else {
            throw PlacementPoseFailureV1.wrongWorkspace
        }
    }
}
// C30: this seam consumes only the frozen, metadata-only operating-context projection.
enum C30ConsumerBoundaryV1_Domain_AssetSemantics_AssetLocatorContractsV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Domain/AssetSemantics/AssetLocatorContractsV1.swift", role: .asset)
}

enum C31LightingAssetLocatorBoundaryV1 {
    static let searchUsesStableAssetAndLocatorIdentifiers = true
    static let privateLocatorPayloadIsExcluded = true
    static let locatorDoesNotImplyLightingCondition = true
}
// MARK: - C32 assistance asset locator boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Domain_AssetSemantics_AssetLocatorContractsV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedEffectRebindsCanonicalLocator = true

    static func validateProposal(_ proposal: AssistanceProposalV1, in context: AssistanceProposalEvaluationContextV1) throws {
        try proposal.validate()
        try context.validate()
        guard proposal.verificationState.rawValue == AssistanceProposalVerificationStateV1.unverified.rawValue,
              context.policy.manualFallback == .typeManually else {
            throw AssistanceContractFailureV1.incompatibleCapability
        }
        if let reason = try proposal.expiryReason(in: context) {
            throw AssistanceContractFailureV1.expired(reason)
        }
    }

    static func validateAcceptanceReceipt(_ receipt: AssistanceAcceptanceReceiptV1) throws {
        try receipt.validate()
    }
}
