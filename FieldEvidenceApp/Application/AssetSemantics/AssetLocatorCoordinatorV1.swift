import Foundation

enum LocatorDecodedInputV1: Equatable, Sendable {
    case localSigned(SignedLocalAssetLocatorPayloadV1)
    case externalKey(ExternalKeyV1)
    case damagedOrIncomplete
}

struct LocatorResolutionInputV1: Equatable, Sendable {
    let source: LocatorInputSourceV1
    let inputSHA256: String
    let decoded: LocatorDecodedInputV1

    init(source: LocatorInputSourceV1, rawBytes: Data, decoded: LocatorDecodedInputV1) throws {
        guard !rawBytes.isEmpty, rawBytes.count <= AssetLocatorLimitsV1.maximumInputBytes else {
            throw AssetLocatorFailureV1.limitExceeded
        }
        self.source=source;inputSHA256=KernelCanonicalHashV1.sha256(rawBytes);self.decoded=decoded
    }
    init(source:LocatorInputSourceV1,inputSHA256:String,decoded:LocatorDecodedInputV1)throws{guard KernelCanonicalHashV1.validSHA256(inputSHA256)else{throw AssetLocatorFailureV1.invalidValue};self.source=source;self.inputSHA256=inputSHA256;self.decoded=decoded}
}

protocol AssetLocatorQueryingV1: Sendable {
    func locator(id: UUID, workspaceID: WorkspaceID) async throws -> AssetLocatorV1?
    func bindingReceipt(id: UUID, workspaceID: WorkspaceID) async throws -> LocatorBindingReceiptV1?
    func locators(lookupKey: String, workspaceID: WorkspaceID) async throws -> [AssetLocatorV1]
    func locatorExistsOutsideWorkspace(
        lookupKey: String,
        workspaceID: WorkspaceID
    ) async throws -> Bool
}

extension AssetLocatorQueryingV1 {
    func bindingReceipt(id: UUID, workspaceID: WorkspaceID) async throws -> LocatorBindingReceiptV1? { nil }
    func locatorExistsOutsideWorkspace(
        lookupKey: String,
        workspaceID: WorkspaceID
    ) async throws -> Bool { false }
}

protocol LocalLocatorSignatureVerifyingV1: Sendable {
    func verify(payload: Data, signature: Data, key: LocatorSigningKeyReferenceV1) throws -> Bool
}

struct OfflineAssetLocatorResolverV1: Sendable {
    let query: any AssetLocatorQueryingV1
    let signatureVerifier: any LocalLocatorSignatureVerifyingV1

