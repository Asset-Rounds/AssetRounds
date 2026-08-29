import CryptoKit
import Foundation

enum InspectionPackageReleaseStateV1: String, CaseIterable, Codable, Sendable {
    case draft = "DRAFT"
    case tested = "TESTED"
    case published = "PUBLISHED"
}

extension InspectionPackageReleaseV1 {
    func validateSurveySessionAuthority(_ authority:SurveySessionAuthorityV1,definition:SurveyDefinitionReleaseV1)throws{try authority.validate(definition:definition,packageRelease:self);guard state == .published,definition.activityKind == .survey,authority.packageRelease.packageReleaseID == packageReleaseID,authority.packageRelease.packageSHA256 == packageSHA256,authority.packageRelease.workflowSHA256 == workflowSHA256 else{throw SurveySessionFailureV1.wrongDefinition}}
}

extension InspectionPackageReleaseV1 {
    func validateSurveyDefinitionRelease(_ survey: SurveyDefinitionReleaseV1) throws {
        try validate(); try survey.validate()
        guard survey.ownerPackageID == packageID else { throw InspectionKernelFailureV1.invalidValue }
    }
}

enum InspectionPackageAccessibleDocumentBoundaryV1{
    static let semanticTreeMayChangePackageTruth=false
    static let assessmentMayActivatePackageRelease=false
}

extension InspectionPackageReleaseV1 {
    func validateFieldReferenceRelease(_ reference: FieldReferenceReleaseV1) throws {
        try validate()
        try reference.validate()
        let package = try InspectionPackageCanonicalCodecV2.decode(canonicalPackageBytes)
        try package.validateFieldReference(reference)
    }
}

extension InspectionPackageReleaseV1 {
    func validateClientCapability(policy: PackageLifecyclePolicyV1,
                                  disposition: PackageLifecycleDispositionV1) throws {
        try validate(); try policy.validate(release: self); try disposition.validate(release: self)
        guard policy.workspaceID == disposition.workspaceID,
              policy.packageReleaseID == packageReleaseID,
              disposition.packageReleaseID == packageReleaseID else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }
}

// Deliberately non-Codable and privately constructible: canonical release bytes
// remain readable history, but changing their state member cannot manufacture
// ordered transition authority.
struct InspectionPackageReleaseTransitionProofV1: Equatable, Sendable {
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let orderedStates: [InspectionPackageReleaseStateV1]

    private init(
        release: InspectionPackageReleaseV1,
        orderedStates: [InspectionPackageReleaseStateV1]
    ) {
        packageReleaseID = release.packageReleaseID
        packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        self.orderedStates = orderedStates
    }

    fileprivate static func tested(_ release: InspectionPackageReleaseV1)
        -> InspectionPackageReleaseTransitionProofV1 {
        InspectionPackageReleaseTransitionProofV1(
            release: release,
            orderedStates: [.draft, .tested]
        )
    }

    fileprivate static func published(_ release: InspectionPackageReleaseV1)
        -> InspectionPackageReleaseTransitionProofV1 {
        InspectionPackageReleaseTransitionProofV1(
            release: release,
            orderedStates: [.draft, .tested, .published]
        )
    }

    fileprivate func validate(
        release: InspectionPackageReleaseV1,
        expectedStates: [InspectionPackageReleaseStateV1]
    ) throws {
        guard packageReleaseID == release.packageReleaseID,
              packageSHA256 == release.packageSHA256,
              workflowSHA256 == release.workflowSHA256,
              orderedStates == expectedStates,
              release.state == expectedStates.last else {
            throw InspectionKernelFailureV1.invalidTransition
        }
    }
}

struct InspectionPackageTestedReleaseV1: Equatable, Sendable {
    let release: InspectionPackageReleaseV1
    let transitionProof: InspectionPackageReleaseTransitionProofV1

    fileprivate init(
        release: InspectionPackageReleaseV1,
        transitionProof: InspectionPackageReleaseTransitionProofV1
    ) {
        self.release = release
        self.transitionProof = transitionProof
    }

    func validate() throws {
        try release.validate()
        try transitionProof.validate(release: release, expectedStates: [.draft, .tested])
    }
}

struct InspectionPackagePublicationReceiptV1: Equatable, Sendable {
    let packageReleaseID: String
    let packageSHA256: String
    let workflowSHA256: String
    let orderedStates: [InspectionPackageReleaseStateV1]

    private init(release: InspectionPackageReleaseV1) {
        packageReleaseID = release.packageReleaseID
        packageSHA256 = release.packageSHA256
        workflowSHA256 = release.workflowSHA256
        orderedStates = [.draft, .tested, .published]
    }

