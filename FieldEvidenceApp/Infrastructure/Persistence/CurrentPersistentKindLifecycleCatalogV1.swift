import Foundation

enum CurrentPersistentKindLifecycleCatalogFailureV1: Error, Equatable, Sendable {
    case invalidCurrentCatalog
    case invalidDescriptor
    case invalidLifecyclePolicy
    case invalidDataHandlingPolicy
    case incompleteCoverage
}

/// Exact-head compiler for the durable lifecycle domain contract. The source
/// universe comes from the current schema/file/projection/journal declarations
/// already closed by `CurrentSyncClassificationCatalogV1`; no count is trusted.
struct CurrentPersistentKindLifecycleCatalogV1: Sendable {
    let descriptors: [PersistentKindDescriptorV1]
    let lifecyclePolicies: [PersistentLifecyclePolicyV1]
    let dataHandlingPolicies: [DataHandlingPolicyV1]
    let coverageManifest: LifecycleCoverageManifestV1

    static func compile(candidateHead: String) throws -> Self {
        try PersistentLifecycleContractReleaseRegistryV1.validate()
        try SurveyDefinitionPersistentKindPolicyV1.validateDeclaration()
        try SurveySessionPersistentKindPolicyV1.validateDeclaration()
        let compatibility = ReleasedDataCompatibilityPolicyV1.exactHead(
            candidateHead: candidateHead
        )
        try compatibility.validate()
        let source = try CurrentSyncClassificationCatalogV1.current
        try source.validate()
        let provenance = try temporalProvenance(for: source.registrations)
        let descriptors = try source.registrations.map { registration in
            guard let temporalEvidence = provenance[registration.subject.canonicalKey] else {
                throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
            }
            return try makeDescriptor(registration, temporalEvidence: temporalEvidence)
        }.sorted {
            $0.stableKindID < $1.stableKindID
        }
        try SurveyDefinitionPersistentKindPolicyV1.validate(descriptors)
        let descriptorIDs=Set(descriptors.map(\.stableKindID));guard SurveySessionPersistentKindPolicyV1.durableKindIDs.isSubset(of:descriptorIDs),SurveySessionPersistentKindPolicyV1.derivedKindIDs.isSubset(of:descriptorIDs)else{throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage}
        let routes = Dictionary(
            uniqueKeysWithValues: source.lifecycleRoutes.map {
                ($0.subject, $0)
            }
        )
        let lifecycle = try source.registrations.map { registration in
            guard let route = routes[registration.subject] else {
                throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidCurrentCatalog
            }
            return try makeLifecyclePolicy(registration, route: route)
        }.sorted { $0.kindID < $1.kindID }
        let handling = try source.registrations.map(makeDataHandlingPolicy).sorted {
            $0.kindID < $1.kindID
        }
        let manifest = try PersistentKindLifecycleRegistryV1.compileCoverage(
            candidateHead: candidateHead,
            sourceEvidence: try makeSourceEvidence(source, descriptors: descriptors),
            universe: source.registrations.map(\.subject),
            descriptors: descriptors,
            lifecyclePolicies: lifecycle,
            dataHandlingPolicies: handling
        )
        return try Self(
            descriptors: descriptors,
            lifecyclePolicies: lifecycle,
            dataHandlingPolicies: handling,
            coverageManifest: manifest
        )
    }

    init(
        descriptors: [PersistentKindDescriptorV1],
        lifecyclePolicies: [PersistentLifecyclePolicyV1],
        dataHandlingPolicies: [DataHandlingPolicyV1],
        coverageManifest: LifecycleCoverageManifestV1
    ) throws {
        self.descriptors = descriptors
        self.lifecyclePolicies = lifecyclePolicies
        self.dataHandlingPolicies = dataHandlingPolicies
        self.coverageManifest = coverageManifest
        try validate()
    }

    func descriptor(for subject: SyncSubjectIdentityV1) throws -> PersistentKindDescriptorV1 {
        let matches = descriptors.filter { $0.subject == subject }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidDescriptor
        }
        return value
    }

    func lifecyclePolicy(for subject: SyncSubjectIdentityV1) throws -> PersistentLifecyclePolicyV1 {
        let matches = lifecyclePolicies.filter { $0.kindID == subject.canonicalKey }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidLifecyclePolicy
        }
        return value
    }

    func dataHandlingPolicy(for subject: SyncSubjectIdentityV1) throws -> DataHandlingPolicyV1 {
        let matches = dataHandlingPolicies.filter { $0.kindID == subject.canonicalKey }
        guard matches.count == 1, let value = matches.first else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidDataHandlingPolicy
        }
        return value
    }

    func validate() throws {
        try coverageManifest.validate()
        try descriptors.forEach { try $0.validate() }
        try lifecyclePolicies.forEach { try $0.validate() }
        try dataHandlingPolicies.forEach { try $0.validate() }
        guard descriptors.map(\.stableKindID) == coverageManifest.universeKindIDs,
              lifecyclePolicies.map(\.kindID) == coverageManifest.universeKindIDs,
              dataHandlingPolicies.map(\.kindID) == coverageManifest.universeKindIDs,
              Set(descriptors.map(\.kindClassification))
                == Set(PersistentKindClassificationV1.allCases) else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
        }
    }

    static func expectedEraseDisposition(
        classification: PersistentKindClassificationV1,
        dataHandling: DataHandlingPolicyV1
    ) throws -> PersistentEraseObservedDispositionV1 {
        try PersistentKindLifecycleRegistryV1.expectedEraseDisposition(
            classification: classification,
            dataHandling: dataHandling
        )
    }

    func auditErase(
        observations: [PersistentEraseObservationV1]
    ) throws -> LifecycleEraseAuditReceiptV1 {
        let expectedIDs = Set(lifecyclePolicies.map(\.kindID))
        let observedIDs = observations.map(\.kindID)
        let observedSet = Set(observedIDs)
        var seen = Set<String>()
        let duplicates = Set(observedIDs.filter { !seen.insert($0).inserted })
        var mismatches = Set<String>()
        for observation in observations where expectedIDs.contains(observation.kindID) {
            guard let descriptor = descriptors.first(where: {
                $0.stableKindID == observation.kindID
            }), let handling = dataHandlingPolicies.first(where: {
                $0.kindID == observation.kindID
            }) else {
                throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidLifecyclePolicy
            }
            if observation.disposition != (try Self.expectedEraseDisposition(
                classification: descriptor.kindClassification,
                dataHandling: handling
            )) {
                mismatches.insert(observation.kindID)
            }
        }
        let receipt = LifecycleEraseAuditReceiptV1(
            schemaVersion: LifecycleEraseAuditReceiptV1.currentSchemaVersion,
            auditedKindIDs: expectedIDs.sorted(),
            missingKindIDs: expectedIDs.subtracting(observedSet).sorted(),
            duplicateKindIDs: duplicates.sorted(),
            unexpectedKindIDs: observedSet.subtracting(expectedIDs).sorted(),
            mismatchedKindIDs: mismatches.sorted()
        )
        try receipt.validate()
        return receipt
    }
}

private extension CurrentPersistentKindLifecycleCatalogV1 {
    static let implementationOwnerPrefix =
        "V23-P02-C09.CurrentPersistentKindLifecycleCatalogV1"

