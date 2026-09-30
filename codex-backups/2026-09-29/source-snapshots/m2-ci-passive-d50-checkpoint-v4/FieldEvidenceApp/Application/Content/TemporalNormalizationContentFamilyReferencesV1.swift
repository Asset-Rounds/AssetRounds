import Foundation

/// Shared codec-family traversal. Every root and extracted binding retains its
/// exact source observation. Logical references are not invented byte descriptors.
struct TemporalNormalizationSurveyLightingInboxReferencesV1: Sendable {
    enum Field: Sendable { case guidedSurveys, lighting, lightingDay, lightingNight, rounds, fastInbox }
    enum Origin: Sendable {
        case canonical(Field, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case surveySession(SurveySessionV1)
        case fact(FactCaptureV1)
        case provisional(ProvisionalSubjectV1)
        case promotion(SubjectPromotionReceiptV1)
        case publication(SurveyPublicationSnapshotV1)
        case surveyMutation(SurveySessionMutationV1)
        case surveyDefinition(SurveyDefinitionReleaseV1)
        case assistance(AssistanceAcceptanceRequestV1)
        case lightingSystem(LightingSystemV1)
        case lightingObservation(LightingObservationV1)
        case lightingIssue(LightingIssueV1)
        case measurementPlan(MeasurementPlanV1)
        case lightingClaim(LightingClaimStateV1)
        case lightingMutation(LightingWriteOperationV1)
        case day(LightingDayInventoryWorkflowV1)
        case dayMutation(LightingDayInventoryWriteOperationV1)
        case night(LightingNightWorkflowV1)
        case nightMutation(LightingNightWorkflowWriteOperationV1)
        case round(RoundSessionV1)
        case inbox(CaptureInboxItemV1)
        case inboxPromotion(CapturePromotionV1)
        case snippet(SnippetV1)
        case insertion(SnippetInsertionV1)
        case inboxSnapshot(FastSurveyInboxBackupSnapshotV1)
        case inboxMutation(FastSurveyInboxMutationCommandV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case content(ContentReferenceV1)
        case locator(ContentLocatorV1)
        case responseContent(ResponseContentReferenceIDV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) -> Observation {
            let root = Observation(origin: origin, value: value); roots.append(root); return root
        }
        func content(_ values: [ContentReferenceV1], _ owner: Observation) {
            for value in values { refs.append(.init(owner: owner, binding: .content(value))) }
        }
        func response(_ value: ResponseValueV1?, _ owner: Observation) {
            if case let .contentReference(reference)? = value {
                refs.append(.init(owner: owner, binding: .responseContent(reference)))
            }
        }
        func fact(_ value: FactCaptureV1, _ origin: Origin) {
            let root = retain(.fact(value), origin); content(value.evidence, root); response(value.value, root)
        }
        func publication(_ value: SurveyPublicationSnapshotV1, _ origin: Origin) {
            let root = retain(.publication(value), origin)
            for fact in value.facts { content(fact.evidence, root); response(fact.value, root) }
        }
        func issue(_ value: LightingIssueV1, _ origin: Origin) {
            content(value.resolutionEvidence, retain(.lightingIssue(value), origin))
        }
        func day(_ value: LightingDayInventoryWorkflowV1, _ origin: Origin) {
            let root = retain(.day(value), origin)
            for condition in value.conditionSnapshots { content(condition.contextualMedia, root) }
        }
        func night(_ value: LightingNightWorkflowV1, _ origin: Origin) {
            let root = retain(.night(value), origin)
            for delta in value.deltas { content(delta.comparableMedia, root) }
            for repair in value.repairs { content(repair.beforeEvidence, root); content(repair.afterEvidence, root) }
            for recheck in value.rechecks { content(recheck.evidence, root) }
            for reopen in value.reopens { content(reopen.evidence, root) }
        }
        func round(_ value: RoundSessionV1, _ origin: Origin) {
            let root = retain(.round(value), origin)
            for item in value.items { content(item.requirement.requiredContent, root) }
        }
        func inbox(_ value: CaptureInboxItemV1, _ origin: Origin) {
            content([value.content], retain(.inbox(value), origin))
        }
        func inboxPromotion(_ value: CapturePromotionV1, _ origin: Origin) {
            content([value.originalContent], retain(.inboxPromotion(value), origin))
        }
        func measurementAttachments(_ captures: [MeasurementCaptureV1],
                                    _ calibration: CalibrationStatusSnapshotV1,
                                    _ quality: [MeasurementQualityAssessmentV1], _ owner: Observation) {
            for capture in captures { content(capture.evidence, owner) }
            if let source = calibration.sourceReference { content([source], owner) }
            for assessment in quality { content(assessment.evidence, owner) }
        }
        func claimAdmission(_ value: LightingClaimAdmissionClosureV1, _ owner: Observation) {
            switch value {
            case .observed, .externallyAttested: break
            case let .measured(_, _, _, captures, _, _, calibration, quality),
                 let .derived(_, _, _, _, captures, _, _, calibration, quality):
                measurementAttachments(captures, calibration, quality, owner)
            case let .screened(_, _, _, captures, _, _, calibration, quality, _, _, authority, _, _, _):
                measurementAttachments(captures, calibration, quality, owner)
                if let source = authority.lawfulContentReference { content([source], owner) }
                if let locator = authority.contentLocator { refs.append(.init(owner: owner, binding: .locator(locator))) }
            }
        }
        func definition(_ value: SurveyDefinitionReleaseV1, _ origin: Origin) {
            let owner = retain(.surveyDefinition(value), origin)
            for reference in TemporalNormalizationSurveyDefinitionContentV1.references(in: value) {
                refs.append(.init(owner: owner, binding: .responseContent(reference)))
            }
        }
        func survey(_ mutation: SurveySessionMutationV1, _ origin: Origin) {
                _ = retain(.surveyMutation(mutation), origin)
                switch mutation.payload {
                case let .applySession(value, release, published):
                    definition(release, origin)
                    _ = retain(.surveySession(value), origin)
                    if let published { publication(published, origin) }
                case let .captureFact(value, session, release, predecessors):
                    definition(release, origin)
                    fact(value, origin); _ = retain(.surveySession(session), origin)
                    for prior in predecessors { fact(prior, origin) }
                case let .applyProvisionalSubject(value): _ = retain(.provisional(value), origin)
                case let .promoteSubject(value, receipt, _, predecessor):
                    _ = retain(.provisional(value), origin); _ = retain(.promotion(receipt), origin)
                    if let predecessor { _ = retain(.promotion(predecessor), origin) }
                case let .publish(session, published, release, captures):
                    definition(release, origin)
                    _ = retain(.surveySession(session), origin); publication(published, origin)
                    for capture in captures { fact(capture, origin) }
                }
        }
        _ = try SurveySessionBackupGraphClosureV1.projection(records: snapshot.records.guidedSurveys,
            surveyDefinitions: snapshot.records.surveyDefinitions,
            packageEvolution: snapshot.records.packageEvolution, history: snapshot.history,
            expectedWorkspaceID: snapshot.workspaceIdentity.workspaceID)
        for row in snapshot.records.guidedSurveys {
            let origin = Origin.canonical(.guidedSurveys, source: snapshot)
            switch row.kind {
            case .session: _ = retain(.surveySession(try SurveySessionCanonicalCodecV1.decode(SurveySessionV1.self, from: row.canonicalData)), origin)
            case .factCapture: fact(try SurveySessionCanonicalCodecV1.decode(FactCaptureV1.self, from: row.canonicalData), origin)
            case .provisionalSubject: _ = retain(.provisional(try SurveySessionCanonicalCodecV1.decode(ProvisionalSubjectV1.self, from: row.canonicalData)), origin)
            case .subjectPromotionReceipt: _ = retain(.promotion(try SurveySessionCanonicalCodecV1.decode(SubjectPromotionReceiptV1.self, from: row.canonicalData)), origin)
            case .publicationSnapshot: publication(try SurveySessionCanonicalCodecV1.decode(SurveyPublicationSnapshotV1.self, from: row.canonicalData), origin)
            }
        }
        try snapshot.records.validateC31LightingClosure()
        try snapshot.records.validateC17LightingDayInventoryClosure()
        try snapshot.records.validateC18LightingNightWorkflowClosure()
        let light = try LightingBackupRecordSetV1.decode(snapshot.records.lighting)
        let lightOrigin = Origin.canonical(.lighting, source: snapshot)
        for value in light.systems { _ = retain(.lightingSystem(value), lightOrigin) }
        for value in light.observations { _ = retain(.lightingObservation(value), lightOrigin) }
        for value in light.issues { issue(value, lightOrigin) }
        for value in light.plans { _ = retain(.measurementPlan(value), lightOrigin) }
        for value in light.claims { _ = retain(.lightingClaim(value), lightOrigin) }
        for value in try LightingDayInventoryBackupRecordSetV1.decode(snapshot.records.lightingDayInventoryWorkflows) {
            day(value, .canonical(.lightingDay, source: snapshot))
        }
        for value in try LightingNightWorkflowBackupRecordSetV1.decode(snapshot.records.lightingNightWorkflows) {
            night(value, .canonical(.lightingNight, source: snapshot))
        }
        try C05RoundSessionBackupEnrollmentV1.validate(snapshot.records)
        for value in snapshot.records.roundSessions { round(value, .canonical(.rounds, source: snapshot)) }
        if let value = snapshot.records.fastSurveyInbox {
            try value.validate()
            let origin = Origin.canonical(.fastInbox, source: snapshot)
            _ = retain(.inboxSnapshot(value), origin)
            for item in value.inboxItems { inbox(item, origin) }
            for promotion in value.promotions { inboxPromotion(promotion, origin) }
            for snippet in value.snippets { _ = retain(.snippet(snippet), origin) }
            for insertion in value.snippetInsertions { _ = retain(.insertion(insertion), origin) }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applySurveySession(mutation):
                try mutation.validate()
                _ = try SurveySessionMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                survey(mutation, origin)
            case let .applyAssistanceAcceptance(request):
                try request.validate()
                _ = try AssistanceAcceptanceReceiptV1(request: request, canonicalMutationReceipt: entry.receipt)
                let owner = retain(.assistance(request), origin)
                response(request.proposal.value, owner)
                switch request.targetMutation {
                case let .surveySession(mutation): survey(mutation, origin)
                }
            case let .applyLighting(operation):
                try operation.validate()
                _ = try LightingMutationReceiptV1(operation: operation, mutationReceipt: entry.receipt)
                let owner = retain(.lightingMutation(operation), origin)
                switch operation {
                case let .appendSystem(value, predecessor, _):
                    _ = retain(.lightingSystem(value), origin)
                    if let predecessor { _ = retain(.lightingSystem(predecessor), origin) }
                case let .appendObservation(value, predecessor, system):
                    _ = retain(.lightingObservation(value), origin); _ = retain(.lightingSystem(system), origin)
                    if let predecessor { _ = retain(.lightingObservation(predecessor), origin) }
                case let .appendIssue(value, predecessor, admission):
                    issue(value, origin); if let predecessor { issue(predecessor, origin) }
                    _ = retain(.lightingObservation(admission.observation), origin)
                case let .appendMeasurementPlan(value, predecessor, system):
                    _ = retain(.measurementPlan(value), origin); _ = retain(.lightingSystem(system), origin)
                    if let predecessor { _ = retain(.measurementPlan(predecessor), origin) }
                case let .appendClaim(value, predecessor, admission):
                    _ = retain(.lightingClaim(value), origin)
                    if let predecessor { _ = retain(.lightingClaim(predecessor), origin) }
                    claimAdmission(admission, owner)
                }
            case let .applyLightingDayInventory(operation):
                try operation.validate()
                _ = try LightingDayInventoryMutationReceiptV1(operation: operation, mutationReceipt: entry.receipt)
                _ = retain(.dayMutation(operation), origin)
                switch operation {
                case let .appendWorkflow(value, predecessor, admission):
                    day(value, origin); if let predecessor { day(predecessor, origin) }
                    if let readiness = admission.readiness {
                        let owner = retain(.dayMutation(operation), origin)
                        for requirement in readiness.contentRequirements { content([requirement.reference], owner) }
                    }
                }
            case let .applyLightingNightWorkflow(operation):
                try operation.validate()
                _ = try LightingNightWorkflowMutationReceiptV1(operation: operation, mutationReceipt: entry.receipt)
                _ = retain(.nightMutation(operation), origin)
                switch operation {
                case let .appendWorkflow(value, predecessor, admission):
                    night(value, origin); if let predecessor { night(predecessor, origin) }
                    day(admission.dayWorkflow, origin)
                    for nestedIssue in admission.issues { issue(nestedIssue, origin) }
                    for patrol in admission.patrolSessions { round(patrol, origin) }
                }
            case let .applyRoundSession(mutation):
                try mutation.validate()
                _ = try RoundSessionMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                round(mutation.session, origin)
            case let .applyFastSurveyInbox(command):
                try command.validate()
                _ = retain(.inboxMutation(command), origin)
                switch command.payload {
                case let .putInboxItem(value): inbox(value, origin)
                case let .promote(value, item): inboxPromotion(value, origin); inbox(item, origin)
                case let .putSnippet(value): _ = retain(.snippet(value), origin)
                case let .insertSnippet(value, snippet):
                    _ = retain(.insertion(value), origin); _ = retain(.snippet(snippet), origin)
                }
            default: break
            }
        }
        observations = roots; references = refs
    }
}


/// Output-bearing contracts retain their original reference type. A completed
/// file commitment is not a ContentReference and cannot prove the file's bytes.
struct TemporalNormalizationActivityLabelReliabilityReferencesV1: Sendable {
    enum Field: Sendable { case activityContracts, acceptedLabels, serviceReliability }
    enum Origin: Sendable {
        case canonical(Field, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case activity(ActivitySessionEnvelopeV2)
        case transition(ActivityStateTransitionV2)
        case task(InstallationTaskResultV1)
        case asBuilt(InstallationAsBuiltSnapshotV1)
        case punch(PunchReviewBasisSnapshotV1)
        case activityMutation(ActivityContractMutationV2)
        case label(AcceptedLabelGenerationSnapshotV1)
        case reliability(ServiceReliabilityMutationPayloadV1)
        case reliabilityReceipt(ServiceReliabilityMutationReceiptV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case content(ContentReferenceV1)
        case locator(ContentLocatorV1)
        case completedFile(ActivityCompletedFileReferenceV1)
        case compatibilitySnapshot(CompletedActivitySnapshotV2CompatibilityReferenceV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]

    /// Closed C53 content inventory. Intrinsic/current/history admission is
    /// performed by the incumbent canonical row and bundle/receipt validators.
    /// Each immutable impact contributes, regardless of projection or status.
    static func reliabilityContent(_ value: ServiceReliabilityMutationPayloadV1) -> [ContentReferenceV1] {
        switch value {
        case let .impact(value): return value.evidence
        case .incident, .cause, .remedy, .repair, .restoration, .exposure: return []
        }
    }

    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) -> Observation {
            let root = Observation(origin: origin, value: value); roots.append(root); return root
        }
        func activity(_ value: ActivitySessionEnvelopeV2, _ origin: Origin) {
            let root = retain(.activity(value), origin)
            if let file = value.completedFileReference { refs.append(.init(owner: root, binding: .completedFile(file))) }
            if let file = value.completedSnapshotReference { refs.append(.init(owner: root, binding: .compatibilitySnapshot(file))) }
        }
        func task(_ value: InstallationTaskResultV1, _ origin: Origin) {
            let root = retain(.task(value), origin)
            for content in value.evidenceReferences { refs.append(.init(owner: root, binding: .content(content))) }
        }
        func label(_ value: AcceptedLabelGenerationSnapshotV1, _ origin: Origin) {
            let root = retain(.label(value), origin)
            // historicCloneOrFork deliberately retains source publication
            // namespace. Never rewrite it to the containing snapshot workspace.
            for artifact in value.outputReceipt.publicationBinding.publishedArtifacts {
                refs.append(.init(owner: root, binding: .content(artifact.reference)))
                refs.append(.init(owner: root, binding: .locator(artifact.locator)))
            }
        }
        func reliability(_ value: ServiceReliabilityMutationPayloadV1, _ origin: Origin) {
            let root = retain(.reliability(value), origin)
            for content in Self.reliabilityContent(value) {
                refs.append(.init(owner: root, binding: .content(content)))
            }
        }
        let activities = try snapshot.records.validateC47ActivityContracts()
        let activityOrigin = Origin.canonical(.activityContracts, source: snapshot)
        for value in activities.envelopes { activity(value, activityOrigin) }
        for value in activities.transitions { _ = retain(.transition(value), activityOrigin) }
        for value in activities.taskResults { task(value, activityOrigin) }
        for value in activities.asBuilt { _ = retain(.asBuilt(value), activityOrigin) }
        for value in activities.punchBasis { _ = retain(.punch(value), activityOrigin) }
        for value in try snapshot.records.validateC45AcceptedLabelSnapshots() {
            label(value, .canonical(.acceptedLabels, source: snapshot))
        }
        let service = try C53ServiceReliabilityBackupEnrollmentV1.canonicalRows(
            from: snapshot.records, workspaceID: snapshot.workspaceIdentity.workspaceID.rawValue)
        let serviceOrigin = Origin.canonical(.serviceReliability, source: snapshot)
        for value in service.incidents { reliability(.incident(value), serviceOrigin) }
        for value in service.impactSegments { reliability(.impact(value), serviceOrigin) }
        for value in service.causeAssertions { reliability(.cause(value), serviceOrigin) }
        for value in service.remedyAssertions { reliability(.remedy(value), serviceOrigin) }
        for value in service.repairIntervals { reliability(.repair(value), serviceOrigin) }
        for value in service.restorationAssertions { reliability(.restoration(value), serviceOrigin) }
        for value in service.qualifiedExposures { reliability(.exposure(value), serviceOrigin) }
        for value in service.receipts { _ = retain(.reliabilityReceipt(value), serviceOrigin) }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyActivityContract(mutation):
                try mutation.validate()
                _ = try ActivityContractMutationReceiptV2(mutation: mutation, mutationReceipt: entry.receipt)
                let owner = retain(.activityMutation(mutation), origin)
                activity(mutation.successorEnvelope, origin)
                if let prior = mutation.predecessorEnvelope { activity(prior, origin) }
                if let value = mutation.transition { _ = retain(.transition(value), origin) }
                for value in mutation.installationTaskResults { task(value, origin) }
                if let value = mutation.installationAsBuiltSnapshot { _ = retain(.asBuilt(value), origin) }
                if let value = mutation.punchReviewBasisSnapshot { _ = retain(.punch(value), origin) }
                if let value = mutation.completedSnapshotReference {
                    refs.append(.init(owner: owner, binding: .compatibilitySnapshot(value)))
                }
            case let .applyAssetLabel(mutation):
                try mutation.validate()
                _ = try AssetLabelAcceptanceReceiptV1(mutation: mutation, canonicalMutationReceipt: entry.receipt)
                label(mutation.snapshot, origin)
            case let .applyServiceReliability(bundle):
                try bundle.validate()
                _ = try ServiceReliabilityMutationReceiptV1(bundle: bundle, mutationReceipt: entry.receipt)
                for value in bundle.payloads { reliability(value, origin) }
            default: break
            }
        }
        observations = roots; references = refs
    }
}