    fileprivate static func issued(for release: InspectionPackageReleaseV1)
        -> InspectionPackagePublicationReceiptV1 {
        InspectionPackagePublicationReceiptV1(release: release)
    }

    func validate(release: InspectionPackageReleaseV1) throws {
        guard packageReleaseID == release.packageReleaseID,
              packageSHA256 == release.packageSHA256,
              workflowSHA256 == release.workflowSHA256,
              orderedStates == [.draft, .tested, .published],
              release.state == .published else {
            throw InspectionKernelFailureV1.invalidTransition
        }
    }
}

struct InspectionPackagePublishedReleaseV1: Equatable, Sendable {
    let release: InspectionPackageReleaseV1
    let publicationReceipt: InspectionPackagePublicationReceiptV1

    fileprivate init(
        release: InspectionPackageReleaseV1,
        publicationReceipt: InspectionPackagePublicationReceiptV1
    ) {
        self.release = release
        self.publicationReceipt = publicationReceipt
    }

    func validate() throws {
        try release.validate()
        try publicationReceipt.validate(release: release)
    }
}

struct InspectionPackageReleaseV1: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let packageReleaseID: String
    let packageID: String
    let packageContentVersion: Int
    let packageSHA256: String
    let canonicalPackageBytes: Data
    let workflowSHA256: String
    let canonicalWorkflowBytes: Data
    let state: InspectionPackageReleaseStateV1

    private init(
        schemaVersion: Int,
        packageReleaseID: String,
        packageID: String,
        packageContentVersion: Int,
        packageSHA256: String,
        canonicalPackageBytes: Data,
        workflowSHA256: String,
        canonicalWorkflowBytes: Data,
        state: InspectionPackageReleaseStateV1
    ) {
        self.schemaVersion = schemaVersion
        self.packageReleaseID = packageReleaseID
        self.packageID = packageID
        self.packageContentVersion = packageContentVersion
        self.packageSHA256 = packageSHA256
        self.canonicalPackageBytes = canonicalPackageBytes
        self.workflowSHA256 = workflowSHA256
        self.canonicalWorkflowBytes = canonicalWorkflowBytes
        self.state = state
    }

    static func makeDraft(
        package: InspectionPackageV2,
        workflow: WorkflowDefinitionV1
    ) throws -> InspectionPackageReleaseV1 {
        try makeValidated(package: package, workflow: workflow, state: .draft)
    }

    fileprivate static func makeValidated(
        package: InspectionPackageV2,
        workflow: WorkflowDefinitionV1,
        state: InspectionPackageReleaseStateV1
    ) throws -> InspectionPackageReleaseV1 {
        try InspectionPackageCompatibilityValidatorV2.validate(package)
        _ = try WorkflowGraphValidatorV1.validate(workflow)
        let packageBytes = try InspectionPackageCanonicalCodecV2.encode(package)
        let workflowBytes = try WorkflowDefinitionCanonicalCodecV1.encode(workflow)
        let packageHash = KernelCanonicalHashV1.sha256(packageBytes)
        let workflowHash = KernelCanonicalHashV1.sha256(workflowBytes)
        let releaseID = KernelCanonicalHashV1.sha256(
            Data("\(package.packageID)|\(package.contentVersion)|\(packageHash)|\(workflowHash)".utf8)
        )
        return InspectionPackageReleaseV1(
            schemaVersion: schemaVersion,
            packageReleaseID: releaseID,
            packageID: package.packageID,
            packageContentVersion: package.contentVersion,
            packageSHA256: packageHash,
            canonicalPackageBytes: packageBytes,
            workflowSHA256: workflowHash,
            canonicalWorkflowBytes: workflowBytes,
            state: state
        )
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              KernelCanonicalHashV1.validSHA256(packageReleaseID),
              WorkflowGrammarValidationV1.validID(packageID),
              packageContentVersion > 0,
              KernelCanonicalHashV1.sha256(canonicalPackageBytes) == packageSHA256,
              KernelCanonicalHashV1.sha256(canonicalWorkflowBytes) == workflowSHA256 else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        let package = try InspectionPackageCanonicalCodecV2.decode(canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(canonicalWorkflowBytes)
        guard package.packageID == packageID, package.contentVersion == packageContentVersion else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        _ = try WorkflowGraphValidatorV1.validate(workflow)
        let expected = try Self.makeValidated(package: package, workflow: workflow, state: state)
        guard expected.packageReleaseID == packageReleaseID else {
            throw InspectionKernelFailureV1.hashMismatch
        }
    }
}