    static func makeSourceEvidence(
        _ source: CurrentSyncClassificationCatalogV1,
        descriptors: [PersistentKindDescriptorV1]
    ) throws -> [LifecycleUniverseSourceEvidenceV1] {
        let values: [(String, [String])] = [
            ("ACCEPTED_FIXTURE_DECLARATION", [
                "V23-P02-C09", PersistentKindLifecycleRegistryV1.schemaID,
            ]),
            ("ARCHIVE_EXPORT_REPORT_PACKAGE_EXCHANGE_REGISTRY",
             source.portableContentProjectionSubjects.map(\.canonicalKey)),
            ("JOURNAL_CHECKPOINT_PROJECTION_REGISTRY",
             (source.journalRecoverySubjects + source.derivedIndexProjectionSubjects)
                .map(\.canonicalKey)),
            ("OWNED_FILE_POLICY", source.ownedFileClassSubjects.map(\.canonicalKey)),
            ("PERSISTENT_SCHEMA", source.persistentModelSubjects.map(\.canonicalKey)),
            ("SYNC_CLASSIFICATION_CATALOG", source.registrations.map {
                $0.subject.canonicalKey
            }),
            ("TEMPORAL_PROVENANCE_REGISTRY",
             PersistentKindLifecycleRegistryV1.temporalProvenanceCanonicalMembers(
                for: descriptors
             )),
        ]
        return try values.map { sourceID, members in
            let canonical = try CompatibilityCanonicalV1.encode(members.sorted())
            return try LifecycleUniverseSourceEvidenceV1(
                sourceID: sourceID,
                canonicalDigest: CompatibilityCanonicalV1.sha256(canonical)
            )
        }.sorted { $0.sourceID < $1.sourceID }
    }

    struct TemporalOriginV1: Equatable, Sendable {
        let card: String
        let ordinal: Int
    }

