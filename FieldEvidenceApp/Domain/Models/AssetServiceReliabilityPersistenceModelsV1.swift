import Foundation
import SwiftData

enum AssetServiceReliabilityPersistenceFailureV1: Error, Equatable, Sendable { case corruptRow }

private enum AssetServiceReliabilityRowCodecV1 {
    static func data<T: Encodable & ServiceReliabilityCanonicalValidatingV1>(_ value: T) throws -> Data {
        try ServiceReliabilityCanonicalCodecV1.encode(value)
    }
    static func value<T: Codable & Equatable & ServiceReliabilityCanonicalValidatingV1>(
        _ type: T.Type, data: Data
    ) throws -> T {
        let value = try ServiceReliabilityCanonicalCodecV1.decode(type, from: data)
        guard try ServiceReliabilityCanonicalCodecV1.encode(value) == data else {
            throw AssetServiceReliabilityPersistenceFailureV1.corruptRow
        }
        return value
    }
    static func identity(_ workspaceID: UUID, _ eventID: UUID) -> String {
        "\(workspaceID.uuidString.lowercased())|\(eventID.uuidString.lowercased())"
    }
}

@Model final class AssetServiceIncidentRow {
    @Attribute(.unique) private(set) var stableIdentity:String;private(set)var eventID,workspaceID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:AssetServiceIncidentV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->AssetServiceIncidentV1{let v=try AssetServiceReliabilityRowCodecV1.value(AssetServiceIncidentV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ServiceImpactSegmentRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,segmentID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:ServiceImpactSegmentV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;segmentID=v.segmentID;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->ServiceImpactSegmentV1{let v=try AssetServiceReliabilityRowCodecV1.value(ServiceImpactSegmentV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,segmentID==v.segmentID,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ServiceCauseAssertionRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,assertionID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:ServiceCauseAssertionV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;assertionID=v.assertionID;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->ServiceCauseAssertionV1{let v=try AssetServiceReliabilityRowCodecV1.value(ServiceCauseAssertionV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,assertionID==v.assertionID,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ServiceRemedyAssertionRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,assertionID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:ServiceRemedyAssertionV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;assertionID=v.assertionID;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->ServiceRemedyAssertionV1{let v=try AssetServiceReliabilityRowCodecV1.value(ServiceRemedyAssertionV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,assertionID==v.assertionID,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ServiceRepairIntervalRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,repairID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:ServiceRepairIntervalV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;repairID=v.repairID;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->ServiceRepairIntervalV1{let v=try AssetServiceReliabilityRowCodecV1.value(ServiceRepairIntervalV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,repairID==v.repairID,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class ServiceRestorationAssertionRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,assertionID,incidentID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:ServiceRestorationAssertionV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;assertionID=v.assertionID;incidentID=v.incidentID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->ServiceRestorationAssertionV1{let v=try AssetServiceReliabilityRowCodecV1.value(ServiceRestorationAssertionV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,assertionID==v.assertionID,incidentID==v.incidentID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

@Model final class QualifiedServiceExposureRow {
    @Attribute(.unique) private(set)var stableIdentity:String;private(set)var eventID,workspaceID,exposureID,mutationID:UUID
    private(set)var revision:UInt64;private(set)var predecessorEventID:UUID?;private(set)var eventSHA256:String;private(set)var canonicalData:Data
    init(_ v:QualifiedServiceExposureV1)throws{try v.validate();stableIdentity=AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID);eventID=v.eventID;workspaceID=v.workspaceID.rawValue;exposureID=v.exposureID;mutationID=v.mutationID.rawValue;revision=v.revision;predecessorEventID=v.predecessor?.eventID;eventSHA256=v.eventSHA256;canonicalData=try AssetServiceReliabilityRowCodecV1.data(v)}
    func value()throws->QualifiedServiceExposureV1{let v=try AssetServiceReliabilityRowCodecV1.value(QualifiedServiceExposureV1.self,data:canonicalData);try v.validate();guard stableIdentity==AssetServiceReliabilityRowCodecV1.identity(v.workspaceID.rawValue,v.eventID),eventID==v.eventID,workspaceID==v.workspaceID.rawValue,exposureID==v.exposureID,mutationID==v.mutationID.rawValue,revision==v.revision,predecessorEventID==v.predecessor?.eventID,eventSHA256==v.eventSHA256 else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow};return v}
}

enum AssetServiceReliabilityPersistenceEnrollmentV1 {
    static let predecessorPersistentSchemaVersion=39,targetPersistentSchemaVersion=40,recordsSchemaVersion=39
    static let durableModels:[Any.Type]=[AssetServiceIncidentRow.self,ServiceImpactSegmentRow.self,ServiceCauseAssertionRow.self,ServiceRemedyAssertionRow.self,ServiceRepairIntervalRow.self,ServiceRestorationAssertionRow.self,QualifiedServiceExposureRow.self]
    static let durableFamilies=["AssetServiceIncidentV1","ServiceImpactSegmentV1","ServiceCauseAssertionV1","ServiceRemedyAssertionV1","ServiceRepairIntervalV1","ServiceRestorationAssertionV1","QualifiedServiceExposureV1"]
    static let derivedProjectionIsPersistent=false
    static func validate()throws{guard targetPersistentSchemaVersion==predecessorPersistentSchemaVersion+1,durableModels.count==7,durableFamilies.count==7,Set(durableFamilies).count==7,!derivedProjectionIsPersistent else{throw AssetServiceReliabilityPersistenceFailureV1.corruptRow}}
}
