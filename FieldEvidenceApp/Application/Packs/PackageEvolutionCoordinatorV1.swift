import Foundation

@MainActor
protocol PackageEvolutionWritingV1: AnyObject {
    func activePointer(workspaceID: WorkspaceID, packageID: String) throws -> ActivePackageRegistryPointerV1?
    func acceptedReceipt(mutationID: MutationIDV1) throws -> PackagePromotionReceiptV1?
    func acceptedLifecycleClosure(mutationID: MutationIDV1) throws -> PackageEvolutionLifecycleClosureV1?
    /// The implementation inserts the release, sandbox and receipt and CASes
    /// the pointer in the sole SwiftData transaction.
    func applyPromotion(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1
}

extension PackageEvolutionCoordinatorV1 {
    func promote(_ bundle: PackagePromotionAtomicBundleV1,
                 admittedBy closure: ClientCapabilityLifecycleClosureV1) throws -> PackagePromotionReceiptV1 {
        try bundle.validateClientCapabilityAdmission(closure)
        return try promoteAdmitted(bundle)
    }
}

// MARK: - C26 active-session package pinning

extension PackageEvolutionCoordinatorV1 {
    /// Package promotion may coexist with older in-flight survey sessions, but
    /// it cannot rewrite their captured definition/package authority.
    static func validateSurveySessionPin(
        _ session: SurveySessionV1,
        definition: SurveyDefinitionReleaseV1,
        packageRelease: InspectionPackageReleaseV1
    ) throws {
        try session.validate(definition: definition)
        try session.authority.validate(
            definition: definition,
            packageRelease: packageRelease
        )
        guard session.activityKind == .survey,
              session.authority.packageRelease == (try SurveyPackageReleaseReferenceV1(packageRelease)),
              packageRelease.packageID == definition.ownerPackageID else {
            throw SurveySessionFailureV1.wrongDefinition
        }
    }
}

/// Typed C36 payload codec bridge. The package release is read from the
/// purpose-owned payload schema; C18 never interprets generic JSON/EAV bytes.
protocol DraftPackageReleaseInspectingV1: Sendable {
    func packageReleaseID(
        in payloadData: Data,
        purpose: DraftPurposeV1,
        codec: DraftPayloadCodecReleaseV1
    ) throws -> String
}

@MainActor
final class PackageEvolutionCoordinatorV1 {
    private let packageWriter: any PackageEvolutionWritingV1
    private let draftCoordinator: FieldDraftCoordinatorV1
    private let draftPayloadInspector: any DraftPackageReleaseInspectingV1

    init(packageWriter: any PackageEvolutionWritingV1,
         draftCoordinator: FieldDraftCoordinatorV1,
         draftPayloadInspector: any DraftPackageReleaseInspectingV1) {
        self.packageWriter = packageWriter
        self.draftCoordinator = draftCoordinator
        self.draftPayloadInspector = draftPayloadInspector
    }