/// Draft payload bytes require their registered purpose codec; merely retaining
/// a checkpoint or terminal state is not a proof that its references are absent.
struct TemporalNormalizationDraftHistoryReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(TemporalNormalizationDraftRowsV1.Observation)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    struct Observation: Sendable {
        let origin: Origin
        let value: TemporalNormalizationDraftRowsV1.Value
    }
    enum Binding: Sendable {
        case content(ContentReferenceV1)
        case reservation(DraftContentReservationV1)
        case purposePayload(FieldDraftCheckpointV1)
        case commitPlan(DraftCommitPlanV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]
    // The complete command also retains reviewed-target/continuation identities
    // which are not represented by a fabricated content descriptor.
    let mutations: [TemporalNormalizationHistoryObservationV1.Entry]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = [], entries: [TemporalNormalizationHistoryObservationV1.Entry] = []
        func retain(_ value: TemporalNormalizationDraftRowsV1.Value, _ origin: Origin) {
            let owner = Observation(origin: origin, value: value); roots.append(owner)
            switch value {
            case let .checkpoint(value): refs.append(.init(owner: owner, binding: .purposePayload(value)))
            case let .stagingItem(value):
                if let reference = value.contentReference { refs.append(.init(owner: owner, binding: .content(reference))) }
            case let .contentReservation(value): refs.append(.init(owner: owner, binding: .reservation(value)))
            case let .commitSaga(value): refs.append(.init(owner: owner, binding: .commitPlan(value.plan)))
            case .commitReceipt, .discardReceipt: break
            }
        }
        for row in try TemporalNormalizationDraftRowsV1(snapshot: snapshot).observations {
            retain(row.value, .canonical(row))
        }
        for entry in history.entries {
            guard case let .applyFieldDraft(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try FieldDraftMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            entries.append(entry)
            let origin = Origin.immutableHistory(entry)
            switch mutation.postImage {
            case let .createCheckpoint(value), let .reviseCheckpoint(value): retain(.checkpoint(value), origin)
            case let .appendStagingItem(value), let .reviseStagingItem(value): retain(.stagingItem(value), origin)
            case let .appendCommitSaga(value), let .advanceCommitSaga(value): retain(.commitSaga(value), origin)
            case let .appendContentReservation(value), let .reviseContentReservation(value): retain(.contentReservation(value), origin)
            case let .applyCommitTerminal(value, _):
                retain(.commitSaga(value.retiredSaga), origin); retain(.checkpoint(value.committedCheckpoint), origin)
                retain(.commitReceipt(value.receipt), origin)
            case let .applyDiscardTerminal(value):
                retain(.checkpoint(value.discardedCheckpoint), origin); retain(.discardReceipt(value.receipt), origin)
            case let .resolveConflict(value):
                retain(.checkpoint(value.expectedCheckpoint), origin); retain(.checkpoint(value.successorCheckpoint), origin)
            case let .publishReadyStage(value):
                retain(.checkpoint(value.expectedCheckpoint), origin); retain(.stagingItem(value.readyItem), origin)
                retain(.checkpoint(value.successorCheckpoint), origin)
            }
        }
        observations = roots; references = refs; mutations = entries
    }
}

struct TemporalNormalizationShopProfileReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    struct Observation: Sendable { let origin: Origin; let profile: ShopReportProfileV1 }
    struct Reference: Sendable { let owner: Observation; let content: OutputScopedContentReferenceV1 }
    let observations: [Observation]
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        try C04ShopReportProfileBackupEnrollmentV1.validate(snapshot.records)
        var roots = snapshot.records.shopReportProfiles.map { Observation(origin: .canonical(source: snapshot), profile: $0) }
        for entry in history.entries {
            guard case let .applyShopReportProfile(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try ShopReportProfileMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            roots.append(.init(origin: .immutableHistory(entry), profile: mutation.profile))
        }
        observations = roots
        references = roots.compactMap { owner in owner.profile.brand.logo.map { .init(owner: owner, content: $0) } }
    }
}


