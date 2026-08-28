import Foundation

enum PrivacyTransformFailureV1: Error, Equatable, Sendable {
    case invalidValue, incompatibleVersion, wrongWorkspace, wrongAudience, wrongPolicy
    case immutableOriginal, invalidCoordinates, nondeterministicRegions, metadataNotSanitized
    case digestMismatch, staleDerivative, reviewRequired, rejected, invalidSuccessor, partialEffect
}

enum FieldReferencePrivacyBoundaryV1 {
    /// A privacy derivative is distinct content and cannot replace immutable
    /// licensed/synthetic reference-pack source bytes in-place.
    static func validateNoInPlaceTransform(original: ContentReferenceV1, derivative: ContentReferenceV1) throws {
        guard original.byteRole == .immutableOriginal,
              derivative.byteRole == .derivative,
              original.contentID != derivative.contentID else {
            throw PrivacyTransformFailureV1.immutableOriginal
        }
    }
}

enum PrivacyTransformKindV1: String, CaseIterable, Codable, Hashable, Sendable {
    case solidFill = "SOLID_FILL"
    case pixelate = "PIXELATE"
    case blur = "BLUR"
}

enum PrivacyTransformReasonV1: String, CaseIterable, Codable, Hashable, Sendable {
    case person = "PERSON"
    case identifyingMark = "IDENTIFYING_MARK"
    case vehicleIdentifier = "VEHICLE_IDENTIFIER"
    case confidentialInformation = "CONFIDENTIAL_INFORMATION"
    case unrelatedPrivateDetail = "UNRELATED_PRIVATE_DETAIL"
}

enum PrivacyReviewDecisionV1: String, CaseIterable, Codable, Hashable, Sendable {
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

enum PrivacyTransformStaleStateV1: String, CaseIterable, Codable, Hashable, Sendable {
    case current = "CURRENT"
    case sourceChanged = "SOURCE_CHANGED"
    case policyChanged = "POLICY_CHANGED"
    case expired = "EXPIRED"
}

enum PrivacyMetadataSanitationResultV1: String, CaseIterable, Codable, Hashable, Sendable {
    case complete = "COMPLETE"
    case failed = "FAILED"
}
enum PrivacyRegionOverlapBehaviorV1:String,Codable,Hashable,Sendable{case applyInAscendingOrder="APPLY_IN_ASCENDING_ORDER"}

enum PrivacyProjectionDenialV1: String, CaseIterable, Codable, Hashable, Sendable {
    case missingReview = "MISSING_REVIEW"
    case rejected = "REJECTED"
    case stale = "STALE"
    case wrongAudience = "WRONG_AUDIENCE"
    case wrongPolicy = "WRONG_POLICY"
    case sourceChanged = "SOURCE_CHANGED"
    case digestMismatch = "DIGEST_MISMATCH"
    case metadataNotSanitized = "METADATA_NOT_SANITIZED"
}

enum PrivacyTransformValidationV1 {
    static let coordinateScale: Int32 = 1_000_000
    static let maximumRegions = 512
    static let maximumTextBytes = 512
    static func text(_ value: String) throws { guard value == value.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value.utf8.count <= maximumTextBytes else { throw PrivacyTransformFailureV1.invalidValue } }
    static func digest(_ value: String) throws { guard KernelCanonicalHashV1.validSHA256(value) else { throw PrivacyTransformFailureV1.digestMismatch } }
    static func workspace(_ workspaceID: WorkspaceID, matches value: String) -> Bool { workspaceID.rawValue.uuidString.lowercased() == value.lowercased() }
}

struct PrivacyNormalizedRectV1: Codable, Equatable, Hashable, Sendable {
    let x: Int32; let y: Int32; let width: Int32; let height: Int32
    init(x: Int32, y: Int32, width: Int32, height: Int32) throws {
        guard x >= 0, y >= 0, width > 0, height > 0,
              x <= PrivacyTransformValidationV1.coordinateScale - width,
              y <= PrivacyTransformValidationV1.coordinateScale - height else { throw PrivacyTransformFailureV1.invalidCoordinates }
        self.x=x; self.y=y; self.width=width; self.height=height
    }
    func validate() throws { _ = try Self(x: x, y: y, width: width, height: height) }
}

extension PrivacyNormalizedRectV1 {
    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(x: values.decode(Int32.self, forKey: .x),
                      y: values.decode(Int32.self, forKey: .y),
                      width: values.decode(Int32.self, forKey: .width),
                      height: values.decode(Int32.self, forKey: .height))
    }
}

enum PrivacyCoordinateSpaceV1: String, CaseIterable, Codable, Hashable, Sendable {
    case normalizedImage = "NORMALIZED_IMAGE_V1"
    case pixelImage = "PIXEL_IMAGE_V1"
}

enum PrivacyImageOrientationV1: String, CaseIterable, Codable, Hashable, Sendable {
    case up = "UP"
    case upMirrored = "UP_MIRRORED"
    case down = "DOWN"
    case downMirrored = "DOWN_MIRRORED"
    case left = "LEFT"
    case leftMirrored = "LEFT_MIRRORED"
    case right = "RIGHT"
    case rightMirrored = "RIGHT_MIRRORED"
}