    func previewDraftUpgrade(
        source: FieldDraftCheckpointV1,
        sourceRelease: InspectionPackageReleaseV1,
        targetRelease: InspectionPackageReleaseV1,
        targetPayloadData: Data,
        actor: ActorSnapshotV1,
        consentRecordedAt: Date
    ) throws -> DraftUpgradePlanV1 {
        try source.validate()
        guard source.state == .active else { throw PackageEvolutionFailureV1.ineligibleDraft }
        guard try draftPayloadInspector.packageReleaseID(
            in: source.payloadData, purpose: source.purpose, codec: source.codec
        ) == sourceRelease.packageReleaseID,
              try draftPayloadInspector.packageReleaseID(
                in: targetPayloadData, purpose: source.purpose, codec: source.codec
              ) == targetRelease.packageReleaseID else {
            throw PackageEvolutionFailureV1.staleSource
        }
        let diff = try PackageSemanticDifferV1.diff(source: sourceRelease, target: targetRelease)
        guard diff.classification == .additiveDraftSafe || diff.classification == .draftMigrationRequired else {
            throw PackageEvolutionFailureV1.ineligibleDraft
        }
        let plan = try DraftUpgradePlanV1(
            workspaceID: source.workspaceID, draftID: source.draftID,
            sourceDraftRevision: source.draftRevision,
            sourceBaseCanonicalRevision: source.baseCanonicalRevision,
            sourceCheckpointSHA256: source.checkpointSHA256,
            sourcePayloadSHA256: source.payloadSHA256,
            sourcePackageReleaseID: sourceRelease.packageReleaseID,
            targetPackageReleaseID: targetRelease.packageReleaseID,
            semanticDiffSHA256: diff.diffSHA256,
            targetPayloadData: targetPayloadData,
            declaredActor: actor, consentRecordedAt: consentRecordedAt
        )
        try plan.validate(source: source, diff: diff)
        guard try draftPayloadInspector.packageReleaseID(
            in: source.payloadData, purpose: source.purpose, codec: source.codec
        ) == plan.sourcePackageReleaseID,
              try draftPayloadInspector.packageReleaseID(
                in: plan.targetPayloadData, purpose: source.purpose, codec: source.codec
              ) == plan.targetPackageReleaseID else {
            throw PackageEvolutionFailureV1.staleSource
        }
        return plan
    }

    /// Applies the already-consented preview only through the C36 checkpoint CAS.
    func applyDraftUpgrade(
        plan: DraftUpgradePlanV1,
        source: FieldDraftCheckpointV1,
        diff: PackageSemanticDiffV1,
        mutationID: MutationIDV1,
        updatedAt: Date,
        admittedBy closure: ClientCapabilityLifecycleClosureV1
    ) throws -> MutationReceiptV1 {
        try closure.validate()
        try plan.validate(source: source, diff: diff)
        guard closure.profile.workspaceID == source.workspaceID,
              closure.release.packageReleaseID == plan.targetPackageReleaseID,
              closure.decision.operation == .upgradeDraft,
              closure.decision.admission == .readWrite else {
            throw PackageEvolutionFailureV1.ineligibleDraft
        }
        return try draftCoordinator.applyPackageUpgrade(
            plan: plan, source: source, diff: diff,
            mutationID: mutationID, updatedAt: updatedAt
        )
    }