/// Incumbent workflow files use DTO/command commitments, not C33 descriptors.
/// Retain their complete typed value and exact source before a physical owner
/// resolves original/thumbnail/snapshot/PDF bytes. No ID or path heuristic joins.
struct TemporalNormalizationWorkflowFileReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Binding: Sendable {
        case evidence(V4BackupEvidenceFileDTO)
        case report(V4BackupReportDTO)
        case acceptedEvidence(CheckEvidenceMutationV1)
        case finalization(FinalizationWriterAuthorityV1)
        case legacyFinalization(FinalizeCheckMutationV1)
        case legacyCorrection(FinalizeCorrectionMutationV1)
        case work(RecordWorkMutationV1)
        case reportTransition(ReportPDFTransitionMutationV1)
    }
    struct Reference: Sendable { let origin: Origin; let binding: Binding }
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var result: [Reference] = []
        let current = Origin.canonical(source: snapshot)
        for value in snapshot.records.evidenceFiles { result.append(.init(origin: current, binding: .evidence(value))) }
        for value in snapshot.records.reports { result.append(.init(origin: current, binding: .report(value))) }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .acceptCheckEvidence(value): result.append(.init(origin: origin, binding: .acceptedEvidence(value)))
            case let .finalizeCheck(value):
                if let authority = value.writerAuthority {
                    try authority.validate()
                    result.append(.init(origin: origin, binding: .finalization(authority)))
                } else {
                    // Frozen legacy commands may lawfully omit the later
                    // writer body. Preserve the actual commitment shape; never
                    // invent an unpersisted report body or content-ID mapping.
                    result.append(.init(origin: origin, binding: .legacyFinalization(value)))
                }
            case let .finalizeCorrection(value):
                if let authority = value.writerAuthority {
                    try authority.validate()
                    result.append(.init(origin: origin, binding: .finalization(authority)))
                } else { result.append(.init(origin: origin, binding: .legacyCorrection(value))) }
            case let .recordWork(value):
                try value.writerAuthority?.validate()
                result.append(.init(origin: origin, binding: .work(value)))
            case let .transitionReportPDF(value):
                try value.validate()
                result.append(.init(origin: origin, binding: .reportTransition(value)))
            default: break
            }
        }
        references = result
    }
}


/// Dispatches only exact registered release values, never text within payloads.
/// Decoded historical payloads remain observations; immutable source-chain and
/// physical scratch-owner admission are separate unresolved requirements.
struct TemporalNormalizationKnownDraftPayloadReferencesV1: Sendable {
    enum Payload: Sendable {
        case checkItem(CheckRunnerItemDraftPayloadV1)
        case checkPhoto(CheckRunnerPhotoDraftPayloadV1)
        case myDay(MyDayPlanningDraftPayloadV1)
        case repetitiveV1(RepetitiveCaptureDraftPayloadV1)
        case repetitiveV2(RepetitiveCaptureProgressDraftPayloadV2)
        case destinationReview(RepetitiveCaptureDestinationReviewPayloadV1)
        case unresolvedCodec(FieldDraftCheckpointV1)
    }
    struct Observation: Sendable {
        let owner: TemporalNormalizationDraftHistoryReferencesV1.Observation
        let payload: Payload
    }
    enum Binding: Sendable {
        case content(ContentReferenceV1)
        case photoRaw(CheckRunnerPhotoRawReadyV1)
        case photoPair(CheckRunnerPhotoNormalizedPairV1, workspace: WorkspaceID)
        case rawStage(CheckRunnerPhotoRawStageIntentV1)
        case myDayEligible(MyDayEligibleReferenceV1)
        case myDayPlan(MyDayPlanReferenceV1)
        case round(RoundSessionReferenceV1)
        case repetitiveCheckpoint(RepetitiveCaptureSourceCheckpointReferenceV1, workspace: WorkspaceID)
        case retainedSourceGraph(RepetitiveCaptureSourceGraphReferenceV2)
        case destinationPredecessor(RepetitiveCaptureReviewPredecessorV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]
    init(drafts: TemporalNormalizationDraftHistoryReferencesV1) throws {
        var roots: [Observation] = [], refs: [Reference] = []
        func content(_ values: [ContentReferenceV1], _ owner: Observation) {
            for value in values { refs.append(.init(owner: owner, binding: .content(value))) }
        }
        func round(_ value: RoundSessionV1, _ owner: Observation) {
            for item in value.items { content(item.requirement.requiredContent, owner) }
        }
        func source(_ value: CheckRunnerRoundItemSourceV1, _ owner: Observation) {
            content(value.originalItem.requirement.requiredContent, owner)
            content(value.itemAtEntry.requirement.requiredContent, owner)
        }
        for draft in drafts.observations {
            guard case let .checkpoint(checkpoint) = draft.value else { continue }
            let payload: Payload
            if checkpoint.codec == (try CheckRunnerItemDraftCodecV1.release()) {
                payload = .checkItem(try CheckRunnerItemDraftCodecV1.validateCheckpoint(checkpoint))
            } else if checkpoint.codec == (try CheckRunnerPhotoDraftCodecV1.release()) {
                payload = .checkPhoto(try CheckRunnerPhotoDraftCodecV1.validateCheckpoint(checkpoint))
            } else if checkpoint.codec == (try MyDayPlanningDraftCodecV1.release()) {
                payload = .myDay(try MyDayPlanningDraftCodecV1.validateCheckpointPayload(checkpoint))
            } else if checkpoint.codec == (try RepetitiveCaptureDraftCodecV1.release()) {
                guard checkpoint.purpose == .repetitiveCapture else { throw FieldDraftFailureV1.unknownPurpose }
                // The source/continuation reader requires actual predecessor
                // checkpoints. Its active-source predicate is not imposed on
                // every immutable historical envelope merely to decode bytes.
                payload = .repetitiveV1(try RepetitiveCaptureDraftCodecV1.decode(checkpoint.payloadData))
            } else if checkpoint.codec == (try RepetitiveCaptureProgressDraftCodecV2.release()) {
                guard checkpoint.purpose == .repetitiveCapture else { throw FieldDraftFailureV1.unknownPurpose }
                payload = .repetitiveV2(try RepetitiveCaptureProgressDraftCodecV2.decode(checkpoint.payloadData))
            } else if checkpoint.codec == (try RepetitiveCaptureDestinationReviewCodecV1.release()) {
                try RepetitiveCaptureDestinationReviewCodecV1.validateCheckpoint(checkpoint)
                payload = .destinationReview(try RepetitiveCaptureDestinationReviewCodecV1.decode(checkpoint.payloadData))
            } else { payload = .unresolvedCodec(checkpoint) }
            let owner = Observation(owner: draft, payload: payload); roots.append(owner)
            switch payload {
            case let .checkItem(value): source(value.source, owner)
            case let .checkPhoto(value):
                source(value.sourceBinding, owner)
                refs.append(.init(owner: owner, binding: .rawStage(value.phase.intent)))
                refs += try Self.photoDescendants(value).map { .init(owner: owner, binding: $0) }
            case let .repetitiveV2(value):
                switch value {
                case let .source(value): round(value.round, owner)
                case let .progress(value):
                    round(value.expectedRound, owner)
                    if let mutation = value.roundMutation { round(mutation.session, owner) }
                }
            case .myDay, .repetitiveV1, .destinationReview:
                refs += try Self.releasedPurposeDescendants(payload).map {
                    .init(owner: owner, binding: $0)
                }
            case .unresolvedCodec: break
            }
        }
        observations = roots; references = refs
    }

    /// READY_LOCAL intentionally has no ContentReference. The exact retained
    /// inspection/provenance supplies its raw content key, including after the
    /// live staging row advances. Never derive this key from a digest here.
    static func photoDescendants(_ value: CheckRunnerPhotoDraftPayloadV1) throws -> [Binding] {
        try value.validate()
        var result: [Binding] = []
        if let raw = value.phase.raw { result.append(.photoRaw(raw)) }
        if let pair = value.phase.pair {
            result.append(.photoPair(pair.normalizedPair, workspace: value.workspaceID))
        }
        return result
    }

    /// Pure affected-key comparison shared by the fixed classifier and its
    /// production-photo witness. Digest mismatch must never erase an owner.
    static func photoOwnsOriginal(_ binding: Binding, workspaceID: WorkspaceID,
                                  contentID: String) throws -> Bool {
        switch binding {
        case let .photoRaw(value):
            try value.validate()
            return value.readyItem.workspaceID == workspaceID && value.inspection.rawContentID == contentID
        case let .photoPair(value, workspace):
            try value.validate()
            let path = "content/\(workspaceID.rawValue.uuidString.lowercased())/\(contentID)/original.bin"
            return (workspace == workspaceID && value.sourceBinding.contentID == contentID) ||
                value.originalRelativePath == path || value.thumbnailRelativePath == path
        default: throw FieldDraftFailureV1.invalidValue
        }
    }