enum InspectionPackageReleasePublisherV1 {
    enum Boundary: String, CaseIterable, Sendable {
        case beforeValidation = "BEFORE_VALIDATION"
        case afterValidationBeforePublication = "AFTER_VALIDATION_BEFORE_PUBLICATION"
        case afterPublicationBeforeReceipt = "AFTER_PUBLICATION_BEFORE_RECEIPT"
    }
    typealias Interruption = @Sendable (Boundary) throws -> Void

    static func test(
        _ release: InspectionPackageReleaseV1,
        interruption: Interruption = { _ in }
    ) throws -> InspectionPackageTestedReleaseV1 {
        try interruption(.beforeValidation)
        try release.validate()
        guard release.state == .draft else { throw InspectionKernelFailureV1.invalidTransition }
        let package = try InspectionPackageCanonicalCodecV2.decode(release.canonicalPackageBytes)
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(release.canonicalWorkflowBytes)
        let candidate = try InspectionPackageReleaseV1.makeValidated(
            package: package,
            workflow: workflow,
            state: .tested
        )
        guard candidate.packageReleaseID == release.packageReleaseID else {
            throw InspectionKernelFailureV1.immutableRelease
        }
        try interruption(.afterValidationBeforePublication)
        try interruption(.afterPublicationBeforeReceipt)
        return InspectionPackageTestedReleaseV1(
            release: candidate,
            transitionProof: .tested(candidate)
        )
    }

    static func publish(
        _ tested: InspectionPackageTestedReleaseV1,
        interruption: Interruption = { _ in }
    ) throws -> InspectionPackagePublishedReleaseV1 {
        try interruption(.beforeValidation)
        try tested.validate()
        let package = try InspectionPackageCanonicalCodecV2.decode(
            tested.release.canonicalPackageBytes
        )
        let workflow = try WorkflowDefinitionCanonicalCodecV1.decode(
            tested.release.canonicalWorkflowBytes
        )
        let candidate = try InspectionPackageReleaseV1.makeValidated(
            package: package,
            workflow: workflow,
            state: .published
        )
        guard candidate.packageReleaseID == tested.release.packageReleaseID else {
            throw InspectionKernelFailureV1.immutableRelease
        }
        try interruption(.afterValidationBeforePublication)
        let proof = InspectionPackageReleaseTransitionProofV1.published(candidate)
        try proof.validate(
            release: candidate,
            expectedStates: [.draft, .tested, .published]
        )
        try interruption(.afterPublicationBeforeReceipt)
        return InspectionPackagePublishedReleaseV1(
            release: candidate,
            publicationReceipt: .issued(for: candidate)
        )
    }

    static func adopt(
        _ publication: InspectionPackagePublishedReleaseV1
    ) throws -> InspectionPackagePublishedReleaseV1 {
        try publication.validate()
        return publication
    }

    // Relaunch never trusts the encoded state member alone. The exact accepted
    // binding is the separately stored publication authority; every canonical
    // byte and hash must reconcile before an in-memory receipt is reissued.
    static func recoverPublished(
        _ historicalRelease: InspectionPackageReleaseV1,
        acceptedBinding: PackageReleaseBindingV1
    ) throws -> InspectionPackagePublishedReleaseV1 {
        try historicalRelease.validate()
        try acceptedBinding.validate()
        guard historicalRelease.state == .published,
              acceptedBinding.packageReleaseID == historicalRelease.packageReleaseID,
              acceptedBinding.packageID == historicalRelease.packageID,
              acceptedBinding.packageContentVersion == historicalRelease.packageContentVersion,
              acceptedBinding.packageSHA256 == historicalRelease.packageSHA256,
              acceptedBinding.canonicalPackageBytes == historicalRelease.canonicalPackageBytes,
              acceptedBinding.workflowSHA256 == historicalRelease.workflowSHA256,
              acceptedBinding.canonicalWorkflowBytes == historicalRelease.canonicalWorkflowBytes else {
            throw InspectionKernelFailureV1.releaseNotFound
        }
        return InspectionPackagePublishedReleaseV1(
            release: historicalRelease,
            publicationReceipt: .issued(for: historicalRelease)
        )
    }
}

enum WorkflowDefinitionCanonicalCodecV1 {
    static func encode(_ value: WorkflowDefinitionV1) throws -> Data {
        _ = try WorkflowGraphValidatorV1.validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> WorkflowDefinitionV1 {
        guard !data.isEmpty, data.count <= 1_048_576 else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(WorkflowDefinitionV1.self, from: data)
        guard try encode(value) == data else { throw InspectionKernelFailureV1.invalidValue }
        return value
    }
}

enum InspectionPackageReleaseCanonicalCodecV1 {
    static func encode(_ value: InspectionPackageReleaseV1) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode(_ data: Data) throws -> InspectionPackageReleaseV1 {
        guard !data.isEmpty, data.count <= 2_097_152 else {
            throw InspectionKernelFailureV1.limitExceeded
        }
        let value = try JSONDecoder().decode(InspectionPackageReleaseV1.self, from: data)
        guard try encode(value) == data else { throw InspectionKernelFailureV1.invalidValue }
        return value
    }
}

enum KernelCanonicalHashV1 {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func validSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x61...0x66).contains($0)
        }
    }
}