struct PrivacyCoordinateScaleV1: Codable, Equatable, Hashable, Sendable {
    let numerator: UInt32
    let denominator: UInt32
    init(numerator: UInt32, denominator: UInt32) throws {
        guard numerator > 0, denominator > 0, numerator <= 16_384, denominator <= 16_384,
              Self.gcd(numerator, denominator) == 1 else { throw PrivacyTransformFailureV1.invalidCoordinates }
        self.numerator = numerator; self.denominator = denominator
    }
    static let identity = try! PrivacyCoordinateScaleV1(numerator: 1, denominator: 1)
    private static func gcd(_ a: UInt32, _ b: UInt32) -> UInt32 { var x=a,y=b;while y != 0{let r=x%y;x=y;y=r};return x }
}

struct PrivacyIntegerRectV1: Codable, Equatable, Hashable, Sendable {
    let x:Int32;let y:Int32;let width:Int32;let height:Int32
    init(x:Int32,y:Int32,width:Int32,height:Int32)throws{guard x>=0,y>=0,width>0,height>0 else{throw PrivacyTransformFailureV1.invalidCoordinates};self.x=x;self.y=y;self.width=width;self.height=height}
}

enum PrivacyCoordinateProjectionV1 {
    static func normalized(sourceBounds:PrivacyIntegerRectV1,space:PrivacyCoordinateSpaceV1,
                           orientation:PrivacyImageOrientationV1,pixelWidth:Int32?,pixelHeight:Int32?,
                           scale:PrivacyCoordinateScaleV1)throws->PrivacyNormalizedRectV1{
        let canvasWidth:Int64,canvasHeight:Int64
        let validatedScale = try PrivacyCoordinateScaleV1(numerator: scale.numerator, denominator: scale.denominator)
        guard validatedScale == scale else { throw PrivacyTransformFailureV1.invalidCoordinates }
        func scaled(_ value:Int32)throws->Int64{
            let product=Int64(value)*Int64(scale.numerator),denominator=Int64(scale.denominator)
            guard product>=0,product%denominator==0 else{throw PrivacyTransformFailureV1.invalidCoordinates}
            return product/denominator
        }
        let x:Int64,y:Int64,w:Int64,h:Int64
        switch space {
        case .normalizedImage:
            guard pixelWidth == nil,pixelHeight == nil,scale == .identity else{throw PrivacyTransformFailureV1.invalidCoordinates}
            canvasWidth=Int64(PrivacyTransformValidationV1.coordinateScale);canvasHeight=canvasWidth
            x=Int64(sourceBounds.x);y=Int64(sourceBounds.y);w=Int64(sourceBounds.width);h=Int64(sourceBounds.height)
        case .pixelImage:
            guard let pixelWidth,let pixelHeight,(1...16_384).contains(pixelWidth),(1...16_384).contains(pixelHeight) else{throw PrivacyTransformFailureV1.invalidCoordinates}
            canvasWidth=Int64(pixelWidth);canvasHeight=Int64(pixelHeight)
            x=try scaled(sourceBounds.x);y=try scaled(sourceBounds.y);w=try scaled(sourceBounds.width);h=try scaled(sourceBounds.height)
        }
        guard x>=0,y>=0,w>0,h>0,x+w<=canvasWidth,y+h<=canvasHeight else{throw PrivacyTransformFailureV1.invalidCoordinates}
        let ox:Int64,oy:Int64,ow:Int64,oh:Int64,orientedWidth:Int64,orientedHeight:Int64
        switch orientation {
        case .up: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(x,y,w,h,canvasWidth,canvasHeight)
        case .upMirrored: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(canvasWidth-x-w,y,w,h,canvasWidth,canvasHeight)
        case .down: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(canvasWidth-x-w,canvasHeight-y-h,w,h,canvasWidth,canvasHeight)
        case .downMirrored: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(x,canvasHeight-y-h,w,h,canvasWidth,canvasHeight)
        case .right: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(canvasHeight-y-h,x,h,w,canvasHeight,canvasWidth)
        case .rightMirrored: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(canvasHeight-y-h,canvasWidth-x-w,h,w,canvasHeight,canvasWidth)
        case .left: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(y,canvasWidth-x-w,h,w,canvasHeight,canvasWidth)
        case .leftMirrored: (ox,oy,ow,oh,orientedWidth,orientedHeight)=(y,x,h,w,canvasHeight,canvasWidth)
        }
        let unit=Int64(PrivacyTransformValidationV1.coordinateScale)
        func floorScaled(_ value:Int64,_ extent:Int64)->Int64{value*unit/extent}
        func ceilScaled(_ value:Int64,_ extent:Int64)->Int64{(value*unit+extent-1)/extent}
        let nx=floorScaled(ox,orientedWidth),ny=floorScaled(oy,orientedHeight)
        let mx=ceilScaled(ox+ow,orientedWidth),my=ceilScaled(oy+oh,orientedHeight)
        return try PrivacyNormalizedRectV1(x:Int32(nx),y:Int32(ny),width:Int32(mx-nx),height:Int32(my-ny))
    }
}

