import Foundation

// Pure structural/reference observations. No source admission or effect authority.

struct TemporalNormalizationContactReinspectionReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case contact(ServiceContactPointV1), intent(SystemHandoffIntentV1)
        case contactMutation(OperationalContactMutationV1)
        case reinspectionSnapshot(ReinspectionExceptionQueueBackupSnapshotV1)
        case plan(ReinspectionPlanV1), attestation(UnchangedAttestationV1)
        case acknowledgement(ExceptionQueueAcknowledgementV1)
        case reinspectionMutation(ReinspectionExceptionMutationCommandV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case importSourceSet(ImportSourceSetV1)
        case reinspectionSource(ReinspectionSourceSnapshotV1)
        case exceptionSource(ExceptionQueueSourceSnapshotV1)
        case acknowledgementSource(ExceptionQueueAcknowledgementV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) -> Observation {
            let owner = Observation(origin: origin, value: value); roots.append(owner); return owner
        }
        func plan(_ value: ReinspectionPlanV1, _ origin: Origin) {
            let owner = retain(.plan(value), origin)
            for item in value.items {
                refs.append(.init(owner: owner, binding: .reinspectionSource(item.prior)))
                refs.append(.init(owner: owner, binding: .reinspectionSource(item.current)))
            }
        }
        func attestation(_ value: UnchangedAttestationV1, _ origin: Origin) {
            let owner = retain(.attestation(value), origin)
            refs.append(.init(owner: owner, binding: .reinspectionSource(value.prior)))
            refs.append(.init(owner: owner, binding: .reinspectionSource(value.current)))
        }
        func acknowledgement(_ value: ExceptionQueueAcknowledgementV1, _ origin: Origin) {
            refs.append(.init(owner: retain(.acknowledgement(value), origin), binding: .acknowledgementSource(value)))
        }
        let origin = Origin.canonical(source: snapshot)
        let contacts = try snapshot.records.validateC46OperationalContacts()
        for value in contacts.contacts { _ = retain(.contact(value), origin) }
        for value in contacts.intents { _ = retain(.intent(value), origin) }
        if let value = snapshot.records.reinspectionExceptionQueue {
            try value.validate()
            _ = retain(.reinspectionSnapshot(value), origin)
            for value in value.plans { plan(value, origin) }
            for value in value.attestations { attestation(value, origin) }
            for value in value.acknowledgements { acknowledgement(value, origin) }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyOperationalContact(mutation):
                try mutation.validate()
                _ = try OperationalContactMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                let owner = retain(.contactMutation(mutation), origin)
                for value in mutation.predecessors + mutation.successors { _ = retain(.contact(value), origin) }
                for value in mutation.handoffIntents { _ = retain(.intent(value), origin) }
                // Source files were deliberately not persisted by C46. The
                // closed import commitment is not a demand for old archive bytes.
                if let source = mutation.importSourceSet { refs.append(.init(owner: owner, binding: .importSourceSet(source))) }
            case let .applyReinspectionException(command):
                try command.validate()
                let owner = retain(.reinspectionMutation(command), origin)
                switch command.payload {
                case let .putPlan(value, prior): plan(value, origin); if let prior { plan(prior, origin) }
                case let .recordAttestation(value, source): attestation(value, origin); plan(source, origin)
                case let .recordAcknowledgement(value, source, prior):
                    acknowledgement(value, origin); if let prior { acknowledgement(prior, origin) }
                    refs.append(.init(owner: owner, binding: .exceptionSource(source)))
                }
            default: break
            }
        }
        observations = roots; references = refs
    }
}

/// Spatial/schedule graph nodes retain exact embedded references and admission
/// context. These are graph observations, not a proof of byte-free families.
struct TemporalNormalizationSpatialScheduleReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case locator(AssetLocatorV1), locatorReceipt(LocatorBindingReceiptV1)
        case schedule(ScheduleDefinitionReleaseV1), calendar(ExceptionCalendarReleaseV1)
        case override(ScheduleOverrideEventV1), occurrence(OccurrenceHistoryEventV1)
        case generationPlan(OccurrenceGenerationPlanV1)
        case pose(AssetPoseEventV1), anchor(SpatialAnchorObservationV1)
        case poseAdmission(PlacementPoseAdmissionClosureV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    let observations: [Observation]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = []
        func retain(_ value: Value, _ origin: Origin) { roots.append(.init(origin: origin, value: value)) }
        let origin = Origin.canonical(source: snapshot)
        for row in snapshot.records.assetLocators {
            switch row.kind {
            case .locator: retain(.locator(try AssetLocatorCanonicalCodecV1.decode(AssetLocatorV1.self, from: row.canonicalData)), origin)
            case .bindingReceipt: retain(.locatorReceipt(try AssetLocatorCanonicalCodecV1.decode(LocatorBindingReceiptV1.self, from: row.canonicalData)), origin)
            }
        }
        for row in snapshot.records.schedules {
            switch row.kind {
            case .scheduleRelease: retain(.schedule(try ScheduleCanonicalCodecV1.decode(ScheduleDefinitionReleaseV1.self, from: row.canonicalData)), origin)
            case .occurrenceHistory: retain(.occurrence(try ScheduleCanonicalCodecV1.decode(OccurrenceHistoryEventV1.self, from: row.canonicalData)), origin)
            case .exceptionCalendarRelease: retain(.calendar(try ScheduleCanonicalCodecV1.decode(ExceptionCalendarReleaseV1.self, from: row.canonicalData)), origin)
            case .scheduleOverrideEvent: retain(.override(try ScheduleCanonicalCodecV1.decode(ScheduleOverrideEventV1.self, from: row.canonicalData)), origin)
            }
        }
        let pose = try PlacementPoseBackupRecordSetV1.decode(snapshot.records.placementPoses)
        for value in pose.poseEvents { retain(.pose(value), origin) }
        for value in pose.spatialAnchors { retain(.anchor(value), origin) }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyAssetLocator(mutation):
                try mutation.validate()
                _ = try AssetLocatorMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.payload {
                case let .bind(value, receipt, prior):
                    retain(.locator(value), origin); retain(.locatorReceipt(receipt), origin)
                    if let prior { retain(.locatorReceipt(prior), origin) }
                case let .transition(value, receipt, predecessor, prior):
                    retain(.locator(value), origin); retain(.locatorReceipt(receipt), origin); retain(.locator(predecessor), origin)
                    if let prior { retain(.locatorReceipt(prior), origin) }
                case let .replace(value, replacement, receipt, predecessor, prior):
                    retain(.locator(value), origin); retain(.locator(replacement), origin)
                    retain(.locatorReceipt(receipt), origin); retain(.locator(predecessor), origin)
                    if let prior { retain(.locatorReceipt(prior), origin) }
                }
            case let .applySchedule(mutation):
                try mutation.validate()
                _ = try ScheduleMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.payload {
                case let .appendRelease(value, prior): retain(.schedule(value), origin); if let prior { retain(.schedule(prior), origin) }
                case let .appendExceptionCalendarRelease(value, prior): retain(.calendar(value), origin); if let prior { retain(.calendar(prior), origin) }
                case let .appendOverrideEvent(value, prior, release):
                    retain(.override(value), origin); if let prior { retain(.override(prior), origin) }; retain(.schedule(release), origin)
                case let .appendOccurrenceEvent(value, prior, release):
                    retain(.occurrence(value), origin); if let prior { retain(.occurrence(prior), origin) }; retain(.schedule(release), origin)
                case let .startOccurrence(value, prior, release):
                    retain(.occurrence(value), origin); retain(.occurrence(prior), origin); retain(.schedule(release), origin)
                case let .generateOccurrences(release, plan, events):
                    retain(.schedule(release), origin); retain(.generationPlan(plan), origin)
                    for value in events { retain(.occurrence(value), origin) }
                }
            case let .applyPlacementPose(mutation):
                try mutation.validate()
                _ = try PlacementPoseMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                for value in mutation.events + mutation.eventPredecessors.compactMap({ $0 }) { retain(.pose(value), origin) }
                for value in mutation.observations + mutation.observationPredecessors.compactMap({ $0 }) { retain(.anchor(value), origin) }
                retain(.poseAdmission(mutation.admissionClosure), origin)
            default: break
            }
        }
        observations = roots
    }
}


struct TemporalNormalizationAssetPartyRequirementReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case party(ServicePartyReferenceV1)
        case siteRole(SitePartyRoleEventV1)
        case actor(ActorSnapshotV1)
        case qualification(QualificationSnapshotV1)
        case signoff(SignoffSnapshotV1)
        case kindBinding(AssetKindBindingEventV1)
        case workflowBinding(AssetWorkflowCapabilityBindingEventV1)
        case product(AssetProductIdentityV1)
        case lifecycle(AssetLifecycleEventV1)
        case successor(AssetSuccessorLinkV1)
        case workScope(WorkSubjectScopeSnapshotV1)
        case functionalDescriptor(FunctionalRelationshipTypeDescriptorV1)
        case functionalEvent(AssetFunctionalRelationshipEventV1)
        case requirement(RequirementAssuranceSnapshotV1)
        case contactImport(OperationalContactMutationV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case requirementEvaluation(RequirementEvaluationV1)
        case importedContactSource(ImportSourceSetV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) {
            let owner = Observation(origin: origin, value: value); roots.append(owner)
            switch value {
            case let .requirement(snapshot):
                for evaluation in snapshot.evaluations { refs.append(.init(owner: owner, binding: .requirementEvaluation(evaluation))) }
            case let .contactImport(mutation):
                if let value = mutation.importSourceSet { refs.append(.init(owner: owner, binding: .importedContactSource(value))) }
            default: break
            }
        }
        func party(_ value: PartyAccountabilityMutationV1, _ origin: Origin) throws {
            try value.validate()
            switch value {
            case let .recordParty(value): retain(.party(value), origin)
            case let .appendSiteRole(value): retain(.siteRole(value), origin)
            case let .appendActorSnapshot(value): retain(.actor(value), origin)
            case let .appendQualificationSnapshot(value): retain(.qualification(value), origin)
            case let .appendSignoff(value): retain(.signoff(value), origin)
            }
        }
        let origin = Origin.canonical(source: snapshot)
        for row in snapshot.records.partyAccountability {
            switch row.kind {
            case .serviceParty: retain(.party(try PartyAccountabilitySnapshotCodecV1.decode(ServicePartyReferenceV1.self, from: row.canonicalData)), origin)
            case .sitePartyRoleEvent: retain(.siteRole(try PartyAccountabilitySnapshotCodecV1.decode(SitePartyRoleEventV1.self, from: row.canonicalData)), origin)
            case .actorSnapshot: retain(.actor(try PartyAccountabilitySnapshotCodecV1.decode(ActorSnapshotV1.self, from: row.canonicalData)), origin)
            case .qualificationSnapshot: retain(.qualification(try PartyAccountabilitySnapshotCodecV1.decode(QualificationSnapshotV1.self, from: row.canonicalData)), origin)
            case .signoffSnapshot: retain(.signoff(try PartyAccountabilitySnapshotCodecV1.decode(SignoffSnapshotV1.self, from: row.canonicalData)), origin)
            }
        }
        for row in snapshot.records.assetSemantics {
            switch row.kind {
            case .kindBindingEvent: retain(.kindBinding(try AssetSemanticCanonicalCodecV1.decode(AssetKindBindingEventV1.self, from: row.canonicalData)), origin)
            case .workflowCapabilityBindingEvent: retain(.workflowBinding(try AssetSemanticCanonicalCodecV1.decode(AssetWorkflowCapabilityBindingEventV1.self, from: row.canonicalData)), origin)
            case .productIdentity: retain(.product(try AssetSemanticCanonicalCodecV1.decode(AssetProductIdentityV1.self, from: row.canonicalData)), origin)
            case .lifecycleEvent: retain(.lifecycle(try AssetSemanticCanonicalCodecV1.decode(AssetLifecycleEventV1.self, from: row.canonicalData)), origin)
            case .successorLink: retain(.successor(try AssetSemanticCanonicalCodecV1.decode(AssetSuccessorLinkV1.self, from: row.canonicalData)), origin)
            case .workSubjectScopeSnapshot: retain(.workScope(try AssetSemanticCanonicalCodecV1.decode(WorkSubjectScopeSnapshotV1.self, from: row.canonicalData)), origin)
            }
        }
        for row in snapshot.records.requirementAssurance { retain(.requirement(try row.snapshot()), origin) }
        for row in snapshot.records.functionalRelationships {
            switch row.kind {
            case .descriptor: retain(.functionalDescriptor(try FunctionalRelationshipCanonicalCodecV1.decode(FunctionalRelationshipTypeDescriptorV1.self, from: row.canonicalData)), origin)
            case .event: retain(.functionalEvent(try FunctionalRelationshipCanonicalCodecV1.decode(AssetFunctionalRelationshipEventV1.self, from: row.canonicalData)), origin)
            }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyPartyAccountability(value): try party(value, origin)
            case let .applyPartyContactSiteRoleImport(mutation):
                try mutation.validate()
                _ = try PartyContactSiteRoleImportMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                for value in mutation.partyMutations + mutation.siteRoleMutations { try party(value, origin) }
                retain(.contactImport(mutation.operationalContactMutation), origin)
            case let .applyAssetSemantics(mutation):
                try mutation.validate()
                if let value = mutation.kindBinding { retain(.kindBinding(value), origin) }
                if let value = mutation.workflowCapabilityBinding { retain(.workflowBinding(value), origin) }
                if let value = mutation.productIdentity { retain(.product(value), origin) }
                if let value = mutation.lifecycleEvent { retain(.lifecycle(value), origin) }
                if let value = mutation.successorLink { retain(.successor(value), origin) }
                if let value = mutation.workSubjectScope { retain(.workScope(value), origin) }
            case let .applyRequirementAssurance(mutation):
                try mutation.validate(); retain(.requirement(mutation.snapshot), origin)
            case let .applyFunctionalRelationship(mutation):
                try mutation.validate()
                _ = try FunctionalRelationshipMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.postImage {
                case let .appendDescriptor(value), let .supersedeDescriptor(value): retain(.functionalDescriptor(value), origin)
                case let .addRelationship(value), let .endRelationship(value), let .supersedeRelationship(value): retain(.functionalEvent(value), origin)
                }
            default: break
            }
        }
        observations = roots; references = refs
    }
}

/// Operational graph aggregates keep all closed typed members, including
/// historical and reversed state. Their subjects and predecessors still need
/// the common namespace resolver; no raw file is inferred from display text.
struct TemporalNormalizationOperationalGraphReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case workResource(WorkResourceEntryV1)
        case stockSnapshot(PartsStockBackupSnapshotV1), stockMutation(PartsStockMutationV1)
        case dayPlan(MyDayPlanV1), dayCarryover(MyDayCarryoverReceiptV1), dayNonactive(MyDayPlanReferenceV1)
        case dayCarryoverPlan(MyDayCarryoverPlanV1)
        case mapping(ImportMappingProfileV1), bulkSession(BulkSessionV1), bulkReceipt(BulkCommitReceiptV1)
        case identitySnapshot(EntityIdentityResolutionBackupSnapshotV1)
        case alias(EntityAliasLinkV1), consolidation(EntityConsolidationReceiptV1)
        case practice(PracticeWorkspaceProvenanceV1), workspaceInstall(WorkspaceExperienceMutationCommandV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    let observations: [Observation]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = []
        func retain(_ value: Value, _ origin: Origin) { roots.append(.init(origin: origin, value: value)) }
        let origin = Origin.canonical(source: snapshot)
        for row in snapshot.records.workResources { retain(.workResource(try row.value()), origin) }
        if let value = snapshot.records.partsStockSnapshot { try value.validate(); retain(.stockSnapshot(value), origin) }
        for value in snapshot.records.myDayPlans { retain(.dayPlan(value), origin) }
        for value in snapshot.records.myDayCarryoverReceipts { retain(.dayCarryover(value), origin) }
        for value in snapshot.records.nonactivePlanReferences { retain(.dayNonactive(value), origin) }
        for value in snapshot.records.importMappingProfiles { retain(.mapping(value), origin) }
        for value in snapshot.records.bulkSessions { retain(.bulkSession(value), origin) }
        for value in snapshot.records.bulkCommitReceipts { retain(.bulkReceipt(value), origin) }
        if let value = snapshot.records.entityIdentityResolution {
            try value.validate(); retain(.identitySnapshot(value), origin)
            for value in value.aliasLinks { retain(.alias(value), origin) }
            for value in value.consolidationReceipts { retain(.consolidation(value), origin) }
        }
        if let value = snapshot.records.practiceWorkspaceProvenance { try value.validate(); retain(.practice(value.provenance), origin) }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyWorkResource(mutation):
                try mutation.validate()
                _ = try WorkResourceMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                retain(.workResource(mutation.postImage), origin)
            case let .applyPartsStock(mutation):
                try mutation.validate(); retain(.stockMutation(mutation), origin)
                // The enum carries every operation's exact part/location/
                // movement/receipt graph, including work-resource successors.
                switch mutation {
                case let .use(value): retain(.workResource(value.workResourceSuccessor), origin)
                case let .reverseUse(value): retain(.workResource(value.workResourceSuccessor), origin)
                case let .returnAgainstUse(value): retain(.workResource(value.workResourceSuccessor), origin)
                case .upsertPart, .upsertLocation, .appendMovement, .transfer, .retirePart, .abandon: break
                }
            case let .applyMyDay(mutation):
                try mutation.validate()
                _ = try MyDayWorkspaceMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.command {
                case let .save(value, prior): retain(.dayPlan(value), origin); if let prior { retain(.dayPlan(prior), origin) }
                case let .carryover(plan, source, target, receipt):
                    retain(.dayCarryoverPlan(plan), origin); retain(.dayPlan(source), origin)
                    retain(.dayPlan(target), origin); retain(.dayCarryover(receipt), origin)
                }
            case let .applyImportBulk(mutation):
                try mutation.validate()
                switch mutation.operation {
                case let .upsertMappingProfile(value, _): retain(.mapping(value), origin)
                case let .advanceSession(value, _): retain(.bulkSession(value), origin)
                case let .appendReceipt(value): retain(.bulkReceipt(value), origin)
                }
            case let .applyEntityIdentityResolution(command):
                try command.validate()
                switch command.payload {
                case let .alias(value, prior): retain(.alias(value), origin); if let prior { retain(.alias(prior), origin) }
                case let .consolidation(value, prior): retain(.consolidation(value), origin); if let prior { retain(.consolidation(prior), origin) }
                }
            case let .applyWorkspaceExperience(command):
                try command.validate()
                retain(.workspaceInstall(command), origin); retain(.practice(command.provenance), origin)
            default: break
            }
        }
        observations = roots
    }
}

struct TemporalNormalizationPackageClientReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case promoted(PromotedPackageReleaseV1), sandbox(PackageSandboxRunV1)
        case promotionReceipt(PackagePromotionReceiptV1), pointer(ActivePackageRegistryPointerV1)
        case promotion(PackagePromotionMutationV1)
        case release(InspectionPackageReleaseV1), package(InspectionPackageV2), workflow(WorkflowDefinitionV1)
        case profile(ClientCapabilityProfileV1), policy(PackageLifecyclePolicyV1)
        case disposition(PackageLifecycleDispositionV1), admission(ClientCapabilityAdmissionDecisionV1)
        case recoverability(RecoverabilityVerificationReceiptV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    let observations: [Observation]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = []
        func retain(_ value: Value, _ origin: Origin) { roots.append(.init(origin: origin, value: value)) }
        func release(_ value: InspectionPackageReleaseV1, _ origin: Origin) throws {
            try value.validate()
            retain(.release(value), origin)
            retain(.package(try InspectionPackageCanonicalCodecV2.decode(value.canonicalPackageBytes)), origin)
            retain(.workflow(try WorkflowDefinitionCanonicalCodecV1.decode(value.canonicalWorkflowBytes)), origin)
        }
        let origin = Origin.canonical(source: snapshot)
        var promoted: [PromotedPackageReleaseV1] = [], runs: [PackageSandboxRunV1] = []
        var receipts: [PackagePromotionReceiptV1] = [], pointers: [ActivePackageRegistryPointerV1] = []
        for row in snapshot.records.packageEvolution {
            let identity: (UUID, WorkspaceID, UInt64)
            switch row.kind {
            case .promotedRelease:
                let value = try PackageEvolutionCanonicalCodecV1.decode(PromotedPackageReleaseV1.self, from: row.canonicalData)
                identity = (value.releaseRecordID, value.workspaceID, value.revision)
                promoted.append(value); retain(.promoted(value), origin); try release(value.packageRelease, origin)
            case .sandboxRun:
                let value = try PackageEvolutionCanonicalCodecV1.decode(PackageSandboxRunV1.self, from: row.canonicalData)
                identity = (value.runID, value.workspaceID, value.revision)
                runs.append(value); retain(.sandbox(value), origin)
            case .promotionReceipt:
                let value = try PackageEvolutionCanonicalCodecV1.decode(PackagePromotionReceiptV1.self, from: row.canonicalData)
                identity = (value.receiptID, value.workspaceID, value.revision)
                receipts.append(value); retain(.promotionReceipt(value), origin)
            case .activePointer:
                let value = try PackageEvolutionCanonicalCodecV1.decode(ActivePackageRegistryPointerV1.self, from: row.canonicalData)
                identity = (value.pointerID, value.workspaceID, value.revision)
                pointers.append(value); retain(.pointer(value), origin)
            }
            guard identity.0 == row.id, identity.1.rawValue == row.workspaceID, identity.2 == row.revision,
                  identity.1 == snapshot.workspaceIdentity.workspaceID else { throw TemporalEvidenceContractFailureV1.staleSource }
        }
        try PackageEvolutionLifecycleClosureV1(promotedReleases: promoted, sandboxRuns: runs,
            promotionReceipts: receipts, activePointers: pointers).validate()
        for row in snapshot.records.clientCapabilities {
            switch row.kind {
            case .profile: retain(.profile(try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityProfileV1.self, from: row.canonicalData)), origin)
            case .policy: retain(.policy(try ClientCapabilityCanonicalCodecV1.decode(PackageLifecyclePolicyV1.self, from: row.canonicalData)), origin)
            case .disposition: retain(.disposition(try ClientCapabilityCanonicalCodecV1.decode(PackageLifecycleDispositionV1.self, from: row.canonicalData)), origin)
            case .admissionDecision: retain(.admission(try ClientCapabilityCanonicalCodecV1.decode(ClientCapabilityAdmissionDecisionV1.self, from: row.canonicalData)), origin)
            }
        }
        for row in snapshot.records.recoverabilityReceipts {
            retain(.recoverability(try RecoverabilityVerificationCanonicalCodecV1.decode(RecoverabilityVerificationReceiptV1.self, from: row.canonicalData)), origin)
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyPackagePromotion(mutation):
                try mutation.validate()
                _ = try PackagePromotionMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                retain(.promotion(mutation), origin); retain(.promoted(mutation.promotedRelease), origin)
                retain(.sandbox(mutation.sandboxRun), origin); retain(.promotionReceipt(mutation.receipt), origin)
                retain(.pointer(mutation.resultingPointer), origin)
                if let prior = mutation.predecessorPointer { retain(.pointer(prior), origin) }
                try release(mutation.promotedRelease.packageRelease, origin)
            case let .applyClientCapability(mutation):
                try mutation.validate()
                _ = try ClientCapabilityMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation {
                case let .profile(value): retain(.profile(value), origin)
                case let .policy(value, package): retain(.policy(value), origin); try release(package, origin)
                case let .disposition(value, package): retain(.disposition(value), origin); try release(package, origin)
                case let .admission(value, profile, policy, disposition, package):
                    retain(.admission(value), origin); retain(.profile(profile), origin)
                    retain(.policy(policy), origin); retain(.disposition(disposition), origin); try release(package, origin)
                }
            default: break
            }
        }
        observations = roots
    }
}