    /// Mechanical traversal of the actual released payload. An owner link is
    /// retained as its full typed descriptor; it is never promoted to content
    /// identity or satisfied by an ID-only match. All predecessor/eligible
    /// branches contribute, including unselected and historical values.
    static func releasedPurposeDescendants(_ payload: Payload) throws -> [Binding] {
        var result: [Binding] = []
        func plan(_ value: MyDayPlanV1) throws {
            try value.validate()
            result += value.items.map { .myDayEligible($0.reference) }
        }
        switch payload {
        case let .myDay(value):
            try value.validate()
            if let intent = value.editingIntent {
                switch intent {
                case let .plan(draft, predecessor):
                    result += draft.items.map { .myDayEligible($0.reference) }
                    result += draft.eligibleReferences.map(Binding.myDayEligible)
                    if let predecessor { try plan(predecessor) }
                case let .carryover(source, _, _, predecessor):
                    result.append(.myDayPlan(source))
                    if let predecessor { result.append(.myDayPlan(predecessor)) }
                }
            }
            if let attempt = value.commitAttempt {
                switch attempt.command {
                case let .save(successor, predecessor):
                    try plan(successor)
                    if let predecessor { try plan(predecessor) }
                case let .carryover(carryover, source, target, receipt):
                    try plan(source); try plan(target)
                    result += carryover.selectedSourceItems.map { .myDayEligible($0.reference) }
                    result.append(.myDayPlan(carryover.sourcePlan))
                    if let expected = carryover.expectedTargetPlan { result.append(.myDayPlan(expected)) }
                    result.append(.myDayPlan(receipt.sourcePlan))
                    result.append(.myDayPlan(receipt.targetPlan))
                }
            }
        case let .repetitiveV1(value):
            try value.validate()
            switch value {
            case let .source(_, round, _): result.append(.round(round))
            case let .continuation(source, request):
                result.append(.repetitiveCheckpoint(source, workspace: request.plan.workspaceID))
                if let round = request.plan.round { result.append(.round(round)) }
                for item in request.roundMutation.session.items {
                    result += item.requirement.requiredContent.map(Binding.content)
                }
                if let predecessor = request.roundMutation.session.predecessor {
                    result.append(.round(predecessor))
                }
            }
        case let .destinationReview(value):
            try value.validate()
            // The descriptor commits to retained original envelopes. It is not
            // a portable archive or a license to rebind the source namespace.
            result.append(.retainedSourceGraph(value.source))
            if let predecessor = value.provenance.immediatePredecessor {
                result.append(.destinationPredecessor(predecessor))
            }
        case .checkItem, .checkPhoto, .repetitiveV2, .unresolvedCodec:
            throw FieldDraftFailureV1.unknownCodec
        }
        return result
    }
}


/// Evidence identifiers/digests remain their actual typed semantic contracts.
/// In particular, excluded manifest links and waived assessments still count
/// as references; presentation and status never establish absence.
struct TemporalNormalizationEvidenceSemanticReferencesV1: Sendable {
    enum Field: Sendable { case contexts, pairs, assurance, quality }
    enum Origin: Sendable {
        case canonical(Field, source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case context(EvidenceContextV1)
        case pair(PairedObservationLinkV1)
        case visibility(EvidenceVisibilityV1)
        case link(ClaimEvidenceLinkV1)
        case manifest(AssuranceManifestV1)
        case attestation(AttestationV1)
        case assuranceMutation(EvidenceAssuranceMutationV1)
        case qualitySnapshot(EvidenceQualityBackupSnapshotV1)
        case qualityMutation(EvidenceQualityMutationCommandV1)
        case ruleSet(EvidenceQualityRuleSetV1)
        case assessment(EvidenceQualityAssessmentV1)
        case waiver(EvidenceQualityWaiverV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case evidenceContext(EvidenceContextV1)
        case pairedObservation(PairedObservationReferenceV1)
        case claimEvidence(ClaimEvidenceLinkV1)
        case evidenceQuality(EvidenceQualityEvidenceBindingV1)
        case attestationManifest(AttestationV1)
    }
    struct Reference: Sendable { let owner: Observation; let binding: Binding }
    let observations: [Observation]
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) -> Observation {
            let root = Observation(origin: origin, value: value); roots.append(root); return root
        }
        func context(_ value: EvidenceContextV1, _ origin: Origin) {
            refs.append(.init(owner: retain(.context(value), origin), binding: .evidenceContext(value)))
        }
        func pair(_ value: PairedObservationLinkV1, _ origin: Origin) {
            let owner = retain(.pair(value), origin)
            refs.append(.init(owner: owner, binding: .pairedObservation(value.first)))
            refs.append(.init(owner: owner, binding: .pairedObservation(value.second)))
        }
        func link(_ value: ClaimEvidenceLinkV1, _ origin: Origin) {
            refs.append(.init(owner: retain(.link(value), origin), binding: .claimEvidence(value)))
        }
        func manifest(_ value: AssuranceManifestV1, _ origin: Origin) {
            _ = retain(.manifest(value), origin)
            for value in value.includedLinks + value.excludedLinks { link(value, origin) }
        }
        func attestation(_ value: AttestationV1, _ origin: Origin) {
            refs.append(.init(owner: retain(.attestation(value), origin), binding: .attestationManifest(value)))
        }
        func assessment(_ value: EvidenceQualityAssessmentV1, _ origin: Origin) {
            let owner = retain(.assessment(value), origin)
            refs.append(.init(owner: owner, binding: .evidenceQuality(value.evidence)))
            for finding in value.orderedFindings {
                refs.append(.init(owner: owner, binding: .evidenceQuality(finding.input.subject)))
                if let comparison = finding.input.comparison {
                    refs.append(.init(owner: owner, binding: .evidenceQuality(comparison)))
                }
                // Keep the exact externally supplied referenceSequenceSHA256
                // in this finding. C10's constructor/coordinator defines a
                // semantic commitment, not a ContentReference or a mapping to
                // EvidenceSequenceV1. The separately stored subject/comparison
                // descriptors above own the actual capture bytes.
            }
        }
        func waiver(_ value: EvidenceQualityWaiverV1, _ origin: Origin) {
            refs.append(.init(owner: retain(.waiver(value), origin), binding: .evidenceQuality(value.evidence)))
        }
        try snapshot.records.validateC30EvidenceContextClosure()
        for (rows, field) in [(snapshot.records.evidenceContexts, Field.contexts), (snapshot.records.pairedObservationLinks, Field.pairs)] {
            let values = try EvidenceContextBackupRecordSetV1.decode(rows)
            let origin = Origin.canonical(field, source: snapshot)
            for value in values.contexts { context(value, origin) }
            for value in values.pairedObservationLinks { pair(value, origin) }
        }
        // Snapshot construction has already run exact canonical admission,
        // including every row's kind/UUID/workspace/revision binding.
        for row in snapshot.records.evidenceAssurance {
            let origin = Origin.canonical(.assurance, source: snapshot)
            switch row.kind {
            case .visibility: _ = retain(.visibility(try EvidenceAssuranceCanonicalCodecV1.decode(EvidenceVisibilityV1.self, from: row.canonicalData)), origin)
            case .evidenceLink: link(try EvidenceAssuranceCanonicalCodecV1.decode(ClaimEvidenceLinkV1.self, from: row.canonicalData), origin)
            case .manifest: manifest(try EvidenceAssuranceCanonicalCodecV1.decode(AssuranceManifestV1.self, from: row.canonicalData), origin)
            case .attestation: attestation(try EvidenceAssuranceCanonicalCodecV1.decode(AttestationV1.self, from: row.canonicalData), origin)
            }
        }
        if let quality = snapshot.records.evidenceQuality {
            try quality.validate()
            let origin = Origin.canonical(.quality, source: snapshot)
            _ = retain(.qualitySnapshot(quality), origin)
            for value in quality.ruleSets { _ = retain(.ruleSet(value), origin) }
            for value in quality.assessments { assessment(value, origin) }
            for value in quality.waivers { waiver(value, origin) }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyEvidenceContext(operation):
                try operation.validate()
                _ = try EvidenceContextMutationReceiptV1(operation: operation, mutationReceipt: entry.receipt)
                switch operation {
                case let .appendContext(value, prior): context(value, origin); if let prior { context(prior, origin) }
                case let .appendPair(value, prior): pair(value, origin); if let prior { pair(prior, origin) }
                }
            case let .applyEvidenceAssurance(mutation):
                try mutation.validate()
                _ = try EvidenceAssuranceMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                _ = retain(.assuranceMutation(mutation), origin)
                switch mutation.postImage {
                case let .appendVisibility(value), let .supersedeVisibility(value): _ = retain(.visibility(value), origin)
                case let .appendLink(value), let .supersedeLink(value): link(value, origin)
                case let .appendManifest(value, preview), let .supersedeManifest(value, preview):
                    manifest(value, origin)
                    for value in preview.includedLinks + preview.excludedLinks { link(value, origin) }
                case let .recordAttestation(value, basis), let .supersedeAttestation(value, basis), let .voidAttestation(value, basis):
                    attestation(value, origin); manifest(basis, origin)
                }
            case let .applyEvidenceQuality(command):
                try command.validate()
                _ = retain(.qualityMutation(command), origin)
                switch command.payload {
                case let .putRuleSet(value): _ = retain(.ruleSet(value), origin)
                case let .recordAssessment(value): assessment(value, origin)
                case let .recordWaiver(value): waiver(value, origin)
                }
            default: break
            }
        }
        observations = roots; references = refs
    }
}


/// A stored basis commits to an original plan; it does not contain that plan.
/// Executed compensation bodies are genuine journal commands and are linked
/// here without constructing a synthetic receipt or recovering JSON by search.
struct TemporalNormalizationReversalReferencesV1: Sendable {
    enum Resolution: Sendable {
        case observed(TemporalNormalizationHistoryObservationV1.Entry)
        case missingMutation(workspace: WorkspaceID, mutation: MutationIDV1)
        case missingReceipt(MutationReceiptIdentityV1)
    }
    struct Execution: Sendable {
        let owner: TemporalNormalizationHistoryObservationV1.Entry
        let receipt: SemanticReversalReceiptV1
        let target: Resolution
        let compensatingCommands: [Resolution]
    }
    struct PlanCommitment: Sendable {
        let owner: TemporalNormalizationHistoryObservationV1.Entry
        let basis: ReversalBasisV1
        // This is the complete persisted commitment shape. Restore law does
        // not require reconstruction of the original plan. Separately existing
        // live/portable plans belong to their actual owner inventory/drain;
        // a stored basis alone does not imply that such an owner exists.
    }
    let executions: [Execution]
    let planCommitments: [PlanCommitment]
    init(history: TemporalNormalizationHistoryObservationV1) throws {
        struct Key: Hashable { let workspace: WorkspaceID; let mutation: MutationIDV1 }
        var byMutation: [Key: TemporalNormalizationHistoryObservationV1.Entry] = [:]
        var byReceipt: [MutationReceiptIdentityV1: TemporalNormalizationHistoryObservationV1.Entry] = [:]
        for entry in history.entries {
            let key = Key(workspace: entry.envelope.workspaceID, mutation: entry.envelope.mutationID)
            guard byMutation.updateValue(entry, forKey: key) == nil,
                  byReceipt.updateValue(entry, forKey: entry.receipt.identity) == nil else {
                throw WorkspaceMutationFailureV1.receiptHistoryCorrupt
            }
        }
        var executions: [Execution] = [], commitments: [PlanCommitment] = []
        for entry in history.entries {
            if let basis = entry.reversalBasis { commitments.append(.init(owner: entry, basis: basis)) }
            guard let reversal = entry.semanticReversal else { continue }
            let target: Resolution = byReceipt[reversal.targetReceiptIdentity].map(Resolution.observed)
                ?? .missingReceipt(reversal.targetReceiptIdentity)
            let commands: [Resolution] = reversal.compensatingMutationIDs.map { mutation in
                let workspace = reversal.reversalReceiptIdentity.workspaceID
                return byMutation[.init(workspace: workspace, mutation: mutation)].map(Resolution.observed)
                    ?? .missingMutation(workspace: workspace, mutation: mutation)
            }
            // Full imported-history laws already authenticated source kind,
            // causation and reversal links. Resolution adds no admission law.
            executions.append(.init(owner: entry, receipt: reversal, target: target, compensatingCommands: commands))
        }
        self.executions = executions; planCommitments = commitments
    }
}


struct TemporalNormalizationReviewWorkReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case transition(InspectionReviewTransitionV1), disposition(ReviewDispositionV1)
        case request(ChangeRequestV1), policy(CorrectiveActionPolicyV1), event(CorrectiveActionEventV1)
        case manifest(WorkPacketManifestV1), claim(WorkItemClaimV1), lease(WorkLeaseV1)
        case release(WorkReleaseV1), handoff(WorkHandoffV1)
        case portable(PortableReviewMutationV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    struct Reference: Sendable { let owner: Observation; let evidence: ReviewEvidenceReferenceV1 }
    let observations: [Observation]
    let references: [Reference]
    init(snapshot: TemporalNormalizationCanonicalSnapshotV1,
         history: TemporalNormalizationHistoryObservationV1) throws {
        guard snapshot.history == history.history else { throw TemporalEvidenceContractFailureV1.staleSource }
        var roots: [Observation] = [], refs: [Reference] = []
        func retain(_ value: Value, _ origin: Origin) {
            let owner = Observation(origin: origin, value: value); roots.append(owner)
            let evidence: [ReviewEvidenceReferenceV1]
            switch value {
            case let .request(value): evidence = value.resolution?.evidence ?? []
            case let .event(value): evidence = value.closureEvidence
            case let .release(value): evidence = value.resultLinks.flatMap(\.evidence)
            case let .handoff(value): evidence = value.resultLinks.flatMap(\.evidence)
            case .transition, .disposition, .policy, .manifest, .claim, .lease, .portable: evidence = []
            }
            for reference in evidence { refs.append(.init(owner: owner, evidence: reference)) }
        }
        func review(_ mutation: InspectionReviewMutationV1, _ origin: Origin) throws {
            try mutation.validate()
            switch mutation.postImage {
            case let .applyReviewBundle(bundle):
                retain(.transition(bundle.transition), origin)
                if let value = bundle.disposition { retain(.disposition(value), origin) }
                for value in bundle.changeRequests { retain(.request(value), origin) }
            case let .appendCorrectivePolicy(value), let .supersedeCorrectivePolicy(value): retain(.policy(value), origin)
            case let .appendCorrectiveEvent(value), let .appendCorrectiveEventSuccessor(value): retain(.event(value), origin)
            }
        }
        let origin = Origin.canonical(source: snapshot)
        for row in snapshot.records.inspectionReview {
            switch row.kind {
            case .reviewTransition: retain(.transition(try InspectionReviewCanonicalCodecV1.decode(InspectionReviewTransitionV1.self, from: row.canonicalData)), origin)
            case .reviewDisposition: retain(.disposition(try InspectionReviewCanonicalCodecV1.decode(ReviewDispositionV1.self, from: row.canonicalData)), origin)
            case .changeRequest: retain(.request(try InspectionReviewCanonicalCodecV1.decode(ChangeRequestV1.self, from: row.canonicalData)), origin)
            case .correctiveActionPolicy: retain(.policy(try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionPolicyV1.self, from: row.canonicalData)), origin)
            case .correctiveActionEvent: retain(.event(try InspectionReviewCanonicalCodecV1.decode(CorrectiveActionEventV1.self, from: row.canonicalData)), origin)
            }
        }
        for row in snapshot.records.workPackets {
            switch row.kind {
            case .manifest: retain(.manifest(try WorkPacketCanonicalCodecV1.decode(WorkPacketManifestV1.self, from: row.canonicalData)), origin)
            case .claim: retain(.claim(try WorkPacketCanonicalCodecV1.decode(WorkItemClaimV1.self, from: row.canonicalData)), origin)
            case .lease: retain(.lease(try WorkPacketCanonicalCodecV1.decode(WorkLeaseV1.self, from: row.canonicalData)), origin)
            case .release: retain(.release(try WorkPacketCanonicalCodecV1.decode(WorkReleaseV1.self, from: row.canonicalData)), origin)
            case .handoff: retain(.handoff(try WorkPacketCanonicalCodecV1.decode(WorkHandoffV1.self, from: row.canonicalData)), origin)
            }
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applyInspectionReview(mutation):
                _ = try InspectionReviewMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                try review(mutation, origin)
            case let .applyPortableReview(mutation):
                try mutation.validate()
                _ = try PortableReviewMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                retain(.portable(mutation), origin)
                try review(mutation.inspectionReviewMutation, origin)
            case let .applyWorkPacket(mutation):
                try mutation.validate()
                _ = try WorkPacketMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                switch mutation.postImage {
                case let .appendManifest(value): retain(.manifest(value), origin)
                case let .appendClaim(value), let .supersedeClaim(value): retain(.claim(value), origin)
                case let .appendLease(value), let .supersedeLease(value): retain(.lease(value), origin)
                case let .recordRelease(value): retain(.release(value), origin)
                case let .recordHandoff(value): retain(.handoff(value), origin)
                }
            default: break
            }
        }
        observations = roots; references = refs
    }
}