struct PrivacyTransformPolicyV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int; let policyID:UUID; let workspaceID:WorkspaceID; let purpose:String
    let audience:EvidenceAudienceV1; let allowedTransformKinds:[PrivacyTransformKindV1]; let allowedReasons:[PrivacyTransformReasonV1]
    let metadataSanitationRequired:Bool; let reviewRequired:Bool; let maximumAgeSeconds:UInt64?; let denyByDefault:Bool
    let effectiveAt:Date; let supersedesPolicyID:UUID?; let revision:UInt64; let mutationID:MutationIDV1; let policySHA256:String
    init(policyID:UUID,workspaceID:WorkspaceID,purpose:String,audience:EvidenceAudienceV1,allowedTransformKinds:[PrivacyTransformKindV1],allowedReasons:[PrivacyTransformReasonV1],maximumAgeSeconds:UInt64?=nil,effectiveAt:Date,supersedesPolicyID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{
        let kinds=allowedTransformKinds.sorted{$0.rawValue<$1.rawValue}, reasons=allowedReasons.sorted{$0.rawValue<$1.rawValue}
        schemaVersion=Self.schemaVersion;self.policyID=policyID;self.workspaceID=workspaceID;self.purpose=purpose;self.audience=audience;self.allowedTransformKinds=kinds;self.allowedReasons=reasons;metadataSanitationRequired=true;reviewRequired=true;self.maximumAgeSeconds=maximumAgeSeconds;denyByDefault=true;self.effectiveAt=effectiveAt;self.supersedesPolicyID=supersedesPolicyID;self.revision=revision;self.mutationID=mutationID
        policySHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,policyID:policyID,workspaceID:workspaceID,purpose:purpose,audience:audience,allowedTransformKinds:kinds,allowedReasons:reasons,metadataSanitationRequired:true,reviewRequired:true,maximumAgeSeconds:maximumAgeSeconds,denyByDefault:true,effectiveAt:effectiveAt,supersedesPolicyID:supersedesPolicyID,revision:revision,mutationID:mutationID));try validate()
    }
    func validate()throws{try PrivacyTransformValidationV1.text(purpose);guard revision>0,!allowedTransformKinds.isEmpty,!allowedReasons.isEmpty,allowedTransformKinds==allowedTransformKinds.sorted(by:{$0.rawValue<$1.rawValue}),allowedReasons==allowedReasons.sorted(by:{$0.rawValue<$1.rawValue}),Set(allowedTransformKinds).count==allowedTransformKinds.count,Set(allowedReasons).count==allowedReasons.count,metadataSanitationRequired,reviewRequired,denyByDefault,maximumAgeSeconds.map{$0>0} ?? true,policySHA256 == (try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:schemaVersion,policyID:policyID,workspaceID:workspaceID,purpose:purpose,audience:audience,allowedTransformKinds:allowedTransformKinds,allowedReasons:allowedReasons,metadataSanitationRequired:metadataSanitationRequired,reviewRequired:reviewRequired,maximumAgeSeconds:maximumAgeSeconds,denyByDefault:denyByDefault,effectiveAt:effectiveAt,supersedesPolicyID:supersedesPolicyID,revision:revision,mutationID:mutationID))) else{throw PrivacyTransformFailureV1.invalidValue}}
    func validateSuccessor(of old:Self)throws{try validate();try old.validate();guard policyID != old.policyID,supersedesPolicyID==old.policyID,workspaceID==old.workspaceID,old.revision<UInt64.max,revision==old.revision+1 else{throw PrivacyTransformFailureV1.invalidSuccessor}}
    private struct Basis:Codable{let schemaVersion:Int;let policyID:UUID;let workspaceID:WorkspaceID;let purpose:String;let audience:EvidenceAudienceV1;let allowedTransformKinds:[PrivacyTransformKindV1];let allowedReasons:[PrivacyTransformReasonV1];let metadataSanitationRequired:Bool;let reviewRequired:Bool;let maximumAgeSeconds:UInt64?;let denyByDefault:Bool;let effectiveAt:Date;let supersedesPolicyID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct PrivacyRegionV1: Codable, Equatable, Hashable, Sendable {
    static let schemaVersion=1
    let schemaVersion:Int;let regionID:UUID;let workspaceID:WorkspaceID;let sourceContentID:String;let sourceRevision:UInt64;let sourceSHA256:String
    let coordinateSpace:PrivacyCoordinateSpaceV1;let orientation:PrivacyImageOrientationV1;let pixelWidth:Int32?;let pixelHeight:Int32?;let coordinateScale:PrivacyCoordinateScaleV1;let sourceBounds:PrivacyIntegerRectV1;let bounds:PrivacyNormalizedRectV1
    let transformKind:PrivacyTransformKindV1;let reason:PrivacyTransformReasonV1;let author:ActorSnapshotV1;let order:UInt32;let authoredAt:Date;let revision:UInt64;let mutationID:MutationIDV1;let regionSHA256:String
    var coordinateSpaceVersion:String{coordinateSpace.rawValue}
    init(regionID:UUID,workspaceID:WorkspaceID,sourceContentID:String,sourceRevision:UInt64,sourceSHA256:String,coordinateSpace:PrivacyCoordinateSpaceV1,orientation:PrivacyImageOrientationV1,sourceBounds:PrivacyIntegerRectV1,pixelWidth:Int32?=nil,pixelHeight:Int32?=nil,coordinateScale:PrivacyCoordinateScaleV1 = .identity,transformKind:PrivacyTransformKindV1,reason:PrivacyTransformReasonV1,author:ActorSnapshotV1,order:UInt32,authoredAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{
        let normalized=try PrivacyCoordinateProjectionV1.normalized(sourceBounds:sourceBounds,space:coordinateSpace,orientation:orientation,pixelWidth:pixelWidth,pixelHeight:pixelHeight,scale:coordinateScale)
        schemaVersion=Self.schemaVersion;self.regionID=regionID;self.workspaceID=workspaceID;self.sourceContentID=sourceContentID;self.sourceRevision=sourceRevision;self.sourceSHA256=sourceSHA256;self.coordinateSpace=coordinateSpace;self.orientation=orientation;self.pixelWidth=pixelWidth;self.pixelHeight=pixelHeight;self.coordinateScale=coordinateScale;self.sourceBounds=sourceBounds;bounds=normalized;self.transformKind=transformKind;self.reason=reason;self.author=author;self.order=order;self.authoredAt=authoredAt;self.revision=revision;self.mutationID=mutationID
        regionSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,regionID:regionID,workspaceID:workspaceID,sourceContentID:sourceContentID,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,coordinateSpace:coordinateSpace,orientation:orientation,pixelWidth:pixelWidth,pixelHeight:pixelHeight,coordinateScale:coordinateScale,sourceBounds:sourceBounds,bounds:normalized,transformKind:transformKind,reason:reason,author:author,order:order,authoredAt:authoredAt,revision:revision,mutationID:mutationID));try validate()
    }
    init(regionID:UUID,workspaceID:WorkspaceID,sourceContentID:String,sourceRevision:UInt64,sourceSHA256:String,coordinateSpaceVersion:String,bounds:PrivacyNormalizedRectV1,transformKind:PrivacyTransformKindV1,reason:PrivacyTransformReasonV1,author:ActorSnapshotV1,order:UInt32,authoredAt:Date,revision:UInt64=1,mutationID:MutationIDV1)throws{
        guard let space=PrivacyCoordinateSpaceV1(rawValue:coordinateSpaceVersion),space == .normalizedImage else{throw PrivacyTransformFailureV1.invalidCoordinates}
        try self.init(regionID:regionID,workspaceID:workspaceID,sourceContentID:sourceContentID,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,coordinateSpace:space,orientation:.up,sourceBounds:try .init(x:bounds.x,y:bounds.y,width:bounds.width,height:bounds.height),transformKind:transformKind,reason:reason,author:author,order:order,authoredAt:authoredAt,revision:revision,mutationID:mutationID)
    }
    func validate()throws{try PrivacyTransformValidationV1.text(sourceContentID);try PrivacyTransformValidationV1.digest(sourceSHA256);try author.validate();let expected=try PrivacyCoordinateProjectionV1.normalized(sourceBounds:sourceBounds,space:coordinateSpace,orientation:orientation,pixelWidth:pixelWidth,pixelHeight:pixelHeight,scale:coordinateScale);guard schemaVersion==Self.schemaVersion,sourceRevision>0,revision==1,author.workspaceID==workspaceID,bounds==expected,regionSHA256==(try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:schemaVersion,regionID:regionID,workspaceID:workspaceID,sourceContentID:sourceContentID,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,coordinateSpace:coordinateSpace,orientation:orientation,pixelWidth:pixelWidth,pixelHeight:pixelHeight,coordinateScale:coordinateScale,sourceBounds:sourceBounds,bounds:bounds,transformKind:transformKind,reason:reason,author:author,order:order,authoredAt:authoredAt,revision:revision,mutationID:mutationID))) else{throw PrivacyTransformFailureV1.invalidValue}}
    private struct Basis:Codable{let schemaVersion:Int;let regionID:UUID;let workspaceID:WorkspaceID;let sourceContentID:String;let sourceRevision:UInt64;let sourceSHA256:String;let coordinateSpace:PrivacyCoordinateSpaceV1;let orientation:PrivacyImageOrientationV1;let pixelWidth:Int32?;let pixelHeight:Int32?;let coordinateScale:PrivacyCoordinateScaleV1;let sourceBounds:PrivacyIntegerRectV1;let bounds:PrivacyNormalizedRectV1;let transformKind:PrivacyTransformKindV1;let reason:PrivacyTransformReasonV1;let author:ActorSnapshotV1;let order:UInt32;let authoredAt:Date;let revision:UInt64;let mutationID:MutationIDV1}
}

