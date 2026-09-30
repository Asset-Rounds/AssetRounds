from pathlib import Path
import hashlib, json

q=Path('.codex-temp/cold-ledger-continuation-successor-v1')
p=q/'candidate/FieldEvidenceApp/Infrastructure/Storage/OwnedStorageLedgerV1.swift'
s=p.read_text(); before=hashlib.sha256(p.read_bytes()).hexdigest()
assert before=='97996c35cf430636aa7c7fd37f5234cb8d5f60a1fa476daea1245c179b0a377d',before

def replace(old,new):
    global s
    assert s.count(old)==1,(s.count(old),old[:140])
    s=s.replace(old,new)

replace('struct OriginalEraseC16BornSourceObservationV1: Equatable {', '''/// The actual retained publisher supplies this immutable request before its
/// first create or replay-settlement effect. It contains no future file fact.
@MainActor final class OriginalEraseC16ProducerRequestV4 {
    enum PublicationMode: String { case linkExclusiveFinal, renameExclusiveFinal }
    let slot: OriginalEraseC16BornProducerSlotV1
    let temporaryPath: String
    let bytes: Data
    let sha256: String
    let planSHA256: String
    let stepSHA256: String
    let ordinal: Int
    let publicationMode: PublicationMode
    fileprivate let sessionIdentity: ObjectIdentifier
    fileprivate init(slot: OriginalEraseC16BornProducerSlotV1,
        temporaryPath: String, bytes: Data, sha256: String,
        planSHA256: String, stepSHA256: String, ordinal: Int,
        publicationMode: PublicationMode, sessionIdentity: ObjectIdentifier) {
        self.slot = slot; self.temporaryPath = temporaryPath
        self.bytes = bytes; self.sha256 = sha256
        self.planSHA256 = planSHA256; self.stepSHA256 = stepSHA256
        self.ordinal = ordinal; self.publicationMode = publicationMode
        self.sessionIdentity = sessionIdentity
    }
}

struct OriginalEraseC16BornSourceObservationV1: Equatable {''')
replace('    enum Purpose: String { case inspection, bornSource }',
        '    enum Purpose: String { case inspection, bornSource, producerRequest }')
replace('''    let bornSource: OriginalEraseC16BornSourceObservationV1?
    fileprivate init(planSHA256: String, stepSHA256: String, ordinal: Int,
        projection: OriginalEraseC16ExpectedTreeV1,
        bornSource: OriginalEraseC16BornSourceObservationV1?) {''', '''    let bornSource: OriginalEraseC16BornSourceObservationV1?
    let producerRequest: OriginalEraseC16ProducerRequestV4?
    fileprivate init(planSHA256: String, stepSHA256: String, ordinal: Int,
        projection: OriginalEraseC16ExpectedTreeV1,
        bornSource: OriginalEraseC16BornSourceObservationV1?,
        producerRequest: OriginalEraseC16ProducerRequestV4? = nil) {''')
replace('''        purpose = bornSource == nil ? .inspection : .bornSource
        self.projection = projection; self.bornSource = bornSource''', '''        purpose = producerRequest != nil ? .producerRequest
            : (bornSource == nil ? .inspection : .bornSource)
        self.projection = projection; self.bornSource = bornSource
        self.producerRequest = producerRequest''')

replace('''    private enum C16SemanticStepV1 {''', '''    private struct OriginalEraseC16PendingPublicationV1 {
        let sessionIdentity: ObjectIdentifier
        let finalPath: String
        let temporaryPath: String
        let bytes: Data
        let atomicExclusiveRename: Bool
    }

    private enum C16SemanticStepV1 {''')
replace('''        func authorizeCaptureAdvance() throws {''', '''        var nextProducerRequest: OriginalEraseC16PendingPublicationV1? {
            guard case let .publication(owner)? = pending.last else { return nil }
            return owner.pendingProducerRequest
        }
        func authorizeProducerRequest(_ pendingRequest: OriginalEraseC16PendingPublicationV1) throws {
            try store.requireScratchDescriptorAccess()
            guard borrowed, case let .publication(owner)? = pending.last,
                  nextCapture == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            try owner.authorizeProducerRequest(pendingRequest)
        }
        func authorizeCaptureAdvance() throws {''')