/// Closed recursive schema traversal, bounded by the release's existing
/// expression-depth/node laws. Equality/default operands can be content IDs.
enum TemporalNormalizationSurveyDefinitionContentV1 {
    static func references(in value: SurveyDefinitionReleaseV1) -> [ResponseContentReferenceIDV1] {
        var result: [ResponseContentReferenceIDV1] = []
        func response(_ value: ResponseValueV1?) {
            if case let .contentReference(reference)? = value { result.append(reference) }
        }
        func expression(_ value: SurveyVisibilityExpressionV1) {
            switch value {
            case let .predicate(value): response(value.expectedValue)
            case let .all(values), let .any(values): for value in values { expression(value) }
            case let .not(value): expression(value)
            }
        }
        for section in value.sections {
            for fact in section.facts {
                response(fact.defaultValue)
                if let visibility = fact.visibility { expression(visibility) }
            }
        }
        func completionExpression(_ value: SurveyCompletionExpressionV1) {
            switch value {
            case .allRequiredVisibleFactsAnswered, .factPresent:
                // Completion leaves refer to fact IDs, never content IDs.
                // Content operands belong to defaults/visibility above.
                break
            case let .all(values), let .any(values):
                for value in values { completionExpression(value) }
            }
        }
        for rule in value.completionRules { completionExpression(rule.expression) }
        return result
    }
}

struct TemporalNormalizationDefinitionAccessibilityReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case definitionIdentity(SurveyDefinitionIdentityV1)
        case definitionRelease(SurveyDefinitionReleaseV1)
        case definitionMutation(SurveyDefinitionMutationV1)
        case acceptance(AssistanceAcceptanceReceiptV1)
        case accessibility(AccessibleDocumentAssessmentReceiptV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case responseContent(ResponseContentReferenceIDV1)
        case accessibleEvidence(AccessibleEvidenceLinkV1)
        case assessedOutput(AccessibleDocumentAssessmentReceiptV1)
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
        func release(_ value: SurveyDefinitionReleaseV1, _ origin: Origin) {
            let owner = retain(.definitionRelease(value), origin)
            for reference in TemporalNormalizationSurveyDefinitionContentV1.references(in: value) {
                refs.append(.init(owner: owner, binding: .responseContent(reference)))
            }
        }
        func accessibility(_ value: AccessibleDocumentAssessmentReceiptV1, _ origin: Origin) {
            let owner = retain(.accessibility(value), origin)
            refs.append(.init(owner: owner, binding: .assessedOutput(value)))
            for reference in value.externalProof { refs.append(.init(owner: owner, binding: .accessibleEvidence(reference))) }
        }
        let origin = Origin.canonical(source: snapshot)
        for row in snapshot.records.surveyDefinitions {
            switch row.kind {
            case .identity: _ = retain(.definitionIdentity(try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionIdentityV1.self, from: row.canonicalData)), origin)
            case .release: release(try SurveyDefinitionCanonicalCodecV1.decode(SurveyDefinitionReleaseV1.self, from: row.canonicalData), origin)
            }
        }
        for row in snapshot.records.assistanceAcceptanceReceipts {
            let value = try row.value(), owner = retain(.acceptance(value), origin)
            if case let .contentReference(reference) = value.acceptedValue { refs.append(.init(owner: owner, binding: .responseContent(reference))) }
        }
        for row in snapshot.records.accessibleDocumentAssessments {
            accessibility(try AccessibleDocumentCanonicalCodecV1.decode(AccessibleDocumentAssessmentReceiptV1.self, from: row.canonicalData), origin)
        }
        for entry in history.entries {
            let origin = Origin.immutableHistory(entry)
            switch entry.envelope.command {
            case let .applySurveyDefinition(mutation):
                try mutation.validate()
                _ = try SurveyDefinitionMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                _ = retain(.definitionMutation(mutation), origin)
                release(mutation.release, origin)
            case let .applyAccessibleDocumentAssessment(mutation):
                try mutation.validate()
                _ = try AccessibleDocumentMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
                accessibility(mutation.receipt, origin)
            default: break
            }
        }
        observations = roots; references = refs
    }
}


struct TemporalNormalizationServiceRequestReferencesV1: Sendable {
    enum Origin: Sendable {
        case canonical(source: TemporalNormalizationCanonicalSnapshotV1)
        case immutableHistory(TemporalNormalizationHistoryObservationV1.Entry)
    }
    enum Value: Sendable {
        case record(ServiceRequestRecordV1)
        case disposition(ServiceRequestDispositionEventV1)
        case workLink(ServiceRequestWorkLinkEventV1)
    }
    struct Observation: Sendable { let origin: Origin; let value: Value }
    enum Binding: Sendable {
        case media(ServiceRequestMediaEntryV1)
        case acceptedSource(CanonicalServiceRequestSourceBytesV1)
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
            if case let .record(record) = value {
                for entry in record.mediaManifest.entries { refs.append(.init(owner: owner, binding: .media(entry))) }
                if let source = record.acceptedSourceBytes { refs.append(.init(owner: owner, binding: .acceptedSource(source))) }
            }
        }
        let values = try C52ServiceRequestBackupEnrollmentV1.canonicalRows(
            from: snapshot.records, workspaceID: snapshot.workspaceIdentity.workspaceID.rawValue)
        let origin = Origin.canonical(source: snapshot)
        for value in values.records { retain(.record(value), origin) }
        for value in values.dispositions { retain(.disposition(value), origin) }
        for value in values.workLinks { retain(.workLink(value), origin) }
        for entry in history.entries {
            guard case let .applyServiceRequest(mutation) = entry.envelope.command else { continue }
            try mutation.validate()
            _ = try ServiceRequestMutationReceiptV1(mutation: mutation, mutationReceipt: entry.receipt)
            let origin = Origin.immutableHistory(entry)
            for payload in mutation.payloads {
                switch payload {
                case let .appendRecord(value): retain(.record(value), origin)
                case let .appendDisposition(value): retain(.disposition(value), origin)
                case let .appendWorkLink(value), let .appendWorkLinkReversal(value): retain(.workLink(value), origin)
                }
            }
        }
        observations = roots; references = refs
    }
}