/// Full structural roots remain typed and source-bound. The independent graph
/// reconciliation obligation is explicit; retaining a root is not closing it.
struct TemporalNormalizationStructuralReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case asset(V4BackupAssetDTO), site(V4BackupSiteDTO)
        case workflow(V4BackupWorkflowRecordDTO), issue(V4BackupIssueDTO), packet(V4BackupPacketDTO)
        case deletionLedger(DeletionLedgerV2)
        case node(LocationNodeV1), placement(AssetPlacementEventV1)
        case edge(AssetCompositionEdgeV1), composition(AssetCompositionEventV1)
        case hierarchyPlan(LocationHierarchyChangePlanV1), hierarchyReceipt(LocationHierarchyChangeReceiptV1)
        case migration(LocationMigrationReceiptV1), smartView(SavedSmartViewDescriptorV1)
        case firstSign(FirstSignMutationV1), checkDraft(CheckDraftMutationV1), timeZone(SiteTimeZoneMutationV1)
        case deleteAsset(DeleteAssetMutationV1), deleteSite(DeleteSiteMutationV1)
        case erase(EraseWorkspaceMutationV1), restore(RestoreWorkspaceMutationV1), archive(ArchiveEntitiesMutationV1)
        case hierarchyMutation(LocationHierarchyMutationV1), placementPlan(AssetPlacementChangePlanV1)
        case compositionPlan(AssetCompositionChangePlanV1), smartViewMutation(SavedSmartViewMutationV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    let observations: [Observation]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var result: [Observation] = []
        func retain(_ value: Value, _ origin: Origin) { result.append(.init(origin: origin, value: value)) }
        let origin = Origin.canonical(source: snapshot)
        for value in snapshot.records.assets { retain(.asset(value), origin) }
        for value in snapshot.records.sites { retain(.site(value), origin) }
        for value in snapshot.records.workflowRecords { retain(.workflow(value), origin) }
        for value in snapshot.records.issues { retain(.issue(value), origin) }
        for value in snapshot.records.packets { retain(.packet(value), origin) }
        if let value = snapshot.records.deletionLedger { retain(.deletionLedger(value), origin) }
        for row in snapshot.records.locationNodes { retain(.node(try LocationPersistenceCodecV1.decode(LocationNodeV1.self, from: row.canonicalData)), origin) }
        for row in snapshot.records.assetPlacementEvents { retain(.placement(try LocationPersistenceCodecV1.decode(AssetPlacementEventV1.self, from: row.canonicalData)), origin) }
        for row in snapshot.records.assetCompositionEdges { retain(.edge(try LocationPersistenceCodecV1.decode(AssetCompositionEdgeV1.self, from: row.canonicalData)), origin) }
        for row in snapshot.records.assetCompositionEvents { retain(.composition(try LocationPersistenceCodecV1.decode(AssetCompositionEventV1.self, from: row.canonicalData)), origin) }
        for row in snapshot.records.locationMigrationReceipts { retain(.migration(try LocationPersistenceCodecV1.decode(LocationMigrationReceiptV1.self, from: row.canonicalData)), origin) }
        for row in snapshot.records.locationHierarchyEvents {
            guard let receiptData = row.secondaryCanonicalData else { throw TemporalEvidenceContractFailureV1.staleSource }
            retain(.hierarchyPlan(try LocationPersistenceCodecV1.decode(LocationHierarchyChangePlanV1.self, from: row.canonicalData)), origin)
            retain(.hierarchyReceipt(try LocationPersistenceCodecV1.decode(LocationHierarchyChangeReceiptV1.self, from: receiptData)), origin)
        }
        for row in snapshot.records.savedSmartViews { retain(.smartView(try row.descriptor()), origin) }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .createFirstSign(value): retain(.firstSign(value), origin)
            case let .createCheckDraft(value): retain(.checkDraft(value), origin)
            case let .updateSiteTimeZone(value): retain(.timeZone(value), origin)
            case let .deleteAsset(value): retain(.deleteAsset(value), origin)
            case let .deleteSite(value): retain(.deleteSite(value), origin)
            case let .eraseWorkspace(value): retain(.erase(value), origin)
            case let .restoreWorkspace(value): retain(.restore(value), origin)
            case let .archiveEntities(value): retain(.archive(value), origin)
            case let .applyLocationHierarchyChange(value):
                guard try LocationHierarchyMutationV1(plan: value.plan, placementChanges: value.placementChanges) == value else { throw TemporalEvidenceContractFailureV1.staleSource }
                retain(.hierarchyMutation(value), origin); retain(.hierarchyPlan(value.plan), origin)
                for plan in value.placementChanges { try plan.validate(); retain(.placementPlan(plan), origin) }
            case let .applyAssetPlacementChange(value): try value.validate(); retain(.placementPlan(value), origin)
            case let .applyAssetCompositionChange(value): try value.validate(); retain(.compositionPlan(value), origin)
            case let .applySavedSmartView(value):
                try value.validate(); retain(.smartViewMutation(value), origin)
                if let descriptor = value.descriptor { retain(.smartView(descriptor), origin) }
            default: break
            }
        }
        observations = result
    }
}

/// Joins actual retained dual receipts. Missing historical sidecars are reported,
/// never manufactured, treated as absence of references, or declared invalid
/// solely because a later lawful restore no longer retains that sidecar.
struct TemporalNormalizationDualReceiptObservationsV1: Sendable {
    enum Sidecar: Sendable {
        case quality(EvidenceQualityMutationReceiptV1)
        case inbox(FastSurveyInboxMutationReceiptV1)
        case reinspection(ReinspectionExceptionMutationReceiptV1)
        case identityResolution(EntityIdentityResolutionMutationReceiptV1)
    }
    enum Resolution: Sendable {
        case observed(Sidecar, source: TemporalNormalizationCanonicalSnapshotV1)
        case notPresentInCanonicalSnapshot
    }
    struct Observation: Sendable {
        let entry: TemporalNormalizationHistoryObservationV1.Entry
        let resolution: Resolution
    }
    struct UnmatchedSidecar: Sendable {
        let value: Sidecar
        let source: TemporalNormalizationCanonicalSnapshotV1
        // No retained generic entry of the matching typed command was joined.
        // The original sidecar is still a reference root; this is not absence
        // evidence and does not by itself invent a restore-admission failure.
    }
    let observations: [Observation]
    let unmatchedSidecars: [UnmatchedSidecar]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        // Reuse the actual closed snapshots' incumbent lifecycle/cardinality
        // and effect-provenance laws, without constructing replacement facts.
        try EvidenceQualityBackupEnrollmentV1.validate(snapshot.records)
        try snapshot.records.fastSurveyInbox?.validate()
        try ReinspectionExceptionQueueBackupEnrollmentV1.validate(snapshot.records)
        try EntityIdentityResolutionBackupEnrollmentV1.validate(snapshot.records)
        struct Key: Hashable { let workspace: WorkspaceID; let generation: UUID; let mutation: MutationIDV1 }
        let failure = WorkspaceMutationFailureV1.receiptHistoryCorrupt
        var quality: [Key: EvidenceQualityMutationReceiptV1] = [:]
        for value in snapshot.records.evidenceQuality?.receipts ?? [] {
            try value.validate()
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            guard quality.updateValue(value, forKey: key) == nil else { throw failure }
        }
        var inbox: [Key: FastSurveyInboxMutationReceiptV1] = [:]
        for value in snapshot.records.fastSurveyInbox?.receipts ?? [] {
            try value.validate()
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            guard inbox.updateValue(value, forKey: key) == nil else { throw failure }
        }
        var reinspection: [Key: ReinspectionExceptionMutationReceiptV1] = [:]
        for value in snapshot.records.reinspectionExceptionQueue?.receipts ?? [] {
            try value.validate()
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            guard reinspection.updateValue(value, forKey: key) == nil else { throw failure }
        }
        var identityResolution: [Key: EntityIdentityResolutionMutationReceiptV1] = [:]
        for value in snapshot.records.entityIdentityResolution?.mutationReceipts ?? [] {
            try value.validate()
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            guard identityResolution.updateValue(value, forKey: key) == nil else { throw failure }
        }
        func validateImages(_ identities: [WorkspaceEntityIdentityV1],
                            _ entry: TemporalNormalizationHistoryObservationV1.Entry) throws {
            guard try entry.receipt.postImages.map({ try $0.identity }) == identities else { throw failure }
            let expected = Dictionary(uniqueKeysWithValues: entry.receipt.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
            let resulting = Dictionary(uniqueKeysWithValues: entry.receipt.resultingRevision.entityRevisions.map { ($0.identity, $0.revision) })
            for image in entry.receipt.postImages {
                let identity = try image.identity
                let (next, overflow) = expected[identity, default: 0].addingReportingOverflow(1)
                guard !overflow, image.revision == next, resulting[identity] == next else { throw failure }
            }
        }
        var result: [Observation] = []
        var joinedQuality = Set<Key>(), joinedInbox = Set<Key>(), joinedReinspection = Set<Key>(), joinedIdentityResolution = Set<Key>()
        for entry in history.entries {
            let key = Key(workspace: entry.envelope.workspaceID,
                generation: entry.envelope.expectedRevision.generationID, mutation: entry.envelope.mutationID)
            let resolution: Resolution
            switch entry.envelope.command {
            case let .applyEvidenceQuality(command):
                try validateImages([try command.affectedIdentityForCanonicalWriter()], entry)
                if let value = quality[key] {
                    try value.validate(command: command)
                    guard value.recoveryState == .receiptCommitted,
                          value.priorWorkspaceRevision == entry.receipt.expectedRevision.workspaceRevision,
                          value.resultingWorkspaceRevision == entry.receipt.resultingRevision.workspaceRevision else { throw failure }
                    guard entry.receipt.postImages.count == 1,
                          entry.receipt.postImages.first?.semanticSHA256 == value.semanticSHA256 else { throw failure }
                    resolution = .observed(.quality(value), source: snapshot)
                    guard joinedQuality.insert(key).inserted else { throw failure }
                } else { resolution = .notPresentInCanonicalSnapshot }
            case let .applyFastSurveyInbox(command):
                try validateImages(try command.affectedIdentitiesForCanonicalWriter(), entry)
                if let value = inbox[key] {
                    try value.validate(command: command)
                    guard value.recoveryState == .receiptCommitted,
                          value.priorWorkspaceRevision == entry.receipt.expectedRevision.workspaceRevision,
                          value.resultingWorkspaceRevision == entry.receipt.resultingRevision.workspaceRevision else { throw failure }
                    guard entry.receipt.postImages.map(\.semanticSHA256).sorted() == value.semanticSHA256s.sorted() else { throw failure }
                    resolution = .observed(.inbox(value), source: snapshot)
                    guard joinedInbox.insert(key).inserted else { throw failure }
                } else { resolution = .notPresentInCanonicalSnapshot }
            case let .applyReinspectionException(command):
                try validateImages(try command.affectedIdentitiesForCanonicalWriter(), entry)
                if let value = reinspection[key] {
                    try value.validate(command: command)
                    guard value.recoveryState == .receiptCommitted,
                          value.priorWorkspaceRevision == entry.receipt.expectedRevision.workspaceRevision,
                          value.resultingWorkspaceRevision == entry.receipt.resultingRevision.workspaceRevision else { throw failure }
                    guard entry.receipt.postImages.map(\.semanticSHA256).sorted() == value.semanticSHA256s.sorted() else { throw failure }
                    resolution = .observed(.reinspection(value), source: snapshot)
                    guard joinedReinspection.insert(key).inserted else { throw failure }
                } else { resolution = .notPresentInCanonicalSnapshot }
            case let .applyEntityIdentityResolution(command):
                try validateImages(try command.affectedIdentitiesForCanonicalWriter(), entry)
                if let value = identityResolution[key] {
                    try value.validate(command: command)
                    guard value.recoveryState == .receiptCommitted,
                          value.priorWorkspaceRevision == entry.receipt.expectedRevision.workspaceRevision,
                          value.resultingWorkspaceRevision == entry.receipt.resultingRevision.workspaceRevision,
                          entry.receipt.postImages.map(\.semanticSHA256).sorted() == value.semanticSHA256s else { throw failure }
                    resolution = .observed(.identityResolution(value), source: snapshot)
                    guard joinedIdentityResolution.insert(key).inserted else { throw failure }
                } else { resolution = .notPresentInCanonicalSnapshot }
            default: continue
            }
            result.append(.init(entry: entry, resolution: resolution))
        }
        // Preserve original canonical order and complete typed values. An
        // unmatched sidecar cannot disappear merely because a history-driven
        // loop did not find it, including a same-ID wrong command family.
        var unmatched: [UnmatchedSidecar] = []
        for value in snapshot.records.evidenceQuality?.receipts ?? [] {
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            if !joinedQuality.contains(key) { unmatched.append(.init(value: .quality(value), source: snapshot)) }
        }
        for value in snapshot.records.fastSurveyInbox?.receipts ?? [] {
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            if !joinedInbox.contains(key) { unmatched.append(.init(value: .inbox(value), source: snapshot)) }
        }
        for value in snapshot.records.reinspectionExceptionQueue?.receipts ?? [] {
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            if !joinedReinspection.contains(key) { unmatched.append(.init(value: .reinspection(value), source: snapshot)) }
        }
        for value in snapshot.records.entityIdentityResolution?.mutationReceipts ?? [] {
            let key = Key(workspace: value.workspaceID, generation: value.generationID, mutation: value.mutationID)
            if !joinedIdentityResolution.contains(key) { unmatched.append(.init(value: .identityResolution(value), source: snapshot)) }
        }
        observations = result; unmatchedSidecars = unmatched
    }
}