replace('''                try requireOriginalEraseC16Cut()
                if let capture = session.nextCapture {''', '''                try requireOriginalEraseC16Cut()
                if let request = session.nextProducerRequest {
                    try requireOriginalEraseC16ProducerRequest(request)
                    try session.authorizeProducerRequest(request)
                }
                if let capture = session.nextCapture {''')

replace('''    /// The callback must prove the held EX/G, the matching sidecar preparing''', '''    /// Receipt issuance is the Router/Store's real durable pending-request
    /// CAS/readback. Ledger authorizes only the exact retained publisher after
    /// the actual tuple and whole pre-publication image have been rechecked.
    @MainActor private func requireOriginalEraseC16ProducerRequest(
        _ pending: OriginalEraseC16PendingPublicationV1
    ) throws {
        try requireScratchDescriptorAccess()
        guard let permit = originalEraseColdPermit, let check = originalEraseC16CutCheck,
              let plan = originalEraseC16ReferencePlan,
              let ordinal = originalEraseC16CurrentOrdinal,
              ordinal >= 0, ordinal < plan.steps.count,
              let operationID = originalEraseOperationID,
              pending.finalPath.hasPrefix("ProtectedIngressReceiptsV1/") else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        let name = String(pending.finalPath.dropFirst("ProtectedIngressReceiptsV1/".count))
        guard OperationalDiagnosticsBoundsV1.validRelativeName(name),
              pending.finalPath == "ProtectedIngressReceiptsV1/" + name,
              pending.temporaryPath == "ProtectedIngressReceiptsV1/"
                + (try Self.originalErasePublicationTemporaryName(operationID: operationID,
                    finalName: name, leaseName: nil)) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        var roles = try originalEraseC16CanonicalRoles(plan: plan, through: ordinal)
        if let marker = try originalEraseC16MaterializedControlRole(plan: plan, ordinal: ordinal) {
            roles[Self.controlEraseName] = marker
        }
        guard let role = roles[name], role.producerOrdinal == ordinal,
              role.role != "finalizedHygienePrepare", role.bytes == pending.bytes,
              pending.bytes.count <= Self.originalEraseC16SourceMaximum(name: name),
              pending.atomicExclusiveRename == (role.role == "scratchControlErase") else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        let slot = OriginalEraseC16BornProducerSlotV1(producerOrdinal: ordinal,
            role: role.role, path: pending.finalPath)
        let planSHA = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan))
        let stepSHA = try CompatibilityCanonicalV1.sha256(CompatibilityCanonicalV1.encode(plan.steps[ordinal]))
        let payloadSHA = try CompatibilityCanonicalV1.sha256(pending.bytes)
        let request = OriginalEraseC16ProducerRequestV4(slot: slot,
            temporaryPath: pending.temporaryPath, bytes: pending.bytes, sha256: payloadSHA,
            planSHA256: planSHA, stepSHA256: stepSHA, ordinal: ordinal,
            publicationMode: pending.atomicExclusiveRename ? .renameExclusiveFinal : .linkExclusiveFinal,
            sessionIdentity: pending.sessionIdentity)
        let projection = try originalEraseC16ExpectedTree(plan: plan, currentOrdinal: ordinal,
            controlMarkerState: originalEraseC16CurrentControlMarkerState,
            ingressMarkerState: originalEraseC16CurrentIngressMarkerState, capturedBirths: [])
        let observation = OriginalEraseC16BoundaryObservationV1(planSHA256: planSHA,
            stepSHA256: stepSHA, ordinal: ordinal, projection: projection,
            bornSource: nil, producerRequest: request)
        let receipt = try check(observation)
        try receipt.requireBound(to: observation)
        guard receipt.recordStage == .preparing || receipt.recordStage == .preparingCaptured,
              receipt.producerRequestCommitmentSHA256 != nil,
              let retained = try permit.canonicalProducerRequest(slot: slot),
              retained.temporaryPath == pending.temporaryPath,
              retained.bytes == pending.bytes, retained.sha256 == payloadSHA else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        try permit.requireObservationBinding()
        _ = try originalEraseC16CurrentObservationScope(plan: plan, currentOrdinal: ordinal,
            controlMarkerState: originalEraseC16CurrentControlMarkerState,
            ingressMarkerState: originalEraseC16CurrentIngressMarkerState)
        try permit.requireHeld()
    }

    /// The callback must prove the held EX/G, the matching sidecar preparing''')