/// Exact transitive assurance links. Opaque evidence strings remain opaque;
/// resolving them to bytes requires their genuine typed source owner.
struct TemporalNormalizationAssuranceGraphV1: Sendable {
    typealias Input = TemporalNormalizationEvidenceSemanticReferencesV1.Observation
    struct Visibility: Sendable {
        let value: EvidenceVisibilityV1
        let origins: [Input]
    }
    struct Link: Sendable {
        let value: ClaimEvidenceLinkV1
        let origins: [Input]
        let visibility: Visibility
    }
    struct Manifest: Sendable {
        let value: AssuranceManifestV1
        let origins: [Input]
        let included: [Link]
        let excluded: [Link]
        // Exact sourcePreviewID/SHA256 and snapshot digest remain in value.
        // A report's authenticated bytes must supply that preview separately.
    }
    struct Attestation: Sendable {
        let value: AttestationV1
        let origins: [Input]
        let manifest: Manifest
    }
    struct Namespace: Sendable {
        let workspaceID: WorkspaceID
        let visibilities: [Visibility]
        let links: [Link]
        let manifests: [Manifest]
        let attestations: [Attestation]
    }
    let namespaces: [Namespace]
    init(semantics: TemporalNormalizationEvidenceSemanticReferencesV1) throws {
        try self.init(sources: [semantics])
    }
    init(sources: [TemporalNormalizationEvidenceSemanticReferencesV1]) throws {
        struct Rows {
            var visibilities: [UUID: EvidenceVisibilityV1] = [:]
            var visibilityOrigins: [UUID: [Input]] = [:]
            var links: [UUID: ClaimEvidenceLinkV1] = [:]
            var linkOrigins: [UUID: [Input]] = [:]
            var manifests: [UUID: AssuranceManifestV1] = [:]
            var manifestOrigins: [UUID: [Input]] = [:]
            var attestations: [UUID: AttestationV1] = [:]
            var attestationOrigins: [UUID: [Input]] = [:]
        }
        var rows: [WorkspaceID: Rows] = [:]
        let failure = TemporalEvidenceContractFailureV1.staleSource
        func sourceNamespace(_ input: Input) -> WorkspaceID {
            switch input.origin {
            case let .canonical(_, source): return source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): return entry.envelope.workspaceID
            }
        }
        for input in sources.flatMap(\.observations) {
            let workspace = sourceNamespace(input)
            var values = rows[workspace] ?? Rows()
            switch input.value {
            case let .visibility(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.visibilities[value.visibilityID].map({ $0 == value }) ?? true else { throw failure }
                values.visibilities[value.visibilityID] = value
                values.visibilityOrigins[value.visibilityID, default: []].append(input)
            case let .link(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.links[value.linkID].map({ $0 == value }) ?? true else { throw failure }
                values.links[value.linkID] = value
                values.linkOrigins[value.linkID, default: []].append(input)
                // Embedded visibility is a genuine, digest-bound value. Retain
                // its containing observation; never fabricate a canonical row.
                let visibility = value.visibility
                guard visibility.workspaceID == workspace,
                      values.visibilities[visibility.visibilityID].map({ $0 == visibility }) ?? true else { throw failure }
                values.visibilities[visibility.visibilityID] = visibility
                values.visibilityOrigins[visibility.visibilityID, default: []].append(input)
            case let .manifest(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.manifests[value.manifestID].map({ $0 == value }) ?? true else { throw failure }
                values.manifests[value.manifestID] = value
                values.manifestOrigins[value.manifestID, default: []].append(input)
            case let .attestation(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.attestations[value.attestationID].map({ $0 == value }) ?? true else { throw failure }
                values.attestations[value.attestationID] = value
                values.attestationOrigins[value.attestationID, default: []].append(input)
            default: continue
            }
            rows[workspace] = values
        }
        var result: [Namespace] = []
        for workspace in rows.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard let values = rows[workspace] else { throw failure }
            try BackupPackageValidatorV1().validateTemporalNormalizationEvidenceAssuranceChains(
                visibilities: values.visibilities, links: values.links,
                manifests: values.manifests, attestations: values.attestations)
            var visibilityByID: [UUID: Visibility] = [:]
            for (id, value) in values.visibilities {
                guard let origins = values.visibilityOrigins[id], !origins.isEmpty else { throw failure }
                visibilityByID[id] = .init(value: value, origins: origins)
            }
            var linkByID: [UUID: Link] = [:]
            for (id, value) in values.links {
                guard let origins = values.linkOrigins[id], !origins.isEmpty,
                      let visibility = visibilityByID[value.visibilityID] else { throw failure }
                try value.validate(visibility: visibility.value)
                linkByID[id] = .init(value: value, origins: origins, visibility: visibility)
            }
            var manifestByID: [UUID: Manifest] = [:]
            func resolveLinks(_ links: [ClaimEvidenceLinkV1]) throws -> [Link] {
                try links.map { value in
                    guard let resolved = linkByID[value.linkID], resolved.value == value else { throw failure }
                    return resolved
                }
            }
            for (id, value) in values.manifests {
                guard let origins = values.manifestOrigins[id], !origins.isEmpty else { throw failure }
                manifestByID[id] = .init(value: value, origins: origins,
                    included: try resolveLinks(value.includedLinks), excluded: try resolveLinks(value.excludedLinks))
            }
            var attestations: [Attestation] = []
            for id in values.attestations.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let value = values.attestations[id],
                      let origins = values.attestationOrigins[id], !origins.isEmpty,
                      let manifest = manifestByID[value.manifestID] else { throw failure }
                try value.validate(manifest: manifest.value)
                attestations.append(.init(value: value, origins: origins, manifest: manifest))
            }
            result.append(.init(workspaceID: workspace,
                visibilities: visibilityByID.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { visibilityByID[$0] },
                links: linkByID.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { linkByID[$0] },
                manifests: manifestByID.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { manifestByID[$0] },
                attestations: attestations))
        }
        namespaces = result
    }
}

/// Resolves the genuine quality rule-set/assessment/waiver chain. This output
/// does not establish dual-receipt lifecycle coverage or content ownership.
struct TemporalNormalizationQualityReferenceGraphV1: Sendable {
    typealias Input = TemporalNormalizationEvidenceSemanticReferencesV1.Observation
    struct RuleSet: Sendable { let value: EvidenceQualityRuleSetV1; let origins: [Input]; let predecessorOrigins: [Input] }
    struct Assessment: Sendable { let value: EvidenceQualityAssessmentV1; let origins: [Input]; let ruleSet: RuleSet }
    struct Waiver: Sendable { let value: EvidenceQualityWaiverV1; let origins: [Input]; let assessment: Assessment; let predecessorOrigins: [Input] }
    struct Namespace: Sendable {
        let workspaceID: WorkspaceID
        let ruleSets: [RuleSet]
        let assessments: [Assessment]
        let waivers: [Waiver]
    }
    let namespaces: [Namespace]
    init(semantics: TemporalNormalizationEvidenceSemanticReferencesV1) throws {
        struct Rows {
            var ruleSets: [UUID: EvidenceQualityRuleSetV1] = [:]
            var ruleOrigins: [UUID: [Input]] = [:]
            var assessments: [UUID: EvidenceQualityAssessmentV1] = [:]
            var assessmentOrigins: [UUID: [Input]] = [:]
            var waivers: [UUID: EvidenceQualityWaiverV1] = [:]
            var waiverOrigins: [UUID: [Input]] = [:]
        }
        let failure = TemporalEvidenceContractFailureV1.staleSource
        var rows: [WorkspaceID: Rows] = [:]
        for input in semantics.observations {
            let workspace: WorkspaceID
            switch input.origin {
            case let .canonical(_, source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            var values = rows[workspace] ?? Rows()
            switch input.value {
            case let .ruleSet(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.ruleSets[value.ruleSetID].map({ $0 == value }) ?? true else { throw failure }
                values.ruleSets[value.ruleSetID] = value
                values.ruleOrigins[value.ruleSetID, default: []].append(input)
            case let .assessment(value):
                guard value.workspaceID == workspace,
                      values.assessments[value.assessmentID].map({ $0 == value }) ?? true else { throw failure }
                values.assessments[value.assessmentID] = value
                values.assessmentOrigins[value.assessmentID, default: []].append(input)
            case let .waiver(value):
                guard value.workspaceID == workspace,
                      values.waivers[value.waiverEventID].map({ $0 == value }) ?? true else { throw failure }
                values.waivers[value.waiverEventID] = value
                values.waiverOrigins[value.waiverEventID, default: []].append(input)
            default: continue
            }
            rows[workspace] = values
        }
        var result: [Namespace] = []
        for workspace in rows.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard let values = rows[workspace] else { throw failure }
            var rules: [UUID: RuleSet] = [:]
            for (id, value) in values.ruleSets {
                guard let origins = values.ruleOrigins[id], !origins.isEmpty else { throw failure }
                let predecessorOrigins: [Input]
                if let priorID = value.supersedesRuleSetID {
                    guard let prior = values.ruleSets[priorID], let priorOrigins = values.ruleOrigins[priorID], !priorOrigins.isEmpty else { throw failure }
                    try value.validateSuccessor(of: prior)
                    predecessorOrigins = priorOrigins
                } else { predecessorOrigins = [] }
                rules[id] = .init(value: value, origins: origins, predecessorOrigins: predecessorOrigins)
            }
            var assessments: [UUID: Assessment] = [:]
            for (id, value) in values.assessments {
                guard let origins = values.assessmentOrigins[id], !origins.isEmpty,
                      let rule = rules[value.ruleSetID] else { throw failure }
                try value.validate(ruleSet: rule.value)
                assessments[id] = .init(value: value, origins: origins, ruleSet: rule)
            }
            var waivers: [Waiver] = []
            for id in values.waivers.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let value = values.waivers[id], let origins = values.waiverOrigins[id], !origins.isEmpty,
                      let assessment = assessments[value.assessmentID] else { throw failure }
                try value.validate(assessment: assessment.value)
                let predecessorOrigins: [Input]
                if let priorID = value.supersedesWaiverEventID {
                    guard let prior = values.waivers[priorID], let priorOrigins = values.waiverOrigins[priorID], !priorOrigins.isEmpty else { throw failure }
                    try value.validateSuccessor(of: prior)
                    predecessorOrigins = priorOrigins
                } else { predecessorOrigins = [] }
                waivers.append(.init(value: value, origins: origins, assessment: assessment, predecessorOrigins: predecessorOrigins))
            }
            result.append(.init(workspaceID: workspace,
                ruleSets: rules.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { rules[$0] },
                assessments: assessments.keys.sorted(by: { $0.uuidString < $1.uuidString }).compactMap { assessments[$0] }, waivers: waivers))
        }
        namespaces = result
    }
}

/// Resolves review history with the incumbent complete five-family chain law.
/// Each evidence edge keeps its owner; unsupported target families stay explicit.
struct TemporalNormalizationReviewReferenceGraphV1: Sendable {
    typealias Input = TemporalNormalizationReviewWorkReferencesV1.Observation
    enum Key: Hashable, Sendable {
        case transition(UUID), disposition(UUID), request(UUID), policy(UUID), event(UUID)
    }
    struct RelationEdge: Sendable {
        let owner: Input
        let target: Key
        let targetOrigins: [Input]
    }
    struct Namespace: Sendable {
        let workspaceID: WorkspaceID
        let transitions: [UUID: InspectionReviewTransitionV1]
        let dispositions: [UUID: ReviewDispositionV1]
        let requests: [UUID: ChangeRequestV1]
        let policies: [UUID: CorrectiveActionPolicyV1]
        let actions: [UUID: CorrectiveActionEventV1]
        let origins: [Key: [Input]]
        let relations: [RelationEdge]
    }
    enum Target: Sendable {
        case assuranceLink(TemporalNormalizationAssuranceGraphV1.Link)
        case externalEvidence([TemporalNormalizationWorkflowFileReferencesV1.Reference])
        case requirementEvaluation([TemporalNormalizationRequirementReferenceGraphV1.Evaluation])
        case requiresTypedSource(ReviewEvidenceReferenceV1)
    }
    struct Edge: Sendable {
        let reference: TemporalNormalizationReviewWorkReferencesV1.Reference
        let target: Target
    }
    let namespaces: [Namespace]
    let evidence: [Edge]
    init(review: TemporalNormalizationReviewWorkReferencesV1,
         assurance: TemporalNormalizationAssuranceGraphV1,
         workflowFiles: TemporalNormalizationWorkflowFileReferencesV1,
         requirements: TemporalNormalizationRequirementReferenceGraphV1) throws {
        struct Rows {
            var transitions: [UUID: InspectionReviewTransitionV1] = [:]
            var dispositions: [UUID: ReviewDispositionV1] = [:]
            var requests: [UUID: ChangeRequestV1] = [:]
            var policies: [UUID: CorrectiveActionPolicyV1] = [:]
            var actions: [UUID: CorrectiveActionEventV1] = [:]
            var origins: [Key: [Input]] = [:]
        }
        func namespace(_ input: Input) -> WorkspaceID {
            switch input.origin {
            case let .canonical(source): return source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): return entry.envelope.workspaceID
            }
        }
        let failure = TemporalEvidenceContractFailureV1.staleSource
        var rows: [WorkspaceID: Rows] = [:]
        for input in review.observations {
            let workspace = namespace(input)
            var values = rows[workspace] ?? Rows()
            let key: Key
            switch input.value {
            case let .transition(value):
                guard value.workspaceID == workspace,
                      values.transitions[value.transitionID].map({ $0 == value }) ?? true else { throw failure }
                values.transitions[value.transitionID] = value; key = .transition(value.transitionID)
            case let .disposition(value):
                guard value.workspaceID == workspace,
                      values.dispositions[value.dispositionID].map({ $0 == value }) ?? true else { throw failure }
                values.dispositions[value.dispositionID] = value; key = .disposition(value.dispositionID)
            case let .request(value):
                guard value.workspaceID == workspace,
                      values.requests[value.requestRevisionID].map({ $0 == value }) ?? true else { throw failure }
                values.requests[value.requestRevisionID] = value; key = .request(value.requestRevisionID)
            case let .policy(value):
                guard value.workspaceID == workspace,
                      values.policies[value.releaseID].map({ $0 == value }) ?? true else { throw failure }
                values.policies[value.releaseID] = value; key = .policy(value.releaseID)
            case let .event(value):
                guard value.workspaceID == workspace,
                      values.actions[value.eventID].map({ $0 == value }) ?? true else { throw failure }
                values.actions[value.eventID] = value; key = .event(value.eventID)
            default: continue
            }
            values.origins[key, default: []].append(input)
            rows[workspace] = values
        }
        var result: [Namespace] = []
        for workspace in rows.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard let values = rows[workspace] else { throw failure }
            try BackupPackageValidatorV1().validateTemporalNormalizationInspectionReviewChains(
                transitions: values.transitions, dispositions: values.dispositions,
                requests: values.requests, policies: values.policies, actions: values.actions)
            let validator = BackupPackageValidatorV1()
            let requestsByStableID = Dictionary(grouping: values.requests.values, by: \.requestID)
            guard values.transitions.values.allSatisfy({ validator.temporalNormalizationReviewTransitionRelationsMatch(
                $0, dispositions: values.dispositions, requestsByStableID: requestsByStableID) }),
                values.dispositions.values.allSatisfy({ validator.temporalNormalizationReviewDispositionRelationsMatch(
                    $0, transitions: values.transitions, requestsByStableID: requestsByStableID) }),
                values.requests.values.allSatisfy({ validator.temporalNormalizationReviewRequestRelationsMatch(
                    $0, transitions: values.transitions) }),
                values.actions.values.allSatisfy({ validator.temporalNormalizationReviewActionPolicyRelationsMatch(
                    $0, policies: values.policies) }) else { throw failure }
            struct ReviewRevision: Hashable { let id: UUID; let revision: UInt64; let mutation: MutationIDV1 }
            struct RequestRevision: Hashable { let request: UUID; let review: ReviewRevision }
            let transitionsByRevision = Dictionary(grouping: values.transitions.values) {
                ReviewRevision(id: $0.reviewID, revision: $0.revision, mutation: $0.mutationID)
            }
            let requestsByRevision = Dictionary(grouping: values.requests.values) {
                RequestRevision(request: $0.requestID,
                    review: .init(id: $0.reviewID, revision: $0.reviewRevision, mutation: $0.mutationID))
            }
            var relations: [RelationEdge] = []
            func edge(_ owner: Input, _ target: Key) throws {
                guard let origins = values.origins[target], !origins.isEmpty else { throw failure }
                relations.append(.init(owner: owner, target: target, targetOrigins: origins))
            }
            // Index once by exact review+revision+mutation. Preserve all source
            // observations; do not rescan a growing result per predecessor.
            for inputs in values.origins.values {
                for input in inputs {
                    switch input.value {
                    case let .transition(value):
                        if let id = value.predecessorTransitionID { try edge(input, .transition(id)) }
                        if let id = value.dispositionID { try edge(input, .disposition(id)) }
                        for id in value.changeRequestIDs {
                            let key = RequestRevision(request: id,
                                review: .init(id: value.reviewID, revision: value.revision, mutation: value.mutationID))
                            guard let targets = requestsByRevision[key], targets.count == 1 else { throw failure }
                            for target in targets { try edge(input, .request(target.requestRevisionID)) }
                        }
                    case let .disposition(value):
                        if let id = value.supersedesDispositionID { try edge(input, .disposition(id)) }
                        let review = ReviewRevision(id: value.reviewID, revision: value.reviewRevision, mutation: value.mutationID)
                        guard let targets = transitionsByRevision[review] else { throw failure }
                        for target in targets where target.dispositionID == value.dispositionID { try edge(input, .transition(target.transitionID)) }
                        for id in value.changeRequestIDs {
                            guard let targets = requestsByRevision[.init(request: id, review: review)] else { throw failure }
                            for target in targets { try edge(input, .request(target.requestRevisionID)) }
                        }
                    case let .request(value):
                        if let id = value.supersedesRequestRevisionID { try edge(input, .request(id)) }
                        let key = ReviewRevision(id: value.reviewID, revision: value.reviewRevision, mutation: value.mutationID)
                        guard let targets = transitionsByRevision[key] else { throw failure }
                        for target in targets where target.changeRequestIDs.contains(value.requestID) { try edge(input, .transition(target.transitionID)) }
                    case let .policy(value):
                        if let id = value.supersedesReleaseID { try edge(input, .policy(id)) }
                    case let .event(value):
                        try edge(input, .policy(value.policy.releaseID))
                        if let id = value.predecessorEventID { try edge(input, .event(id)) }
                    default: break
                    }
                }
            }
            result.append(.init(workspaceID: workspace, transitions: values.transitions,
                dispositions: values.dispositions, requests: values.requests,
                policies: values.policies, actions: values.actions, origins: values.origins, relations: relations))
        }
        var links: [WorkspaceID: [UUID: TemporalNormalizationAssuranceGraphV1.Link]] = [:]
        for source in assurance.namespaces {
            guard links[source.workspaceID] == nil else { throw failure }
            var entries: [UUID: TemporalNormalizationAssuranceGraphV1.Link] = [:]
            for link in source.links {
                guard entries.updateValue(link, forKey: link.value.linkID) == nil else { throw failure }
            }
            links[source.workspaceID] = entries
        }
        struct EvidenceKey: Hashable { let workspace: WorkspaceID; let id: UUID }
        struct EvidenceBytes: Equatable {
            let recordID: UUID; let purpose: String; let path: String; let mime: String
            let count: Int; let digest: String; let createdAt: Date
            let thumbnailPath: String; let thumbnailCount: Int; let thumbnailDigest: String
        }
        var bytesByEvidence: [EvidenceKey: EvidenceBytes] = [:]
        var evidenceOrigins: [EvidenceKey: [TemporalNormalizationWorkflowFileReferencesV1.Reference]] = [:]
        for reference in workflowFiles.references {
            let workspace: WorkspaceID
            switch reference.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            let id: UUID
            let bytes: EvidenceBytes
            switch reference.binding {
            case let .evidence(value):
                id = value.id
                bytes = .init(recordID: value.recordID, purpose: value.purposeKey,
                    path: value.relativePath, mime: value.mimeType, count: value.byteCount,
                    digest: value.sha256, createdAt: value.createdAt,
                    thumbnailPath: value.thumbnailRelativePath, thumbnailCount: value.thumbnailByteCount,
                    thumbnailDigest: value.thumbnailSHA256)
            case let .acceptedEvidence(value):
                id = value.evidenceID
                bytes = .init(recordID: value.draftID, purpose: value.purposeKey,
                    path: value.relativePath, mime: value.mimeType, count: value.byteCount,
                    digest: value.sha256, createdAt: value.createdAt,
                    thumbnailPath: value.thumbnailRelativePath, thumbnailCount: value.thumbnailByteCount,
                    thumbnailDigest: value.thumbnailSHA256)
            case let .work(command):
                guard let authority = command.writerAuthority, let value = authority.evidenceInsert else { continue }
                try authority.validate(command: .recordWork(command))
                id = value.id
                bytes = .init(recordID: value.recordID, purpose: value.purposeKey,
                    path: value.relativePath, mime: value.mimeType, count: value.byteCount,
                    digest: value.sha256, createdAt: value.createdAt,
                    thumbnailPath: value.thumbnailRelativePath, thumbnailCount: value.thumbnailByteCount,
                    thumbnailDigest: value.thumbnailSHA256)
            default: continue
            }
            let key = EvidenceKey(workspace: workspace, id: id)
            guard bytesByEvidence[key].map({ $0 == bytes }) ?? true else { throw failure }
            bytesByEvidence[key] = bytes
            evidenceOrigins[key, default: []].append(reference)
        }
        var edges: [Edge] = []
        for reference in review.references {
            try reference.evidence.validate()
            let target: Target
            switch reference.evidence.kind {
            case .claimEvidenceLink:
                guard let id = UUID(uuidString: reference.evidence.referenceID),
                      let link = links[namespace(reference.owner)]?[id],
                      link.value.revision == reference.evidence.revision,
                      link.value.linkSHA256 == reference.evidence.sha256 else { throw failure }
                target = .assuranceLink(link)
            case .externalEvidenceReference:
                guard let id = UUID(uuidString: reference.evidence.referenceID) else { throw failure }
                let key = EvidenceKey(workspace: namespace(reference.owner), id: id)
                if let bytes = bytesByEvidence[key] {
                    guard reference.evidence.revision == 1,
                          reference.evidence.sha256 == bytes.digest,
                          let origins = evidenceOrigins[key], !origins.isEmpty else { throw failure }
                    target = .externalEvidence(origins)
                } else { target = .requiresTypedSource(reference.evidence) }
            case .requirementEvaluation:
                let sources = try requirements.resolve(workspaceID: namespace(reference.owner).rawValue,
                    reference: reference.evidence)
                target = sources.isEmpty ? .requiresTypedSource(reference.evidence)
                    : .requirementEvaluation(sources)
            case .verifiedRecheck, .completedActivitySnapshot,
                 .functionalRelationshipSnapshot:
                target = .requiresTypedSource(reference.evidence)
            }
            edges.append(.init(reference: reference, target: target))
        }
        namespaces = result; evidence = edges
    }
}