    func resolve(_ input: LocatorResolutionInputV1, workspaceID: WorkspaceID, evaluatedAt: Date) async throws -> LocatorResolutionV1 {
        switch input.decoded {
        case .damagedOrIncomplete:
            return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])
        case .localSigned(let payload):
            do { try payload.validateStructure() } catch { return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[]) }
            guard payload.workspaceID == workspaceID else { return try result(input,.foreignWorkspace,workspaceID,evaluatedAt,nil,[]) }
            guard try signatureVerifier.verify(payload:payload.unsignedCanonicalData(),signature:payload.signatureData,key:payload.signingKey) else{return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])}
            guard let locator=try await query.locator(id:payload.locatorID,workspaceID:workspaceID) else{return try result(input,.noMatch,workspaceID,evaluatedAt,nil,[])}
            guard case .localSigned(let stored)=locator.representation,stored==payload else{return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[])}
            return try result(input,outcome(locator.state),workspaceID,evaluatedAt,locator,[])
        case .externalKey(let key):
            do { try key.validate() } catch { return try result(input,.damagedOrIncomplete,workspaceID,evaluatedAt,nil,[]) }
            let candidates=try await query.locators(lookupKey:key.lookupKey,workspaceID:workspaceID).sorted{$0.locatorID.uuidString<$1.locatorID.uuidString}
            guard candidates.count<=AssetLocatorLimitsV1.maximumCandidates else{return try result(input,.ambiguous,workspaceID,evaluatedAt,nil,Array(candidates.prefix(AssetLocatorLimitsV1.maximumCandidates)))}
            guard !candidates.isEmpty else {
                let foreign = try await query.locatorExistsOutsideWorkspace(
                    lookupKey: key.lookupKey, workspaceID: workspaceID
                )
                return try result(
                    input, foreign ? .foreignWorkspace : .noMatch,
                    workspaceID, evaluatedAt, nil, []
                )
            }
            guard candidates.count==1 else{return try result(input,.ambiguous,workspaceID,evaluatedAt,nil,candidates)}
            return try result(input,outcome(candidates[0].state),workspaceID,evaluatedAt,candidates[0],[])
        }
    }

    private func outcome(_ state:AssetLocatorStateV1)->LocatorResolutionOutcomeV1{switch state{case .active:return .matched;case .retired:return .retired;case .revoked:return .revoked;case .replaced:return .replaced}}
    private func result(_ input:LocatorResolutionInputV1,_ outcome:LocatorResolutionOutcomeV1,_ workspaceID:WorkspaceID,_ at:Date,_ locator:AssetLocatorV1?,_ candidates:[AssetLocatorV1])throws->LocatorResolutionV1{try .init(workspaceID:workspaceID,source:input.source,inputSHA256:input.inputSHA256,outcome:outcome,matchedLocator:try locator?.reference,matchedAssetID:locator?.assetID,replacementLocatorID:locator?.replacedByLocatorID,candidateLocators:try candidates.map{$0.reference},evaluatedAt:at)}
}