struct PrivacyMetadataSanitationEvidenceV1:Codable,Equatable,Hashable,Sendable{let sanitizerID:String;let sanitizerVersion:String;let result:PrivacyMetadataSanitationResultV1;let retainedSourceMetadataKeys:[String];init(sanitizerID:String,sanitizerVersion:String,result:PrivacyMetadataSanitationResultV1,retainedSourceMetadataKeys:[String]=[])throws{try PrivacyTransformValidationV1.text(sanitizerID);try PrivacyTransformValidationV1.text(sanitizerVersion);guard result == .complete,retainedSourceMetadataKeys.isEmpty else{throw PrivacyTransformFailureV1.metadataNotSanitized};self.sanitizerID=sanitizerID;self.sanitizerVersion=sanitizerVersion;self.result=result;self.retainedSourceMetadataKeys=retainedSourceMetadataKeys}}

struct PrivacyTransformManifestV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let manifestID:UUID;let workspaceID:WorkspaceID;let original:ContentReferenceV1;let sourceRevision:UInt64;let sourceSHA256:String;let derivative:ContentReferenceV1;let derivativeSHA256:String;let policyID:UUID;let policyRevision:UInt64;let policySHA256:String;let audience:EvidenceAudienceV1;let orderedRegions:[PrivacyRegionV1];let overlapBehavior:PrivacyRegionOverlapBehaviorV1;let rendererID:String;let rendererVersion:String;let metadataSanitation:PrivacyMetadataSanitationEvidenceV1;let staleState:PrivacyTransformStaleStateV1;let renderedAt:Date;let supersedesManifestID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let manifestSHA256:String
    init(manifestID:UUID,workspaceID:WorkspaceID,original:ContentReferenceV1,sourceRevision:UInt64,sourceSHA256:String,derivative:ContentReferenceV1,derivativeSHA256:String,policy:PrivacyTransformPolicyV1,orderedRegions:[PrivacyRegionV1],rendererID:String,rendererVersion:String,metadataSanitation:PrivacyMetadataSanitationEvidenceV1,staleState:PrivacyTransformStaleStateV1 = .current,renderedAt:Date,supersedesManifestID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.manifestID=manifestID;self.workspaceID=workspaceID;self.original=original;self.sourceRevision=sourceRevision;self.sourceSHA256=sourceSHA256;self.derivative=derivative;self.derivativeSHA256=derivativeSHA256;policyID=policy.policyID;policyRevision=policy.revision;policySHA256=policy.policySHA256;audience=policy.audience;self.orderedRegions=orderedRegions;overlapBehavior = .applyInAscendingOrder;self.rendererID=rendererID;self.rendererVersion=rendererVersion;self.metadataSanitation=metadataSanitation;self.staleState=staleState;self.renderedAt=renderedAt;self.supersedesManifestID=supersedesManifestID;self.revision=revision;self.mutationID=mutationID;manifestSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,manifestID:manifestID,workspaceID:workspaceID,original:original,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,derivative:derivative,derivativeSHA256:derivativeSHA256,policyID:policy.policyID,policyRevision:policy.revision,policySHA256:policy.policySHA256,audience:policy.audience,orderedRegions:orderedRegions,overlapBehavior:.applyInAscendingOrder,rendererID:rendererID,rendererVersion:rendererVersion,metadataSanitation:metadataSanitation,staleState:staleState,renderedAt:renderedAt,supersedesManifestID:supersedesManifestID,revision:revision,mutationID:mutationID));try validate(policy:policy)}
    func validate(policy:PrivacyTransformPolicyV1)throws{try policy.validate();try PrivacyTransformValidationV1.digest(sourceSHA256);try PrivacyTransformValidationV1.digest(derivativeSHA256);try PrivacyTransformValidationV1.text(rendererID);try PrivacyTransformValidationV1.text(rendererVersion);try orderedRegions.forEach{$0.validate()};let shaOriginal=original.digests.digest(for:.sha256)?.hexadecimalValue,shaDerivative=derivative.digests.digest(for:.sha256)?.hexadecimalValue;guard revision>0,sourceRevision>0,policyID==policy.policyID,policyRevision==policy.revision,policySHA256==policy.policySHA256,audience==policy.audience,original.byteRole == .immutableOriginal,derivative.byteRole == .derivative,original.mediaType.hasPrefix("image/"),original.mediaType==derivative.mediaType,original.contentID != derivative.contentID,sourceSHA256 != derivativeSHA256,PrivacyTransformValidationV1.workspace(workspaceID,matches:original.workspaceID),PrivacyTransformValidationV1.workspace(workspaceID,matches:derivative.workspaceID),shaOriginal==sourceSHA256,shaDerivative==derivativeSHA256,!orderedRegions.isEmpty,orderedRegions.count<=PrivacyTransformValidationV1.maximumRegions,overlapBehavior == .applyInAscendingOrder,orderedRegions.map(\.order)==Array(0..<UInt32(orderedRegions.count)),Set(orderedRegions.map(\.regionID)).count==orderedRegions.count,orderedRegions.allSatisfy{$0.workspaceID==workspaceID&&$0.sourceContentID==original.contentID&&$0.sourceRevision==sourceRevision&&$0.sourceSHA256==sourceSHA256&&policy.allowedTransformKinds.contains($0.transformKind)&&policy.allowedReasons.contains($0.reason)},metadataSanitation.result == .complete,metadataSanitation.retainedSourceMetadataKeys.isEmpty,manifestSHA256==(try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:schemaVersion,manifestID:manifestID,workspaceID:workspaceID,original:original,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,derivative:derivative,derivativeSHA256:derivativeSHA256,policyID:policyID,policyRevision:policyRevision,policySHA256:policySHA256,audience:audience,orderedRegions:orderedRegions,overlapBehavior:overlapBehavior,rendererID:rendererID,rendererVersion:rendererVersion,metadataSanitation:metadataSanitation,staleState:staleState,renderedAt:renderedAt,supersedesManifestID:supersedesManifestID,revision:revision,mutationID:mutationID))) else{throw PrivacyTransformFailureV1.invalidValue}}
    func validateSuccessor(of old:Self,policy:PrivacyTransformPolicyV1)throws{try validate(policy:policy);try old.validate(policy:policy);guard manifestID != old.manifestID,supersedesManifestID==old.manifestID,workspaceID==old.workspaceID,original==old.original,sourceRevision==old.sourceRevision,sourceSHA256==old.sourceSHA256,old.revision<UInt64.max,revision==old.revision+1 else{throw PrivacyTransformFailureV1.invalidSuccessor}}
    private struct Basis:Codable{let schemaVersion:Int;let manifestID:UUID;let workspaceID:WorkspaceID;let original:ContentReferenceV1;let sourceRevision:UInt64;let sourceSHA256:String;let derivative:ContentReferenceV1;let derivativeSHA256:String;let policyID:UUID;let policyRevision:UInt64;let policySHA256:String;let audience:EvidenceAudienceV1;let orderedRegions:[PrivacyRegionV1];let overlapBehavior:PrivacyRegionOverlapBehaviorV1;let rendererID:String;let rendererVersion:String;let metadataSanitation:PrivacyMetadataSanitationEvidenceV1;let staleState:PrivacyTransformStaleStateV1;let renderedAt:Date;let supersedesManifestID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct PrivacyReviewReceiptV1:Codable,Equatable,Sendable{
    static let schemaVersion=1
    let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let manifestID:UUID;let manifestRevision:UInt64;let manifestSHA256:String;let derivativeContentID:String;let derivativeSHA256:String;let policyID:UUID;let policyRevision:UInt64;let policySHA256:String;let audience:EvidenceAudienceV1;let sourceContentID:String;let sourceRevision:UInt64;let sourceSHA256:String;let reviewer:ActorSnapshotV1;let decision:PrivacyReviewDecisionV1;let rationale:String;let reviewedAt:Date;let supersedesReceiptID:UUID?;let revision:UInt64;let mutationID:MutationIDV1;let receiptSHA256:String
    init(receiptID:UUID,workspaceID:WorkspaceID,manifest:PrivacyTransformManifestV1,policy:PrivacyTransformPolicyV1,reviewer:ActorSnapshotV1,decision:PrivacyReviewDecisionV1,rationale:String,reviewedAt:Date,supersedesReceiptID:UUID?=nil,revision:UInt64=1,mutationID:MutationIDV1)throws{schemaVersion=Self.schemaVersion;self.receiptID=receiptID;self.workspaceID=workspaceID;manifestID=manifest.manifestID;manifestRevision=manifest.revision;manifestSHA256=manifest.manifestSHA256;derivativeContentID=manifest.derivative.contentID;derivativeSHA256=manifest.derivativeSHA256;policyID=policy.policyID;policyRevision=policy.revision;policySHA256=policy.policySHA256;audience=policy.audience;sourceContentID=manifest.original.contentID;sourceRevision=manifest.sourceRevision;sourceSHA256=manifest.sourceSHA256;self.reviewer=reviewer;self.decision=decision;self.rationale=rationale;self.reviewedAt=reviewedAt;self.supersedesReceiptID=supersedesReceiptID;self.revision=revision;self.mutationID=mutationID;receiptSHA256=try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:Self.schemaVersion,receiptID:receiptID,workspaceID:workspaceID,manifestID:manifest.manifestID,manifestRevision:manifest.revision,manifestSHA256:manifest.manifestSHA256,derivativeContentID:manifest.derivative.contentID,derivativeSHA256:manifest.derivativeSHA256,policyID:policy.policyID,policyRevision:policy.revision,policySHA256:policy.policySHA256,audience:policy.audience,sourceContentID:manifest.original.contentID,sourceRevision:manifest.sourceRevision,sourceSHA256:manifest.sourceSHA256,reviewer:reviewer,decision:decision,rationale:rationale,reviewedAt:reviewedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID));try validate(manifest:manifest,policy:policy)}
    func validate(manifest:PrivacyTransformManifestV1,policy:PrivacyTransformPolicyV1)throws{try manifest.validate(policy:policy);try reviewer.validate();try PrivacyTransformValidationV1.text(rationale);guard revision>0,reviewer.workspaceID==workspaceID,reviewer.responsibility == .reviewedBy,manifestID==manifest.manifestID,manifestRevision==manifest.revision,manifestSHA256==manifest.manifestSHA256,derivativeContentID==manifest.derivative.contentID,derivativeSHA256==manifest.derivativeSHA256,policyID==policy.policyID,policyRevision==policy.revision,policySHA256==policy.policySHA256,audience==policy.audience,sourceContentID==manifest.original.contentID,sourceRevision==manifest.sourceRevision,sourceSHA256==manifest.sourceSHA256,receiptSHA256==(try WorkspaceMutationCanonicalV1.sha256(Basis(schemaVersion:schemaVersion,receiptID:receiptID,workspaceID:workspaceID,manifestID:manifestID,manifestRevision:manifestRevision,manifestSHA256:manifestSHA256,derivativeContentID:derivativeContentID,derivativeSHA256:derivativeSHA256,policyID:policyID,policyRevision:policyRevision,policySHA256:policySHA256,audience:audience,sourceContentID:sourceContentID,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,reviewer:reviewer,decision:decision,rationale:rationale,reviewedAt:reviewedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID))) else{throw PrivacyTransformFailureV1.invalidValue}}
    func validateSuccessor(of old:Self,manifest:PrivacyTransformManifestV1,policy:PrivacyTransformPolicyV1)throws{try validate(manifest:manifest,policy:policy);guard receiptID != old.receiptID,supersedesReceiptID==old.receiptID,workspaceID==old.workspaceID,manifestID==old.manifestID,old.revision<UInt64.max,revision==old.revision+1 else{throw PrivacyTransformFailureV1.invalidSuccessor}}
    private struct Basis:Codable{let schemaVersion:Int;let receiptID:UUID;let workspaceID:WorkspaceID;let manifestID:UUID;let manifestRevision:UInt64;let manifestSHA256:String;let derivativeContentID:String;let derivativeSHA256:String;let policyID:UUID;let policyRevision:UInt64;let policySHA256:String;let audience:EvidenceAudienceV1;let sourceContentID:String;let sourceRevision:UInt64;let sourceSHA256:String;let reviewer:ActorSnapshotV1;let decision:PrivacyReviewDecisionV1;let rationale:String;let reviewedAt:Date;let supersedesReceiptID:UUID?;let revision:UInt64;let mutationID:MutationIDV1}
}

