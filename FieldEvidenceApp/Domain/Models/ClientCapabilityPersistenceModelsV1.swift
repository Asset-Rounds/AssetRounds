import Foundation
import SwiftData

enum ClientCapabilityPersistenceFailureV1:Error{case corruptRow,linkedValidationRequired}

@Model final class ClientCapabilityProfileRow{
    @Attribute(.unique)var profileID:UUID;var workspaceID:UUID;var revision:UInt64;var mutationID:UUID;var profileSHA256:String;var canonicalData:Data
    init(_ value:ClientCapabilityProfileV1)throws{try value.validate();profileID=value.profileID;workspaceID=value.workspaceID.rawValue;revision=value.revision;mutationID=value.mutationID.rawValue;profileSHA256=value.profileSHA256;canonicalData=try ClientCapabilityCanonicalCodecV1.encode(value)}
    func value()throws->ClientCapabilityProfileV1{let v=try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self,from:canonicalData);try v.validate();guard v.schemaVersion==ClientCapabilityProfileV1.schemaVersion,v.profileID==profileID,v.workspaceID.rawValue==workspaceID,v.revision==revision,v.mutationID.rawValue==mutationID,v.profileSHA256==profileSHA256 else{throw ClientCapabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class PackageLifecyclePolicyRow{
    @Attribute(.unique)var policyID:UUID;var workspaceID:UUID;var packageReleaseID:String;var revision:UInt64;var mutationID:UUID;var policySHA256:String;var canonicalData:Data
    init(_ value:PackageLifecyclePolicyV1)throws{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    init(_ value:PackageLifecyclePolicyV1,release:InspectionPackageReleaseV1)throws{try value.validate(release:release);policyID=value.policyID;workspaceID=value.workspaceID.rawValue;packageReleaseID=value.packageReleaseID;revision=value.revision;mutationID=value.mutationID.rawValue;policySHA256=value.policySHA256;canonicalData=try ClientCapabilityCanonicalCodecV1.encode(value)}
    func value()throws->PackageLifecyclePolicyV1{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    func value(release:InspectionPackageReleaseV1)throws->PackageLifecyclePolicyV1{let v=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self,from:canonicalData);try v.validate(release:release);guard v.schemaVersion==PackageLifecyclePolicyV1.schemaVersion,v.policyID==policyID,v.workspaceID.rawValue==workspaceID,v.packageReleaseID==packageReleaseID,v.revision==revision,v.mutationID.rawValue==mutationID,v.policySHA256==policySHA256 else{throw ClientCapabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class PackageLifecycleDispositionRow{
    @Attribute(.unique)var dispositionID:UUID;var workspaceID:UUID;var packageReleaseID:String;var revision:UInt64;var mutationID:UUID;var dispositionSHA256:String;var canonicalData:Data
    init(_ value:PackageLifecycleDispositionV1)throws{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    init(_ value:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)throws{try value.validate(release:release);dispositionID=value.dispositionID;workspaceID=value.workspaceID.rawValue;packageReleaseID=value.packageReleaseID;revision=value.revision;mutationID=value.mutationID.rawValue;dispositionSHA256=value.dispositionSHA256;canonicalData=try ClientCapabilityCanonicalCodecV1.encode(value)}
    func value()throws->PackageLifecycleDispositionV1{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    func value(release:InspectionPackageReleaseV1)throws->PackageLifecycleDispositionV1{let v=try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self,from:canonicalData);try v.validate(release:release);guard v.schemaVersion==PackageLifecycleDispositionV1.schemaVersion,v.dispositionID==dispositionID,v.workspaceID.rawValue==workspaceID,v.packageReleaseID==packageReleaseID,v.revision==revision,v.mutationID.rawValue==mutationID,v.dispositionSHA256==dispositionSHA256 else{throw ClientCapabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ClientCapabilityAdmissionDecisionRow{
    @Attribute(.unique)var decisionID:UUID;var workspaceID:UUID;var profileID:UUID;var policyID:UUID;var dispositionID:UUID;var packageReleaseID:String;var revision:UInt64;var mutationID:UUID;var decisionSHA256:String;var canonicalData:Data
    init(_ value:ClientCapabilityAdmissionDecisionV1)throws{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    init(_ value:ClientCapabilityAdmissionDecisionV1,profile:ClientCapabilityProfileV1,policy:PackageLifecyclePolicyV1,disposition:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)throws{try value.validate(profile:profile,policy:policy,disposition:disposition,release:release);decisionID=value.decisionID;workspaceID=value.workspaceID.rawValue;profileID=value.profileID;policyID=value.policyID;dispositionID=value.dispositionID;packageReleaseID=value.packageReleaseID;revision=value.revision;mutationID=value.mutationID.rawValue;decisionSHA256=value.decisionSHA256;canonicalData=try ClientCapabilityCanonicalCodecV1.encode(value)}
    func value()throws->ClientCapabilityAdmissionDecisionV1{throw ClientCapabilityPersistenceFailureV1.linkedValidationRequired}
    func value(profile:ClientCapabilityProfileV1,policy:PackageLifecyclePolicyV1,disposition:PackageLifecycleDispositionV1,release:InspectionPackageReleaseV1)throws->ClientCapabilityAdmissionDecisionV1{let v=try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self,from:canonicalData);try v.validate(profile:profile,policy:policy,disposition:disposition,release:release);guard v.schemaVersion==ClientCapabilityAdmissionDecisionV1.schemaVersion,v.decisionID==decisionID,v.workspaceID.rawValue==workspaceID,v.profileID==profileID,v.policyID==policyID,v.dispositionID==dispositionID,v.packageReleaseID==packageReleaseID,v.revision==revision,v.mutationID.rawValue==mutationID,v.decisionSHA256==decisionSHA256 else{throw ClientCapabilityPersistenceFailureV1.corruptRow};return v}
}