/// Reuses exactly the writer's pure postimage predicates on already validated
/// immutable journal entries. Coverage is descriptive, not an admission seal.
struct TemporalNormalizationCommandPostImageObservationsV1: Sendable {
    enum Coverage: Sendable {
        case exactDomainPostImages
        case identityAndRevisionOnly
        case identitySemanticAndRevision
        case nestedPlacementPoseOnly
        case incumbentImportedHistorySpecialization
        case notCoveredByAppendBlock
    }
    enum SupplementalCoverage: Sendable {
        case none, exactPartyValue, exactSavedDescriptor, exactSavedDescriptorTombstone
    }
    struct Observation: Sendable {
        let entry: TemporalNormalizationHistoryObservationV1.Entry
        let coverage: Coverage
        let supplementalCoverage: SupplementalCoverage
    }
    let observations: [Observation]
    init(history: TemporalNormalizationHistoryObservationV1) throws {
        var result: [Observation] = []
        for entry in history.entries {
            // History admission retains the original envelope, receipt,
            // sourceKind, imported/recovery/reversal bindings and full bytes.
            // Never construct a localUser wrapper around another provenance.
            try entry.envelope.validate(); try entry.receipt.validate()
            let expected = Dictionary(uniqueKeysWithValues:
                entry.receipt.expectedRevision.entityRevisions.map { ($0.identity, $0.revision) })
            // The incumbent import-bulk branch performs one addition on the
            // command's own expected revision. Reject overflow before invoking
            // that exact predicate from this read-only observation route.
            if case let .applyImportBulk(command) = entry.envelope.command {
                guard command.expectedRevision < UInt64.max else {
                    throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                }
            }
            // Receipt.validate already requires each postimage's concurrency
            // predecessor below UInt64.max. Guard the exact identities used by
            // these three append predicates before their original arithmetic.
            let incremented: [WorkspaceEntityIdentityV1]
            switch entry.envelope.command {
            case let .applyEvidenceQuality(command): incremented = [try command.affectedIdentityForCanonicalWriter()]
            case let .applyFastSurveyInbox(command): incremented = try command.affectedIdentitiesForCanonicalWriter()
            case let .applyReinspectionException(command): incremented = try command.affectedIdentitiesForCanonicalWriter()
            default: incremented = []
            }
            guard incremented.allSatisfy({ expected[$0, default: 0] < UInt64.max }) else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
            try MutationJournalStoreV1.validateAppendCommandPostImages(command: entry.envelope.command,
                postImages: entry.receipt.postImages, expectedByIdentity: expected)
            let supplemental: SupplementalCoverage
            switch entry.envelope.command {
            case let .applyPartyAccountability(command):
                let identity = try command.affectedIdentity
                guard entry.receipt.postImages.count == 1, let image = entry.receipt.postImages.first,
                      try image.identity == identity else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                let expectedImage: MutationPostImageV1
                switch command {
                case let .recordParty(value): expectedImage = try MutationJournalStoreV1.observationPostImage(value, revision: image.revision)
                case let .appendSiteRole(value): expectedImage = try MutationJournalStoreV1.observationPostImage(value, revision: image.revision)
                case let .appendActorSnapshot(value): expectedImage = try MutationJournalStoreV1.observationPostImage(value, revision: image.revision)
                case let .appendQualificationSnapshot(value): expectedImage = try MutationJournalStoreV1.observationPostImage(value, revision: image.revision)
                case let .appendSignoff(value): expectedImage = try MutationJournalStoreV1.observationPostImage(value, revision: image.revision)
                }
                guard image == expectedImage else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                supplemental = .exactPartyValue
            case let .applySavedSmartView(command):
                let identity = try WorkspaceEntityIdentityV1(kind: .savedSmartView, id: command.id)
                guard entry.receipt.postImages.count == 1, let image = entry.receipt.postImages.first,
                      try image.identity == identity else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                switch command.disposition {
                case .upsert:
                    guard let descriptor = command.descriptor,
                          image == (try MutationJournalStoreV1.observationPostImage(descriptor, revision: image.revision)) else {
                        throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
                    }
                    supplemental = .exactSavedDescriptor
                case .delete:
                    let expectedImage = MutationPostImageV1.tombstone(identity: identity, revision: image.revision,
                        semanticSHA256: try MutationJournalStoreV1.restoreTombstoneSHA256(identity: identity, revision: image.revision))
                    guard image == expectedImage else { throw WorkspaceMutationFailureV1.receiptHistoryCorrupt }
                    supplemental = .exactSavedDescriptorTombstone
                }
            default: supplemental = .none
            }
            let coverage: Coverage
            switch entry.envelope.command {
            case .applyAuthorityCriterion, .applyFunctionalRelationship, .applyEvidenceAssurance, .applyInspectionReview, .applyWorkPacket, .applyFieldDraft, .applyPackagePromotion, .applyMeasurementIntegrity, .applyPrivacyTransform, .applyEvidenceMetadata, .applyClientCapability, .applyFieldReference, .applyAccessibleDocumentAssessment, .applySurveyDefinition, .applySurveySession, .applyAssetLocator, .applySchedule, .applyPlan, .applyPlacementPose, .applyEvidenceContext, .applyLighting, .applyLightingDayInventory, .applyLightingNightWorkflow, .applyTemporalEvidence, .applyAssetLabel, .applyOperationalContact, .applyPartyContactSiteRoleImport, .applyActivityContract, .applyPortableReview, .applyWorkResource, .applyPartsStock, .applyMyDay, .applyServiceRequest, .applyServiceReliability, .applyShopReportProfile, .applyRoundSession, .applyWorkspaceExperience:
                coverage = .exactDomainPostImages
            case .applyImportBulk, .applyEvidenceQuality:
                coverage = .identityAndRevisionOnly
            case .applyFastSurveyInbox, .applyReinspectionException:
                coverage = .identitySemanticAndRevision
            case .applyAssetPlacementChange, .applyLocationHierarchyChange:
                coverage = .nestedPlacementPoseOnly
            case .finalizeCheck, .finalizeCorrection, .transitionReportPDF, .recordWork:
                coverage = .incumbentImportedHistorySpecialization
            case .createFirstSign, .createCheckDraft, .acceptCheckEvidence, .updateSiteTimeZone, .deleteAsset, .deleteSite, .eraseWorkspace, .restoreWorkspace, .archiveEntities, .applyAssetCompositionChange, .applySavedSmartView, .applyRequirementAssurance, .applyPartyAccountability, .applyAssetSemantics, .applyAssistanceAcceptance, .applyEntityIdentityResolution:
                coverage = .notCoveredByAppendBlock
            }
            result.append(.init(entry: entry, coverage: coverage, supplementalCoverage: supplemental))
        }
        observations = result
    }
}


