import CryptoKit
import Foundation
import Security

struct SystemManualShortCodeCryptographicEntropyV1: ManualShortCodeCryptographicEntropyV1 {
    func randomBytes(count: Int) throws -> Data {
        guard count > 0, count <= ManualShortCodeIssuanceCoordinatorV1.entropyBytesPerAttempt else {
            throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
        }
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes -> OSStatus in
            guard let address = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, address)
        }
        guard status == errSecSuccess else {
            throw AssetLabelContractFailureV1.insufficientCryptographicEntropy
        }
        return data
    }
}

struct Ed25519LocalLocatorSignatureVerifierV1: LocalLocatorSignatureVerifyingV1 {
    func verify(payload:Data,signature:Data,key:LocatorSigningKeyReferenceV1)throws->Bool{try key.validate();guard signature.count==AssetLocatorLimitsV1.ed25519SignatureBytes else{return false};do{return try Curve25519.Signing.PublicKey(rawRepresentation:key.publicKeyData).isValidSignature(signature,for:payload)}catch{return false}}
}

struct AssetLocatorInputDecoderV1:Sendable{
    func localSigned(_ bytes:Data,source:LocatorInputSourceV1)throws->LocatorResolutionInputV1{let digest=KernelCanonicalHashV1.sha256(bytes);guard !bytes.isEmpty,bytes.count<=AssetLocatorLimitsV1.maximumInputBytes else{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)};do{let payload=try AssetLocatorCanonicalCodecV1.decode(SignedLocalAssetLocatorPayloadV1.self,from:bytes);try payload.validateStructure();return try .init(source:source,inputSHA256:digest,decoded:.localSigned(payload))}catch{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)}}
    func externalKey(_ bytes:Data,namespaceID:String,normalization:ExternalKeyNormalizationV1,source:LocatorInputSourceV1)throws->LocatorResolutionInputV1{let digest=KernelCanonicalHashV1.sha256(bytes);guard !bytes.isEmpty,bytes.count<=AssetLocatorLimitsV1.maximumInputBytes,let value=String(data:bytes,encoding:.utf8)else{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)};do{return try .init(source:source,inputSHA256:digest,decoded:.externalKey(try ExternalKeyV1(namespaceID:namespaceID,normalization:normalization,suppliedValue:value)))}catch{return try .init(source:source,inputSHA256:digest,decoded:.damagedOrIncomplete)}}
}

struct AssetLocatorLifecycleAdapterV1{
    let resolver:OfflineAssetLocatorResolverV1
    let writer:(any AssetLocatorMutationCommittingV1)?
    init(resolver:OfflineAssetLocatorResolverV1,writer:(any AssetLocatorMutationCommittingV1)?=nil){self.resolver=resolver;self.writer=writer}
    func resolve(_ input:LocatorResolutionInputV1,workspaceID:WorkspaceID,evaluatedAt:Date)async throws->LocatorResolutionV1{try await resolver.resolve(input,workspaceID:workspaceID,evaluatedAt:evaluatedAt)}
    func publish(_ mutation:AssetLocatorMutationV1)throws->AssetLocatorMutationReceiptV1{guard let writer else{throw WorkspaceMutationFailureV1.writerInvalidated};try mutation.validate();let receipt=try writer.commitAssetLocator(mutation);return try .init(mutation:mutation,mutationReceipt:receipt)}
    func manualShortCodeIssuanceCoordinator() throws -> ManualShortCodeIssuanceCoordinatorV1 {
        guard let writer else { throw WorkspaceMutationFailureV1.writerInvalidated }
        return .init(query: resolver.query, writer: writer,
                     entropy: SystemManualShortCodeCryptographicEntropyV1())
    }
    func validateClosure(locators:[AssetLocatorV1],receipts:[LocatorBindingReceiptV1])throws{_ = try AssetLocatorLifecycleClosureV1(locators:locators,receipts:receipts)}
    static let scanMutatesCanonicalState=false
    static let resolutionStartsWork=false
    static let resolutionGrantsAccess=false
}

extension AssetLocatorLifecycleAdapterV1 {
    func resolveScanToWork(_ input: LocatorResolutionInputV1,
                           source: ScanToWorkEntrySourceV1,
                           workspaceID: WorkspaceID,
                           evaluatedAt: Date) async throws -> LocatorResolutionV1 {
        guard input.source == source.locatorSource else { throw AssetLocatorFailureV1.invalidValue }
        return try await resolve(input, workspaceID: workspaceID, evaluatedAt: evaluatedAt)
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1_swift {
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
enum C30ConsumerBoundaryV1_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    static let registration = C30ConsumerRegistrationV1(ownerPath: "FieldEvidenceApp/Infrastructure/AssetSemantics/AssetLocatorLifecycleAdapterV1.swift", role: .asset)
}

enum C31LightingConsumerBoundary_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    static let registrationID = "C31_LIGHTING_CONSUMER/asset-locator-lifecycle-adapter"
    static let compatibility = C31LightingCompatibilityPolicyV1()
    static func validate(projection: C31LightingReportProjectionV1) throws {
        try compatibility.validate()
        try C31LightingProjectionPolicyV1.validate(projection)
    }
}

/// C32 keeps assistance candidates outside every durable and derived surface;
/// only explicit acceptance may reach the existing canonical writer/receipt path.
enum C32AssistanceCompatibility_AssetSemantics_AssetLocatorLifecycleAdapterV1 {
    enum ProposalDispositionV1: Sendable {
        case nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
    }