replace('''        private var capturedTemporaryBytes: Data?

        init(store: ScratchDataLeaseStoreV1, data: Data,''', '''        private var capturedTemporaryBytes: Data?
        private var producerRequestAuthorized = false

        var pendingProducerRequest: OriginalEraseC16PendingPublicationV1? {
            guard borrowed, !producerRequestAuthorized else { return nil }
            switch stage {
            case .create, .clearExisting:
                return .init(sessionIdentity: ObjectIdentifier(self),
                    finalPath: "ProtectedIngressReceiptsV1/" + finalName,
                    temporaryPath: "ProtectedIngressReceiptsV1/" + temporaryName,
                    bytes: data, atomicExclusiveRename: atomicExclusiveRename)
            default: return nil
            }
        }
        func authorizeProducerRequest(_ expected: OriginalEraseC16PendingPublicationV1) throws {
            try store.requireScratchDescriptorAccess()
            guard let pending = pendingProducerRequest,
                  pending.sessionIdentity == expected.sessionIdentity,
                  pending.sessionIdentity == ObjectIdentifier(self),
                  pending.finalPath == expected.finalPath,
                  pending.temporaryPath == expected.temporaryPath,
                  pending.bytes == expected.bytes,
                  pending.atomicExclusiveRename == expected.atomicExclusiveRename else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            producerRequestAuthorized = true
        }

        init(store: ScratchDataLeaseStoreV1, data: Data,''')
start=s.index('    private final class PublicationSessionV1 {')
index=s.index('''        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            switch stage {''',start)
s=s[:index]+s[index:].replace('''        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            switch stage {''','''        func advance() throws -> Bool {
            try store.requireScratchDescriptorAccess()
            guard pendingProducerRequest == nil else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            switch stage {''',1)