/// Requirement-assurance history follows incumbent immutable admission plus
/// separately authenticated terminal state. Historical digest inversion is not
/// an admission law. This value observes those distinctions; it admits no source.
struct TemporalNormalizationRequirementAssuranceHistoryV1: Sendable {
    enum ProvenanceLaw: Sendable {
        case localUser, localRecovery, importedHistory, semanticReversal
    }
    enum TerminalObservation: Sendable {
        // Foreign originals retain their references and commitments but cannot
        // supply the current workspace's receipt-backed terminal image.
        case foreignWorkspace
        case externalProjectionCommitment(MutationHistoryEntityRevisionV1,
                                latestLocalReceiptImage: MutationPostImageV1?)
        case localReceiptCommitment(MutationHistoryEntityRevisionV1, MutationPostImageV1)
        // These are unresolved observations, never absence/removal permission.
        case missingRevision
        case missingLocalReceiptImage(MutationHistoryEntityRevisionV1)
    }
    enum ReaderRequirement: Sendable {
        // Fixed exporter -> journal.exportSnapshot -> validateAll ->
        // validateTerminalRows, under the genuine retained source capability.
        // Plain DTO construction or this observation cannot satisfy it.
        case activeSchemaValidatedReader
        // validateAll() defaults activeRelease; a generic old-schema DTO or
        // manifest switch does not establish released terminal admission.
        case releasedSchemaValidatedReader(persistentSchemaVersion: Int)
    }
    struct Observation: Sendable {
        let entry: TemporalNormalizationHistoryObservationV1.Entry
        let mutation: RequirementAssuranceMutationV1
        let workflowIdentity: WorkspaceEntityIdentityV1
        let provenanceLaw: ProvenanceLaw
        let terminal: TerminalObservation
        // The complete original images stay in entry.receipt. No image is
        // selected and relabeled as equivalent to the assurance snapshot hash.
    }
    let snapshot: TemporalNormalizationCanonicalSnapshotV1
    let readerRequirement: ReaderRequirement
    let observations: [Observation]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        self.snapshot = snapshot
        if snapshot.source.persistentSchemaVersion == PersistentSchemaReleaseRegistryV1.activeRelease.versionIdentifier.major {
            readerRequirement = .activeSchemaValidatedReader
        } else {
            readerRequirement = .releasedSchemaValidatedReader(
                persistentSchemaVersion: snapshot.source.persistentSchemaVersion)
        }
        // Existing history constructor validated canonical raw bytes, complete
        // normalized history and source-specific reversal/receipt bindings.
        // Reuse the incumbent local-terminal selector; never plan new external
        // projections to make observed rows pass validation.
        let terminalImages = try MutationJournalStoreV1.receiptTerminalImages(
            in: history.history, workspaceID: snapshot.workspaceIdentity.workspaceID)
        let revisions = Dictionary(uniqueKeysWithValues:
            history.history.entityRevisions.map { ($0.identity, $0) })
        observations = try history.entries.compactMap { entry in
            guard case let .applyRequirementAssurance(mutation) = entry.envelope.command else {
                return nil
            }
            let identity = try WorkspaceEntityIdentityV1(kind: .workflowRecord,
                id: mutation.snapshot.workflowRecordID)
            let provenance: ProvenanceLaw
            switch entry.envelope.sourceKind {
            case .localUser: provenance = .localUser
            case .localRecovery: provenance = .localRecovery
            case .importedHistory: provenance = .importedHistory
            case .semanticReversal: provenance = .semanticReversal
            }
            let terminal: TerminalObservation
            if entry.receipt.identity.workspaceID != snapshot.workspaceIdentity.workspaceID {
                terminal = .foreignWorkspace
            } else if let row = revisions[identity] {
                if row.externalProjectionSHA256 != nil {
                    terminal = .externalProjectionCommitment(row,
                        latestLocalReceiptImage: terminalImages[identity])
                } else if let image = terminalImages[identity] {
                    terminal = .localReceiptCommitment(row, image)
                } else {
                    terminal = .missingLocalReceiptImage(row)
                }
            } else {
                terminal = .missingRevision
            }
            return Observation(entry: entry, mutation: mutation,
                workflowIdentity: identity, provenanceLaw: provenance, terminal: terminal)
        }
    }
}


/// Reconciles the persisted C12 graph and the exact C14 evaluation descriptor.
/// Opaque evaluator IDs are logical references, not guessed content locators.
struct TemporalNormalizationRequirementReferenceGraphV1: Sendable {
    typealias Input = TemporalNormalizationAssetPartyRequirementReferencesV1.Observation
    struct EvaluationKey: Hashable, Sendable {
        // Same closed UUID-or-opaque ID normalization as incumbent backup
        // review/work-packet reference validation; no substring matching.
        enum ReferenceID: Hashable, Sendable { case uuid(UUID), opaque(String) }
        let workspaceID: UUID
        let referenceID: ReferenceID
        let revision: UInt64
        let digest: String
        init(workspaceID: UUID, reference: ReviewEvidenceReferenceV1) throws {
            try reference.validate()
            guard reference.kind == .requirementEvaluation else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            self.workspaceID = workspaceID
            referenceID = UUID(uuidString: reference.referenceID).map(ReferenceID.uuid)
                ?? .opaque(reference.referenceID)
            revision = reference.revision; digest = reference.sha256
        }
        init(workspaceID: UUID, evaluation: RequirementEvaluationV1) throws {
            try self.init(workspaceID: workspaceID,
                reference: evaluation.inspectionReviewEvidenceReference())
        }
    }
    enum Origin: Sendable {
        case record(Input)
        case report(TemporalNormalizationReportSnapshotObservationV1)
    }
    struct Evaluation: Sendable {
        let owner: Origin
        let snapshot: RequirementAssuranceSnapshotV1
        let value: RequirementEvaluationV1
        // Keep these different closed domains separate. The engine's
        // missingEvidenceReferences contains kind IDs, not evidence IDs.
        let missingEvidenceKindIDs: [String]
        let logicalEvidenceIDs: [String]
        let invalidLogicalEvidenceIDs: [String]
        let waiverID: String?
    }
    struct SnapshotGraph: Sendable {
        let owner: Origin
        let value: RequirementAssuranceSnapshotV1
        let evaluations: [Evaluation]
        // Snapshot.validate recomputes the incumbent decision from exactly
        // these evaluations, including all requirement-ID lists and digests.
        let decision: CompletionDecisionV1
        // Diagnostic references may intentionally name orphan/invalid inputs.
        // Preserve the complete findings; absence is never no-reference proof.
        let findings: [IntegrityFindingV1]
    }
    let snapshots: [SnapshotGraph]
    private let evaluationIndex: TemporalNormalizationRequirementEvaluationLookupV1<Evaluation>