extension InspectionPackageReleaseV1 {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, packageReleaseID, packageID, packageContentVersion
        case packageSHA256, canonicalPackageBytes, workflowSHA256
        case canonicalWorkflowBytes, state
    }
    init(from decoder: any Decoder) throws {
        try KernelClosedCodingV1.require(decoder, keys: CodingKeys.allCases.map(\.rawValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            packageReleaseID: try c.decode(String.self, forKey: .packageReleaseID),
            packageID: try c.decode(String.self, forKey: .packageID),
            packageContentVersion: try c.decode(Int.self, forKey: .packageContentVersion),
            packageSHA256: try c.decode(String.self, forKey: .packageSHA256),
            canonicalPackageBytes: try c.decode(Data.self, forKey: .canonicalPackageBytes),
            workflowSHA256: try c.decode(String.self, forKey: .workflowSHA256),
            canonicalWorkflowBytes: try c.decode(Data.self, forKey: .canonicalWorkflowBytes),
            state: try c.decode(InspectionPackageReleaseStateV1.self, forKey: .state)
        )
        try validate()
    }
}

// MARK: - C19 measurement release binding

extension InspectionPackageReleaseV1 {
    /// A capture carries the exact package-release and workflow digests. The
    /// release remains immutable and declaration-only; this method only
    /// verifies that binding before a capture is consumed.
    func c19ValidateMeasurementCapture(
        _ capture: MeasurementCaptureV1
    ) throws {
        try validate()
        try capture.validate()
        guard capture.packageReleaseID == packageReleaseID,
              capture.workflowSHA256 == workflowSHA256 else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }

    func c19ValidateMeasurementSeries(
        _ series: MeasurementSeriesV1,
        captures: [MeasurementCaptureV1],
        protocolRelease: MeasurementProtocolReleaseV1
    ) throws {
        try validate()
        try protocolRelease.c19ValidateSeries(series, captures: captures)
        guard captures.allSatisfy({
            $0.packageReleaseID == packageReleaseID
                && $0.workflowSHA256 == workflowSHA256
        }) else {
            throw MeasurementIntegrityFailureV1.staleReference
        }
    }
}

// MARK: - C20 reviewed-derivative release binding

extension InspectionPackageReleaseV1 {
    /// Checks the immutable package bytes/release identity before allowing a
    /// C20 derivative projection. This is a read-only validation seam: it
    /// neither changes release state nor makes a privacy/compliance claim.
    func c20ValidateReviewedDerivative(
        package: InspectionPackageV2,
        manifest: PrivacyTransformManifestV1,
        review: PrivacyReviewReceiptV1?,
        policy: PrivacyTransformPolicyV1,
        requestedAudience: EvidenceAudienceV1,
        currentSourceRevision: UInt64,
        currentSourceSHA256: String,
        at now: Date
    ) throws -> ContentReferenceV1 {
        try validate()
        try package.validate()
        let encodedPackage = try InspectionPackageCanonicalCodecV2.encode(package)
        guard packageID == package.packageID,
              packageContentVersion == package.contentVersion,
              canonicalPackageBytes == encodedPackage,
              KernelCanonicalHashV1.sha256(encodedPackage) == packageSHA256 else {
            throw InspectionKernelFailureV1.hashMismatch
        }
        guard manifest.workspaceID == policy.workspaceID else {
            throw PrivacyTransformFailureV1.wrongWorkspace
        }
        return try C20PrivacyProjectionBridgeV1.requireAllowed(
            manifest: manifest,
            review: review,
            policy: policy,
            requestedAudience: requestedAudience,
            currentSourceRevision: currentSourceRevision,
            currentSourceSHA256: currentSourceSHA256,
            at: now
        )
    }
}

/// C29 typed integration anchor: this owner consumes an exact immutable plan
/// revision reference and may not reinterpret current plan state implicitly.
enum C29PlanIntegration_Domain_InspectionKernel_InspectionPackageReleaseV1 {
    static func validatePlanRevision(_ value: PlanRevisionReferenceV1) throws {
        try value.validate()
    }
}

enum C37PoseIntegration_FieldEvidenceApp_Domain_InspectionKernel_InspectionPackageReleaseV1_swift {
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