/// Typed work relations retain every observation, including obsolete leases.
/// Shared incumbent topology and predecessor laws validate the complete input.
/// Actor/packet admission and evidence endpoints remain separate. UI projection
/// output is discarded and is never used for reference reachability.
struct TemporalNormalizationWorkPacketReferenceGraphV1: Sendable {
    typealias Input = TemporalNormalizationReviewWorkReferencesV1.Observation
    enum Key: Hashable, Sendable { case manifest(UUID), claim(UUID), lease(UUID), release(UUID), handoff(UUID) }
    struct Edge: Sendable { let owner: Input; let target: Key; let targetOrigins: [Input] }
    struct Namespace: Sendable { let workspaceID: WorkspaceID; let origins: [Key: [Input]]; let edges: [Edge] }
    let namespaces: [Namespace]
    init(review: TemporalNormalizationReviewWorkReferencesV1) throws {
        struct Rows {
            var manifests: [UUID: WorkPacketManifestV1] = [:]
            var claims: [UUID: WorkItemClaimV1] = [:]
            var leases: [UUID: WorkLeaseV1] = [:]
            var releases: [UUID: WorkReleaseV1] = [:]
            var handoffs: [UUID: WorkHandoffV1] = [:]
            var origins: [Key: [Input]] = [:]
            var inputs: [Input] = []
        }
        let failure = TemporalEvidenceContractFailureV1.staleSource
        var rows: [WorkspaceID: Rows] = [:]
        for input in review.observations {
            let workspace: WorkspaceID
            switch input.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            var values = rows[workspace] ?? Rows()
            let key: Key
            switch input.value {
            case let .manifest(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.manifests[value.manifestID].map({ $0 == value }) ?? true else { throw failure }
                values.manifests[value.manifestID] = value; key = .manifest(value.manifestID)
            case let .claim(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.claims[value.claimID].map({ $0 == value }) ?? true else { throw failure }
                values.claims[value.claimID] = value; key = .claim(value.claimID)
            case let .lease(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.leases[value.leaseID].map({ $0 == value }) ?? true else { throw failure }
                values.leases[value.leaseID] = value; key = .lease(value.leaseID)
            case let .release(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.releases[value.releaseID].map({ $0 == value }) ?? true else { throw failure }
                values.releases[value.releaseID] = value; key = .release(value.releaseID)
            case let .handoff(value):
                try value.validate()
                guard value.workspaceID == workspace,
                      values.handoffs[value.handoffID].map({ $0 == value }) ?? true else { throw failure }
                values.handoffs[value.handoffID] = value; key = .handoff(value.handoffID)
            default: continue
            }
            values.origins[key, default: []].append(input); values.inputs.append(input)
            rows[workspace] = values
        }
        var result: [Namespace] = []
        for workspace in rows.keys.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            guard let values = rows[workspace] else { throw failure }
            let validator = BackupPackageValidatorV1()
            try validator.validateTemporalNormalizationWorkPacketTopology(manifests: values.manifests,
                claims: values.claims, leases: values.leases)
            var edges: [Edge] = []
            func edge(_ owner: Input, _ target: Key) throws {
                guard let origins = values.origins[target], !origins.isEmpty else { throw failure }
                edges.append(.init(owner: owner, target: target, targetOrigins: origins))
            }
            for input in values.inputs {
                switch input.value {
                case let .claim(value):
                    try validator.validateTemporalNormalizationWorkPacketClaim(value,
                        manifests: values.manifests, claims: values.claims)
                    guard let manifest = values.manifests[value.manifest.manifestID] else { throw failure }
                    try edge(input, .manifest(manifest.manifestID))
                    if let id = value.supersedesClaimID {
                        try edge(input, .claim(id))
                    }
                case let .lease(value):
                    try validator.validateTemporalNormalizationWorkPacketLease(value,
                        claims: values.claims, leases: values.leases)
                    guard let claim = values.claims[value.claimID] else { throw failure }
                    try edge(input, .claim(claim.claimID))
                    if let id = value.supersedesLeaseID {
                        try edge(input, .lease(id))
                    }
                case let .release(value):
                    guard let claim = values.claims[value.claimID], let lease = values.leases[value.leaseID],
                          let manifest = values.manifests[claim.manifest.manifestID] else { throw failure }
                    try value.validate(claim: claim, lease: lease, manifest: manifest)
                    try edge(input, .claim(claim.claimID)); try edge(input, .lease(lease.leaseID))
                    try edge(input, .manifest(manifest.manifestID))
                case let .handoff(value):
                    guard let release = values.releases[value.releaseID] else { throw failure }
                    try value.validate(release: release); try edge(input, .release(release.releaseID))
                default: break
                }
            }
            // Same incumbent structural validation; discard its UI projection.
            // Every unfiltered original and reference edge above remains retained.
            try validator.validateTemporalNormalizationWorkPacketProjection(workspaceID: workspace,
                manifests: values.manifests, claims: values.claims, leases: values.leases,
                releases: values.releases, handoffs: values.handoffs)
            result.append(.init(workspaceID: workspace, origins: values.origins, edges: edges))
        }
        namespaces = result
    }
}

/// Resolves embedded review/work actors against genuine party observations.
/// Every canonical generation and immutable entry remains attached to its row.
/// Missing observations stay explicit and confer no graph-completion authority.
struct TemporalNormalizationReviewWorkActorGraphV1: Sendable {
    typealias Input = TemporalNormalizationReviewWorkReferencesV1.Observation
    typealias PartyInput = TemporalNormalizationAssetPartyRequirementReferencesV1.Observation
    enum Role: Sendable { case actor, reviewer, requester, resolver, recorder, verifier, creator, holder, fromHolder, toHolder }
    enum PartyResolution: Sendable {
        case observed(partyID: UUID, origins: [PartyInput])
        case missing(partyID: UUID)
    }
    enum Resolution: Sendable {
        case observed(origins: [PartyInput])
        case missingActor
    }
    struct ActorEdge: Sendable {
        let owner: Input
        let role: Role
        let value: ActorSnapshotV1
        let resolution: Resolution
        let party: PartyResolution?
    }
    struct AssigneeEdge: Sendable {
        let owner: Input
        let resolution: PartyResolution
    }
    let actors: [ActorEdge]
    let assignees: [AssigneeEdge]
    init(review: TemporalNormalizationReviewWorkReferencesV1,
         parties: TemporalNormalizationAssetPartyRequirementReferencesV1) throws {
        struct Key: Hashable { let workspace: WorkspaceID; let id: UUID }
        struct PartyRevision: Hashable { let identity: Key; let revision: UInt64 }
        struct ActorRow { let value: ActorSnapshotV1; var origins: [PartyInput] }
        var actorRows: [Key: ActorRow] = [:]
        var partyRows: [Key: [PartyInput]] = [:]
        var partyRevisions: [PartyRevision: ServicePartyReferenceV1] = [:]
        let failure = TemporalEvidenceContractFailureV1.staleSource
        for input in parties.observations {
            let workspace: WorkspaceID
            switch input.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            switch input.value {
            case let .actor(value):
                try value.validate()
                guard value.workspaceID == workspace else { throw failure }
                let key = Key(workspace: workspace, id: value.snapshotID)
                if var prior = actorRows[key] {
                    guard prior.value == value else { throw failure }
                    prior.origins.append(input); actorRows[key] = prior
                } else { actorRows[key] = .init(value: value, origins: [input]) }
            case let .party(value):
                try value.validate()
                guard value.workspaceID == workspace else { throw failure }
                let key = Key(workspace: workspace, id: value.partyID)
                let revision = PartyRevision(identity: key, revision: value.revision)
                guard partyRevisions[revision].map({ $0 == value }) ?? true else { throw failure }
                partyRevisions[revision] = value; partyRows[key, default: []].append(input)
            default: break
            }
        }
        func party(_ id: UUID, _ workspace: WorkspaceID) -> PartyResolution {
            if let origins = partyRows[.init(workspace: workspace, id: id)] {
                return .observed(partyID: id, origins: origins)
            }
            return .missing(partyID: id)
        }
        var actorEdges: [ActorEdge] = [], assigneeEdges: [AssigneeEdge] = []
        for input in review.observations {
            let workspace: WorkspaceID
            switch input.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            func actor(_ value: ActorSnapshotV1, _ role: Role) throws {
                try value.validate()
                guard value.workspaceID == workspace else { throw failure }
                let resolution: Resolution
                if let row = actorRows[.init(workspace: workspace, id: value.snapshotID)] {
                    guard row.value == value else { throw failure }
                    resolution = .observed(origins: row.origins)
                } else { resolution = .missingActor }
                actorEdges.append(.init(owner: input, role: role, value: value, resolution: resolution,
                    party: value.actor.partyID.map { party($0, workspace) }))
            }
            switch input.value {
            case let .transition(value): try actor(value.actor, .actor)
            case let .disposition(value): try actor(value.reviewer, .reviewer)
            case let .request(value):
                try actor(value.requester, .requester)
                if let resolution = value.resolution { try actor(resolution.resolver, .resolver) }
            case let .event(value):
                try actor(value.recorder, .recorder)
                if let verifier = value.verifier { try actor(verifier, .verifier) }
                if let id = value.assignee?.partyID {
                    assigneeEdges.append(.init(owner: input, resolution: party(id, workspace)))
                }
            case let .manifest(value): try actor(value.creator, .creator)
            case let .claim(value): try actor(value.holder, .holder)
            case let .lease(value): try actor(value.holder, .holder)
            case let .release(value): try actor(value.holder, .holder)
            case let .handoff(value):
                try actor(value.fromHolder, .fromHolder); try actor(value.toHolder, .toHolder)
            case .policy, .portable: break
            }
        }
        actors = actorEdges; assignees = assigneeEdges
    }
}

/// Closed review subject/item codecs resolve to typed retained domain values.
/// Report-derived subjects require genuine snapshot bytes and remain explicit.
struct TemporalNormalizationReviewSubjectGraphV1: Sendable {
    typealias Input = TemporalNormalizationReviewWorkReferencesV1.Observation
    typealias AuthorityInput = TemporalNormalizationAuthorityMeasurementReferencesV1.Observation
    typealias FunctionalInput = TemporalNormalizationAssetPartyRequirementReferencesV1.Observation
    enum Endpoint: Sendable {
        case subject(InspectionReviewSubjectReferenceV1)
        case item(ChangeRequestItemReferenceV1)
        case assuranceManifest(id: UUID, revision: UInt64?, digest: String?)
    }
    enum Target: Sendable {
        case classification([AuthorityInput])
        case functionalRelationship([FunctionalInput])
        case review([Input])
        case evidence(TemporalNormalizationAssuranceGraphV1.Link)
        case manifest(TemporalNormalizationAssuranceGraphV1.Manifest)
        case requiresTypedSource
    }
    struct Edge: Sendable { let owner: Input; let endpoint: Endpoint; let target: Target }
    let edges: [Edge]
    init(review: TemporalNormalizationReviewWorkReferencesV1,
         authority: TemporalNormalizationAuthorityMeasurementReferencesV1,
         functional: TemporalNormalizationAssetPartyRequirementReferencesV1,
         assurance: TemporalNormalizationAssuranceGraphV1) throws {
        // Same closed ID normalization as incumbent package reference law,
        // expressed as typed alternatives rather than concatenated strings.
        enum ReferenceID: Hashable {
            case uuid(UUID), opaque(String)
            init(_ value: String) { self = UUID(uuidString: value).map(Self.uuid) ?? .opaque(value) }
        }
        struct Key: Hashable { let workspace: WorkspaceID; let id: ReferenceID; let revision: UInt64; let digest: String }
        struct Identity: Hashable { let workspace: WorkspaceID; let id: UUID }
        var findings: [Key: [AuthorityInput]] = [:], criteria: [Key: [AuthorityInput]] = [:]
        for input in authority.observations {
            guard case let .findingClassificationBinding(value) = input.value else { continue }
            let workspace: WorkspaceID
            switch input.origin {
            case let .authorityRow(_, source), let .measurementRow(_, source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            guard value.workspaceID == workspace else { throw TemporalEvidenceContractFailureV1.staleSource }
            findings[.init(workspace: workspace, id: .uuid(value.findingID), revision: value.revision, digest: value.bindingSHA256), default: []].append(input)
            criteria[.init(workspace: workspace, id: .init(value.criterionID), revision: value.revision, digest: value.bindingSHA256), default: []].append(input)
        }
        var functions: [Key: [FunctionalInput]] = [:]
        var functionValues: [Identity: AssetFunctionalRelationshipEventV1] = [:]
        for input in functional.observations {
            guard case let .functionalEvent(value) = input.value else { continue }
            let workspace: WorkspaceID
            switch input.origin {
            case let .canonical(source): workspace = source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): workspace = entry.envelope.workspaceID
            }
            try value.validate()
            let identity = Identity(workspace: workspace, id: value.eventID)
            guard value.workspaceID == workspace,
                  functionValues[identity].map({ $0 == value }) ?? true else { throw TemporalEvidenceContractFailureV1.staleSource }
            functionValues[identity] = value
            for id in Set([value.relationshipID, value.eventID]) {
                functions[.init(workspace: workspace, id: .uuid(id), revision: value.revision, digest: value.eventSHA256), default: []].append(input)
            }
        }
        var reviews: [Key: [Input]] = [:]
        func workspace(_ input: Input) -> WorkspaceID {
            switch input.origin {
            case let .canonical(source): return source.workspaceIdentity.workspaceID
            case let .immutableHistory(entry): return entry.envelope.workspaceID
            }
        }
        for input in review.observations {
            if case let .transition(value) = input.value {
                reviews[.init(workspace: workspace(input), id: .uuid(value.reviewID), revision: value.revision, digest: value.transitionSHA256), default: []].append(input)
            }
        }
        var links: [Key: TemporalNormalizationAssuranceGraphV1.Link] = [:]
        var manifests: [Key: TemporalNormalizationAssuranceGraphV1.Manifest] = [:]
        for namespace in assurance.namespaces {
            for link in namespace.links {
                links[.init(workspace: namespace.workspaceID, id: .uuid(link.value.linkID), revision: link.value.revision, digest: link.value.linkSHA256)] = link
            }
            for manifest in namespace.manifests {
                manifests[.init(workspace: namespace.workspaceID, id: .uuid(manifest.value.manifestID), revision: manifest.value.revision, digest: manifest.value.manifestSHA256)] = manifest
            }
        }
        var result: [Edge] = []
        for input in review.observations {
            let namespace = workspace(input)
            func subject(_ value: InspectionReviewSubjectReferenceV1) {
                let key = Key(workspace: namespace, id: .init(value.subjectID), revision: value.subjectRevision, digest: value.subjectSHA256)
                let target: Target
                switch value.kind {
                case .finding: target = findings[key].map(Target.classification) ?? .requiresTypedSource
                case .completedActivitySnapshot, .reportSnapshot: target = .requiresTypedSource
                }
                result.append(.init(owner: input, endpoint: .subject(value), target: target))
            }
            func item(_ value: ChangeRequestItemReferenceV1) {
                let key = Key(workspace: namespace, id: .init(value.itemID), revision: value.itemRevision, digest: value.itemSHA256)
                let target: Target
                switch value.kind {
                case .review: target = reviews[key].map(Target.review) ?? .requiresTypedSource
                case .finding: target = findings[key].map(Target.classification) ?? .requiresTypedSource
                case .criterion: target = criteria[key].map(Target.classification) ?? .requiresTypedSource
                case .evidence: target = links[key].map(Target.evidence) ?? .requiresTypedSource
                case .functionalRelationship: target = functions[key].map(Target.functionalRelationship) ?? .requiresTypedSource
                }
                result.append(.init(owner: input, endpoint: .item(value), target: target))
            }
            switch input.value {
            case let .transition(value):
                subject(value.subject)
                if let successor = value.successorSubject { subject(successor) }
            case let .disposition(value):
                subject(value.subject)
                if let id = value.assuranceManifestID {
                    let target: Target
                    if let revision = value.assuranceManifestRevision, let digest = value.assuranceManifestSHA256 {
                        target = manifests[.init(workspace: namespace, id: .uuid(id), revision: revision, digest: digest)].map(Target.manifest) ?? .requiresTypedSource
                    } else { target = .requiresTypedSource }
                    result.append(.init(owner: input,
                        endpoint: .assuranceManifest(id: id, revision: value.assuranceManifestRevision, digest: value.assuranceManifestSHA256), target: target))
                }
            case let .request(value): item(value.item)
            case let .event(value): item(value.source)
            default: break
            }
        }
        edges = result
    }
}


/// One operation-local index over genuine retained round bodies. Returned
/// positions identify every original observation; they confer no authority and
/// never coalesce away canonical/history/generation provenance.
struct TemporalNormalizationRoundReferenceIndexV1: Sendable {
    private struct Identity: Hashable, Sendable {
        let workspaceID: WorkspaceID
        let sessionID: UUID
        let revision: UInt64
    }
    private let positions: [RoundSessionReferenceV1: [Int]]
    init(rounds: [RoundSessionV1]) throws {
        var values: [Identity: RoundSessionV1] = [:]
        var positions: [RoundSessionReferenceV1: [Int]] = [:]
        for (offset, value) in rounds.enumerated() {
            try value.validateIntrinsic()
            let key = Identity(workspaceID: value.workspaceID, sessionID: value.sessionID, revision: value.revision)
            if let prior = values[key], prior != value { throw TemporalEvidenceContractFailureV1.staleSource }
            values[key] = value
            positions[try value.reference, default: []].append(offset)
        }
        self.positions = positions
    }
    func matchingPositions(_ reference: RoundSessionReferenceV1) throws -> [Int] {
        try reference.validate()
        return positions[reference] ?? []
    }
}