struct PrivacyProjectionDecisionV1:Equatable,Sendable{let derivative:ContentReferenceV1?;let denial:PrivacyProjectionDenialV1?;var isAllowed:Bool{derivative != nil && denial == nil}}
enum PrivacyProjectionV1{
    static func decide(manifest:PrivacyTransformManifestV1?,review:PrivacyReviewReceiptV1?,policy:PrivacyTransformPolicyV1,requestedAudience:EvidenceAudienceV1,currentSourceRevision:UInt64,currentSourceSHA256:String,at now:Date)throws->PrivacyProjectionDecisionV1{
        guard let manifest else{return .init(derivative:nil,denial:.missingReview)}
        guard manifest.workspaceID == policy.workspaceID else{return .init(derivative:nil,denial:.wrongPolicy)}
        guard manifest.policyID==policy.policyID,manifest.policyRevision==policy.revision,manifest.policySHA256==policy.policySHA256 else{return .init(derivative:nil,denial:.wrongPolicy)}
        guard requestedAudience==policy.audience else{return .init(derivative:nil,denial:.wrongAudience)}
        guard manifest.sourceRevision==currentSourceRevision,manifest.sourceSHA256==currentSourceSHA256 else{return .init(derivative:nil,denial:.sourceChanged)}
        guard manifest.staleState == .current else{return .init(derivative:nil,denial:.stale)}
        if let age=policy.maximumAgeSeconds,now.timeIntervalSince(manifest.renderedAt)>Double(age){return .init(derivative:nil,denial:.stale)}
        guard manifest.metadataSanitation.result == .complete,manifest.metadataSanitation.retainedSourceMetadataKeys.isEmpty else{return .init(derivative:nil,denial:.metadataNotSanitized)}
        guard let review else{return .init(derivative:nil,denial:.missingReview)}
        guard review.workspaceID == manifest.workspaceID else{return .init(derivative:nil,denial:.digestMismatch)}
        do{try review.validate(manifest:manifest,policy:policy)}catch{return .init(derivative:nil,denial:.digestMismatch)}
        guard review.decision == .approved else{return .init(derivative:nil,denial:.rejected)}
        return .init(derivative:manifest.derivative,denial:nil)
    }
}