    init(requirements: TemporalNormalizationAssetPartyRequirementReferencesV1,
         reports: TemporalNormalizationReportRequirementObservationsV1? = nil) throws {
        struct SnapshotKey: Hashable {
            let workspace: UUID
            let workflow: UUID
            let revision: UInt64
        }
        var result: [SnapshotGraph] = []
        var snapshotsByIdentity: [SnapshotKey: RequirementAssuranceSnapshotV1] = [:]
        func retain(_ snapshot: RequirementAssuranceSnapshotV1, owner: Origin, workspace: UUID) throws {
            try snapshot.validate()
            guard snapshot.workspaceID == workspace else { throw TemporalEvidenceContractFailureV1.staleSource }
            let snapshotKey = SnapshotKey(workspace: workspace,
                workflow: snapshot.workflowRecordID, revision: snapshot.evaluatedRevision)
            guard snapshotsByIdentity[snapshotKey].map({ $0 == snapshot }) ?? true else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            snapshotsByIdentity[snapshotKey] = snapshot
            let evaluations = try snapshot.evaluations.map { value in
                let node = Evaluation(owner: owner, snapshot: snapshot, value: value,
                    missingEvidenceKindIDs: value.missingEvidenceReferences,
                    logicalEvidenceIDs: value.evidenceReferenceIDs,
                    invalidLogicalEvidenceIDs: value.invalidEvidenceReferences,
                    waiverID: value.waiverID)
                return node
            }
            result.append(.init(owner: owner, value: snapshot, evaluations: evaluations,
                decision: snapshot.decision, findings: snapshot.findings))
        }
        for owner in requirements.observations {
            guard case let .requirement(snapshot) = owner.value else { continue }
            let workspace: UUID
            switch owner.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID.rawValue
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID.rawValue
            }
            try retain(snapshot, owner: .record(owner), workspace: workspace)
        }
        for report in reports?.observations ?? [] {
            guard let assurance = report.assurance,
                  assurance.workspaceID == report.member.workspaceIdentity.workspaceID.rawValue else { continue }
            try retain(assurance, owner: .report(report.member), workspace: assurance.workspaceID)
        }
        snapshots = result
        evaluationIndex = try .init(sources: result.flatMap { graph in
            graph.evaluations.map { .init(workspaceID: graph.value.workspaceID, value: $0.value, origin: $0) }
        })
    }

    /// Returns EVERY genuine matching origin. Equal descriptors shared by
    /// several workflows/history entries never collapse their ownership.
    /// Empty means no exact source in this graph, not permission to remove.
    func resolve(workspaceID: UUID, reference: ReviewEvidenceReferenceV1) throws -> [Evaluation] {
        try evaluationIndex.resolve(workspaceID: workspaceID, reference: reference).map(\.origin)
    }
}


/// Pure value reconciliation, not a source or mutation capability. Generic
/// origins retain every actual observation; equal values never erase owners.
struct TemporalNormalizationMyDayPlanIndexV1<Origin: Sendable>: Sendable {
    struct Source: Sendable { let value: MyDayPlanV1; let origin: Origin }
    struct Identity: Hashable, Sendable { let workspace: WorkspaceID; let planID: UUID; let revision: UInt64 }
    struct Predecessor: Sendable { let source: Source; let targets: [Source] }
    let predecessors: [Predecessor]
    private let values: [Identity: [Source]]
    init(sources: [Source]) throws {
        var index: [Identity: [Source]] = [:]
        for source in sources {
            try source.value.validate()
            let key = Identity(workspace: source.value.key.workspaceID,
                planID: source.value.planID, revision: source.value.revision)
            guard index[key]?.first.map({ $0.value == source.value }) ?? true else {
                throw MyDayFailureV1.divergentMutation
            }
            index[key, default: []].append(source)
        }
        var edges: [Predecessor] = []
        for source in sources {
            let value = source.value
            if value.revision == 1 {
                try value.validate(predecessor: nil)
            } else {
                let key = Identity(workspace: value.key.workspaceID, planID: value.planID,
                    revision: value.revision - 1)
                let targets = index[key] ?? []
                if let prior = targets.first { try value.validate(predecessor: prior.value) }
                // Missing predecessors stay unresolved. Never substitute the
                // latest current plan or classify missing history as absent.
                edges.append(.init(source: source, targets: targets))
            }
        }
        values = index; predecessors = edges
    }
    func resolve(_ reference: MyDayPlanReferenceV1) throws -> [Source] {
        try reference.validate()
        let matches = values[.init(workspace: reference.key.workspaceID,
            planID: reference.planID, revision: reference.revision)] ?? []
        guard try matches.allSatisfy({ try MyDayPlanReferenceV1($0.value) == reference }) else {
            throw MyDayFailureV1.divergentMutation
        }
        return matches
    }
}

struct TemporalNormalizationMyDayReferenceGraphV1: Sendable {
    typealias Input = TemporalNormalizationOperationalGraphReferencesV1.Observation
    typealias Plans = TemporalNormalizationMyDayPlanIndexV1<Input>
    struct Carryover: Sendable {
        let owner: Input
        let receipt: MyDayCarryoverReceiptV1
        let source: [Plans.Source]
        let target: [Plans.Source]
        let actualCarryoverPlans: [Input]
    }
    struct Nonactive: Sendable { let owner: Input; let reference: MyDayPlanReferenceV1; let plans: [Plans.Source] }
    struct PlanningReferences: Sendable { let owner: Input; let value: MyDayCarryoverPlanV1; let source: [Plans.Source]; let expectedTarget: [Plans.Source]? }
    let plans: Plans
    let carryovers: [Carryover]
    let nonactive: [Nonactive]
    let planning: [PlanningReferences]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         operational: TemporalNormalizationOperationalGraphReferencesV1) throws {
        // Actual canonical records only; no invented record/manifest envelope.
        try C57MyDayBackupEnrollmentV1.validate(snapshot.records)
        func namespace(_ input: Input) -> WorkspaceID {
            switch input.origin {
            case let .canonical(source): return source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): return entry.envelope.workspaceID
            }
        }
        struct CarryoverKey: Hashable { let workspace: WorkspaceID; let digest: String }
        var sources: [Plans.Source] = []
        var carryoverPlans: [CarryoverKey: [(MyDayCarryoverPlanV1, Input)]] = [:]
        for input in operational.observations {
            switch input.value {
            case let .dayPlan(value):
                guard value.key.workspaceID == namespace(input) else { throw MyDayFailureV1.wrongWorkspace }
                sources.append(.init(value: value, origin: input))
            case let .dayCarryoverPlan(value):
                try value.validate()
                guard value.sourcePlan.key.workspaceID == namespace(input) else { throw MyDayFailureV1.wrongWorkspace }
                carryoverPlans[.init(workspace: namespace(input), digest: value.planSHA256), default: []].append((value, input))
            default: break
            }
        }
        let index = try Plans(sources: sources)
        var receipts: [Carryover] = [], inactive: [Nonactive] = []
        var planningEdges: [PlanningReferences] = []
        for input in operational.observations {
            switch input.value {
            case let .dayCarryover(value):
                try value.validate()
                guard value.sourcePlan.key.workspaceID == namespace(input) else { throw MyDayFailureV1.wrongWorkspace }
                let source = try index.resolve(value.sourcePlan), target = try index.resolve(value.targetPlan)
                let actual = carryoverPlans[.init(workspace: namespace(input), digest: value.carryoverPlanSHA256)] ?? []
                if let sourceValue = source.first?.value, let targetValue = target.first?.value {
                    for (plan, _) in actual {
                        try value.validate(plan: plan, source: sourceValue, target: targetValue)
                    }
                }
                // Canonical receipts require exact endpoints under C57. An
                // original carryover-plan body is checked when genuinely held;
                // its absence alone does not invalidate normalized history.
                receipts.append(.init(owner: input, receipt: value, source: source, target: target,
                    actualCarryoverPlans: actual.map { $0.1 }))
            case let .dayCarryoverPlan(value):
                planningEdges.append(.init(owner: input, value: value,
                    source: try index.resolve(value.sourcePlan),
                    expectedTarget: try value.expectedTargetPlan.map { try index.resolve($0) }))
            case let .dayNonactive(value):
                guard value.key.workspaceID == namespace(input) else { throw MyDayFailureV1.wrongWorkspace }
                inactive.append(.init(owner: input, reference: value, plans: try index.resolve(value)))
            default: break
            }
        }
        plans = index; carryovers = receipts; nonactive = inactive; planning = planningEdges
    }
}


/// This helper proves only exact canonical report bytes/DTO correspondence.
/// Calling it with arbitrary bytes cannot manufacture the owner-created member
/// observation required by the graph's production entry point.
enum TemporalNormalizationReportRequirementDecoderV1 {
    static func decode(report: V4BackupReportDTO, bytes: Data) throws -> RequirementAssuranceSnapshotV1? {
        guard CanonicalJSONV1.sha256(bytes) == report.snapshotSHA256 else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        let encoder = ReportSnapshotEncoderV1()
        if try encoder.completedActivityV2SnapshotIfPresent(bytes,
            declaredSchemaVersion: report.snapshotSchemaVersion) != nil {
            // The incumbent review/work-packet reference law contributes no
            // C12 evaluation from this distinct completed-activity family.
            return nil
        }
        let value = try encoder.decode(bytes)
        guard value.reportID == report.id, value.sourceRecordID == report.sourceRecordID,
              value.packetID == report.packetID, value.snapshotCreatedAt == report.createdAt else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        try value.requirementAssurance?.validate()
        return value.requirementAssurance
    }
}