replace('''    private func originalEraseC16FixedFreshEraseMarker(
''', '''    /// Only a genuine Store-authenticated fixed-slot pending request can
    /// retain dynamic producer bytes across an interrupted partial write.
    /// Nil proves pending-table absence and grants no publication effect.
    private func originalEraseC16PendingProducerBytes(
        slot: OriginalEraseC16BornProducerSlotV1
    ) throws -> Data? {
        try requireScratchDescriptorAccess()
        guard originalEraseBorrowedLifetime == .active, Thread.isMainThread,
              let operationID = originalEraseOperationID else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        return try MainActor.assumeIsolated {
            guard let permit = originalEraseColdPermit else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            do {
                try permit.requireObservationBinding()
                guard let value = try permit.canonicalProducerRequest(slot: slot) else { return nil }
                let prefix = "ProtectedIngressReceiptsV1/"
                let name = String(slot.path.dropFirst(prefix.count))
                guard slot.path == prefix + name,
                      OperationalDiagnosticsBoundsV1.validRelativeName(name),
                      value.temporaryPath == prefix
                        + (try Self.originalErasePublicationTemporaryName(operationID: operationID,
                            finalName: name, leaseName: nil)),
                      value.bytes.count <= Self.originalEraseC16SourceMaximum(name: name),
                      try CompatibilityCanonicalV1.sha256(value.bytes) == value.sha256 else {
                    throw ScratchDataLeaseStoreFailureV1.leaseCollision
                }
                try permit.requireObservationBinding()
                return value.bytes
            } catch {
                originalEraseBorrowedLifetime = .uncertain
                permit.poisonOnUncertainEffect()
                throw error
            }
        }
    }

    private func originalEraseC16FixedFreshEraseMarker(
''')
replace('''        let published = try plan.freshPublishedTargets.map { target -> C16IngressPublicationV1 in''', '''        guard let producerOrdinal = plan.steps.firstIndex(of: .eraseIngress) else {
            throw ScratchDataLeaseStoreFailureV1.leaseCollision
        }
        if let bytes = try originalEraseC16PendingProducerBytes(slot: .init(
            producerOrdinal: producerOrdinal, role: "freshIngressErasePrepare",
            path: "ProtectedIngressReceiptsV1/" + name)) {
            let marker = try CompatibilityCanonicalV1.decode(C16IngressEraseV1.self, from: bytes)
            try marker.validate()
            guard marker.operationID == operationID,
                  marker.rootDevice == authority.rootDevice, marker.rootInode == authority.rootInode,
                  marker.targets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.intent.intentID,
                    directory: .init($0)) }) == plan.freshPublishedTargets,
                  marker.unpublishedTargets.map({ OriginalEraseC16PlannedTargetV1(intentID: $0.preparation.intent.intentID,
                    directory: $0.directory.map(OriginalEraseC16TargetFactV1.init)) }) == plan.freshUnpublishedTargets,
                  try CompatibilityCanonicalV1.encode(marker) == bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return marker
        }
        let published = try plan.freshPublishedTargets.map { target -> C16IngressPublicationV1 in''')
replace('''        let names = try originalEraseC16FinalControlRoleNames(plan: plan)
        let files = try names.map { name -> C16IngressHygieneFileIdentityV1 in''', '''        let names = try originalEraseC16FinalControlRoleNames(plan: plan)
        if let producerOrdinal = plan.steps.firstIndex(of: .eraseFinalControl),
           let bytes = try originalEraseC16PendingProducerBytes(slot: .init(
            producerOrdinal: producerOrdinal, role: "scratchControlErase",
            path: "ProtectedIngressReceiptsV1/" + Self.controlEraseName)) {
            let marker = try CompatibilityCanonicalV1.decode(C16ScratchControlEraseV1.self, from: bytes)
            try marker.validate()
            guard marker.rootDevice == authority.rootDevice, marker.rootInode == authority.rootInode,
                  marker.controlDevice == control.rootDevice, marker.controlInode == control.rootInode,
                  marker.files.map(\\.name) == names,
                  try CompatibilityCanonicalV1.encode(marker) == bytes else {
                throw ScratchDataLeaseStoreFailureV1.leaseCollision
            }
            return .init(role: "scratchControlErase", bytes: bytes, producerOrdinal: producerOrdinal)
        }
        let files = try names.map { name -> C16IngressHygieneFileIdentityV1 in''')

p.write_text(s)
record={'model':'gpt-6.1-sol','reasoningEffort':'xhigh','beforeSHA256':before,
    'afterSHA256':hashlib.sha256(p.read_bytes()).hexdigest(),
    'contract':'central pending-producer-interface-v10 Ledgerbe527834/Router9ecad486/ORDER68ae75ca',
    'sourceDirection':['Actual retained session read-only initial cut before request','Private exact slot/temp/payload/mode request before create or replay temp settlement','Actual receipt/readback consumed and pending getter compared before session authorization','Dynamic fresh E and scratch marker replay uses authentic pending bytes','No finalized H partial request, future fullFact, new nonce, generic replacement or version ordinal'],
    'limitations':['Actual Store V4/Router handler/readback and record issuer incomplete','Shared engine actual execution/typecheck/runtime due','Complete generic directory source and coherent current capacity remain due']}
(q/'PENDING_PRODUCER_GATE_V24.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record,indent=2))