struct PrivacyTransformLifecycleClosureV1: Sendable {
    let policy: PrivacyTransformPolicyV1
    let regions: [PrivacyRegionV1]
    let manifest: PrivacyTransformManifestV1
    let review: PrivacyReviewReceiptV1?
    func validate() throws {
        guard policy.schemaVersion == PrivacyTransformPolicyV1.schemaVersion,
              manifest.schemaVersion == PrivacyTransformManifestV1.schemaVersion,
              review.map({ $0.schemaVersion == PrivacyReviewReceiptV1.schemaVersion }) ?? true else {
            throw PrivacyTransformFailureV1.incompatibleVersion
        }
        try policy.validate()
        try manifest.validate(policy: policy)
        guard manifest.workspaceID == policy.workspaceID,
              review.map({ $0.workspaceID == manifest.workspaceID }) ?? true else {
            throw PrivacyTransformFailureV1.wrongWorkspace
        }
        for region in regions {
            guard region.schemaVersion == PrivacyRegionV1.schemaVersion else { throw PrivacyTransformFailureV1.incompatibleVersion }
            try region.bounds.validate()
        }
        guard regions == manifest.orderedRegions else { throw PrivacyTransformFailureV1.nondeterministicRegions }
        if let review { try review.validate(manifest: manifest, policy: policy) }
    }
}

