import Foundation
import SwiftData

private func evidenceAssuranceStoredRevision(_ value: UInt64) throws -> Int64 {
    guard value > 0, value <= UInt64(Int64.max) else { throw EvidenceAssuranceFailureV1.invalidValue }
    return Int64(value)
}

private func evidenceAssuranceDomainRevision(_ value: Int64) throws -> UInt64 {
    guard value > 0 else { throw EvidenceAssuranceFailureV1.digestMismatch }
    return UInt64(value)
}

@Model final class EvidenceVisibilityRow {
    @Attribute(.unique) private(set) var visibilityID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: Int64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String
    private(set) var effectiveAt: Date; private(set) var canonicalData: Data
    init(_ value: EvidenceVisibilityV1) throws { try value.validate(); let data=try EvidenceAssuranceCanonicalCodecV1.encode(value); let v=try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self,from:data); visibilityID=v.visibilityID;workspaceID=v.workspaceID.rawValue;revision=try evidenceAssuranceStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.visibilitySHA256;effectiveAt=v.effectiveAt;canonicalData=data }
    func value() throws -> EvidenceVisibilityV1 { let v=try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self,from:canonicalData);guard v.visibilityID==visibilityID,v.workspaceID.rawValue==workspaceID,v.revision==(try evidenceAssuranceDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.visibilitySHA256==canonicalSHA256,v.effectiveAt==effectiveAt else{throw EvidenceAssuranceFailureV1.digestMismatch};return v }
}

@Model final class ClaimEvidenceLinkRow {
    @Attribute(.unique) private(set) var linkID: UUID
    private(set) var workspaceID: UUID; private(set) var visibilityID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID
    private(set) var canonicalSHA256: String; private(set) var canonicalData: Data
    init(_ value: ClaimEvidenceLinkV1) throws { try value.validate();let data=try EvidenceAssuranceCanonicalCodecV1.encode(value);let v=try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self,from:data);linkID=v.linkID;workspaceID=v.workspaceID.rawValue;visibilityID=v.visibilityID;revision=try evidenceAssuranceStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.linkSHA256;canonicalData=data }
    func value() throws -> ClaimEvidenceLinkV1 { let v=try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self,from:canonicalData);guard v.linkID==linkID,v.workspaceID.rawValue==workspaceID,v.visibilityID==visibilityID,v.revision==(try evidenceAssuranceDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.linkSHA256==canonicalSHA256 else{throw EvidenceAssuranceFailureV1.digestMismatch};return v }
}

@Model final class AssuranceManifestRow {
    @Attribute(.unique) private(set) var manifestID: UUID
    private(set) var workspaceID: UUID; private(set) var revision: Int64
    private(set) var mutationID: UUID; private(set) var canonicalSHA256: String
    private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: AssuranceManifestV1) throws { try value.validate();let data=try EvidenceAssuranceCanonicalCodecV1.encode(value);let v=try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self,from:data);manifestID=v.manifestID;workspaceID=v.workspaceID.rawValue;revision=try evidenceAssuranceStoredRevision(v.revision);mutationID=v.mutationID.rawValue;canonicalSHA256=v.manifestSHA256;recordedAt=v.recordedAt;canonicalData=data }
    func value() throws -> AssuranceManifestV1 { let v=try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self,from:canonicalData);guard v.manifestID==manifestID,v.workspaceID.rawValue==workspaceID,v.revision==(try evidenceAssuranceDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.manifestSHA256==canonicalSHA256,v.recordedAt==recordedAt else{throw EvidenceAssuranceFailureV1.digestMismatch};return v }
}

@Model final class AttestationRow {
    @Attribute(.unique) private(set) var attestationID: UUID
    private(set) var workspaceID: UUID; private(set) var manifestID: UUID
    private(set) var revision: Int64; private(set) var mutationID: UUID
    private(set) var actionRawValue: String; private(set) var canonicalSHA256: String
    private(set) var recordedAt: Date; private(set) var canonicalData: Data
    init(_ value: AttestationV1) throws { try value.validate();let data=try EvidenceAssuranceCanonicalCodecV1.encode(value);let v=try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self,from:data);attestationID=v.attestationID;workspaceID=v.workspaceID.rawValue;manifestID=v.manifestID;revision=try evidenceAssuranceStoredRevision(v.revision);mutationID=v.mutationID.rawValue;actionRawValue=v.action.rawValue;canonicalSHA256=v.attestationSHA256;recordedAt=v.recordedAt;canonicalData=data }
    func value() throws -> AttestationV1 { let v=try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self,from:canonicalData);guard v.attestationID==attestationID,v.workspaceID.rawValue==workspaceID,v.manifestID==manifestID,v.revision==(try evidenceAssuranceDomainRevision(revision)),v.mutationID.rawValue==mutationID,v.action.rawValue==actionRawValue,v.attestationSHA256==canonicalSHA256,v.recordedAt==recordedAt else{throw EvidenceAssuranceFailureV1.digestMismatch};return v }
}