    enum AcceptanceDispositionV1: Sendable {
        case durableThroughExistingCanonicalWriter
    }

    static func disposition(
        for proposal: AssistanceProposalV1
    ) throws -> ProposalDispositionV1 {
        try proposal.validate()
        guard !AssistancePersistenceEnrollmentV1.proposalIsPersistent,
              !AssistancePersistenceEnrollmentV1.rejectedProposalCorpusIsPersistent else {
            throw AssistanceContractFailureV1.nonCanonicalData
        }
        switch proposal.verificationState {
        case .unverified:
            return .nonpersistentUnverifiedExcludedFromStorageSearchReportBackup
        }
    }

    static func disposition(
        for receipt: AssistanceAcceptanceReceiptV1
    ) throws -> AcceptanceDispositionV1 {
        try receipt.validate()
        guard AssistancePersistenceEnrollmentV1.durableModelCount == 1 else {
            throw AssistanceContractFailureV1.invalidReceipt
        }
        return .durableThroughExistingCanonicalWriter
    }

    static let capabilityScratchIsDiscardedOnTerminalReview = true
    static let manualFallbackRemainsAvailable = true
    static let interruptionNeverPromotesAProposal = true
    static let createsParallelStoreOrWriter = false
}

enum C33TemporalEvidenceConformance_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1_swift {
    static let durableFamilyCount = TemporalEvidencePersistenceEnrollmentV1.durableModelCount
    static func validate(clip: TemporalEvidenceClipV1,
                         anchor: TimecodedEvidenceAnchorV1) throws {
        try clip.validateIntrinsic()
        try anchor.validate(clip: clip)
        guard durableFamilyCount == 2 else {
            throw TemporalEvidenceContractFailureV1.invalidValue
        }
    }
}

// MARK: - C45 canonical asset-label integration
enum C45AssetLabelBoundary_Row140 {
    static let reusesCanonicalAssetLocatorAndWriter = true
    static func validateAcceptedSnapshot(_ snapshot: AcceptedLabelGenerationSnapshotV1) throws {
        try snapshot.validate()
    }
}
enum C46OperationalContactConformance_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1_swift {
    static let operationalContactsRemainPurposeSeparated = true
    static let systemHandoffsRemainExplicitEphemeralAndNoncanonical = true
    static let subscriberConsentCampaignAndMeasurementProjectionForbidden = true
    static let contactExportExcludedByDefault = true
    static let noContactProjectionOrNetworkDelivery = true
}

// MARK: - C52 lifecycle and privacy boundary
enum C52ServiceRequestBoundary_FieldEvidenceApp_Infrastructure_AssetSemantics_AssetLocatorLifecycleAdapterV1_swift {
    static let acceptedCanonicalRecordPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let acceptedEventPersistence: ServiceRequestPersistenceClassV1 = .canonicalPersistent
    static let duplicateProjectionPersistence: ServiceRequestPersistenceClassV1 = .nonpersistentDerived
    static let rawCapabilityPersistence: ServiceRequestPersistenceClassV1 = .prohibitedPersistent
    static let acceptedLifecycleEnrollment: ServiceRequestPersistenceEnrollmentV1.Type = ServiceRequestPersistenceEnrollmentV1.self
    static let cloneOrForkInvalidatesActiveCapabilities: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.cloneOrForkInvalidatesOutstandingCapabilities
    static let duplicateProjectionIsRebuildable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.derivedProjectionIsRebuildable &&
        !ServiceRequestNoncanonicalBoundaryV1.duplicateProjectionIsPersistent
    static let rawCapabilityIsExcludedFromReportsAndDiagnostics: Bool =
        !ServiceRequestLifecycleRegistrationBoundaryV1.rawCapabilityAppearsInReportsOrDiagnostics
    static let sharedPortableFilesAreRecallable: Bool =
        ServiceRequestLifecycleRegistrationBoundaryV1.escapedPortableFilesCanBeRecalled
    static let unverifiedAssertionsAreVerified: Bool = false
    static let automaticWorkNetworkSLAOrAIClaimsPermitted: Bool = false
}