    static let acceptedTemporalUniverseDigest =
        "be79c683750ab0b026e3eb3fa23ca4b4448c805151d76e90f4d1c1792bc00bcc"
    static let baselineTemporalOrigin = TemporalOriginV1(
        card: "PRE_V23_BASELINE", ordinal: 0
    )
    static let laterTemporalOrigins: [String: TemporalOriginV1] = {
        let c16 = TemporalOriginV1(card: "V23_P01_C03", ordinal: 16)
        let c17 = TemporalOriginV1(card: "V23_P01_C04", ordinal: 17)
        let c18 = TemporalOriginV1(card: "V23_P01_C05", ordinal: 18)
        let c19 = TemporalOriginV1(card: "V23_P01_C06", ordinal: 19)
        let c02 = TemporalOriginV1(card: "V23_P02_C02", ordinal: 22)
        let c04 = TemporalOriginV1(card: "V23_P02_C04", ordinal: 24)
        let c07 = TemporalOriginV1(card: "V23_P02_C07", ordinal: 27)
        let c08 = TemporalOriginV1(card: "V23_P02_C08", ordinal: 28)
        let c35 = TemporalOriginV1(card: "V23_P03_C35", ordinal: 41)
        let c42 = TemporalOriginV1(card: "V23_P03_C09", ordinal: 42)
        let c44 = TemporalOriginV1(card: "V23_P03_C12", ordinal: 44)
        let c46 = TemporalOriginV1(card: "V23_P03_C38", ordinal: 46)
        let c47 = TemporalOriginV1(card: "V23_P03_C39", ordinal: 47)
        let c48 = TemporalOriginV1(card: "V23_P03_C40", ordinal: 48)
        let c49 = TemporalOriginV1(card: "V23_P03_C41", ordinal: 49)
        let c50=TemporalOriginV1(card:"V23_P03_C13",ordinal:50)
        let c51=TemporalOriginV1(card:"V23_P03_C14",ordinal:51)
        let c52=TemporalOriginV1(card:"V23_P03_C15",ordinal:52)
        let c53=TemporalOriginV1(card:"V23_P03_C36",ordinal:53)
        let c55=TemporalOriginV1(card:"V23_P04_C18",ordinal:55)
        let c56=TemporalOriginV1(card:"V23_P03_C19",ordinal:56)
        let c57=TemporalOriginV1(card:"V23_P03_C20",ordinal:57)
        let c58=TemporalOriginV1(card:"V23_P03_C21",ordinal:58)
        let c59=TemporalOriginV1(card:"V23_P03_C22",ordinal:59)
        let c60=TemporalOriginV1(card:"V23_P03_C23",ordinal:60)
        let c61=TemporalOriginV1(card:"V23_P03_C24",ordinal:61)
        let c62=TemporalOriginV1(card:"V23_P03_C25",ordinal:62)
        let c63=TemporalOriginV1(card:"V23_P03_C26",ordinal:63)
        let groups: [(TemporalOriginV1, [String])] = [
            (c16, [
                "JOURNAL:CurrentGenerationPointerV2",
                "JOURNAL:PreparedMigrationEnvelopeV1",
                "JOURNAL:StoreGenerationManifestV1",
                "JOURNAL:StoreMigrationJournalV1",
                "JOURNAL:storeMigration",
                "PERSISTENT_MODEL:PersistentSchemaReleaseMarker",
            ]),
            (c17, [
                "PROJECTION:StreamingArchiveIndexV1",
            ]),
            (c18, [
                "JOURNAL:CurrentGenerationPointerV3",
            ]),
            (c19, [
                "PERSISTENT_MODEL:DeletionLedgerRow",
                "PROJECTION:DeletionLedgerV2",
                "PROJECTION:StoreSemanticEnvelopeV3",
            ]),
            (c02, [
                "JOURNAL:MutationEnvelopeV1",
                "JOURNAL:MutationHistoryQuarantineRecordV1",
                "JOURNAL:MutationReceiptV1",
                "JOURNAL:ReversalBasisV1",
                "JOURNAL:SemanticReversalReceiptV1",
                "JOURNAL:mutationReceipt",
                "PERSISTENT_MODEL:EntityMutationRevisionRow",
                "PERSISTENT_MODEL:MutationQuarantineRow",
                "PERSISTENT_MODEL:MutationReceiptRow",
                "PERSISTENT_MODEL:WorkspaceMutationStateRow",
                "PROJECTION:EntityMutationRevisionSemanticV1",
                "PROJECTION:MutationHistorySnapshotV1",
                "PROJECTION:MutationQuarantineSemanticV1",
                "PROJECTION:MutationReceiptSemanticV1",
                "PROJECTION:StoreSemanticEnvelopeV4",
                "PROJECTION:WorkspaceMutationStateSemanticV1",
                "PROJECTION:entityMutationRevision",
                "PROJECTION:workspaceMutationState",
            ]),
            (c04, [
                "OWNED_FILE_CLASS:generationLeaseControl",
                "OWNED_FILE_CLASS:generationLeaseControlTemporary",
                "OWNED_FILE_CLASS:generationLeaseDirectory",
                "OWNED_FILE_CLASS:generationLeaseOwnerLock",
            ]),
            (c07, [
                "PERSISTENT_MODEL:ObservationAndTimeRow",
                "PROJECTION:ObservationAndTimeMigrationReceiptV1",
                "PROJECTION:ObservationAndTimeSemanticV1",
                "PROJECTION:ObservationBasisV1",
                "PROJECTION:StoreSemanticEnvelopeV5",
                "PROJECTION:TemporalContextV1",
            ]),
            (c08, [
                "DIAGNOSTIC:DeviceOperationalSupportSnapshotV2",
                "DIAGNOSTIC:DeviceOperationalSupportStoreV1",
                "DIAGNOSTIC:DeviceOperationalSupportStoreV2",
                "DIAGNOSTIC:OperationalFailureV1",
                "DIAGNOSTIC:ScratchDataLeaseStoreV1",
                "DIAGNOSTIC:SystemHealthDiagnosticsV1",
                "OWNED_FILE_CLASS:scratch",
            ]),
            (c35, [
                "PERSISTENT_MODEL:AssetCompositionEdgeRow",
                "PERSISTENT_MODEL:AssetCompositionEventRow",
                "PERSISTENT_MODEL:AssetPlacementEventRow",
                "PERSISTENT_MODEL:LocationHierarchyEventRow",
                "PERSISTENT_MODEL:LocationMigrationReceiptRow",
                "PERSISTENT_MODEL:LocationNodeRow",
            ]),
            (c42, [
                "INDEX:SearchIndexProjectionV1",
                "OWNED_FILE_CLASS:searchIndex",
                "PERSISTENT_MODEL:SavedSmartView",
                "PROJECTION:SavedSmartViewDescriptorV1",
                "PROJECTION:StoreSemanticEnvelopeV7",
            ]),
            (c44, [
                "PERSISTENT_MODEL:RequirementAssuranceRow",
                "PROJECTION:RequirementAssuranceSnapshotV1",
                "PROJECTION:RequirementEvaluationV1",
                "PROJECTION:CompletionDecisionV1",
                "PROJECTION:IntegrityFindingV1",
                "PROJECTION:StoreSemanticEnvelopeV8",
            ]),
            (c46, [
                "PERSISTENT_MODEL:ServicePartyRow",
                "PERSISTENT_MODEL:SitePartyRoleEventRow",
                "PERSISTENT_MODEL:ActorSnapshotRow",
                "PERSISTENT_MODEL:QualificationSnapshotRow",
                "PERSISTENT_MODEL:SignoffSnapshotRow",
                "PROJECTION:ServicePartyReferenceV1",
                "PROJECTION:SitePartyRoleEventV1",
                "PROJECTION:ActorSnapshotV1",
                "PROJECTION:QualificationSnapshotV1",
                "PROJECTION:SignoffSnapshotV1",
                "PROJECTION:StoreSemanticEnvelopeV9",
            ]),
            (c47, [
                "PERSISTENT_MODEL:AssetKindBindingEventRow",
                "PERSISTENT_MODEL:AssetWorkflowCapabilityBindingEventRow",
                "PERSISTENT_MODEL:AssetProductIdentityRow",
                "PERSISTENT_MODEL:AssetLifecycleEventRow",
                "PERSISTENT_MODEL:AssetSuccessorLinkRow",
                "PERSISTENT_MODEL:WorkSubjectScopeSnapshotRow",
                "PROJECTION:AssetSemanticCatalogReleaseV1",
                "PROJECTION:AssetKindDefinitionV1",
                "PROJECTION:AssetKindBindingEventV1",
                "PROJECTION:AssetWorkflowCapabilityBindingEventV1",
                "PROJECTION:AssetProductIdentityV1",
                "PROJECTION:AssetLifecycleEventV1",
                "PROJECTION:AssetSuccessorLinkV1",
                "PROJECTION:WorkSubjectScopeSnapshotV1",
                "PROJECTION:StoreSemanticEnvelopeV10",
            ]),
            (c48, [
                "PERSISTENT_MODEL:AuthoritySourceReleaseRow",
                "PERSISTENT_MODEL:RequirementBasisBindingRow",
                "PERSISTENT_MODEL:ApplicabilityContextSnapshotRow",
                "PERSISTENT_MODEL:AssessmentScopeSnapshotRow",
                "PERSISTENT_MODEL:SeverityScaleReleaseRow",
                "PERSISTENT_MODEL:FindingClassificationBindingRow",
                "PERSISTENT_MODEL:MeasurementProtocolReleaseRow",
                "PERSISTENT_MODEL:DerivedFactEvaluatorDescriptorRow",
                "PERSISTENT_MODEL:DerivedFactProvenanceRow",
                "PROJECTION:AuthoritySourceReleaseV1",
                "PROJECTION:RequirementBasisBindingV1",
                "PROJECTION:ApplicabilityContextSnapshotV1",
                "PROJECTION:AssessmentScopeSnapshotV1",
                "PROJECTION:SeverityScaleReleaseV1",
                "PROJECTION:FindingClassificationBindingV1",
                "PROJECTION:MeasurementProtocolReleaseV1",
                "PROJECTION:DerivedFactEvaluatorDescriptorV1",
                "PROJECTION:DerivedFactProvenanceV1",
                "PROJECTION:StoreSemanticEnvelopeV11",
            ]),
            (c49, [
                "PERSISTENT_MODEL:FunctionalRelationshipTypeDescriptorRow",
                "PERSISTENT_MODEL:AssetFunctionalRelationshipEventRow",
                "PROJECTION:FunctionalRelationshipTypeDescriptorV1",
                "PROJECTION:AssetFunctionalRelationshipEventV1",
                "PROJECTION:CurrentFunctionalRelationshipProjectionV1",
                "PROJECTION:FunctionalRelationshipDispositionPreviewV1",
                "PROJECTION:CompletedFunctionalRelationshipSnapshotV1",
                "PROJECTION:StoreSemanticEnvelopeV12",
            ]),
            (c50,["PERSISTENT_MODEL:EvidenceVisibilityRow","PERSISTENT_MODEL:ClaimEvidenceLinkRow","PERSISTENT_MODEL:AssuranceManifestRow","PERSISTENT_MODEL:AttestationRow","PROJECTION:EvidenceVisibilityV1","PROJECTION:ClaimEvidenceLinkV1","PROJECTION:AssuranceProjectionPreviewV1","PROJECTION:AssuranceManifestV1","PROJECTION:AttestationV1","PROJECTION:StoreSemanticEnvelopeV13"]),
            (c51,["PERSISTENT_MODEL:InspectionReviewTransitionRow","PERSISTENT_MODEL:ReviewDispositionRow","PERSISTENT_MODEL:ChangeRequestRow","PERSISTENT_MODEL:CorrectiveActionPolicyRow","PERSISTENT_MODEL:CorrectiveActionEventRow","PROJECTION:InspectionReviewTransitionV1","PROJECTION:ReviewDispositionV1","PROJECTION:ChangeRequestV1","PROJECTION:CorrectiveActionPolicyV1","PROJECTION:CorrectiveActionEventV1","PROJECTION:InspectionReviewProjectionV1","PROJECTION:CorrectiveActionProjectionV1","PROJECTION:StoreSemanticEnvelopeV14"]),
            (c52,["PERSISTENT_MODEL:WorkPacketManifestRow","PERSISTENT_MODEL:WorkItemClaimRow","PERSISTENT_MODEL:WorkLeaseRow","PERSISTENT_MODEL:WorkReleaseRow","PERSISTENT_MODEL:WorkHandoffRow","PROJECTION:WorkPacketManifestV1","PROJECTION:WorkItemClaimV1","PROJECTION:WorkLeaseV1","PROJECTION:WorkReleaseV1","PROJECTION:WorkHandoffV1","PROJECTION:WorkPacketProjectionV1","PROJECTION:StoreSemanticEnvelopeV15"]),
            (c53,["PERSISTENT_MODEL:FieldDraftCheckpointRow","PERSISTENT_MODEL:AttachmentStagingItemRow","PERSISTENT_MODEL:DraftCommitSagaRow","PERSISTENT_MODEL:DraftContentReservationRow","PERSISTENT_MODEL:DraftCommitReceiptRow","PERSISTENT_MODEL:DraftDiscardReceiptRow","PROJECTION:FieldDraftCheckpointV1","PROJECTION:AttachmentStagingItemV1","PROJECTION:DraftCommitSagaV1","PROJECTION:DraftContentReservationV1","PROJECTION:DraftCommitReceiptV1","PROJECTION:DraftDiscardReceiptV1","PROJECTION:DraftRecoveryProjectionV1","PROJECTION:StoreSemanticEnvelopeV16"]),
            (c55,["PERSISTENT_MODEL:PromotedPackageReleaseRow","PERSISTENT_MODEL:PackageSandboxRunRow","PERSISTENT_MODEL:PackagePromotionReceiptRow","PERSISTENT_MODEL:ActivePackageRegistryPointerRow","PROJECTION:PromotedPackageReleaseV1","PROJECTION:PackageSandboxRunV1","PROJECTION:PackagePromotionReceiptV1","PROJECTION:ActivePackageRegistryPointerV1","PROJECTION:PackageEvolutionLifecycleClosureV1","PROJECTION:PackageSemanticDiffV1","PROJECTION:DraftUpgradePlanV1","PROJECTION:StoreSemanticEnvelopeV17"]),
            (c56,["PERSISTENT_MODEL:InstrumentReferenceRow","PERSISTENT_MODEL:CalibrationStatusSnapshotRow","PERSISTENT_MODEL:MeasurementCaptureRow","PERSISTENT_MODEL:MeasurementSeriesRow","PERSISTENT_MODEL:MeasurementQualityAssessmentRow","PROJECTION:InstrumentReferenceV1","PROJECTION:CalibrationStatusSnapshotV1","PROJECTION:MeasurementCaptureV1","PROJECTION:MeasurementSeriesV1","PROJECTION:MeasurementQualityAssessmentV1","PROJECTION:StoreSemanticEnvelopeV18"]),
            (c57,["PERSISTENT_MODEL:PrivacyTransformPolicyRow","PERSISTENT_MODEL:PrivacyRegionRow","PERSISTENT_MODEL:PrivacyTransformManifestRow","PERSISTENT_MODEL:PrivacyReviewReceiptRow","PROJECTION:PrivacyTransformPolicyV1","PROJECTION:PrivacyRegionV1","PROJECTION:PrivacyTransformManifestV1","PROJECTION:PrivacyReviewReceiptV1","PROJECTION:PrivacyProjectionV1","PROJECTION:PrivacyTransformLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV19"]),
            (c58,["PERSISTENT_MODEL:ClientCapabilityProfileRow","PERSISTENT_MODEL:ClientCapabilityAdmissionDecisionRow","PERSISTENT_MODEL:PackageLifecyclePolicyRow","PERSISTENT_MODEL:PackageLifecycleDispositionRow","PROJECTION:ClientCapabilityProfileV1","PROJECTION:ClientCapabilityAdmissionDecisionV1","PROJECTION:PackageLifecyclePolicyV1","PROJECTION:PackageLifecycleDispositionV1","PROJECTION:ClientCapabilityAdmissionEvaluatorV1","PROJECTION:ClientCapabilityLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV20"]),
            (c59,["PERSISTENT_MODEL:RecoverabilityVerificationReceiptRow","PROJECTION:RecoverabilityVerificationReceiptV1","PROJECTION:RecoverabilityVerificationStagingV1","PROJECTION:RecoverabilityFreshnessProjectionV1","PROJECTION:RecoverabilityVerificationLifecycleV1","PROJECTION:StoreSemanticEnvelopeV21"]),
            (c60,["PERSISTENT_MODEL:FieldReferenceReleaseRow","PERSISTENT_MODEL:FieldReferenceBindingRow","PROJECTION:FieldReferenceReleaseV1","PROJECTION:FieldReferenceBindingV1","PROJECTION:FieldReferenceOfflineReadinessV1","PROJECTION:FieldReferencePackLifecycleV1","PROJECTION:StoreSemanticEnvelopeV22"]),
            (c61,["PERSISTENT_MODEL:AccessibleDocumentAssessmentReceiptRow","PROJECTION:AccessibleDocumentAssessmentReceiptV1","PROJECTION:AccessibleDocumentSemanticTreeV1","PROJECTION:AccessibleDocumentLifecycleV1","PROJECTION:StoreSemanticEnvelopeV23"]),
            (c62,["PERSISTENT_MODEL:SurveyDefinitionIdentityRow","PERSISTENT_MODEL:SurveyDefinitionReleaseRow","JOURNAL:SurveyDefinitionLifecycleEventV1","PROJECTION:SurveyDefinitionIdentityV1","PROJECTION:SurveyDefinitionReleaseV1","PROJECTION:SurveyDefinitionSemanticDiffV1","PROJECTION:SurveyDefinitionAdoptionPreviewV1","PROJECTION:SurveyTemplateQuarantineAssessmentV1","PROJECTION:StoreSemanticEnvelopeV24"]),
            (c63,["PERSISTENT_MODEL:SurveySessionRow","PERSISTENT_MODEL:FactCaptureRow","PERSISTENT_MODEL:ProvisionalSubjectRow","PERSISTENT_MODEL:SubjectPromotionReceiptRow","PERSISTENT_MODEL:SurveyPublicationSnapshotRow","PROJECTION:SurveySessionV1","PROJECTION:FactCaptureV1","PROJECTION:ProvisionalSubjectV1","PROJECTION:SubjectPromotionReceiptV1","PROJECTION:SurveyPublicationSnapshotV1","PROJECTION:SurveySessionLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV25"]),
        ]
        return groups.reduce(into: [:]) { result, group in
            for kindID in group.1 {
                result[kindID] = group.0
            }
        }
    }()