    private func promoteAdmitted(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1 {
        switch bundle.receipt.operation {
        case .initialActivation:
            return try activateInitial(bundle)
        case .postActivationForwardFix:
            return try applyPostActivationForwardFix(bundle)
        }
    }

    private func activateInitial(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1 {
        guard bundle.receipt.operation == .initialActivation,
              bundle.receipt.postActivationPolicy == .forwardFixOnly,
              bundle.predecessorPointer == nil,
              bundle.resultingPointer.revision == 1 else {
            throw PackageEvolutionFailureV1.incompatiblePromotion
        }
        return try commitPromotion(bundle)
    }

    /// The only operation admitted after an active pointer exists. There is
    /// intentionally no rollback operation: correction publishes a new
    /// immutable release and a successor pointer.
    private func applyPostActivationForwardFix(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1 {
        guard bundle.receipt.operation == .postActivationForwardFix,
              bundle.receipt.postActivationPolicy == .forwardFixOnly,
              let predecessor = bundle.predecessorPointer else {
            throw PackageEvolutionFailureV1.incompatiblePromotion
        }
        try bundle.resultingPointer.validateSuccessor(of: predecessor, expectedRevision: predecessor.revision)
        return try commitPromotion(bundle)
    }

    private func commitPromotion(_ bundle: PackagePromotionAtomicBundleV1) throws -> PackagePromotionReceiptV1 {
        try bundle.validate()
        if let closure = try packageWriter.acceptedLifecycleClosure(mutationID: bundle.receipt.mutationID) {
            try closure.validate()
            guard closure.promotedReleases == [bundle.promotedRelease],
                  closure.sandboxRuns == [bundle.sandboxRun],
                  closure.promotionReceipts == [bundle.receipt],
                  closure.activePointers == [bundle.predecessorPointer, bundle.resultingPointer].compactMap({ $0 }).sorted(by: { $0.pointerID.uuidString < $1.pointerID.uuidString }) else {
                throw PackageEvolutionFailureV1.divergentMutation
            }
            return bundle.receipt
        }
        let current = try packageWriter.activePointer(
            workspaceID: bundle.resultingPointer.workspaceID,
            packageID: bundle.resultingPointer.packageID
        )
        guard current == bundle.predecessorPointer else { throw PackageEvolutionFailureV1.stalePointer }
        let receipt = try packageWriter.applyPromotion(bundle)
        guard receipt == bundle.receipt else { throw PackageEvolutionFailureV1.divergentMutation }
        return receipt
    }
}

// MARK: - C25 package-evolution consumer

enum SurveyDefinitionPackageEvolutionConsumerPolicyV1 {
    static let canonicalWriter = "SOLE_CANONICAL_WORKSPACE_WRITER"
    static let durableFamilies = [
        "SurveyDefinitionIdentityV1",
        "SurveyDefinitionReleaseV1",
    ]
    static let lifecycleEventsUseExistingMutationEnvelope = true
    static let importDisposition = "QUARANTINE_THEN_NEW_DRAFT_IDENTITY"
    static let draftPreviewIsNonpersistent = true
    static let noPackageCreatedStorage = true
    static let noRuntimeCodeExecution = true
    static let noSecondWriter = true
    static let historicReleaseIsImmutable = true

    static func validate() throws {
        guard durableFamilies == [
                "SurveyDefinitionIdentityV1",
                "SurveyDefinitionReleaseV1",
            ],
            lifecycleEventsUseExistingMutationEnvelope,
            importDisposition == "QUARANTINE_THEN_NEW_DRAFT_IDENTITY",
            draftPreviewIsNonpersistent,
            noPackageCreatedStorage,
            noRuntimeCodeExecution,
            noSecondWriter,
            historicReleaseIsImmutable else {
            throw SurveyDefinitionConsumerFailureV1.invalidValue
        }
    }
}

extension PackageEvolutionCoordinatorV1 {
    /// Package evolution may inspect and carry a validated definition release,
    /// but it does not become a second writer for the canonical identity or
    /// release lifecycle.
    static func validateSurveyDefinitionConsumer(
        _ release: SurveyDefinitionReleaseV1
    ) throws -> SurveyDefinitionReleaseReferenceV1 {
        try SurveyDefinitionPackageEvolutionConsumerPolicyV1.validate()
        try release.validate()
        return try SurveyDefinitionReleaseReferenceV1(release)
    }
}

enum C47ActivityContractConformance_FieldEvidenceApp_Application_Packs_PackageEvolutionCoordinatorV1_swift {
    static let integrationRole = "SHARED_INVALIDATION_THROUGH_PACKAGE_EVOLUTION"
    static let sharedReceipt = SharedActivityEnvelopeReceiptV1.self
    static let installationReceipt = InstallationActivityContractReceiptV1.self
    static let punchReceipt = PunchActivityContractReceiptV1.self
    static let noPlanFallback = NoPlanFallbackV1.self
    static let usesExistingWriterRendererStoreAndPackageInfrastructure = true
    static let createsSecondRouteOrInspectionAlias = false
    static func validateReadable(_ value: ActivitySessionEnvelopeV2) throws { try value.validateForRead() }
}

enum ActivityWorkflowReleaseUseV2: String, Codable, CaseIterable, Hashable, Sendable {
    case start = "START"
    case export = "EXPORT"
    case read = "READ"
    case recovery = "RECOVERY"
}

enum BundledActivityWorkflowReleaseV2: Equatable, Sendable {
    case installation(InstallationWorkflowDefinitionReleaseV1)
    case punch(PunchReviewWorkflowDefinitionReleaseV1)

    var kind: ActivityKindV2 {
        switch self {
        case .installation: return .installation
        case .punch: return .punchReview
        }
    }

    var workspaceID: WorkspaceID {
        switch self {
        case let .installation(value): return value.workspaceID
        case let .punch(value): return value.workspaceID
        }
    }

    func validate() throws {
        switch self {
        case let .installation(value):
            try value.validate()
            guard value.bundledRelease == .installationV1 else {
                throw InspectionPackageFailureV2.incompatiblePackage
            }
        case let .punch(value):
            try value.validate()
            guard value.bundledRelease == .punchReviewV1 else {
                throw InspectionPackageFailureV2.incompatiblePackage
            }
        }
    }
}

struct BundledActivityWorkflowReleaseSelectionV2: Equatable, Sendable {
    let packageID: String
    let release: BundledActivityWorkflowReleaseV2

    func validate(registry: InspectionPackageRegistryV2) throws {
        _ = try registry.package(id: packageID)
        try release.validate()
    }
}

struct ActivityWorkflowReleasePublicationV2: Equatable, Sendable {
    let packageRegistryReceipt: InspectionPackageRegistryPublicationReceiptV2
    let selection: BundledActivityWorkflowReleaseSelectionV2

    init(registry: InspectionPackageRegistryV2,
         selection: BundledActivityWorkflowReleaseSelectionV2) throws {
        try selection.validate(registry: registry)
        let receipt = try registry.publicationReceipt(adoptedExisting: true)
        guard receipt.orderedPackageIDs.contains(selection.packageID),
              !receipt.persistentWriteOccurred else {
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        packageRegistryReceipt = receipt
        self.selection = selection
    }
}

extension InspectionPackageRegistryV2 {
    func bundledActivityWorkflowRelease(
        kind: ActivityKindV2,
        packageID: String,
        workspaceID: WorkspaceID
    ) throws -> BundledActivityWorkflowReleaseSelectionV2 {
        _ = try package(id: packageID)
        func uuid(_ value: String) throws -> UUID {
            guard let result = UUID(uuidString: value) else {
                throw InspectionPackageFailureV2.invalidValue
            }
            return result
        }
        let release: BundledActivityWorkflowReleaseV2
        switch kind {
        case .installation:
            release = .installation(try InstallationWorkflowDefinitionReleaseV1(
                releaseID: uuid("c4700000-0000-4000-8000-000000000101"),
                workspaceID: workspaceID,
                tasks: [
                    InstallationTaskDefinitionV1(
                        taskID: "identify-subject", ordinal: 0, title: "Confirm the selected subject",
                        evidencePurposes: [.subjectIdentity]
                    ),
                    InstallationTaskDefinitionV1(
                        taskID: "record-placement", ordinal: 1, title: "Record placement context",
                        evidencePurposes: [.placementContext]
                    ),
                    InstallationTaskDefinitionV1(
                        taskID: "record-as-built", ordinal: 2, title: "Record the as-built condition",
                        evidencePurposes: [.asBuiltOverview, .asBuiltDetail]
                    ),
                ],
                readinessPolicy: InstallationReadinessPolicyV1(
                    requiredFacets: [.subject, .site, .material, .equipment]
                ),
                revision: 1,
                mutationID: MutationIDV1(rawValue: uuid("c4700000-0000-4000-8000-000000000102"))
            ))
        case .punchReview:
            release = .punch(try PunchReviewWorkflowDefinitionReleaseV1(
                releaseID: uuid("c4700000-0000-4000-8000-000000000201"),
                workspaceID: workspaceID,
                scope: [
                    PunchReviewScopeItemV1(
                        scopeItemID: "review-recorded-scope", ordinal: 0,
                        title: "Review the recorded scope"
                    ),
                    PunchReviewScopeItemV1(
                        scopeItemID: "record-findings", ordinal: 1,
                        title: "Link any recorded findings"
                    ),
                ],
                readinessPolicy: PunchReviewReadinessPolicyV1(
                    requiredFacets: [.subject, .site]
                ),
                revision: 1,
                mutationID: MutationIDV1(rawValue: uuid("c4700000-0000-4000-8000-000000000202"))
            ))
        default:
            throw InspectionPackageFailureV2.incompatiblePackage
        }
        let selection = BundledActivityWorkflowReleaseSelectionV2(
            packageID: packageID, release: release
        )
        try selection.validate(registry: self)
        return selection
    }

}
