import Foundation
import SwiftData

private protocol AuthorityCriterionPersistableV1: Codable {
    func validate() throws
}

extension AuthoritySourceReleaseV1: AuthorityCriterionPersistableV1 {}
extension RequirementBasisBindingV1: AuthorityCriterionPersistableV1 {}
extension ApplicabilityContextSnapshotV1: AuthorityCriterionPersistableV1 {}
extension AssessmentScopeSnapshotV1: AuthorityCriterionPersistableV1 {}
extension SeverityScaleReleaseV1: AuthorityCriterionPersistableV1 {}
extension FindingClassificationBindingV1: AuthorityCriterionPersistableV1 {}
extension MeasurementProtocolReleaseV1: AuthorityCriterionPersistableV1 {}
extension DerivedFactEvaluatorDescriptorV1: AuthorityCriterionPersistableV1 {}
extension DerivedFactProvenanceV1: AuthorityCriterionPersistableV1 {}

enum AuthorityCriterionCanonicalCodecV1 {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try WorkspaceMutationCanonicalV1.data(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
}

private func authorityData<T: Encodable>(_ value: T) throws -> Data {
    try AuthorityCriterionCanonicalCodecV1.encode(value)
}
private func authorityValue<T: AuthorityCriterionPersistableV1>(_ type: T.Type, data: Data) throws -> T {
    let value = try AuthorityCriterionCanonicalCodecV1.decode(type, from: data)
    try value.validate()
    guard try authorityData(value) == data else { throw AuthorityCriterionFailureV1.digestMismatch }
    return value
}

private func authorityCanonicalized<T: AuthorityCriterionPersistableV1>(_ value: T) throws -> (value: T, data: Data) {
    let data = try authorityData(value)
    return (try authorityValue(T.self, data: data), data)
}

private func authorityStoredRevision(_ value: UInt64) throws -> Int64 {
    guard value > 0, value <= UInt64(Int64.max) else { throw AuthorityCriterionFailureV1.invalidValue }
    return Int64(value)
}

private func authorityDomainRevision(_ value: Int64) throws -> UInt64 {
    guard value > 0 else { throw AuthorityCriterionFailureV1.digestMismatch }
    return UInt64(value)
}

@Model final class AuthoritySourceReleaseRow {
    @Attribute(.unique) private(set) var releaseID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: AuthoritySourceReleaseV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; releaseID=value.releaseID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.releaseSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> AuthoritySourceReleaseV1 { let v=try authorityValue(AuthoritySourceReleaseV1.self,data:canonicalData); guard v.releaseID==releaseID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.releaseSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class RequirementBasisBindingRow {
    @Attribute(.unique) private(set) var bindingID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: RequirementBasisBindingV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; bindingID=value.bindingID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.bindingSHA256; recordedAt=value.selectedAt; canonicalData=stored.data }
    func value() throws -> RequirementBasisBindingV1 { let v=try authorityValue(RequirementBasisBindingV1.self,data:canonicalData); guard v.bindingID==bindingID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.bindingSHA256==canonicalSHA256,v.selectedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class ApplicabilityContextSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: ApplicabilityContextSnapshotV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; snapshotID=value.snapshotID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.snapshotSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> ApplicabilityContextSnapshotV1 { let v=try authorityValue(ApplicabilityContextSnapshotV1.self,data:canonicalData); guard v.snapshotID==snapshotID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.snapshotSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class AssessmentScopeSnapshotRow {
    @Attribute(.unique) private(set) var snapshotID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: AssessmentScopeSnapshotV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; snapshotID=value.snapshotID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.snapshotSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> AssessmentScopeSnapshotV1 { let v=try authorityValue(AssessmentScopeSnapshotV1.self,data:canonicalData); guard v.snapshotID==snapshotID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.snapshotSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class SeverityScaleReleaseRow {
    @Attribute(.unique) private(set) var releaseID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: SeverityScaleReleaseV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; releaseID=value.releaseID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.releaseSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> SeverityScaleReleaseV1 { let v=try authorityValue(SeverityScaleReleaseV1.self,data:canonicalData); guard v.releaseID==releaseID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.releaseSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class FindingClassificationBindingRow {
    @Attribute(.unique) private(set) var bindingID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: FindingClassificationBindingV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; bindingID=value.bindingID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.bindingSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> FindingClassificationBindingV1 { let v=try authorityValue(FindingClassificationBindingV1.self,data:canonicalData); guard v.bindingID==bindingID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.bindingSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class MeasurementProtocolReleaseRow {
    @Attribute(.unique) private(set) var releaseID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: MeasurementProtocolReleaseV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; releaseID=value.releaseID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.releaseSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> MeasurementProtocolReleaseV1 { let v=try authorityValue(MeasurementProtocolReleaseV1.self,data:canonicalData); guard v.releaseID==releaseID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.releaseSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class DerivedFactEvaluatorDescriptorRow {
    @Attribute(.unique) private(set) var descriptorID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: DerivedFactEvaluatorDescriptorV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; descriptorID=value.descriptorID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.descriptorSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> DerivedFactEvaluatorDescriptorV1 { let v=try authorityValue(DerivedFactEvaluatorDescriptorV1.self,data:canonicalData); guard v.descriptorID==descriptorID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.descriptorSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
@Model final class DerivedFactProvenanceRow {
    @Attribute(.unique) private(set) var provenanceID: UUID; private(set) var workspaceID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID; private(set) var canonicalSHA256: String; private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: DerivedFactProvenanceV1) throws { try value.validate(); let stored=try authorityCanonicalized(value); let value=stored.value; provenanceID=value.provenanceID; workspaceID=value.workspaceID.rawValue; revision=try authorityStoredRevision(value.revision); mutationID=value.mutationID.rawValue; canonicalSHA256=value.provenanceSHA256; recordedAt=value.recordedAt; canonicalData=stored.data }
    func value() throws -> DerivedFactProvenanceV1 { let v=try authorityValue(DerivedFactProvenanceV1.self,data:canonicalData); guard v.provenanceID==provenanceID,v.workspaceID.rawValue==workspaceID,v.revision==(try authorityDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.provenanceSHA256==canonicalSHA256,v.recordedAt==recordedAt else { throw AuthorityCriterionFailureV1.digestMismatch }; return v }
}