    static func temporalProvenance(
        for registrations: [SyncClassificationRegistrationV1]
    ) throws -> [String: PersistentKindTemporalEvidenceV1] {
        let kindIDs = registrations.map { $0.subject.canonicalKey }.sorted()
        let c09KindIDs = Set([
            "INDEX:SearchIndexProjectionV1",
            "OWNED_FILE_CLASS:searchIndex",
            "PERSISTENT_MODEL:SavedSmartView",
            "PROJECTION:SavedSmartViewDescriptorV1",
            "PROJECTION:StoreSemanticEnvelopeV7",
        ])
        let c12KindIDs = Set([
            "PERSISTENT_MODEL:RequirementAssuranceRow",
            "PROJECTION:RequirementAssuranceSnapshotV1",
            "PROJECTION:RequirementEvaluationV1",
            "PROJECTION:CompletionDecisionV1",
            "PROJECTION:IntegrityFindingV1",
            "PROJECTION:StoreSemanticEnvelopeV8",
        ])
        let c38KindIDs = Set([
            "PERSISTENT_MODEL:ServicePartyRow", "PERSISTENT_MODEL:SitePartyRoleEventRow",
            "PERSISTENT_MODEL:ActorSnapshotRow", "PERSISTENT_MODEL:QualificationSnapshotRow",
            "PERSISTENT_MODEL:SignoffSnapshotRow", "PROJECTION:ServicePartyReferenceV1",
            "PROJECTION:SitePartyRoleEventV1", "PROJECTION:ActorSnapshotV1",
            "PROJECTION:QualificationSnapshotV1", "PROJECTION:SignoffSnapshotV1",
            "PROJECTION:StoreSemanticEnvelopeV9",
        ])
        let c39KindIDs = Set([
            "PERSISTENT_MODEL:AssetKindBindingEventRow",
            "PERSISTENT_MODEL:AssetWorkflowCapabilityBindingEventRow",
            "PERSISTENT_MODEL:AssetProductIdentityRow",
            "PERSISTENT_MODEL:AssetLifecycleEventRow",
            "PERSISTENT_MODEL:AssetSuccessorLinkRow",
            "PERSISTENT_MODEL:WorkSubjectScopeSnapshotRow",
            "PROJECTION:AssetSemanticCatalogReleaseV1", "PROJECTION:AssetKindDefinitionV1",
            "PROJECTION:AssetKindBindingEventV1", "PROJECTION:AssetWorkflowCapabilityBindingEventV1",
            "PROJECTION:AssetProductIdentityV1", "PROJECTION:AssetLifecycleEventV1",
            "PROJECTION:AssetSuccessorLinkV1", "PROJECTION:WorkSubjectScopeSnapshotV1",
            "PROJECTION:StoreSemanticEnvelopeV10",
        ])
        let c40KindIDs = Set([
            "PERSISTENT_MODEL:AuthoritySourceReleaseRow",
            "PERSISTENT_MODEL:RequirementBasisBindingRow",
            "PERSISTENT_MODEL:ApplicabilityContextSnapshotRow",
            "PERSISTENT_MODEL:AssessmentScopeSnapshotRow",
            "PERSISTENT_MODEL:SeverityScaleReleaseRow",
            "PERSISTENT_MODEL:FindingClassificationBindingRow",
            "PERSISTENT_MODEL:MeasurementProtocolReleaseRow",
            "PERSISTENT_MODEL:DerivedFactEvaluatorDescriptorRow",
            "PERSISTENT_MODEL:DerivedFactProvenanceRow",
            "PROJECTION:AuthoritySourceReleaseV1", "PROJECTION:RequirementBasisBindingV1",
            "PROJECTION:ApplicabilityContextSnapshotV1", "PROJECTION:AssessmentScopeSnapshotV1",
            "PROJECTION:SeverityScaleReleaseV1", "PROJECTION:FindingClassificationBindingV1",
            "PROJECTION:MeasurementProtocolReleaseV1", "PROJECTION:DerivedFactEvaluatorDescriptorV1",
            "PROJECTION:DerivedFactProvenanceV1", "PROJECTION:StoreSemanticEnvelopeV11",
        ])
        let c41KindIDs = Set([
            "PERSISTENT_MODEL:FunctionalRelationshipTypeDescriptorRow",
            "PERSISTENT_MODEL:AssetFunctionalRelationshipEventRow",
            "PROJECTION:FunctionalRelationshipTypeDescriptorV1",
            "PROJECTION:AssetFunctionalRelationshipEventV1",
            "PROJECTION:CurrentFunctionalRelationshipProjectionV1",
            "PROJECTION:FunctionalRelationshipDispositionPreviewV1",
            "PROJECTION:CompletedFunctionalRelationshipSnapshotV1",
            "PROJECTION:StoreSemanticEnvelopeV12",
        ])
        let c13KindIDs=Set(["PERSISTENT_MODEL:EvidenceVisibilityRow","PERSISTENT_MODEL:ClaimEvidenceLinkRow","PERSISTENT_MODEL:AssuranceManifestRow","PERSISTENT_MODEL:AttestationRow","PROJECTION:EvidenceVisibilityV1","PROJECTION:ClaimEvidenceLinkV1","PROJECTION:AssuranceProjectionPreviewV1","PROJECTION:AssuranceManifestV1","PROJECTION:AttestationV1","PROJECTION:StoreSemanticEnvelopeV13"])
        let c14KindIDs=Set(["PERSISTENT_MODEL:InspectionReviewTransitionRow","PERSISTENT_MODEL:ReviewDispositionRow","PERSISTENT_MODEL:ChangeRequestRow","PERSISTENT_MODEL:CorrectiveActionPolicyRow","PERSISTENT_MODEL:CorrectiveActionEventRow","PROJECTION:InspectionReviewTransitionV1","PROJECTION:ReviewDispositionV1","PROJECTION:ChangeRequestV1","PROJECTION:CorrectiveActionPolicyV1","PROJECTION:CorrectiveActionEventV1","PROJECTION:InspectionReviewProjectionV1","PROJECTION:CorrectiveActionProjectionV1","PROJECTION:StoreSemanticEnvelopeV14"])
        let c15KindIDs=Set(["PERSISTENT_MODEL:WorkPacketManifestRow","PERSISTENT_MODEL:WorkItemClaimRow","PERSISTENT_MODEL:WorkLeaseRow","PERSISTENT_MODEL:WorkReleaseRow","PERSISTENT_MODEL:WorkHandoffRow","PROJECTION:WorkPacketManifestV1","PROJECTION:WorkItemClaimV1","PROJECTION:WorkLeaseV1","PROJECTION:WorkReleaseV1","PROJECTION:WorkHandoffV1","PROJECTION:WorkPacketProjectionV1","PROJECTION:StoreSemanticEnvelopeV15"])
        let c36KindIDs=Set(["PERSISTENT_MODEL:FieldDraftCheckpointRow","PERSISTENT_MODEL:AttachmentStagingItemRow","PERSISTENT_MODEL:DraftCommitSagaRow","PERSISTENT_MODEL:DraftContentReservationRow","PERSISTENT_MODEL:DraftCommitReceiptRow","PERSISTENT_MODEL:DraftDiscardReceiptRow","PROJECTION:FieldDraftCheckpointV1","PROJECTION:AttachmentStagingItemV1","PROJECTION:DraftCommitSagaV1","PROJECTION:DraftContentReservationV1","PROJECTION:DraftCommitReceiptV1","PROJECTION:DraftDiscardReceiptV1","PROJECTION:DraftRecoveryProjectionV1","PROJECTION:StoreSemanticEnvelopeV16"])
        let c18KindIDs=Set(["PERSISTENT_MODEL:PromotedPackageReleaseRow","PERSISTENT_MODEL:PackageSandboxRunRow","PERSISTENT_MODEL:PackagePromotionReceiptRow","PERSISTENT_MODEL:ActivePackageRegistryPointerRow","PROJECTION:PromotedPackageReleaseV1","PROJECTION:PackageSandboxRunV1","PROJECTION:PackagePromotionReceiptV1","PROJECTION:ActivePackageRegistryPointerV1","PROJECTION:PackageEvolutionLifecycleClosureV1","PROJECTION:PackageSemanticDiffV1","PROJECTION:DraftUpgradePlanV1","PROJECTION:StoreSemanticEnvelopeV17"])
        let c19KindIDs=Set(["PERSISTENT_MODEL:InstrumentReferenceRow","PERSISTENT_MODEL:CalibrationStatusSnapshotRow","PERSISTENT_MODEL:MeasurementCaptureRow","PERSISTENT_MODEL:MeasurementSeriesRow","PERSISTENT_MODEL:MeasurementQualityAssessmentRow","PROJECTION:InstrumentReferenceV1","PROJECTION:CalibrationStatusSnapshotV1","PROJECTION:MeasurementCaptureV1","PROJECTION:MeasurementSeriesV1","PROJECTION:MeasurementQualityAssessmentV1","PROJECTION:StoreSemanticEnvelopeV18"])
        let c20KindIDs=Set(["PERSISTENT_MODEL:PrivacyTransformPolicyRow","PERSISTENT_MODEL:PrivacyRegionRow","PERSISTENT_MODEL:PrivacyTransformManifestRow","PERSISTENT_MODEL:PrivacyReviewReceiptRow","PROJECTION:PrivacyTransformPolicyV1","PROJECTION:PrivacyRegionV1","PROJECTION:PrivacyTransformManifestV1","PROJECTION:PrivacyReviewReceiptV1","PROJECTION:PrivacyProjectionV1","PROJECTION:PrivacyTransformLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV19"])
        let c21KindIDs=Set(["PERSISTENT_MODEL:ClientCapabilityProfileRow","PERSISTENT_MODEL:ClientCapabilityAdmissionDecisionRow","PERSISTENT_MODEL:PackageLifecyclePolicyRow","PERSISTENT_MODEL:PackageLifecycleDispositionRow","PROJECTION:ClientCapabilityProfileV1","PROJECTION:ClientCapabilityAdmissionDecisionV1","PROJECTION:PackageLifecyclePolicyV1","PROJECTION:PackageLifecycleDispositionV1","PROJECTION:ClientCapabilityAdmissionEvaluatorV1","PROJECTION:ClientCapabilityLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV20"])
        let c22KindIDs=Set(["PERSISTENT_MODEL:RecoverabilityVerificationReceiptRow","PROJECTION:RecoverabilityVerificationReceiptV1","PROJECTION:RecoverabilityVerificationStagingV1","PROJECTION:RecoverabilityFreshnessProjectionV1","PROJECTION:RecoverabilityVerificationLifecycleV1","PROJECTION:StoreSemanticEnvelopeV21"])
        let c23KindIDs=Set(["PERSISTENT_MODEL:FieldReferenceReleaseRow","PERSISTENT_MODEL:FieldReferenceBindingRow","PROJECTION:FieldReferenceReleaseV1","PROJECTION:FieldReferenceBindingV1","PROJECTION:FieldReferenceOfflineReadinessV1","PROJECTION:FieldReferencePackLifecycleV1","PROJECTION:StoreSemanticEnvelopeV22"])
        let c24KindIDs=Set(["PERSISTENT_MODEL:AccessibleDocumentAssessmentReceiptRow","PROJECTION:AccessibleDocumentAssessmentReceiptV1","PROJECTION:AccessibleDocumentSemanticTreeV1","PROJECTION:AccessibleDocumentLifecycleV1","PROJECTION:StoreSemanticEnvelopeV23"])
        let c25KindIDs=Set(["PERSISTENT_MODEL:SurveyDefinitionIdentityRow","PERSISTENT_MODEL:SurveyDefinitionReleaseRow","JOURNAL:SurveyDefinitionLifecycleEventV1","PROJECTION:SurveyDefinitionIdentityV1","PROJECTION:SurveyDefinitionReleaseV1","PROJECTION:SurveyDefinitionSemanticDiffV1","PROJECTION:SurveyDefinitionAdoptionPreviewV1","PROJECTION:SurveyTemplateQuarantineAssessmentV1","PROJECTION:StoreSemanticEnvelopeV24"])
        let c26KindIDs=Set(["PERSISTENT_MODEL:SurveySessionRow","PERSISTENT_MODEL:FactCaptureRow","PERSISTENT_MODEL:ProvisionalSubjectRow","PERSISTENT_MODEL:SubjectPromotionReceiptRow","PERSISTENT_MODEL:SurveyPublicationSnapshotRow","PROJECTION:SurveySessionV1","PROJECTION:FactCaptureV1","PROJECTION:ProvisionalSubjectV1","PROJECTION:SubjectPromotionReceiptV1","PROJECTION:SurveyPublicationSnapshotV1","PROJECTION:SurveySessionLifecycleClosureV1","PROJECTION:StoreSemanticEnvelopeV25"])
        let c17KindIDs = Set([
            "PROJECTION:IntegrationConformanceConsumerV1",
            "PROJECTION:IntegrationContractRegistryV1",
            "PROJECTION:IntegrationEventProjectionV1",
            "PROJECTION:IntegrationEventV1",
            "PROJECTION:IntegrationProjectionCheckpointStoreV1",
            "PROJECTION:ProjectionCheckpointV1",
        ])
        guard kindIDs.count == 311,
              Set(kindIDs).count == kindIDs.count,
              laterTemporalOrigins.count == 249,
              c09KindIDs.isSubset(of: Set(kindIDs)),
              c12KindIDs.isSubset(of: Set(kindIDs)),
              c38KindIDs.isSubset(of: Set(kindIDs)),
              c39KindIDs.isSubset(of: Set(kindIDs)),
              c40KindIDs.isSubset(of: Set(kindIDs)),
              c41KindIDs.isSubset(of: Set(kindIDs)),
              c13KindIDs.isSubset(of:Set(kindIDs)),
              c14KindIDs.isSubset(of:Set(kindIDs)),
              c15KindIDs.isSubset(of:Set(kindIDs)),
              c36KindIDs.isSubset(of:Set(kindIDs)),
              c17KindIDs.isSubset(of: Set(kindIDs)),
              c18KindIDs.isSubset(of: Set(kindIDs)),
              c19KindIDs.isSubset(of: Set(kindIDs)),
              c20KindIDs.isSubset(of:Set(kindIDs)),
              c21KindIDs.isSubset(of:Set(kindIDs)),
              c22KindIDs.isSubset(of:Set(kindIDs)),
              c23KindIDs.isSubset(of:Set(kindIDs)),
              c24KindIDs.isSubset(of:Set(kindIDs)),
              c25KindIDs.isSubset(of:Set(kindIDs)),
              c26KindIDs.isSubset(of:Set(kindIDs)),
              Set(laterTemporalOrigins.keys).isSubset(of: Set(kindIDs)) else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
        }
        let durableKindIDs = Set(registrations.compactMap { registration in
            PersistentKindLifecycleRegistryV1.hasIndependentRepresentationWrite(
                registration.subject
            ) ? registration.subject.canonicalKey : nil
        })
        guard durableKindIDs.count == 150 else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
        }
        let universeBytes = try CompatibilityCanonicalV1.encode(
            kindIDs.filter {
                !c09KindIDs.contains($0) && !c12KindIDs.contains($0)
                    && !c38KindIDs.contains($0) && !c39KindIDs.contains($0)
                    && !c40KindIDs.contains($0)
                    && !c41KindIDs.contains($0)
                    && !c13KindIDs.contains($0)
                    && !c14KindIDs.contains($0)
                    && !c15KindIDs.contains($0)
                    && !c36KindIDs.contains($0)
                    && !c17KindIDs.contains($0)
                    && !c18KindIDs.contains($0)
                    && !c19KindIDs.contains($0)
                    && !c20KindIDs.contains($0)
                    && !c21KindIDs.contains($0)
                    && !c22KindIDs.contains($0)
                    && !c23KindIDs.contains($0)
                    && !c24KindIDs.contains($0)
                    && !c25KindIDs.contains($0)
                    && !c26KindIDs.contains($0)
            }
        )
        guard CompatibilityCanonicalV1.sha256(universeBytes)
                == acceptedTemporalUniverseDigest else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
        }
        let pairs = try registrations.map { registration in
            let kindID = registration.subject.canonicalKey
            let origin = laterTemporalOrigins[kindID] ?? baselineTemporalOrigin
            let hasDurableWrite = durableKindIDs.contains(kindID)
            let enrolledWithDeclaration = hasDurableWrite && origin.ordinal > 29
            let notApplicable = PersistentKindTemporalEvidenceV1.notApplicable
            let evidence = try PersistentKindTemporalEvidenceV1(
                evidenceID: "temporal." + kindID,
                evidenceVersion: 1,
                disposition: enrolledWithDeclaration
                    ? .enrolledBeforeFirstWrite
                    : (hasDurableWrite
                        ? .preexistingBoundForwardFix : .nonpersistentNoCanonicalWrite),
                representationSourceCard: origin.card,
                representationSourceOrdinal: origin.ordinal,
                firstWriteVersion: hasDurableWrite ? origin.card : notApplicable,
                lifecycleEnrollmentVersion: enrolledWithDeclaration
                    ? origin.card : "V23_P02_C09",
                forwardFixVersion: hasDurableWrite && !enrolledWithDeclaration
                    ? "V23_P02_C09" : notApplicable,
                firstWriteOrdinal: hasDurableWrite ? origin.ordinal : 0,
                lifecycleEnrollmentOrdinal: enrolledWithDeclaration ? origin.ordinal : 29,
                forwardFixOrdinal: hasDurableWrite && !enrolledWithDeclaration ? 29 : 0
            )
            return (kindID, evidence)
        }
        var result: [String: PersistentKindTemporalEvidenceV1] = [:]
        for pair in pairs {
            guard result.updateValue(pair.1, forKey: pair.0) == nil else {
                throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
            }
        }
        guard result.count == kindIDs.count else {
            throw CurrentPersistentKindLifecycleCatalogFailureV1.incompleteCoverage
        }
        return result
    }

    static func storageDisposition(
        _ registration: SyncClassificationRegistrationV1
    ) -> PersistentKindStorageDispositionV1 {
        switch registration.replicationPolicy.persistence {
        case .swiftDataRecord:
            return .swiftDataModel
        case .ownedFile:
            return registration.subject.category == .journal
                ? .recoveryJournal : .ownedFile
        case .nonpersistent:
            if registration.subject.category == .projection,
               registration.replicationPolicy.export != .exclude {
                return .portableWireProjection
            }
            if registration.subject.category == .projection
                || registration.subject.category == .index {
                return .derivedProjection
            }
            return .nonpersistentDeclaration
        }
    }

    static func makeDescriptor(
        _ registration: SyncClassificationRegistrationV1,
        temporalEvidence: PersistentKindTemporalEvidenceV1
    ) throws -> PersistentKindDescriptorV1 {
        let policy = registration.replicationPolicy
        let storage = storageDisposition(registration)

        let revision: PersistentKindRevisionDispositionV1
        let mutation: PersistentKindMutationDispositionV1
        let digest: PersistentKindDigestDispositionV1
        switch registration.classification {
        case .replicated:
            revision = policy.bootstrap == .immutableHistory
                ? .appendOnlyImmutable : .exactRevision
            mutation = .workspaceWriter
            digest = .canonicalDigestRequired
        case .contentBlob:
            revision = .immutableContent
            mutation = .immutableContentWriter
            digest = .immutableContentDigestRequired
        case .derivedRebuildable:
            revision = .derivedFromCanonicalInputs
            mutation = .derivedOnly
            digest = .rebuildFromDependencies
        case .localOnly:
            revision = policy.retention == .operationScoped
                ? .operationScoped : .destinationLocal
            mutation = .localDeviceOwner
            digest = .notApplicable
        case .privateDeviceOnly:
            revision = .destinationLocal
            mutation = .localDeviceOwner
            digest = .notApplicable
        }
        let kindClassification = kindClassification(registration)
        return try PersistentKindDescriptorV1(
            subject: registration.subject,
            storage: storage,
            revision: revision,
            mutation: mutation,
            digest: digest,
            kindClassification: kindClassification,
            replicationClassification: registration.classification,
            temporalEvidence: temporalEvidence,
            declarationOwner: PersistentKindLifecycleRegistryV1.declarationOwner,
            currentImplementationOwner: implementationOwnerPrefix
                + "." + registration.subject.category.rawValue
        )
    }

    static func kindClassification(
        _ registration: SyncClassificationRegistrationV1
    ) -> PersistentKindClassificationV1 {
        if registration.subject.category == .persistentModel,
           registration.subject.stableName == "PersistentSchemaReleaseMarker" {
            return .declaration
        }
        if registration.subject.category == .projection {
            switch registration.subject.stableName {
            case "ReportSnapshotV1":
                return .immutable
            case "entityMutationRevision", "workspaceMutationState":
                return .canonical
            default:
                break
            }
        }
        if registration.subject.category == .projection,
           registration.replicationPolicy.export != .exclude {
            return .wire
        }
        if registration.classification == .derivedRebuildable {
            return .derived
        }
        if registration.replicationPolicy.persistence == .nonpersistent {
            return .nonpersistent
        }
        if registration.subject.category == .journal {
            return .canonical
        }
        if registration.subject.category == .diagnostic {
            return registration.subject.stableName == "DeviceOperationalSupportStoreV2"
                ? .canonical : .nonpersistent
        }
        if registration.subject.category == .ownedFileClass,
           let kind = OwnedFileKindV1(rawValue: registration.subject.stableName) {
            switch kind {
            case .database, .databaseWAL, .databaseSHM, .durableDirectory,
                    .generationPointer, .generationLeaseDirectory:
                return .declaration
            case .journal, .diagnostics, .generationLeaseControl:
                return .canonical
            case .reportSnapshot, .reportPDF:
                return .immutable
            case .stagingDirectory, .restoreStaging, .stagingFile, .temporaryFile,
                    .generationPointerTemporary, .generationLeaseControlTemporary,
                    .generationLeaseOwnerLock, .journalTemporary, .cache, .scratch:
                return .nonpersistent
            default:
                break
            }
        }
        switch registration.classification {
        case .contentBlob: return .content
        case .derivedRebuildable: return .derived
        case .replicated:
            switch registration.conflictPolicy.rule {
            case .deleteWins, .stableIDAppendUnion, .immutableVersion: return .immutable
            default: return .canonical
            }
        case .localOnly, .privateDeviceOnly: return .declaration
        }
    }

    static func makeLifecyclePolicy(
        _ registration: SyncClassificationRegistrationV1,
        route: CurrentSyncLifecycleRouteV1
    ) throws -> PersistentLifecyclePolicyV1 {
        let isPortable = registration.replicationPolicy.export != .exclude
        let persistentClassification = kindClassification(registration)
        let isDerived = persistentClassification == .derived
        let isUserVisibleHistoricOutput = [
            "ReportSnapshotV1", "reportPDF", "reportSnapshot",
        ].contains(registration.subject.stableName)
        let hasNoCanonicalWrite = persistentClassification == .wire
            || persistentClassification == .nonpersistent
        let migration: PersistentLifecycleActionDispositionV1 = hasNoCanonicalWrite
            ? .notApplicable
            : isDerived
            ? .rebuildable
            : (registration.replicationPolicy.persistence == .nonpersistent
                ? .notApplicable : .supported)
        let backup = backupDisposition(registration.replicationPolicy.backup)
        let restore: PersistentLifecycleActionDispositionV1
        switch registration.replicationPolicy.backup {
        case .includeCanonical: restore = .supported
        case .includeImmutableHistory: restore = .immutable
        case .rebuildAfterRestore: restore = .rebuildable
        case .exclude: restore = .denied
        }
        let rebuild: PersistentLifecycleActionDispositionV1 = isDerived
            && route.rebuild == .rebuildFromCanonicalDependencies
            ? .rebuildable : .notApplicable
        let replay: PersistentLifecycleActionDispositionV1
        switch route.replay {
        case .immutableMutationHistory: replay = .immutable
        case .recoveryStateMachine: replay = .supported
        case .notApplicable: replay = .notApplicable
        }
        let filesystemBackup: PersistentLifecycleActionDispositionV1
        switch route.filesystemBackup {
        case .included: filesystemBackup = .supported
        case .excluded: filesystemBackup = .denied
        case .notApplicable: filesystemBackup = .notApplicable
        }
        let writer: PersistentLifecycleActionDispositionV1 = hasNoCanonicalWrite
            ? .notApplicable
            : isDerived
            ? .rebuildable
            : .supported
        let query: PersistentLifecycleActionDispositionV1 = hasNoCanonicalWrite
            ? .notApplicable : .supported
        let journal: PersistentLifecycleActionDispositionV1
        if registration.subject.category == .journal {
            journal = registration.classification == .replicated ? .immutable : .supported
        } else {
            journal = .notApplicable
        }
        let futureReplication: PersistentLifecycleActionDispositionV1 =
            registration.replicationPolicy.transport == .excluded ? .denied : .supported
        let erase: PersistentLifecycleActionDispositionV1
        switch persistentClassification {
        case .canonical: erase = .supported
        case .immutable, .declaration: erase = .immutable
        case .derived: erase = .rebuildable
        case .wire: erase = .notApplicable
        case .content: erase = .contentManaged
        case .nonpersistent: erase = .notApplicable
        }
        let dispositions: [PersistentLifecycleActionV1: PersistentLifecycleActionDispositionV1] = [
            .schemaAndVersion: .supported,
            .writerCommand: writer,
            .canonicalQuery: query,
            .migration: migration,
            .filesystemBackup: filesystemBackup,
            .semanticBackup: backup,
            .replaceRestore: restore,
            .clone: cloneOrForkDisposition(registration),
            .fork: cloneOrForkDisposition(registration),
            .importAction: isPortable
                ? (registration.classification == .contentBlob ? .contentManaged : .supported)
                : .denied,
            .export: exportDisposition(registration.replicationPolicy.export),
            .report: isPortable ? .supported : .denied,
            .journal: journal,
            .replay: replay,
            .search: .denied,
            .rebuild: rebuild,
            .delete: deleteDisposition(route.deletion),
            .erase: erase,
            .retention: .supported,
            .localization: isUserVisibleHistoricOutput ? .supported : .notApplicable,
            .accessibility: isUserVisibleHistoricOutput ? .supported : .notApplicable,
            .privacy: .supported,
            .compatibility: isDerived ? .rebuildable : (isPortable ? .supported : .notApplicable),
            .downgrade: .denied,
            .forwardFix: .supported,
            .interruptionRecovery: .supported,
            .idempotentReceipt: .supported,
            .futureReplication: futureReplication,
        ]
        let authority = implementationOwnerPrefix
            + "." + registration.subject.category.rawValue
        let declaredDependencies = registration.replicationPolicy.dependencies
            .map(\.canonicalKey).sorted()
        let dependencies = registration.classification == .derivedRebuildable
            && declaredDependencies.isEmpty
            ? CurrentSyncClassificationCatalogV1.activePersistentModelNames.map {
                SyncSubjectCategoryV1.persistentModel.rawValue + ":" + $0
            }.sorted()
            : declaredDependencies
        let rows = try PersistentLifecycleActionV1.allCases.map { action in
            guard let disposition = dispositions[action] else {
                throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidLifecyclePolicy
            }
            let evidence: PersistentLifecycleEvidenceDispositionV1
            switch disposition {
            case .notApplicable: evidence = .notApplicable
            case .denied: evidence = .absenceProved
            case .immutable: evidence = .immutableDeclaration
            case .supported, .rebuildable, .contentManaged:
                evidence = .implementationRequired
            case .ownerRequired:
                throw CurrentPersistentKindLifecycleCatalogFailureV1.invalidLifecyclePolicy
            }
            return try PersistentLifecycleActionPolicyV1(
                action: action,
                disposition: disposition,
                authority: authority,
                reason: "policy." + action.rawValue.lowercased(),
                dependencyKindIDs: action == .rebuild ? dependencies : [],
                evidence: evidence
            )
        }.sorted { $0.action.rawValue < $1.action.rawValue }
        return try PersistentLifecyclePolicyV1(
            kindID: registration.subject.canonicalKey,
            policyRevision: 1,
            actionPolicies: rows
        )
    }

    static func makeDataHandlingPolicy(
        _ registration: SyncClassificationRegistrationV1
    ) throws -> DataHandlingPolicyV1 {
        let persistentClassification = kindClassification(registration)
        let isUserVisibleHistoricOutput = [
            "ReportSnapshotV1", "reportPDF", "reportSnapshot",
        ].contains(registration.subject.stableName)
        let privacy: PersistentDataPrivacyDispositionV1
        switch registration.replicationPolicy.privacy {
        case .workspaceData: privacy = .workspaceCanonical
        case .workspaceContentBlob: privacy = .workspaceContent
        case .privateDeviceData, .secretNeverPortable:
            privacy = .privateDeviceOperational
        case .noncustomerDiagnostic: privacy = .noncustomerDiagnostic
        }
        let retention: PersistentDataRetentionDispositionV1
        switch registration.replicationPolicy.retention {
        case .untilCanonicalDeleteOrErase: retention = .untilCanonicalDeleteOrErase
        case .immutableHistoryUntilErase: retention = .immutableHistoryUntilErase
        case .rebuildable: retention = .rebuildable
        case .operationScoped: retention = .operationScoped
        case .localDeviceRetained: retention = .localDeviceRetained
        }
        let authority: PersistentDestructiveAuthorityV1
        switch persistentClassification {
        case .content: authority = .immutableContentManager
        default:
            switch registration.replicationPolicy.deletion {
            case .appendTombstone, .canonicalDelete: authority = .canonicalWorkspaceDeletion
            case .rebuild: authority = .derivedRebuildOwner
            case .operationCleanup: authority = .operationCleanupOwner
            case .localAuthority: authority = .localDeviceOwner
            }
        }
        return try DataHandlingPolicyV1(
            kindID: registration.subject.canonicalKey,
            policyRevision: 1,
            privacy: privacy,
            retention: retention,
            privacyAuthority: implementationOwnerPrefix + ".PRIVACY",
            retentionAuthority: implementationOwnerPrefix + ".RETENTION",
            destructiveAuthority: authority,
            destructiveAuthorityOwner: implementationOwnerPrefix + ".DESTRUCTIVE",
            secretHandling: registration.subject.category == .secret
                ? .nonportableSecretAuthority : .forbidden,
            telemetry: privacy == .noncustomerDiagnostic
                ? .boundedNoncustomerOperationalOnly : .forbidden,
            fileProtection: registration.replicationPolicy.persistence == .ownedFile
                ? .complete : .notApplicable,
            localization: isUserVisibleHistoricOutput
                ? .localizedFrozenHistoricProjection : .frozenDataNoPresentation,
            accessibility: isUserVisibleHistoricOutput
                ? .accessibleFrozenHistoricProjection : .frozenDataNoPresentation,
            customerWorkDataScope: privacy == .workspaceCanonical
                ? .workspaceData
                : (privacy == .workspaceContent
                    ? .workspaceContent : .deviceOperationalNoCustomerData)
        )
    }

    static func backupDisposition(
        _ value: ReplicationBackupDispositionV1
    ) -> PersistentLifecycleActionDispositionV1 {
        switch value {
        case .includeCanonical: return .supported
        case .includeImmutableHistory: return .immutable
        case .rebuildAfterRestore: return .rebuildable
        case .exclude: return .denied
        }
    }

    static func exportDisposition(
        _ value: ReplicationExportDispositionV1
    ) -> PersistentLifecycleActionDispositionV1 {
        switch value {
        case .portableCanonical: return .supported
        case .portableImmutableHistory: return .immutable
        case .exclude: return .denied
        }
    }

    static func cloneOrForkDisposition(
        _ value: SyncClassificationRegistrationV1
    ) -> PersistentLifecycleActionDispositionV1 {
        switch value.classification {
        case .replicated: return .supported
        case .contentBlob: return .immutable
        case .derivedRebuildable: return .rebuildable
        case .localOnly, .privateDeviceOnly: return .denied
        }
    }

    static func deleteDisposition(
        _ value: ReplicationDeleteDispositionV1
    ) -> PersistentLifecycleActionDispositionV1 {
        switch value {
        case .appendTombstone: return .immutable
        case .canonicalDelete: return .supported
        case .rebuild: return .rebuildable
        case .operationCleanup: return .supported
        case .localAuthority: return .contentManaged
        }
    }

    static func eraseDisposition(
        _ value: ReplicationEraseDispositionV1
    ) -> PersistentLifecycleActionDispositionV1 {
        switch value {
        case .clearWithWorkspace, .recreateEmpty: return .supported
        case .rebuildAfterErase: return .rebuildable
        case .localAuthority: return .contentManaged
        }
    }
}