/// Exhaustive member accounting for the exact observed canonical report set.
/// A missing or foreign embedded assurance remains explicit; neither means
/// unreferenced. Physical freshness and full report projection admission remain
/// with the actual retained reader/member owner and incumbent family validator.
struct TemporalNormalizationReportRequirementObservationsV1: Sendable {
    struct Observation: Sendable {
        let member: TemporalNormalizationReportSnapshotObservationV1
        let assurance: RequirementAssuranceSnapshotV1?
    }
    let observations: [Observation]
    let missingReports: [V4BackupReportDTO]
    let foreignAssurances: [Observation]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         members: [TemporalNormalizationReportSnapshotObservationV1]) throws {
        let recordsDigest = KernelCanonicalHashV1.sha256(snapshot.recordsData)
        guard Set(snapshot.records.reports.map(\.id)).count == snapshot.records.reports.count else {
            throw TemporalEvidenceContractFailureV1.staleSource
        }
        let reports = Dictionary(uniqueKeysWithValues: snapshot.records.reports.map { ($0.id, $0) })
        var values: [Observation] = [], foreign: [Observation] = []
        var observed = Set<UUID>()
        for member in members {
            guard member.source == snapshot.source,
                  member.workspaceIdentity == snapshot.workspaceIdentity,
                  member.generationID == snapshot.generationID,
                  member.revision == snapshot.revision,
                  member.recordsSHA256 == recordsDigest,
                  reports[member.report.id] == member.report,
                  Int64(exactly: member.bytes.count) == member.byteCount,
                  member.sha256 == member.report.snapshotSHA256,
                  CanonicalJSONV1.sha256(member.bytes) == member.sha256 else {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            let value = Observation(member: member, assurance: try TemporalNormalizationReportRequirementDecoderV1.decode(
                report: member.report, bytes: member.bytes))
            values.append(value); observed.insert(member.report.id)
            if let assurance = value.assurance,
               assurance.workspaceID != snapshot.workspaceIdentity.workspaceID.rawValue {
                foreign.append(value)
            }
        }
        observations = values; foreignAssurances = foreign
        missingReports = snapshot.records.reports.filter { !observed.contains($0.id) }
    }
}


/// Exact pure lookup used by the graph and value-level tests. An origin is
/// retained data only; this constructor cannot create member/source authority.
struct TemporalNormalizationRequirementEvaluationLookupV1<Origin: Sendable>: Sendable {
    struct Source: Sendable { let workspaceID: UUID; let value: RequirementEvaluationV1; let origin: Origin }
    private let index: [TemporalNormalizationRequirementReferenceGraphV1.EvaluationKey: [Source]]
    init(sources: [Source]) throws {
        var result: [TemporalNormalizationRequirementReferenceGraphV1.EvaluationKey: [Source]] = [:]
        for source in sources {
            let key = try TemporalNormalizationRequirementReferenceGraphV1.EvaluationKey(
                workspaceID: source.workspaceID, evaluation: source.value)
            result[key, default: []].append(source)
        }
        index = result
    }
    func resolve(workspaceID: UUID, reference: ReviewEvidenceReferenceV1) throws -> [Source] {
        index[try .init(workspaceID: workspaceID, reference: reference)] ?? []
    }
}


/// Report-byte descendants from the same owner-bound observations as C12.
/// The full incumbent report/legacy-package predicate runs first. These values
/// retain report provenance; no report ID or hash is a source capability.
struct TemporalNormalizationReportContentReferencesV1: Sendable {
    enum Body: Sendable {
        case legacy(ReportSnapshotV1)
        case completed(CompletedActivitySnapshotV2)
    }
    enum Binding: Sendable {
        case content(ContentReferenceV1)
        case locator(ContentLocatorV1)
        case legacyEvidence(EvidenceSnapshotV1)
        case output(OutputScopedContentReferenceV1, card: EvidenceDetailCardV1)
        case temporal(TemporalEvidenceReportLinkV1)
        case claim(ClaimEvidenceLinkV1)
        case review(ReviewEvidenceReferenceV1)
        case privacy(PrivacyTransformReportProjectionV1)
    }
    struct Observation: Sendable {
        let member: TemporalNormalizationReportSnapshotObservationV1
        let body: Body
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         members: TemporalNormalizationReportRequirementObservationsV1,
         photoHistory: CheckRunnerPhotoBackupHistoryV1,
         profileRegistry: WorkspacePackageLifecycleProfileRegistryV1) throws {
        guard members.missingReports.isEmpty else { throw TemporalEvidenceContractFailureV1.staleSource }
        var bytes: [String: Data] = [:]
        for observation in members.observations {
            let member = observation.member
            let name = "snapshots/\(member.report.id.uuidString.lowercased()).json"
            if let previous = bytes[name], previous != member.bytes {
                throw TemporalEvidenceContractFailureV1.staleSource
            }
            bytes[name] = member.bytes
        }
        try BackupPackageValidatorV1(profileRegistry: profileRegistry).validateTemporalReportSnapshots(
            records: snapshot.records, reportBytes: bytes, photoHistory: photoHistory)
        let temporal = try snapshot.records.validateC33TemporalEvidence()
        let clipsByID = Dictionary(uniqueKeysWithValues: temporal.clips.map { ($0.clipID, $0) })
        let anchorsByID = Dictionary(uniqueKeysWithValues: temporal.anchors.map { ($0.anchorID, $0) })
        var roots: [Observation] = [], refs: [Reference] = []
        for member in members.observations.map(\.member) {
            let encoder = ReportSnapshotEncoderV1()
            let body: Body
            if let completed = try encoder.completedActivityV2SnapshotIfPresent(member.bytes,
                declaredSchemaVersion: member.report.snapshotSchemaVersion) {
                body = .completed(completed)
            } else { body = .legacy(try encoder.decode(member.bytes)) }
            let owner = Observation(member: member, body: body)
            roots.append(owner)
            // Other frozen report fields retain logical lineage, counts,
            // display values and digest commitments in `body`. In particular,
            // field-reference/plan/survey/measurement projections are not their
            // source manifests; actual source content lives in the separately
            // inventoried canonical/history descriptors. Accountability text
            // and output-scope identifiers are not ContentIDs or managed paths.
            switch body {
            case let .completed(value):
                for card in value.payload.activity.evidenceCards {
                    for output in card.outputReferences {
                        refs.append(.init(owner: owner, binding: .output(output, card: card)))
                    }
                }
            case let .legacy(value):
                try C33TemporalEvidencePackageValidationV1.validateReportLinks(value,
                    sourceWorkspaceID: snapshot.workspaceIdentity.workspaceID.rawValue,
                    clipsByID: clipsByID, anchorsByID: anchorsByID)

                refs += value.evidence.map { .init(owner: owner, binding: .legacyEvidence($0)) }
                refs += (value.temporalEvidenceLinks ?? []).map { .init(owner: owner, binding: .temporal($0)) }
                if let privacy = value.privacyTransform {
                    refs.append(.init(owner: owner, binding: .privacy(privacy)))
                }
                if let authority = value.authorityCriterion {
                    try authority.validate()
                    for release in authority.aggregate.sourceReleases {
                        if let content = release.lawfulContentReference {
                            refs.append(.init(owner: owner, binding: .content(content)))
                        }
                        if let locator = release.contentLocator {
                            refs.append(.init(owner: owner, binding: .locator(locator)))
                        }
                    }
                }
                if let assurance = value.assurance {
                    try assurance.validate()
                    let preview = assurance.preview
                    // Excluded links still retain their real source bindings.
                    refs += (preview.includedLinks + preview.excludedLinks).map {
                        .init(owner: owner, binding: .claim($0))
                    }
                    if let manifest = assurance.manifest {
                        refs += (manifest.includedLinks + manifest.excludedLinks).map {
                            .init(owner: owner, binding: .claim($0))
                        }
                    }
                }
                if let review = value.inspectionReviewHistory {
                    for request in review.changeRequests {
                        refs += (request.resolution?.evidence ?? []).map {
                            .init(owner: owner, binding: .review($0))
                        }
                    }
                    for event in review.correctiveActions {
                        refs += event.closureEvidence.map { .init(owner: owner, binding: .review($0)) }
                    }
                }
            }
        }
        observations = roots; references = refs
    }
}