private enum PrivacyTransformRebindV1 {
    static func reference(_ value: ContentReferenceV1, to workspaceID: WorkspaceID) throws -> ContentReferenceV1 {
        try ContentReferenceV1(workspaceID: workspaceID.rawValue.uuidString.lowercased(), contentID: value.contentID, byteLength: value.byteLength, mediaType: value.mediaType, digests: value.digests, byteRole: value.byteRole, createdAt: value.createdAt)
    }
    static func actor(_ value: ActorSnapshotV1, to workspaceID: WorkspaceID) throws -> ActorSnapshotV1 {
        let local = try LocalActorReferenceV1(actorReferenceID: value.actor.actorReferenceID, workspaceID: workspaceID, partyID: value.actor.partyID, displayName: value.actor.displayName)
        return try ActorSnapshotV1(snapshotID: value.snapshotID, workspaceID: workspaceID, actor: local, responsibility: value.responsibility, displayNameAtTime: value.displayNameAtTime, capturedAt: value.capturedAt)
    }
}

extension PrivacyTransformPolicyV1 { func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(policyID:policyID,workspaceID:workspaceID,purpose:purpose,audience:audience,allowedTransformKinds:allowedTransformKinds,allowedReasons:allowedReasons,maximumAgeSeconds:maximumAgeSeconds,effectiveAt:effectiveAt,supersedesPolicyID:supersedesPolicyID,revision:revision,mutationID:mutationID)} }
extension PrivacyRegionV1 { func rebound(to workspaceID:WorkspaceID)throws->Self{try .init(regionID:regionID,workspaceID:workspaceID,sourceContentID:sourceContentID,sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,coordinateSpace:coordinateSpace,orientation:orientation,sourceBounds:sourceBounds,pixelWidth:pixelWidth,pixelHeight:pixelHeight,coordinateScale:coordinateScale,transformKind:transformKind,reason:reason,author:PrivacyTransformRebindV1.actor(author,to:workspaceID),order:order,authoredAt:authoredAt,revision:revision,mutationID:mutationID)} }
extension PrivacyTransformManifestV1 { func rebound(to workspaceID:WorkspaceID,policy:PrivacyTransformPolicyV1)throws->Self{let regions=try orderedRegions.map{$0.rebound(to:workspaceID)};return try .init(manifestID:manifestID,workspaceID:workspaceID,original:PrivacyTransformRebindV1.reference(original,to:workspaceID),sourceRevision:sourceRevision,sourceSHA256:sourceSHA256,derivative:PrivacyTransformRebindV1.reference(derivative,to:workspaceID),derivativeSHA256:derivativeSHA256,policy:policy,orderedRegions:regions,rendererID:rendererID,rendererVersion:rendererVersion,metadataSanitation:metadataSanitation,staleState:staleState,renderedAt:renderedAt,supersedesManifestID:supersedesManifestID,revision:revision,mutationID:mutationID)} }
extension PrivacyReviewReceiptV1 { func rebound(to workspaceID:WorkspaceID,manifest:PrivacyTransformManifestV1,policy:PrivacyTransformPolicyV1)throws->Self{try .init(receiptID:receiptID,workspaceID:workspaceID,manifest:manifest,policy:policy,reviewer:PrivacyTransformRebindV1.actor(reviewer,to:workspaceID),decision:decision,rationale:rationale,reviewedAt:reviewedAt,supersedesReceiptID:supersedesReceiptID,revision:revision,mutationID:mutationID)} }