struct AssetLocatorCoordinatorV1: Sendable {
    let resolver: OfflineAssetLocatorResolverV1
    func resolveCamera(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .camera else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func resolveManual(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .manual else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func resolveImported(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{guard input.source == .imported else{throw AssetLocatorFailureV1.invalidValue};return try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func preview(action:LocatorBindingActionV1,before:AssetLocatorV1?,after:AssetLocatorV1,replacement:AssetLocatorV1?,generatedAt:Date)throws->LocatorBindingPreviewV1{let value=try LocatorBindingPreviewV1(workspaceID:after.workspaceID,action:action,before:try before?.reference,after:after.reference,replacement:try replacement?.reference,generatedAt:generatedAt);try value.validate(before:before,after:after,replacement:replacement);return value}
}

protocol AssetLocatorMutationCommittingV1: AnyObject {
    func commitAssetLocator(_ mutation: AssetLocatorMutationV1) throws -> MutationReceiptV1
    func durableReceipt(mutationID: MutationIDV1) throws -> MutationReceiptV1?
    func manualShortCodeIsAvailable(_ code: ManualShortCodeV1, workspaceID: WorkspaceID) throws -> Bool
}

extension WorkspaceWriterV1: AssetLocatorMutationCommittingV1 {}

/// Entropy is injected so tests remain deterministic; the live conformer uses
/// the platform cryptographic random generator and never accepts caller bodies.
protocol ManualShortCodeCryptographicEntropyV1: Sendable {
    func randomBytes(count: Int) throws -> Data
}

struct ManualShortCodeIssuanceCoordinatorV1 {
    static let maximumCollisionAttempts = 32
    static let entropyBytesPerAttempt = 64
    let query: any AssetLocatorQueryingV1
    let writer: any AssetLocatorMutationCommittingV1
    let entropy: any ManualShortCodeCryptographicEntropyV1

    init(query: any AssetLocatorQueryingV1,
         writer: any AssetLocatorMutationCommittingV1,
         entropy: any ManualShortCodeCryptographicEntropyV1) {
        self.query = query; self.writer = writer; self.entropy = entropy
    }

    /// Generates a workspace-unique candidate. Persist/retry this exact envelope
    /// through the existing resumable operation boundary if the process can die.
    func prepare(_ operation: ManualShortCodeIssuanceOperationV1) async throws
        -> ManualShortCodeIssuanceRequestV1 {
        try operation.validate()
        if let durable = try writer.durableReceipt(mutationID: operation.mutationID) {
            guard let locator = try await query.locator(id: operation.locatorID, workspaceID: operation.workspaceID),
                  let binding = try await query.bindingReceipt(id: operation.bindingReceiptID, workspaceID: operation.workspaceID),
                  let code = binding.manualShortCodeIssuance else {
                throw AssetLabelContractFailureV1.shortCodeRecoveryRequiresPreparedRequest
            }
            let request = try ManualShortCodeIssuanceRequestV1(
                operation: operation, issuerGeneratedShortCode: code
            )
            _ = try ManualShortCodeIssuanceReceiptV1(
                request: request, locator: locator, bindingReceipt: binding,
                mutationReceipt: durable
            )
            return request
        }
        if let locator = try await query.locator(id: operation.locatorID, workspaceID: operation.workspaceID) {
            guard let binding = try await query.bindingReceipt(id: operation.bindingReceiptID, workspaceID: operation.workspaceID),
                  let code = binding.manualShortCodeIssuance else {
                throw AssetLabelContractFailureV1.shortCodeRecoveryRequiresPreparedRequest
            }
            let request = try ManualShortCodeIssuanceRequestV1(
                operation: operation, issuerGeneratedShortCode: code
            )
            let exact = try bindingBundle(for: request)
            guard exact.locator == locator, exact.bindingReceipt == binding else {
                throw AssetLabelContractFailureV1.invalidReceipt
            }
            return request
        }
        for _ in 0..<Self.maximumCollisionAttempts {
            let code = try candidate()
            let key = try code.externalKey()
            let matches = try await query.locators(lookupKey: key.lookupKey, workspaceID: operation.workspaceID)
            guard matches.count <= AssetLocatorLimitsV1.maximumCandidates else {
                throw AssetLocatorFailureV1.ambiguous
            }
            if matches.isEmpty,
               try writer.manualShortCodeIsAvailable(code, workspaceID: operation.workspaceID) {
                return try .init(operation: operation, issuerGeneratedShortCode: code)
            }
        }
        throw AssetLabelContractFailureV1.shortCodeCollisionLimitReached
    }

    func issue(_ operation: ManualShortCodeIssuanceOperationV1) async throws
        -> ManualShortCodeIssuanceReceiptV1 {
        let request = try await prepare(operation)
        return try await issue(request)
    }

    /// Idempotent prepared-request path. A durable matching C27 receipt wins;
    /// mismatched MutationID reuse is rejected by the canonical receipt wrapper.
    func issue(_ request: ManualShortCodeIssuanceRequestV1) async throws
        -> ManualShortCodeIssuanceReceiptV1 {
        try request.validate()
        let bundle = try bindingBundle(for: request)
        if let recovered = try writer.durableReceipt(mutationID: request.operation.mutationID) {
            return try .init(request: request, locator: bundle.locator,
                             bindingReceipt: bundle.bindingReceipt, mutationReceipt: recovered)
        }
        let key = try request.shortCode.externalKey()
        let matches = try await query.locators(lookupKey: key.lookupKey,
                                               workspaceID: request.operation.workspaceID)
        let exactEffect = matches.count == 1 && matches[0] == bundle.locator
        guard matches.isEmpty || exactEffect else {
            throw AssetLabelContractFailureV1.shortCodeCollisionLimitReached
        }
        if matches.isEmpty,
           try !writer.manualShortCodeIsAvailable(
                request.shortCode, workspaceID: request.operation.workspaceID
           ) {
            throw AssetLabelContractFailureV1.shortCodeCollisionLimitReached
        }
        do {
            let receipt = try writer.commitAssetLocator(bundle.mutation)
            return try .init(request: request, locator: bundle.locator,
                             bindingReceipt: bundle.bindingReceipt, mutationReceipt: receipt)
        } catch {
            // Covers effect-before-receipt interruption when the canonical writer
            // recovered/committed the same MutationID before surfacing an error.
            if let recovered = try writer.durableReceipt(mutationID: request.operation.mutationID) {
                return try .init(request: request, locator: bundle.locator,
                                 bindingReceipt: bundle.bindingReceipt, mutationReceipt: recovered)
            }
            throw error
        }
    }

    private func candidate() throws -> ManualShortCodeV1 {
        let alphabet = Array(ManualShortCodeV1.alphabet)
        let bytes = try entropy.randomBytes(count: Self.entropyBytesPerAttempt)
        guard bytes.count == Self.entropyBytesPerAttempt else {
            throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
        }
        let acceptanceLimit = (256 / alphabet.count) * alphabet.count
        var body = ""
        for byte in bytes where Int(byte) < acceptanceLimit {
            body.append(alphabet[Int(byte) % alphabet.count])
            if body.count == ManualShortCodeV1.randomBodyLength { return try .init(randomBody: body) }
        }
        throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
    }

    private func bindingBundle(for request: ManualShortCodeIssuanceRequestV1) throws
        -> (locator: AssetLocatorV1, bindingReceipt: LocatorBindingReceiptV1,
            mutation: AssetLocatorMutationV1) {
        let operation = request.operation
        let locator = try AssetLocatorV1(
            locatorID: operation.locatorID, workspaceID: operation.workspaceID,
            assetID: operation.assetID, representation: .externalKey(request.shortCode.externalKey()),
            state: .active, revision: 1, mutationID: operation.mutationID,
            recordedAt: operation.requestedAt
        )
        let preview = try LocatorBindingPreviewV1(
            workspaceID: operation.workspaceID, action: .bind, before: nil,
            after: locator.reference, replacement: nil, generatedAt: operation.requestedAt
        )
        let bindingReceipt = try LocatorBindingReceiptV1(
            receiptID: operation.bindingReceiptID, preview: preview,
            recordedBy: operation.recordedBy, predecessor: nil, revision: 1,
            mutationID: operation.mutationID, recordedAt: operation.requestedAt,
            manualShortCodeIssuance: request.shortCode
        )
        let mutation = try AssetLocatorMutationV1(
            workspaceID: operation.workspaceID, mutationID: operation.mutationID,
            payload: .bind(locator, receipt: bindingReceipt, predecessorReceipt: nil)
        )
        return (locator, bindingReceipt, mutation)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Application_AssetSemantics_AssetLocatorCoordinatorV1_swift {
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
enum C30ConsumerBoundaryV1_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Application/AssetSemantics/AssetLocatorCoordinatorV1.swift", role: .asset)
}

enum C31LightingConsumerBoundary_Application_AssetSemantics_AssetLocatorCoordinatorV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-locator-coordinator"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}
// MARK: - C32 assistance asset locator boundary

enum C32AssistanceLifecycleBoundary_FieldEvidenceApp_Application_AssetSemantics_AssetLocatorCoordinatorV1_swift {
    static let proposalIsPersistent = AssistancePersistenceEnrollmentV1.proposalIsPersistent
    static let rejectedProposalCorpusIsPersistent = AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent
    static let durableFamilyCount = AssistancePersistenceEnrollmentV1.durableModelCount
    static let acceptedMutationKind: WorkspaceCommandKindV1 = .applyAssistanceAcceptance
    static let manualFallback: ManualFallbackActionV1 = .typeManually
    static let acceptedEffectUsesExistingAssetIdentity = true

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

enum C33TemporalEvidenceBoundary_Application_AssetSemantics_AssetLocatorCoordinatorV1_V1 {
    static let clipType: TemporalEvidenceClipV1.Type = TemporalEvidenceClipV1.self
    static let anchorType: TimecodedEvidenceAnchorV1.Type = TimecodedEvidenceAnchorV1.self
    static let persistentSchemaVersion: Int =
        TemporalEvidencePersistenceEnrollmentV1.persistentSchemaVersion
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row139 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Application_AssetSemantics_AssetLocatorCoordinatorV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noSecondWriterOrAutomaticHandoff = true
}