enum PrivacyTransformCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(value)
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        return data
    }

    static func decode<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        guard !data.isEmpty, data.count <= ContentContractLimitsV1.maximumCanonicalBytes else {
            throw PrivacyTransformFailureV1.invalidValue
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let value = try decoder.decode(type, from: data)
        guard try encode(value) == data else { throw PrivacyTransformFailureV1.digestMismatch }
        return value
    }

    static func decodePolicy(from data: Data) throws -> PrivacyTransformPolicyV1 {
        let value = try decode(PrivacyTransformPolicyV1.self, from: data)
        guard value.schemaVersion == PrivacyTransformPolicyV1.schemaVersion else { throw PrivacyTransformFailureV1.incompatibleVersion }
        try value.validate(); return value
    }

    static func decodeRegion(from data: Data) throws -> PrivacyRegionV1 {
        let value = try decode(PrivacyRegionV1.self, from: data)
        guard value.schemaVersion == PrivacyRegionV1.schemaVersion else { throw PrivacyTransformFailureV1.incompatibleVersion }
        try value.validate(); try value.bounds.validate(); return value
    }

    static func decodeManifest(from data: Data, policy: PrivacyTransformPolicyV1) throws -> PrivacyTransformManifestV1 {
        let value = try decode(PrivacyTransformManifestV1.self, from: data)
        guard value.schemaVersion == PrivacyTransformManifestV1.schemaVersion else { throw PrivacyTransformFailureV1.incompatibleVersion }
        try value.validate(policy: policy); return value
    }

    static func decodeReview(from data: Data, manifest: PrivacyTransformManifestV1,
                             policy: PrivacyTransformPolicyV1) throws -> PrivacyReviewReceiptV1 {
        let value = try decode(PrivacyReviewReceiptV1.self, from: data)
        guard value.schemaVersion == PrivacyReviewReceiptV1.schemaVersion else { throw PrivacyTransformFailureV1.incompatibleVersion }
        try value.validate(manifest: manifest, policy: policy); return value
    }
}

// MARK: - C24 accessible-document privacy projection

/// C24 consumes a validated audience-safe derivative of the report snapshot.
/// This is a consumer boundary over the canonical accessible-document types,
/// not another privacy-transform writer or a second semantic-tree owner.
enum AccessibleDocumentPrivacyTransformBoundaryV1 {
    static let requiresAudienceSafeDerivative = true
    static let semanticTreePersistence = "DERIVED_ONLY"
    static let excludesOriginalEvidence = true
    static let excludesPrivateEvidence = true
    static let excludesAssessorIdentity = true
    static let excludesPrivateLocators = true
    static let excludesUnsupportedConformanceClaims = true

    static func validateAudienceSafeProjection(
        _ tree: AccessibleDocumentSemanticTreeV1,
        assessment: AccessibleDocumentAssessmentReceiptV1? = nil
    ) throws {
        try AccessibleDocumentProvenanceBoundaryV1.validateTree(tree)
        try AccessibleDocumentLocatorBoundaryV1.validateAudienceSafeTree(tree)
        guard !tree.pdfUAClaimed,
              !tree.wcagClaimed,
              !tree.legalCertificationClaimed,
              !tree.s10BrandReconciled else {
            throw AccessibleDocumentFailureV1.unsupportedConformanceClaim
        }
        if let assessment {
            try AccessibleDocumentContentReferenceBoundaryV1
                .validateAssessment(assessment, for: tree)
        }
    }
}
